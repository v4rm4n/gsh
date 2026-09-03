// src/gsh/command/bindings.gleam

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gsh/evaluator/binding.{type Binding}
import gsh/input/terminal

pub fn show(bindings: List(Binding)) -> Nil {
  terminal.println("")
  terminal.println("Loaded bindings:")

  case bindings {
    [] -> terminal.println("  (none)")

    _ ->
      list.each(bindings, fn(binding) {
        terminal.println("  " <> display_name(binding))
      })
  }

  terminal.println("")
  terminal.println("Total: " <> int.to_string(list.length(bindings)))
}

fn display_name(binding: Binding) -> String {
  case binding.name {
    Some(name) -> name
    None -> binding.pattern
  }
}
