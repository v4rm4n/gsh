// src/gsh.gleam

import gleam/erlang/atom
import gleam/format
import gleam/io
import gleam/list
import gleam/option
import gleam/string
import gsh/command/router as command
import gsh/evaluator/binding
import gsh/evaluator/evaluator
import gsh/runtime/runtime.{app_version, system_version}
import in

// GSH keeps shell information immutable and passes the updated
// state into the next REPL iteration
type ShellState {
  ShellState(
    prompt_count: Int,
    bindings: List(binding.Binding),
    history: List(String),
  )
}

pub fn main() -> Nil {
  // Print the banner.
  banner()
  // Start the REPL.
  shell_loop(ShellState(1, [], []))
}

fn banner() -> Nil {
  // Use FFI calls for the banner
  io.println(system_version())
  format.printf(
    "Interactive Gleam (GSH ~s) - press Ctrl+C to exit (type h() ENTER for help)",
    app_version(atom.create("gsh")),
  )
  io.println("")
}

fn shell_loop(state: ShellState) -> Nil {
  format.printf("gsh(~b)> ", state.prompt_count)

  case in.read_line() {
    Ok(input) -> {
      let input = string.trim(input)
      let history = case input {
        "" -> state.history
        _ -> list.append(state.history, [input])
      }
      case command.handle(input, state.bindings, state.history) {
        command.Handled ->
          shell_loop(ShellState(
            state.prompt_count + 1,
            state.bindings,
            history:,
          ))

        command.Exit -> {
          io.println("Goodbye.")
          Nil
        }

        command.NotCommand -> {
          let result = evaluator.evaluate(input, state.bindings)

          io.print(result.output)

          let bindings = case result.new_binding {
            option.Some(binding) -> list.append(state.bindings, [binding])

            option.None -> state.bindings
          }

          shell_loop(ShellState(state.prompt_count + 1, bindings, history:))
        }
      }
    }
    // TODO: Handle error by looping with last good state
    Error(_) -> Nil
  }
}
