import gleam/option.{type Option, None, Some}
import gleam/string
import shellout
import simplifile

const evaluator_path = "test/gsh_eval.gleam"

pub type Binding {
  Binding(source: String, reference: String)
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

      // GSH removes generated evaluator source after execution so
      // temporary REPL state never becomes permanent project code.
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

// Run the generated evaluator using shellout rather than a custom
// Erlang os:cmd bridge, giving GSH structured process errors.
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

// Parse the simple `let name = value` form supported by the
// first GSH binding implementation.
fn parse_binding(input: String) -> Option(Binding) {
  let without_let = string.remove_prefix(from: input, matching: "let ")

  case string.split_once(without_let, on: "=") {
    Ok(#(reference, _value)) -> {
      let reference = string.trim(reference)

      Some(Binding(source: input, reference:))
    }

    Error(_) -> None
  }
}

// Generate a temporary module for evaluating a normal expression
// while replaying bindings already stored in this GSH session.
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

// Generate a temporary module for evaluating a new let binding,
// printing the resulting value if compilation succeeds.
fn make_binding_source(binding: Binding, bindings: List(Binding)) -> String {
  "import gleam/io\n"
  <> "import gleam/string\n"
  <> "\n"
  <> "pub fn main() {\n"
  <> bindings_source(bindings)
  <> "  "
  <> binding.source
  <> "\n"
  <> "  io.println(string.inspect("
  <> binding.reference
  <> "))\n"
  <> "}\n"
}

// Convert the successful bindings from the current GSH session
// back into Gleam source before compiling the next expression.
fn bindings_source(bindings: List(Binding)) -> String {
  case bindings {
    [] -> ""

    [binding, ..rest] ->
      "  "
      <> binding.source
      <> "\n"
      <> "  let _ = "
      <> binding.reference
      <> "\n"
      <> bindings_source(rest)
  }
}
