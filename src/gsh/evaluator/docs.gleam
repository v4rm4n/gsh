// src/gsh/evaluator/docs.gleam

import gleam/list
import gleam/result
import gleam/string
import glexer
import glexer/token
import simplifile

/// Public entry point for `h module` (e.g., `h simplifile`)
pub fn get_module_help(module_path: String) -> String {
  case find_source(module_path) {
    Error(_) ->
      "error: Could not find source code for module '" <> module_path <> "'"
    Ok(src) -> {
      let tokens = glexer.new(src) |> glexer.lex() |> list.map(fn(t) { t.0 })

      let docs =
        list.filter_map(tokens, fn(t) {
          case t {
            token.CommentModule(d) ->
              Ok(string.replace(d, "////", "") |> string.trim())
            _ -> Error(Nil)
          }
        })

      case docs {
        [] -> "No module documentation found for '" <> module_path <> "'."
        _ -> {
          let raw_text = string.join(docs, "\n")
          format_title(module_path) <> format_markdown(raw_text) <> "\n"
        }
      }
    }
  }
}

/// Public entry point for `h module.function` (e.g., `h simplifile.append`)
pub fn get_function_help(module_path: String, func_name: String) -> String {
  case find_source(module_path) {
    Error(_) ->
      "error: Could not find source code for module '" <> module_path <> "'"
    Ok(src) -> {
      let tokens = glexer.new(src) |> glexer.lex()

      case extract_fn(tokens, func_name, []) {
        Error(_) ->
          "error: Function '" <> func_name <> "' not found in " <> module_path
        Ok(#(doc_strings, sig_tokens)) -> {
          let docs =
            list.map(doc_strings, fn(d) {
              string.replace(d, "///", "") |> string.trim()
            })
            |> string.join("\n")

          let signature = glexer.to_source(sig_tokens) |> string.trim()

          // Color the signature green, then append the formatted docs!
          "\n\u{001b}[32m"
          <> signature
          <> "\u{001b}[0m\n\n"
          <> format_markdown(docs)
          <> "\n"
        }
      }
    }
  }
}

// --- INTERNAL SEARCH & LEXING LOGIC ---

/// Hunts down the raw `.gleam` file. Checks the local `src/` folder first, 
/// then scans all dependencies inside `build/packages/`.
fn find_source(module_path: String) -> Result(String, Nil) {
  let file_name = module_path <> ".gleam"
  let local_path = "src/" <> file_name

  case simplifile.read(local_path) {
    Ok(src) -> Ok(src)
    Error(_) -> {
      // Read all dependency folders and check if they contain the target module
      case simplifile.read_directory("build/packages") {
        Ok(packages) -> {
          let paths =
            list.map(packages, fn(pkg) {
              "build/packages/" <> pkg <> "/src/" <> file_name
            })

          case list.find(paths, fn(p) { simplifile.is_file(p) == Ok(True) }) {
            Ok(found_path) ->
              simplifile.read(found_path) |> result.replace_error(Nil)
            Error(_) -> Error(Nil)
          }
        }
        Error(_) -> Error(Nil)
      }
    }
  }
}

/// Recursively scans tokens looking for `fn target_name`.
/// Maintains a rolling buffer of `///` docs leading up to the function.
fn extract_fn(
  tokens: List(#(token.Token, glexer.Position)),
  target: String,
  current_docs: List(String),
) -> Result(#(List(String), List(#(token.Token, glexer.Position))), Nil) {
  case tokens {
    [] -> Error(Nil)

    // Accumulate `///` comments
    [#(token.CommentDoc(d), _), ..rest] ->
      extract_fn(rest, target, [d, ..current_docs])

    // Ignore safe modifiers and whitespace that appear between docs and the function
    [#(token.Pub, _), ..rest]
    | [#(token.Opaque, _), ..rest]
    | [#(token.Space(_), _), ..rest]
    | [#(token.CommentNormal(_), _), ..rest] ->
      extract_fn(rest, target, current_docs)

    // Found it! `fn my_func` (with a space)
    [#(token.Fn, p1), #(token.Space(s), p2), #(token.Name(name), p3), ..rest]
      if name == target
    -> {
      let head = [
        #(token.Fn, p1),
        #(token.Space(s), p2),
        #(token.Name(name), p3),
      ]
      let signature = take_signature(rest, list.reverse(head))
      Ok(#(list.reverse(current_docs), signature))
    }

    // Reset our docs buffer if we hit unrelated code, and keep searching
    [_, ..rest] -> extract_fn(rest, target, [])
  }
}

/// Takes tokens until it hits the `{` that opens the function body.
fn take_signature(
  tokens: List(#(token.Token, glexer.Position)),
  acc: List(#(token.Token, glexer.Position)),
) -> List(#(token.Token, glexer.Position)) {
  case tokens {
    [] -> list.reverse(acc)
    [#(token.LeftBrace, _), ..] -> list.reverse(acc)
    [t, ..rest] -> take_signature(rest, [t, ..acc])
  }
}

/// Centers a title for the terminal and makes it bold/colored
fn format_title(title: String) -> String {
  let len = string.length(title)
  // Assume an 80-character standard terminal width for centering
  let padding = case len < 80 {
    True -> string.repeat(" ", { 80 - len } / 2)
    False -> ""
  }
  "\n" <> padding <> "\u{001b}[1;36m" <> title <> "\u{001b}[0m\n\n"
}

/// Parses raw Gleam comments into beautiful terminal output
fn format_markdown(text: String) -> String {
  text
  |> string.split("\n")
  |> list.map(format_line)
  |> string.join("\n")
  |> string.trim()
}

fn format_line(line: String) -> String {
  let trimmed = string.trim(line)

  case trimmed {
    // Format headers (## Title)
    "#" <> _ -> {
      let header = string.replace(trimmed, "#", "") |> string.trim()
      "\n\u{001b}[1m" <> header <> "\u{001b}[0m\n"
    }

    // Format lists (- item or * item)
    "- " <> rest | "* " <> rest -> "  • " <> format_inline(rest)

    // Default: just highlight inline code
    _ -> format_inline(line)
  }
}

/// Wraps anything inside backticks in yellow ANSI color
fn format_inline(line: String) -> String {
  // Splitting by "`" means every alternating item is inside backticks!
  let parts = string.split(line, on: "`")
  do_format_inline(parts, False, "")
}

fn do_format_inline(parts: List(String), is_code: Bool, acc: String) -> String {
  case parts {
    [] -> acc
    [part, ..rest] -> {
      let formatted = case is_code {
        True -> "\u{001b}[33m" <> part <> "\u{001b}[0m"
        // Yellow for code
        False -> part
      }
      do_format_inline(rest, !is_code, acc <> formatted)
    }
  }
}
