//// The `evaluator` module is the core module of the GSH REPL.
////
//// Because Gleam is statically typed and compiled, we cannot evaluate raw AST 
//// dynamically like Elixir's IEx. Instead, this module acts as a synthetic runtime, 
//// taking the user's input, injecting historical state (imports, bindings, types, functions), 
//// and generating a unique `gsh_eval_X.gleam` file for execution.
////
//// **Key Capabilities:**
//// * **Token Routing:** Uses `glexer` to parse input and accurately classify the statement 
////   (import, type, function, binding, or raw expression).
//// * **Side-Effect Caching:** Wraps every variable assignment in an Erlang Process Dictionary 
////   check, ensuring side effects (like `io.println`) execute exactly once per session even 
////   as the file is continually recompiled.
//// * **Cache Collision Prevention:** Appends the `prompt_count` to module names to 
////   guarantee the Erlang VM loads fresh bytecode from disk on every execution.

// src/gsh/evaluator/evaluator.gleam

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gsh/evaluator/binding.{type Binding, Binding, Let, LetAssert}
import gsh/evaluator/parser
import gsh/evaluator/result.{type Evaluation, CompileError, Evaluation, NoError}
import gsh/evaluator/runner
import gsh/evaluator/source
import gsh/runtime/runtime
import simplifile

