//// `gsh` is the core entry point for the Interactive Gleam Shell.
////
//// It acts as a development orchestrator, providing two main capabilities:
//// 
//// 1. **Zero-Config Bootloader:** Intercepts CLI arguments to dynamically boot host 
////    applications in the background (e.g., `gleam run -m gsh -- my_app`).
//// 2. **Persistent REPL:** A live-node interactive shell that maintains VM state, 
////    memoizes side effects, and safely handles runtime exceptions while toggling
////    terminal raw mode to ensure clean I/O.

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
import gsh/evaluator/docs
import gsh/evaluator/evaluator
import gsh/evaluator/runner
import gsh/input/buffer
import gsh/input/editor
import gsh/input/terminal
import gsh/runtime/runtime.{app_version, system_version}
import simplifile

/// Holds the persistent state of the shell session across evaluations.
/// This state is passed recursively through the REPL loop to maintain history, 
/// variable bindings, and declared types/functions.
pub type ShellState {
  ShellState(
    prompt_count: Int,
    bindings: List(binding.Binding),
    imports: List(String),
    types: List(#(String, String)),
    history: List(String),
    functions: List(#(String, String)),
    debug: Bool,
  )
}

/// The main entry point. 
/// 
/// 1. Intercepts trailing CLI arguments to boot background applications and print their PIDs.
/// 2. Places the terminal into raw mode for character-by-character input processing.
/// 3. Starts the recursive REPL loop.
pub fn main() -> Nil {
  let _ = simplifile.delete_all(["test/gsh_eval.gleam"])

  // 1. Intercept ALL CLI arguments and boot them
  let args = runtime.get_args()

  case list.is_empty(args) {
    True -> Nil
    False -> {
      terminal.println("Booting background applications...")

      list.each(args, fn(app_module) {
        case runtime.boot_app(app_module) {
          Ok(pid) -> {
            // Strip out the ugly //erl() syntax wrapper!
            let pid_str =
              string.inspect(pid)
              |> string.replace("//erl(", "")
              |> string.replace(")", "")

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

  // 2. Wrap the logger to prevent staircasing in background jobs
  runtime.fix_logger_staircase()

  // 3. Start the shell as usual
  let assert Ok(_) = tty.enter_raw()

  banner()

  // Initialized with empty lists
  shell_loop(ShellState(1, [], [], [], [], [], False))

  let assert Ok(_) = tty.exit_raw()

  Nil
}

/// Prints the OTP/ERTS version and the GSH startup banner.
fn banner() -> Nil {
  terminal.println(system_version())
  format.printf(
    "Interactive Gleam (GSH ~s) - press Ctrl+C to exit (type h() ENTER for help)",
    app_version(atom.create("gsh")),
  )
  terminal.println("")
}

/// The recursive heartbeat of the REPL. 
/// Prompts for input, processes it, and recurses with the updated state.
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
        state.debug,
      ))

    _ -> handle_input(input, state)
  }
}

/// Routes the user's input to either internal shell commands (like exit or clear)
/// or passes it to the evaluator engine.
/// 
/// Crucially, this function temporarily exits terminal raw mode during evaluation
/// so that side-effects (like `io.println`) and background server logs render correctly.
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
        state.debug,
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
        state.debug,
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
        state.debug,
      ))
    }

    command.Help(target) -> {
      // 1. Exit raw mode so multi-line text formats perfectly
      let assert Ok(_) = tty.exit_raw()

      // 2. Check if they asked for a function (`list.map`) or a module (`list`)
      let is_function = string.contains(target, ".")

      let output = case is_function {
        True -> {
          // Safely split "list.map" into "list" and "map"
          case string.split_once(target, ".") {
            Ok(#(mod_alias, func)) -> {
              let full_mod = resolve_alias(mod_alias, state.imports)
              docs.get_function_help(full_mod, func)
            }
            Error(_) -> "error: Invalid help target"
          }
        }
        False -> {
          let full_mod = resolve_alias(target, state.imports)
          docs.get_module_help(full_mod)
        }
      }

      // 3. Print the scraped docs
      terminal.println(output)

      // 4. Re-enter raw mode and restart the shell loop
      let assert Ok(_) = tty.enter_raw()

      shell_loop(ShellState(
        state.prompt_count + 1,
        state.bindings,
        state.imports,
        state.types,
        history,
        state.functions,
        state.debug,
      ))
    }

    command.ToggleDebug -> {
      let new_debug = !state.debug
      let status = case new_debug {
        True -> "enabled"
        False -> "disabled"
      }
      terminal.println("Debug mode " <> status)

      shell_loop(ShellState(
        state.prompt_count + 1,
        state.bindings,
        state.imports,
        state.types,
        history,
        state.functions,
        new_debug,
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
            state.debug,
          ))
        }

        False -> {
          // Exit raw mode so side effects print normally!
          let assert Ok(_) = tty.exit_raw()

          // Pass only the source strings into the evaluator
          let type_sources = list.map(state.types, fn(t) { t.1 })
          let function_sources = list.map(state.functions, fn(f) { f.1 })

          let result =
            evaluator.evaluate(
              input,
              state.bindings,
              state.imports,
              type_sources,
              function_sources,
              state.debug,
            )

          // Print evaluator output while still in normal mode
          io.print(result.output)

          // Re-enter raw mode for the next REPL prompt
          let assert Ok(_) = tty.enter_raw()

          // Identify all names just created (variables or functions)
          let defined_names = case result.new_binding {
            option.Some(b) -> b.names
            option.None ->
              case result.new_function {
                option.Some(f) -> [f.0]
                option.None -> []
              }
          }

          // Prune old bindings if any of their names were overwritten
          let base_bindings = case defined_names {
            [] -> state.bindings
            _ ->
              list.filter(state.bindings, fn(b) {
                !list.any(b.names, fn(n) { list.contains(defined_names, n) })
              })
          }
          let bindings = case result.new_binding {
            option.Some(binding) -> list.append(base_bindings, [binding])
            option.None -> base_bindings
          }

          // Prune old functions if their name was overwritten
          let base_functions = case defined_names {
            [] -> state.functions
            _ ->
              list.filter(state.functions, fn(f) {
                !list.contains(defined_names, f.0)
              })
          }
          let functions = case result.new_function {
            option.Some(f) -> list.append(base_functions, [f])
            option.None -> base_functions
          }

          // Prune old types
          let base_types = case result.new_type {
            option.Some(new_t) ->
              list.filter(state.types, fn(t) { t.0 != new_t.0 })
            option.None -> state.types
          }
          let types = case result.new_type {
            option.Some(t) -> list.append(base_types, [t])
            option.None -> base_types
          }

          let imports = case result.new_import {
            option.Some(imp) -> list.append(state.imports, [imp])
            option.None -> state.imports
          }

          shell_loop(ShellState(
            state.prompt_count + 1,
            bindings,
            imports,
            types,
            history,
            functions,
            state.debug,
          ))
        }
      }
    }
  }
}

/// Builds the autocompletion context (keywords, bindings, module exports) 
/// and passes control to the line reader.
fn read_command(prompt: String, state: ShellState) -> String {
  let keywords = [
    "let", "assert", "import", "type", "fn", "case", "if", "True", "False",
  ]

  // Use flat_map to get all variable names!
  let variables = list.flat_map(state.bindings, fn(b) { b.names })

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

/// Reads user input and continuously buffers lines if the AST is incomplete.
/// Uses the `...>` prompt for multiline continuations.
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

/// Resolves a module alias (e.g. `list`) to its full path (`gleam/list`) 
/// based on the shell's active imports.
fn resolve_alias(alias: String, imports: List(String)) -> String {
  let matched =
    list.find(imports, fn(imp) {
      string.ends_with(imp, "/" <> alias) || string.ends_with(imp, " " <> alias)
    })

  case matched {
    Ok(imp) -> {
      let path = string.replace(imp, "import ", "") |> string.trim()
      case string.split_once(path, on: " as ") {
        Ok(#(real_path, _)) -> string.trim(real_path)
        Error(_) -> path
      }
    }
    // Fallback: If not imported, assume they typed the full path (e.g. `h gleam/list`)
    Error(_) -> alias
  }
}
