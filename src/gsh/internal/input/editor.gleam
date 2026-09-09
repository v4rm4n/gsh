// The `editor` module implements a custom multiline line-editing engine built for raw-mode TTY input.
//
// Standard input primitives (like `erlang:get_line`) block thread execution and lack support 
// for custom keybindings, autocomplete menus, or 2D cursor traversal. This module replaces 
// standard terminal input by capturing keystrokes directly, translating 1D buffer indices into 
// 2D terminal coordinates, rendering floating autocompletion menus, and managing interactive 
// command history navigation.

// src/gsh/iinternal/nput/editor.gleam

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gsh/internal/input/display
import gsh/internal/input/key.{
  ArrowDown, ArrowLeft, ArrowRight, ArrowUp, Backspace, Character, CtrlL,
  CtrlLeft, CtrlRight, End, Enter, Home, Tab,
}
import gsh/internal/input/reader
import gsh/internal/input/terminal

/// Tracks the active state of an interactive prompt session.
pub type Editor {
  Editor(
    /// The current raw input text buffer.
    buffer: String,
    /// The 1D index offset of the cursor within the input buffer string.
    cursor: Int,
    /// Chronological list of previously executed commands.
    history: List(String),
    /// Current pointer index when navigating through command history (-1 when typing active input).
    history_index: Int,
    /// Temporarily stores unsubmitted buffer state when scrolling upwards into history.
    saved_buffer: Option(String),
    /// Pre-rendered multi-column string grid containing active autocompletion suggestions.
    menu: Option(String),
  )
}

/// Initializes the interactive editor state and initiates the blocking keystroke listener loop.
/// 
/// Returns the final, accumulated input string once the user submits execution via the `Enter` key.
pub fn read_line(
  prompt: String,
  history: List(String),
  completions: List(String),
) -> String {
  loop(
    prompt,
    Editor(
      buffer: "",
      cursor: 0,
      history: history,
      history_index: -1,
      saved_buffer: None,
      menu: None,
    ),
    completions,
  )
}

// --- 2D MULTILINE RENDERING ENGINE ---

/// Redraws the terminal prompt and buffer state in response to keystroke mutations.
/// 
/// **Rendering Sequence:**
/// 1. Calculates the current cursor line offset and returns the terminal cursor to the prompt origin.
/// 2. Clears the multiline block and any active floating menus using ANSI escape codes.
/// 3. Redraws the prompt along with the syntax-highlighted input buffer via `display.render`.
/// 4. Renders the floating autocomplete grid below the active buffer if present.
/// 5. Invokes `sync_cursor` to reposition the terminal cursor to its relative 2D coordinates.
fn render_editor(
  prompt: String,
  old_editor: Editor,
  new_editor: Editor,
) -> Nil {
  // 1. Jump back up to the prompt line from wherever the cursor CURRENTLY is
  let before_cursor = string.slice(old_editor.buffer, 0, old_editor.cursor)
  let cursor_y = list.length(string.split(before_cursor, "\n")) - 1
  case cursor_y > 0 {
    True -> terminal.cursor_up(cursor_y)
    False -> Nil
  }

  // 2. Wipe the entire multiline block clean
  terminal.move_start()
  // Explicitly clear from cursor to end of screen!
  terminal.print("\u{001b}[J")

  // 3. Draw the new prompt and buffer
  display.render(prompt, new_editor.buffer)

  // 4. Draw the floating menu if it exists
  case new_editor.menu {
    Some(grid) -> {
      let lines_to_go_up = list.length(string.split(grid, "\n"))
      terminal.print("\n" <> grid)
      terminal.cursor_up(lines_to_go_up)
      terminal.move_start()
      display.render(prompt, new_editor.buffer)
    }
    None -> Nil
  }

  // 5. Snap the cursor to its correct 2D position
  sync_cursor(prompt, new_editor)
}

