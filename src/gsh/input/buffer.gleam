//// The `buffer` module handles multiline input detection for the REPL.
////
//// When a user types a command that spans multiple lines (like a `case` statement,
//// a long list, or a function definition), this module analyzes the syntax tree's 
//// surface level to determine if the user is finished typing or if the shell 
//// should prompt for a continuation line (`...>`).

// src/gsh/input/buffer.gleam

import gleam/list
import gleam/string

/// Evaluates a string of Gleam source code to determine if it is structurally complete.
/// It does this by verifying that all opened parentheses `()`, square brackets `[]`, 
/// and curly braces `{}` have been properly closed.
pub fn is_complete(input: String) -> Bool {
  let braces = count_brackets(input)

  braces.paren == 0 && braces.square == 0 && braces.curly == 0
}

/// Internal state tracker used while iterating through the input's graphemes.
/// It keeps track of the current nesting depth of various bracket types, 
/// as well as a boolean flag to track whether the parser is currently inside a string.
type Brackets {
  Brackets(paren: Int, square: Int, curly: Int, in_string: Bool)
}

/// Performs a single-pass fold over the input string's graphemes to count brackets.
/// Crucially, it tracks string literal boundaries (`"`) so that brackets typed 
/// inside a string (e.g., `let a = "(hello["`) do not interfere with the overall 
/// structural completion check.
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
