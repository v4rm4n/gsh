// src/gsh/evaluator/source.gleam
pub fn header(with_string: Bool) -> String {
  "import gsh/input/terminal\n"
  <> case with_string {
    True -> "import gleam/string\n"
    False -> ""
  }
  <> "\n"
}
