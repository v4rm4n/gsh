import gleam/option.{Some}
import gleeunit/should
import helpers.{eval}

pub fn eval_anon_function_binding_test() {
  let result = eval("let add = fn(a, b) { a + b }")

  result.success |> should.be_true
  let assert Some(b) = result.new_binding

  // Since it's assigned to a variable, it registers as a Binding, not a Function.
  b.names |> should.equal(["add"])
}
