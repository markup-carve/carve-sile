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

local function readFile (filename)
  local handle = io.open(filename, "rb")
  if not handle then return nil end
  local content = handle:read("*a")
  handle:close()
  return content
end

local function isAbsolute (path)
  return type(path) == "string" and (path:match("^/") ~= nil or path:match("^[A-Za-z]:[\\/]") ~= nil)
end

local function sanitizePath (value, path, replacement)
  if not value or not path or path == "/" then return value end
  local pattern = path:gsub("([^%w])", "%%%1")
  value = value:gsub(pattern .. "/", replacement .. "/")
  return value:gsub(pattern .. "([:%s])", replacement .. "%1")
end

function bridge.convert (source, options)
  options = options or {}
  local converter = options.converter or "carve"
  local requestedSourceName = options.source_path
  local includeRoot = options.include_root
  if requestedSourceName and not isAbsolute(requestedSourceName) then
    return nil, "Carve source_path must be absolute"
  end
  if includeRoot and not isAbsolute(includeRoot) then
    return nil, "Carve include_root must be absolute"
  end

  if requestedSourceName and not includeRoot then
    includeRoot = pl.path.dirname(requestedSourceName)
  end

  -- SILE may preprocess a file before passing its source to an inputter. Only
  -- let the CLI reopen source_path when its bytes still match that source.
  local sourceName = requestedSourceName
  if sourceName and readFile(sourceName) ~= source then
    return nil, "Carve source_path content differs from the source supplied by SILE"
  end
  local temporary = sourceName == nil
  if temporary then
    sourceName = os.tmpname()
    local ok, err = writeFile(sourceName, source)
    if not ok then
      return nil, "cannot create temporary Carve input: " .. tostring(err)
    end
  end

  local command = shellQuote(converter)
  if temporary and includeRoot then
    command = command .. " --include-root " .. shellQuote(includeRoot) .. " --json < " .. shellQuote(sourceName)
  else
    command = command .. " " .. shellQuote(sourceName)
    if includeRoot then command = command .. " --include-root " .. shellQuote(includeRoot) end
    if temporary then command = command .. " --no-includes" end
    command = command .. " --json"
  end
  local success, code, stdout, stderr = pl.utils.executeex(command)
  if temporary then os.remove(sourceName) end
  stderr = sanitizePath(stderr, includeRoot, "[include-root]")
  if temporary then stderr = sanitizePath(stderr, sourceName, "[temporary-input]") end

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
  return stdout, nil, stderr
end

return bridge
