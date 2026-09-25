# Calling Erlang Directly

You can declare an Erlang function with `@external` and call it straight away, without writing a module. This is handy for poking at the BEAM from the prompt.

Keep the whole declaration **on one line**. GSH evaluates each line as soon as it's complete on its own, and an `@external(...)` line by itself is, so splitting it fails:

```gleam
gsh(8)> @external(erlang, "erlang", "system_time")
error: Syntax error near At
```

On one line, it works:

```gleam
gsh(2)> @external(erlang, "erlang", "system_time") fn system_time() -> Int
gsh(3)> system_time() > 0
True : Bool
```