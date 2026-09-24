// The `router` module intercepts user input to check for built-in shell commands.
//
// Before sending input to the dynamic evaluator (which would try to compile 
// and execute it as Gleam code), the REPL passes the input here. If it matches 
// a known command (like `:h` for help, `:cc` for hot-reloading, or `:c` for clearing the screen), 
// the router flags it for immediate execution and tells the shell to skip evaluation.

// src/gsh/internal/command/router.gleam

import gleam/int
import gleam/string
import gsh/internal/command/bindings
import gsh/internal/command/help
import gsh/internal/command/history
import gsh/internal/command/version
import gsh/internal/evaluator/binding.{type Binding}
import gsh/internal/input/terminal

/// Represents the routing signal returned to the main shell loop.
pub type CommandResult {
  /// The command was recognized, executed, and the shell should prompt again.
  Handled

  /// The user requested to terminate the shell session (e.g., `k()`).
  Exit

  /// The user requested to clear the terminal screen.
  Clear

  /// The user requested to rebuild the host project and hot-reload active imports.
  Compile

  /// The user requested to toggle verbose AST and evaluator debugging logs.
  ToggleDebug

  Logs

  Obs

  /// `:pry`: attach to the oldest process paused at a pry point.
  PryAttach

  /// `:pry <id>`: attach to a specific paused process.
  PryAttachId(Int)

  /// `:pry list`: show every process waiting at a pry point.
  PryList

  /// `:pry on` / `:pry off`: enable or disable pry points.
  PryEnable(Bool)

  /// `:continue`: resume the attached process and return to the session.
  PryContinue

  /// The user requested documentation for a specific module or function target 
  /// (e.g., `h gleam/list` or `h list.map`).
  Help(String)

  /// The input did not match any built-in commands and should be sent 
  /// to the standard Gleam evaluator.
  NotCommand
}

/// Inspects the raw string input to route it to the appropriate built-in command.
///
/// **Routing Logic:**
/// * **Exact Matches:** Checks for fixed command strings like `:h`, `:q`, `:cc` or `:pry`.
/// * **Prefix Matches:** Intercepts commands with dynamic arguments, such as `:h <target>`,
///   extracting the target payload for the documentation scraper.
/// * **Context Injection:** Injects the current `bindings` and `history_entries`
///   so introspection commands like `:b` and `:hs` can print accurate summaries.
pub fn handle(
  input: String,
  bindings: List(Binding),
  history_entries: List(String),
) -> CommandResult {
  let trimmed = string.trim(input)

  case trimmed {
    ":d" | ":debug" -> ToggleDebug

    ":logs" -> Logs

    ":obs" -> Obs

    ":h" | ":help" -> {
      help.show()
      Handled
    }

    ":v" | ":version" -> {
      version.show()
      Handled
    }

    ":q" | ":quit" -> Exit

    ":c" | ":clear" -> Clear

    ":cc" | ":compile" -> Compile

    ":b" | ":bindings" -> {
      bindings.show(bindings)
      Handled
    }

    ":pry" -> PryAttach

    ":pry list" | ":pry ls" -> PryList

    ":pry on" -> PryEnable(True)

    ":pry off" -> PryEnable(False)

    ":continue" | ":cont" -> PryContinue

    ":hs" | ":history" -> {
      history.show(history_entries)
      Handled
    }

    ":pry " <> rest ->
      case int.parse(string.trim(rest)) {
        Ok(id) -> PryAttachId(id)
        Error(_) -> {
          terminal.println("Usage: :pry [list | <id> | on | off]")
          Handled
        }
      }

    _ -> {
      case string.starts_with(trimmed, ":h ") {
        True -> {
          let target = string.replace(trimmed, ":h ", "") |> string.trim()
          Help(target)
        }
        False -> NotCommand
      }
    }
  }
}
