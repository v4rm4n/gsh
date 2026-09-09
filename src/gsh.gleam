//// `gsh` is the core entry point for the Interactive Gleam Shell.
////
//// It acts as a development orchestrator, providing three main capabilities:
//// 
//// 1. **Zero-Config Bootloader:** Intercepts CLI arguments to dynamically boot host 
////    applications in the background (e.g., `gleam run -m gsh -- my_app`).
//// 2. **Hot Code Swapping:** Provides a `compile` command to manually rebuild the host 
////    project and trigger Erlang `code:purge` and `code:load_file`, hot-swapping live 
////    module updates without restarting the shell.
//// 3. **Persistent REPL:** A live-node interactive shell that maintains VM state, 
////    memoizes side effects, and safely handles runtime exceptions while toggling
////    terminal raw mode to ensure clean I/O. It supports standard expression evaluation, 
////    lexical variable shadowing, and convenient top-level module syntax (`fn`, `type`) 
////    for rapid prototyping.

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
import gsh/internal/command/router as command
import gsh/internal/evaluator/binding
import gsh/internal/evaluator/docs
import gsh/internal/evaluator/evaluator
import gsh/internal/evaluator/parser
import gsh/internal/evaluator/runner
import gsh/internal/input/buffer
import gsh/internal/input/editor
import gsh/internal/input/terminal
import gsh/internal/runtime/runtime.{app_version, system_version}
import simplifile

