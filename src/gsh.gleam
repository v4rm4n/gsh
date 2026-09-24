//// `gsh` is the core entry point for the Interactive Gleam Shell.
////
//// It acts as a development orchestrator, providing four main capabilities:
//// 
//// 1. **Zero-Config Bootloader:** Intercepts CLI arguments to dynamically boot host 
////    applications in the background (e.g., `gleam run -m gsh -- my_app`).
//// 2. **Hot Code Swapping:** Provides a `compile` command that rebuilds the host 
////    project and reloads every module whose compiled code changed, without 
////    restarting the shell. It is disabled while connected to a remote node.
//// 3. **Persistent REPL:** A live-node interactive shell that maintains VM state, 
////    memoizes side effects, and safely handles runtime exceptions while toggling
////    terminal raw mode to ensure clean I/O. It supports standard expression evaluation, 
////    lexical variable shadowing, and convenient top-level module syntax (`fn`, `type`) 
////    for rapid prototyping.
//// 4. **Pry:** Application code can pause a process at a `pry` call. The shell 
////    attaches to it with `:pry`, evaluates code inside that process, and lets it 
////    carry on with `:continue`.

// src/gsh.gleam

import etch/erlang/tty
import gleam/erlang/atom
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/string
import gsh/internal/command/router as command
import gsh/internal/config
import gsh/internal/evaluator/binding
import gsh/internal/evaluator/docs
import gsh/internal/evaluator/evaluator
import gsh/internal/evaluator/parser
import gsh/internal/evaluator/runner
import gsh/internal/evaluator/target.{type Target, Local, Pried, Remote}
import gsh/internal/input/buffer
import gsh/internal/input/editor
import gsh/internal/input/key
import gsh/internal/input/reader
import gsh/internal/input/terminal
import gsh/internal/runtime/pry
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
    /// Active `let` bindings of the current scope: the main session's, or,
    /// while attached to a paused process, the pry session's.
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
    /// Tracks the target node for remote evaluations
    remote_node: option.Option(String),
    /// The paused process this shell is attached to, if any.
    pry: option.Option(PrySession),
  )
}

/// An attachment to a process paused at a `pry` call.
pub type PrySession {
  PrySession(
    paused: pry.Paused,
    /// The main session's bindings, restored on `:continue`. They stay out of
    /// the pry session: replaying them inside the paused process would miss
    /// the cache there and re-run their side effects.
    saved_bindings: List(binding.Binding),
  )
}

