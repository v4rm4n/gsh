//// Where an evaluation runs.

// src/gsh/internal/evaluator/target.gleam

import gleam/erlang/process.{type Pid}

pub type Target {
  /// In the shell's own process.
  Local

  /// Inside this session's evaluation agent on a remote node (`--remsh`).
  Remote(node: String)

  /// Inside a process paused at a `pry` call (see `gsh_pry.erl`).
  Pried(pid: Pid, id: Int)
}
