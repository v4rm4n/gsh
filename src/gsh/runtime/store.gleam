// src/gsh/runtime/store.gleam

@external(erlang, "ffi", "store_put")
pub fn put(key: String, value: a) -> a

@external(erlang, "ffi", "store_get")
pub fn get(key: String) -> a

@external(erlang, "ffi", "store_has")
pub fn has(key: String) -> Bool
