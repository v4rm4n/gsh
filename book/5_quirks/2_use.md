# `use`

A `use` expression takes **the rest of its block** as its callback. At the prompt, a `use` line on its own has no rest, so Gleam fills the gap with `todo` and it crashes:

```gleam
gsh(6)> use x <- result.try(Ok(1))
Execution Error: "error:#{function => <<\"gsh_entry\">>,line => 26,\n        message =>\n            <<\"`todo` expression evaluated. This code has not yet been implemented.\">>,
...
```

Wrap the `use` and everything that follows it in braces:

```gleam
gsh(7)> {
...> use x <- result.try(Ok(1))
...> Ok(x + 1)
...> }
Ok(2)
```