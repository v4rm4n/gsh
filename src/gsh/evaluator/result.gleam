//// The `result` module defines the data structures returned by the evaluator.
////
//// When the REPL processes user input, it needs to know more than just what 
//// text to print to the screen. It needs to know if the execution succeeded, 
//// what type of error occurred if it failed, and whether there are any new 
//// variables, imports, or types that need to be saved into the shell's persistent state.

// src/gsh/evaluator/result.gleam

import gleam/option.{type Option}
import gsh/evaluator/binding.{type Binding}

/// Represents the complete outcome of a single REPL evaluation cycle.
pub type Evaluation {
  Evaluation(
    /// The final formatted string (including ANSI colors) to print to the terminal.
    output: String,
    /// True if the code compiled and ran without crashing; False otherwise.
    success: Bool,
    /// The specific category of error if the evaluation failed.
    error_kind: ErrorKind,
    /// A new variable assignment to save to state (e.g., `let x = 1`).
    new_binding: Option(Binding),
    /// A new module import to save to state (e.g., `import gleam/list`).
    new_import: Option(String),
    /// A new custom type definition to save to state (e.g., `pub type User { User }`).
    new_type: Option(String),
    /// A new custom function definition to save to state.
    new_function: Option(String),
  )
}

/// Classifies the outcome of the evaluation for error handling.
pub type ErrorKind {
  /// The evaluation completed successfully.
  NoError

  /// The code failed to compile (e.g., syntax error, type mismatch).
  CompileError

  /// The code compiled successfully but crashed the Erlang VM during 
  /// execution (e.g., division by zero, pattern match failure).
  RuntimeError
}
