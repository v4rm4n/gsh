import gsh/evaluator/binding.{type Binding}
import gsh/evaluator/evaluator
import gsh/evaluator/result

// Helper to keep tests clean. Passes empty state to your existing evaluator.
pub fn eval(input: String) -> result.Evaluation {
  evaluator.evaluate(input, [], [], [], [], False, 1)
}

// Helper to inject specific historical state for complex tests.
pub fn evaluator_with_state(
  input: String,
  bindings: List(Binding),
  imports: List(String),
  types: List(String),
  functions: List(String),
  debug: Bool,
  prompt_count: Int,
) -> result.Evaluation {
  evaluator.evaluate(
    input,
    bindings,
    imports,
    types,
    functions,
    debug,
    prompt_count,
  )
}
