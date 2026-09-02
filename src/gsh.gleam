import gleam/erlang/atom
import gleam/format
import gleam/io
import in

// --- FFI Bridges --
// GSH uses this small Erlang bridges to inspect the BEAM runtime it is running on
// and the app version as well.
@external(erlang, "gsh_ffi", "system_version")
fn system_version() -> String

@external(erlang, "gsh_ffi", "app_version")
fn app_version(app_name: atom.Atom) -> String

// --- FFI Bridges --

pub fn main() -> Nil {
  // Print the banner.
  banner()
  // Start the REPL.
  shell_loop(1)
}

fn banner() -> Nil {
  // Use FFI calls for the banner
  io.println(system_version())
  format.printf(
    "Interactive Gleam (GSH ~s) - press Ctrl+C to exit (type h() ENTER for help)",
    app_version(atom.create("gsh")),
  )
  io.println("")
}

fn shell_loop(prompt_count: Int) -> Nil {
  format.printf("gsh(~b)> ", prompt_count)

  case in.read_line() {
    Ok(input) -> {
      io.print(input)
      shell_loop(prompt_count + 1)
    }
    Error(_) -> Nil
  }
}
