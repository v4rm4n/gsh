# GSH: Usage Guide

> Welcome to the usage guide for GSH (Gleam SHell), a comprehensive manual for leveraging the BEAM's interactive capabilities directly from Gleam.

## Getting Started

- Add `gsh` to your project as a development dependency, then run it from the project root:

```sh
gleam add gsh --dev
gleam run -m gsh
```

- Your project's modules are ready to `import` straight away.
- GSH runs on the Erlang target (the BEAM) only. It doesn't support the JavaScript target.

## What This Book Covers

1. **[Basics](1_basics.md)**  
Everyday use of the shell: evaluating expressions and reading compiler errors, stateful bindings with Gleam's lexical shadowing (side effects run exactly once), defining types and functions right at the prompt, redefining them and the limits of that, and multi-line input with `Ctrl+X` to abort.
---
2. **[Prying](2_prying.md)**  
REPL-driven debugging: pause a live process at a `pry` call in your code, attach the shell to it, evaluate code inside that process, and let it continue. Also covers handling several paused processes, switching pry points off, the safety nets that keep your session alive, and the current limitations.
---
3. **[Contributing](3_contributing.md)**  
How to report bugs, suggest features, set up a local copy of GSH, and send a pull request, including what makes a contribution easy to accept.

## Reading the Examples

- Every example is a transcript of a real session.
- `gsh(N)>` is the prompt, `...>` continues a multi-line input, and `pry(<label>)>` means you're attached to a paused process.
- Prompt numbers and pids (like `<0.115.0>`) will differ on your machine.

## Contributing

GSH and this guide are open source, and there's plenty of room to grow. Found a bug, a confusing page or an outdated transcript? Have an idea for the shell? See **[Contributing](3_contributing.md)** for how to open an issue or send a pull request to [github.com/v4rm4n/gsh](https://github.com/v4rm4n/gsh).