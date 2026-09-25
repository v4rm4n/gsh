# Talking to Processes

A subject belongs to the process that created it, and everything you type at the prompt runs in the same shell process. So a subject you create at the prompt can receive messages from processes you spawn, in a later prompt:

```gleam
gsh(11)> let subject = process.new_subject()
Subject(//erl(<0.83.0>), //erl(#Ref<0.4287553976.2794979329.241872>))
gsh(12)> process.spawn(fn() { process.send(subject, 42) })
//erl(<0.147.0>)
gsh(13)> process.receive(subject, 1000)
Ok(42)
```

This is the easiest way to get results back from background work, or to call an actor and inspect its reply.