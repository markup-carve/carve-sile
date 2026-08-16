--- Assertions on what carve/renderer.lua puts into the SILE AST.
--
-- Run it through test/renderer.sh, which executes this file inside SILE, so
-- SU.ast and pl.class are the real ones rather than a stand-in that could
-- agree with a broken renderer.
--
-- Every fixture is parsed by the carve CLI, so the AST under assertion is the
-- engine's own output rather than a hand-written record that could drift from
-- it.

local repo = os.getenv("CARVE_SILE_REPO") or "."
package.path = repo .. "/?.lua;" .. package.path

local bridge = require("carve.bridge")
local Renderer = require("carve.renderer")

-- Same decoder choice as inputters/carve.lua, so an installation with only one
-- of the two rocks runs the assertions rather than dying on the require.
local hasJson, decoder = pcall(require, "json.decode")
if not hasJson then hasJson, decoder = pcall(require, "lunajson") end
if not hasJson then error("the renderer assertions require luajson or lunajson") end

local NBSP_SENTINEL = "\238\128\128" -- U+E000
local NBSP = "\194\160" -- U+00A0

local failed = {}
local run = 0

local function check (name, ok, detail)
  run = run + 1
  if ok then
    print("ok   - " .. name)
  else
    failed[#failed + 1] = name
    print("FAIL - " .. name)
    if detail then print("       " .. tostring(detail)) end
  end
end

local function render (source)
  local json, err = bridge.convert(source, {})
  if not json then error("carve CLI: " .. tostring(err)) end
  return Renderer({}):render(decoder.decode(json))
end

--- Every table in a rendered tree, depth first, the root included.
local function tables (node, acc)
  acc = acc or {}
  if type(node) == "table" then
    acc[#acc + 1] = node
    for i = 1, #node do tables(node[i], acc) end
  end
  return acc
end

--- Every string in a rendered tree, concatenated in document order.
local function flatten (node)
  local out = {}
  local function walk (n)
    if type(n) == "string" then
      out[#out + 1] = n
    elseif type(n) == "table" then
      for i = 1, #n do walk(n[i]) end
    end
  end
  walk(node)
  return table.concat(out)
end

local function firstCommand (tree, command)
  for _, node in ipairs(tables(tree)) do
    if node.command == command then return node end
  end
  return nil
end

--- Show a string with its non-ASCII bytes spelled out, so a U+E000 in a
-- failure report is not an invisible box in the terminal too.
local function visible (s)
  return (s:gsub("[^\032-\126]", function (c) return string.format("<%02X>", string.byte(c)) end))
end

-- A document that reaches every handler the assertions below care about, so
-- the tree-wide invariants are measured over more than one construct.
local BROAD = table.concat({
  "# A heading",
  "",
  "Escaped\\ space here, a code span `x" .. NBSP_SENTINEL .. "y`, and !`lit"
    .. NBSP_SENTINEL .. "eral`.",
  "",
  "```",
  "code block a" .. NBSP_SENTINEL .. "b",
  "```",
  "",
  ":term[widget] inline ext.",
  "",
  -- A line block is the sentinel's other source: the parser rewrites the
  -- indentation it preserves to a run of U+E000, which the engine's HTML
  -- target emits as a run of `&nbsp;`.
  "::: |",
  "line one",
  "    indented line",
  ":::",
  "",
  "{#pid .note}",
  "Attributed paragraph text.",
  "",
  "- One item",
  "- Another item",
  "",
}, "\n")

local broad = render(BROAD)

-- 1. inline_extension carries its content as an ARRAY OF NODES. Handing that
-- array to createCommand as content puts unconverted AST records into the SILE
-- tree, where SILE.process drops them: the word disappears from the PDF.
do
  local tree = render(":term[widget] inline ext.\n")
  local span = firstCommand(tree, "markdown:internal:span")
  check("inline extension renders a span", span ~= nil)
  if span then
    check(
      "inline extension content is rendered, not passed through as AST records",
      flatten(span) == "widget",
      "got " .. string.format("%q", visible(flatten(span)))
    )
  end
end

-- 2. The same defect, stated as an invariant: nothing in a rendered tree may
-- still be an exchange-AST record. Those carry `type`; SILE commands carry
-- `command`.
do
  local leaked = {}
  for _, node in ipairs(tables(broad)) do
    if node.type ~= nil and node.command == nil then
      leaked[#leaked + 1] = tostring(node.type)
    end
  end
  check(
    "no unconverted exchange-AST record reaches the SILE tree",
    #leaked == 0,
    "leaked: " .. table.concat(leaked, ", ")
  )
end

-- 3. The parser carries a non-breaking space as U+E000. Left alone it reaches
-- the typesetter as an unmapped private-use codepoint, and SILE draws the
-- font's .notdef box for it.
do
  local tree = render("Escaped\\ space here.\n")
  local got = flatten(tree)
  check(
    "an escaped space becomes a real non-breaking space",
    got == "Escaped" .. NBSP .. "space here.",
    "got " .. string.format("%q", visible(got))
  )
end

-- 4. The same defect as an invariant, over text, a code span, a code block and
-- a literal inline - every place the engine's own HTML target resolves the
-- sentinel.
do
  local carriers = {}
  for _, node in ipairs(tables(broad)) do
    for i = 1, #node do
      if type(node[i]) == "string" and node[i]:find(NBSP_SENTINEL, 1, true) then
        carriers[#carriers + 1] = string.format("%q", visible(node[i]))
      end
    end
  end
  check(
    "no U+E000 sentinel reaches the SILE tree",
    #carriers == 0,
    "carried by: " .. table.concat(carriers, ", ")
  )
end

-- 5. An id on a block has to land on a command that reads options.
-- `markdown:internal:paragraph` is declared `function (_, content)` in
-- resilient.sile: it ignores options outright, so an id routed there is
-- dropped and the `\label` that a `[text](#id)` link resolves against is never
-- emitted. `markdown:internal:div` does emit it, and cascades the paragraph
-- itself, which is also what resilient's own djot inputter does with an
-- attributed paragraph.
do
  local tree = render("{#pid .note}\nAttributed paragraph text.\n")
  check(
    "an attributed paragraph keeps its id on a command that consumes options",
    tree.command == "markdown:internal:div" and tree.options and tree.options.id == "pid",
    "got command " .. tostring(tree.command)
  )

  local dropped = {}
  for _, node in ipairs(tables(broad)) do
    if node.command == "markdown:internal:paragraph" and node.options then
      for key in pairs(node.options) do dropped[#dropped + 1] = key end
    end
  end
  check(
    "no options are handed to markdown:internal:paragraph, which discards them",
    #dropped == 0,
    "would be dropped: " .. table.concat(dropped, ", ")
  )
end

-- 6. Control. Nothing above touches heading rendering; if this one ever passes
-- while the file is broken on purpose, the suite is not running.
do
  local tree = render("# A heading\n")
  check(
    "a heading renders as a header command at its own level",
    tree.command == "markdown:internal:header" and tree.options.level == 1,
    "got command " .. tostring(tree.command) .. " level " .. tostring(tree.options and tree.options.level)
  )
end

print(string.format("\n%d checks, %d failed", run, #failed))
os.exit(#failed == 0 and 0 or 1)
