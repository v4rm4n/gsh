// src/gsh/evaluator/types.gleam

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type TypeNode {
  Named(
    name: String,
    package: String,
    module: String,
    parameters: List(TypeNode),
  )
  Tuple(elements: List(TypeNode))
  Variable(id: Int)
  Fn(params: List(TypeNode), ret: TypeNode)
}

pub fn type_node_decoder() -> decode.Decoder(TypeNode) {
  use kind <- decode.field("kind", decode.string)

  case kind {
    "named" -> {
      use name <- decode.field("name", decode.string)
      use package <- decode.optional_field("package", "", decode.string)
      use module <- decode.optional_field("module", "", decode.string)
      use parameters <- decode.field(
        "parameters",
        decode.list(type_node_decoder()),
      )
      decode.success(Named(name:, package:, module:, parameters:))
    }
    "tuple" -> {
      use elements <- decode.field("elements", decode.list(type_node_decoder()))
      decode.success(Tuple(elements:))
    }
    "variable" -> {
      use id <- decode.field("id", decode.int)
      decode.success(Variable(id:))
    }
    "fn" -> {
      use params <- decode.field("parameters", decode.list(type_node_decoder()))
      use ret <- decode.field("return", type_node_decoder())
      decode.success(Fn(params:, ret:))
    }
    _ -> decode.success(Variable(-1))
  }
}

pub fn render(node: TypeNode) -> String {
  case node {
    Named(name, _package, _module, []) -> name
    Named(name, _package, _module, params) -> {
      let rendered_params = list.map(params, render) |> string.join(", ")
      name <> "(" <> rendered_params <> ")"
    }
    Tuple(elements) -> {
      let rendered = list.map(elements, render) |> string.join(", ")
      "#(" <> rendered <> ")"
    }
    Variable(id) -> "a_" <> int.to_string(id)
    Fn(params, ret) -> {
      let rendered_params = list.map(params, render) |> string.join(", ")
      "fn(" <> rendered_params <> ") -> " <> render(ret)
    }
  }
}

pub fn get_entry_type(
  json_string: String,
  module_name: String,
) -> Result(String, String) {
  let decoder =
    decode.at(
      ["modules", module_name, "functions", "gsh_entry", "return"],
      type_node_decoder(),
    )

  case json.parse(json_string, decoder) {
    Ok(node) -> Ok(render(node))
    Error(err) -> Error(string.inspect(err))
  }
}

// =============================================================================
// PACKAGE INTERFACE DECODER FOR FALLBACK TYPE LOOKUPS
// =============================================================================

pub type PackageInterface {
  PackageInterface(name: String, modules: Dict(String, ModuleData))
}

pub type ModuleData {
  ModuleData(
    types: Dict(String, TypeData),
    functions: Dict(String, FunctionData),
  )
}

pub type TypeData {
  TypeData(constructors: List(ConstructorData))
}

pub type ConstructorData {
  ConstructorData(name: String)
}

pub type FunctionData {
  FunctionData(return_type: TypeNode)
}

fn constructor_decoder() -> decode.Decoder(ConstructorData) {
  use name <- decode.field("name", decode.string)
  decode.success(ConstructorData(name: name))
}

fn type_data_decoder() -> decode.Decoder(TypeData) {
  use constructors <- decode.optional_field(
    "constructors",
    [],
    decode.list(constructor_decoder()),
  )
  decode.success(TypeData(constructors: constructors))
}

fn function_data_decoder() -> decode.Decoder(FunctionData) {
  use return_type <- decode.field("return", type_node_decoder())
  decode.success(FunctionData(return_type: return_type))
}

fn module_data_decoder() -> decode.Decoder(ModuleData) {
  use types <- decode.optional_field(
    "types",
    dict.new(),
    decode.dict(decode.string, type_data_decoder()),
  )
  use functions <- decode.optional_field(
    "functions",
    dict.new(),
    decode.dict(decode.string, function_data_decoder()),
  )
  decode.success(ModuleData(types: types, functions: functions))
}

pub fn package_interface_decoder() -> decode.Decoder(PackageInterface) {
  use name <- decode.field("name", decode.string)
  use modules <- decode.optional_field(
    "modules",
    dict.new(),
    decode.dict(decode.string, module_data_decoder()),
  )
  decode.success(PackageInterface(name: name, modules: modules))
}

// =============================================================================
// INFERENCE & LOOKUP PIPELINE
// =============================================================================

pub fn infer_or_get_type(
  json_string: String,
  module_name: String,
  source_input: String,
) -> Result(String, Nil) {
  case get_entry_type(json_string, module_name) {
    Ok(t) -> Ok(t)
    Error(_) -> infer_type_from_input(source_input, json_string)
  }
}

