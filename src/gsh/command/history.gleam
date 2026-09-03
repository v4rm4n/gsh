// src/gsh/command/help.gleam

import gleam/int
import gleam/io
import gleam/list

pub fn show(history: List(String)) -> Nil {
  io.println("")
  io.println("Command history:")

  case history {
    [] -> io.println("  (empty)")

    _ ->
      list.each(
        list.index_map(history, fn(command, index) {
          int.to_string(index + 1) <> "  " <> command
        }),
        io.println,
      )
  }

  io.println("")
}