/// Calculates the target buffer offset when moving the cursor vertically up one line within a multiline string.
fn move_cursor_up(buffer: String, cursor: Int) -> Int {
  let before = string.slice(buffer, 0, cursor)
  let parts = string.split(before, "\n")
  case list.length(parts) > 1 {
    False -> cursor
    // Already on top line
    True -> {
      let current_col = string.length(result.unwrap(list.last(parts), ""))
      let prev_line =
        result.unwrap(list.last(list.take(parts, list.length(parts) - 1)), "")
      let new_col = int.min(current_col, string.length(prev_line))
      let up_to_prev =
        string.length(before) - current_col - string.length(prev_line) - 1
      up_to_prev + new_col
    }
  }
}

/// Calculates the target buffer offset when moving the cursor vertically down one line within a multiline string.
fn move_cursor_down(buffer: String, cursor: Int) -> Int {
  let before = string.slice(buffer, 0, cursor)
  let after = string.slice(buffer, cursor, string.length(buffer) - cursor)
  let current_col =
    string.length(result.unwrap(list.last(string.split(before, "\n")), ""))

  case string.split_once(after, "\n") {
    Error(_) -> cursor
    // No newline below
    Ok(#(_, next_remainder)) -> {
      let next_line =
        result.unwrap(list.first(string.split(next_remainder, "\n")), "")
      let new_col = int.min(current_col, string.length(next_line))
      let dist_to_eol =
        string.length(result.unwrap(list.first(string.split(after, "\n")), ""))
      cursor + dist_to_eol + 1 + new_col
    }
  }
}

/// Translates the 1D `editor.cursor` buffer index into 2D terminal coordinates and dispatches ANSI cursor movement codes.
fn sync_cursor(prompt: String, editor: Editor) -> Nil {
  // Calculate how many lines tall the buffer is, and which line the cursor is on
  let total_lines = list.length(string.split(editor.buffer, "\n")) - 1
  let before_cursor = string.slice(editor.buffer, 0, editor.cursor)
  let cursor_y = list.length(string.split(before_cursor, "\n")) - 1

  // Move UP from the bottom of the buffer to the target line
  let lines_to_go_up = total_lines - cursor_y
  case lines_to_go_up > 0 {
    True -> terminal.cursor_up(lines_to_go_up)
    False -> Nil
  }

  // Calculate the X position (only the first line has the prompt width pushing it!)
  let current_line =
    result.unwrap(list.last(string.split(before_cursor, "\n")), "")
  let prompt_offset = case cursor_y == 0 {
    True -> string.length(prompt)
    False -> 0
  }
  let target_x = prompt_offset + string.length(current_line)

  // Move RIGHT to the target X coordinate
  terminal.move_start()
  case target_x > 0 {
    True -> terminal.cursor_right(target_x)
    False -> Nil
  }
}

