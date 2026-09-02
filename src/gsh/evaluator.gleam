import gleam/option.{type Option, None, Some}
import gleam/string
import shellout
import simplifile

const evaluator_path = "src/gsh_eval.gleam"

// GSH returns both the visible evaluation output and, when applicable,
// a successfully compiled binding that should persist in the REPL session.
pub type Evaluation {
  Evaluation(output: String, new_binding: Option(String))
}

pub fn evaluate(input: String, bindings: List(String)) -> Evaluation {
  let input = string.trim(input)

  let is_binding = string.starts_with(input, "let ")

  let source = case is_binding {
    True -> make_binding_source(input, bindings)

    False -> make_expression_source(input, bindings)
  }

  case simplifile.write(to: evaluator_path, contents: source) {
    Ok(_) -> run_evaluator(input, is_binding)

    Error(_) ->
      Evaluation(
        output: "GSH could not create the evaluator module.\n",
        new_binding: None,
      )
  }
}

// Run the generated evaluator using shellout rather than a custom
// Erlang os:cmd bridge, giving GSH structured process errors.
fn run_evaluator(input: String, is_binding: Bool) -> Evaluation {
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
    Ok(output) -> {
      let new_binding = case is_binding {
        True -> Some(input)
        False -> None
      }

      Evaluation(output: output, new_binding: new_binding)
    }

    Error(#(_status, output)) -> Evaluation(output: output, new_binding: None)
  }
}

// Generate a temporary module for evaluating a normal expression
// while replaying bindings already stored in this GSH session.
fn make_expression_source(
  expression: String,
  bindings: List(String),
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

// Generate a temporary module for evaluating a new let binding,
// printing the resulting value if compilation succeeds.
fn make_binding_source(binding: String, bindings: List(String)) -> String {
  let without_let = string.remove_prefix(from: binding, matching: "let ")

  case string.split_once(without_let, on: "=") {
    Ok(#(name, _value)) -> {
      let variable_name = string.trim(name)

      "import gleam/io\n"
      <> "import gleam/string\n"
      <> "\n"
      <> "pub fn main() {\n"
      <> bindings_source(bindings)
      <> "  "
      <> binding
      <> "\n"
      <> "  io.println(string.inspect("
      <> variable_name
      <> "))\n"
      <> "}\n"
    }

    Error(_) -> make_expression_source(binding, bindings)
  }
}

// Convert the successful bindings from the current GSH session
// back into Gleam source before compiling the next expression.
fn bindings_source(bindings: List(String)) -> String {
  case bindings {
    [] -> ""

    _ -> "  " <> string.join(bindings, with: "\n  ") <> "\n"
  }
}
