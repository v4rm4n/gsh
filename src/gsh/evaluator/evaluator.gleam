//// The `evaluator` module is the beating heart of the GSH REPL.
////
//// Because Gleam is statically typed and compiled, we cannot evaluate raw AST 
//// dynamically like Elixir's IEx. Instead, this module takes the user's input, 
//// combines it with all previous session state (imports, bindings, types), 
//// and generates a temporary `gsh_eval.gleam` file.
////
//// Crucially, this is where the "Side-Effect Magic Caching" happens. Every 
//// variable assignment is wrapped in a check against the Erlang Process Dictionary, 
//// ensuring that `let x = io.println("test")` only prints once, even as the 
//// file is re-compiled for subsequent REPL prompts.

// src/gsh/evaluator/evaluator.gleam

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import glexer
import glexer/token
import gsh/evaluator/binding.{type Binding, Binding, Let, LetAssert}
import gsh/evaluator/result.{type Evaluation, CompileError, Evaluation}
import gsh/evaluator/runner
import gsh/evaluator/source
import gsh/runtime/runtime
import simplifile

// const evaluator_path = "test/gsh_eval.gleam"

/// The main entry point for code evaluation.
/// 1. Analyzes the input to determine if it is an import, type, function, binding, or expression.
/// 2. Generates the full source code for a temporary Gleam module.
/// 3. Writes the file to disk and passes it to the `runner` to be compiled and executed.
/// 4. Returns the result, updating the shell state if new bindings/imports were successfully evaluated.
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

  // 1. Run the lexer and get ALL tokens (including comments and errors)
  let raw_tokens =
    glexer.new(input)
    |> glexer.lex()
    |> list.map(fn(tuple) { tuple.0 })

  // 2. Check if the user left a string open or typed a bad character
  let lex_error =
    list.find(raw_tokens, fn(t) {
      case t {
        token.UnterminatedString(_) | token.UnexpectedGrapheme(_) -> True
        _ -> False
      }
    })

  case lex_error {
    Ok(token.UnterminatedString(_)) -> {
      Evaluation(
        output: "error: Syntax error\n  The string was left open.\n",
        success: False,
        error_kind: CompileError,
        // Reverted from IncompleteInput
        new_binding: None,
        new_import: None,
        new_type: None,
        new_function: None,
      )
    }
    Ok(token.UnexpectedGrapheme(g)) -> {
      Evaluation(
        output: "error: Syntax error\n  Unexpected grapheme: " <> g <> "\n",
        success: False,
        error_kind: CompileError,
        new_binding: None,
        new_import: None,
        new_type: None,
        new_function: None,
      )
    }
    _ -> {
      // 1. Filter out comments AND spaces so we only route based on actual syntax
      let tokens =
        list.filter(raw_tokens, fn(t) {
          case t {
            token.CommentNormal(_)
            | token.CommentDoc(_)
            | token.CommentModule(_)
            | token.Space(_) -> False
            _ -> True
          }
        })

      // 2. Token-based routing
      let #(is_import, is_type, is_function, is_binding) = case tokens {
        [token.Import, ..] -> #(True, False, False, False)
        [token.Pub, token.Type, ..] | [token.Type, ..] -> #(
          False,
          True,
          False,
          False,
        )
        [token.Pub, token.Fn, ..] | [token.Fn, ..] -> #(
          False,
          False,
          True,
          False,
        )
        [token.Let, ..] -> #(False, False, False, True)
        _ -> #(False, False, False, False)
      }

      // 3. Extract the binding if it is one
      let parsed_binding = case is_binding {
        True -> parse_binding(input, tokens)
        False -> None
      }

      let parsed_def_name = case is_type || is_function {
        True -> extract_def_name(tokens)
        False -> None
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
  let pub_fn = case string.starts_with(new_fn, "pub ") {
    True -> new_fn
    False -> "pub " <> new_fn
  }

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

/// Parses a string like `let x = 5` into a structured `Binding` record, 
/// separating the left-hand pattern from the right-hand value.
fn parse_binding(source: String, tokens: List(token.Token)) -> Option(Binding) {
  let #(kind, without_let) = case tokens {
    [token.Let, token.Assert, ..] -> #(
      LetAssert,
      string.remove_prefix(from: source, matching: "let assert "),
    )
    _ -> #(Let, string.remove_prefix(from: source, matching: "let "))
  }

  let references = extract_names_from_tokens(tokens, [])

  case string.split_once(without_let, on: "=") {
    Ok(#(pattern, value)) -> {
      Some(Binding(
        kind: kind,
        source: source,
        pattern: string.trim(pattern),
        names: references,
        // Now passing the List
        value: string.trim(value),
      ))
    }
    Error(_) -> None
  }
}

/// Scans the left side of an assignment to extract ALL bound variable names.
fn extract_names_from_tokens(
  tokens: List(token.Token),
  acc: List(String),
) -> List(String) {
  case tokens {
    [] | [token.Equal, ..] -> list.reverse(acc)

    // Grab lowercase variable names!
    [token.Name(name), ..rest] -> extract_names_from_tokens(rest, [name, ..acc])

    // Ignore everything else
    [_, ..rest] -> extract_names_from_tokens(rest, acc)
  }
}

/// Injects the necessary hidden imports for the caching engine into the generated file.
fn imports_source(imports: List(String)) -> String {
  let base =
    "import gsh/runtime/store as gsh_store\n"
    <> "import gsh/runtime/runtime as gsh_internal_runtime\n"

  case imports {
    [] -> base
    _ -> base <> string.join(imports, "\n") <> "\n"
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
  let pub_type = case string.starts_with(new_type, "pub ") {
    True -> new_type
    False -> "pub " <> new_type
  }

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
  source.header(False, False)
  <> imports_source(imports)
  <> types_source(types)
  <> functions_source(functions)
  <> new_import
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

fn extract_def_name(tokens: List(token.Token)) -> Option(String) {
  case tokens {
    [token.Pub, token.Fn, token.Name(name), ..] -> Some(name)
    [token.Fn, token.Name(name), ..] -> Some(name)
    [token.Pub, token.Type, token.UpperName(name), ..] -> Some(name)
    [token.Type, token.UpperName(name), ..] -> Some(name)
    _ -> None
  }
}