/// The main event loop for interactive editing. Blocks until a keystroke is received via `reader.read_key`, 
/// processes buffer or cursor state mutations, re-renders the terminal, and recurses.
fn loop(prompt: String, editor: Editor, completions: List(String)) -> String {
  let key = reader.read_key()

  case key {
    Enter -> {
      // 1. Create a final state with the cursor pushed to the very end of the text
      // and the autocomplete menu explicitly closed.
      let end_cursor = string.length(editor.buffer)
      let updated = Editor(..editor, cursor: end_cursor, menu: None)

      // 2. Run the renderer one last time. This erases any floating menus 
      // and places the terminal cursor safely at the very end of your code
      // so we don't accidentally wipe the right side of your input!
      render_editor(prompt, editor, updated)

      // 3. Move to a fresh line for the evaluator's output
      terminal.println("")
      editor.buffer
    }

    CtrlL -> {
      terminal.clear_screen()
      // Fake an old editor at cursor 0 so it doesn't try to jump up!
      let fake_old = Editor(..editor, buffer: "", cursor: 0)
      render_editor(prompt, fake_old, editor)
      loop(prompt, editor, completions)
    }

    ArrowUp -> {
      let before_cursor = string.slice(editor.buffer, 0, editor.cursor)
      let cursor_y = list.length(string.split(before_cursor, "\n")) - 1

      case cursor_y == 0 {
        // We are on the top line, go to history!
        True -> {
          let updated = Editor(..history_up(editor), menu: None)
          render_editor(prompt, editor, updated)
          loop(prompt, updated, completions)
        }
        // We are inside a multiline block, just move the cursor up!
        False -> {
          let updated =
            Editor(
              ..editor,
              cursor: move_cursor_up(editor.buffer, editor.cursor),
              menu: None,
            )
          render_editor(prompt, editor, updated)
          loop(prompt, updated, completions)
        }
      }
    }

    ArrowDown -> {
      let before_cursor = string.slice(editor.buffer, 0, editor.cursor)
      let cursor_y = list.length(string.split(before_cursor, "\n")) - 1
      let total_lines = list.length(string.split(editor.buffer, "\n")) - 1

      case cursor_y == total_lines {
        // We are on the bottom line, go to history!
        True -> {
          let updated = Editor(..history_down(editor), menu: None)
          render_editor(prompt, editor, updated)
          loop(prompt, updated, completions)
        }
        // We are inside a multiline block, just move the cursor down!
        False -> {
          let updated =
            Editor(
              ..editor,
              cursor: move_cursor_down(editor.buffer, editor.cursor),
              menu: None,
            )
          render_editor(prompt, editor, updated)
          loop(prompt, updated, completions)
        }
      }
    }

    ArrowLeft -> {
      let new_cursor = int.max(0, editor.cursor - 1)
      let updated = Editor(..editor, cursor: new_cursor, menu: None)
      render_editor(prompt, editor, updated)
      loop(prompt, updated, completions)
    }

    ArrowRight -> {
      let max_cursor = string.length(editor.buffer)
      let new_cursor = int.min(max_cursor, editor.cursor + 1)
      let updated = Editor(..editor, cursor: new_cursor, menu: None)
      render_editor(prompt, editor, updated)
      loop(prompt, updated, completions)
    }

    Character(value) -> {
      let left = string.slice(editor.buffer, 0, editor.cursor)
      let right =
        string.slice(
          editor.buffer,
          editor.cursor,
          string.length(editor.buffer) - editor.cursor,
        )
      let updated =
        Editor(
          ..editor,
          buffer: left <> value <> right,
          cursor: editor.cursor + string.length(value),
          menu: None,
        )

      render_editor(prompt, editor, updated)
      loop(prompt, updated, completions)
    }

    Backspace -> {
      case editor.cursor > 0 {
        False -> loop(prompt, editor, completions)
        True -> {
          let left = string.slice(editor.buffer, 0, editor.cursor - 1)
          let right =
            string.slice(
              editor.buffer,
              editor.cursor,
              string.length(editor.buffer) - editor.cursor,
            )
          let updated =
            Editor(
              ..editor,
              buffer: left <> right,
              cursor: editor.cursor - 1,
              menu: None,
            )

          render_editor(prompt, editor, updated)
          loop(prompt, updated, completions)
        }
      }
    }

    Home -> {
      // Jump to the start of the current line
      let before_cursor = string.slice(editor.buffer, 0, editor.cursor)
      let current_line_len =
        string.length(result.unwrap(
          list.last(string.split(before_cursor, "\n")),
          "",
        ))
      let new_cursor = int.max(0, editor.cursor - current_line_len)

      let updated = Editor(..editor, cursor: new_cursor, menu: None)
      render_editor(prompt, editor, updated)
      loop(prompt, updated, completions)
    }

    End -> {
      // Jump to the end of the current line
      let after_cursor =
        string.slice(
          editor.buffer,
          editor.cursor,
          string.length(editor.buffer) - editor.cursor,
        )
      let remainder_len =
        string.length(result.unwrap(
          list.first(string.split(after_cursor, "\n")),
          "",
        ))
      let new_cursor =
        int.min(string.length(editor.buffer), editor.cursor + remainder_len)

      let updated = Editor(..editor, cursor: new_cursor, menu: None)
      render_editor(prompt, editor, updated)
      loop(prompt, updated, completions)
    }

    CtrlLeft -> {
      let new_cursor = scan_word_left(editor.buffer, editor.cursor)
      let updated = Editor(..editor, cursor: new_cursor, menu: None)
      render_editor(prompt, editor, updated)
      loop(prompt, updated, completions)
    }

    CtrlRight -> {
      let new_cursor = scan_word_right(editor.buffer, editor.cursor)
      let updated = Editor(..editor, cursor: new_cursor, menu: None)
      render_editor(prompt, editor, updated)
      loop(prompt, updated, completions)
    }

    Tab -> {
      let left_of_cursor = string.slice(editor.buffer, 0, editor.cursor)
      let word = get_current_word(left_of_cursor)

      case word == "" {
        True -> loop(prompt, editor, completions)
        False -> {
          let matches = list.filter(completions, string.starts_with(_, word))
          case matches {
            [] -> loop(prompt, editor, completions)
            [match] ->
              insert_completion(prompt, editor, word, match, completions)
            _ -> {
              let common_prefix = longest_common_prefix(matches)
              case common_prefix == word {
                False ->
                  insert_completion(
                    prompt,
                    editor,
                    word,
                    common_prefix,
                    completions,
                  )
                True -> {
                  let grid = format_grid(matches)
                  let updated = Editor(..editor, menu: Some(grid))
                  render_editor(prompt, editor, updated)
                  loop(prompt, updated, completions)
                }
              }
            }
          }
        }
      }
    }

    _ -> loop(prompt, editor, completions)
  }
}

