//// The `display` module is responsible for rendering the REPL prompt and 
//// the user's current input buffer to the terminal.
////
//// It provides real-time syntax highlighting using the `contour` library, 
//// ensuring that Gleam code is easily readable and beautiful as it is being typed.

// src/gsh/input/display.gleam

import contour
import gleam/list
import gleam/string
import gsh/input/terminal

/// Clears the current terminal line and redraws the prompt along with the user's input.
/// 
/// To prevent syntax highlighting artifacts or crashes while the user is actively 
/// typing inside a string literal, this function counts quotation marks. If the quotes 
/// are unbalanced (meaning the user is in the middle of typing a string), it temporarily 
/// disables the ANSI highlighting until the string is closed.
pub fn render(prompt: String, buffer: String) -> Nil {
  terminal.clear_line()

  let quote_count = list.count(string.to_graphemes(buffer), fn(c) { c == "\"" })

  let display_buffer = case quote_count % 2 == 0 {
    True -> contour.to_ansi(buffer)
    False -> buffer
  }

  terminal.print(prompt <> display_buffer)
}
