//// The `key` module defines the semantic domain model for terminal input.
////
//// When the terminal is in raw mode, every keystroke (including multi-byte 
//// ANSI escape sequences for arrow keys) is read directly. This module 
//// provides a clean algebraic data type to represent those inputs, abstracting 
//// away the low-level byte parsing so the editor can simply pattern match 
//// on meaningful events.

// src/gsh/input/key.gleam

/// Represents a parsed keystroke or terminal control event.
pub type Key {
  /// A standard printable character (e.g., "a", "A", "1", " ", or symbols).
  Character(String)

  /// The Enter / Return key, used to submit a command or create a new line 
  /// in multiline blocks.
  Enter

  /// The Backspace key, used to delete the character to the left of the cursor.
  Backspace

  /// The Tab key, used to trigger the autocomplete engine and floating menu.
  Tab

  /// The Up Arrow key, typically used to traverse backward through REPL history.
  ArrowUp

  /// The Down Arrow key, typically used to traverse forward through REPL history.
  ArrowDown

  /// The Left Arrow key, used to move the cursor backward within the text buffer.
  ArrowLeft

  /// The Right Arrow key, used to move the cursor forward within the text buffer.
  ArrowRight

  /// The Ctrl+L chord, which is the standard Unix terminal shortcut for clearing the screen.
  CtrlL

  /// Any unrecognized or unhandled control sequence (e.g., Page Up, Home, End).
  Unknown
}
