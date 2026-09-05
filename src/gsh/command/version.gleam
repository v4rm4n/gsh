//// The `version` module handles the built-in version inspection command.
////
//// When a user types `v()`, this module queries the Erlang application 
//// controller to dynamically fetch the current running version of GSH and prints it.

// src/gsh/command/version.gleam

import gleam/erlang/atom
import gsh/input/terminal
import gsh/runtime/runtime.{app_version}

/// Fetches the loaded application version of "gsh" from the VM and 
/// prints it formatted to the terminal.
pub fn show() -> Nil {
  terminal.println(
    "Gleam SHell (GSH) version " <> app_version(atom.create("gsh")),
  )
}
