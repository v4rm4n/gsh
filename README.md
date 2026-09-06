# GSH (Gleam Shell)

<!-- [![Package Version](https://img.shields.io/hexpm/v/gsh)](https://hex.pm/packages/gsh)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gsh/) -->

> GSH is an interactive REPL for the [Gleam Programming Language](https://gleam.run/) written in Gleam and Erlang.

**⚠This is still a work in progress tool⚠**

## Latest Bugfixes
- **Robust Multiline Input & String Boundaries:** Replaced manual string-counting with a `glexer` powered token buffer. The shell now accurately detects open strings `(token.UnterminatedString)` and unclosed brackets, safely trapping them in the `...>` continuation prompt instead of crashing the compiler.

- **Smart Variable Shadowing (Pruning):** Fixed a bug where redefining a variable as a function (e.g., `let a = 1` followed by `fn a() { ... }`) would cause a compiler type-mismatch. The REPL state now actively tracks the names of newly evaluated functions, types, and bindings, automatically purging older conflicting definitions from memory.

- **Complex Pattern Destructuring (`let assert`):** Upgraded the token extractor to capture multiple variables from complex assignments. Statements like `let assert Ok(#(user_id, status)) = result` now correctly extract and cache both `user_id` and `status` into the shell's persistent memory, rather than stopping at the first token.

- **Function Definition Recognition:** Fixed an issue where whitespace tokens (`token.Space`) caused the evaluator to miss function declarations. The token router now aggressively filters out whitespace and comments before analysis, ensuring reliable state updates for custom functions.

- **Compiler Warning Suppression for Tuples:** Updated the background caching engine to dynamically generate `let _ = variable` statements for every variable extracted from a destructured list or tuple, preventing Gleam from throwing **"unused variable"** warnings behind the scenes.

- **Standard Library Compatibility:** Replaced the deprecated `trim_left` string function with trim to ensure compatibility with recent Gleam standard library updates.

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
1. `gsh` is a **"Compiler Injection REPL"**.
```plaintext
Gleam code -> Gleam compiler -> Erlang Target -> BEAM
```

2. Previously, `gsh` used to spin up and destroy a **separate BEAM node for every evaluation** (no state persistence). This introduced the **side-effect problem** where code can re-execute. `gsh` currently uses a single persistent BEAM node along with a safety layer where side-effects (like spawning a process or writing to a DB) are wrapped in type-safe **process dictionary cache**. Only the **cached memory pointer** is used in all future evaluations.

3. The **shell's state** is stored in memory for every session. It includes constructs like imports, history, assertion, bindings, functions and types.

4. [etch_erlang](https://etch-erlang.hexdocs.pm/index.html) -- a well-maintained TUI backend is used to render characters properly on the terminal.

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