/// Splices an autocompletion string into the buffer at the active cursor position.
fn insert_completion(
  prompt: String,
  editor: Editor,
  word: String,
  match: String,
  completions: List(String),
) -> String {
  let remainder = string.drop_start(match, string.length(word))
  let left = string.slice(editor.buffer, 0, editor.cursor)
  let right =
    string.slice(
      editor.buffer,
      editor.cursor,
      string.length(editor.buffer) - editor.cursor,
    )

  let updated =
    Editor(
      ..editor,
      buffer: left <> remainder <> right,
      cursor: editor.cursor + string.length(remainder),
      menu: None,
    )

  render_editor(prompt, editor, updated)
  loop(prompt, updated, completions)
}

/// Navigates backwards to the previous command entry in the history list.
fn history_up(editor: Editor) -> Editor {
  case editor.history {
    [] -> editor
    _ -> {
      let new_index = case editor.history_index {
        -1 -> list.length(editor.history) - 1
        index -> int.max(index - 1, 0)
      }

      let saved_buffer = case editor.history_index {
        -1 -> Some(editor.buffer)
        _ -> editor.saved_buffer
      }

      let command =
        editor.history
        |> list.drop(new_index)
        |> list.first()
        |> result.unwrap("")

      Editor(
        buffer: command,
        cursor: string.length(command),
        history: editor.history,
        history_index: new_index,
        saved_buffer: saved_buffer,
        menu: None,
      )
    }
  }
}

/// Navigates forwards in command history, restoring the unsubmitted input buffer upon reaching the latest entry.
fn history_down(editor: Editor) -> Editor {
  case editor.history_index {
    -1 -> editor
    index -> {
      let max = list.length(editor.history) - 1

      case index >= max {
        True -> {
          let restored = option.unwrap(editor.saved_buffer, "")

          Editor(
            buffer: restored,
            cursor: string.length(restored),
            history: editor.history,
            history_index: -1,
            saved_buffer: None,
            menu: None,
          )
        }
        False -> {
          let new_index = index + 1
          let command =
            editor.history
            |> list.drop(new_index)
            |> list.first()
            |> result.unwrap("")

          Editor(
            buffer: command,
            cursor: string.length(command),
            history: editor.history,
            history_index: new_index,
            saved_buffer: editor.saved_buffer,
            menu: None,
          )
        }
      }
    }
  }
}

