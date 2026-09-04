// src/gsh/input/display.gleam

import contour
import gleam/list
import gleam/string
import gsh/input/terminal

pub fn render(prompt: String, buffer: String) -> Nil {
  terminal.clear_line()

  let quote_count = list.count(string.to_graphemes(buffer), fn(c) { c == "\"" })

  let display_buffer = case quote_count % 2 == 0 {
    True -> contour.to_ansi(buffer)
    False -> buffer
  }

  terminal.print(prompt <> display_buffer)
}
