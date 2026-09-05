//// The `source` module provides boilerplate code generation helpers for the evaluator.
////
//// When the evaluator constructs the temporary `gsh_eval.gleam` file, it needs 
//// to inject certain hidden imports so that the generated code can successfully 
//// format and print its output back to the REPL.

// src/gsh/evaluator/source.gleam

/// Generates the standard module header and base imports for the evaluation file.
/// 
/// It always imports `gsh/input/terminal` so the injected `gsh_entry` function 
/// can print results. If `with_string` is True, it also imports `gleam/string` 
/// under a hidden alias (`gsh_internal_string`). The alias prevents namespace 
/// collisions in case the user also decides to type `import gleam/string` in the REPL.
pub fn header(with_string: Bool) -> String {
  "import gsh/input/terminal\n"
  <> case with_string {
    True -> "import gleam/string as gsh_internal_string\n"
    False -> ""
  }
  <> "\n"
}
