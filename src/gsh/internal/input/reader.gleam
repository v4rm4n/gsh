// The `reader` module provides an event-driven terminal polling loop for raw-mode TTY input.
//
// When operating in raw mode, user keystrokes are received as unbuffered input streams. 
// This module wraps the low-level `etch` event parser to poll TTY state, filter out non-keyboard 
// signals (such as window resizes or mouse movements), intercept control chord modifiers 
// (e.g., `Ctrl+L` or `Ctrl+Left`), and map raw events into the shell's structured `Key` domain.

// src/gsh/input/reader.gleam

import etch/erlang/input
import etch/event
import gleam/erlang/process
import gleam/option.{None, Some}
import gsh/internal/input/key.{
  type Key as GshKey, ArrowDown, ArrowLeft, ArrowRight, ArrowUp, Backspace,
  Character, CtrlL, CtrlLeft, CtrlRight, End, Enter, Home, Tab, Unknown,
}

/// Polls the raw TTY stream for the next valid keyboard event.
/// 
/// **Polling & CPU Yielding:**
/// * Calls `input.read()` to retrieve pending TTY events without thread blocking.
/// * Yields thread execution via `process.sleep(5)` when no input is available (`None`), 
///   preventing high CPU utilization during idle REPL prompts.
/// * Recursively discards non-keyboard terminal events (e.g., window size changes, mouse clicks) 
///   or stream parse errors until a valid key event is received.
pub fn read_key() -> GshKey {
  // `input.read()` returns Option(Result(Event, EventError))
  case input.read() {
    // We pass the ENTIRE key_event to map_etch_key, not just the code!
    Some(Ok(event.Key(key_event))) -> map_etch_key(key_event)

    // Ignore mouse clicks, resizes, or parse errors and keep reading
    Some(Ok(_)) -> read_key()
    Some(Error(_)) -> read_key()

    // None means no key is pressed yet. Sleep 5ms so we don't fry the CPU!
    None -> {
      process.sleep(5)
      read_key()
    }
  }
}

/// Maps low-level `etch/event.KeyEvent` records to the shell's internal `GshKey` domain type.
/// 
/// **Modifier Disambiguation:**
/// * Intercepts control modifiers (`key_event.modifiers.control`) before checking base keycodes.
/// * Translates terminal control sequences (e.g., `Ctrl+L`, `\f`) to `CtrlL`.
/// * Maps chorded arrow combinations (`Ctrl+Left`, `Ctrl+Right`) to word-boundary movement variants, 
///   reserving base `LeftArrow` and `RightArrow` for single-grapheme cursor navigation.
fn map_etch_key(key_event: event.KeyEvent) -> GshKey {
  let is_ctrl = key_event.modifiers.control

  case key_event.code, is_ctrl {
    event.Char("\f"), _ -> CtrlL
    event.Char("l"), True -> CtrlL
    event.Char("L"), True -> CtrlL

    event.Enter, _ -> Enter
    event.Backspace, _ -> Backspace
    event.Tab, _ -> Tab
    event.UpArrow, _ -> ArrowUp
    event.DownArrow, _ -> ArrowDown

    // 1. Check for Ctrl modifiers BEFORE falling back to standard arrows
    event.LeftArrow, True -> CtrlLeft
    event.RightArrow, True -> CtrlRight

    // 2. Standard arrows
    event.LeftArrow, False -> ArrowLeft
    event.RightArrow, False -> ArrowRight

    // 3. Home and End keys
    event.Home, _ -> Home
    event.End, _ -> End

    event.Char(c), False -> Character(c)
    _, _ -> Unknown
  }
}
