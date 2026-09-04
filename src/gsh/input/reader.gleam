// src/gsh/input/reader.gleam
import etch/erlang/input
import etch/event
import gleam/erlang/process
import gleam/option.{None, Some}
import gsh/input/key.{
  type Key as GshKey, ArrowDown, ArrowLeft, ArrowRight, ArrowUp, Backspace,
  Character, CtrlL, Enter, Tab, Unknown,
}

pub fn read_key() -> GshKey {
  // `input.read()` returns Option(Result(Event, EventError))
  case input.read() {
    // We now pass the ENTIRE key_event to map_etch_key, not just the code!
    Some(Ok(event.Key(key_event))) -> map_etch_key(key_event)

    // Ignore mouse clicks, resizes, or parse errors and keep reading
    Some(Ok(_)) -> read_key()
    Some(Error(_)) -> read_key()

    // None means no key is pressed yet. Sleep 5ms so we don't fry your CPU!
    None -> {
      process.sleep(5)
      read_key()
    }
  }
}

fn map_etch_key(key_event: event.KeyEvent) -> GshKey {
  let is_ctrl = key_event.modifiers.control

  case key_event.code, is_ctrl {
    // Standard raw mode sends Form Feed (\f) for Ctrl+L
    event.Char("\f"), _ -> CtrlL

    // Modern enhanced terminals send 'l' + Control modifier
    event.Char("l"), True -> CtrlL
    event.Char("L"), True -> CtrlL

    event.Enter, _ -> Enter
    event.Backspace, _ -> Backspace
    event.Tab, _ -> Tab
    event.UpArrow, _ -> ArrowUp
    event.DownArrow, _ -> ArrowDown
    event.LeftArrow, _ -> ArrowLeft
    event.RightArrow, _ -> ArrowRight

    // Only map standard characters if Ctrl is NOT pressed
    event.Char(c), False -> Character(c)
    _, _ -> Unknown
  }
}
