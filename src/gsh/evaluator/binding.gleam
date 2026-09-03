// src/gsh/evaluator/binding.gleam

import gleam/option.{type Option}

pub type BindingKind {
  Let
  LetAssert
}

pub type Binding {
  Binding(
    kind: BindingKind,
    source: String,
    pattern: String,
    reference: Option(String),
    value: String,
  )
}
