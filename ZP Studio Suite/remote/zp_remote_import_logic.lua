-- @noindex

-- Pure planning rules for the ZP Remote REAPER importer. No reaper.* calls.
local M = {}

local function text(v)
  if type(v) ~= "string" then return "" end
  return v:match("^%s*(.-)%s*$")
end

function M.normalize_name(value)
  local s = text(value):lower()
  s = s:gsub("[%s_%-]+", " ")
  return s
end

function M.canonico(value, kind)
  if kind ~= "prj" and kind ~= "pers" then return nil end
  local id = text(value)
  local prefix, rest = id:match("^([%a]+)%-(.*)$")
  if prefix then
    if prefix:lower() ~= kind then return nil end
    id = rest
  elseif id:sub(1,1) == "{" and id:sub(-1) == "}" then
    id = id:sub(2,-2)
  end
  id = id:gsub("-", ""):lower()
  if #id ~= 32 or id:find("[^0-9a-f]") then return nil end
  return kind .. "-" .. id:sub(1,8) .. "-" .. id:sub(9,12) .. "-" .. id:sub(13,16) .. "-" .. id:sub(17,20) .. "-" .. id:sub(21,32)
end

local function char_key(file)
  local raw = text(file.character_id)
  if raw ~= "" then return "id:" .. M.canonico(raw, "pers"), false end
  return "name:" .. M.normalize_name(file.character), true
end

function M.validate(plan)
  if type(plan) ~= "table" or type(plan.files) ~= "table" or type(plan.counts) ~= "table" then
    return false, "Piano senza files/counts."
  end
  local project_id = M.canonico(plan.project_guid, "prj")
  if plan.project_guid and not project_id then return false, "project_guid non valido o di tipo diverso." end
  if plan.project_id and M.canonico(plan.project_id, "prj") ~= project_id then return false, "project.id non corrisponde a project_guid." end
  if plan.delivery_project_id and M.canonico(plan.delivery_project_id, "prj") ~= M.canonico(plan.delivery_guid, "prj") then return false, "ID canonico consegna non coerente." end
  local files, items, p, a, outside = 0, 0, 0, 0, 0
  local characters = {}
  for _, file in ipairs(plan.files) do
    files = files + 1
    if file.role == "P" or file.role == "A" then
      if file.role == "P" then p = p + 1 else a = a + 1 end
      local id, name = text(file.character_id), text(file.character)
      if id ~= "" and not M.canonico(id, "pers") then return false, "character_id non valido o di tipo diverso: " .. tostring(file.file) end
      if id ~= "" then id = M.canonico(id, "pers"); file.character_id = id end
      if id == "" and name == "" and #(file.items or {}) > 0 then return false, "Personaggio assente: " .. tostring(file.file) end
      local n = #(file.items or {})
      if n > 0 then
        if id ~= "" then characters["characters_by_id|" .. id] = (characters["characters_by_id|" .. id] or 0) + n end
        if name ~= "" then characters["characters|" .. name] = (characters["characters|" .. name] or 0) + n end
      end
    elseif file.role == "fuori_traccia" then
      outside = outside + 1
    else
      return false, "Ruolo non supportato nel piano: " .. tostring(file.role)
    end
    for _, item in ipairs(file.items or {}) do
      items = items + 1
      if type(item.position_s) ~= "number" or type(item.source_offset_s) ~= "number"
        or type(item.length_s) ~= "number" or item.length_s <= 0 then
        return false, "Item con coordinate non valide: " .. tostring(file.file)
      end
    end
  end
  local counts = plan.counts
  if counts.files ~= files or counts.items ~= items or counts.P ~= p or (counts.A or 0) ~= a or counts.fuori_traccia ~= outside then
    return false, "Conteggi dichiarati diversi dal contenuto del piano."
  end
  local seen_by_table = {characters=0,characters_by_id=0}
  for composite, count in pairs(characters) do
    local table_key, key = composite:match("^([%w_]+)|(.*)$")
    local declared = counts[table_key] or {}
    if declared[key] ~= count then return false, "Conteggio personaggio incoerente: " .. tostring(key) end
    seen_by_table[table_key] = seen_by_table[table_key] + 1
  end
  for _, table_key in ipairs({"characters","characters_by_id"}) do
    local declared_keys = 0
    for _ in pairs(counts[table_key] or {}) do declared_keys = declared_keys + 1 end
    if declared_keys ~= seen_by_table[table_key] then return false, "Conteggi personaggio non coerenti nel piano." end
  end
  return true
end


function M.project_identity(delivery_id, project_id)
  local incoming = M.canonico(delivery_id, "prj")
  local current = text(project_id) ~= "" and M.canonico(project_id, "prj") or nil
  if not incoming then return nil, "ID progetto della consegna non valido o di tipo diverso." end
  if text(project_id) ~= "" and not current then return nil, "ID progetto REAPER non valido o di tipo diverso." end
  if not current then return "assign" end
  if current == incoming then return "match" end
  return nil, "ID progetto diverso dalla consegna: import bloccato."
