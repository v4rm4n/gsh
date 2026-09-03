// src/gsh/input/editor.gleam
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gsh/input/display
import gsh/input/key.{
  ArrowDown, ArrowLeft, ArrowRight, ArrowUp, Backspace, Character, Enter,
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
  )
}

pub fn read_line(prompt: String, history: List(String)) -> String {
  loop(
    prompt,
    Editor(
      buffer: "",
      cursor: 0,
      history: history,
      history_index: -1,
      saved_buffer: None,
    ),
  )
}

fn loop(prompt: String, editor: Editor) -> String {
  let key = reader.read_key()

  case key {
    Enter -> {
      terminal.println("")
      editor.buffer
    }

    ArrowUp -> {
      let updated = history_up(editor)
      display.render(prompt, updated.buffer)
      loop(prompt, updated)
    }

    ArrowDown -> {
      let updated = history_down(editor)
      display.render(prompt, updated.buffer)
      loop(prompt, updated)
    }

    ArrowLeft -> {
      let new_cursor = int.max(0, editor.cursor - 1)
      let updated = Editor(..editor, cursor: new_cursor)

      display.render(prompt, updated.buffer)
      sync_cursor(updated)

      loop(prompt, updated)
    }

    ArrowRight -> {
      let max_cursor = string.length(editor.buffer)
      let new_cursor = int.min(max_cursor, editor.cursor + 1)
      let updated = Editor(..editor, cursor: new_cursor)

      display.render(prompt, updated.buffer)
      sync_cursor(updated)

      loop(prompt, updated)
    }

    Character(value) -> {
      // Inject the new character at the current cursor position
      let left = string.slice(editor.buffer, 0, editor.cursor)
      let right =
        string.slice(
          editor.buffer,
          editor.cursor,
          string.length(editor.buffer) - editor.cursor,
        )

      let new_buffer = left <> value <> right

      let updated =
        Editor(
          ..editor,
          buffer: new_buffer,
          cursor: editor.cursor + string.length(value),
        )

      display.render(prompt, updated.buffer)
      sync_cursor(updated)

      loop(prompt, updated)
    }

    Backspace -> {
      case editor.cursor > 0 {
        False -> loop(prompt, editor)
        // At the start, do nothing
        True -> {
          let left = string.slice(editor.buffer, 0, editor.cursor - 1)
          let right =
            string.slice(
              editor.buffer,
              editor.cursor,
              string.length(editor.buffer) - editor.cursor,
            )

          let updated =
            Editor(..editor, buffer: left <> right, cursor: editor.cursor - 1)

          display.render(prompt, updated.buffer)
          sync_cursor(updated)
          loop(prompt, updated)
        }
      }
    }

    _ -> loop(prompt, editor)
  }
}

fn history_up(editor: Editor) -> Editor {
  case editor.history {
    [] -> editor

    _ -> {
      let new_index = case editor.history_index {
        -1 -> list.length(editor.history) - 1

        index -> int.max(index - 1, 0)
      }

      // Stash the in-progress line the first time we leave it.
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
      )
    }
  }
}

fn history_down(editor: Editor) -> Editor {
  case editor.history_index {
    -1 -> editor

    // not browsing, nothing to do
    index -> {
      let max = list.length(editor.history) - 1

      case index >= max {
        True -> {
          // Walked past the newest entry: restore what was being typed.
          let restored = option.unwrap(editor.saved_buffer, "")

          Editor(
            buffer: restored,
            cursor: string.length(restored),
            history: editor.history,
            history_index: -1,
            saved_buffer: None,
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
          )
        }
      }
    }
  }
}

fn sync_cursor(editor: Editor) -> Nil {
  let distance_from_end = string.length(editor.buffer) - editor.cursor

  case distance_from_end > 0 {
    True -> terminal.cursor_left(distance_from_end)
    False -> Nil
  }
}
