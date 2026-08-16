--- Convert the normative Carve exchange AST directly to SILE commands.

local createCommand, createStructuredCommand = SU.ast.createCommand, SU.ast.createStructuredCommand

local Renderer = pl.class()

local function pos (node)
  if not node.pos then return nil end
  return {
    lno = node.pos.startLine,
    col = node.pos.startColumn,
    pos = node.pos.startOffset,
  }
end

local function attrs (node, extraClass)
  local source = node.attrs or {}
  local out = {}
  if source.id then out.id = source.id end
  if source.classes and #source.classes > 0 then
    out.class = table.concat(source.classes, " ")
  end
  if extraClass then
    out.class = out.class and (out.class .. " " .. extraClass) or extraClass
  end
  for key, value in pairs(source.keyValues or {}) do out[key] = value end
  return out
end

local function asList (value)
  if value == nil then return {} end
  if type(value) == "table" and value.command then return { value } end
  return value
end

-- The parser carries a no-break space as U+E000, a private-use codepoint: an
-- escaped `\ `, and the indentation a line block preserves, both arrive as
-- that character rather than as U+00A0, which is published as itself. The
-- exchange format requires the resolution rather than suggesting it - a
-- consumer "MUST map U+E000 to its target's no-break space, or to an ordinary
-- space where the target has none, and MUST NOT emit it" (the AST schema, on
-- a text node's value).
--
-- SILE has a no-break space, so the first branch applies: it honors U+00A0,
-- hyphenating a word rather than breaking the line at one. Left alone the
-- sentinel is not dropped either - SILE draws the font's .notdef box for it,
-- so `Escaped\ space` typesets as "Escaped[]space". That puts this target
-- alongside the engine's HTML and Markdown output rather than alongside its
-- terminal targets, which flatten the sentinel to an ordinary space because a
-- terminal has nowhere to put the no-break property.
local NBSP_SENTINEL = "\238\128\128" -- U+E000
local NBSP = "\194\160" -- U+00A0

--- Resolve the sentinel in a string the renderer is about to typeset.
-- Applied where the engine's own HTML target escapes the value - text, code
-- spans, code blocks, literal inlines - and deliberately not to raw blocks and
-- raw inlines, which that target passes through byte for byte.
local function resolveNbsp (value)
  if type(value) ~= "string" then return value end
  return (value:gsub(NBSP_SENTINEL, NBSP))
end

function Renderer:_init (options)
  self.shiftHeadings = SU.cast("integer", options.shift_headings or 0)
  self.footnotes = {}
end

function Renderer:render (document)
  if type(document) ~= "table" or document.type ~= "document" then
    SU.error("Carve parser output is not a document exchange AST")
  end
  for _, node in ipairs(document.children or {}) do
    if node.type == "footnote" then self.footnotes[node.label] = node end
  end
  return self:children(document)
end