/// The main entry point. 
/// 
/// 1. Cleans up any orphaned evaluation files from previous crashed sessions.
/// 2. Intercepts trailing CLI arguments to boot background host applications.
/// 3. Injects a custom logger to prevent staircasing in background logs.
/// 4. Starts the pry server, so application processes can pause for the shell.
/// 5. Places the terminal into raw mode and starts the recursive REPL loop.
pub fn main() -> Nil {
  runtime.ensure_code_paths()

  // Survive crashes of processes spawned from REPL expressions (they are
  // linked to this process); they're reported before the next prompt instead.
  runtime.trap_exits()

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

  // ...and the package interface from a previous session, which describes
  // that session's REPL functions and types rather than this one's. A fresh
  // one is exported in the background, so calls to project functions show
  // their types from the first prompt.
  runner.clear_interface()
  process.spawn(runner.export_interface)

  // Keeps output from processes started through the shell lined up while the
  // terminal is in raw mode (see `use_output_proxy`).
  runtime.start_output_proxy()

  // 2. Wrap the logger to prevent staircasing in background jobs
  runtime.setup_logger()

  // 3. Load configuration from .gsh.toml
  let cfg = config.load()

  // Validate configured imports against available project modules
  let available_modules = get_import_completions()
  let valid_imports =
    list.filter(cfg.default_imports, fn(imp) {
      let path = string.replace(imp, "import ", "") |> string.trim()
      let real_path = case string.split_once(path, on: " as ") {
        Ok(#(p, _)) -> string.trim(p)
        Error(_) -> path
      }

      case list.contains(available_modules, real_path) {
        True -> True
        False -> {
          // Print a yellow warning to the terminal and drop the invalid import
          terminal.println(
            "\u{001b}[33mwarning:\u{001b}[0m Module '"
            <> real_path
            <> "' specified in [tools.gsh] imports not found. Ignoring.",
          )
          False
        }
      }
    })

  // Parse Networking Flags
  let raw_args = runtime.get_args()
  let #(sname, name, cookie, remsh, app_args) =
    parse_network_args(
      raw_args,
      option.None,
      option.None,
      option.None,
      option.None,
      [],
    )

  let network = case sname, name, remsh {
    option.Some(n), _, _ -> option.Some(runtime.start_network(n, "shortnames"))
    _, option.Some(n), _ -> option.Some(runtime.start_network(n, "longnames"))
    _, _, option.Some(_) ->
      option.Some(runtime.start_network(
        "gsh_" <> int.to_string(runtime.system_time()),
        "shortnames",
      ))
    _, _, option.None -> option.None
  }

  let network_up = case network {
    option.Some(Ok(Nil)) -> True
    option.Some(Error(err)) -> {
      terminal.println(
        "\u{001b}[31merror:\u{001b}[0m Could not start distribution: " <> err,
      )
      False
    }
    option.None -> False
  }

  // set_cookie raises on a node that isn't alive
  case network_up, cookie {
    True, option.Some(c) -> runtime.set_cookie(c)
    _, _ -> Nil
  }

  // 4. Start the pry server before booting apps, so they can pause right away
  pry.start_server(process.self())

  // Use the filtered `app_args` instead of `cli_args` for booting background apps
  let apps_to_boot =
    list.append(cfg.auto_boot_apps, app_args)
    |> list.unique()

  case list.is_empty(apps_to_boot) {
    True -> Nil
    False -> {
      terminal.println("Booting background applications...")
      runtime.use_output_proxy(True)
      list.each(apps_to_boot, fn(app_module) {
        case runtime.boot_app(app_module) {
          Ok(pid) ->
            terminal.println(app_module <> " -> " <> string.inspect(pid))
          Error(err) -> terminal.println(app_module <> " -> Failed: " <> err)
        }
      })
      runtime.use_output_proxy(False)
      terminal.println("")
      process.sleep(50)
    }
  }

  // 5. Start the shell as usual
  let assert Ok(_) = tty.enter_raw()
  terminal.enable_bracketed_paste()

  banner()

  let valid_remsh = case remsh {
    option.Some(target) -> {
      case runtime.ping_node(target) {
        Ok(Nil) -> {
          terminal.println(
            "\u{001b}[36mConnected to remote node: " <> target <> "\u{001b}[0m",
          )
          option.Some(target)
        }
        Error(diagnostic) -> {
          terminal.println(
            "\u{001b}[31merror:\u{001b}[0m Could not reach remote node '"
            <> target
            <> "'. (Wrong cookie or name?)",
          )
          terminal.println("  " <> diagnostic)
          terminal.println(
            "\u{001b}[33mwarning:\u{001b}[0m Falling back to local REPL.",
          )
          option.None
        }
      }
    }
    option.None -> option.None
  }

  // Shell state seeded with necessary stuff
  shell_loop(ShellState(
    prompt_count: 1,
    bindings: [],
    imports: valid_imports,
    types: [],
    history: [],
    functions: [],
    debug: False,
    remote_node: valid_remsh,
    pry: option.None,
  ))

  terminal.disable_bracketed_paste()
  let assert Ok(_) = tty.exit_raw()

  Nil
}

/// Recursively strips network flags from standard CLI arguments
fn parse_network_args(
  args: List(String),
  sname: option.Option(String),
  name: option.Option(String),
  cookie: option.Option(String),
  remsh: option.Option(String),
  others: List(String),
) -> #(
  option.Option(String),
  option.Option(String),
  option.Option(String),
  option.Option(String),
  List(String),
) {
  case args {
    ["--sname", val, ..rest] ->
      parse_network_args(rest, option.Some(val), name, cookie, remsh, others)
    ["--name", val, ..rest] ->
      parse_network_args(rest, sname, option.Some(val), cookie, remsh, others)
    ["--cookie", val, ..rest] ->
      parse_network_args(rest, sname, name, option.Some(val), remsh, others)
    ["--remsh", val, ..rest] ->
      parse_network_args(rest, sname, name, cookie, option.Some(val), others)
    [other, ..rest] ->
      parse_network_args(
        rest,
        sname,
        name,
        cookie,
        remsh,
        list.append(others, [other]),
      )
    [] -> #(sname, name, cookie, remsh, others)
  }
}

