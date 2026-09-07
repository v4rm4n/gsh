# GSH (Gleam Shell)

[![Package Version](https://img.shields.io/hexpm/v/gsh)](https://hex.pm/packages/gsh)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gsh/)

> GSH is an interactive REPL for the [Gleam Programming Language](https://gleam.run/) written in Gleam and Erlang.

## Latest Bugfixes
- **Zero-Collision Dynamic Runtime:** Replaced static file evaluations with dynamically generated, prompt-indexed modules (`gsh_eval_X.gleam`), eliminating BEAM bytecode caching conflicts and stale memory state across evaluation loops.
- **Masked Internal Evaluator Traces:** Updated error formatting (`hide_internal_path`) to strip dynamic generator file paths from Gleam compiler errors and stack traces, cleanly replacing them with a native `REPL` origin identifier.
- **Elixir-Style In-REPL Documentation Engine:** Introduced `h <module>` and `h <module.function>` inspection powered by a live `glexer` tokenization pipeline, rendering ANSI-highlighted markdown documentation and type signatures directly in the terminal.
- **Dynamic Variable Shadowing & Pattern Destructuring:** Re-engineered variable binding extraction to track single assignments (`let x = 1`) and complex pattern destructuring (`let #(a, b) = pair`), preserving accurate variable scope across evaluations.
- **Spurious Warning Suppression & Cleanup:** Optimized module generation headers (`source.header`) to eliminate unused import/formatter compiler warnings and guaranteed immediate disk cleanup of temporary evaluation files.

## Installation
Add `gsh` to your project as a development dependency:

```bash
gleam add gsh --dev
```

## Usage
`gsh` can either be used as a standalone REPL or a live-app bootloader.

### Standalone
```bash
gleam run -m gsh
```

### App loader
```bash
gleam run -m gsh -- my_app worker_pool bg_module_1
```

## Built-in Commands
GSH includes several built-in commands to manage your session:
- `h()` - Show the help menu
- `v()` - Show the current GSH version
- `l()` - List all currently active variable bindings
- `history()` - Show the history of executed commands
- `compile` - Recompile the host Gleam project without leaving the shell
- `clear` - Clear the terminal screen (or Ctrl + L)
- `pid()` - Create a pid from a string (e.g. pid("<0.34.0>"))
- `h <module/function>` - Retrieve module/function documentation
- `k()` - Exit the shell

## Target limitations
> **Note:** GSH is heavily tied to the Erlang VM (BEAM) for state persistence and dynamic evaluation. It **does not** support the JavaScript target.

## Why a REPL?
After using Elixir's `iex`, OCaml's `utop` or even Rust's `evcxr`. I really wanted to build a tool for Gleam that gets me closer to the BEAM. **GSH**, expanded as **Gleam SHell** is a materialization of that dream.

### REPL use cases
  - Function & module debugging with mock data.
  - Interaction with actors & the supervision tree.
  - Quick scratch-pad for validating logic & trivial constructs.
  - Working with the Gleam ecosystem and libraries.

## Demo
- Tab-completion with auto suggestions
![Auto Suggestions](demo/auto_sug.png)

- Input/Output syntax highlighting + Multi-line + Pattern matching
![I/O mul](demo/io_mul.png)

- Processes & built-ins (pid)
![proc_pid](demo/proc_pid.png)


## How it works
### In-RAM Fast Compilation Pipeline (Sub-20ms Latency)
Rather than spawning heavy OS subprocesses with `gleam build` or writing `.beam` files to disk, GSH compiles and executes code directly in memory:

  - **Fast AST Emission:** Executes gleam compile-package --no-beam to instantly convert Gleam code into raw Erlang (.erl) source, bypassing disk artifact writes.

  - **Native In-VM Bytecode Loading:** Uses an Erlang FFI bridge (compile:file with [binary] + code:load_binary) to compile .erl files directly into RAM and hot-load the bytecode into the running VM.

  - **Result:** Evaluation latency drops from ~375ms down to ~18ms (~20x speedup), delivering real-time interactive feedback below human perception thresholds.

### Single Persistent Node & Side-Effect Memoization
GSH runs inside a single, long-lived Erlang VM node. To prevent historic variable assignments from re-executing side effects (like spawning processes, printing logs, or hitting a database) during session re-evaluations:

  - Each `let` binding is automatically wrapped in a type-safe Process Dictionary cache.

  - Subsequent prompts reuse the cached memory pointer, ensuring side-effecting code executes exactly once.

### Stateful Lexical Scope Tracking
Session scope is tracked in an explicit ShellState record across evaluations. GSH dynamically merges, prunes, and re-injects:

  - Active variable bindings and shadowed variables

  - Global module imports and custom type definitions

  - Interactive function declarations and command history

### Raw Terminal TUI & I/O Engine
Powered by `etch_erlang`, GSH toggles terminal raw mode on the fly to support character-by-character key handling, live TAB completion, multiline syntax buffering (`...>`), and ANSI color formatting without corrupting background process stdout.

## Feature set comparison with `iex`

| Feature | GSH (Gleam Shell) | IEx (Interactive Elixir) |
|---|---|---|
| **Live App Bootstrapping** | `gleam run -m gsh -- app` | `iex -S mix` |
| **Syntax** | Gleam (Rust-like, strict types) | Elixir (Ruby-like, dynamic) |
| **Syntax Highlighting** | Yes (ANSI-based) | Yes (Configurable ANSI) |
| **Type System** | Static (recompiles on the fly) | Dynamic |
| **Evaluation Engine** | File-backed generation + Hot code reload | Direct Erlang AST evaluation |
| **Side-Effect Safety** | Yes (Process Dictionary memoization) | Yes (Native to AST loop) |
| **VM State Persistence** | Yes (Actors, PIDs, ETS stay alive) | Yes |
| **Fault Tolerance** | Yes (Catches `Badarg` / VM crashes) | Yes |
| **Multiline Input** | Yes (Buffer completion) | Yes (Native AST parsing) |
| **Built-in Helpers** | `pid()` (easily extensible) | `h()`, `i()`, `v()`, `pid()`, etc. |
| **Autocomplete** | Keywords, bound vars, module exports | Deeply context-aware + docstrings |

## Elixir-Style Live Documentation (h command)

While the Gleam compiler traditionally strips `///` comments during compilation (meaning compiled bytecode lacks documentation metadata), GSH bypasses this limitation entirely. By combining intelligent package path resolution with a live `glexer` token stream, the shell locates raw `.gleam` source files, lexes them on the fly, and extracts both module-level documentation and function signatures. This brings the legendary, tactile developer experience of Elixir's `iex` to Gleam, allowing developers to read rich, ANSI-formatted markdown documentation directly in the REPL without requiring modifications to the Gleam compiler.

## Acknowledgments
GSH stands on the shoulders of some excellent Gleam libraries:
- [etch_erlang](https://hex.pm/packages/etch) for non-blocking raw terminal events.
- [contour](https://hex.pm/packages/contour) for beautiful ANSI syntax highlighting.
- [shellout](https://hex.pm/packages/shellout) for seamless Gleam compiler orchestration.

## Contributing

Contributions are massively appreciated! A REPL would be a nice to have tool in the Gleam ecosystem, and there is plenty of room to grow. 

<!-- ## License
This project is licensed under the [Apache-2.0](LICENSE). -->