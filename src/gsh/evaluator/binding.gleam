//// The `binding` module defines the data structures used to track and persist 
//// variable assignments across REPL prompts.
////
//// When a user evaluates an expression like `let x = 10`, the evaluator 
//// parses it into a `Binding` record. This allows the shell to dynamically 
//// inject previous variables into the top of the generated AST for subsequent 
//// evaluations, creating the illusion of persistent local scope.

// src/gsh/evaluator/binding.gleam

import gleam/option.{type Option}

/// Distinguishes between a standard variable assignment and a strict pattern match.
pub type BindingKind {
  /// A standard assignment (e.g., `let x = 5`).
  Let

  /// A strict pattern match that can crash the evaluation if it fails 
  /// (e.g., `let assert Ok(val) = result`).
  LetAssert
}

/// Represents a single tracked variable assignment within the REPL session.
pub type Binding {
  Binding(
    /// Whether this is a `let` or `let assert` binding.
    kind: BindingKind,
    /// The full, raw source code of the assignment (e.g., `"let x = 5"`).
    source: String,
    /// The simple identifier name if this is a basic assignment (e.g., `Some("x")`).
    /// If this is a complex destructuring pattern, this will be `None`.
    name: Option(String),
    /// The left-hand side pattern of the assignment (e.g., `"x"` or `"Ok(val)"`).
    pattern: String,
    /// The right-hand side expression that produced the value (e.g., `"5"`).
    value: String,
  )
}
