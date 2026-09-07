//// The `router` module intercepts user input to check for built-in shell commands.
////
//// Before sending input to the dynamic evaluator (which would try to compile 
//// and execute it as Gleam code), the REPL passes the input here. If it matches 
//// a known command (like `h()` for help, `compile` for hot-reloading, or `clear`), 
//// the router flags it for immediate execution and tells the shell to skip evaluation.

// src/gsh/command/router.gleam

import gleam/string
import gsh/command/bindings
import gsh/command/help
import gsh/command/history
import gsh/command/version
import gsh/evaluator/binding.{type Binding}

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
/// * **Exact Matches:** Checks for fixed command strings like `h()`, `k()`, or `compile`.
/// * **Prefix Matches:** Intercepts commands with dynamic arguments, such as `h <target>`, 
///   extracting the target payload for the documentation scraper.
/// * **Context Injection:** Injects the current `bindings` and `history_entries` 
///   so introspection commands like `l()` and `history()` can print accurate summaries.
pub fn handle(
  input: String,
  bindings: List(Binding),
  history_entries: List(String),
) -> CommandResult {
  let trimmed = string.trim(input)

  case trimmed {
    ":debug" | "debug" | "debug()" -> ToggleDebug

    "h()" -> {
      help.show()
      Handled
    }

    "v()" -> {
      version.show()
      Handled
    }

    "k()" -> Exit

    // Cleaner than `clear()`
    "clear" -> Clear

    "compile" -> Compile

    "l()" -> {
      bindings.show(bindings)
      Handled
    }

    "history()" -> {
      history.show(history_entries)
      Handled
    }

    _ -> {
      // Check for dynamic prefix commands!
      case string.starts_with(trimmed, "h ") {
        True -> {
          let target = string.replace(trimmed, "h ", "") |> string.trim()
          Help(target)
        }
        False -> NotCommand
      }
    }
  }
}
