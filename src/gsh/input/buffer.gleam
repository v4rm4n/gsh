//// The `buffer` module handles multiline input detection for the REPL.
////
//// When a user types a command that spans multiple lines (like a `case` statement,
//// a long list, or a function definition), this module analyzes the syntax tree's 
//// surface level to determine if the user is finished typing or if the shell 
//// should prompt for a continuation line (`...>`).

// src/gsh/input/buffer.gleam

import gleam/list
import glexer
import glexer/token

/// Evaluates a string of Gleam source code to determine if it is structurally complete.
/// It uses the lexer to verify that no strings are left open, and all opened 
/// parentheses `()`, square brackets `[]`, and curly braces `{}` have been properly closed.
pub fn is_complete(input: String) -> Bool {
  let tokens =
    glexer.new(input)
    |> glexer.lex()
    |> list.map(fn(t) { t.0 })

  // 1. If the lexer found an open string, we immediately know it's incomplete
  let has_open_string =
    list.any(tokens, fn(t) {
      case t {
        token.UnterminatedString(_) -> True
        _ -> False
      }
    })

  case has_open_string {
    True -> False
    False -> {
      // 2. Count the brackets using pure syntax tokens. 
      // Because we are using tokens, brackets inside strings or comments are naturally ignored!
      let #(paren, square, curly) =
        list.fold(tokens, #(0, 0, 0), fn(acc, t) {
          case t {
            token.LeftParen -> #(acc.0 + 1, acc.1, acc.2)
            token.RightParen -> #(acc.0 - 1, acc.1, acc.2)
            token.LeftSquare -> #(acc.0, acc.1 + 1, acc.2)
            token.RightSquare -> #(acc.0, acc.1 - 1, acc.2)
            token.LeftBrace -> #(acc.0, acc.1, acc.2 + 1)
            token.RightBrace -> #(acc.0, acc.1, acc.2 - 1)
            _ -> acc
          }
        })

      // If all bracket counts are 0 (or less), the statement is complete
      paren <= 0 && square <= 0 && curly <= 0
    }
  }
}
