// src/gsh/runtime/runtime.gleam
import gleam/erlang/atom

@external(erlang, "ffi", "system_version")
pub fn system_version() -> String

@external(erlang, "ffi", "app_version")
pub fn app_version(app_name: atom.Atom) -> String

@external(erlang, "ffi", "get_char")
pub fn get_char() -> String

@external(erlang, "ffi", "pusbhack")
pub fn pushback(char: String) -> Nil
