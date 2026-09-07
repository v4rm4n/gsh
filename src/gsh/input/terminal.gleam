//// The `terminal` module handles low-level stdout rendering and ANSI escape sequences.
////
//// When operating in TTY raw mode, standard carriage return and newline behaviors 
//// (`\n`) are unhandled by the terminal driver. This module provides an abstraction layer 
//// for rendering output, handling newline translations (`\r\n`), managing visibility, 
//// and controlling 2D hardware cursor movement via ANSI control codes.

// src/gsh/input/terminal.gleam

import gleam/int
import gleam/io
import gleam/string

/// Clears the active terminal line and repositions the cursor to column 0.
/// 
/// Dispatches ANSI `\u{001b}[2K` (clear entire line) preceded by `\r` (carriage return).
pub fn clear_line() -> Nil {
  io.print("\r\u{001b}[2K")
}

/// Repositions the hardware cursor leftward by the specified column count using ANSI `D` sequences.
pub fn cursor_left(count: Int) -> Nil {
  io.print("\u{001b}[" <> int_to_string(count) <> "D")
}

/// Repositions the hardware cursor rightward by the specified column count using ANSI `C` sequences.
pub fn cursor_right(count: Int) -> Nil {
  io.print("\u{001b}[" <> int_to_string(count) <> "C")
}

/// Snaps the cursor position to column 0 of the current line via a raw carriage return (`\r`).
pub fn move_start() -> Nil {
  io.print("\r")
}

/// Suppresses hardware cursor rendering (`\u{001b}[?25l`) to eliminate visual flickering 
/// during full-buffer editor redraws.
pub fn hide_cursor() -> Nil {
  io.print("\u{001b}[?25l")
}

/// Restores hardware cursor rendering (`\u{001b}[?25h`).
pub fn show_cursor() -> Nil {
  io.print("\u{001b}[?25h")
}

// Helper for integer conversion.
fn int_to_string(value: Int) -> String {
  int.to_string(value)
}

/// Outputs string content to stdout while translating standard line feeds (`\n`) 
/// into raw-mode carriage return/line feed pairs (`\r\n`) to prevent staircasing.
pub fn print(text: String) -> Nil {
  text
  |> string.replace(each: "\n", with: "\r\n")
  |> io.print()
}

/// Outputs string content to stdout with `\r\n` line-end translation and appends a trailing `\r\n`.
pub fn println(text: String) -> Nil {
  text
  |> string.replace(each: "\n", with: "\r\n")
  |> fn(t) { io.print(t <> "\r\n") }
}

/// Erases all stdout content from the active cursor position to the bottom of the viewport using ANSI `\u{001b}[J`.
pub fn clear_below() -> Nil {
  io.print("\u{001b}[J")
}

/// Repositions the cursor upward by the specified row count using ANSI `A` sequences.
pub fn cursor_up(count: Int) -> Nil {
  io.print("\u{001b}[" <> int.to_string(count) <> "A")
}

/// Repositions the cursor downward by the specified row count using ANSI `B` sequences.
pub fn cursor_down(count: Int) -> Nil {
  io.print("\u{001b}[" <> int.to_string(count) <> "B")
}

/// Clears the full terminal viewport (`\u{001b}[2J`) and resets cursor placement to home coordinates `(0, 0)` (`\u{001b}[H`).
pub fn clear_screen() -> Nil {
  io.print("\u{001b}[2J\u{001b}[H")
}
