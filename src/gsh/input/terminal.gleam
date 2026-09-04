// src/gsh/input/terminal.gleam

import gleam/int
import gleam/io
import gleam/string

// Terminal control sequences.
// Keeping ANSI handling isolated here so editor logic does not depend on escape codes.

pub fn clear_line() -> Nil {
  io.print("\r\u{001b}[2K")
}

pub fn cursor_left(count: Int) -> Nil {
  io.print("\u{001b}[" <> int_to_string(count) <> "D")
}

pub fn cursor_right(count: Int) -> Nil {
  io.print("\u{001b}[" <> int_to_string(count) <> "C")
}

pub fn move_start() -> Nil {
  io.print("\r")
}

pub fn hide_cursor() -> Nil {
  io.print("\u{001b}[?25l")
}

pub fn show_cursor() -> Nil {
  io.print("\u{001b}[?25h")
}

fn int_to_string(value: Int) -> String {
  // temporary until we import gleam/int
  int.to_string(value)
}

pub fn print(text: String) -> Nil {
  text
  |> string.replace(each: "\n", with: "\r\n")
  |> io.print()
}

pub fn println(text: String) -> Nil {
  text
  |> string.replace(each: "\n", with: "\r\n")
  |> fn(t) { io.print(t <> "\r\n") }
}

pub fn clear_below() -> Nil {
  io.print("\u{001b}[J")
}

pub fn cursor_up(count: Int) -> Nil {
  io.print("\u{001b}[" <> int.to_string(count) <> "A")
}
