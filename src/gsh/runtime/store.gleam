//// The `store` module provides a lightweight, persistent key-value cache 
//// backed by the Erlang Process Dictionary.
////
//// In a standard file-backed REPL, every time the file is re-evaluated, 
//// all previous side-effects (like spawning processes or DB writes) would run again. 
//// GSH avoids this by wrapping every `let` binding in a cache check. 
//// This store ensures that variables are evaluated exactly once and kept alive 
//// in the VM's memory across multiple REPL prompts.

// src/gsh/runtime/store.gleam

/// Saves a value into the Process Dictionary under the given string key.
/// Returns the saved value so it can be returned inline during evaluation.
@external(erlang, "ffi", "store_put")
pub fn put(key: String, value: a) -> a

/// Retrieves a value from the Process Dictionary by its key.
/// Note: This is dynamically typed because the cache holds everything from 
/// basic integers to complex Erlang PIDs and custom types.
@external(erlang, "ffi", "store_get")
pub fn get(key: String) -> a

/// Checks if a given key already exists in the Process Dictionary.
/// The GSH evaluator uses this to determine if a binding's side-effects 
/// need to be executed or if they can be skipped by fetching from the cache.
@external(erlang, "ffi", "store_has")
pub fn has(key: String) -> Bool
