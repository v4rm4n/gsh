// src/gsh/evaluator/parser.gleam

import glance
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// 1. The data structures our shell will use instead of raw tokens
pub type DefKind {
  FnDef
  TypeDef
  ConstDef
}

pub type Item {
  ImportItem(module: String, source: String)
  DefinitionItem(name: String, kind: DefKind, source: String)
  ValueItem(names: List(String), rhs: String, is_assert: Bool)
}

pub type ClassifyResult {
  Items(List(Item))
  ClassifyEmpty
  ClassifyIncomplete
  ClassifyError(String)
}

pub type Unqualified {
  Unqualified(name: String, alias: Option(String))
}

pub type ImportSpec {
  ImportSpec(
    module: String,
    alias: Option(String),
    types: List(Unqualified),
    values: List(Unqualified),
  )
}

// 2. The main entry point for the new parser
pub fn parse(src: String) -> ClassifyResult {
  let trimmed = string.trim(src)
  case trimmed {
    "" -> ClassifyEmpty
    _ -> {
      // glance.module() builds a true Abstract Syntax Tree.
      // It natively understands comments, whitespace, and attributes!
      case glance.module(src) {
        Ok(module) -> from_module(src, module)
        Error(glance.UnexpectedEndOfInput) -> ClassifyIncomplete
        Error(glance.UnexpectedToken(_, _)) -> parse_wrapped_expression(src)
      }
    }
  }
}

// 3. Extracting top-level definitions (Functions, Types, Imports)
fn from_module(src: String, module: glance.Module) -> ClassifyResult {
  // ADD THIS BLOCK:
  let imports =
    list.map(module.imports, fn(def) {
      ImportItem(module: def.definition.module, source: src)
    })

  let functions =
    list.map(module.functions, fn(def) {
      DefinitionItem(name: def.definition.name, kind: FnDef, source: src)
    })

  let types =
    list.map(module.custom_types, fn(def) {
      DefinitionItem(name: def.definition.name, kind: TypeDef, source: src)
    })

  // ADD `imports` to the flatten list:
  let items = list.flatten([imports, functions, types])
  case items {
    [] -> parse_wrapped_expression(src)
    _ -> Items(items)
  }
}

// 4. Fallback for raw expressions and let-bindings (which aren't valid top-level Gleam)
fn parse_wrapped_expression(src: String) -> ClassifyResult {
  let wrapped = "pub fn temp() {\n" <> src <> "\n}\n"

  case glance.module(wrapped) {
    Ok(module) ->
      case module.functions {
        [def] -> extract_statements(def.definition.body)
        _ -> ClassifyError("Could not classify snippet")
      }
    Error(glance.UnexpectedEndOfInput) -> ClassifyIncomplete
    Error(glance.UnexpectedToken(token:, ..)) ->
      ClassifyError("Syntax error near " <> string.inspect(token))
  }
}

// 5. Extracting variable names from Let bindings
fn extract_statements(statements: List(glance.Statement)) -> ClassifyResult {
  case statements {
    [] -> ClassifyEmpty
    _ -> {
      let items =
        list.map(statements, fn(statement) {
          case statement {
            glance.Assignment(kind:, pattern:, ..) -> {
              let is_assert = case kind {
                glance.Let -> False
                glance.LetAssert(_) -> True
              }
              ValueItem(
                names: pattern_names(pattern),
                rhs: "",
                // We will extract the raw string slice later
                is_assert: is_assert,
              )
            }
            glance.Expression(_) ->
              ValueItem(names: [], rhs: "", is_assert: False)
            _ -> ValueItem(names: [], rhs: "", is_assert: False)
          }
        })
      Items(items)
    }
  }
}

pub fn pattern_names(pattern: glance.Pattern) -> List(String) {
  pattern_names_acc(pattern, [])
}

