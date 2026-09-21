-- Plain tables to Lua source and back, for the Rounds records file. Loaded in
-- an empty environment, the same way a company save is, so it is only data.
local IO = {}

local function encode(value)
  local kind = type(value)
  if kind == "number" or kind == "boolean" then return tostring(value) end
  if kind == "string" then return string.format("%q", value) end
  assert(kind == "table", "unsupported value")
  local out = { "{" }
  for key, item in pairs(value) do
    if type(item) ~= "function" then out[#out + 1] = "[" .. encode(key) .. "]=" .. encode(item) .. "," end
  end
  out[#out + 1] = "}"
  return table.concat(out)
end

function IO.encode(value) return "return " .. encode(value) .. "\n" end

function IO.decode(text)
  if type(text) ~= "string" then return nil end
  local chunk
  if loadstring then
    chunk = loadstring(text, "rounds records")
    if chunk then setfenv(chunk, {}) end
  else
    chunk = load(text, "rounds records", "t", {})
  end
  if not chunk then return nil end
  local ok, data = pcall(chunk)
  return ok and type(data) == "table" and data or nil
end

return IO
