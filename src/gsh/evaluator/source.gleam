// The `source` module provides boilerplate code generation helpers for the evaluator.
//
// When the evaluator constructs a temporary `gsh_eval_X.gleam` file, it uses 
// this module to inject hidden standard imports under safely aliased namespaces 
// (e.g., `gsh_internal_string`). This prevents variable collisions if a user 
// explicitly imports the same standard libraries in their REPL session.

// src/gsh/evaluator/source.gleam

/// Generates the standard module header and base imports for dynamically generated 
/// evaluation files.
/// 
/// **Import Injections:**
/// * Always imports `gsh/input/terminal` so the injected `gsh_entry` function 
///   can print results while honoring raw-mode formatting.
/// * **Formatter (`with_formatter`):** Conditionally imports `gsh/evaluator/formatter` 
///   under `gsh_internal_formatter` to process runtime inspect outputs.
/// * **String (`with_string`):** Conditionally imports `gleam/string` under 
///   `gsh_internal_string` to safely stringify expressions without namespace collisions.
@internal
pub fn header(with_string: Bool, with_formatter: Bool) -> String {
  "import gsh/input/terminal\n"
  <> case with_formatter {
    True -> "import gsh/evaluator/formatter as gsh_internal_formatter\n"
    False -> ""
  }
  <> case with_string {
    True -> "import gleam/string as gsh_internal_string\n"
    False -> ""
  }
  <> "\n"
}
