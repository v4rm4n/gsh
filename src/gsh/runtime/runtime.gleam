// src/gsh/runtime/runtime.gleam
import etch/erlang/tty
import gleam/erlang/atom

@external(erlang, "ffi", "system_version")
pub fn system_version() -> String

@external(erlang, "ffi", "app_version")
pub fn app_version(app_name: atom.Atom) -> String

@external(erlang, "ffi", "get_char")
pub fn get_char() -> String

@external(erlang, "ffi", "pushback")
pub fn pushback(char: String) -> Nil

@external(erlang, "ffi", "get_char_timeout")
pub fn get_char_timeout(timeout_ms: Int) -> Result(String, Nil)

pub fn enable_raw_mode() -> Result(Nil, tty.TerminalError) {
  tty.enter_raw()
}

pub fn disable_raw_mode() -> Result(Nil, tty.TerminalError) {
  tty.exit_raw()
}
