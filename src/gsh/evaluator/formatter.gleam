// The `formatter` module is responsible for cleaning up and beautifying 
// the raw output emitted by the Gleam compiler and Erlang runtime.
//
// Because GSH executes code by compiling temporary `gsh_eval_X.gleam` files, 
// the underlying compiler frequently generates noisy "unused variable" warnings 
// and exposes absolute internal file paths. This module intercepts that text stream, 
// purges the noise, rewrites stack traces to simulate a native REPL environment, 
// and applies ANSI syntax highlighting.

// src/gsh/evaluator/formatter.gleam

import contour
import gleam/int
import gleam/list
import gleam/string

/// Tracks nesting depth to safely tokenize Erlang's flat string outputs.
@internal
pub type HydrateState {
  HydrateState(
    depth: Int,
    in_string: Bool,
    escape: Bool,
    current: String,
    acc: List(String),
  )
}

/// Processes the standard output of a successful code evaluation.
/// 
/// **Formatting Pipeline:**
/// * Splits the raw output by line and feeds it through the warning filter.
/// * Trims trailing whitespace.
/// * Applies dynamic ANSI syntax highlighting via the `contour` library so 
///   returned data structures (like tuples or records) look native to the terminal.
@internal
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
@internal
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
        // Safely strip the directory prefix regardless of ANSI codes
        let clean_before =
          before
          |> string.replace("./src/", "")
          |> string.replace("src/", "")

        // Drop the dynamic ID and extension
        case string.split_once(after, on: ".gleam") {
          Ok(#(_id, rest)) -> clean_before <> "REPL" <> rest
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
  let clean = strip_ansi(line) |> string.lowercase
  string.starts_with(clean, "warning:")
}

/// A heuristic whitelist function that attempts to detect when a compiler warning 
/// block has ended and the actual stdout or result data has begun.
fn is_runtime_output(line: String) -> Bool {
  let clean = strip_ansi(line) |> string.trim

  case int.parse(clean) {
    Ok(_) -> True
    Error(_) ->
      clean == "True"
      || clean == "False"
      || clean == "ok"
      || string.starts_with(clean, "\"")
      || string.starts_with(clean, "#(")
      || string.starts_with(clean, "{")
      || string.starts_with(clean, "[")
      || string.starts_with(clean, "//fn")
      || string.starts_with(clean, "fn(")
      || string.starts_with(clean, "Ok(")
      || string.starts_with(clean, "Error(")
      || string.starts_with(clean, "error:")
      || string.starts_with(clean, "runtime error:")
  }
}

/// Safely strips all ANSI escape codes from a string so we can reliably 
/// perform text matching without colors breaking the comparisons.
@internal
pub fn strip_ansi(text: String) -> String {
  strip_ansi_loop(text, "")
}

fn strip_ansi_loop(remaining: String, acc: String) -> String {
  case string.split_once(remaining, "\u{001b}[") {
    Ok(#(before, after)) -> {
      case string.split_once(after, "m") {
        Ok(#(_codes, rest)) -> strip_ansi_loop(rest, acc <> before)
        Error(_) -> acc <> remaining
        // Malformed ANSI fallback
      }
    }
    Error(_) -> acc <> remaining
  }
}

/// Hydrates a raw Erlang tuple string (e.g., `Config("0.1.0", 8000)`) 
/// into a labeled Gleam string (e.g., `Config(version: "0.1.0", port: 8000)`).
@internal
pub fn hydrate_labels(
  raw_output: String,
  type_name: String,
  labels: List(String),
) -> String {
  let prefix = type_name <> "("

  case string.split_once(raw_output, on: prefix) {
    Ok(#(before, after)) -> {
      case string.ends_with(after, ")") {
        True -> {
          let inner = string.slice(after, 0, string.length(after) - 1)
          let values = tokenize_inspect_string(inner)

          // Use our safe zipper instead of list.map2
          let hydrated_pairs = zip_labels(labels, values, [])

          before <> prefix <> string.join(hydrated_pairs, ", ") <> ")"
        }
        False -> raw_output
      }
    }
    Error(_) -> raw_output
  }
}

/// Safely zips labels and values. If values outnumber labels (e.g. for Prelude types 
/// like `Ok` or `Error`), it appends the remaining values without labels.
fn zip_labels(
  labels: List(String),
  values: List(String),
  acc: List(String),
) -> List(String) {
  case labels, values {
    [], [] -> list.reverse(acc)

    // Out of labels, but still have values -> append raw values
    [], [v, ..vs] -> zip_labels([], vs, [v, ..acc])

    // Have both label and value
    [l, ..ls], [v, ..vs] -> {
      let pair = case l {
        "" -> v
        _ -> l <> ": " <> v
      }
      zip_labels(ls, vs, [pair, ..acc])
    }

    // Out of values (shouldn't happen on valid inspect strings)
    _, [] -> list.reverse(acc)
  }
}

/// Safely splits a comma-separated string, ignoring commas trapped inside 
/// nested brackets, parentheses, or escaped strings.
@internal
pub fn tokenize_inspect_string(raw_args: String) -> List(String) {
  let chars = string.to_graphemes(raw_args)
  tokenize_loop(chars, HydrateState(0, False, False, "", []))
}

fn tokenize_loop(chars: List(String), state: HydrateState) -> List(String) {
  case chars {
    // End of string: append the final accumulated buffer
    [] -> list.reverse([string.trim(state.current), ..state.acc])

    [char, ..rest] -> {
      case char, state.in_string, state.escape {
        // Handle escaped characters inside strings (e.g., \")
        "\\", True, False ->
          tokenize_loop(
            rest,
            HydrateState(..state, escape: True, current: state.current <> char),
          )
        _, True, True ->
          tokenize_loop(
            rest,
            HydrateState(..state, escape: False, current: state.current <> char),
          )

        // Toggle string boundaries
        "\"", False, False ->
          tokenize_loop(
            rest,
            HydrateState(
              ..state,
              in_string: True,
              current: state.current <> char,
            ),
          )
        "\"", True, False ->
          tokenize_loop(
            rest,
            HydrateState(
              ..state,
              in_string: False,
              current: state.current <> char,
            ),
          )

        // Track structural depth (ignore brackets if inside a string)
        "(", False, _ | "[", False, _ | "{", False, _ ->
          tokenize_loop(
            rest,
            HydrateState(
              ..state,
              depth: state.depth + 1,
              current: state.current <> char,
            ),
          )
        ")", False, _ | "]", False, _ | "}", False, _ ->
          tokenize_loop(
            rest,
            HydrateState(
              ..state,
              depth: state.depth - 1,
              current: state.current <> char,
            ),
          )

        // Safely split on comma ONLY if at root depth and outside strings
        ",", False, _ if state.depth == 0 ->
          tokenize_loop(
            rest,
            HydrateState(..state, current: "", acc: [
              string.trim(state.current),
              ..state.acc
            ]),
          )

        // Standard character accumulation
        _, _, _ ->
          tokenize_loop(
            rest,
            HydrateState(..state, current: state.current <> char),
          )
      }
    }
  }
}
