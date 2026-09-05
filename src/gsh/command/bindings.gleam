//// The `bindings` module provides functionality for inspecting the current 
//// variable environment of the shell session.
////
//// When a user types a command to list active variables, this module formats 
//// and prints the active bindings that are currently persisted in the REPL's state.

// src/gsh/command/bindings.gleam

import gleam/int
import gleam/list
import gleam/option.{None, Some}
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
/// If a standard variable name is available (e.g., `let x = 1`), it uses that.
/// If the binding was a complex pattern match (e.g., destructuring), it falls 
/// back to printing the raw pattern string.
fn display_name(binding: Binding) -> String {
  case binding.name {
    Some(name) -> name
    None -> binding.pattern
  }
}
