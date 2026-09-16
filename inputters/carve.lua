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

--- The file SILE is processing, when `doc` is still exactly its content.
-- Source handed over as a string, or rewritten on the way, has no file.
local function sourceFile (doc)
  local path = SILE.currentlyProcessingFile
  -- SILE also reads named pipes, and a pipe cannot be read a second time.
  if type(path) ~= "string" or require("lfs").attributes(path, "mode") ~= "file" then return nil end
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local content = handle:read("*a")
  handle:close()
  return content == doc and path or nil
end

function inputter:parse (doc)
  local includes = self.options.includes
  local json, err, warnings = bridge.convert(doc, {
    converter = self.options.converter,
    source_path = sourceFile(doc),
    include_root = self.options.include_root,
    includes = includes ~= false and includes ~= "false",
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
