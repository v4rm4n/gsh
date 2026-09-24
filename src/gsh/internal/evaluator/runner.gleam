// The `runner` module orchestrates the compilation and execution pipeline
// for the shell's dynamically generated REPL modules.
//
// It acts as the bridge between the host filesystem and the Erlang VM,
// utilizing `shellout` to invoke the Gleam compiler for static analysis
// and Erlang generation, and utilizing the `runtime` FFI to dynamically compile,
// load, and execute the resulting code directly in memory.

// src/gsh/internal/evaluator/runner.gleam

import gleam/dynamic
import gleam/option.{type Option, None}
import gleam/string
import gsh/internal/evaluator/binding.{type Binding}
import gsh/internal/evaluator/formatter
import gsh/internal/evaluator/result.{
  type Evaluation, CompileError, Evaluation, NoError, RuntimeError,
}
import gsh/internal/evaluator/style
import gsh/internal/evaluator/target.{type Target, Local, Pried, Remote}
import gsh/internal/evaluator/types
import gsh/internal/runtime/pry
import gsh/internal/runtime/runtime
import shellout
import simplifile

/// Written after every definition (fn/type/import). Later prompts use it to
/// show the types of calls to REPL functions and constructors.
const interface_path = "build/dev/erlang/gsh_eval/package_interface.json"

/// Zero-cost cast to force the Erlang RPC payload back into a Gleam String.
@external(erlang, "gleam_stdlib", "identity")
fn unsafe_to_string(a: dynamic.Dynamic) -> String

fn persist_binding(binding: Option(Binding)) -> Option(Binding) {
  binding
}

pub fn build_project() -> Result(String, #(Int, String)) {
  shellout.command(run: "gleam", with: ["build"], in: ".", opt: [
    shellout.SetEnvironment([#("FORCE_COLOR", "1"), #("CLICOLOR_FORCE", "1")]),
  ])
}

/// Deletes a package interface left over from an earlier session. It would
/// describe that session's REPL functions and types, not this one's.
pub fn clear_interface() -> Nil {
  let _ = simplifile.delete(interface_path)
  Nil
}

pub fn run(
  binding: Option(Binding),
  module_name: String,
  source_input: String,
  is_definition: Bool,
  target: Target,
) -> Evaluation {
  let args = [
    "compile-package", "--target", "erlang", "--package", ".", "--out",
    "build/dev/erlang/gsh_eval", "--lib", "build/dev/erlang", "--no-beam",
  ]

  case
    shellout.command(run: "gleam", with: args, in: ".", opt: [
      shellout.SetEnvironment([#("FORCE_COLOR", "1"), #("CLICOLOR_FORCE", "1")]),
    ])
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
        active_bindings: None,
      )

    Ok(_) -> {
      let erl_path =
        "build/dev/erlang/gsh_eval/_gleam_artefacts/" <> module_name <> ".erl"

      let exec_result = case target {
        Local ->
          case runtime.compile_and_load(erl_path, module_name) {
            Ok(_) -> runtime.run_entry(module_name, "gsh_entry")
            Error(err) -> Error(dynamic.string(err))
          }
        Remote(node) ->
          runtime.rpc_compile_and_run(node, erl_path, module_name, "gsh_entry")
        Pried(pid, id) -> pry.run(pid, id, erl_path, module_name, "gsh_entry")
      }

      case exec_result {
        Ok(returned_dyn) -> {
          // Definitions print nothing themselves, but exporting the interface
          // (~400ms) lets later prompts type calls to what they defined.
          case is_definition {
            True -> export_interface()
            False -> Nil
          }

          // Bypass decoders and forcibly cast the Dynamic back to a String.
          let raw_val = unsafe_to_string(returned_dyn)

          let type_suffix = case
            types.infer_or_get_type(read_interface(), module_name, source_input)
          {
            Ok("Nil") -> ""
            Ok(t) -> style.type_note(" : " <> t)
            Error(_) -> ""
          }

          let final_output = case raw_val {
            "" -> type_suffix <> "\n"
            _ -> formatter.format_output(raw_val) <> type_suffix <> "\n"
          }

          Evaluation(
            output: final_output,
            success: True,
            error_kind: NoError,
            new_binding: persist_binding(binding),
            new_import: None,
            new_type: None,
            new_function: None,
            active_bindings: None,
          )
        }

        Error(err) ->
          Evaluation(
            output: "Execution Error: "
              <> formatter.format_error(string.inspect(err))
              <> "\n",
            success: False,
            error_kind: RuntimeError,
            new_binding: None,
            new_import: None,
            new_type: None,
            new_function: None,
            active_bindings: None,
          )
      }
    }
  }
}

/// Re-exports the package interface, used to type calls to project and REPL
/// functions. Runs after definitions, after `:cc`, and once at startup.
pub fn export_interface() -> Nil {
  // Remove the old interface first, so a failed export can't leave a stale one.
  let _ = simplifile.delete(interface_path)
  let _ =
    shellout.command(
      run: "gleam",
      with: ["export", "package-interface", "--out", interface_path],
      in: ".",
      opt: [],
    )
  Nil
}

fn read_interface() -> String {
  case simplifile.read(interface_path) {
    Ok(json) -> json
    Error(_) -> ""
  }
}
