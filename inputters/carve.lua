--- Carve input support for SILE and resilient.sile.

local base = require("inputters.base")
local bridge = require("carve.bridge")
local figuregroup = require("carve.figuregroup")
local pandocast = require("inputters.pandocast")

local inputter = pl.class(base)
inputter._name = "carve"
inputter.order = 2

function inputter.appropriate (round, filename, _)
  return round == 1 and filename:lower():match("%.crv$") ~= nil
end

function inputter:parse (doc)
  local json, err, warnings = bridge.convert(doc, {
    converter = self.options.converter,
  })
  if not json then
    SU.error(err)
  end
  if warnings and not warnings:match("^%s*$") then
    SU.warn(warnings:gsub("%s+$", ""))
  end

  -- Reuse resilient.sile's mature Pandoc AST-to-SILE renderer. This returns
  -- the complete document AST, including the default markdown/resilient class.
  local tree = pandocast(self.options):parse(json)

  -- A Carve composite figure is one numbering unit (PART 9 section 4c), but
  -- the renderer above numbers each panel separately. Suppress the panels.
  return figuregroup.mark(tree)
end

return inputter