fn pattern_names_acc(
  pattern: glance.Pattern,
  acc: List(String),
) -> List(String) {
  case pattern {
    glance.PatternVariable(_, name) -> push_unique(acc, name)
    glance.PatternAssignment(_, inner, name) ->
      pattern_names_acc(inner, push_unique(acc, name))
    glance.PatternTuple(_, elements) ->
      list.fold(elements, acc, fn(acc, p) { pattern_names_acc(p, acc) })
    glance.PatternList(_, elements, tail) -> {
      let acc =
        list.fold(elements, acc, fn(acc, p) { pattern_names_acc(p, acc) })
      case tail {
        Some(tail) -> pattern_names_acc(tail, acc)
        None -> acc
      }
    }
    glance.PatternVariant(_, _, _, arguments, _) ->
      list.fold(arguments, acc, fn(acc, field) {
        case field {
          glance.LabelledField(_, _, item) -> pattern_names_acc(item, acc)
          glance.UnlabelledField(item) -> pattern_names_acc(item, acc)
          glance.ShorthandField(label:, location: _) -> push_unique(acc, label)
        }
      })
    glance.PatternConcatenate(_, _, prefix_name, rest_name) -> {
      let acc = case prefix_name {
        Some(glance.Named(name)) -> push_unique(acc, name)
        Some(glance.Discarded(_)) | None -> acc
      }
      case rest_name {
        glance.Named(name) -> push_unique(acc, name)
        glance.Discarded(_) -> acc
      }
    }
    glance.PatternBitString(_, segments) ->
      list.fold(segments, acc, fn(acc, segment) {
        pattern_names_acc(segment.0, acc)
      })
    glance.PatternInt(_, _)
    | glance.PatternFloat(_, _)
    | glance.PatternString(_, _)
    | glance.PatternDiscard(_, _) -> acc
  }
}

fn push_unique(acc: List(String), name: String) -> List(String) {
  case list.contains(acc, name) {
    True -> acc
    False -> list.append(acc, [name])
  }
}

pub fn merge_imports(imports: List(String)) -> List(String) {
  let src = string.join(imports, "\n")
  case glance.module(src) {
    Ok(module) -> {
      let specs = list.map(module.imports, extract_import_spec)
      let merged = list.fold(specs, [], merge_import_spec)
      list.map(merged, render_import)
    }
    Error(_) -> imports
    // Fallback just in case
  }
}

fn extract_import_spec(def: glance.Definition(glance.Import)) -> ImportSpec {
  let import_ = def.definition
  ImportSpec(
    module: import_.module,
    alias: assignment_alias(import_.alias),
    types: list.map(import_.unqualified_types, unqualified),
    values: list.map(import_.unqualified_values, unqualified),
  )
}

fn assignment_alias(alias: Option(glance.AssignmentName)) -> Option(String) {
  case alias {
    Some(glance.Named(name)) -> Some(name)
    Some(glance.Discarded(_)) | None -> None
  }
}

fn unqualified(item: glance.UnqualifiedImport) -> Unqualified {
  Unqualified(name: item.name, alias: item.alias)
}

fn merge_import_spec(
  acc: List(ImportSpec),
  spec: ImportSpec,
) -> List(ImportSpec) {
  let #(same, rest) =
    list.partition(acc, fn(existing) {
      existing.module == spec.module && existing.alias == spec.alias
    })
  case same {
    [] -> list.append(acc, [spec])
    [first, ..] -> {
      let merged =
        ImportSpec(
          module: spec.module,
          alias: spec.alias,
          types: merge_unqualified(first.types, spec.types),
          values: merge_unqualified(first.values, spec.values),
        )
      list.append(rest, [merged])
    }
  }
}

fn merge_unqualified(
  left: List(Unqualified),
  right: List(Unqualified),
) -> List(Unqualified) {
  list.fold(right, left, fn(acc, item) {
    case list.find(acc, fn(existing) { existing.name == item.name }) {
      Ok(_) -> acc
      Error(_) -> list.append(acc, [item])
    }
  })
}

fn render_import(spec: ImportSpec) -> String {
  let base = "import " <> spec.module
  let base = case spec.alias {
    Some(alias) -> base <> " as " <> alias
    None -> base
  }
  let types = list.map(spec.types, render_unqualified_type)
  let values = list.map(spec.values, render_unqualified)
  let unqualified_list = list.append(types, values)

  case unqualified_list {
    [] -> base
    _ -> base <> ".{" <> string.join(unqualified_list, ", ") <> "}"
  }
}

fn render_unqualified(item: Unqualified) -> String {
  case item.alias {
    Some(alias) -> item.name <> " as " <> alias
    None -> item.name
  }
}

fn render_unqualified_type(item: Unqualified) -> String {
  "type " <> render_unqualified(item)
}

pub fn get_imported_names(src: String) -> List(String) {
  case glance.module(src) {
    Ok(module) -> {
      list.flat_map(module.imports, fn(def) {
        let spec = extract_import_spec(def)

        // Get the module alias (e.g., 'list' or a custom 'l')
        let alias = case spec.alias {
          Some(a) -> a
          None ->
            case list.last(string.split(spec.module, "/")) {
              Ok(last) -> last
              Error(_) -> spec.module
            }
        }

        // Get the specific extracted values (e.g., 'map', 'filter')
        let values =
          list.map(spec.values, fn(v) {
            case v.alias {
              Some(a) -> a
              None -> v.name
            }
          })

        list.append([alias], values)
      })
    }
    Error(_) -> []
  }
}
