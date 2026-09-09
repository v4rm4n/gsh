// The `buffer` module handles multiline input detection for the REPL.
//
// When a user enters code spanning multiple lines (like a `case` block, 
// anonymous function, or complex data structure), this module analyzes the 
// surface AST to determine if the statement is complete or requires additional 
// input via the continuation prompt (`...>`).

// src/gsh/internal/input/buffer.gleam

import gleam/list
import glexer
import glexer/token

/// Analyzes a string of Gleam source code to determine if it is structurally complete.
/// 
/// **Verification Strategy:**
/// * **String Termination:** Lexes the string to check for `UnterminatedString` 
///   tokens. If an unclosed string is found, evaluation is deferred.
/// * **Delimiter Balancing:** Tracks opening and closing delimiters—parentheses `()`, 
///   brackets `[]`, and braces `{}`—using token streams. Because matching relies on 
///   lexer output rather than raw characters, delimiters enclosed within strings or 
///   comments are safely ignored.
/// * **Completion Criteria:** Returns `True` only when all delimiter depth counts 
///   reach zero or less, signaling that the statement is ready for evaluation.
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
