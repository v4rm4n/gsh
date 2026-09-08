// The `bindings` module provides introspection capabilities for the shell's 
// lexical environment.
//
// It allows users to query the currently active REPL state to see exactly 
// which variables are available in memory, handling both simple assignments 
// and complex pattern-matched destructurings.

// src/gsh/command/bindings.gleam

import gleam/int
import gleam/list
import gsh/evaluator/binding.{type Binding}
import gsh/input/terminal

/// Renders a formatted, human-readable summary of all active variables 
/// currently tracked by the REPL's state manager.
/// 
/// **Output Format:**
/// * Prints an indented list of variable names or binding patterns.
/// * Gracefully handles empty states by printing `(none)`.
/// * Appends a summary footer with the total count of active bindings.
@internal
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

/// Resolves the most readable string representation for a given binding instance.
/// 
/// **Resolution Logic:**
/// * **Single Bindings:** Extracts and prints the direct variable name 
///   (e.g., `let x = 1` or `let Ok(val) = ...` yields `x` or `val`).
/// * **Complex Destructuring:** If a statement binds multiple variables simultaneously 
///   (e.g., `let #(a, b) = ...`), it falls back to printing the raw pattern string 
///   to accurately represent the tuple or record structure.
fn display_name(binding: Binding) -> String {
  case binding.names {
    [name] -> name
    _ -> binding.pattern
  }
}
