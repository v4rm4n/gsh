// The `help` module provides the built-in command reference for the interactive shell.
//
// It handles rendering the help menu when the user requests assistance, 
// providing a quick cheat sheet for REPL-specific utilities, inspection tools, 
// and hot-reloading commands.

// src/gsh/internal/command/help.gleam

import gsh/internal/input/terminal

/// Prints the GSH command reference menu to the console.
/// It uses the custom `terminal.println` function to ensure newlines (`\n`) 
/// are correctly translated to CRLF (`\r\n`) so the formatting doesn't break 
/// while the terminal is in raw mode.
pub fn show() -> Nil {
  terminal.println(
    "
GSH builtins:

  h()               Show this help
  v()               Show version
  k()               Exit shell
  l()               List loaded bindings
  pid(<pid string>) Create BEAM pid from string
  compile           Rebuild host project and hot-reload imports
  debug             Toggle AST and evaluator debug output
",
  )
}
