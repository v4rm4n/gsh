// src/gsh/runtime/runtime.gleam
import etch/erlang/tty
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom
import gleam/erlang/process

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

@external(erlang, "ffi", "load_and_run")
pub fn load_and_run(
  module: String,
  function: String,
) -> Result(Dynamic, Dynamic)

@external(erlang, "ffi", "get_args")
pub fn get_args() -> List(String)

@external(erlang, "ffi", "boot_app")
pub fn boot_app(module: String) -> Result(Dynamic, String)

@external(erlang, "ffi", "pid_from_string")
pub fn pid_from_string(pid: String) -> process.Pid
