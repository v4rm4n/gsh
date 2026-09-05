//// The `runtime` module serves as GSH's bridge to the Erlang Virtual Machine (BEAM).
//// 
//// It provides the foreign function interfaces (FFI) necessary for dynamic code loading,
//// process orchestration, runtime metadata inspection, and catching VM-level exceptions.
//// Everything in this module delegates to `ffi.erl` or other low-level utilities.

// src/gsh/runtime/runtime.gleam

import etch/erlang/tty
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom
import gleam/erlang/process

/// Retrieves the Erlang/OTP and ERTS version string directly from the VM.
/// Used to display the system information in the startup banner.
@external(erlang, "ffi", "system_version")
pub fn system_version() -> String

/// Retrieves the version number of a loaded application (e.g., "gsh").
/// Used to display the current version of the REPL in the startup banner.
@external(erlang, "ffi", "app_version")
pub fn app_version(app_name: atom.Atom) -> String

/// Places the terminal into raw mode, allowing the editor to capture keystrokes
/// character-by-character for features like history traversal and autocomplete.
pub fn enable_raw_mode() -> Result(Nil, tty.TerminalError) {
  tty.enter_raw()
}

/// Restores the terminal to standard cooked mode. Must be called before printing
/// large blocks of text, evaluating side-effects, or exiting the shell.
pub fn disable_raw_mode() -> Result(Nil, tty.TerminalError) {
  tty.exit_raw()
}

/// Dynamically inspects a loaded Erlang module to find all of its exported functions.
/// This powers GSH's intelligent autocomplete for standard library and project imports.
@external(erlang, "ffi", "get_exports")
pub fn get_exports(module: String) -> List(String)

/// The core execution bridge. Dynamically loads a freshly compiled `.beam` file 
/// into the VM and runs a specific function (usually `gsh_entry`). 
/// 
/// Crucially, this FFI wrapper catches all Erlang runtime exceptions (like `Badarg`)
/// and returns them as a safe `Result` so the REPL never crashes.
@external(erlang, "ffi", "load_and_run")
pub fn load_and_run(
  module: String,
  function: String,
) -> Result(Dynamic, Dynamic)

/// Retrieves the raw command-line arguments passed after the `--` separator.
/// Used by the bootloader to determine which background applications to orchestrate.
@external(erlang, "ffi", "get_args")
pub fn get_args() -> List(String)

/// Weaponizes Erlang's auto-loader to boot a background application.
/// It dynamically locates the compiled module, spawns its `main()` function 
/// in a new process, and returns the active PID.
@external(erlang, "ffi", "boot_app")
pub fn boot_app(module: String) -> Result(Dynamic, String)

/// Converts a string representation of a PID (e.g., `"<0.83.0>"`) back into 
/// a native Erlang `Pid` reference. This is exposed in the REPL as the `pid()` 
/// helper to allow seamless interaction with background actors.
@external(erlang, "ffi", "pid_from_string")
pub fn pid_from_string(pid: String) -> process.Pid
