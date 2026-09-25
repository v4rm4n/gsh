# Integrations

- GSH runs in any terminal, so it works alongside any editor.
- Editor integrations go a step further: they start GSH for your project and let you send code to it straight from your source files.

## Emacs: gleam-repl

- **[gleam-repl](https://github.com/wmealing/gleam-repl)**, by [Wade Mealing](https://github.com/wmealing), is a Gleam REPL for Emacs built on GSH.
- It gives you a dedicated REPL buffer, plus keys to send the current line, a region or the whole buffer from your Gleam source to it, in the style of Emacs's Erlang shell support.
- The REPL buffer is a real terminal emulator (`term-mode`, the same one `M-x ansi-term` uses). That's needed because GSH puts the terminal into raw mode and runs its own line editor, so everything from the rest of this guide works inside it.
- gleam-repl is at an early stage (version 0.2.0) and isn't on MELPA yet, so you install it from GitHub.

### Requirements

- **Emacs 29 or newer**, for `gleam-ts-mode` (gleam-repl itself needs Emacs 26.1 or newer).
- **`gleam`** on your `PATH`.
- **GSH** in each project you want a REPL for:

```sh
gleam add gsh --dev
```

### Installing

1. Clone gleam-repl into your Emacs directory:

```sh
git clone https://github.com/wmealing/gleam-repl.git ~/.emacs.d/lisp/gleam-repl
```

2. Add this to `~/.emacs.d/init.el`:

```elisp
;; MELPA, for gleam-ts-mode
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

;; gleam-repl, cloned from GitHub
(add-to-list 'load-path "~/.emacs.d/lisp/gleam-repl")
(require 'gleam-repl)

;; Open .gleam files in gleam-ts-mode, with gleam-repl's keys enabled
(add-to-list 'auto-mode-alist '("\\.gleam\\'" . gleam-ts-mode))
(add-hook 'gleam-ts-mode-hook #'gleam-repl-minor-mode)

;; Emacs's lockfiles for unsaved buffers break gsh (see Known issues)
(setq create-lockfiles nil)
```

3. Restart Emacs, then install `gleam-ts-mode` with `M-x package-install RET gleam-ts-mode RET`.
4. Install the Gleam tree-sitter grammar with `M-x treesit-install-language-grammar RET gleam RET`. Choose to build it interactively, give the repository URL `https://github.com/gleam-lang/tree-sitter-gleam`, and accept the defaults for the rest.

### Using it

- Open any `.gleam` file in your project and press `C-c C-z`. gleam-repl starts GSH in the project's root (the closest directory with a `gleam.toml`) and shows the REPL buffer.
- `M-x gleam-repl` (or `M-x run-gleam`) does the same. With a prefix argument (`C-u M-x gleam-repl`), it asks which project directory to use.
- From a Gleam source buffer:

| Keys | What it does |
|---|---|
| `C-c C-z` | Show the REPL, starting it if needed |
| `C-c C-l` | Send the whole buffer |
| `C-c C-r` | Send the selected region |
| `C-c C-e` or `C-M-x` | Send the current line |
| `C-c C-k` | Recompile the project (`:cc`) |
| `C-c C-d` | Show docs for the symbol at point (`:h`) |

- Sending a region that holds a `fn` or `type` definition defines it in the REPL, exactly as if you'd typed it at the `gsh(N)>` prompt.
- Inside the REPL buffer you're talking to GSH directly, so everything works as in a terminal: `:h`, `:b`, `:cc`, `:pry`, `:q`, Up and Down for history, and `Ctrl+L` to clear.
- `C-c C-j` and `C-c C-k` in the REPL buffer switch between `term-mode`'s line mode and char mode, as in any Emacs terminal.

### Configuration

You can change these with `M-x customize-group RET gleam-repl RET`, or with `setq` in your `init.el`:

| Variable | Default | What it controls |
|---|---|---|
| `gleam-repl-program` | `"gleam"` | The program that starts GSH |
| `gleam-repl-program-args` | `("run" "-m" "gsh")` | Its arguments. Add apps to boot after `"--"`, e.g. `("run" "-m" "gsh" "--" "my_app")` |
| `gleam-repl-buffer-name` | `"*gleam*"` | The REPL buffer's name |
| `gleam-repl-send-line-delay` | `0.05` | Seconds to wait between lines when sending several |
| `gleam-repl-pop-to-buffer` | `t` | Whether sending code also shows the REPL |

### Known issues

- **Unsaved buffers break evaluation.** Emacs creates a lockfile (like `.#hello.gleam`) next to every file with unsaved changes. GSH compiles everything in `src/`, and the Gleam compiler fails on that lockfile. The `(setq create-lockfiles nil)` line above prevents it. Without it, save your files before sending code.
- **`C-c C-k` and `C-c C-d` use old command names.** gleam-repl 0.2.0 sends `compile` and `h <name>`, which current GSH doesn't recognise, so both fail with `Unknown variable`. Until gleam-repl is updated, add this to your `init.el` after `(require 'gleam-repl)`:

```elisp
;; gleam-repl 0.2.0 sends gsh's old command names. Use the current ones.
(defun gleam-repl-compile ()
  "Recompile the host project (gsh `:cc')."
  (interactive)
  (gleam-repl--send ":cc"))

(defun gleam-repl-doc (symbol)
  "Show gsh's documentation for SYMBOL (gsh `:h')."
  (interactive
   (list (read-string "Docs for (module or module.function): "
                      (thing-at-point 'symbol t))))
  (gleam-repl--send (concat ":h " symbol)))
```

- **Large regions can arrive too fast.** gleam-repl types your code into GSH one line at a time. If a big region or deeply nested multi-line code gets garbled, increase `gleam-repl-send-line-delay`.

### Reporting problems

- Problems with the Emacs side (keys, buffers, installation) belong on [gleam-repl's issue tracker](https://github.com/wmealing/gleam-repl/issues).
- Problems with GSH itself belong on [GSH's](https://github.com/v4rm4n/gsh/issues). If you're not sure which, try the same thing in GSH in a plain terminal: if it happens there too, it's GSH.

## Adding an integration

- Built something that connects GSH to another editor or tool? See **[Contributing](4_contributing.md)**: a pull request that adds it to this chapter is very welcome.