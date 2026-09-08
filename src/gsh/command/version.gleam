// The `version` module provides introspection into the currently running 
// shell's deployment metadata.
//
// When a user executes the `v()` command, this module queries the Erlang 
// application controller via FFI to dynamically extract and format the 
// active version of the GSH package.

// src/gsh/command/version.gleam

import gleam/erlang/atom
import gsh/input/terminal
import gsh/runtime/runtime.{app_version}

/// Dynamically resolves the loaded application version of `gsh` from the 
/// Erlang VM's application environment and prints it to the standard output.
@internal
pub fn show() -> Nil {
  terminal.println(
    "Gleam SHell (GSH) version " <> app_version(atom.create("gsh")),
  )
}
