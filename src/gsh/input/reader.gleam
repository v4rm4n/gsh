import gsh/input/key.{
  type Key, ArrowDown, ArrowLeft, ArrowRight, ArrowUp, Backspace, Character,
  Enter, Unknown,
}
import gsh/runtime/runtime

pub fn read_key() -> Key {
  case runtime.get_char() {
    "\r" -> Enter
    "\n" -> Enter
    "\u{007f}" -> Backspace
    "\u{001b}" -> read_escape()
    value -> Character(value)
  }
}

fn read_escape() -> Key {
  case runtime.get_char_timeout(50) {
    Ok("[") ->
      case runtime.get_char_timeout(50) {
        Ok("A") -> ArrowUp
        Ok("B") -> ArrowDown
        Ok("C") -> ArrowRight
        Ok("D") -> ArrowLeft

        Ok(other) -> {
          runtime.pushback(other)
          Unknown
        }

        Error(_) -> Unknown
      }

    Ok(other) -> {
      runtime.pushback(other)
      Unknown
    }

    Error(_) -> Unknown
    // No continuation bytes within 50ms → treat as a bare Escape keypress,
    // not a stuck read.
  }
}
