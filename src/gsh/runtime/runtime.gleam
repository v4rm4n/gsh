// src/gsh/runtime/runtime.gleam
import etch/erlang/tty
import gleam/erlang/atom

@external(erlang, "ffi", "system_version")
pub fn system_version() -> String

@external(erlang, "ffi", "app_version")
pub fn app_version(app_name: atom.Atom) -> String

pub fn enable_raw_mode() -> Result(Nil, tty.TerminalError) {
  tty.enter_raw()
}

pub fn disable_raw_mode() -> Result(Nil, tty.TerminalError) {
  tty.exit_raw()
}

@external(erlang, "ffi", "get_exports")
pub fn get_exports(module: String) -> List(String)
