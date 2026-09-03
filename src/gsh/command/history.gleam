// src/gsh/command/help.gleam

import gleam/int
import gleam/list
import gsh/input/terminal

pub fn show(history: List(String)) -> Nil {
  terminal.println("")
  terminal.println("Command history:")

  case history {
    [] -> terminal.println("  (empty)")

    _ ->
      list.each(
        list.index_map(history, fn(command, index) {
          int.to_string(index + 1) <> "  " <> command
        }),
        terminal.println,
      )
  }

  terminal.println("")
}
