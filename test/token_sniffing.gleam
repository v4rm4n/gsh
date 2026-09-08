import gleam/option.{Some}
import gleeunit/should
import helpers.{eval}

pub fn eval_function_with_comments_test() {
  // If a user drops a comment above a function, your current token router 
  // [token.Pub, token.Fn, ...] will fail to match because it expects Pub first.
  let source =
    "
    // A helpful comment
    pub fn hello() { \"world\" }
  "
  let result = eval(source)

  // This will currently fail! Your code will route it as a generic expression,
  // throwing a compiler error instead of extracting the new_function.
  let assert Some(#(name, _)) = result.new_function
  name |> should.equal("hello")
}

pub fn eval_function_with_attributes_test() {
  let source =
    "
    @external(erlang, \"math\", \"pi\")
    pub fn pi() -> Float
  "
  let result = eval(source)

  // This will also fail in the old code. The `@external` attribute throws 
  // off the manual token matching array.
  let assert Some(#(name, _)) = result.new_function
  name |> should.equal("pi")
}
