// src/gsh/input/buffer.gleam

import gleam/list
import gleam/string

pub fn is_complete(input: String) -> Bool {
  let braces = count_brackets(input)

  braces.paren == 0 && braces.square == 0 && braces.curly == 0
}

type Brackets {
  Brackets(paren: Int, square: Int, curly: Int)
}

fn count_brackets(input: String) -> Brackets {
  string.to_graphemes(input)
  |> list.fold(Brackets(0, 0, 0), fn(acc, char) {
    case char {
      "(" -> Brackets(acc.paren + 1, acc.square, acc.curly)

      ")" -> Brackets(acc.paren - 1, acc.square, acc.curly)

      "[" -> Brackets(acc.paren, acc.square + 1, acc.curly)

      "]" -> Brackets(acc.paren, acc.square - 1, acc.curly)

      "{" -> Brackets(acc.paren, acc.square, acc.curly + 1)

      "}" -> Brackets(acc.paren, acc.square, acc.curly - 1)

      _ -> acc
    }
  })
}