/// The primary orchestration engine for REPL input execution.
/// 
/// **Execution Pipeline:**
/// 1. **Lexical Analysis:** Scans the raw string to intercept syntax errors (e.g., open strings) 
///    and strips whitespace/comments to correctly route the syntax tree.
/// 2. **Code Generation:** Passes the tokens to the appropriate source builder and recursively 
///    injects the historical `ShellState` variables to maintain lexical scope.
/// 3. **Compilation:** Writes the generated code to a unique file in `test/` and triggers 
///    the `runner` for background compilation and VM execution.
/// 4. **Cleanup & State:** Deletes the temporary file, calculates execution latency for debug 
///    logs, and returns the extracted definitions so the REPL can update its active state.
pub fn evaluate(
  input: String,
  bindings: List(Binding),
  imports: List(String),
  types: List(String),
  functions: List(String),
  debug: Bool,
  prompt_count: Int,
) -> Evaluation {
  let module_name = "gsh_eval_" <> int.to_string(prompt_count)
  let evaluator_path = "test/" <> module_name <> ".gleam"
  let input = string.trim(input)

  case parser.parse(input) {
    parser.ClassifyIncomplete -> {
      Evaluation(
        output: "error: Syntax error\n  Incomplete input (missing closing delimiter).\n",
        success: False,
        error_kind: CompileError,
        new_binding: None,
        new_import: None,
        new_type: None,
        new_function: None,
      )
    }
    parser.ClassifyError(msg) -> {
      Evaluation(
        output: "error: " <> msg <> "\n",
        success: False,
        error_kind: CompileError,
        new_binding: None,
        new_import: None,
        new_type: None,
        new_function: None,
      )
    }
    parser.ClassifyEmpty | parser.Items([]) -> {
      Evaluation("", True, NoError, None, None, None, None)
    }
    parser.Items([item, ..]) -> {
      // Map the AST item back to your existing boolean flags and records
      let #(
        is_import,
        is_type,
        is_function,
        _is_binding,
        parsed_binding,
        parsed_def_name,
      ) = case item {
        parser.ImportItem(_, _) -> #(True, False, False, False, None, None)
        parser.DefinitionItem(name, parser.TypeDef, _) -> #(
          False,
          True,
          False,
          False,
          None,
          Some(name),
        )
        parser.DefinitionItem(name, parser.FnDef, _) -> #(
          False,
          False,
          True,
          False,
          None,
          Some(name),
        )
        parser.DefinitionItem(name, parser.ConstDef, _) -> #(
          False,
          False,
          False,
          False,
          None,
          Some(name),
        )
        parser.ValueItem(names, _, is_assert) -> {
          case names {
            [] -> #(False, False, False, False, None, None)
            // Raw expression
            _ -> {
              let kind = case is_assert {
                True -> LetAssert
                False -> Let
              }
              // Construct the old Binding record so your code generators don't break
              let b =
                Binding(
                  kind: kind,
                  source: input,
                  pattern: "",
                  // Not needed for generation
                  names: names,
                  value: "",
                  // Not needed for generation
                )
              #(False, False, False, True, Some(b), None)
            }
          }
        }
      }

      // 4. Generate the source
      let source = case is_import {
        True -> make_import_source(input, bindings, imports, types, functions)
        False ->
          case is_type {
            True -> make_type_source(input, bindings, imports, types, functions)
            False ->
              case is_function {
                True ->
                  make_function_source(
                    input,
                    bindings,
                    imports,
                    types,
                    functions,
                  )
                False ->
                  case parsed_binding {
                    Some(binding) ->
                      make_binding_source(
                        binding,
                        bindings,
                        imports,
                        types,
                        functions,
                      )
                    None ->
                      make_expression_source(
                        input,
                        bindings,
                        imports,
                        types,
                        functions,
                      )
                  }
              }
          }
      }

      let _ = simplifile.create_directory("test")

      case simplifile.write(to: evaluator_path, contents: source) {
        Ok(_) -> {
          let start_time = runtime.system_time()
          let result = runner.run(parsed_binding, module_name)
          let elapsed_us = runtime.system_time() - start_time

          // Delete the specific dynamic file!
          let _ = simplifile.delete(evaluator_path)

          let debug_output = case debug {
            True -> {
              let ms = int.to_string(elapsed_us / 1000)
              let us = int.to_string(elapsed_us % 1000)
              "\u{001b}[90m[debug] latency: "
              <> ms
              <> "."
              <> us
              <> "ms | bindings: "
              <> int.to_string(list.length(bindings))
              <> " | imports: "
              <> int.to_string(list.length(imports))
              <> "\u{001b}[0m\n"
            }
            False -> ""
          }

          let eval = case is_import, is_type, is_function, result.success {
            True, _, _, True ->
              Evaluation(..result, new_import: Some(input), output: "")
            _, True, _, True ->
              Evaluation(
                ..result,
                new_type: option.map(parsed_def_name, fn(n) { #(n, input) }),
                output: "",
              )
            _, _, True, True ->
              Evaluation(
                ..result,
                new_function: option.map(parsed_def_name, fn(n) { #(n, input) }),
                output: "",
              )
            _, _, _, _ -> result
          }

          Evaluation(..eval, output: debug_output <> eval.output)
        }

        Error(_) ->
          Evaluation(
            output: "GSH could not write evaluator file.\n",
            success: False,
            error_kind: CompileError,
            new_binding: None,
            new_import: None,
            new_type: None,
            new_function: None,
          )
      }
    }
  }
}

/// Constructs the source code when the user defines a new function.
/// Ensures the function is exposed as `pub` so it can be called in future evaluations.
fn make_function_source(
  new_fn: String,
  bindings: List(Binding),
  imports: List(String),
  types: List(String),
  functions: List(String),
) -> String {
  let pub_fn = insert_pub(new_fn)

  source.header(False, False)
  <> imports_source(imports)
  <> types_source(types)
  <> functions_source(functions)
  <> pub_fn
  <> "\n\n"
  <> "pub fn gsh_entry() {\n"
  <> bindings_source(bindings)
  <> "  terminal.println(\"// Function defined\")\n"
  <> "}\n"
}

/// Injects the necessary hidden imports for the caching engine into the generated file.
fn imports_source(imports: List(String)) -> String {
  let base =
    "import gsh/runtime/store as gsh_store\n"
    <> "import gsh/runtime/runtime as gsh_internal_runtime\n"

  // Pass the strings through the AST merger!
  let merged = parser.merge_imports(imports)

  case merged {
    [] -> base
    _ -> base <> string.join(merged, "\n") <> "\n"
  }
}

fn types_source(types: List(String)) -> String {
  case types {
    [] -> ""
    _ -> {
      let pub_types =
        list.map(types, fn(t) {
          case string.starts_with(t, "pub ") {
            True -> t
            False -> "pub " <> t
          }
        })
      string.join(pub_types, "\n\n") <> "\n\n"
    }
  }
}

/// Injects previous custom functions, as well as the built-in `pid()` helper, 
/// so they are available in the top-level scope of the evaluation.
fn functions_source(functions: List(String)) -> String {
  let builtins =
    "pub fn pid(id: String) { gsh_internal_runtime.pid_from_string(id) }"

  case functions {
    [] -> builtins <> "\n\n"
    _ -> builtins <> "\n\n" <> string.join(functions, "\n\n") <> "\n\n"
  }
}

fn make_type_source(
  new_type: String,
  bindings: List(Binding),
  imports: List(String),
  types: List(String),
  functions: List(String),
) -> String {
  let pub_type = insert_pub(new_type)

  source.header(False, False)
  <> imports_source(imports)
  <> types_source(types)
  <> functions_source(functions)
  <> pub_type
  <> "\n\n"
  <> "pub fn gsh_entry() {\n"
  <> bindings_source(bindings)
  <> "  terminal.println(\"// Type defined\")\n"
  <> "}\n"
}

fn make_import_source(
  new_import: String,
  bindings: List(Binding),
  imports: List(String),
  types: List(String),
  functions: List(String),
) -> String {
  // Combine the new import with the historical ones
  let all_imports = list.append(imports, [new_import])

  source.header(False, False)
  <> imports_source(all_imports)
  <> types_source(types)
  <> functions_source(functions)
  <> "\n"
  <> "pub fn gsh_entry() {\n"
  <> bindings_source(bindings)
  <> "  terminal.println(\"ok\")\n"
  <> "}\n"
}

/// Generates the code for a raw expression (e.g., `1 + 1`).
/// Evaluates the expression, inspects it to a string, and prints it.
fn make_expression_source(
  expression: String,
  bindings: List(Binding),
  imports: List(String),
  types: List(String),
  functions: List(String),
) -> String {
  source.header(True, True)
  <> imports_source(imports)
  <> types_source(types)
  <> functions_source(functions)
  <> "pub fn gsh_entry() {\n"
  <> bindings_source(bindings)
  <> "  let gsh_internal_expr = {\n"
  <> "    "
  <> expression
  <> "\n"
  <> "  }\n"
  <> "  terminal.println(gsh_internal_formatter.format_output(gsh_internal_string.inspect(gsh_internal_expr)))\n"
  <> "}\n"
}

fn make_binding_source(
  binding: Binding,
  bindings: List(Binding),
  imports: List(String),
  types: List(String),
  functions: List(String),
) -> String {
  case binding.kind {
    Let ->
      make_normal_binding_source(binding, bindings, imports, types, functions)
    LetAssert ->
      make_assert_source(binding, bindings, imports, types, functions)
  }
}

fn make_normal_binding_source(
  binding: Binding,
  bindings: List(Binding),
  imports: List(String),
  types: List(String),
  functions: List(String),
) -> String {
  case binding.names {
    [name] ->
      source.header(True, False)
      <> imports_source(imports)
      <> types_source(types)
      <> functions_source(functions)
      <> "pub fn gsh_entry() {\n"
      <> bindings_source(bindings)
      <> generate_current_binding(binding)
      <> "  terminal.println(gsh_internal_string.inspect("
      <> name
      <> "))\n"
      <> "}\n"

    _ ->
      make_complex_binding_source(binding, bindings, imports, types, functions)
  }
}

fn make_complex_binding_source(
  binding: Binding,
  bindings: List(Binding),
  imports: List(String),
  types: List(String),
  functions: List(String),
) -> String {
  source.header(False, False)
  <> imports_source(imports)
  <> types_source(types)
  <> functions_source(functions)
  <> "pub fn gsh_entry() {\n"
  <> bindings_source(bindings)
  <> generate_current_binding(binding)
  <> "  terminal.println(\"ok\")\n"
  <> "}\n"
}

fn make_assert_source(
  binding: Binding,
  bindings: List(Binding),
  imports: List(String),
  types: List(String),
  functions: List(String),
) -> String {
  source.header(False, False)
  <> imports_source(imports)
  <> types_source(types)
  <> functions_source(functions)
  <> "pub fn gsh_entry() {\n"
  <> bindings_source(bindings)
  <> generate_current_binding(binding)
  <> "  terminal.println(\"ok\")\n"
  <> "}\n"
}

/// CURRENT BINDING: Generates exact raw code for pristine compiler errors, 
/// then manually pushes the resulting variables into the cache.
fn generate_current_binding(binding: Binding) -> String {
  let cache_key = "gsh_bind_" <> string.join(binding.names, "_")
  let capture = build_capture_group(binding.names)

  "  "
  <> binding.source
  <> "\n"
  <> "  let _ = gsh_store.put(\""
  <> cache_key
  <> "\", "
  <> capture
  <> ")\n"
}

/// HISTORICAL BINDING: Safely restores previous variables from the cache.
fn generate_historical_binding(binding: Binding) -> String {
  let cache_key = "gsh_bind_" <> string.join(binding.names, "_")
  let capture = build_capture_group(binding.names)

  "  let "
  <> capture
  <> " = gsh_store.cache(\""
  <> cache_key
  <> "\", fn() {\n"
  <> "    "
  <> binding.source
  <> "\n"
  <> "    "
  <> capture
  <> "\n"
  <> "  })\n"
}

fn bindings_source(bindings: List(Binding)) -> String {
  bindings_source_loop(bindings)
}

fn bindings_source_loop(bindings: List(Binding)) -> String {
  case bindings {
    [] -> ""
    [binding, ..rest] -> {
      let mark_used =
        binding.names
        |> list.map(fn(name) { "  let _ = " <> name <> "\n" })
        |> string.join("")

      generate_historical_binding(binding)
      <> mark_used
      <> bindings_source_loop(rest)
    }
  }
}

/// Builds a capture syntax for the bound variables (e.g., `x` or `#(a, b)`).
fn build_capture_group(names: List(String)) -> String {
  case names {
    [] -> "Nil"
    [name] -> name
    _ -> "#(" <> string.join(names, ", ") <> ")"
  }
}

fn insert_pub(src: String) -> String {
  insert_pub_loop(src, "")
}

fn insert_pub_loop(remaining: String, acc: String) -> String {
  case remaining {
    "pub " <> _ | "pub\n" <> _ -> acc <> remaining
    "fn " <> _ | "fn\n" <> _ -> acc <> "pub " <> remaining
    "type " <> _ | "type\n" <> _ -> acc <> "pub " <> remaining
    "const " <> _ | "const\n" <> _ -> acc <> "pub " <> remaining
    "opaque " <> _ -> acc <> "pub " <> remaining
    "" -> acc
    _ ->
      case string.pop_grapheme(remaining) {
        Ok(#(g, rest)) -> insert_pub_loop(rest, acc <> g)
        Error(_) -> acc <> remaining
      }
  }
}
