// The `binding` module defines the core data structures used to track, persist, 
// and safely shadow variable assignments across sequential REPL prompts.
//
// When a user evaluates an expression, the AST parser extracts the assignment 
// into a `Binding` record. The shell recursively injects these records into 
// subsequent temporary modules to maintain stateful lexical scope.

// src/gsh/internal/evaluator/binding.gleam

/// Distinguishes between standard variable assignments and strict pattern matching.
pub type BindingKind {
  /// A standard, infallible assignment (e.g., `let x = 5`).
  Let

  /// A strict, fallible pattern match that enforces structural assertions 
  /// (e.g., `let assert Ok(val) = result`).
  LetAssert
}

/// Represents a parsed and tracked variable assignment within the REPL session.
pub type Binding {
  Binding(
    /// The syntactical classification of the binding (`let` vs `let assert`).
    kind: BindingKind,
    /// The exact, raw source string of the assignment (e.g., `"let x = 5"`).
    source: String,
    /// The list of variable identifiers successfully extracted from the pattern. 
    /// For simple assignments this is `["x"]`. For tuple/record destructuring, 
    /// it contains all bound names (e.g., `["a", "b"]`).
    names: List(String),
    /// The left-hand side matching pattern (e.g., `"x"`, `"#(a, b)"`, or `"Ok(val)"`).
    pattern: String,
    /// The right-hand side expression that yielded the bound value (e.g., `"5"`).
    value: String,
  )
}
