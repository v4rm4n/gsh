// src/gsh/evaluator/runner.gleam

import gleam/option.{type Option, None, Some}
import gleam/string
import gsh/evaluator/binding.{type Binding, Let, LetAssert}
import gsh/evaluator/formatter
import gsh/evaluator/result.{
  type ErrorKind, type Evaluation, CompileError, Evaluation, NoError,
  RuntimeError,
}
import shellout

fn persist_binding(binding: Option(Binding)) -> Option(Binding) {
  case binding {
    Some(binding) ->
      case binding.kind {
        Let -> Some(binding)

        LetAssert -> None
      }

    None -> None
  }
}

pub fn run(binding: Option(Binding)) -> Evaluation {
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
    Ok(output) ->
      Evaluation(
        output: formatter.format_output(output),
        success: True,
        error_kind: NoError,
        new_binding: persist_binding(binding),
      )

    Error(#(_status, output)) ->
      Evaluation(
        output: formatter.format_output(output),
        success: False,
        error_kind: classify_error(output),
        new_binding: None,
      )
  }
}

fn classify_error(output: String) -> ErrorKind {
  case string.contains(output, "stacktrace") {
    True -> RuntimeError

    False -> CompileError
  }
}
