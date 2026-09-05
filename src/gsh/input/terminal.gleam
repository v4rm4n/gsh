//// The `terminal` module handles low-level standard output and ANSI escape sequences.
////
//// Because the REPL operates in terminal raw mode, standard formatting rules 
//// (like a simple `\n` moving the cursor down and to the left) no longer apply. 
//// This module provides a clean API for rendering text and manually manipulating 
//// the 2D position of the cursor on the screen without leaking escape codes 
//// into the rest of the application.

// src/gsh/input/terminal.gleam

import gleam/int
import gleam/io
import gleam/string

/// Clears the entire current line and returns the cursor to the leftmost column.
/// Uses the ANSI sequence `[2K` (clear entire line) and `\r` (carriage return).
pub fn clear_line() -> Nil {
  io.print("\r\u{001b}[2K")
}

/// Moves the terminal cursor to the left by the specified number of columns.
pub fn cursor_left(count: Int) -> Nil {
  io.print("\u{001b}[" <> int_to_string(count) <> "D")
}

/// Moves the terminal cursor to the right by the specified number of columns.
pub fn cursor_right(count: Int) -> Nil {
  io.print("\u{001b}[" <> int_to_string(count) <> "C")
}

/// Snaps the cursor directly to the first column of the current line.
pub fn move_start() -> Nil {
  io.print("\r")
}

/// Hides the hardware terminal cursor. Useful when redrawing large 
/// multiline buffers to prevent visual flickering.
pub fn hide_cursor() -> Nil {
  io.print("\u{001b}[?25l")
}

/// Restores the hardware terminal cursor to visible.
pub fn show_cursor() -> Nil {
  io.print("\u{001b}[?25h")
}

// Helper for integer conversion.
fn int_to_string(value: Int) -> String {
  int.to_string(value)
}

/// Prints text to the screen. In raw mode, a standard newline (`\n`) only moves 
/// the cursor down, not to the start of the next line. This safely replaces 
/// all newlines with CRLF (`\r\n`) so text renders normally.
pub fn print(text: String) -> Nil {
  text
  |> string.replace(each: "\n", with: "\r\n")
  |> io.print()
}

/// Prints text to the screen and appends a CRLF (`\r\n`) to jump to the next line.
pub fn println(text: String) -> Nil {
  text
  |> string.replace(each: "\n", with: "\r\n")
  |> fn(t) { io.print(t <> "\r\n") }
}

/// Clears all terminal text from the current cursor position down to the bottom 
/// of the screen. Used by the editor to wipe old multiline blocks before redrawing.
pub fn clear_below() -> Nil {
  io.print("\u{001b}[J")
}

/// Moves the terminal cursor straight up by the specified number of rows.
pub fn cursor_up(count: Int) -> Nil {
  io.print("\u{001b}[" <> int.to_string(count) <> "A")
}

/// Moves the terminal cursor straight down by the specified number of rows.
pub fn cursor_down(count: Int) -> Nil {
  io.print("\u{001b}[" <> int_to_string(count) <> "B")
}

/// Clears the entire terminal screen and resets the cursor to the top-left (0,0) position.
pub fn clear_screen() -> Nil {
  io.print("\u{001b}[2J\u{001b}[H")
}
