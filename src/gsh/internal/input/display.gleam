// The `display` module renders the REPL prompt and active input buffer to 
// the terminal output stream.
//
// It provides real-time, syntax-highlighted visual feedback during typing 
// using the `contour` library, while applying defensive rendering heuristics 
// to prevent ANSI escaping artifacts during incomplete string inputs.

// src/gsh/internal/input/display.gleam

import contour
import gleam/list
import gleam/string
import gsh/internal/input/terminal

/// Clears the current line buffer and redraws the prompt along with the user's input.
/// 
/// **Rendering Heuristics:**
/// * **Line Reset:** Invokes `terminal.clear_line()` to erase the previous cursor line.
/// * **Quote Balancing:** Counts quotation marks (`"`) across input graphemes. If the 
///   count is odd (indicating an unclosed string literal), syntax highlighting is 
///   temporarily bypassed to prevent broken ANSI color code rendering.
/// * **ANSI Highlighting:** When quote counts are balanced, passes the buffer string 
///   to `contour.to_ansi()` for real-time Gleam syntax coloring before output.
/// Clears the current line buffer and redraws the prompt along with the user's input.
/// Safely handles syntax highlighting across multiline pastes and escaped string quotes.
pub fn render(prompt: String, buffer: String, previous_text: String) -> Nil {
  terminal.clear_line()

  // 1. Calculate if previous lines left a string open (for `...>` prompts)
  let clean_prev = string.replace(previous_text, "\\\"", "")
  let prev_quotes =
    list.count(string.to_graphemes(clean_prev), fn(c) { c == "\"" })
  let start_in_string = prev_quotes % 2 != 0

  // 2. Split the active buffer into individual lines (crucial for Bracketed Pastes!)
  let lines = string.split(buffer, "\n")

  // 3. Process line-by-line, tracking string state to override the syntax highlighter
  let #(_, formatted_lines) =
    list.fold(lines, #(start_in_string, []), fn(acc, line) {
      let #(in_string, colored_lines) = acc

      // Strip escaped quotes so they don't break our parity math
      let clean_line = string.replace(line, "\\\"", "")
      let line_quotes =
        list.count(string.to_graphemes(clean_line), fn(c) { c == "\"" })

      let ends_in_string = case line_quotes % 2 == 0 {
        True -> in_string
        False -> !in_string
      }

      let colored_line = case in_string, ends_in_string {
        // 1. Fully enclosed in a multiline string
        True, True -> "\u{001b}[32m" <> line <> "\u{001b}[0m"

        // 2. Opening a string (e.g., `let x = "`)
        False, True -> {
          // Split at the first quote. Highlight the code, color the rest green!
          case string.split_once(line, "\"") {
            Ok(#(code, string_part)) ->
              contour.to_ansi(code)
              <> "\u{001b}[32m\""
              <> string_part
              <> "\u{001b}[0m"
            Error(_) -> line
          }
        }

        // 3. Closing a string (e.g., `  }" }`)
        True, False -> {
          // Split at the closing quote. Color the string green, highlight the trailing code!
          case string.split_once(line, "\"") {
            Ok(#(string_part, code)) ->
              "\u{001b}[32m"
              <> string_part
              <> "\"\u{001b}[0m"
              <> contour.to_ansi(code)
            Error(_) -> line
          }
        }

        // 4. Normal code
        False, False -> contour.to_ansi(line)
      }

      #(ends_in_string, list.append(colored_lines, [colored_line]))
    })

  // 4. Reassemble and print
  let display_buffer = string.join(formatted_lines, "\n")
  terminal.print(prompt <> display_buffer)
}
