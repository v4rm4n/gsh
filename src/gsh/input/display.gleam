//// The `display` module renders the REPL prompt and active input buffer to 
//// the terminal output stream.
////
//// It provides real-time, syntax-highlighted visual feedback during typing 
//// using the `contour` library, while applying defensive rendering heuristics 
//// to prevent ANSI escaping artifacts during incomplete string inputs.

// src/gsh/input/display.gleam

import contour
import gleam/list
import gleam/string
import gsh/input/terminal

/// Clears the current line buffer and redraws the prompt along with the user's input.
/// 
/// **Rendering Heuristics:**
/// * **Line Reset:** Invokes `terminal.clear_line()` to erase the previous cursor line.
/// * **Quote Balancing:** Counts quotation marks (`"`) across input graphemes. If the 
///   count is odd (indicating an unclosed string literal), syntax highlighting is 
///   temporarily bypassed to prevent broken ANSI color code rendering.
/// * **ANSI Highlighting:** When quote counts are balanced, passes the buffer string 
///   to `contour.to_ansi()` for real-time Gleam syntax coloring before output.
pub fn render(prompt: String, buffer: String) -> Nil {
  terminal.clear_line()

  let quote_count = list.count(string.to_graphemes(buffer), fn(c) { c == "\"" })

  let display_buffer = case quote_count % 2 == 0 {
    True -> contour.to_ansi(buffer)
    False -> buffer
  }

  terminal.print(prompt <> display_buffer)
}
