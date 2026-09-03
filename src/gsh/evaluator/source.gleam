pub fn header(with_string: Bool) -> String {
  "import gleam/io\n"
  <> case with_string {
    True -> "import gleam/string\n"
    False -> ""
  }
  <> "\n"
}
