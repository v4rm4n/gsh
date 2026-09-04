// src/gsh/evaluator/runner.gleam
import gleam/option.{type Option, None, Some}
import gleam/string
import gsh/evaluator/binding.{type Binding, Let, LetAssert}
import gsh/evaluator/formatter
import gsh/evaluator/result.{
  type Evaluation, CompileError, Evaluation, NoError, RuntimeError,
}
import gsh/runtime/runtime
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

pub fn build_project() -> Result(String, #(Int, String)) {
  shellout.command(run: "gleam", with: ["build"], in: ".", opt: [])
}

pub fn run(binding: Option(Binding)) -> Evaluation {
  // 1. Trigger compile-only step (creates/updates .beam files without running a new VM)
  case
    shellout.command(
      run: "gleam",
      with: ["build", "--target", "erlang"],
      in: ".",
      opt: [],
    )
  {
    Error(#(_status, output)) ->
      Evaluation(
        output: formatter.format_error(output),
        success: False,
        error_kind: CompileError,
        new_binding: None,
        new_import: None,
        new_type: None,
        new_function: None,
      )

    Ok(_) -> {
      // 2. Change "main" to "gsh_entry" here!
      case runtime.load_and_run("gsh_eval", "gsh_entry") {
        Ok(_) ->
          Evaluation(
            output: "",
            success: True,
            error_kind: NoError,
            new_binding: persist_binding(binding),
            new_import: None,
            new_type: None,
            new_function: None,
          )

        Error(err) ->
          Evaluation(
            output: "Runtime Error: "
              <> formatter.format_error(string.inspect(err))
              <> "\n",
            success: False,
            error_kind: RuntimeError,
            new_binding: None,
            new_import: None,
            new_type: None,
            new_function: None,
          )
      }
    }
  }
}
