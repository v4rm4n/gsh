// src/gsh.gleam

import etch/erlang/tty
import gleam/erlang/atom
import gleam/erlang/process
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

type ShellState {
  ShellState(
    prompt_count: Int,
    bindings: List(binding.Binding),
    imports: List(String),
    types: List(String),
    history: List(String),
    functions: List(String),
  )
}

pub fn main() -> Nil {
  // 1. Intercept ALL CLI arguments and boot them
  let args = runtime.get_args()

  case list.is_empty(args) {
    True -> Nil
    False -> {
      terminal.println("Booting background applications...")

      list.each(args, fn(app_module) {
        case runtime.boot_app(app_module) {
          Ok(pid) -> {
            // pid is returned as Dynamic, so we inspect it to get <0.X.0>
            let pid_str = string.inspect(pid)
            terminal.println(app_module <> " -> " <> pid_str)
          }
          Error(err) -> {
            terminal.println(app_module <> " -> Failed: " <> err)
          }
        }
      })

      terminal.println("")
      // Empty line for spacing
      process.sleep(50)
      // Give them time to print startup logs before raw mode
    }
  }

  // 2. Start the shell as usual
  let assert Ok(_) = tty.enter_raw()

  banner()

  // Initialized with empty lists
  shell_loop(ShellState(1, [], [], [], [], []))

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
        state.types,
        state.history,
        state.functions,
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
        state.types,
        history,
        state.functions,
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
        state.types,
        history,
        state.functions,
      ))
    }

    command.Compile -> {
      case runner.build_project() {
        Ok("") -> terminal.println("Noop")

        Ok(output) -> {
          terminal.println(output)
          terminal.println("Ok")
        }

        Error(#(_, output)) -> {
          terminal.println(output)
          terminal.println("Error")
        }
      }

      shell_loop(ShellState(
        state.prompt_count + 1,
        state.bindings,
        state.imports,
        state.types,
        history,
        state.functions,
      ))
    }

    command.NotCommand -> {
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
            state.types,
            history,
            state.functions,
          ))
        }

        False -> {
          // Exit raw mode so side effects print normally!
          let assert Ok(_) = tty.exit_raw()

          // Pass state.types into the evaluator
          let result =
            evaluator.evaluate(
              input,
              state.bindings,
              state.imports,
              state.types,
              state.functions,
            )

          // Print evaluator output while still in normal mode
          io.print(result.output)

          // Re-enter raw mode for the next REPL prompt
          let assert Ok(_) = tty.enter_raw()

          let bindings = case result.new_binding {
            option.Some(binding) -> list.append(state.bindings, [binding])
            option.None -> state.bindings
          }

          let imports = case result.new_import {
            option.Some(imp) -> list.append(state.imports, [imp])
            option.None -> state.imports
          }

          // Persist newly evaluated custom types
          let types = case result.new_type {
            option.Some(t) -> list.append(state.types, [t])
            option.None -> state.types
          }

          // Persist newly evaluated custom functions
          let functions = case result.new_function {
            option.Some(f) -> list.append(state.functions, [f])
            option.None -> state.functions
          }

          shell_loop(ShellState(
            state.prompt_count + 1,
            bindings,
            imports,
            types,
            history,
            functions,
          ))
        }
      }
    }
  }
}

fn read_command(prompt: String, state: ShellState) -> String {
  let keywords = [
    "let", "assert", "import", "type", "fn", "case", "if", "True", "False",
  ]
  let variables =
    list.filter_map(state.bindings, fn(b) { option.to_result(b.name, Nil) })

  let module_completions =
    list.flat_map(state.imports, fn(imp) {
      let path = string.replace(imp, "import ", "") |> string.trim()

      let alias = case list.last(string.split(path, "/")) {
        Ok(a) -> a
        Error(_) -> path
      }

      let erl_module = string.replace(path, "/", "@")
      let functions = runtime.get_exports(erl_module)

      let formatted_functions =
        list.map(functions, fn(func) { alias <> "." <> func })

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
