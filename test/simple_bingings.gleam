import gleam/option.{Some}
import gleeunit/should
import gsh/evaluator/binding.{Let, LetAssert}
import helpers.{eval}

pub fn eval_simple_let_test() {
  let result = eval("let name = \"Alice\"")
  result.success |> should.be_true
  let assert Some(b) = result.new_binding
  b.kind |> should.equal(Let)
  b.names |> should.equal(["name"])
}

pub fn eval_let_assert_test() {
  let result = eval("let assert Ok(val) = Ok(10)")

  result.success |> should.be_true
  let assert Some(b) = result.new_binding

  b.kind |> should.equal(LetAssert)

  // Current glexer code stops at `=` and grabs all lowercase words,
  // so it correctly extracts "val" and ignores the UpperName "Ok".
  b.names |> should.equal(["val"])
}
