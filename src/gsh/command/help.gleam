//// The `help` module provides the built-in command reference for the interactive shell.
////
//// It handles rendering the help menu when the user types the `h()` command, 
//// giving them a quick cheat sheet for REPL-specific utilities.

// src/gsh/command/help.gleam

import gsh/input/terminal

/// Prints the GSH command reference menu to the console.
/// It uses the custom `terminal.println` function to ensure newlines (`\n`) 
/// are correctly translated to CRLF (`\r\n`) so the formatting doesn't break 
/// while the terminal is in raw mode.
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
