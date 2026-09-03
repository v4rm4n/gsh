// src/gsh/input/reader.gleam
import etch/erlang/input
import etch/event
import gleam/erlang/process
import gleam/option.{None, Some}
import gsh/input/key.{
  type Key as GshKey, ArrowDown, ArrowLeft, ArrowRight, ArrowUp, Backspace,
  Character, Enter, Unknown,
}

pub fn read_key() -> GshKey {
  // `input.read()` returns Option(Result(Event, EventError))
  case input.read() {
    Some(Ok(event.Key(key_event))) -> map_etch_key(key_event.code)

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

fn map_etch_key(code: event.KeyCode) -> GshKey {
  case code {
    event.Enter -> Enter
    event.Backspace -> Backspace
    // These are the correct KeyCode names from etch!
    event.UpArrow -> ArrowUp
    event.DownArrow -> ArrowDown
    event.LeftArrow -> ArrowLeft
    event.RightArrow -> ArrowRight
    event.Char(c) -> Character(c)
    _ -> Unknown
  }
}
