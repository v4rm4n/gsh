// src/gsh/input/editor.gleam
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gsh/input/display
import gsh/input/key.{ArrowDown, ArrowUp, Backspace, Character, Enter}
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

    Character(value) -> {
      let updated =
        Editor(
          buffer: editor.buffer <> value,
          cursor: editor.cursor + 1,
          history: editor.history,
          history_index: editor.history_index,
          saved_buffer: editor.saved_buffer,
        )

      display.render(prompt, updated.buffer)
      loop(prompt, updated)
    }

    Backspace -> {
      let updated = case editor.buffer {
        "" -> editor

        _ -> {
          let new_buffer =
            editor.buffer
            |> string.to_graphemes()
            |> list.reverse()
            |> list.drop(1)
            |> list.reverse()
            |> string.join("")

          Editor(
            buffer: new_buffer,
            cursor: string.length(new_buffer),
            history: editor.history,
            history_index: editor.history_index,
            saved_buffer: editor.saved_buffer,
          )
        }
      }

      display.render(prompt, updated.buffer)
      loop(prompt, updated)
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
