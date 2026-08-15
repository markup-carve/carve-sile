--- Make a Carve composite figure number as one unit in the Resilient renderer.
--
-- Carve PART 9 section 4c: a bare `::: figure` container is ONE figure of
-- ordered panels. Its direct `figure` and `table` children are the panels; the
-- group is one numbering unit, and only the group produces a list-of-figures
-- entry. A number placeholder in a panel caption stays literal.
--
-- pandoc-carve maps that node to a Pandoc `Figure` whose direct `Figure` and
-- `Table` children are the panels, and Resilient's `pandocast` renderer turns
-- every one of those into its own captioned float. Left alone, a group of two
-- panels therefore consumes three figure numbers and files three list-of-
-- figures entries, and Resilient's counter stops agreeing with the number
-- Carve already resolved into the group caption.
--
-- Resilient's `markdown:internal:captioned-*` commands read the `unnumbered`
-- and `notoc` classes off their options, so the whole correction is to put
-- those two classes on the panels. Nothing else about the group changes: the
-- panels keep their captions, their ids and their position, and group content
-- that is not a panel is left exactly where it was.
--
-- Only DIRECT children are panels. A captioned figure that sits inside group
-- content -- inside a `::: note`, or inside the generic div a nested bare
-- `::: figure` degrades to -- is not a panel and keeps its own number, which
-- is what corpus documents 318-composite-figures-9 and -11 pin.

local figuregroup = {}

-- The two commands `pandocast` produces for a captioned float. It has no path
-- to `markdown:internal:captioned-listing`, so that one is deliberately absent
-- rather than listed for symmetry: a panel can only arrive as one of these.
local CAPTIONED = {
  ["markdown:internal:captioned-figure"] = true,
  ["markdown:internal:captioned-table"] = true,
}

local PANEL_CLASSES = { "unnumbered", "notoc" }

local function hasClass (classes, name)
  return string.find(" " .. classes .. " ", " " .. name .. " ", 1, true) ~= nil
end

local function markPanel (node)
  node.options = node.options or {}
  local classes = node.options.class or ""
  for _, name in ipairs(PANEL_CLASSES) do
    if not hasClass(classes, name) then
      classes = classes == "" and name or (classes .. " " .. name)
    end
  end
  node.options.class = classes
end

-- A captioned figure holds { <rendered blocks>, <caption> }. The first slot is
-- the list of the group's direct children, except that pandocast collapses a
-- one-element list to the element itself, so a single-panel group arrives as a
-- bare command node.
local function directChildren (node)
  local slot = node[1]
  if type(slot) ~= "table" then
    return {}
  end
  if slot.command then
    return { slot }
  end
  return slot
end

--- Mark the panels of every composite figure in a SILE AST, in place.
-- @tparam table tree SILE AST node, or a list of them
-- @treturn table the same tree
function figuregroup.mark (tree)
  if type(tree) ~= "table" then
    return tree
  end
  if tree.command == "markdown:internal:captioned-figure" then
    for _, child in ipairs(directChildren(tree)) do
      if type(child) == "table" and CAPTIONED[child.command] then
        markPanel(child)
      end
    end
  end
  for _, child in ipairs(tree) do
    figuregroup.mark(child)
  end
  return tree
end

return figuregroup
