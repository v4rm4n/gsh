# Running Work in the Background

The prompt waits for each evaluation to finish, and `Ctrl+C` exits the whole shell rather than interrupting it. Anything slow or never-ending, like a long `sleep` or a server loop, would lock up your session.

Spawn it instead. The prompt comes straight back, and the output shows up when the work is done:

```gleam
gsh(14)> process.spawn(fn() {
...> process.sleep(1500)
...> io.println("background work done")
...> })
//erl(<0.160.0>)
gsh(15)> background work done
gsh(15)> 1 + 1
2 : Int
```

If the spawned process crashes, GSH reports it as `[exit]` instead of crashing with it.