end

function M.validate_source_hashes(plan, observed)
  observed = observed or {}
  for _, file in ipairs(plan.files or {}) do
    local actual = observed[file.file]
    if not actual then return false, "WAV mancante: " .. tostring(file.file) end
    if tostring(actual):lower() ~= tostring(file.sha256 or ""):lower() then
      return false, "SHA-256 non coerente: " .. tostring(file.file)
    end
  end
  return true
end

-- plan.cues is built after all input hashes and files have been checked.
-- state.items records every imported item as {key, hash, legacy_key, character_key, lane}.
function M.decide(plan, state)
  local ok, err = M.validate(plan)
  if not ok then return nil, err end
  state = state or {}
  local project = M.canonico(plan.project_guid, "prj")
  local region = text(plan.region and plan.region.guid)
  if not project or region == "" then return nil, "Manca l'identità stabile del progetto o della regione." end

  local old_items = state.items or {}
  local used_keys, used_lanes = {}, {}
  local tracks = state.characters or {}
  for _, item in ipairs(old_items) do
    if item.key and item.key ~= "" then
      local list = used_keys[item.key] or {}
      list[#list + 1] = item
      used_keys[item.key] = list
      if item.key and type(item.lane) == "number" then
        used_lanes[item.key] = used_lanes[item.key] or {}
        used_lanes[item.key][item.lane] = true
      end
    end
  end

  local actions, current_keys, new_chars, upgrades = {}, {}, {}, {}
  local added, unchanged, replaced, legacy_fallbacks = 0, 0, 0, 0
  for _, cue in ipairs(plan.cues or {}) do
    local file, item = cue.file, cue.item
    local ck, legacy = char_key(file)
    if legacy then legacy_fallbacks = legacy_fallbacks + 1 end
    local ring = text(item.ring_id or file.ring_id)
    local version = text(item.take_version or file.take_version)
    local base
    if ring ~= "" then
      base = table.concat({project, region, ring, version ~= "" and version or "1"}, "|")
    else
      -- Old deliveries have no ring/version. Keep stable filename and cue ordinal.
      base = table.concat({project, region, "legacy", M.normalize_name(file.file), tostring(item.item_index)}, "|")
    end
    local key = base .. "|" .. tostring(item.item_index)
    current_keys[key] = true

    local track = tracks[ck]
    if not track then
      local label_key = "name:" .. M.normalize_name(file.character)
      track = tracks[label_key]
      if track and not legacy then upgrades[ck] = {track=track,character_id=file.character_id,name=file.character} end
      if not track then
        new_chars[ck] = new_chars[ck] or {key=ck, character_id=legacy and nil or file.character_id, name=file.character or file.file, legacy=legacy}
      end
    end

    local matching
    for _, old in ipairs(used_keys[key] or {}) do
      if old.hash == file.sha256 then matching = old; break end
    end
    if not matching and cue.legacy_key then
      for _, old in ipairs(old_items) do
        if old.legacy_key == cue.legacy_key and old.hash == file.sha256 then matching = old; break end
      end
    end
    local lane
    if matching then
      lane = matching.lane
      unchanged = unchanged + 1
      actions[#actions + 1] = {kind="unchanged", key=key, hash=file.sha256, character_key=ck, lane=lane, file=file.file, role=file.role}
    else
      local is_replacement = #(used_keys[key] or {}) > 0
      local requested = tonumber(item.lane_index)
      if requested and requested >= 0 and not ((used_lanes[key] or {})[requested]) then lane = requested end
      if lane == nil then
        lane = 0
        while (used_lanes[key] or {})[lane] do lane = lane + 1 end
      end
      used_lanes[key] = used_lanes[key] or {}
      used_lanes[key][lane] = true
      if is_replacement then
        replaced = replaced + 1
        actions[#actions + 1] = {kind="replace", key=key, hash=file.sha256, character_key=ck, lane=lane, file=file.file, role=file.role}
      else
        added = added + 1
        actions[#actions + 1] = {kind="add", key=key, hash=file.sha256, character_key=ck, lane=lane, file=file.file, role=file.role}
      end
    end
  end

  local archived = {}
  for _, old in ipairs(old_items) do
    if old.key and old.key:sub(1, #project + #region + 2) == project .. "|" .. region .. "|"
      and not current_keys[old.key] then
      archived[#archived + 1] = {key=old.key, hash=old.hash, file=old.file, character_key=old.character_key}
    end
  end
  return {
    actions=actions, new_characters=new_chars, upgraded_characters=upgrades, archived=archived,
    added=added, unchanged=unchanged, replaced=replaced,
    legacy_fallbacks=legacy_fallbacks, total=#actions
  }
end

return M
