// src/gsh/evaluator/evaluator.gleam
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gsh/evaluator/binding.{type Binding, Binding, Let, LetAssert}
import gsh/evaluator/result.{type Evaluation, CompileError, Evaluation}
import gsh/evaluator/runner.{run}
import gsh/evaluator/source
import simplifile

const evaluator_path = "test/gsh_eval.gleam"

pub fn evaluate(
  input: String,
  bindings: List(Binding),
  imports: List(String),
  types: List(String),
  functions: List(String),
) -> Evaluation {
  let input = string.trim(input)

  let is_import = string.starts_with(input, "import ")
  let is_type =
    string.starts_with(input, "type ") || string.starts_with(input, "pub type ")
  let is_function =
    string.starts_with(input, "fn ") || string.starts_with(input, "pub fn ")

  let parsed_binding = case is_import || is_type || is_function {
    True -> None
    False ->
      case string.starts_with(input, "let ") {
        True -> parse_binding(input)
        False -> None
      }
  }

  let source = case is_import {
    True -> make_import_source(input, bindings, imports, types, functions)
    False ->
      case is_type {
        True -> make_type_source(input, bindings, imports, types, functions)
        False ->
          case is_function {
            True ->
              make_function_source(input, bindings, imports, types, functions)
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
      let result = run(parsed_binding)
      let _ = simplifile.delete_all(paths: [evaluator_path])

      case is_import, is_type, is_function, result.success {
        True, _, _, True ->
          Evaluation(..result, new_import: Some(input), output: "")
        _, True, _, True ->
          Evaluation(..result, new_type: Some(input), output: "")
        _, _, True, True ->
          Evaluation(..result, new_function: Some(input), output: "")
        _, _, _, _ -> result
      }
    }

    Error(_) ->
      Evaluation(
        output: "GSH could not create the evaluator module.\n",
        success: False,
        error_kind: CompileError,
        new_binding: None,
        new_import: None,
        new_type: None,
        new_function: None,
      )
  }
}

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

  source.header(False)
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

fn parse_binding(source: String) -> Option(Binding) {
  let #(kind, without_let) = case string.starts_with(source, "let assert ") {
    True -> #(
      LetAssert,
      string.remove_prefix(from: source, matching: "let assert "),
    )
    False -> #(Let, string.remove_prefix(from: source, matching: "let "))
  }

  case string.split_once(without_let, on: "=") {
    Ok(#(pattern, value)) -> {
      let pattern = string.trim(pattern)
      let value = string.trim(value)
      let reference = extract_simple_reference(pattern)
      Some(Binding(
        kind: kind,
        source: source,
        pattern: pattern,
        name: reference,
        value: value,
      ))
    }
    Error(_) -> None
  }
}

fn extract_simple_reference(pattern: String) -> Option(String) {
  case string.split_once(pattern, on: ":") {
    Ok(#(name, _type_annotation)) -> {
      let name = string.trim(name)
      case is_simple_identifier(name) {
        True -> Some(name)
        False -> None
      }
    }
    Error(_) ->
      case is_simple_identifier(pattern) {
        True -> Some(pattern)
        False -> None
      }
  }
}

fn is_simple_identifier(value: String) -> Bool {
  case value {
    "_" -> False
    _ ->
      case string.to_graphemes(value) {
        [] -> False
        [first, ..rest] ->
          is_identifier_start(first) && list.all(rest, is_identifier_continue)
      }
  }
}

fn is_identifier_start(value: String) -> Bool {
  string.contains(does: "abcdefghijklmnopqrstuvwxyz_", contain: value)
}

fn is_identifier_continue(value: String) -> Bool {
  string.contains(does: "abcdefghijklmnopqrstuvwxyz_0123456789", contain: value)
}

// INJECT THE STORE IMPORT SO CACHING ALWAYS WORKS
fn imports_source(imports: List(String)) -> String {
  let base = "import gsh/runtime/store as gsh_store\n"
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

fn functions_source(functions: List(String)) -> String {
  case functions {
    [] -> ""
    _ -> string.join(functions, "\n\n") <> "\n\n"
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

  source.header(False)
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
  source.header(False)
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

fn make_expression_source(
  expression: String,
  bindings: List(Binding),
  imports: List(String),
  types: List(String),
  functions: List(String),
) -> String {
  source.header(True)
  <> imports_source(imports)
  <> types_source(types)
  <> functions_source(functions)
  <> "pub fn gsh_entry() {\n"
  <> bindings_source(bindings)
  <> "  terminal.println(gsh_internal_string.inspect("
  <> expression
  <> "))\n"
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
  let index = list.length(bindings)
  case binding.name {
    Some(name) ->
      source.header(True)
      <> imports_source(imports)
      <> types_source(types)
      <> functions_source(functions)
      <> "pub fn gsh_entry() {\n"
      <> bindings_source(bindings)
      <> generate_cached_binding(binding, index)
      <> "  terminal.println(gsh_internal_string.inspect("
      <> name
      <> "))\n"
      <> "}\n"

    None ->
      make_complex_binding_source(binding, bindings, imports, types, functions)
  }
}

fn make_assert_source(
  binding: Binding,
  bindings: List(Binding),
  imports: List(String),
  types: List(String),
  functions: List(String),
) -> String {
  let index = list.length(bindings)
  source.header(False)
  <> imports_source(imports)
  <> types_source(types)
  <> functions_source(functions)
  <> "pub fn gsh_entry() {\n"
  <> bindings_source(bindings)
  <> generate_cached_binding(binding, index)
  <> "  terminal.println(\"ok\")\n"
  <> "}\n"
}

fn make_complex_binding_source(
  binding: Binding,
  bindings: List(Binding),
  imports: List(String),
  types: List(String),
  functions: List(String),
) -> String {
  let index = list.length(bindings)
  source.header(True)
  <> imports_source(imports)
  <> types_source(types)
  <> functions_source(functions)
  <> "pub fn gsh_entry() {\n"
  <> bindings_source(bindings)
  <> generate_cached_binding(binding, index)
  <> "  terminal.println(\"ok\")\n"
  <> "}\n"
}

// GENERATES THE MAGIC CACHING WRAPPER
fn generate_cached_binding(binding: Binding, index: Int) -> String {
  let cache_key = "gsh_bind_" <> int.to_string(index)
  let keyword = case binding.kind {
    Let -> "let "
    LetAssert -> "let assert "
  }

  "  "
  <> keyword
  <> binding.pattern
  <> " = case gsh_store.has(\""
  <> cache_key
  <> "\") {\n"
  <> "    True -> gsh_store.get(\""
  <> cache_key
  <> "\")\n"
  <> "    False -> {\n"
  <> "      let gsh_internal_val = "
  <> binding.value
  <> "\n"
  <> "      gsh_store.put(\""
  <> cache_key
  <> "\", gsh_internal_val)\n"
  <> "      gsh_internal_val\n"
  <> "    }\n"
  <> "  }\n"
}

fn bindings_source(bindings: List(Binding)) -> String {
  bindings_source_loop(bindings, 0)
}

fn bindings_source_loop(bindings: List(Binding), index: Int) -> String {
  case bindings {
    [] -> ""
    [binding, ..rest] -> {
      let mark_used = case binding.name {
        Some(name) -> "  let _ = " <> name <> "\n"
        None -> ""
      }
      generate_cached_binding(binding, index)
      <> mark_used
      <> bindings_source_loop(rest, index + 1)
    }
  }
}
