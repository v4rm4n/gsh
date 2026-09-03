// src/gsh/command/router.gleam

import gsh/command/bindings
import gsh/command/help
import gsh/command/history
import gsh/command/version
import gsh/evaluator/binding.{type Binding}

pub type CommandResult {
  Handled
  Exit
  NotCommand
}

pub fn handle(
  input: String,
  bindings: List(Binding),
  history_entries: List(String),
) -> CommandResult {
  case input {
    "h()" -> {
      help.show()
      Handled
    }

    "v()" -> {
      version.show()
      Handled
    }

    "k()" -> Exit

    "l()" -> {
      bindings.show(bindings)
      Handled
    }

    "history()" -> {
      history.show(history_entries)
      Handled
    }

    _ -> NotCommand
  }
}
