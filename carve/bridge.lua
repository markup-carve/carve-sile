--- Convert Carve source to Pandoc JSON through the pandoc-carve CLI.

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

function bridge.convert (source, options)
  options = options or {}
  local converter = options.converter or "pandoc-carve"
  local sourceName = os.tmpname()
  local ok, err = writeFile(sourceName, source)
  if not ok then
    return nil, "cannot create temporary Carve input: " .. tostring(err)
  end

  local command = shellQuote(converter) .. " " .. shellQuote(sourceName) .. " -t json"
  local success, code, stdout, stderr = pl.utils.executeex(command)
  os.remove(sourceName)

  if not success then
    local detail = stderr and stderr:gsub("%s+$", "") or ""
    if detail == "" then
      detail = "exit status " .. tostring(code)
    end
    return nil, "pandoc-carve failed: " .. detail
  end
  if not stdout or stdout:match("^%s*$") then
    return nil, "pandoc-carve produced no Pandoc JSON"
  end
  return stdout, nil, stderr
end

return bridge
