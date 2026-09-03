// src/gsh/command/version.gleam

import gleam/erlang/atom
import gleam/io
import gsh/runtime/runtime.{app_version}

pub fn show() -> Nil {
  io.println("Gleam SHell (GSH) version " <> app_version(atom.create("gsh")))
}
