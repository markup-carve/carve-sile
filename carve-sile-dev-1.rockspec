rockspec_format = "3.0"
package = "carve-sile"
version = "dev-1"

source = {
  url = "git+https://github.com/markup-carve/carve-sile.git",
}

description = {
  summary = "Carve input support for the SILE typesetter and resilient.sile",
  detailed = [[
    A SILE inputter for .crv documents. It converts Carve to Pandoc JSON with
    pandoc-carve, then delegates to resilient.sile's Pandoc AST renderer.
  ]],
  homepage = "https://github.com/markup-carve/carve-sile",
  license = "MIT",
}

dependencies = {
  "lua >= 5.1",
  "resilient.sile >= 4.2.0",
}

build = {
  type = "builtin",
  modules = {
    ["sile.inputters.carve"] = "inputters/carve.lua",
    ["sile.carve.bridge"] = "carve/bridge.lua",
    ["sile.carve.renderer"] = "carve/renderer.lua",
  },
}
