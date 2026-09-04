// src/gsh/input/key.gleam

pub type Key {
  Character(String)
  Enter
  Backspace
  Tab
  ArrowUp
  ArrowDown
  ArrowLeft
  ArrowRight
  Unknown
}
