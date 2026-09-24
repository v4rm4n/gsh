//// Shell-side interface to `gsh_pry.erl`: taking paused processes off the
//// queue, running evaluations inside them, and resuming them.

// src/gsh/internal/runtime/pry.gleam

import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid}

/// A process paused at a `pry` call, waiting for the shell.
pub type Paused {
  Paused(
    pid: Pid,
    /// Identifies this pause. Evaluations read the pried value with it.
    id: Int,
    /// The label passed to `pry`.
    label: String,
    /// The file of the code that called `pry`, e.g. `"src/hello.gleam"`.
    /// Best effort: if `pry` is the last expression of a function, it's the
    /// caller's file. The label is what identifies the exact pry point.
    location: String,
    /// How many other processes are still waiting after this one.
    waiting: Int,
  )
}

/// Starts this session's pry server. Paused processes watch it, so they all
/// resume if the shell exits.
@external(erlang, "gsh_pry", "start_server")
pub fn start_server(owner: Pid) -> Nil

/// Takes the oldest paused process off the queue.
@external(erlang, "gsh_pry", "take")
pub fn take() -> Result(Paused, Nil)

/// Takes the paused process with this id off the queue.
@external(erlang, "gsh_pry", "take_id")
pub fn take_id(id: Int) -> Result(Paused, Nil)

/// Every process waiting at a pry point, oldest first.
@external(erlang, "gsh_pry", "list")
pub fn list() -> List(Paused)

/// How many processes are waiting at pry points.
@external(erlang, "gsh_pry", "waiting")
pub fn waiting() -> Int

/// Switches pry points on or off. Switching them off resumes every waiting
/// process and returns how many were released.
@external(erlang, "gsh_pry", "set_enabled")
pub fn set_enabled(on: Bool) -> Int

/// Lets a paused process carry on from its `pry` call.
@external(erlang, "gsh_pry", "resume")
pub fn resume(pid: Pid, id: Int) -> Nil

/// Compiles an evaluation module and runs it inside the paused process.
@external(erlang, "gsh_pry", "run")
pub fn run(
  pid: Pid,
  id: Int,
  erl_path: String,
  module: String,
  function: String,
) -> Result(Dynamic, Dynamic)

/// A pid as `<0.231.0>`, for messages.
@external(erlang, "gsh_pry", "pid_text")
pub fn pid_text(pid: Pid) -> String
