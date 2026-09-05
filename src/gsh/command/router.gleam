//// The `router` module intercepts user input to check for built-in shell commands.
////
//// Before sending input to the dynamic evaluator (which would try to compile 
//// and execute it as Gleam code), the REPL passes the input here. If it matches 
//// a known command (like `h()` for help or `clear` to wipe the screen), the router 
//// executes it immediately and tells the shell loop to skip evaluation.

// src/gsh/command/router.gleam

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

  /// The user requested to recompile the surrounding Mix/Gleam project.
  Compile

  /// The input did not match any built-in commands and should be sent 
  /// to the standard Gleam evaluator.
  NotCommand
}

/// Inspects the raw string input to route it to the appropriate built-in command.
/// 
/// It requires access to the current `bindings` and `history_entries` state 
/// so that commands like `l()` (list bindings) and `history()` have the 
/// necessary context to print accurate summaries.
pub fn handle(
  input: String,
  bindings: List(Binding),
  history_entries: List(String),
) -> CommandResult {
  case input {
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

    _ -> NotCommand
  }
}
