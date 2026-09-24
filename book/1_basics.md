# Basics

## 1. Evaluation & REPL Errors

- All valid Gleam syntax is evaluated cleanly.

- Invalid Gleam syntax is reported by the REPL with the exact compiler error.

- Errors are trapped gracefully protecting the VM from crashing.

```gleam
Erlang/OTP 28 [erts-16.1.2] [source] [64-bit] [smp:16:16] [ds:16:16:10] [async-threads:1] [jit:ns]

Interactive Gleam (GSH 1.2.0) - press Ctrl+C to exit (type :h ENTER for help)
gsh(1)> 1
1 : Int
gsh(2)> 3.01 *. 3.14
9.4514 : Float
gsh(3)> 1 + "two"
error: Type mismatch
   ┌─ REPL:19:9
   │
19 │     1 + "two"
   │         ^^^^^

The + operator expects arguments of this type:

    Int

But this argument has this type:

    String

Hint: Strings can be joined using the `<>` operator.
```

## 2. Bindings & Shadowing

- GSH is **stateful**.
- When you bind a variable using `let`, `gsh` caches it in the shell-state.
- Those bindings seamlessly cascade into your subsequent evaluations, and Gleam's native **lexical shadowing** works exactly as you would expect in a compiled file.

```gleam
gsh(1)> let x = 10
10 : Int
gsh(2)> let x = x * 2
20 : Int
gsh(3)> x
20
```

- Side effects are managed by wrapping these assignments in **Erlang process-dictionary** checks.
- Side-effects execute exactly once, rather than re-firing every time the shell re-compiles the historical AST.

```gleam
gsh(6)> let _ = io.println("Fired!")
Fired!
Nil
gsh(7)> echo 1
src/gsh_eval_7.gleam:30
1
1
```

## 3. Multiline Expressions & Top-Level Definitions

- Unlike standard compiled Gleam, `gsh` allows you to define **custom types** and **top-level functions** directly in the prompt for rapid prototyping.
- The `pub` modifier doesn't make any difference in the top-level.

```gleam
gsh(1)> type Status {
...> Online
...> Offline
...> }
gsh(2)> pub fn check_status(s: Status) {
...> case s {
...> Online -> "All systems online"
...> Offline -> "Disconnected"
...> }
...> }
gsh(3)> check_status(Online)
"All systems online"
gsh(4)> check_status(Offline)
"Disconnected"
```

## 4. Type & Function Pruning

- Old types & functions defined in the top-level when re-defined will be pruned.
- Pruning is **limited to fast prototyping!** Changing the shape of the types or functions being chained with existing functions will result in **broken shell-state** till you fix the shape every where else!

```gleam
gsh(1)> type Something {
...> A
...> B
...> }
gsh(2)> fn wibble(param: Something) {
...> case param {
...> B -> "hello"
...> _ -> "nah"
...> }
...> }
gsh(3)> wibble(A)
"nah"
gsh(4)> type Something {
...> Online
...> Offline
...> }
error: Unknown variable
   ┌─ REPL:18:1
   │
18 │ B -> "hello"
   │ ^

The custom type variant constructor `B` is not in scope here.
gsh(5)> fn wibble(param: Int) {
...> 2 + 4
...> }
gsh(6)> wibble(3)
6
```

## 5. Multi-line Support

- `gsh` supports multi-line evaluations smartly based on Gleam's syntax.

- If you made a mistake in the middle of a multi-line evaluation, you can press `ctrl + x` to abort it.

```gleam
gsh(1)> fn wobble() {
...> "The
...> Quick
...> Brown
...> Fox
...> "
...> }
gsh(2)> wobble()
"The\nQuick\nBrown\nFox\n"
gsh(3)> type Struct {
...> Struct(
...> v1: Int,
...> v2: WrongType,
...> <something that won't compile!>
...> ^X
gsh(3)> 
```