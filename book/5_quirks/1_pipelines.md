# Pipelines

Pasting an a multi-line expression like this in GSH would fail:

```gleam
let number = 123

number
|> int.to_string()
|> string.to_graphemes()
|> list.map(fn(x) { int.parse(x) })
|> result.all()

// error: Syntax error near Pipe
```

Pipelines at the end of an expression won't trigger multi-line evaluation like `iex`!

```gleam
gsh(18)> 1 |>
error: Syntax error near RightBrace
```

For cleanly evaluating pipelines in GSH you can wrap the entire set of pipelines within braces:

```gleam
gsh(15)> {
...> number
...>     |> int.to_string()
...>     |> string.to_graphemes()
...>     |> list.map(fn(x) { int.parse(x) })
...>     |> result.all()
...> }
Ok([1, 2, 4, 1, 5, 1, 3])
```