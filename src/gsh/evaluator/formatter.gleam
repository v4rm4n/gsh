// src/gsh/evaluator/formatter.gleam

import gleam/int
import gleam/list
import gleam/string

pub fn format_output(output: String) -> String {
  output
  |> string.split("\n")
  |> filter_warning_lines(False, [])
  |> string.join(with: "\n")
  |> string.trim()
  <> "\n"
}

fn filter_warning_lines(
  lines: List(String),
  skipping: Bool,
  acc: List(String),
) -> List(String) {
  case lines {
    [] -> list.reverse(acc)

    [line, ..rest] -> {
      let next = case is_warning_header(line) {
        True -> filter_warning_lines(rest, True, acc)

        False ->
          case skipping {
            True ->
              case is_runtime_output(line) {
                True -> filter_warning_lines(rest, False, [line, ..acc])

                False -> filter_warning_lines(rest, True, acc)
              }

            False -> filter_warning_lines(rest, False, [line, ..acc])
          }
      }

      next
    }
  }
}

fn is_warning_header(line: String) -> Bool {
  string.starts_with(line, "warning:")
}

fn is_runtime_output(line: String) -> Bool {
  let line = string.trim(line)

  case int.parse(line) {
    Ok(_) -> True

    Error(_) ->
      line == "True"
      || line == "False"
      || string.starts_with(line, "\"")
      || string.starts_with(line, "#(")
      || string.starts_with(line, "{")
      || string.starts_with(line, "[")
      || string.starts_with(line, "//fn")
      || string.starts_with(line, "fn(")
      || string.starts_with(line, "Ok(")
      || string.starts_with(line, "Error(")
  }
}
