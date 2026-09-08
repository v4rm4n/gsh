// The `key` module defines the domain model for terminal input events.
//
// When the TTY operates in raw mode, user keystrokes—ranging from single UTF-8 
// graphemes to multi-byte ANSI escape sequences (e.g., arrow keys, word navigation)—
// are captured as raw byte streams. This module provides an algebraic data type 
// to abstract low-level TTY sequences into structured events for the editor.

// src/gsh/input/key.gleam

/// Represents a parsed keystroke or control sequence captured from raw terminal input.
pub type Key {
  /// A printable UTF-8 character grapheme (e.g., `"a"`, `"Z"`, `"5"`, `" "`).
  Character(String)

  /// The Return/Enter key, signaling prompt submission or line insertion.
  Enter

  /// The Backspace key, used to remove the character grapheme preceding the cursor.
  Backspace

  /// The Tab key, used to trigger predictive autocompletion and candidate grid menus.
  Tab

  /// The Up Arrow key, used for upward 2D cursor traversal or history retrieval.
  ArrowUp

  /// The Down Arrow key, used for downward 2D cursor traversal or history retrieval.
  ArrowDown

  /// The Left Arrow key, used to move the cursor backward by one grapheme.
  ArrowLeft

  /// The Right Arrow key, used to move the cursor forward by one grapheme.
  ArrowRight

  /// The `Ctrl+L` chord, triggering a screen clear while preserving active buffer state.
  CtrlL

  /// The Home key (or `Fn+Left`), repositioning the cursor to the start of the current line.
  End

  /// The End key (or `Fn+Right`), repositioning the cursor to the end of the current line.
  Home

  /// The `Ctrl+Left` chord, jumping the cursor backward across word boundaries.
  CtrlLeft

  /// The `Ctrl+Right` chord, jumping the cursor forward across word boundaries.
  CtrlRight

  /// Unrecognized or unhandled ANSI escape sequences (e.g., function keys, scroll lock).
  Unknown
}
