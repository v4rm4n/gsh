import gleam/option.{Some}
import gleeunit/should
import helpers.{eval}

pub fn eval_tuple_destructuring_test() {
  let result = eval("let #(x, y) = #(10, 20)")

  result.success |> should.be_true
  let assert Some(b) = result.new_binding

  // Your current scanner successfully finds these because it recursively
  // hunts for Name() tokens before the `=` sign.
  b.names |> should.equal(["x", "y"])
}
