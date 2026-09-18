--- Parse Carve source into its normative exchange JSON AST.

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

local supportCache = {}

local function helpText (converter)
  if supportCache[converter] == nil then
    local _, _, stdout, stderr = pl.utils.executeex(shellQuote(converter) .. " --help")
    supportCache[converter] = (stdout or "") .. (stderr or "")
  end
  return supportCache[converter]
end

--- Whether the converter's CLI knows --include-root. Published
-- @markup-carve/carve 0.1.6 does not, and refuses the flag outright.
function bridge.supportsIncludes (converter)
  return helpText(converter):find("--include-root", 1, true) ~= nil
end

--- Whether the converter can publish include dependency identities.
function bridge.supportsIncludeReport (converter)
  return helpText(converter):find("--report-includes", 1, true) ~= nil
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

--- Convert Carve source to exchange JSON.
--
-- options.converter     CLI executable, default "carve"
-- options.source_path   the file `source` was read from; relative directives
--                       resolve against it. Without one the source goes over
--                       stdin and has no directory of its own.
-- options.include_root  absolute containment root; default the source file's
--                       directory, and none for source without a file
-- options.includes      false leaves directives literal
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
  -- Stdin has no directory, so only a file needs --no-includes to stay literal.
  local needsNoIncludes = options.includes == false and sourcePath ~= nil and hasDirective
  local supported = (includesOn or needsNoIncludes) and bridge.supportsIncludes(converter)
  local warning
  if includesOn and not supported then
    if root ~= nil then
      return nil, "Carve include_root cannot be used: " .. converter .. " has no include support"
    end
    warning = "include directives left literal: " .. converter .. " has no include support"
  end

  local command = shellQuote(converter)
  local stdinName
  if sourcePath then
    command = command .. " " .. shellQuote(sourcePath)
  else
    stdinName = os.tmpname()
    local ok, err = writeFile(stdinName, source)
    if not ok then
      return nil, "cannot create temporary Carve input: " .. tostring(err)
    end
  end
  command = command .. " --json"
  if supported and needsNoIncludes then
    command = command .. " --no-includes"
  elseif supported and includesOn and root ~= nil then
    command = command .. " --include-root " .. shellQuote(root)
  end
  local reportName
  if supported and includesOn and bridge.supportsIncludeReport(converter) then
    reportName = os.tmpname()
    command = command .. " --report-includes " .. shellQuote(reportName)
  end
  if stdinName then
    command = command .. " < " .. shellQuote(stdinName)
  end

  local success, code, stdout, stderr = pl.utils.executeex(command)
  if stdinName then os.remove(stdinName) end
  local dependencies = {}
  local reportError
  if reportName then
    local handle = io.open(reportName, "rb")
    if handle then
      local report = handle:read("*a")
      handle:close()
      local hasJson, decoder = pcall(require, "json.decode")
      if not hasJson then hasJson, decoder = pcall(require, "lunajson") end
      if hasJson then
        local ok, decoded = pcall(decoder.decode, report)
        if ok and type(decoded) == "table" and type(decoded.dependencies) == "table" then
          dependencies = decoded.dependencies
        else
          reportError = "Carve parser produced an invalid include dependency report"
        end
      else
        reportError = "The Carve bridge requires luajson or lunajson for include dependency reports"
      end
    else
      reportError = "Carve parser produced no include dependency report"
    end
    os.remove(reportName)
  end
  stderr = relativeToRoot(stderr, root or (sourcePath and pl.path.dirname(sourcePath)))
  if warning then
    stderr = warning .. "\n" .. (stderr or "")
  end
  if reportError then
    stderr = (stderr or "") .. reportError .. "\n"
  end

  if not success then
    local detail = stderr and stderr:gsub("%s+$", "") or ""
    if detail == "" then
      detail = "exit status " .. tostring(code)
    end
    return nil, "Carve parser failed: " .. detail
  end
  if not stdout or stdout:match("^%s*$") then
    return nil, "Carve parser produced no exchange AST"
  end
  return stdout, nil, stderr, dependencies
end

return bridge
