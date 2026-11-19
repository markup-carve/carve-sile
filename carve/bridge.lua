--- Parse Carve source into the Carve 0.2 tree (AST contract 2.0) as JSON.

local bridge = {}

local function shellQuote (value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function writeFile (filename, content)
  local handle, err = io.open(filename, "wb")
  if not handle then
    return nil, err
  end
  local ok, writeErr = handle:write(content)
  handle:close()
  if not ok then
    return nil, writeErr
  end
  return true
end

local windows = package.config:sub(1, 1) == "\\"

-- A drive path is relative to a POSIX CLI, which would resolve it against the
-- working directory.
local function isAbsolute (path)
  return path:match("^/") ~= nil or (windows and path:match("^[A-Za-z]:[\\/]") ~= nil)
end

--- The directory with symlinks resolved, which is how the CLI names files.
local function realDirectory (dir)
  local lfs = require("lfs")
  local here = lfs.currentdir()
  if not lfs.chdir(dir) then return nil end
  local real = lfs.currentdir()
  lfs.chdir(here)
  return real
end

--- Strip the include root from CLI output so warnings name files below it.
local function relativeToRoot (text, root)
  if not text or not root then return text end
  for _, prefix in ipairs({ realDirectory(root), pl.path.abspath(root) }) do
    if prefix and prefix ~= "/" then
      text = pl.stringx.replace(text, prefix .. "/", "")
    end
  end
  return text
end

local function jsonDecoder ()
  local hasJson, decoder = pcall(require, "json.decode")
  if not hasJson then hasJson, decoder = pcall(require, "lunajson") end
  return hasJson and decoder or nil
end

--- The include report of `carve ast --report-includes`, as the inputter reads
-- it: one entry per directive, `id` the absolute path of a file that was read.
-- The CLI names files by their id below the include root (C2-N-007).
local function readDependencies (reportName, root)
  local handle = io.open(reportName, "rb")
  if not handle then return {}, "Carve parser produced no include dependency report" end
  local report = handle:read("*a")
  handle:close()
  local decoder = jsonDecoder()
  if not decoder then return {}, "The Carve bridge requires luajson or lunajson for include dependency reports" end
  local ok, decoded = pcall(decoder.decode, report)
  if not ok or type(decoded) ~= "table" or type(decoded.files) ~= "table" then
    return {}, "Carve parser produced an invalid include dependency report"
  end
  local dependencies = {}
  for _, file in ipairs(decoded.files) do
    for _, dependency in ipairs(type(file.dependencies) == "table" and file.dependencies or {}) do
      local id
      if type(dependency.file) == "string" then
        id = pl.path.normpath(pl.path.join(root, dependency.file))
      elseif type(dependency.path) == "string" then
        local from = type(dependency.from) == "string" and pl.path.dirname(dependency.from) or ""
        id = pl.path.normpath(pl.path.join(root, from, dependency.path))
      end
      dependencies[#dependencies + 1] = { id = id, path = dependency.path, resolved = dependency.read == true }
    end
  end
  return dependencies
end

--- Convert Carve source to its tree as JSON.
--
-- options.converter     CLI executable, default "carve"
-- options.source_path   the file `source` was read from; relative directives
--                       resolve against it. Without one the source goes over
--                       stdin and has no directory of its own.
-- options.include_root  absolute containment root; default the source file's
--                       directory, and none for source without a file
-- options.includes      false leaves directives literal
--
-- Returns the JSON text, an error, the warnings and the include dependencies.
function bridge.convert (source, options)
  options = options or {}
  local converter = options.converter or "carve"
  local sourcePath = options.source_path
  local root = options.include_root

  -- The CLI resolves a relative root against the working directory, which is
  -- not a root anyone chose, so it must not get that far.
  if root ~= nil and (type(root) ~= "string" or not isAbsolute(root)) then
    return nil, "Carve include_root must be an absolute path: " .. tostring(root)
  end

  local hasDirective = source:find("{{", 1, true) ~= nil
  local includesOn = options.includes ~= false and (root ~= nil or (sourcePath ~= nil and hasDirective))
  -- The CLI expands the includes of a named file, so source whose directives
  -- must stay literal goes over stdin, which has no directory to resolve against.
  local fromFile = sourcePath ~= nil and options.includes ~= false

  local flags = ""
  local reportName
  if includesOn then
    flags = " --includes"
    if root ~= nil then flags = flags .. " --include-root " .. shellQuote(root) end
    reportName = os.tmpname()
  end
  local input, stdinName
  if fromFile then
    input = " " .. shellQuote(sourcePath)
  else
    stdinName = os.tmpname()
    local ok, err = writeFile(stdinName, source)
    if not ok then
      return nil, "cannot create temporary Carve input: " .. tostring(err)
    end
    input = " < " .. shellQuote(stdinName)
  end

  local command = shellQuote(converter) .. " ast" .. flags
  if reportName then command = command .. " --report-includes " .. shellQuote(reportName) end
  local success, code, stdout, stderr = pl.utils.executeex(command .. input)

  -- `carve ast` prints the tree only; the include warnings come from
  -- `carve diagnostics`, which parses with the same flags.
  local warnings = stderr or ""
  if success and includesOn and hasDirective then
    local _, _, diagnostics = pl.utils.executeex(shellQuote(converter) .. " diagnostics" .. flags .. input)
    for line in (diagnostics or ""):gmatch("[^\n]+") do
      if line:find(" include%-") then warnings = warnings .. line .. "\n" end
    end
  end
  if stdinName then os.remove(stdinName) end

  local dependencies, reportError = {}, nil
  local base = root or (sourcePath and pl.path.dirname(pl.path.abspath(sourcePath)))
  if reportName then
    if success and base then dependencies, reportError = readDependencies(reportName, pl.path.abspath(base)) end
    os.remove(reportName)
  end
  warnings = relativeToRoot(warnings, base)
  if reportError then
    warnings = warnings .. reportError .. "\n"
  end

  if not success then
    local detail = warnings:gsub("%s+$", "")
    if detail == "" then
      detail = "exit status " .. tostring(code)
    end
    return nil, "Carve parser failed: " .. detail
  end
  if not stdout or stdout:match("^%s*$") then
    return nil, "Carve parser produced no tree"
  end
  return stdout, nil, warnings, dependencies
end

return bridge
