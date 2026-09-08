import gleam/option.{None}
import gleeunit/should
import helpers.{eval}

pub fn eval_int_test() {
  let result = eval("42")

  result.success |> should.be_true
  result.new_binding |> should.equal(None)
  result.new_function |> should.equal(None)
}

pub fn eval_float_test() {
  let result = eval("3.14")
  result.success |> should.be_true
  result.new_binding |> should.equal(None)
}
