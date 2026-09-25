# Constants

GSH doesn't support `const` at the prompt:

```gleam
gsh(5)> const pi = 3.14
error: Syntax error near Const
```

Use `let` instead. GSH computes each binding once and caches it, so it behaves like a constant for the rest of the session:

```gleam
gsh(10)> let pi = 3.14
3.14 : Float
```