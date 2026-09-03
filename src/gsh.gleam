// src/gsh.gleam

import gleam/erlang/atom
import gleam/format
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gsh/command/router as command
import gsh/evaluator/binding
import gsh/evaluator/evaluator
import gsh/input/buffer
import gsh/input/editor
import gsh/input/terminal
import gsh/runtime/runtime.{app_version, system_version}

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
  let _ = runtime.enable_raw_mode()
  // Print the banner.
  banner()
  // Start the REPL.
  shell_loop(ShellState(1, [], []))
}

fn banner() -> Nil {
  // Use FFI calls for the banner
  terminal.println(system_version())
  format.printf(
    "Interactive Gleam (GSH ~s) - press Ctrl+C to exit (type h() ENTER for help)",
    app_version(atom.create("gsh")),
  )
  terminal.println("")
}

fn shell_loop(state: ShellState) -> Nil {
  let prompt = "gsh(" <> int.to_string(state.prompt_count) <> ")> "

  let input = read_command(prompt, state.history)

  case input {
    "" ->
      shell_loop(ShellState(state.prompt_count, state.bindings, state.history))

    _ -> handle_input(input, state)
  }
}

fn handle_input(input: String, state: ShellState) -> Nil {
  let history = list.append(state.history, [input])

  case command.handle(input, state.bindings, state.history) {
    command.Handled ->
      shell_loop(ShellState(state.prompt_count + 1, state.bindings, history))

    command.Exit -> {
      let _ = runtime.disable_raw_mode()
      terminal.println("Goodbye.")
      Nil
    }

    command.NotCommand -> {
      let result = evaluator.evaluate(input, state.bindings)

      io.print(result.output)

      let bindings = case result.new_binding {
        option.Some(binding) -> list.append(state.bindings, [binding])

        option.None -> state.bindings
      }

      shell_loop(ShellState(state.prompt_count + 1, bindings, history))
    }
  }
}

fn read_command(prompt: String, history: List(String)) -> String {
  read_lines(prompt, history, "", True)
}

fn read_lines(
  prompt: String,
  history: List(String),
  current: String,
  first: Bool,
) -> String {
  let current_prompt = case first {
    True -> prompt
    False -> "...> "
  }

  io.print(current_prompt)

  let line = editor.read_line(current_prompt, history)

  let combined = case current {
    "" -> line
    _ -> current <> "\n" <> line
  }

  case buffer.is_complete(combined) {
    True -> combined

    False -> read_lines(prompt, history, combined, False)
  }
}
