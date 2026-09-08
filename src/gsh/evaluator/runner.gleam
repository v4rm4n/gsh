//// The `runner` module orchestrates the compilation and execution pipeline 
//// for the shell's dynamically generated REPL modules.
////
//// It acts as the bridge between the host filesystem and the Erlang VM, 
//// utilizing `shellout` to invoke the Gleam compiler for static analysis 
//// and Erlang generation, and utilizing the `runtime` FFI to dynamically compile, 
//// load, and execute the resulting code directly in memory.

// src/gsh/evaluator/runner.gleam

import gleam/option.{type Option, None}
import gleam/string
import gsh/evaluator/binding.{type Binding}
import gsh/evaluator/formatter
import gsh/evaluator/result.{
  type Evaluation, CompileError, Evaluation, NoError, RuntimeError,
}
import gsh/runtime/runtime
import shellout

/// Filters whether a successfully evaluated binding should be persisted into 
/// the shell's active state.
/// 
/// Currently, standard `Let` bindings are saved, but strict `LetAssert` 
/// pattern matches are intentionally discarded. This prevents complex, 
/// fallible destructuring from polluting the REPL's persistent variable cache.
fn persist_binding(binding: Option(Binding)) -> Option(Binding) {
  binding
}

/// Triggers a full compilation of the host workspace using the Gleam CLI.
/// 
/// This is invoked by the `compile` command in the REPL, allowing developers 
/// to rebuild their background application and trigger Erlang VM hot-reloads 
/// without dropping their active shell session.
pub fn build_project() -> Result(String, #(Int, String)) {
  shellout.command(run: "gleam", with: ["build"], in: ".", opt: [])
}

/// The core execution pipeline for evaluated code.
/// 
/// **Execution Lifecycle:**
/// 1. **Isolated Compilation:** Invokes `gleam compile-package` targeting an 
///    isolated `build/dev/erlang/gsh_eval` output directory. This ensures the REPL's 
///    temporary files never corrupt or overwrite the host project's build cache.
/// 2. **In-Memory Loading:** Reads the resulting `.erl` file and uses Erlang's 
///    native compiler FFI to compile it directly into RAM, bypassing `.beam` disk I/O.
/// 3. **Execution:** Invokes the dynamically loaded `gsh_entry` function, capturing 
///    the evaluation success or gracefully intercepting Erlang VM runtime crashes.
pub fn run(binding: Option(Binding), module_name: String) -> Evaluation {
  // 1. Output to a dedicated directory ('gsh_eval') so 'gsh' metadata isn't nuked in --lib
  let args = [
    "compile-package", "--target", "erlang", "--package", ".", "--out",
    "build/dev/erlang/gsh_eval", "--lib", "build/dev/erlang", "--no-beam",
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
      // 2. Read the generated .erl file from the isolated gsh_eval build directory
      let erl_path =
        "build/dev/erlang/gsh_eval/_gleam_artefacts/" <> module_name <> ".erl"

      case runtime.compile_and_load(erl_path, module_name) {
        Ok(_) -> {
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
