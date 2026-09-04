// src/gsh/evaluator/evaluator.gleam

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
) -> Evaluation {
  let input = string.trim(input)

  let is_import = string.starts_with(input, "import ")

  // Don't bother checking for `let ` if we already know it's an import
  let parsed_binding = case is_import {
    True -> None
    False ->
      case string.starts_with(input, "let ") {
        True -> parse_binding(input)
        False -> None
      }
  }

  let source = case is_import {
    True -> make_import_source(input, bindings, imports)
    False ->
      case parsed_binding {
        Some(binding) -> make_binding_source(binding, bindings, imports)
        None -> make_expression_source(input, bindings, imports)
      }
  }

  case simplifile.write(to: evaluator_path, contents: source) {
    Ok(_) -> {
      let result = run(parsed_binding)

      let _ = simplifile.delete_all(paths: [evaluator_path])

      // Intercept the result! If it was an import and it compiled successfully,
      // save the import string and clear the dummy output.
      case is_import, result.success {
        True, True -> Evaluation(..result, new_import: Some(input), output: "")
        _, _ -> result
      }
    }

    Error(_) ->
      Evaluation(
        output: "GSH could not create the evaluator module.\n",
        success: False,
        error_kind: CompileError,
        new_binding: None,
        new_import: None,
      )
  }
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

// GSH only recognizes ordinary reusable variable names here.
// `_` itself is a discard pattern and cannot be referenced later.
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

fn imports_source(imports: List(String)) -> String {
  case imports {
    [] -> ""
    _ -> string.join(imports, "\n") <> "\n"
  }
}

fn make_import_source(
  new_import: String,
  bindings: List(Binding),
  imports: List(String),
) -> String {
  source.header(False)
  <> imports_source(imports)
  <> new_import
  <> "\n"
  <> "pub fn main() {\n"
  <> bindings_source(bindings)
  <> "  terminal.println(\"ok\")\n"
  <> "}\n"
}

// Generate a temporary module for evaluating a normal expression
// while replaying successful bindings from the current session.
fn make_expression_source(
  expression: String,
  bindings: List(Binding),
  imports: List(String),
) -> String {
  source.header(True)
  <> imports_source(imports)
  <> "pub fn main() {\n"
  <> bindings_source(bindings)
  <> "  terminal.println(gsh_internal_string.inspect(\n"
  <> "    "
  <> expression
  <> "\n"
  <> "  ))\n"
  <> "}\n"
}

fn make_binding_source(
  binding: Binding,
  bindings: List(Binding),
  imports: List(String),
) -> String {
  case binding.kind {
    Let -> make_normal_binding_source(binding, bindings, imports)

    LetAssert -> make_assert_source(binding, bindings, imports)
  }
}

fn make_normal_binding_source(
  binding: Binding,
  bindings: List(Binding),
  imports: List(String),
) -> String {
  case binding.name {
    Some(name) ->
      source.header(True)
      <> imports_source(imports)
      <> "pub fn main() {\n"
      <> bindings_source(bindings)
      <> "  "
      <> binding.source
      <> "\n"
      <> "  terminal.println(gsh_internal_string.inspect("
      <> name
      <> "))\n"
      <> "}\n"

    None -> make_complex_binding_source(binding, bindings, imports)
  }
}

fn make_assert_source(
  binding: Binding,
  bindings: List(Binding),
  imports: List(String),
) -> String {
  source.header(False)
  <> imports_source(imports)
  <> "pub fn main() {\n"
  <> bindings_source(bindings)
  <> "  "
  <> binding.source
  <> "\n"
  <> "  terminal.println(\"ok\")\n"
  <> "}\n"
}

// Complex patterns currently need a temporary value so GSH can display
// the complete value produced by the binding. This is temporary until
// GSH has richer pattern information.
fn make_complex_binding_source(
  binding: Binding,
  bindings: List(Binding),
  imports: List(String),
) -> String {
  source.header(True)
  <> imports_source(imports)
  <> "pub fn main() {\n"
  <> bindings_source(bindings)
  <> "  "
  <> binding.source
  <> "\n"
  <> "  terminal.println(gsh_internal_string.inspect("
  <> binding.value
  <> "))\n"
  <> "}\n"
}

fn bindings_source(bindings: List(Binding)) -> String {
  case bindings {
    [] -> ""

    [binding, ..rest] -> {
      let mark_used = case binding.name {
        Some(name) -> "  let _ = " <> name <> "\n"

        None -> ""
      }

      "  " <> binding.source <> "\n" <> mark_used <> bindings_source(rest)
    }
  }
}
