//// The `history` module provides functionality for reviewing previous commands.
////
//// When a user wants to see their session's execution history, this module 
//// formats and prints the chronologically ordered list of inputs.

// src/gsh/command/history.gleam

import gleam/int
import gleam/list
import gsh/input/terminal

/// Prints a numbered list of all previously executed commands in the current 
/// REPL session. If no commands have been entered yet, it safely notifies 
/// the user that the history is empty.
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
