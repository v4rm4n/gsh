// src/gsh/command/bindings.gleam

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gsh/evaluator/binding.{type Binding}

pub fn show(bindings: List(Binding)) -> Nil {
  io.println("")
  io.println("Loaded bindings:")

  case bindings {
    [] -> io.println("  (none)")

    _ ->
      list.each(bindings, fn(binding) {
        io.println("  " <> display_name(binding))
      })
  }

  io.println("")
  io.println("Total: " <> int.to_string(list.length(bindings)))
}

fn display_name(binding: Binding) -> String {
  case binding.name {
    Some(name) -> name
    None -> binding.pattern
  }
}