function Renderer:children (node, field)
  local output = {}
  for _, child in ipairs(node[field or "children"] or {}) do
    local rendered = self:node(child)
    if rendered ~= nil then
      if type(rendered) == "string" and type(output[#output]) == "string" then
        output[#output] = output[#output] .. rendered
      else
        output[#output + 1] = rendered
      end
    end
  end
  if #output == 1 then return output[1] end
  return output
end

function Renderer:node (node)
  local handler = self[node.type]
  if not handler then SU.error("Unsupported Carve AST node type '" .. tostring(node.type) .. "'") end
  return handler(self, node)
end

function Renderer:document (node) return self:children(node) end
function Renderer:text (node) return resolveNbsp(node.value) end
function Renderer:escaped_text (node) return node.value end
function Renderer:soft_break (_) return " " end
function Renderer:hard_break (_) return createCommand("markdown:internal:hardbreak") end
function Renderer:comment (_) return nil end
function Renderer:frontmatter (_) return nil end
function Renderer:link_reference_definition (_) return nil end
function Renderer:abbreviation_def (_) return nil end

function Renderer:paragraph (node)
  local content = self:children(node)
  local options = attrs(node)
  if next(options) then
    return createCommand("markdown:internal:div", options, content, pos(node))
  end
  return createCommand("markdown:internal:paragraph", {}, content, pos(node))
end

function Renderer:heading (node)
  local options = attrs(node)
  options.level = node.level + self.shiftHeadings
  return createCommand("markdown:internal:header", options, self:children(node), pos(node))
end

function Renderer:thematic_break (node)
  return createCommand("markdown:internal:thematicbreak", attrs(node), nil, pos(node))
end

function Renderer:block_quote (node)
  return createCommand("blockquote", attrs(node), self:children(node), pos(node))
end

function Renderer:div (node)
  return createCommand("markdown:internal:div", attrs(node), self:children(node), pos(node))
end

function Renderer:admonition (node)
  local options = attrs(node, "admonition " .. node.kind)
  local content = asList(self:children(node))
  if node.title and #node.title > 0 then
    table.insert(content, 1, createCommand("markdown:internal:paragraph", { class = "admonition-title" }, self:children(node, "title"), pos(node)))
  end
  return createCommand("markdown:internal:div", options, content, pos(node))
end

function Renderer:code_block (node)
  local options = attrs(node, node.lang)
  return createCommand("markdown:internal:codeblock", options, resolveNbsp(node.content), pos(node))
end

function Renderer:raw_block (node)
  return createCommand("markdown:internal:rawblock", { format = node.format }, node.content, pos(node))
end

function Renderer:list (node)
  local content = asList(self:children(node, "items"))
  if not node.ordered then return createStructuredCommand("itemize", {}, content, pos(node)) end
  return createStructuredCommand("enumerate", { start = node.start or 1 }, content, pos(node))
end

function Renderer:list_item (node)
  local bullet = node.checked == true and "☑" or node.checked == false and "☐" or nil
  return createCommand("item", { bullet = bullet }, self:children(node), pos(node))
end

function Renderer:table (node, extraClass)
  local rows = node.rows or {}
  local columns = rows[1] and #(rows[1].cells or {}) or 1
  local widths = {}
  for i = 1, columns do widths[i] = string.format("%.5f%%lw", 99.9 / columns) end
  local content = {}
  for _, row in ipairs(rows) do content[#content + 1] = self:node(row) end
  local tableNode = createStructuredCommand("ptable", {
    cols = table.concat(widths, " "),
    header = rows[1] and rows[1].cells and rows[1].cells[1] and rows[1].cells[1].header or false,
  }, content, pos(node))
  local wrapped = { tableNode }
  if node.caption and #node.caption > 0 then
    wrapped[#wrapped + 1] = createCommand("caption", {}, self:children(node, "caption"), pos(node))
  end
  return createStructuredCommand("markdown:internal:captioned-table", attrs(node, extraClass), wrapped, pos(node))
end

function Renderer:table_row (node)
  local content = {}
  for _, cell in ipairs(node.cells or {}) do content[#content + 1] = self:node(cell) end
  return createStructuredCommand("row", {}, content, pos(node))
end

function Renderer:table_cell (node)
  local options = { halign = node.align }
  if node.span then
    options.colspan = node.span.cols
    options.rowspan = node.span.rows
  end
  return createStructuredCommand("cell", options, self:children(node), pos(node))
end

local function inlineCommand (command, class)
  return function (self, node)
    local content = self:children(node)
    if class then return createCommand("markdown:internal:span", attrs(node, class), content, pos(node)) end
    local options = attrs(node)
    if next(options) then content = createCommand("markdown:internal:span", options, content, pos(node)) end
    return createCommand(command, {}, content, pos(node))
  end
end

Renderer.emphasis = inlineCommand("em")
Renderer.strong = inlineCommand("strong")
Renderer.underline = inlineCommand(nil, "underline")
Renderer.strike = inlineCommand(nil, "strike")
Renderer.highlight = inlineCommand(nil, "mark")
Renderer.insert = inlineCommand(nil, "inserted")
Renderer.delete = inlineCommand(nil, "deleted")

function Renderer:span (node)
  return createCommand("markdown:internal:span", attrs(node), self:children(node), pos(node))
end

function Renderer:subscript (node) return createCommand("textsubscript", {}, self:children(node), pos(node)) end
function Renderer:superscript (node) return createCommand("textsuperscript", {}, self:children(node), pos(node)) end
function Renderer:code (node) return createCommand("code", attrs(node), resolveNbsp(node.value), pos(node)) end
function Renderer:literal_inline (node) return createCommand("code", attrs(node), resolveNbsp(node.content), pos(node)) end

function Renderer:link (node)
  local options = attrs(node)
  options.src = node.href
  if node.title then options.title = node.title end
  return createCommand("markdown:internal:link", options, self:children(node), pos(node))
end

function Renderer:autolink (node)
  return createCommand("markdown:internal:link", { src = node.href }, { node.text or node.href }, pos(node))
end

function Renderer:heading_ref (node)
  return createCommand("markdown:internal:link", { src = node.href or ("#" .. node.target) }, { node.target }, pos(node))
end

function Renderer:image (node)
  local options = attrs(node)
  options.src = node.src
  if node.title then options.title = node.title end
  return createCommand("markdown:internal:image", options, { node.alt }, pos(node))
end

function Renderer:raw_inline (node)
  return createCommand("markdown:internal:rawinline", { format = node.format }, node.content, pos(node))
end

function Renderer:math (node)
  return createCommand("markdown:internal:math", { mode = node.display and "display" or "text" }, { node.content }, pos(node))
end

function Renderer:footnote_ref (node)
  local note = node.id and self.footnotes[node.id] or nil
  if not note then SU.error("Failure to find Carve footnote '" .. tostring(node.id) .. "'") end
  return createCommand("markdown:internal:footnote", { id = node.id }, self:children(note), pos(node))
end

function Renderer:inline_footnote (node)
  return createCommand("markdown:internal:footnote", {}, self:children(node, "inline"), pos(node))
end

function Renderer:footnote (_) return nil end
function Renderer:line_block (node) return createStructuredCommand("markdown:internal:lineblock", attrs(node), asList(self:children(node)), pos(node)) end
function Renderer:definition_list (node) return createCommand("markdown:internal:paragraph", attrs(node), self:children(node, "items"), pos(node)) end
function Renderer:definition_term (node) return createCommand("term", attrs(node), self:children(node), pos(node)) end
function Renderer:definition_description (node) return createCommand("definition", attrs(node), self:children(node), pos(node)) end

function Renderer:figure (node, extraClass)
  local target = self:node(node.target)
  local content = { target, createCommand("caption", {}, self:children(node, "caption"), pos(node)) }
  return createStructuredCommand("markdown:internal:captioned-figure", attrs(node, extraClass), content, pos(node))
end

-- A composite figure (PART 9 section 4c): one figure of ordered panels under
-- a single caption. The panels are the `figure` and `table` children, derived
-- by type exactly as the exchange schema defines them; every other child is
-- stray group content preserved in place between the panels.
--
-- The group is ONE numbering unit. Resilient numbers every captioned figure
-- and table it typesets and files each into the list of figures or tables, so
-- left alone a two-panel group would consume three numbers and three list
-- entries. The panels therefore carry `unnumbered` and `notoc`, the two
-- classes `markdown:internal:captioned-figure` and `-table` already read: the
-- group takes the only number, the list of figures gains one entry per group,
-- and each panel still keeps its own caption. A figure nested DEEPER than a
-- direct child - inside a note, a div, or stray paragraph content - is not a
-- panel and keeps its own number, which is also the engine's rule.
--
-- Resilient's captioned elements are not floats (its book class says so of
-- itself), and no layer below acts on a `columns-N` class, so the group
-- typesets as the contract's degradation floor: a vertical stack of panels
-- with their captions in source order, group caption last. The class stays on
-- the emitted options untouched - a hint decides arrangement, never content,
-- and the day Resilient grows a float or column mechanism it is still there.
local PANEL_CLASS = "unnumbered notoc"

function Renderer:figure_group (node)
  local content = {}
  for _, child in ipairs(node.children or {}) do
    local rendered
    if child.type == "figure" then
      rendered = self:figure(child, PANEL_CLASS)
    elseif child.type == "table" then
      rendered = self:table(child, PANEL_CLASS)
    else
      rendered = self:node(child)
    end
    if rendered ~= nil then content[#content + 1] = rendered end
  end
  -- Absent means uncaptioned, not empty: without a caption child, Resilient's
  -- captioned-figure numbers nothing and files nothing, which matches the
  -- engine - a group with no caption draws no number for itself or its panels.
  if node.caption then
    content[#content + 1] = createCommand("caption", {}, self:children(node, "caption"), pos(node))
  end
  return createStructuredCommand("markdown:internal:captioned-figure", attrs(node), content, pos(node))
end

function Renderer:citation_group (node)
  SU.warn("Carve citation group rendered as literal citation text")
  return createCommand("markdown:internal:span", attrs(node, "citation"), node.raw, pos(node))
end
function Renderer:smart_punctuation (node) return node.glyph or node.value end
function Renderer:caption_number (node) return tostring(node.n or "#") end
function Renderer:critic_comment (node) return createCommand("markdown:internal:span", { class = "critic-comment" }, node.text, pos(node)) end
function Renderer:substitution (node) return createCommand("markdown:internal:span", { class = "substitution", old = node.oldText }, node.newText, pos(node)) end
function Renderer:mention (node) return createCommand("markdown:internal:span", attrs(node, "mention"), "@" .. node.user, pos(node)) end
function Renderer:tag (node) return createCommand("markdown:internal:span", attrs(node, "tag"), "#" .. node.name, pos(node)) end
function Renderer:symbol (node) return createCommand("markdown:internal:symbol", { _symbol_ = node.name }, nil, pos(node)) end
function Renderer:abbreviation (node) return createCommand("markdown:internal:span", { title = node.expansion }, node.abbr, pos(node)) end
-- An inline extension carries its content as an array of nodes under
-- `content`, not as a string, so it needs converting like any other children
-- list. Handed to createCommand as-is, the records reach SILE.process, which
-- has nothing to do with them and drops the content on the floor.
function Renderer:inline_extension (node) return createCommand("markdown:internal:span", attrs(node, "extension " .. node.name), self:children(node, "content"), pos(node)) end

return Renderer
