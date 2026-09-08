// src/gsh/internal/evaluator/style.gleam

const reset = "\u{001b}[0m"

const red = "\u{001b}[31m"

const yellow = "\u{001b}[33m"

const dim = "\u{001b}[90m"

// Bright black / dim grey

pub fn error(text: String) -> String {
  red <> text <> reset
}

pub fn warning(text: String) -> String {
  yellow <> text <> reset
}

// We will use this in Step 2 for the OCaml-style `: Int`

pub fn type_note(text: String) -> String {
  dim <> text <> reset
}
