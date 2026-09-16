--- Carve input support for SILE and resilient.sile.

local base = require("inputters.base")
local bridge = require("carve.bridge")
local Renderer = require("carve.renderer")

local inputter = pl.class(base)
inputter._name = "carve"
inputter.order = 2

function inputter.appropriate (round, filename, _)
  return round == 1 and filename:lower():match("%.crv$") ~= nil
end

function inputter:parse (doc)
  local json, err, warnings = bridge.convert(doc, {
    converter = self.options.converter,
    source_path = self.options.source_path,
    include_root = self.options.include_root,
  })
  if not json then
    SU.error(err)
  end
  if warnings and not warnings:match("^%s*$") then
    SU.warn(warnings:gsub("%s+$", ""))
  end

  local hasJson, decoder = pcall(require, "json.decode")
  if not hasJson then hasJson, decoder = pcall(require, "lunajson") end
  if not hasJson then SU.error("The Carve inputter requires luajson or lunajson") end

  local ast = decoder.decode(json)
  local tree = Renderer(self.options):render(ast)
  tree = SU.ast.createCommand("document", { class = "markdown" }, tree)
  return { tree }
end

return inputter
