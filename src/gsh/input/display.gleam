// src/gsh/input/display.gleam

import contour
import gsh/input/terminal

pub fn render(prompt: String, buffer: String) -> Nil {
  terminal.clear_line()

  // Pass the raw buffer through contour before sticking it on the prompt
  let highlighted_buffer = contour.to_ansi(buffer)

  terminal.print(prompt <> highlighted_buffer)
}
