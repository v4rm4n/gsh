//// The `runner` module orchestrates the compilation and execution of the shell's 
//// dynamically generated code.
////
//// It acts as the coordinator between the external system (using `shellout` to 
//// invoke the Gleam compiler) and the internal Erlang VM (using the `runtime` 
//// FFI to dynamically load and execute the resulting `.beam` bytecode).

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

/// Filters whether a successful binding should be saved to the shell's persistent state.
/// Currently, standard `Let` bindings are persisted, but strict `LetAssert` pattern 
/// matches are discarded from the global namespace to prevent complex destructuring 
/// from polluting the simple variable cache.
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

/// Triggers a full compilation of the host project using the Gleam CLI.
/// This is used when the user types the `compile` command in the REPL, 
/// allowing them to rebuild their background application without leaving the shell.
pub fn build_project() -> Result(String, #(Int, String)) {
  shellout.command(run: "gleam", with: ["build"], in: ".", opt: [])
}

/// The core execution pipeline for evaluated code.
pub fn run(binding: Option(Binding), module_name: String) -> Evaluation {
  // 1. Fast-path Gleam compilation straight to .erl source (skips full build graph & .beam disk writes)
  let args = [
    "compile-package", "--target", "erlang", "--package", ".", "--out",
    "build/dev/erlang/gsh", "--lib", "build/dev/erlang", "--no-beam",
  ]

  case shellout.command(run: "gleam", with: args, in: ".", opt: []) {
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
      // 2. Compile the generated .erl file directly into RAM via Erlang's compile:file
      let erl_path =
        "build/dev/erlang/gsh/_gleam_artefacts/" <> module_name <> ".erl"

      case runtime.compile_and_load(erl_path, module_name) {
        Ok(_) -> {
          // 3. Execute entrypoint in memory
          case runtime.run_entry(module_name, "gsh_entry") {
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

        Error(err) ->
          Evaluation(
            output: "Erlang RAM Compilation Error: " <> err <> "\n",
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
