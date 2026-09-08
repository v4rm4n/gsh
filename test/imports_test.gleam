import gleam/option.{Some}
import gleeunit/should
import helpers

pub fn eval_duplicate_unqualified_imports_test() {
  // 1. Simulate a state where the user already imported `map`
  let existing_imports = ["import gleam/list.{map}"]

  // 2. The user now tries to import `filter`
  let new_input = "import gleam/list.{filter}"

  // 3. We pass BOTH into your evaluator
  let result =
    helpers.evaluator_with_state(
      new_input,
      [],
      existing_imports,
      // <-- Pass the existing imports here
      [],
      [],
      False,
      1,
    )

  // Right now, this will FAIL because the Gleam compiler will crash
  // when it sees both imports in the same file!
  result.success |> should.be_true

  // The evaluator should return the newly merged string
  let assert Some(merged) = result.new_import
  merged |> should.equal("import gleam/list.{filter}")
}
