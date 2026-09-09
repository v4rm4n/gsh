// The `source` module provides boilerplate code generation helpers for the evaluator.
//
// When the evaluator constructs a temporary `gsh_eval_X.gleam` file, it uses 
// this module to inject hidden standard imports under safely aliased namespaces 
// (e.g., `gsh_internal_string`). This prevents variable collisions if a user 
// explicitly imports the same standard libraries in their REPL session.

// src/gsh/evaluator/source.gleam

/// Generates the standard module header and base imports for dynamically generated 
/// evaluation files.
pub fn header(with_string: Bool, _with_formatter: Bool) -> String {
  case with_string {
    True -> "import gleam/string as gsh_internal_string\n\n"
    False -> "\n"
  }
}
