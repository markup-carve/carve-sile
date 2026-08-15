-- Unit test for carve/figuregroup.lua. Pure Lua: no SILE, no Resilient.
--
-- The fixtures below are the shape Resilient's pandocast renderer actually
-- produces for examples/composite-figure.crv, read off the parsed tree:
--
--   markdown:internal:captioned-figure  class=columns-2
--     <list #2>
--       markdown:internal:captioned-table
--       markdown:internal:captioned-figure
--     caption
--   markdown:internal:div  class=admonition figure
--     <list #2>
--       markdown:internal:paragraph
--       markdown:internal:captioned-figure
--
-- test/smoke.sh checks the same thing end to end through SILE, against the
-- list-of-figures entries the run writes out. This one is the fast half.

package.path = (arg[0]:match("^(.*)/test/[^/]+$") or ".") .. "/?.lua;" .. package.path
local figuregroup = require("carve.figuregroup")

local failures = 0

local function check (name, condition)
  if condition then
    print("ok   - " .. name)
  else
    print("FAIL - " .. name)
    failures = failures + 1
  end
end

local function command (name, options, children)
  local node = children or {}
  node.command = name
  node.id = "command"
  node.options = options or {}
  return node
end

local function classOf (node)
  return node.options and node.options.class or ""
end

-- A group: two panels, one of each kind pandocast can produce.
local tablePanel = command("markdown:internal:captioned-table", {})
local figurePanel = command("markdown:internal:captioned-figure", {})
local group = command("markdown:internal:captioned-figure", { class = "columns-2" }, {
  { tablePanel, figurePanel },
  command("caption", {}),
})

-- The control: the same panel content under a titled opener, which is not a
-- composite figure but a generic container.
local containedFigure = command("markdown:internal:captioned-figure", { class = "" })
local container = command("markdown:internal:div", { class = "admonition figure" }, {
  { command("markdown:internal:paragraph", {}), containedFigure },
})

-- Group content that is not a panel, and a panel that already carries a class.
local prose = command("markdown:internal:paragraph", {})
local keptPanel = command("markdown:internal:captioned-figure", { class = "custom" })
local mixedGroup = command("markdown:internal:captioned-figure", {}, {
  { prose, keptPanel },
  command("caption", {}),
})

-- A single-panel group: pandocast collapses a one-element block list to the
-- element itself, so slot 1 is the panel node rather than a list.
local lonePanel = command("markdown:internal:captioned-figure", {})
local loneGroup = command("markdown:internal:captioned-figure", {}, {
  lonePanel,
  command("caption", {}),
})

figuregroup.mark({ group, container, mixedGroup, loneGroup })

check("a table panel is unnumbered", classOf(tablePanel):match("unnumbered") ~= nil)
check("a table panel is out of the list of figures", classOf(tablePanel):match("notoc") ~= nil)
check("a figure panel is unnumbered", classOf(figurePanel):match("unnumbered") ~= nil)
check("a figure panel is out of the list of figures", classOf(figurePanel):match("notoc") ~= nil)
check("the group keeps its own number", classOf(group) == "columns-2")
check("the group keeps its layout hint", classOf(group):match("columns%-2") ~= nil)

check("a figure in a titled container still numbers", classOf(containedFigure) == "")

check("non-panel group content is untouched", classOf(prose) == "")
check("a panel keeps the classes it had", classOf(keptPanel) == "custom unnumbered notoc")

check("a lone panel is unnumbered", classOf(lonePanel) == "unnumbered notoc")

-- Marking twice must not double the classes.
figuregroup.mark({ group })
check("marking is idempotent", classOf(figurePanel) == "unnumbered notoc")

if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("PASS: carve.figuregroup")
