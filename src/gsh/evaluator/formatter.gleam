// src/gsh/evaluator/formatter.gleam
import gleam/string

pub fn format_error(output: String) -> String {
  case string.contains(output, "Pattern match failed") {
    True -> "error: assertion failed\n"

    False -> output
  }
}
