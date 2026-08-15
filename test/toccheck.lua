-- Check the list entries a SILE run produced for a composite-figure example.
--
--   toccheck.lua panels <file.toc>   examples/composite-figure.crv
--   toccheck.lua nested <file.toc>   examples/composite-figure-nested.crv
--
-- Resilient writes its table-of-contents data as a Lua chunk next to the
-- master file, one record per entry, with figure captions at level 5 and table
-- captions at level 6. That makes the numbering observable without reading the
-- PDF.

local mode = assert(arg[1], "usage: toccheck.lua <panels|nested> <file.toc>")
local path = assert(arg[2], "usage: toccheck.lua <panels|nested> <file.toc>")
local toc = assert(loadfile(path))()

local failures = 0

local function check (name, condition, detail)
  if condition then
    print("ok   - " .. name)
  else
    print("FAIL - " .. name .. (detail and (" (" .. detail .. ")") or ""))
    failures = failures + 1
  end
end

local function flatten (node, out)
  if type(node) == "string" then
    out[#out + 1] = node
  elseif type(node) == "table" then
    for _, child in ipairs(node) do
      flatten(child, out)
    end
  end
  return out
end

local figures = {}
local tables = {}
for _, entry in ipairs(toc) do
  local record = {
    number = entry.number,
    text = table.concat(flatten(entry.label, {}), " "),
  }
  if entry.level == 5 then
    figures[#figures + 1] = record
  elseif entry.level == 6 then
    tables[#tables + 1] = record
  end
end

local function has (list, needle)
  for _, record in ipairs(list) do
    if record.text:find(needle, 1, true) then
      return record
    end
  end
  return nil
end

if mode == "panels" then
  -- Section 4c wants exactly two entries here: the composite figure, one unit
  -- whatever its panel count, and the captioned listing in the titled
  -- container, which is not a group and numbers on its own. Without
  -- carve/figuregroup.lua the listing panel files an entry of its own, the
  -- count is three, and Resilient numbers the group 2 while the caption Carve
  -- resolved still reads "Figure 1:".
  check("the example files two list-of-figures entries", #figures == 2,
    "found " .. #figures)

  -- A table panel goes to the list of tables rather than the list of figures,
  -- so it needs suppressing on its own account. Without that the example files
  -- one entry here, and the panel takes table number 1.
  check("the table panel files no list-of-tables entry", #tables == 0,
    "found " .. #tables)

  if #figures == 2 then
    check("the composite figure is the first entry",
      figures[1].text:find("Two panels, one figure", 1, true) ~= nil,
      figures[1].text)
    check("Resilient numbers the group 1", figures[1].number == "1",
      tostring(figures[1].number))
    check("the caption Carve resolved agrees with that number",
      figures[1].text:find("Figure 1:", 1, true) ~= nil,
      figures[1].text)
    check("the titled container's listing numbers on its own",
      figures[2].number == "2" and
        figures[2].text:find("still its own figure", 1, true) ~= nil,
      tostring(figures[2].number) .. " " .. figures[2].text)
  end
elseif mode == "nested" then
  -- The captioned listing here sits inside a `::: note` inside the group. It
  -- is group content, not a panel, so it keeps a number and an entry of its
  -- own; only the group's DIRECT figure and table children are panels. A rule
  -- written over descendants instead of direct children suppresses it and
  -- leaves one entry.
  --
  -- No number is asserted. Resilient numbers every captioned figure, while
  -- Carve only numbers the captions that carry a placeholder, so the two
  -- counters agree only in a document where every caption carries one. This
  -- example deliberately is not such a document.
  check("the example files two list-of-figures entries", #figures == 2,
    "found " .. #figures)
  check("the group files an entry",
    has(figures, "A group whose content is not a panel") ~= nil)
  check("group content that is not a panel keeps its own entry",
    has(figures, "still its own figure") ~= nil)
else
  print("unknown mode: " .. mode)
  os.exit(1)
end

if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("PASS: composite figure numbering (" .. mode .. ")")
