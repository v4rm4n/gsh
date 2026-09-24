# Prying

- Pry lets you **pause a live process** at a chosen point in your code, **attach** `gsh` to it, poke around **inside that process**, and then let it **continue** as if nothing happened.
- It's REPL-driven debugging: instead of adding a bunch of `echo` statements and re-running, you stop the code where it matters and ask it questions.

## 1. Adding a pry point

- `gsh` is a dev dependency, and Gleam doesn't let `src/` modules import dev dependencies. So you declare `pry` yourself with an `@external`, once per module that uses it.
- `pry(value, label)` takes the value you want to inspect and a label, and **returns the value unchanged**.
- Gleam has no macros, so `pry` can't capture your local variables by itself. Pass the ones you care about, usually as a tuple.

```gleam
// src/shop.gleam
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list

/// Pauses the calling process until gsh lets it continue.
@external(erlang, "gsh_pry", "pry")
fn pry(value: a, label: String) -> a

pub type Cart {
  Cart(items: List(Int))
}

pub fn total(cart: Cart) -> Int {
  list.fold(cart.items, 0, fn(acc, price) { acc + price })
}

pub fn checkout(user: String, cart: Cart) -> Int {
  let #(user, cart) = pry(#(user, cart), "checkout")
  io.println(user <> " paid " <> int.to_string(total(cart)))
  total(cart)
}

pub fn refund(order_id: Int, amount: Int) -> Int {
  let #(_order_id, amount) = pry(#(order_id, amount), "refund")
  io.println("refunded " <> int.to_string(amount))
  amount
}

/// Simulates two requests, each handled in its own process.
pub fn simulate() -> Nil {
  process.spawn(fn() { checkout("ada", Cart([10, 20, 30])) })
  process.sleep(10)
  process.spawn(fn() { refund(42, 500) })
  Nil
}
```

- Because `pry` returns its value, it also fits in the middle of a pipeline:

```gleam
order
|> pry("before submit")
|> submit
```

## 2. Pausing a process

- When a process reaches a `pry` call while `gsh` is running, it **pauses** and `gsh` prints a notice with its **id**, **pid**, **location** and **label**.
- The shell keeps working normally. The paused process simply waits for you.

```gleam
gsh(1)> import shop
gsh(2)> import gleam/erlang/process
gsh(3)> let orders = 3
3 : Int
gsh(4)> shop.simulate()

[pry] #1 <0.115.0> paused at src/shop.gleam:21 ("checkout"). Type :pry to attach.

[pry] #2 <0.116.0> paused at src/shop.gleam:27 ("refund"). 2 waiting, :pry list to see them.
Nil
```

- The same happens in a real app booted through `gsh` (for example with `apps` in `[tools.gsh]`). A request that reaches a pry point waits there until you continue it, so the HTTP client may time out while you're looking around.

## 3. Listing & attaching