/// Extracts the identifier substring immediately preceding the cursor position for completion matching.
fn get_current_word(text: String) -> String {
  text
  |> string.to_graphemes()
  |> list.reverse()
  |> list.take_while(is_identifier_char)
  |> list.reverse()
  |> string.join("")
}

/// Determines whether a given character grapheme is valid inside a Gleam variable, module, or function identifier.
fn is_identifier_char(c: String) -> Bool {
  string.contains(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./",
    c,
  )
}

/// Computes the longest common prefix across a list of matching completion strings.
fn longest_common_prefix(strings: List(String)) -> String {
  case strings {
    [] -> ""
    [first, ..rest] -> find_common_prefix(first, rest)
  }
}

/// Recursively truncates a candidate prefix until all target strings match.
fn find_common_prefix(current: String, strings: List(String)) -> String {
  case current {
    "" -> ""
    _ -> {
      let all_match = list.all(strings, string.starts_with(_, current))
      case all_match {
        True -> current
        False -> {
          let dropped = string.drop_end(current, 1)
          find_common_prefix(dropped, strings)
        }
      }
    }
  }
}

// --- GRID FORMATTING ---

/// Formats a list of autocomplete candidates into a multi-column terminal grid capped at 80 columns wide.
fn format_grid(items: List(String)) -> String {
  let max_len =
    list.fold(items, 0, fn(acc, item) { int.max(acc, string.length(item)) })

  let col_width = max_len + 2
  let max_cols = int.max(1, 80 / col_width)

  build_grid(items, max_cols, col_width, 0, "")
  |> string.trim_end()
  // Crucial: No trailing newline, or the jump-up math breaks!
}

/// Recursively constructs the formatted multi-column menu grid string.
fn build_grid(
  items: List(String),
  max_cols: Int,
  col_width: Int,
  current_col: Int,
  acc: String,
) -> String {
  case items {
    [] -> acc
    [item, ..rest] -> {
      let padded = string.pad_end(item, to: col_width, with: " ")
      let next_col = current_col + 1

      case next_col >= max_cols {
        True -> build_grid(rest, max_cols, col_width, 0, acc <> padded <> "\n")
        False -> build_grid(rest, max_cols, col_width, next_col, acc <> padded)
      }
    }
  }
}

/// Scans backwards from the cursor to find the starting index of the preceding word.
fn scan_word_left(buffer: String, cursor: Int) -> Int {
  case cursor <= 0 {
    True -> 0
    False -> {
      let before = string.slice(buffer, 0, cursor)
      let chars = list.reverse(string.to_graphemes(before))

      // Skip any trailing spaces first
      let without_spaces =
        list.drop_while(chars, fn(c) { c == " " || c == "\n" })
      // Count the characters of the actual word
      let word_chars =
        list.take_while(without_spaces, fn(c) { c != " " && c != "\n" })

      let spaces_skipped = list.length(chars) - list.length(without_spaces)
      let jump = case list.length(word_chars) {
        0 -> spaces_skipped
        len -> spaces_skipped + len
      }

      int.max(0, cursor - jump)
    }
  }
}

/// Scans forwards from the cursor to find the ending index of the next word boundary.
fn scan_word_right(buffer: String, cursor: Int) -> Int {
  let max_len = string.length(buffer)
  case cursor >= max_len {
    True -> max_len
    False -> {
      let after = string.slice(buffer, cursor, max_len - cursor)
      let chars = string.to_graphemes(after)

      // Skip any leading spaces first
      let without_spaces =
        list.drop_while(chars, fn(c) { c == " " || c == "\n" })
      // Count the characters of the actual word
      let word_chars =
        list.take_while(without_spaces, fn(c) { c != " " && c != "\n" })

      let spaces_skipped = list.length(chars) - list.length(without_spaces)
      let jump = case list.length(word_chars) {
        0 -> spaces_skipped
        len -> spaces_skipped + len
      }

      int.min(max_len, cursor + jump)
    }
  }
}
