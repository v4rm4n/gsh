// src/input/editor.gleam
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gsh/input/key.{ArrowDown, ArrowUp, Character, Enter}
import gsh/input/reader

pub type Editor {
  Editor(buffer: String, cursor: Int, history: List(String), history_index: Int)
}

pub fn read_line(history: List(String)) -> String {
  loop(Editor(buffer: "", cursor: 0, history: history, history_index: -1))
}

fn loop(editor: Editor) -> String {
  let key = reader.read_key()

  case key {
    Enter -> editor.buffer

    ArrowUp -> loop(history_up(editor))

    ArrowDown -> loop(history_down(editor))

    Character(value) ->
      loop(Editor(
        buffer: editor.buffer <> value,
        cursor: editor.cursor + 1,
        history: editor.history,
        history_index: editor.history_index,
      ))

    _ -> loop(editor)
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
      )
    }
  }
}

fn history_down(editor: Editor) -> Editor {
  let max = list.length(editor.history) - 1

  let new_index = int.min(editor.history_index + 1, max)

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
  )
}
