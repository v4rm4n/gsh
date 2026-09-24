# Contributing

- GSH is open source under the **Apache-2.0** license, and lives at [github.com/v4rm4n/gsh](https://github.com/v4rm4n/gsh).
- Bug reports, ideas, documentation fixes and code are all welcome. You don't need to write code to help: a clear bug report is a contribution too.

## 1. Opening an Issue

- **Search existing issues first.** If yours is already there, add your details to it rather than opening a new one.
- **One problem per issue.** Two unrelated bugs are easier to track as two issues.

### Reporting a bug

- Include the versions, because terminal and BEAM behaviour vary between them:
  - GSH: type `:v` in the shell
  - Gleam: `gleam --version`
  - Erlang/OTP: the first line GSH prints when it starts
  - Your operating system and terminal
- Paste **the whole session**, from the banner to the error, exactly as it appeared. `:hs` shows what you typed.
- Say what you expected to happen and what happened instead.
- The smaller the reproduction, the faster the fix. If you can, cut it down to one small module and a few prompts.
- For problems with pry or connecting to another node, also include how the app or node was started (the full command, with any cookie removed).

A report that covers all of that looks like this:

````md
**Versions**
GSH 1.2.0, Gleam 1.18.1, Erlang/OTP 28, Void Linux, kitty

**What I did**
```gleam
gsh(1)> import hello
gsh(2)> hello.start()
...
```

**What I expected**
The process to pause at the "name" pry point.

**What happened**
It printed "Hello, ada!" without pausing.
````

### Suggesting a feature

- **Start with the problem**, not the solution: what were you trying to do, and where did GSH get in the way?
- **Sketch the session you wish you could have.** A few lines of imagined `gsh(N)>` input and output say more than a paragraph.
- If Elixir's `iex` or Erlang's `erl` shell already does something similar, mention it. It helps to see how the BEAM ecosystem solved the same problem.

### Security issues

- Some GSH features run code on other processes and nodes. If you find something that could be abused, **don't post the details publicly**. Open an issue asking for a private way to share it.

## 2. Setting Up a Local Copy

- Fork the repository on GitHub, then clone your fork:

```sh
git clone https://github.com/<your-username>/gsh.git
cd gsh
gleam run -m gsh
```

- To try your changes against a real project, point a scratch project at your local copy instead of the published package:

```toml
# gleam.toml of a scratch project, next to your gsh checkout
[dev_dependencies]
gsh = { path = "../gsh" }
```

- Running `gleam run -m gsh` in that project now uses your local GSH. This is the best way to test anything that involves project modules, booted apps or pry.

## 3. The Pull Request Workflow

1. **Talk first for anything big.** For a new command, a change to how evaluation works or anything that touches many files, open an issue to agree on the approach before writing code. Small fixes and doc changes can go straight to a pull request.
2. **Create a branch** from `main` with a descriptive name:

```sh
git switch -c fix/pry-list-ordering
```

3. **Keep the change focused.** One fix or feature per pull request. Unrelated clean-ups belong in their own pull request.
4. **Check it before pushing:**

```sh
gleam format   # formatting is not up for debate
gleam build    # no new warnings
gleam test
```

5. **Try it in a real terminal session.** GSH lives in raw terminal mode, so some bugs only show up interactively. Say which OS and terminal you tested on.
6. **Update this guide** if the change affects anything it describes. Transcripts must be copied from a real session.
7. **Open the pull request** and describe:
   - what changed and why, linking the issue it fixes
   - a before and after transcript for anything the user can see
   - how you tested it
8. **Respond to review** by pushing more commits to the same branch. The pull request updates itself.

## 4. What Makes a Good Contribution

- **Small and focused.** A pull request that does one thing is quick to review and easy to accept.
- **Proven.** A bug fix comes with the session that reproduced the bug, and the same session working afterwards.
- **Safe for the session.** Errors and crashes in evaluated code must never take the shell down. New features should keep that promise.
- **Documented.** If users will notice the change, this guide says how it works.

### Where help is especially welcome

- **Documentation:** typos, unclear explanations, outdated transcripts and missing examples.
- **Terminal support:** trying GSH on macOS, Windows and less common terminals, and reporting what breaks.
- **Known limitations:** anything listed under *Limitations* in this guide is fair game. Examples include redrawing the line you're typing after background output, pry on remote nodes, and breakpoints without code changes. These need design discussion, so open an issue first.

## 5. Improving These Docs

- Every page of this guide is a Markdown file. Fixes go through a pull request, the same way as code.
- Keep the existing style: a few short bullets explaining the idea, followed by a transcript that shows it.
- Transcripts must come from a real GSH session, so readers can trust them. Prompt numbers and pids don't need to match anyone else's.

## License

By contributing, you agree that your contributions are licensed under the project's **Apache-2.0** license.