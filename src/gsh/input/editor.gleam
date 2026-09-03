// src/input/editor.gleam
import gleam/io
import gsh/input/buffer
import gsh/input/reader

pub type Editor {
  Editor(buffer: String, cursor: Int, history: List(String), history_index: Int)
}

pub fn read_command(prompt: String, history: List(String)) -> String {
  io.print(prompt)

  loop(Editor(buffer: "", cursor: 0, history: history, history_index: -1))
}

fn loop(editor: Editor) -> String {
  let key = reader.read_char()

  case key {
    "\r" -> {
      case buffer.is_complete(editor.buffer) {
        True -> editor.buffer

        False -> {
          io.print("...> ")

          loop(Editor(
            buffer: editor.buffer <> "\n",
            cursor: editor.cursor,
            history: editor.history,
            history_index: editor.history_index,
          ))
        }
      }
    }

    "\n" -> loop(editor)

    _ ->
      loop(Editor(
        buffer: editor.buffer <> key,
        cursor: editor.cursor + 1,
        history: editor.history,
        history_index: editor.history_index,
      ))
  }
}
