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

function bridge.convert (source, options)
  options = options or {}
  local converter = options.converter or "carve"
  local sourceName = os.tmpname()
  local ok, err = writeFile(sourceName, source)
  if not ok then
    return nil, "cannot create temporary Carve input: " .. tostring(err)
  end

  local command = shellQuote(converter) .. " " .. shellQuote(sourceName) .. " --json"
  local success, code, stdout, stderr = pl.utils.executeex(command)
  os.remove(sourceName)

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
