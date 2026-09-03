// src/gsh/input/display.gleam

import gleam/io
import gsh/input/terminal

pub fn render(prompt: String, buffer: String) -> Nil {
  terminal.clear_line()
  io.print(prompt <> buffer)
}
