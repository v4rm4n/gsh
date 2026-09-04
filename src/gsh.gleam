// src/gsh.gleam

import etch/erlang/tty
import gleam/erlang/atom
import gleam/format
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/string
import gsh/command/router as command
import gsh/evaluator/binding
import gsh/evaluator/evaluator
import gsh/evaluator/runner
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
    imports: List(String),
    history: List(String),
  )
}

pub fn main() -> Nil {
  let assert Ok(_) = tty.enter_raw()

  banner()

  // 2. INITIALIZE with empty imports
  shell_loop(ShellState(1, [], [], []))

  let assert Ok(_) = tty.exit_raw()

  Nil
}

fn banner() -> Nil {
  terminal.println(system_version())
  format.printf(
    "Interactive Gleam (GSH ~s) - press Ctrl+C to exit (type h() ENTER for help)",
    app_version(atom.create("gsh")),
  )
  terminal.println("")
}

fn shell_loop(state: ShellState) -> Nil {
  let prompt = "gsh(" <> int.to_string(state.prompt_count) <> ")> "

  let input = read_command(prompt, state)

  case input {
    "" ->
      shell_loop(ShellState(
        state.prompt_count,
        state.bindings,
        state.imports,
        state.history,
      ))

    _ -> handle_input(input, state)
  }
}

fn handle_input(input: String, state: ShellState) -> Nil {
  let history = list.append(state.history, [input])

  case command.handle(input, state.bindings, state.history) {
    command.Handled ->
      shell_loop(ShellState(
        state.prompt_count + 1,
        state.bindings,
        state.imports,
        // <-- Pass imports
        history,
      ))

    command.Exit -> {
      let _ = tty.exit_raw()
      terminal.println("Goodbye.")
      Nil
    }

    command.Clear -> {
      terminal.clear_screen()
      shell_loop(ShellState(
        state.prompt_count + 1,
        state.bindings,
        state.imports,
        history,
      ))
    }

    command.Compile -> {
      case runner.build_project() {
        // If the output is empty, nothing changed.
        Ok("") -> terminal.println("Noop")

        // If it succeeded and has output, print it and return Ok
        Ok(output) -> {
          terminal.println(output)
          terminal.println("Ok")
        }

        // If it failed, print the compiler error and return Error
        Error(#(_, output)) -> {
          terminal.println(output)
          terminal.println("Error")
        }
      }

      shell_loop(ShellState(
        state.prompt_count + 1,
        state.bindings,
        state.imports,
        history,
      ))
    }

    command.NotCommand -> {
      // 1. Check if they are trying to import something they already imported
      let is_duplicate_import =
        string.starts_with(input, "import ")
        && list.contains(state.imports, input)

      case is_duplicate_import {
        True -> {
          terminal.println("Discarded duplicate import")

          shell_loop(ShellState(
            state.prompt_count + 1,
            state.bindings,
            state.imports,
            history,
          ))
        }

        False -> {
          // 2. Normal evaluation path
          let result = evaluator.evaluate(input, state.bindings, state.imports)

          terminal.print(result.output)

          let bindings = case result.new_binding {
            option.Some(binding) -> list.append(state.bindings, [binding])
            option.None -> state.bindings
          }

          let imports = case result.new_import {
            option.Some(imp) -> list.append(state.imports, [imp])
            option.None -> state.imports
          }

          shell_loop(ShellState(
            state.prompt_count + 1,
            bindings,
            imports,
            history,
          ))
        }
      }
    }
  }
}

fn read_command(prompt: String, state: ShellState) -> String {
  // Gather keywords and active variables
  let keywords = [
    "let",
    "assert",
    "import",
    "fn",
    "case",
    "if",
    "True",
    "False",
  ]
  let variables =
    list.filter_map(state.bindings, fn(b) { option.to_result(b.name, Nil) })

  let module_completions =
    list.flat_map(state.imports, fn(imp) {
      // 1. Clean the import string (e.g., "import gleam/int" -> "gleam/int")
      let path = string.replace(imp, "import ", "") |> string.trim()

      // 2. Get the module alias (e.g., "gleam/int" -> "int")
      let alias = case list.last(string.split(path, "/")) {
        Ok(a) -> a
        Error(_) -> path
      }

      // 3. Convert to Erlang format (e.g., "gleam/int" -> "gleam@int")
      let erl_module = string.replace(path, "/", "@")

      // 4. Fetch the exports from Erlang!
      let functions = runtime.get_exports(erl_module)

      // 5. Format them as "int.to_string"
      let formatted_functions =
        list.map(functions, fn(func) { alias <> "." <> func })

      // Include the base alias (so typing "in" completes to "int") plus all its functions
      list.append([alias], formatted_functions)
    })

  let completions =
    keywords
    |> list.append(variables)
    |> list.append(module_completions)

  read_lines(prompt, state.history, "", True, completions)
}

fn read_lines(
  prompt: String,
  history: List(String),
  current: String,
  first: Bool,
  completions: List(String),
) -> String {
  let current_prompt = case first {
    True -> prompt
    False -> "...> "
  }

  io.print(current_prompt)

  let line = editor.read_line(current_prompt, history, completions)

  let combined = case current {
    "" -> line
    _ -> current <> "\n" <> line
  }

  case buffer.is_complete(combined) {
    True -> combined

    False -> read_lines(prompt, history, combined, False, completions)
  }
}
