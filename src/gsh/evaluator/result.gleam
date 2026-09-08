//// The `result` module defines the core data structures returned by the 
//// evaluation engine back to the REPL's main state loop.
////
//// When the shell processes user input, it needs more than just a raw string 
//// to print. It requires structured metadata detailing execution success, 
//// error classifications, and any new lexical artifacts (variables, imports, 
//// types, functions) that must be merged into the persistent `ShellState`.

// src/gsh/evaluator/result.gleam

import gleam/option.{type Option}
import gsh/evaluator/binding.{type Binding}

/// Encapsulates the complete lifecycle outcome of a single REPL evaluation prompt.
pub type Evaluation {
  Evaluation(
    /// The final formatted string (including ANSI syntax highlighting and debug 
    /// latency logs) ready to be printed to the terminal.
    output: String,
    /// `True` if the generated code successfully compiled and executed without 
    /// a VM crash; `False` otherwise.
    success: Bool,
    /// The specific classification of error if the evaluation failed.
    error_kind: ErrorKind,
    /// A successfully evaluated variable assignment (e.g., `let x = 1`) to be 
    /// appended to the active lexical scope.
    new_binding: Option(Binding),
    /// A successfully evaluated module import (e.g., `import gleam/list`) to be 
    /// tracked for subsequent file generations.
    new_import: Option(String),
    /// A custom type declaration (stored as `#(Name, Source)`) to be injected 
    /// into future evaluations.
    new_type: Option(#(String, String)),
    /// A custom function definition (stored as `#(Name, Source)`) to be injected 
    /// into future evaluations.
    new_function: Option(#(String, String)),
    active_bindings: Option(List(Binding)),
  )
}

/// Classifies the exact failure mode of an evaluation attempt.
pub type ErrorKind {
  /// The execution completed successfully without any compilation or VM faults.
  NoError

  /// The code failed the Gleam compiler's strict static analysis (e.g., syntax 
  /// error, type mismatch, or unknown identifier).
  CompileError

  /// The code compiled successfully but triggered a fatal exception within the 
  /// Erlang VM during runtime (e.g., division by zero, `let assert` failure).
  RuntimeError
}
