// src/gsh/input/display.gleam

import gsh/input/terminal

pub fn render(prompt: String, buffer: String) -> Nil {
  terminal.clear_line()
  terminal.print(prompt <> buffer)
}
