// The `runtime` module serves as GSH's low-level bridge to the Erlang Virtual Machine (BEAM).
// 
// It exposes the Foreign Function Interfaces (FFI) required for dynamic in-memory code loading, 
// background actor orchestration, VM metadata inspection, logger modification, and exception trapping. 
// All functions in this module delegate directly to Erlang's underlying `code` server or GSH's `ffi.erl` driver.

// src/gsh/internal/runtime/runtime.gleam

import etch/erlang/tty
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process
import gleam/string

/// Returns the current monotonic system time in microseconds.
@external(erlang, "ffi", "system_time")
pub fn system_time() -> Int

/// Retrieves the running Erlang/OTP release and ERTS version string directly from the VM.
/// Used to construct system information during startup banner rendering.
@external(erlang, "ffi", "system_version")
pub fn system_version() -> String

/// Resolves the application version string for a loaded OTP application (e.g., `gsh`).
@external(erlang, "ffi", "app_version")
pub fn app_version(app_name: atom.Atom) -> String

/// Enables raw mode on the active TTY stream to capture unbuffered keystrokes.
pub fn enable_raw_mode() -> Result(Nil, tty.TerminalError) {
  tty.enter_raw()
}

/// Disables raw mode and restores standard cooked terminal mode.
pub fn disable_raw_mode() -> Result(Nil, tty.TerminalError) {
  tty.exit_raw()
}

/// Dynamically inspects a loaded Erlang module's exports table to return all public function names.
/// Powers autocomplete suggestions for imported standard library and project modules.
@external(erlang, "ffi", "get_exports")
pub fn get_exports(module: String) -> List(String)

/// Dynamically loads a `.beam` bytecode file into the VM and executes a designated function.
/// Intercepts VM-level exceptions (e.g., `badarg`, `function_clause`) to prevent REPL process crashes.
@external(erlang, "ffi", "load_and_run")
pub fn load_and_run(
  module: String,
  function: String,
) -> Result(Dynamic, Dynamic)

/// Retrieves raw CLI arguments passed after the `--` separator during shell boot.
/// Utilized by the bootloader to identify background application modules to start.
@external(erlang, "ffi", "get_args")
pub fn get_args() -> List(String)

/// Boots a background application module in an isolated Erlang process and returns its active PID.
@external(erlang, "ffi", "boot_app")
pub fn boot_app(module: String) -> Result(Dynamic, String)

/// Converts a formatted string PID representation (e.g., `"<0.83.0>"`) into a native Erlang `Pid` reference.
@external(erlang, "ffi", "pid_from_string")
pub fn pid_from_string(pid: String) -> process.Pid

/// Intercepts and wraps the default Erlang logger output handler to convert `\n` into `\r\n`, 
/// preventing log staircasing artifacts when background processes log during raw-mode TTY sessions.
@external(erlang, "ffi", "fix_logger_staircase")
pub fn fix_logger_staircase() -> Nil

/// Compiles an Erlang source file (`.erl`) directly into memory and loads the resulting code 
/// into the BEAM code server without writing a `.beam` file to disk.
@external(erlang, "ffi", "compile_and_load")
pub fn compile_and_load(
  erl_path: String,
  module_name: String,
) -> Result(Nil, String)

/// Safely executes an entrypoint function within an already loaded BEAM module, 
/// trapping runtime crashes and returning them as an error `Result`.
@external(erlang, "ffi", "run_entry")
pub fn run_entry(module: String, function: String) -> Result(Dynamic, Dynamic)

@external(erlang, "code", "purge")
fn ffi_purge(module: Atom) -> Bool

@external(erlang, "code", "load_file")
fn ffi_load_file(module: Atom) -> Dynamic

/// Forces the Erlang code server to purge its active RAM cache for a module and reload 
/// the latest compiled artifact from disk.
/// 
/// Automatically translates Gleam module paths (e.g., `gleam/httpc`) to their BEAM 
/// atom equivalents (`gleam@httpc`).
pub fn hot_reload(module_path: String) -> Nil {
  // Convert Gleam paths ("gleam/httpc") to Erlang modules ("gleam@httpc")
  let erl_name = string.replace(module_path, "/", "@")
  let mod_atom = atom.create(erl_name)

  let _ = ffi_purge(mod_atom)
  let _ = ffi_load_file(mod_atom)
  Nil
}

@external(erlang, "ffi", "ensure_code_paths")
pub fn ensure_code_paths() -> Nil
