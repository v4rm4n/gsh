import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import shellout
import simplifile

const evaluator_path = "test/gsh_eval.gleam"

pub type BindingKind {
  Let
  LetAssert
}

pub type Binding {
  Binding(
    kind: BindingKind,
    source: String,
    pattern: String,
    reference: Option(String),
    value: String,
  )
}

// GSH returns both the visible evaluation output and, when applicable,
// a successfully compiled binding that should persist in the REPL session.
pub type Evaluation {
  Evaluation(output: String, new_binding: Option(Binding))
}

pub fn evaluate(input: String, bindings: List(Binding)) -> Evaluation {
  let input = string.trim(input)

  let parsed_binding = case string.starts_with(input, "let ") {
    True -> parse_binding(input)
    False -> None
  }

  let source = case parsed_binding {
    Some(binding) -> make_binding_source(binding, bindings)

    None -> make_expression_source(input, bindings)
  }

  case simplifile.write(to: evaluator_path, contents: source) {
    Ok(_) -> {
      let result = run_evaluator(parsed_binding)

      // Remove generated evaluator code after each command so REPL
      // session implementation details never persist in the project.
      let _ = simplifile.delete_all(paths: [evaluator_path])

      result
    }

    Error(_) ->
      Evaluation(
        output: "GSH could not create the evaluator module.\n",
        new_binding: None,
      )
  }
}

// Run the generated Gleam module and only persist a binding when
// compilation and execution complete successfully.
fn run_evaluator(new_binding: Option(Binding)) -> Evaluation {
  case
    shellout.command(
      run: "gleam",
      with: [
        "run",
        "--module",
        "gsh_eval",
        "--no-print-progress",
      ],
      in: ".",
      opt: [],
    )
  {
    Ok(output) -> Evaluation(output: output, new_binding: new_binding)

    Error(#(_status, output)) -> Evaluation(output: output, new_binding: None)
  }
}

// Parse the current prototype forms:
//
//   let x = value
//   let x: Type = value
//
// Complex Gleam patterns are still passed through to the real
// compiler, but GSH only extracts a reusable reference for simple names.
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
        reference: reference,
        value: value,
      ))
    }

    Error(_) -> None
  }
}

// Extract the reusable variable name from either:
//
//   x
//   x: Int
//
// Anything more complex is left to the Gleam compiler.
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

// Generate a temporary module for evaluating a normal expression
// while replaying successful bindings from the current session.
fn make_expression_source(
  expression: String,
  bindings: List(Binding),
) -> String {
  "import gleam/io\n"
  <> "import gleam/string\n"
  <> "\n"
  <> "pub fn main() {\n"
  <> bindings_source(bindings)
  <> "  io.println(string.inspect(\n"
  <> "    "
  <> expression
  <> "\n"
  <> "  ))\n"
  <> "}\n"
}

fn make_binding_source(binding: Binding, bindings: List(Binding)) -> String {
  case binding.kind {
    Let -> make_normal_binding_source(binding, bindings)

    LetAssert -> make_assert_source(binding, bindings)
  }
}

fn make_normal_binding_source(
  binding: Binding,
  bindings: List(Binding),
) -> String {
  case binding.reference {
    Some(reference) ->
      "import gleam/io\n"
      <> "import gleam/string\n"
      <> "\n"
      <> "pub fn main() {\n"
      <> bindings_source(bindings)
      <> "  "
      <> binding.source
      <> "\n"
      <> "  io.println(string.inspect("
      <> reference
      <> "))\n"
      <> "}\n"

    None -> make_complex_binding_source(binding, bindings)
  }
}

fn make_assert_source(binding: Binding, bindings: List(Binding)) -> String {
  "import gleam/io\n"
  <> "import gleam/string\n"
  <> "\n"
  <> "pub fn main() {\n"
  <> bindings_source(bindings)
  <> "  "
  <> binding.source
  <> "\n"
  <> "  io.println(string.inspect("
  <> binding.pattern
  <> "))\n"
  <> "}\n"
}

// Complex patterns currently need a temporary value so GSH can display
// the complete value produced by the binding. This is temporary until
// GSH has richer pattern information.
fn make_complex_binding_source(
  binding: Binding,
  bindings: List(Binding),
) -> String {
  "import gleam/io\n"
  <> "import gleam/string\n"
  <> "\n"
  <> "pub fn main() {\n"
  <> bindings_source(bindings)
  <> "  let gsh_value = "
  <> binding.value
  <> "\n"
  <> "  let "
  <> binding.pattern
  <> " = gsh_value\n"
  <> "  io.println(string.inspect(gsh_value))\n"
  <> "}\n"
}

// Replay successful bindings in their original order.
// Simple named bindings are marked as intentionally used so GSH's
// replay mechanism does not create artificial compiler warnings.
fn bindings_source(bindings: List(Binding)) -> String {
  case bindings {
    [] -> ""

    [binding, ..rest] -> {
      let mark_used = case binding.reference {
        Some(reference) -> "  let _ = " <> reference <> "\n"

        None -> ""
      }

      "  " <> binding.source <> "\n" <> mark_used <> bindings_source(rest)
    }
  }
}
