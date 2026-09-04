// src/gsh/input/editor.gleam
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gsh/input/display
import gsh/input/key.{
  ArrowDown, ArrowLeft, ArrowRight, ArrowUp, Backspace, Character, CtrlL, Enter,
  Tab,
}
import gsh/input/reader
import gsh/input/terminal

pub type Editor {
  Editor(
    buffer: String,
    cursor: Int,
    history: List(String),
    history_index: Int,
    saved_buffer: Option(String),
    menu: Option(String),
    // <-- Track the floating grid
  )
}

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
  terminal.clear_below()

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

fn loop(prompt: String, editor: Editor, completions: List(String)) -> String {
  let key = reader.read_key()

  case key {
    Enter -> {
      // Jump to the very bottom of the multiline block before printing a new line!
      let total_lines = list.length(string.split(editor.buffer, "\n")) - 1
      let before_cursor = string.slice(editor.buffer, 0, editor.cursor)
      let cursor_y = list.length(string.split(before_cursor, "\n")) - 1
      let lines_to_go_down = total_lines - cursor_y

      case lines_to_go_down > 0 {
        True -> terminal.cursor_down(lines_to_go_down)
        False -> Nil
      }

      terminal.clear_below()
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
      let updated = Editor(..history_up(editor), menu: None)
      render_editor(prompt, editor, updated)
      loop(prompt, updated, completions)
    }

    ArrowDown -> {
      let updated = Editor(..history_down(editor), menu: None)
      render_editor(prompt, editor, updated)
      loop(prompt, updated, completions)
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

fn get_current_word(text: String) -> String {
  text
  |> string.to_graphemes()
  |> list.reverse()
  |> list.take_while(is_identifier_char)
  |> list.reverse()
  |> string.join("")
}

fn is_identifier_char(c: String) -> Bool {
  string.contains(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.",
    c,
  )
}

fn longest_common_prefix(strings: List(String)) -> String {
  case strings {
    [] -> ""
    [first, ..rest] -> find_common_prefix(first, rest)
  }
}

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

fn format_grid(items: List(String)) -> String {
  let max_len =
    list.fold(items, 0, fn(acc, item) { int.max(acc, string.length(item)) })

  let col_width = max_len + 2
  let max_cols = int.max(1, 80 / col_width)

  build_grid(items, max_cols, col_width, 0, "")
  |> string.trim_end()
  // Crucial: No trailing newline, or the jump-up math breaks!
}

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
