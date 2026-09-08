//// The `history` module provides introspection into the REPL's chronological 
//// execution log.
////
//// It allows users to review their past inputs, formatting the raw string 
//// history into a numbered, human-readable list for quick reference.

// src/gsh/command/history.gleam

import gleam/int
import gleam/list
import gsh/input/terminal

/// Renders a sequentially numbered list of all previously executed commands 
/// within the current active session.
/// 
/// **Formatting Logic:**
/// * Iterates through the provided history list and prefixes each command 
///   with its chronological execution index (e.g., `1  let x = 5`).
/// * Safely handles fresh or recently cleared sessions by printing `(empty)`.
@internal
pub fn show(history: List(String)) -> Nil {
  terminal.println("")
  terminal.println("Command history:")

  case history {
    [] -> terminal.println("  (empty)")

    _ ->
      list.each(
        list.index_map(history, fn(command, index) {
          int.to_string(index + 1) <> "  " <> command
        }),
        terminal.println,
      )
  }

  terminal.println("")
}