- `:pry list` shows every process waiting at a pry point, oldest first.
- `:pry` attaches to the oldest one, and `:pry <id>` attaches to a specific one.
- On attach, the value passed to `pry` is bound to a variable **named after the label** (or `pried`, if the label isn't a valid Gleam variable name) and printed.
- The prompt changes to `pry(<label>)>` while you're attached.

```gleam
gsh(5)> :pry list
Waiting at pry points:
  #1  <0.115.0>  src/shop.gleam:21  "checkout"
  #2  <0.116.0>  src/shop.gleam:27  "refund"
Type :pry <id> to attach, or :pry for the oldest.
gsh(6)> :pry
Attached to #1 <0.115.0> at src/shop.gleam:21
checkout = #("ada", Cart([10, 20, 30]))
1 more waiting at pry points. Type :pry to attach.
```

## 4. Inspecting inside the paused process

- Everything you evaluate while attached **runs inside the paused process**, so `process.self()` is that process.
- A pry session has **its own bindings**. Your main session's bindings are set aside while you're attached, because replaying them inside another process would re-run their side effects.
- Your imports, types and functions stay available.
- The pried value has an **open type**: you can destructure it and pass it to functions, but reading a record field needs a type annotation first.

```gleam
pry(checkout)> let #(user, cart) = checkout
ok
pry(checkout)> shop.total(cart)
60 : Int
pry(checkout)> cart.items
error: Unknown type for record access
   ┌─ REPL:35:5
   │
35 │     cart.items
   │     ^^^^ I don't know what type this is

In order to access a record field we need to know what type it is, but I
can't tell the type here. Try adding type annotations to your function and
try again.
pry(checkout)> let cart: shop.Cart = cart
Cart([10, 20, 30])
pry(checkout)> cart.items
[10, 20, 30]
pry(checkout)> process.self()
//erl(<0.115.0>)
pry(checkout)> :b

Loaded bindings:
  checkout
  user
  cart

Total: 3
```

## 5. Continuing

- `:continue` lets the process carry on from its `pry` call. `pry` returns the original value.
- You're back in your main session with your earlier bindings. The pry session's bindings are discarded, and `gsh` removes everything it stored in the paused process's memory.
- If other processes are still waiting, `gsh` tells you.

```gleam
pry(checkout)> :continue
Resumed <0.115.0>
ada paid 60
1 more waiting at pry points. Type :pry to attach.
gsh(15)> :b

Loaded bindings:
  orders

Total: 1
gsh(16)> :pry 2
Attached to #2 <0.116.0> at src/shop.gleam:27
refund = #(42, 500)
pry(refund)> :continue
Resumed <0.116.0>
refunded 500
```

## 6. Turning pry points off

- `:pry off` releases every waiting process and makes `pry` calls return immediately.
- `:pry on` turns them back on.
- This is handy when a pry point sits in a busy code path and you've seen enough.

```gleam
gsh(19)> :pry off
Pry points disabled.
gsh(20)> shop.simulate()
ada paid 60
refunded 500
Nil
gsh(21)> :pry on
Pry points enabled.
```

## 7. Safety nets

- Calling code with a pry point **from the shell itself** doesn't pause (the shell would be waiting on itself). The call just runs.

```gleam
gsh(18)> shop.checkout("bob", shop.Cart([5]))
bob paid 5
5 : Int
```

- If the paused process **dies while you're attached**, `gsh` reports it and returns you to your main session.
- Processes spawned from the REPL are linked to the shell. If one crashes, `gsh` reports it as `[exit]` instead of crashing with it.

```gleam
gsh(22)> shop.simulate()

[pry] #3 <0.181.0> paused at src/shop.gleam:21 ("checkout"). Type :pry to attach.

[pry] #4 <0.182.0> paused at src/shop.gleam:27 ("refund"). 2 waiting, :pry list to see them.
Nil
gsh(23)> :pry
Attached to #3 <0.181.0> at src/shop.gleam:21
checkout = #("ada", Cart([10, 20, 30]))
1 more waiting at pry points. Type :pry to attach.
pry(checkout)> process.kill(process.self())
Execution Error: "the paused process exited: killed"

<0.181.0> exited. Back to the main session.
[exit] <0.181.0> exited: killed
gsh(25)> :pry off
Pry points disabled. Resumed 1 waiting process(es).
refunded 500
```

## 8. Limitations

- **Pry is dev-only.** A build without `gsh` (such as an Erlang shipment) has no `gsh_pry` module, so a leftover `pry` call crashes with `undef`. A CI check catches them:

```sh
# Fails the build if a pry call was left in the code
! grep -rn '"gsh_pry"' src/
```

- **Local node only.** Pry attaches to processes on the node `gsh` runs on. In a `--remsh` session, `:pry` doesn't see the remote node's processes.
- **No breakpoints without code changes.** Unlike Elixir's `IEx.break!`, you add a `pry` call and recompile.
- **The value can't be replaced.** `:continue` always returns the original value to the paused code.
- **Output can interrupt your typing.** Pry notices and other background output are printed as they happen, even in the middle of a line you're typing.

## Command reference

| Command | What it does |
|---|---|
| `:pry` | Attach to the oldest process waiting at a pry point |
| `:pry list` | List the processes waiting at pry points |
| `:pry <id>` | Attach to a specific waiting process |
| `:continue` | Resume the attached process and return to the main session |
| `:pry off` | Release every waiting process and ignore pry points |
| `:pry on` | Pay attention to pry points again |
