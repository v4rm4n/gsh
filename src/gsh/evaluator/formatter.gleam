//// The `formatter` module is responsible for cleaning up and beautifying 
//// the raw output emitted by the Gleam compiler and Erlang runtime.
////
//// Because GSH executes code by compiling temporary `gsh_eval_X.gleam` files, 
//// the underlying compiler frequently generates noisy "unused variable" warnings 
//// and exposes absolute internal file paths. This module intercepts that text stream, 
//// purges the noise, rewrites stack traces to simulate a native REPL environment, 
//// and applies ANSI syntax highlighting.

// src/gsh/evaluator/formatter.gleam

import contour
import gleam/int
import gleam/list
import gleam/string

/// Processes the standard output of a successful code evaluation.
/// 
/// **Formatting Pipeline:**
/// * Splits the raw output by line and feeds it through the warning filter.
/// * Trims trailing whitespace.
/// * Applies dynamic ANSI syntax highlighting via the `contour` library so 
///   returned data structures (like tuples or records) look native to the terminal.
pub fn format_output(output: String) -> String {
  output
  |> string.split("\n")
  |> filter_warning_lines(False, [])
  |> string.join(with: "\n")
  |> string.trim()
  |> contour.to_ansi()
}

/// Processes the output of a failed code evaluation (compiler error or runtime crash).
/// 
/// **Error Pipeline:**
/// * Runs the identical warning filter to strip out unrelated noise.
/// * Trims whitespace.
/// * Passes the resulting string through the `hide_internal_path` interceptor 
///   so the user sees a pristine REPL error trace rather than a filesystem leak.
pub fn format_error(output: String) -> String {
  output
  |> string.split("\n")
  |> filter_warning_lines(False, [])
  |> string.join(with: "\n")
  |> string.trim()
  |> hide_internal_path()
  <> "\n"
}

/// Scans error output for references to the dynamically generated evaluator 
/// files (e.g., `gsh_eval_4.gleam`). 
/// 
/// Safely parses the Gleam compiler's box-drawing characters (`┌─`) to strip out 
/// the `./test/` directory prefix and dynamic file ID, seamlessly replacing it 
/// with a static `REPL` identifier.
fn hide_internal_path(output: String) -> String {
  output
  |> string.split("\n")
  |> list.map(fn(line) {
    case string.split_once(line, on: "gsh_eval_") {
      Ok(#(before, after)) -> {
        // Strip out the "./test/" directory prefix
        case string.split_once(before, on: "┌─ ") {
          Ok(#(padding, _path_prefix)) -> {
            // Strip out the dynamic prompt ID and extension
            case string.split_once(after, on: ".gleam") {
              Ok(#(_id, rest)) -> padding <> "┌─ REPL" <> rest
              Error(_) -> line
            }
          }
          Error(_) -> line
        }
      }
      Error(_) -> line
    }
  })
  |> string.join("\n")
}

/// A recursive state-machine filter that purges multi-line compiler warnings.
/// 
/// When it detects a warning header (e.g., `warning:`), it toggles its state 
/// to `skipping = True` and drops subsequent lines until it encounters something 
/// that matches the heuristic for actual runtime output or return values.
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

/// A heuristic whitelist function that attempts to detect when a compiler warning 
/// block has ended and the actual stdout or result data has begun.
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
