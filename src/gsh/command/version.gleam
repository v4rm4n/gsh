// src/gsh/command/version.gleam

import gleam/erlang/atom
import gsh/input/terminal
import gsh/runtime/runtime.{app_version}

pub fn show() -> Nil {
  terminal.println(
    "Gleam SHell (GSH) version " <> app_version(atom.create("gsh")),
  )
}
