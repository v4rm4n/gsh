// The `store` module provides a lightweight, persistent key-value cache 
// backed by the Erlang Process Dictionary (`erlang:get/1` and `erlang:put/2`).
//
// In GSH's synthetic runtime approach, generated evaluation modules re-declare historical 
// statements to maintain lexical scope. To prevent duplicate side-effects (such as process 
// spawning or network calls), every variable binding is wrapped in a cache lookup. 
// This module ensures that bindings are computed exactly once during their initial evaluation 
// and retrieved directly from BEAM process memory in subsequent prompts.

// src/gsh/internal/runtime/store.gleam

/// Stores a dynamically typed value in the Erlang Process Dictionary under the specified string key.
/// Returns the stored value directly to support inline assignments within generated code.
@external(erlang, "ffi", "store_put")
pub fn put(key: String, value: a) -> a

/// Retrieves a value from the Erlang Process Dictionary associated with the specified key.
/// Unsafely coerced to type `a` as the process memory contains diverse runtime values.
@external(erlang, "ffi", "store_get")
fn get(key: String) -> a

/// Checks if a key exists in the Erlang Process Dictionary.
/// Used by the evaluator engine to determine whether a statement must be re-executed or read from memory.
@external(erlang, "ffi", "store_has")
fn has(key: String) -> Bool

/// Evaluates a computation closure or retrieves its cached result from process memory.
/// 
/// **Cache Logic:**
/// * If `key` exists in the Erlang Process Dictionary, retrieves and returns the stored value immediately.
/// * If `key` is absent, executes the `compute` closure, caches the evaluated result under `key`, and returns it.
pub fn cache(key: String, compute: fn() -> a) -> a {
  case has(key) {
    True -> get(key)
    False -> {
      let val = compute()
      put(key, val)
      val
    }
  }
}