/// Prints the OTP/ERTS version and the GSH startup banner.
fn banner() -> Nil {
  terminal.println(system_version())
  {
    "Interactive Gleam (GSH "
    <> app_version(atom.create("gsh"))
    <> ") - press Ctrl+C to exit (type :h ENTER for help)"
  }
  |> terminal.println()
}

/// The recursive heartbeat of the REPL. 
/// Prompts for input, processes it, and recurses with the updated state.
fn shell_loop(state: ShellState) -> Nil {
  report_exits()

  let prompt = case state.pry {
    option.Some(session) -> "pry(" <> session.paused.label <> ")> "
    option.None -> "gsh(" <> int.to_string(state.prompt_count) <> ")> "
  }

  let input = read_command(prompt, state)

  case input {
    "" -> shell_loop(state)

    _ -> handle_input(input, state)
  }
}

/// Where the next evaluation runs: inside the attached paused process,
/// on the remote node, or in this shell's own process.
fn evaluation_target(state: ShellState) -> Target {
  case state.pry, state.remote_node {
    option.Some(session), _ -> Pried(session.paused.pid, session.paused.id)
    option.None, option.Some(node) -> Remote(node)
    option.None, option.None -> Local
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
/// * **Hot Swapping:** Intercepts the `compile` command to rebuild the project 
///   and reload every module whose compiled code changed.
/// * **Pry:** Attaches to and resumes processes paused at `pry` calls.
fn handle_input(input: String, state: ShellState) -> Nil {
  let history = list.append(state.history, [input])

  case command.handle(input, state.bindings, state.history) {
    command.Handled ->
      shell_loop(
        ShellState(..state, prompt_count: state.prompt_count + 1, history:),
      )

    command.Exit -> {
      let _ = tty.exit_raw()
      terminal.println("Goodbye.")
      Nil
    }

    command.Clear -> {
      terminal.clear_screen()
      shell_loop(
        ShellState(..state, prompt_count: state.prompt_count + 1, history:),
      )
    }

    command.Compile -> {
      case state.remote_node {
        // Remote hot loading is disabled: rebuilding locally would make gsh
        // type-check against code the remote node isn't running.
        option.Some(target) ->
          terminal.println(
            "\u{001b}[33mwarning:\u{001b}[0m :cc is disabled while connected to "
            <> target
            <> ". Ship code changes with a deploy.",
          )

        option.None ->
          case runner.build_project() {
            Ok("") -> terminal.println("Noop")

            Ok(output) -> {
              terminal.println(output)

              // The project changed, so refresh the types of its functions.
              runner.export_interface()

              // Reload every module whose .beam changed on disk, like IEx's recompile
              case runtime.reload_modified() {
                // Nothing already loaded changed. New modules load on first use.
                [] -> terminal.println("Ok")
                mods ->
                  terminal.println(
                    "Ok (reloaded: "
                    <> string.join(
                      list.map(mods, string.replace(_, "@", "/")),
                      ", ",
                    )
                    <> ")",
                  )
              }
            }

            Error(#(_, output)) -> {
              terminal.println(output)
              terminal.println("Error")
            }
          }
      }

      shell_loop(
        ShellState(..state, prompt_count: state.prompt_count + 1, history:),
      )
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

      shell_loop(
        ShellState(..state, prompt_count: state.prompt_count + 1, history:),
      )
    }

    command.ToggleDebug -> {
      let new_debug = !state.debug
      let status = case new_debug {
        True -> "enabled"
        False -> "disabled"
      }
      terminal.println("Debug mode " <> status)

      shell_loop(
        ShellState(
          ..state,
          prompt_count: state.prompt_count + 1,
          history:,
          debug: new_debug,
        ),
      )
    }

    command.Logs -> {
      // 1. Clear the screen for the dashboard
      terminal.clear_screen()

      // 2. Fetch the logs from the ETS buffer (via the FFI we added)
      let logs = runtime.get_logs()

      // 3. Draw the UI
      draw_log_box(logs)

      // 4. Wait for the user to press 'q'
      wait_for_q()

      // 5. Clear the screen again and return to the normal REPL state
      terminal.clear_screen()

      shell_loop(ShellState(..state, history:))
    }

    command.Obs -> {
      case runtime.start_observer() {
        Ok(_) -> terminal.println("Launching Observer GUI...")
        Error(err) -> terminal.println("\u{001b}[31merror:\u{001b}[0m " <> err)
      }

      shell_loop(ShellState(..state, history:))
    }

    command.PryAttach -> {
      let state = ShellState(..state, history:)

      case state.pry {
        option.Some(session) -> {
          terminal.println(
            "Already attached to "
            <> pry.pid_text(session.paused.pid)
            <> ". Type :continue first.",
          )
          shell_loop(ShellState(..state, prompt_count: state.prompt_count + 1))
        }

        option.None ->
          case pry.take() {
            Ok(paused) -> shell_loop(attach(state, paused))
            Error(Nil) -> {
              terminal.println(nothing_waiting(state))
              shell_loop(
                ShellState(..state, prompt_count: state.prompt_count + 1),
              )
            }
          }
      }
    }

    command.PryAttachId(id) -> {
      let state = ShellState(..state, history:)

      case state.pry {
        option.Some(session) -> {
          terminal.println(
            "Already attached to "
            <> pry.pid_text(session.paused.pid)
            <> ". Type :continue first.",
          )
          shell_loop(ShellState(..state, prompt_count: state.prompt_count + 1))
        }

        option.None ->
          case pry.take_id(id) {
            Ok(paused) -> shell_loop(attach(state, paused))
            Error(Nil) -> {
              terminal.println(
                "No process is waiting as #"
                <> int.to_string(id)
                <> ". Type :pry list to see the waiting ones.",
              )
              shell_loop(
                ShellState(..state, prompt_count: state.prompt_count + 1),
              )
            }
          }
      }
    }

    command.PryList -> {
      case pry.list() {
        [] -> terminal.println(nothing_waiting(state))
        waiting -> {
          terminal.println("Waiting at pry points:")
          list.each(waiting, fn(paused) {
            terminal.println(
              "  #"
              <> int.to_string(paused.id)
              <> "  "
              <> pry.pid_text(paused.pid)
              <> "  \""
              <> paused.label
              <> "\"  "
              <> paused.location,
            )
          })
          terminal.println("Type :pry <id> to attach, or :pry for the oldest.")
        }
      }

      shell_loop(
        ShellState(..state, prompt_count: state.prompt_count + 1, history:),
      )
    }

    command.PryContinue -> {
      let state =
        ShellState(..state, prompt_count: state.prompt_count + 1, history:)

      case state.pry {
        option.None -> {
          terminal.println("Not attached to a paused process.")
          shell_loop(state)
        }

        option.Some(session) -> {
          pry.resume(session.paused.pid, session.paused.id)
          terminal.println("Resumed " <> pry.pid_text(session.paused.pid))
          // Give the resumed process a moment, so whatever it prints straight
          // away lands before the prompt instead of after it.
          process.sleep(50)
          announce_waiting(pry.waiting())

          shell_loop(
            ShellState(
              ..state,
              pry: option.None,
              bindings: session.saved_bindings,
            ),
          )
        }
      }
    }

    command.PryEnable(on) -> {
      let released = pry.set_enabled(on)

      case on, released {
        True, _ -> terminal.println("Pry points enabled.")
        False, 0 -> terminal.println("Pry points disabled.")
        False, n ->
          terminal.println(
            "Pry points disabled. Resumed "
            <> int.to_string(n)
            <> " waiting process(es).",
          )
      }

      shell_loop(
        ShellState(..state, prompt_count: state.prompt_count + 1, history:),
      )
    }

    command.NotCommand -> {
      let is_duplicate_import =
        string.starts_with(input, "import ")
        && list.contains(state.imports, input)

      case is_duplicate_import {
        True -> {
          terminal.println("Discarded duplicate import")

          shell_loop(
            ShellState(..state, prompt_count: state.prompt_count + 1, history:),
          )
        }

        False -> {
          // Exit raw mode so side effects print normally!
          let assert Ok(_) = tty.exit_raw()

          // Processes the code spawns inherit the output proxy, so their
          // output stays lined up after we're back in raw mode.
          runtime.use_output_proxy(True)
          let result =
            evaluator.evaluate(
              input,
              state.bindings,
              state.imports,
              state.types,
              state.functions,
              state.debug,
              state.prompt_count,
              evaluation_target(state),
            )
          runtime.use_output_proxy(False)

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

          ShellState(
            ..state,
            prompt_count: state.prompt_count + 1,
            bindings:,
            imports:,
            types:,
            history:,
            functions:,
          )
          |> detach_if_exited
          |> shell_loop
        }
      }
    }
  }
}

/// Attaches the shell to a paused process: switches to a fresh binding scope,
/// then binds the value passed to `pry` and prints it.
fn attach(state: ShellState, paused: pry.Paused) -> ShellState {
  terminal.println(
    "Attached to #"
    <> int.to_string(paused.id)
    <> " "
    <> pry.pid_text(paused.pid)
    <> " at \""
    <> paused.label
    <> "\" ("
    <> paused.location
    <> ")",
  )

  let name = pry_variable(paused.label)
  let input =
    "let " <> name <> " = gsh_pry_value(" <> int.to_string(paused.id) <> ")"

  let assert Ok(_) = tty.exit_raw()
  runtime.use_output_proxy(True)
  let result =
    evaluator.evaluate(
      input,
      [],
      state.imports,
      state.types,
      state.functions,
      state.debug,
      state.prompt_count,
      Pried(paused.pid, paused.id),
    )
  runtime.use_output_proxy(False)
  io.print(name <> " = " <> result.output)
  let assert Ok(_) = tty.enter_raw()

  announce_waiting(paused.waiting)

  let bindings = case result.new_binding {
    option.Some(b) -> [b]
    option.None -> []
  }

  ShellState(
    ..state,
    prompt_count: state.prompt_count + 1,
    bindings:,
    pry: option.Some(PrySession(paused:, saved_bindings: state.bindings)),
  )
}

/// Returns to the main session if the attached process has died
/// (for example, the code evaluated in it crashed it).
fn detach_if_exited(state: ShellState) -> ShellState {
  case state.pry {
    option.Some(session) ->
      case process.is_alive(session.paused.pid) {
        True -> state
        False -> {
          terminal.println(
            pry.pid_text(session.paused.pid)
            <> " exited. Back to the main session.",
          )
          ShellState(
            ..state,
            pry: option.None,
            bindings: session.saved_bindings,
          )
        }
      }
    option.None -> state
  }
}

/// Reports linked processes that crashed since the last prompt.
fn report_exits() -> Nil {
  list.each(runtime.drain_exits(), fn(exit) {
    terminal.println(
      "\u{001b}[33m[exit]\u{001b}[0m " <> exit.0 <> " exited: " <> exit.1,
    )
  })
}

fn nothing_waiting(state: ShellState) -> String {
  case state.remote_node {
    option.Some(node) ->
      "No process is waiting at a pry point. Pry attaches to processes on this node, not "
      <> node
      <> "."
    option.None -> "No process is waiting at a pry point."
  }
}

fn announce_waiting(count: Int) -> Nil {
  case count {
    0 -> Nil
    n ->
      terminal.println(
        int.to_string(n) <> " more waiting at pry points. Type :pry to attach.",
      )
  }
}

/// The variable a pried value is bound to: the label when it's a valid Gleam
/// variable name, otherwise `pried`.
fn pry_variable(label: String) -> String {
  let reserved = [
    "as", "assert", "auto", "case", "const", "delegate", "derive", "echo",
    "else", "fn", "if", "implement", "import", "let", "macro", "opaque", "panic",
    "pub", "test", "todo", "type", "use",
  ]
  let lower = "abcdefghijklmnopqrstuvwxyz"
  let tail = lower <> "0123456789_"

  case string.to_graphemes(label) {
    [first, ..rest] -> {
      let valid =
        string.contains(lower, first)
        && list.all(rest, fn(g) { string.contains(tail, g) })
        && !list.contains(reserved, label)
      case valid {
        True -> label
        False -> "pried"
      }
    }
    [] -> "pried"
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

  let line = editor.read_line(current_prompt, history, completions, current)

  case line == "\u{0018}" {
    True -> ""
    // Cancel evaluation and reset the prompt
    False -> {
      let combined = case current {
        "" -> line
        _ -> current <> "\n" <> line
      }

      case buffer.is_complete(combined) {
        True -> combined
        False -> read_lines(prompt, history, combined, False, completions)
      }
    }
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

fn get_import_completions() -> List(String) {
  // 1. Scan local project source files
  let local_modules = case simplifile.get_files("src") {
    Ok(files) -> {
      list.filter_map(files, fn(file) {
        case string.ends_with(file, ".gleam") {
          True -> {
            let module =
              file
              |> string.replace("./src/", "")
              |> string.replace("src/", "")
              |> string.replace(".gleam", "")

            Ok(module)
          }
          False -> Error(Nil)
        }
      })
    }
    Error(_) -> []
  }

  // 2. Scan third-party dependencies downloaded by Gleam
  let package_modules = case simplifile.get_files("build/packages") {
    Ok(files) -> {
      list.filter_map(files, fn(file) {
        case string.ends_with(file, ".gleam") {
          True -> {
            // A file path looks like: build/packages/gleam_stdlib/src/gleam/list.gleam
            // We split on "/src/" and keep everything after it.
            case string.split_once(file, on: "/src/") {
              Ok(#(_before, after)) -> Ok(string.replace(after, ".gleam", ""))
              Error(_) -> Error(Nil)
            }
          }
          False -> Error(Nil)
        }
      })
    }
    Error(_) -> []
  }

  // 3. Combine and deduplicate the list
  list.append(local_modules, package_modules)
  |> list.unique()
}

/// Prints the captured logs cleanly to the screen without heavy borders.
fn draw_log_box(logs: List(String)) -> Nil {
  terminal.println("\u{001b}[1m--- Background Logs ---\u{001b}[0m\n")

  case logs {
    [] -> terminal.println("\u{001b}[90mNo logs captured yet.\u{001b}[0m")
    _ -> {
      list.each(logs, fn(log) { terminal.println(string.trim(log)) })
    }
  }

  terminal.println("\n\u{001b}[90mPress 'q' to return to REPL\u{001b}[0m")
}

/// A blocking recursive loop that swallows all keystrokes until 'q' is pressed.
fn wait_for_q() -> Nil {
  let pressed = reader.read_key()

  case pressed {
    key.Character("q") | key.Character("Q") -> Nil
    _ -> wait_for_q()
  }
}
