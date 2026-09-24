# Changelog

All notable changes to GSH are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and GSH follows [Semantic Versioning](https://semver.org/).

## [1.3.0] - Unreleased

### Added

- **Prying (REPL-driven debugging).** Pause a process at a `pry` call in your code, attach the shell to it with `:pry`, evaluate code inside that process, and let it carry on with `:continue`.
  - `:pry list` shows every paused process, and `:pry <id>` attaches to a specific one.
  - `:pry off` releases every paused process and makes `pry` calls return immediately. `:pry on` turns them back on.
  - Pry calls only pause while a GSH session runs in the same VM.
- **Remote shells.** Start GSH with `--name` or `--sname`, `--cookie` and `--remsh <node>` to evaluate code on a running node. Bindings keep their values between prompts, and nothing GSH starts on the remote node outlives the session. For now, the remote node needs GSH's modules on its code path (for example, an app started with `gleam run`).
- **The [GSH Usage Guide](https://v4rm4n.github.io/gsh/)**, a walkthrough of the shell with real session transcripts.
- `:cc` lists the modules it reloaded.
- Calls to your project's functions show their types from the first prompt, and stay accurate after `:cc`.
- `pid()` accepts a pid without angle brackets, such as `pid("0.123.0")`.
- A failed remote connection shows a fingerprint of the cookie GSH used, to compare with the remote node's cookie.

### Changed

- `:cc` now reloads every module whose compiled code changed, like IEx's `recompile`, instead of only the modules imported in the session. Unchanged modules are left alone.
- `:cc` is disabled while connected to a remote node, so the shell never type-checks against code the remote node isn't running.

### Fixed

- A crash in a process spawned from the REPL no longer takes the shell down. It's reported as `[exit] <pid> exited: <reason>` before the next prompt.
- Output from processes started through GSH no longer drifts to the right ("staircasing") while the shell waits at its prompt.
- A variable bound to a value like `Undefined` no longer re-runs its side effects on every prompt.
- `let a_b = ...` and `let #(a, b) = ...` no longer overwrite each other's cached value, and each shadowed version of a variable keeps its own value.
- Expressions no longer show a wrong type (such as `3.14 : String`) left over from an earlier session.
- A variable no longer shows the return type of a function that happens to share its name.
- `:b` no longer prints a blank line for destructuring bindings, or lists a shadowed variable more than once.
- GSH no longer crashes at startup when Erlang distribution can't be started. It reports the reason instead.

## Earlier releases

Versions up to 1.2.0 are listed on [Hex](https://hex.pm/packages/gsh/versions).