fn infer_type_from_input(
  input: String,
  json_string: String,
) -> Result(String, Nil) {
  let trimmed = string.trim(input)

  let expr = case string.split_once(trimmed, " = ") {
    Ok(#(_lhs, rhs)) -> string.trim(rhs)
    Error(_) -> trimmed
  }

  case int.parse(expr) {
    Ok(_) -> Ok("Int")
    Error(_) ->
      case float.parse(expr) {
        Ok(_) -> Ok("Float")
        Error(_) ->
          case expr {
            "True" | "False" -> Ok("Bool")
            _ -> infer_complex_expression(expr, json_string)
          }
      }
  }
}

fn infer_complex_expression(
  expr: String,
  json_string: String,
) -> Result(String, Nil) {
  // Strip syntax arrows so `-` doesn't match `->` or `<-`
  let clean_expr =
    expr
    |> string.replace("->", " ")
    |> string.replace("<-", " ")

  // Extract the last non-empty line (the return value of block/case statements)
  let last_line =
    clean_expr
    |> string.split("\n")
    |> list.map(string.trim)
    |> list.filter(fn(l) { l != "" && l != "}" })
    |> list.last
    |> result.unwrap(clean_expr)

  case
    string.starts_with(last_line, "\"") || string.ends_with(last_line, "\"")
  {
    True -> Ok("String")
    False ->
      case last_line == "True" || last_line == "False" {
        True -> Ok("Bool")
        False ->
          case int.parse(last_line) {
            Ok(_) -> Ok("Int")
            Error(_) ->
              case float.parse(last_line) {
                Ok(_) -> Ok("Float")
                Error(_) ->
                  case
                    string.contains(clean_expr, "+.")
                    || string.contains(clean_expr, "-.")
                    || string.contains(clean_expr, "*.")
                    || string.contains(clean_expr, "/.")
                  {
                    True -> Ok("Float")
                    False ->
                      case
                        string.contains(clean_expr, "+")
                        || string.contains(clean_expr, "-")
                        || string.contains(clean_expr, "*")
                        || string.contains(clean_expr, "/")
                        || string.contains(clean_expr, "%")
                      {
                        True -> Ok("Int")
                        False ->
                          case string.contains(clean_expr, "<>") {
                            True -> Ok("String")
                            False ->
                              case
                                string.contains(clean_expr, "==")
                                || string.contains(clean_expr, "!=")
                                || string.contains(clean_expr, "&&")
                                || string.contains(clean_expr, "||")
                              {
                                True -> Ok("Bool")
                                False ->
                                  lookup_in_package_interface(
                                    last_line,
                                    json_string,
                                  )
                              }
                          }
                      }
                  }
              }
          }
      }
  }
}

fn lookup_in_package_interface(
  expr: String,
  json_string: String,
) -> Result(String, Nil) {
  case json.parse(json_string, package_interface_decoder()) {
    Error(_) -> Error(Nil)
    Ok(pi) -> {
      let call_target = case string.split_once(expr, "(") {
        Ok(#(head, _)) -> string.trim(head)
        Error(_) -> expr
      }

      // 1. Check custom constructors (e.g. "S", "Fall", "Summer", "Ok")
      case lookup_constructor(pi, call_target) {
        Ok(t) -> Ok(t)
        Error(_) -> {
          // 2. Check function return types (e.g. "a", "config.load", "client.check_ip")
          lookup_function_return(pi, call_target)
        }
      }
    }
  }
}

fn lookup_constructor(
  pi: PackageInterface,
  cname: String,
) -> Result(String, Nil) {
  let modules = dict.to_list(pi.modules)
  find_constructor_in_modules(modules, cname)
}

fn find_constructor_in_modules(
  modules: List(#(String, ModuleData)),
  cname: String,
) -> Result(String, Nil) {
  case modules {
    [] -> Error(Nil)
    [#(_mod_name, mod_data), ..rest] -> {
      let types = dict.to_list(mod_data.types)
      case find_constructor_in_types(types, cname) {
        Ok(tname) -> Ok(tname)
        Error(_) -> find_constructor_in_modules(rest, cname)
      }
    }
  }
}

fn find_constructor_in_types(
  types: List(#(String, TypeData)),
  cname: String,
) -> Result(String, Nil) {
  case types {
    [] -> Error(Nil)
    [#(type_name, type_data), ..rest] -> {
      let has_constructor =
        list.any(type_data.constructors, fn(c) { c.name == cname })
      case has_constructor {
        True -> Ok(type_name)
        False -> find_constructor_in_types(rest, cname)
      }
    }
  }
}

fn lookup_function_return(
  pi: PackageInterface,
  call_target: String,
) -> Result(String, Nil) {
  let parts = string.split(call_target, ".")
  case parts {
    [fn_name] -> {
      let modules = dict.to_list(pi.modules)
      find_function_in_modules(modules, fn_name)
    }
    [mod_alias, fn_name] -> {
      let modules = dict.to_list(pi.modules)
      find_qualified_function_in_modules(modules, mod_alias, fn_name)
    }
    _ -> Error(Nil)
  }
}

fn find_function_in_modules(
  modules: List(#(String, ModuleData)),
  fn_name: String,
) -> Result(String, Nil) {
  case modules {
    [] -> Error(Nil)
    [#(_mod_name, mod_data), ..rest] -> {
      case dict.get(mod_data.functions, fn_name) {
        Ok(fn_data) -> Ok(render(fn_data.return_type))
        Error(_) -> find_function_in_modules(rest, fn_name)
      }
    }
  }
}

fn find_qualified_function_in_modules(
  modules: List(#(String, ModuleData)),
  mod_alias: String,
  fn_name: String,
) -> Result(String, Nil) {
  case modules {
    [] -> Error(Nil)
    [#(mod_name, mod_data), ..rest] -> {
      let matches =
        mod_name == mod_alias || string.ends_with(mod_name, "/" <> mod_alias)
      case matches {
        True -> {
          case dict.get(mod_data.functions, fn_name) {
            Ok(fn_data) -> Ok(render(fn_data.return_type))
            Error(_) ->
              find_qualified_function_in_modules(rest, mod_alias, fn_name)
          }
        }
        False -> find_qualified_function_in_modules(rest, mod_alias, fn_name)
      }
    }
  }
}
