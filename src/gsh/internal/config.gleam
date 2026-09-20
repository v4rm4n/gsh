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

  case simplifile.read("gleam.toml") {
    Error(_) -> default_config
    Ok(content) -> {
      case tom.parse(content) {
        Error(_) -> default_config
        Ok(toml) -> {
          // Extract the array from [tools.gsh] -> imports
          let imports =
            tom.get_array(toml, ["tools", "gsh", "imports"])
            |> result.unwrap([])
            |> list.filter_map(fn(val) {
              case val {
                tom.String(s) -> Ok("import " <> s)
                _ -> Error(Nil)
              }
            })

          // Extract the array from [tools.gsh] -> apps
          let apps =
            tom.get_array(toml, ["tools", "gsh", "apps"])
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
