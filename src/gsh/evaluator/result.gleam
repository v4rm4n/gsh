// src/gsh/evaluator/result.gleam

import gleam/option.{type Option}
import gsh/evaluator/binding.{type Binding}

pub type Evaluation {
  Evaluation(
    output: String,
    success: Bool,
    error_kind: ErrorKind,
    new_binding: Option(Binding),
    new_import: Option(String),
    new_type: Option(String),
  )
}

pub type ErrorKind {
  NoError
  CompileError
  RuntimeError
}
