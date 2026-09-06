//// The `bindings` module provides functionality for inspecting the current 
//// variable environment of the shell session.
////
//// When a user types a command to list active variables, this module formats 
//// and prints the active bindings that are currently persisted in the REPL's state.

// src/gsh/command/bindings.gleam

import gleam/int
import gleam/list
import gsh/evaluator/binding.{type Binding}
import gsh/input/terminal

/// Prints a formatted summary of all currently active variables in the REPL session.
/// Outputs a list of variable names followed by the total count.
pub fn show(bindings: List(Binding)) -> Nil {
  terminal.println("")
  terminal.println("Loaded bindings:")

  case bindings {
    [] -> terminal.println("  (none)")

    _ ->
      list.each(bindings, fn(binding) {
        terminal.println("  " <> display_name(binding))
      })
  }

  terminal.println("")
  terminal.println("Total: " <> int.to_string(list.length(bindings)))
}

/// Helper function to determine the printable name of a binding.
/// If exactly one variable is bound (e.g., `let x = 1` or `let Ok(val) = ...`), it uses that.
/// If it's a complex pattern matching multiple variables (e.g., `let #(a, b) = ...`), 
/// it falls back to printing the raw pattern string.
fn display_name(binding: Binding) -> String {
  case binding.names {
    [name] -> name
    _ -> binding.pattern
  }
}
