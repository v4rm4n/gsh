// src/input/reader.gleam

import gsh/runtime/runtime

import gsh/input/key.{
  type Key, ArrowDown, ArrowLeft, ArrowRight, ArrowUp, Backspace, Character,
  Enter, Unknown,
}

pub fn read_key() -> Key {
  case runtime.get_char() {
    "\r" -> {
      // Windows console in line mode delivers "\r\n" as one unit for Enter.
      // On Unix this branch is never hit — ICRNL already turns \r into \n
      // before we see it — so this peek can't block waiting on a keystroke.
      case runtime.get_char() {
        "\n" -> Nil
        other -> runtime.pushback(other)
        // see note below
      }
      Enter
    }

    "\n" -> Enter
    "\u{007f}" -> Backspace
    "\u{001b}" -> read_escape()
    value -> Character(value)
  }
}

fn read_escape() -> Key {
  let second = runtime.get_char()

  case second {
    "[" -> {
      let third = runtime.get_char()

      case third {
        "A" -> ArrowUp
        "B" -> ArrowDown
        "C" -> ArrowRight
        "D" -> ArrowLeft

        _ -> Unknown
      }
    }

    _ -> Unknown
  }
}
