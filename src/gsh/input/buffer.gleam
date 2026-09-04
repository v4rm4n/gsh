// src/gsh/input/buffer.gleam

import gleam/list
import gleam/string

pub fn is_complete(input: String) -> Bool {
  let braces = count_brackets(input)

  braces.paren == 0 && braces.square == 0 && braces.curly == 0
}

type Brackets {
  Brackets(paren: Int, square: Int, curly: Int, in_string: Bool)
}

fn count_brackets(input: String) -> Brackets {
  string.to_graphemes(input)
  |> list.fold(Brackets(0, 0, 0, False), fn(acc, char) {
    case char, acc.in_string {
      // Toggle string state when we see an unescaped quote
      "\"", in_str -> Brackets(..acc, in_string: !in_str)

      // If we are inside a string, ignore all brackets!
      _, True -> acc

      "(", False -> Brackets(..acc, paren: acc.paren + 1)
      ")", False -> Brackets(..acc, paren: acc.paren - 1)
      "[", False -> Brackets(..acc, square: acc.square + 1)
      "]", False -> Brackets(..acc, square: acc.square - 1)
      "{", False -> Brackets(..acc, curly: acc.curly + 1)
      "}", False -> Brackets(..acc, curly: acc.curly - 1)
      _, _ -> acc
    }
  })
}
