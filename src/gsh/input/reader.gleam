// src/input/reader.gleam

import gsh/runtime/runtime

pub fn read_char() -> String {
  runtime.get_char()
}
