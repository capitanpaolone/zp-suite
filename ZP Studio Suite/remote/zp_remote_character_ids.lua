-- @noindex

-- Pure ID registry rules for persistent REAPER characters. No reaper.* calls.
local M = {}

local function trim(value)
  return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

function M.canonical(value)
  local id = trim(value)
  local prefix, rest = id:match("^([%a]+)%-(.*)$")
  if prefix then
    if prefix:lower() ~= "pers" then return nil end
    id = rest
  elseif id:sub(1,1) == "{" and id:sub(-1) == "}" then
    id = id:sub(2,-2)
  end
  id = id:gsub("-", ""):lower()
  if #id ~= 32 or id:find("[^0-9a-f]") then return nil end
  return "pers-" .. id:sub(1,8) .. "-" .. id:sub(9,12) .. "-" .. id:sub(13,16) .. "-" .. id:sub(17,20) .. "-" .. id:sub(21,32)
end

local function quote(value)
  return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(c)
    local map = {['"']='\\\"', ['\\']='\\\\', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t'}
    return map[c] or ("\\u%04x"):format(c:byte())
  end) .. '"'
end

local function encode_map(map)
  local keys = {}; for key in pairs(map or {}) do keys[#keys+1] = key end
  table.sort(keys)
  local values = {}
  for _, key in ipairs(keys) do values[#values+1] = quote(key) .. ":" .. quote(map[key]) end
  return "{" .. table.concat(values, ",") .. "}"
end

function M.encode(registry)
  return '{"version":1,"by_marker":' .. encode_map(registry.by_marker) .. ',"by_name":' .. encode_map(registry.by_name) .. '}'
end

local function name_key(value)
  return trim(value):upper():gsub("[^A-Z0-9]", "")
end

local function marker_key(value)
  return trim(value):gsub("[{}%-]", ""):lower()
end

function M.reconcile(markers_by_name, registry, generate)
  registry = type(registry) == "table" and registry or {}
  registry.version = 1
  registry.by_marker = type(registry.by_marker) == "table" and registry.by_marker or {}
  registry.by_name = type(registry.by_name) == "table" and registry.by_name or {}
  if type(generate) ~= "function" then return nil, false, "Generatore ID non disponibile." end
  local changed, assigned = false, {}
  for name, markers in pairs(markers_by_name or {}) do
    local nk = name_key(name)
    local selected
    local saved_name = registry.by_name[nk]
    if saved_name then
      selected = M.canonical(saved_name)
      if not selected then return nil, false, "ID personaggio non valido per " .. tostring(name) .. "." end
    else
      local ids = {}
      for _, guid in ipairs(markers or {}) do
        local key = marker_key(guid)
        local saved = key ~= "" and registry.by_marker[key] or nil
        if saved then
          local id = M.canonical(saved)
          if not id then return nil, false, "ID marker non valido per " .. tostring(name) .. "." end
          ids[id] = true
        end
      end
      local count = 0
      for id in pairs(ids) do selected, count = id, count + 1 end
      if count > 1 then return nil, false, "Il personaggio " .. tostring(name) .. " è collegato a più ID." end
      if not selected then
        selected = M.canonical(generate())
        if not selected then return nil, false, "Non riesco a generare un ID valido per " .. tostring(name) .. "." end
        changed = true
      end
    end
    if assigned[selected] and assigned[selected] ~= name then return nil, false, "Lo stesso ID personaggio è assegnato a più nomi." end
    assigned[selected] = name
    if registry.by_name[nk] ~= selected then registry.by_name[nk] = selected; changed = true end
    for _, guid in ipairs(markers or {}) do
      local key = marker_key(guid)
      if key ~= "" and registry.by_marker[key] ~= selected then registry.by_marker[key] = selected; changed = true end
    end
  end
  return registry, changed
end

return M
