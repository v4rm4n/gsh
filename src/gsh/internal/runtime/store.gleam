// The `store` module provides a lightweight, persistent key-value cache
// backed by the Erlang process dictionary of the process that runs REPL
// evaluations: the local shell process, or the evaluation agent on a remote node.
//
// In GSH's synthetic runtime approach, generated evaluation modules re-declare historical
// statements to maintain lexical scope. To prevent duplicate side-effects (such as process
// spawning or network calls), every variable binding is wrapped in a cache lookup.
// This module ensures that bindings are computed exactly once during their initial evaluation
// and retrieved directly from BEAM process memory in subsequent prompts.

// src/gsh/internal/runtime/store.gleam

/// Caches `value` under `key` in the current process and returns it, so
/// generated code can store a binding inline.
@external(erlang, "ffi", "store_put")
pub fn put(key: String, value: a) -> a

/// Looks up a cached value. `Error(Nil)` means nothing was stored under `key`.
///
/// Values are wrapped on the Erlang side, so a cached value that happens to be
/// the atom `undefined` (such as a Gleam `Undefined` constructor) is still found.
/// Checking for `undefined` directly would treat it as missing and re-run its
/// side effects on every prompt.
@external(erlang, "ffi", "store_lookup")
fn lookup(key: String) -> Result(a, Nil)

/// Returns the value cached under `key`, or runs `compute` once, caches its
/// result, and returns it.
pub fn cache(key: String, compute: fn() -> a) -> a {
  case lookup(key) {
    Ok(value) -> value
    Error(Nil) -> put(key, compute())
  }
}
