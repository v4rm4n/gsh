import gleam/io
import gleam/string

pub fn main() {
  let x = 1
  io.println(string.inspect(
    x
  ))
}