/// Holds the persistent state of the shell session across evaluations.
/// This state is passed recursively through the REPL loop to seamlessly inject 
/// historical context into each dynamically generated module.
pub type ShellState {
  ShellState(
    /// Increments on every REPL execution to guarantee uniquely named Erlang 
    /// modules (e.g., `gsh_eval_1`, `gsh_eval_2`), preventing VM cache collisions.
    prompt_count: Int,
    /// Active `let` bindings. The shell intelligently drops older bindings 
    /// only when all of their extracted variables have been fully shadowed.
    bindings: List(binding.Binding),
    /// Active `import` statements. Checked sequentially to discard duplicates.
    imports: List(String),
    /// Custom `type` declarations. Stored as a tuple of `#(Type_Name, Source_String)`. 
    /// Redefining a type automatically prunes the old source to prevent compiler crashes.
    types: List(#(String, String)),
    /// The raw input strings of previously executed commands, used by the 
    /// raw-mode editor for Arrow Up/Arrow Down traversal.
    history: List(String),
    /// Top-level `fn` definitions. Stored as a tuple of `#(Function_Name, Source_String)`. 
    /// When redefined, the old source string is strictly purged from the active state 
    /// to satisfy the Gleam compiler's unique-name constraints.
    functions: List(#(String, String)),
    /// Toggles verbose output for debugging the internal AST parsing and 
    /// evaluation pipeline.
    debug: Bool,
  )
}

/// The main entry point. 
/// 
/// 1. Cleans up any orphaned evaluation files from previous crashed sessions.
/// 2. Intercepts trailing CLI arguments to boot background host applications.
/// 3. Injects a custom logger to prevent staircasing in background logs.
/// 4. Places the terminal into raw mode and starts the recursive REPL loop.
pub fn main() -> Nil {
  runtime.ensure_code_paths()

  // 1. Clean up any orphaned `gsh_eval_X.gleam` files from previous crashes
  case simplifile.read_directory("src") {
    Ok(files) -> {
      list.each(files, fn(file) {
        case string.starts_with(file, "gsh_eval_") {
          True -> {
            let _ = simplifile.delete("src/" <> file)
            Nil
          }
          False -> Nil
        }
      })
    }
    Error(_) -> Nil
  }

  // 2. Intercept ALL CLI arguments and boot them
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

  // 3. Wrap the logger to prevent staircasing in background jobs
  runtime.fix_logger_staircase()

  // 4. Start the shell as usual
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
    "Interactive Gleam (GSH ~s) - press Ctrl+C to exit (type :h ENTER for help)",
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

/// Routes the user's input to internal shell commands (e.g., `exit`, `clear`, `compile`) 
/// or passes it to the evaluator engine for execution.
/// 
/// **Key Responsibilities:**
/// * **I/O Management:** Temporarily exits terminal raw mode during evaluation 
///   so that side-effects (like `io.println`) and background server logs render correctly.
/// * **State Pruning:** When passing code to the evaluator, it intelligently filters the 
///   returned AST bindings against the historical state, safely pruning old source strings 
///   when a variable, type, or function is fully shadowed or redefined.
/// * **Hot Swapping:** Intercepts the `compile` command to trigger background host 
///   rebuilds and automatically hot-reloads the VM caches for all active imports.
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

          // Auto-reload all active imports to reflect the new disk artifacts
          list.each(state.imports, fn(imp) {
            let path = string.replace(imp, "import ", "") |> string.trim()
            let real_path = case string.split_once(path, on: " as ") {
              Ok(#(p, _)) -> string.trim(p)
              Error(_) -> path
            }
            runtime.hot_reload(real_path)
          })

          terminal.println("Ok (Imports hot-reloaded)")
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
              state.prompt_count,
            )

          // Print evaluator output while still in normal mode
          io.print(result.output)

          // Re-enter raw mode for the next REPL prompt
          let assert Ok(_) = tty.enter_raw()

          // Identify all names just created (variables, functions, OR imports!)
          let defined_names = case result.new_binding {
            option.Some(b) -> b.names
            option.None ->
              case result.new_function {
                option.Some(f) -> [f.0]
                option.None ->
                  // ADD THIS BRANCH:
                  case result.new_import {
                    option.Some(imp) -> parser.get_imported_names(imp)
                    option.None -> []
                  }
              }
          }

          // Start from pruned bindings if evaluator auto-cleared stale host code references
          let current_bindings = case result.active_bindings {
            option.Some(active) -> active
            option.None -> state.bindings
          }

          // Only prune an old binding if it was shadowed AND the new input doesn't read it on the RHS
          let base_bindings = case defined_names {
            [] -> current_bindings
            _ ->
              list.filter(current_bindings, fn(b) {
                list.any(b.names, fn(n) {
                  let is_rebound = list.contains(defined_names, n)
                  let is_self_referenced = string.contains(input, n)

                  // Keep the old binding if it is self-referenced (e.g. `let x = f(x)`)
                  !is_rebound || is_self_referenced
                })
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

/// Constructs the predictive autocompletion dictionary for the current REPL prompt 
/// before passing control to the raw-mode line reader.
/// 
/// **Injected Context:**
/// * **Keywords:** Standard Gleam syntax primitives (e.g., `let`, `fn`, `case`).
/// * **Variables:** Dynamically extracted from all active `let` bindings in the state.
/// * **Module Exports:** Maps active `import` statements to their underlying Erlang 
///   `.beam` modules, using FFI to scrape and append all publicly exported functions 
///   under their correct alias (e.g., `list.map`, `list.filter`).
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

  let import_completions = get_import_completions()

  let completions =
    keywords
    |> list.append(variables)
    |> list.append(module_completions)
    |> list.append(import_completions)

  read_lines(prompt, state.history, "", True, completions)
}

/// Recursively reads and buffers user input until a syntactically complete 
/// Gleam expression or module definition is formed.
/// 
/// **Key Behaviors:**
/// * **Multiline Prompting:** Shifts from the standard numbered prompt (e.g., `gsh(1)>`) 
///   to a continuation prompt (`...>`) when an expression spans multiple lines.
/// * **AST Validation:** Evaluates the accumulated string using `buffer.is_complete` 
///   to check for unclosed delimiters (like brackets, braces, or quotes). If the syntax 
///   tree is incomplete, it blocks execution and recurses to prompt for the next line.
/// * **Accumulation:** Safely concatenates successive inputs with newline characters 
///   to preserve structural formatting for the evaluator and syntax highlighter.
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

/// Resolves a module alias (e.g., `list` or a custom `l`) back to its fully qualified 
/// package path (e.g., `gleam/list`) by scanning the shell's active `import` history.
/// 
/// **Resolution Logic:**
/// * **Standard Imports:** Matches paths ending in the alias (e.g., extracting `gleam/list` from `list`).
/// * **Custom Aliases:** Safely splits and extracts the true path from `as` bindings (e.g., `import gleam/io as print`).
/// * **Fallback:** If no matching import is found in the state, it assumes the user provided 
///   the full path directly (e.g., `h gleam/list`) and returns the input untouched.
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

// Add this helper to scan the src directory
fn get_import_completions() -> List(String) {
  case simplifile.get_files("src") {
    Ok(files) -> {
      list.filter_map(files, fn(file) {
        case string.ends_with(file, ".gleam") {
          True -> {
            let module =
              file
              |> string.replace("./src/", "")
              // Catch the dot-slash
              |> string.replace("src/", "")
              // Catch the standard
              |> string.replace(".gleam", "")

            Ok(module)
          }
          False -> Error(Nil)
        }
      })
    }
    Error(_) -> []
  }
}
