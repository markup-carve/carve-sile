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
  "{#bfig}",
  "::: figure",
  "![p](p.png)",
  "^ (a) Panel",
  ":::",
  "^ Figure #: Broad group",
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

--- Does a command node carry `name` in its space-joined class option?
local function hasClass (node, name)
  local class = node.options and node.options.class
  if type(class) ~= "string" then return false end
  for word in class:gmatch("%S+") do
    if word == name then return true end
  end
  return false
end

local GROUP = table.concat({
  "{#fig-x .columns-2}",
  "::: figure",
  "{#fig-x-a}",
  "![one](a.png)",
  "^ (a) One",
  "",
  "| Kind | N |",
  "|------|---|",
  "| a    | 1 |",
  "^ (b) A table panel",
  "",
  "Stray text between the panels.",
  ":::",
  "^ Figure #: Group caption",
  "",
}, "\n")

-- 7. A composite figure (PART 9 section 4c) is ONE numbering unit. Resilient
-- numbers every captioned figure and table it typesets, so unmarked panels
-- would take a number and a list entry each: a two-panel group would consume
-- three figure-sequence draws and file three list entries. The panels must
-- carry `unnumbered` and `notoc` - the classes Resilient's captioned commands
-- read - while the group itself carries neither.
do
  local tree = render(GROUP)
  check(
    "a figure group renders as one captioned figure carrying its attributes",
    tree.command == "markdown:internal:captioned-figure"
      and tree.options and tree.options.id == "fig-x" and hasClass(tree, "columns-2"),
    "got command " .. tostring(tree.command) .. " id " .. tostring(tree.options and tree.options.id)
  )
  check(
    "the group is the numbered element and the list entry",
    not hasClass(tree, "unnumbered") and not hasClass(tree, "notoc"),
    "group class: " .. tostring(tree.options and tree.options.class)
  )

  local figurePanel, tablePanel, stray, groupCaption
  for i = 1, #tree do
    local child = tree[i]
    if child.command == "markdown:internal:captioned-figure" then figurePanel = child end
    if child.command == "markdown:internal:captioned-table" then tablePanel = child end
    if child.command == "markdown:internal:paragraph" then stray = child end
    if child.command == "caption" then groupCaption = child end
  end
  check(
    "a figure panel keeps its caption but takes neither number nor list entry",
    figurePanel ~= nil and hasClass(figurePanel, "unnumbered") and hasClass(figurePanel, "notoc")
      and flatten(firstCommand(figurePanel, "caption")) == "(a) One",
    figurePanel and ("class " .. tostring(figurePanel.options.class) .. ", caption "
      .. string.format("%q", flatten(firstCommand(figurePanel, "caption")))) or "no figure panel"
  )
  check(
    "a table panel is marked the same way through the captioned-table path",
    tablePanel ~= nil and hasClass(tablePanel, "unnumbered") and hasClass(tablePanel, "notoc"),
    tablePanel and ("class " .. tostring(tablePanel.options.class)) or "no table panel"
  )
  check(
    "stray group content is preserved in place, not suppressed by the hint",
    stray ~= nil and flatten(stray) == "Stray text between the panels.",
    stray and string.format("%q", flatten(stray)) or "no stray paragraph"
  )
  check(
    "the group caption sits last, with the engine's number resolved",
    groupCaption ~= nil and tree[#tree] == groupCaption
      and flatten(groupCaption) == "Figure 1: Group caption",
    groupCaption and string.format("%q", flatten(groupCaption)) or "no group caption"
  )
end

-- 8. Absent means uncaptioned: a group without the `^ ` line after the closing
-- fence must not grow an empty caption command, because Resilient's
-- captioned-figure would number it and file a blank list entry.
do
  local tree = render(table.concat({
    "::: figure",
    "![one](a.png)",
    "^ (a) One",
    "",
    "![two](b.png)",
    "^ (b) Two",
    ":::",
    "",
  }, "\n"))
  local direct = false
  for i = 1, #tree do
    if tree[i].command == "caption" then direct = true end
  end
  check("an uncaptioned group emits no group caption command", not direct)
end

-- 9. Only DIRECT children are panels, which is the engine's rule too: a
-- captioned figure nested inside stray group content keeps its own number.
-- Marking every captioned DESCENDANT instead would leave test 7 green, so
-- this is the check that pins the depth.
do
  local tree = render(table.concat({
    "::: figure",
    "![one](a.png)",
    "^ (a) One",
    "",
    "::: note",
    "![deep](d.png)",
    "^ Figure #: Not a panel",
    ":::",
    ":::",
    "^ Figure #: Group caption",
    "",
  }, "\n"))
  local nested
  for _, node in ipairs(tables(tree)) do
    if node.command == "markdown:internal:captioned-figure"
      and flatten(firstCommand(node, "caption")):find("Not a panel", 1, true) then
      nested = node
    end
  end
  check(
    "a captioned figure nested below a direct child keeps its own number",
    nested ~= nil and not hasClass(nested, "unnumbered") and not hasClass(nested, "notoc"),
    nested and ("class " .. tostring(nested.options.class)) or "nested figure not found"
  )
end

-- 10. Control. The panel marking must come from the group, not from the figure
-- or table handlers: a captioned figure outside any group keeps its number,
-- and if this ever fails the classes were fixed at the wrong layer.
do
  local tree = render("![one](a.png)\n^ Figure #: Alone\n")
  check(
    "a standalone captioned figure is still a numbered element",
    tree.command == "markdown:internal:captioned-figure"
      and not hasClass(tree, "unnumbered") and not hasClass(tree, "notoc"),
    "got command " .. tostring(tree.command) .. " class " .. tostring(tree.options and tree.options.class)
  )
end

-- 11. Includes. Each target below WOULD resolve if the guard under test were
-- missing, so a directive left standing is evidence rather than a default.
do
  local function write (filename, content)
    local handle = assert(io.open(filename, "wb"))
    handle:write(content)
    handle:close()
  end
  local function has (text, needle) return text:find(needle, 1, true) ~= nil end

  local base = os.tmpname()
  os.remove(base)
  local book = base .. "/book"
  pl.dir.makepath(book .. "/parts/nested")
  write(base .. "/outside.crv", "OUTSIDE-ROOT\n")
  write(book .. "/parts/one.crv", "One.\n\n{{ nested/two.crv }}\n\n{{ nested/gone.crv }}\n")
  write(book .. "/parts/nested/two.crv", "Two.\n")
  local mainSource = "Before.\n\n{{ parts/one.crv }}\n"
  write(book .. "/main.crv", mainSource)
  local escapeSource = "{{ ../outside.crv }}\n"
  write(book .. "/escape.crv", escapeSource)

  local function convert (source, options)
    local json, err, warnings = bridge.convert(source, options)
    local text = json and flatten(Renderer({}):render(decoder.decode(json))) or ""
    return text, err or "", warnings or ""
  end

  local text, err, warnings = convert(mainSource, { source_path = book .. "/main.crv" })
  check("a named file expands nested includes against their parent", has(text, "Two."), err)
  check("an include that does not resolve reports itself", has(warnings, "include-unresolved"), warnings)
  check("include warnings name no host path", not has(warnings, base), warnings)
  check("include warnings name the file below the root", has("\n" .. warnings, "\nparts/one.crv:"), warnings)

  text, err = convert(escapeSource, { source_path = book .. "/escape.crv" })
  check("a directive cannot leave the file's directory", not has(text, "OUTSIDE-ROOT"), err)

  text, err = convert(escapeSource, { source_path = book .. "/escape.crv", include_root = base })
  check("include_root widens containment", has(text, "OUTSIDE-ROOT"), err)

  text, err = convert("text\n", { include_root = "book", converter = "/nonexistent/carve" })
  check("a relative include_root is refused before the converter runs", has(err, "must be an absolute path"), err)

  text, err = convert("text\n", { include_root = "C:\\book", converter = "/nonexistent/carve" })
  check("a drive-letter include_root is relative on POSIX", has(err, "must be an absolute path"), err)

  -- A temporary file would give the source the temporary directory as its root.
  local stray = os.tmpname()
  os.remove(stray)
  write(stray .. ".crv", "STRAY-TEMP\n")
  text, err = convert("{{ " .. pl.path.basename(stray) .. ".crv }}\n", {})
  check("source without a file does not resolve against the temporary directory", not has(text, "STRAY-TEMP"), err)
  os.remove(stray .. ".crv")

  text, err = convert("{{ parts/one.crv }}\n", { include_root = book })
  check("source without a file resolves against include_root", has(text, "One."), err)

  text, err = convert(mainSource, { source_path = book .. "/main.crv", includes = false })
  check("includes = false leaves a named file's directives literal", not has(text, "One."), err)

  local old = "carve-0.1.6"
  if pl.utils.executeex("command -v " .. old) then
    check("the probe finds include support in the current CLI", bridge.supportsIncludes("carve"))
    check("the probe finds none in " .. old, not bridge.supportsIncludes(old))

    text, err, warnings = convert(mainSource, { converter = old, source_path = book .. "/main.crv" })
    check("an older CLI still renders a named file with directives", has(text, "{{ parts/one.crv }}"), err)
    check("an older CLI reports that directives stayed literal", has(warnings, "include directives left literal"), warnings)

    text, err = convert(mainSource, { converter = old, source_path = book .. "/main.crv", include_root = book })
    check("include_root with an older CLI is an error", has(err, "has no include support"), err)

    text, err = convert(mainSource, { converter = old, source_path = book .. "/main.crv", includes = false })
    check("an older CLI accepts includes = false", has(text, "Before."), err)
  else
    print("skip - " .. old .. " is not installed; older-CLI include checks not run")
  end

  local Inputter = require("inputters.carve")
  local function parseAs (file, doc, options)
    local saved = SILE.currentlyProcessingFile
    SILE.currentlyProcessingFile = file
    local ok, result = pcall(function () return Inputter(options or {}):parse(doc) end)
    SILE.currentlyProcessingFile = saved
    return ok and flatten(result) or ("ERROR: " .. tostring(result))
  end

  text = parseAs(book .. "/main.crv", mainSource)
  check("the inputter gives the bridge the file SILE is processing", has(text, "Two."), text)

  text = parseAs(book .. "/main.crv", "Rewritten.\n\n{{ parts/one.crv }}\n")
  check("source that differs from its file is not read from the file", not has(text, "One."), text)
  check("source that differs from its file still renders", has(text, "Rewritten."), text)

  text = parseAs(book .. "/escape.crv", escapeSource, { include_root = base })
  check("the inputter passes include_root", has(text, "OUTSIDE-ROOT"), text)

  text = parseAs(book .. "/main.crv", mainSource, { includes = "false" })
  check("the inputter honors includes=false from an option string", not has(text, "One."), text)

  pl.dir.rmtree(base)
end

print(string.format("\n%d checks, %d failed", run, #failed))
os.exit(#failed == 0 and 0 or 1)
