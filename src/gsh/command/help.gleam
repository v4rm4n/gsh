// src/gsh/command/help.gleam

import gleam/io

pub fn show() -> Nil {
  io.println(
    "
GSH commands:

  h()       Show this help
  v()       Show version
  k()       Exit shell
  l()       List loaded bindings
",
  )
}
