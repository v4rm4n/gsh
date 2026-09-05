//// The `formatter` module is responsible for cleaning up and beautifying 
//// the output from the Gleam compiler and evaluator.
////
//// Because GSH works by compiling a temporary file behind the scenes, standard 
//// compiler output often includes noisy "unused variable" warnings or absolute 
//// file paths. This module parses that text, strips out the noise, replaces 
//// temporary file paths with "REPL", and applies ANSI syntax highlighting.

// src/gsh/evaluator/formatter.gleam

import contour
import gleam/int
import gleam/list
import gleam/string

/// Processes the standard output of a successful code evaluation.
/// It filters out any noisy compiler warnings, trims whitespace, and applies 
/// ANSI syntax highlighting so the result looks beautiful in the terminal.
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

/// Processes the output of a failed code evaluation (compiler error or runtime crash).
/// Filters out warnings, trims whitespace, and most importantly, rewrites the 
/// error trace so it doesn't expose the temporary `gsh_eval.gleam` file path.
pub fn format_error(output: String) -> String {
  output
  |> string.split("\n")
  |> filter_warning_lines(False, [])
  |> string.join(with: "\n")
  |> string.trim()
  |> hide_internal_path()
  <> "\n"
}

/// Scans error output for references to the internal evaluator file (`gsh_eval.gleam`).
/// When the Gleam compiler prints an error snippet, it draws a UI box with the path.
/// This function swaps that absolute path out for `┌─ REPL` to maintain the illusion 
/// that the code was executed directly in memory.
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

/// A recursive state-machine filter that removes multi-line compiler warnings.
/// When it detects a warning header, it switches to `skipping = True` and drops 
/// lines until it encounters something that looks like actual runtime output.
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

/// Checks if a string line matches the standard format of a Gleam compiler warning.
fn is_warning_header(line: String) -> Bool {
  // Gleam compiler warnings typically look like:
  // "path/to/file.gleam:line:col: Warning: message
  string.contains(line, "Warning:") || string.starts_with(line, "warning:")
}

/// A heuristic function that attempts to detect when a compiler warning block 
/// has ended and the actual stdout or result data has begun.
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
