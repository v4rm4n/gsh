// The `bindings` module provides introspection capabilities for the shell's
// lexical environment.
//
// It allows users to query the currently active REPL state to see exactly
// which variables are available in memory, handling both simple assignments
// and complex pattern-matched destructurings.

// src/gsh/internal/command/bindings.gleam

import gleam/int
import gleam/list
import gsh/internal/evaluator/binding.{type Binding}
import gsh/internal/input/terminal

/// Renders a formatted, human-readable summary of every variable currently
/// in scope in the REPL session.
///
/// **Output Format:**
/// * Prints an indented list of variable names, one per line.
/// * Gracefully handles empty states by printing `(none)`.
/// * Appends a summary footer with the total count of variables in scope.
pub fn show(bindings: List(Binding)) -> Nil {
  let names = visible_names(bindings)

  terminal.println("")
  terminal.println("Loaded bindings:")

  case names {
    [] -> terminal.println("  (none)")
    _ -> list.each(names, fn(name) { terminal.println("  " <> name) })
  }

  terminal.println("")
  terminal.println("Total: " <> int.to_string(list.length(names)))
}

/// Every variable currently in scope, in the order it was first bound.
///
/// Destructuring bindings (`let #(a, b) = ...`) contribute each of their
/// names. A variable that was rebound later (`let x = x + 1`) is listed once,
/// because only its latest binding is visible, even though the session keeps
/// every earlier binding to replay them in order.
fn visible_names(bindings: List(Binding)) -> List(String) {
  bindings
  |> list.flat_map(fn(binding) { binding.names })
  |> list.unique
}
