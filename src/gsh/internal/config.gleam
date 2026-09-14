// src/gsh/internal/config.gleam

import gleam/list
import gleam/result
import simplifile
import tom

pub type Config {
  Config(default_imports: List(String), auto_boot_apps: List(String))
}

pub fn load() -> Config {
  let default_config = Config(default_imports: [], auto_boot_apps: [])

  case simplifile.read(".gsh.toml") {
    Error(_) -> default_config
    Ok(content) -> {
      case tom.parse(content) {
        Error(_) -> default_config
        Ok(toml) -> {
          // Extract the [imports] array
          let imports =
            tom.get_array(toml, ["imports"])
            |> result.unwrap([])
            |> list.filter_map(fn(val) {
              case val {
                tom.String(s) -> Ok("import " <> s)
                _ -> Error(Nil)
              }
            })

          let apps =
            tom.get_array(toml, ["apps"])
            |> result.unwrap([])
            |> list.filter_map(fn(val) {
              case val {
                tom.String(s) -> Ok(s)
                _ -> Error(Nil)
              }
            })

          Config(default_imports: imports, auto_boot_apps: apps)
        }
      }
    }
  }
}
