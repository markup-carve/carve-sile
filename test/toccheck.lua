-- Check the list-of-figures entries a SILE run produced for
-- examples/composite-figure.crv.
--
-- Resilient writes its table-of-contents data as a Lua chunk next to the
-- master file, one record per entry, with figure captions at level 5. That
-- makes the numbering observable without reading the PDF.
--
-- Carve PART 9 section 4c wants exactly two entries out of that example: the
-- composite figure (one unit, whatever its panel count) and the captioned
-- listing in the titled container, which is not a group and numbers on its
-- own. Without carve/figuregroup.lua the two panels file entries of their own,
-- the count is four, and the number Resilient gives the group no longer
-- matches the number Carve already resolved into its caption.

local path = assert(arg[1], "usage: toccheck.lua <file.toc>")
local chunk = assert(loadfile(path))
local toc = chunk()

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
for _, entry in ipairs(toc) do
  if entry.level == 5 then
    figures[#figures + 1] = {
      number = entry.number,
      text = table.concat(flatten(entry.label, {}), " "),
    }
  end
end

check("the example files two list-of-figures entries", #figures == 2,
  "found " .. #figures)

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

if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("PASS: composite figure numbering")
