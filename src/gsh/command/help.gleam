// src/gsh/command/help.gleam

import gsh/input/terminal

pub fn show() -> Nil {
  terminal.println(
    "
GSH commands:

  h()       Show this help
  v()       Show version
  k()       Exit shell
  l()       List loaded bindings
",
  )
}
