# GSH: The Advanced Usage Guide

> Welcome to the advanced usage guide for GSH (Gleam SHell), a comprehensive manual for leveraging the BEAM's interactive capabilities directly from Gleam.

This book bypasses the basics of the Gleam language to focus exclusively on orchestrating live applications, manipulating the Erlang VM, and customizing your REPL environment.

Because GSH is built natively on Erlang primitives—compiling Gleam directly to in-memory bytecode—it provides access to the same legendary debugging superpowers found in Elixir's iex and Erlang's erl.

This guide is designed for developers who want to push GSH beyond a simple scratchpad and use it as a full-fledged development and production-debugging orchestrator.

## What This Book Covers

1. **Automated Environment Configuration ([tools.gsh])**  
Eliminate repetitive setup by deeply integrating GSH into your project's `gleam.toml`. We will cover how to pre-load critical stdlib and project modules, auto-start background OTP supervision trees, and resolve dependency pathing so your shell is perfectly customized the second it boots.
---
2. **Distributed Erlang & Remote Shells**  
The holy grail of BEAM development is **zero-downtime remote inspection**. We will explore how to boot GSH with distributed networking flags (`--sname`, `--cookie`), connect your local terminal to live remote production nodes, and evaluate code across the network.
---
3. **Remote Hot-Swapping & Compilation**  
We will look at how the `:cc` command bridges local compilation with remote execution. You will learn how GSH extracts raw `.beam` binaries from your local disk and **injects** them over the wire into a live server's RAM via Erlang Remote Procedure Calls (`rpc`), patching code without dropping connections.
---
4. **Process Introspection & The `:pry` Tool**  
A deep dive into advanced debugging techniques. We will cover how to use `:pry` to freeze execution, intercept live actors, and drop into a REPL session directly inside the lexical scope of a running background process.
---
5. `Native VM Tooling`  
Mastering the built-in commands like `:tree` for visualizing process hierarchies in the terminal, managing I/O group leaders to prevent log flooding, and safely navigating the process dictionary.