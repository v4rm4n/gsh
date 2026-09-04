// src/gsh/evaluator/formatter.gleam

import contour
import gleam/int
import gleam/list
import gleam/string

pub fn format_output(output: String) -> String {
  output
  |> string.split("\n")
  |> filter_warning_lines(False, [])
  |> string.join(with: "\n")
  |> string.trim()
  |> contour.to_ansi()
  // <-- Add contour here!
  |> fn(highlighted) { highlighted <> "\n" }
}

pub fn format_error(output: String) -> String {
  output
  |> string.split("\n")
  |> filter_warning_lines(False, [])
  |> string.join(with: "\n")
  |> string.trim()
  |> hide_internal_path()
  <> "\n"
}

fn hide_internal_path(output: String) -> String {
  output
  |> string.split("\n")
  |> list.map(fn(line) {
    // Look for the specific file name the evaluator uses
    case string.split_once(line, on: "gsh_eval.gleam") {
      Ok(#(before, after)) -> {
        // Strip out the absolute path directory structure, preserving the UI border
        case string.split_once(before, on: "┌─ ") {
          Ok(#(padding, _path)) -> padding <> "┌─ REPL" <> after
          Error(_) -> line
        }
      }
      Error(_) -> line
    }
  })
  |> string.join("\n")
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
  // Gleam compiler warnings typically look like:
  // "path/to/file.gleam:line:col: Warning: message
  string.contains(line, "Warning:") || string.starts_with(line, "warning:")
}

fn is_runtime_output(line: String) -> Bool {
  let line = string.trim(line)

  case int.parse(line) {
    Ok(_) -> True

    Error(_) ->
      line == "True"
      || line == "False"
      // Whitelist successful asserts
      || line == "ok"
      || string.starts_with(line, "\"")
      || string.starts_with(line, "#(")
      || string.starts_with(line, "{")
      || string.starts_with(line, "[")
      || string.starts_with(line, "//fn")
      || string.starts_with(line, "fn(")
      || string.starts_with(line, "Ok(")
      || string.starts_with(line, "Error(")
      // Use contains() to bypass ANSI codes
      || string.starts_with(line, "error:")
      // Use contains() to bypass ANSI codes
      || string.starts_with(line, "runtime error:")
  }
}
