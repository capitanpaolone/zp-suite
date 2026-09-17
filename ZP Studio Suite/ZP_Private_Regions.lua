-- @noindex
-- Private Regions v1: lane GUID -> owner plus optional immutable role.
-- No owner-specific semantics, colors or visual lane numbers in recognition.
local M = { SECTION = "ZP_PRIVATE_REGIONS_V1" }
local r = reaper

local function token(value)
  return type(value) == "string" and value:match("^[A-Z][A-Z0-9_]*$") ~= nil
end

function M.registry(proj)
  local result, roles, i = {}, {}, 0
  while true do
    local ok, key, owner = r.EnumProjExtState(proj, M.SECTION, i)
    if not ok then break end
    local guid = key:match("^lane:(.+)$")
    if guid and owner ~= "" then result[guid] = owner end
    local role_guid = key:match("^role:(.+)$")
    if role_guid and owner ~= "" then roles[role_guid] = owner end
    i = i + 1
  end
  return result, roles
end

function M.supported()
  return r.GetRegionOrMarker and r.GetRegionOrMarkerInfo_Value
    and r.GetSetProjectInfo_String and r.GetSetProjectInfo
end

function M.lane_guid(proj, lane)
  local ok, guid = r.GetSetProjectInfo_String(proj, "RULER_LANE_GUID:" .. lane, "", false)
  if ok and guid ~= "" then return guid end
end

function M.owner_at_index(proj, index, registry)
  registry = registry or M.registry(proj)
  if not next(registry) then return nil end
  -- Fail closed if a registered project is opened without the lane APIs.
  if not M.supported() then return "UNKNOWN" end
  local object = r.GetRegionOrMarker(proj, index, "")
  if not object then return "UNKNOWN" end
  local lane = r.GetRegionOrMarkerInfo_Value(proj, object, "I_LANENUMBER")
  local guid = M.lane_guid(proj, lane)
  if not guid then return "UNKNOWN" end
  return registry[guid]
end

function M.is_private(proj, index, registry)
  return M.owner_at_index(proj, index, registry) ~= nil
end

-- Register an empty lane only: never turn editorial content into private data.
function M.register_lane(proj, owner, lane, role)
  assert(role == nil or token(role), "Ruolo non valido")
  assert(token(owner), "Owner non valido")
  assert(M.supported(), "REAPER non supporta le Ruler Lane con GUID")
  local guid = assert(M.lane_guid(proj, lane), "GUID della lane non disponibile")
  local registry, roles = M.registry(proj)
  if registry[guid] == owner then
    assert(roles[guid] == role, "Ruolo della lane registrata incompatibile")
    return guid
  end
  assert(not roles[guid], "Registro ruolo orfano: ripristinare il progetto")
  assert(not registry[guid], "Lane gia appartenente a un altro owner")
  for i = 0, r.GetNumRegionsOrMarkers(proj) - 1 do
    local object = r.GetRegionOrMarker(proj, i, "")
    assert(r.GetRegionOrMarkerInfo_Value(proj, object, "I_LANENUMBER") ~= lane,
      "La lane contiene gia marker o regioni")
  end
  assert(r.SetProjExtState(proj, M.SECTION, "lane:" .. guid, owner) > 0,
    "Registrazione della lane fallita")
  if role then
    assert(r.SetProjExtState(proj, M.SECTION, "role:" .. guid, role) > 0,
      "Registrazione del ruolo fallita; ripristinare con Undo")
  end
  return guid
end

function M.ensure_lane(proj, owner, preferred_visual_lane, role)
  assert(role == nil or token(role), "Ruolo non valido")
  assert(token(owner), "Owner non valido")
  assert(M.supported() and r.GetNumRegionsOrMarkers, "API Ruler Lane non disponibili")
  local registry, roles = M.registry(proj)
  local owned
  for guid in pairs(roles) do
    assert(registry[guid], "Registro ruolo orfano: ripristinare il progetto")
  end
  for guid, value in pairs(registry) do
    if value == owner then
      assert(role == nil or token(roles[guid]),
        "Lane privata legacy senza ruolo: migrazione esplicita necessaria")
      if roles[guid] == role then
        assert(not owned, "Piu lane registrate per owner/ruolo: risolvere l'ambiguita")
        owned = guid
      end
    end
  end
  local count = r.GetSetProjectInfo(proj, "RULER_LANE_COUNT", 0, false)
  if owned then
    for lane = 0, count - 1 do
      if M.lane_guid(proj, lane) == owned then return lane, owned end
    end
    error("La Private Lane registrata non esiste piu: ripristinarla con Undo")
  end
  -- Append, never appropriate an existing lane (even an apparently empty one).
  local lane = math.max(count, (preferred_visual_lane or 1) - 1)
  r.GetSetProjectInfo(proj, "RULER_LANE_COUNT", lane + 1, true)
  assert(r.GetSetProjectInfo(proj, "RULER_LANE_COUNT", 0, false) == lane + 1,
    "Creazione della Ruler Lane fallita")
  local guid = M.register_lane(proj, owner, lane, role)
  r.GetSetProjectInfo_String(proj, "RULER_LANE_NAME:" .. lane, "ZP Private | " .. owner .. (role and " | " .. role or ""), true)
  return lane, guid
end

local function valid_range(start_pos, end_pos)
  return type(start_pos) == "number" and type(end_pos) == "number"
    and start_pos >= 0 and end_pos > start_pos and end_pos < math.huge
end

function M.create(proj, owner, kind, start_pos, end_pos, color, preferred_visual_lane, role)
  assert(token(kind), "Tipo non valido")
  assert(role == nil or kind == role, "Tipo incompatibile con il ruolo della lane")
  assert(valid_range(start_pos, end_pos), "Selezionare un intervallo temporale valido")
  assert(r.AddRegionOrMarker and r.SetRegionOrMarkerInfo_Value, "API regioni non disponibili")
  local lane = M.ensure_lane(proj, owner, preferred_visual_lane, role)
  local object = assert(r.AddRegionOrMarker(proj, true, start_pos, end_pos, kind, -1, color or 0),
    "Creazione della regione fallita")
  r.SetRegionOrMarkerInfo_Value(proj, object, "I_LANENUMBER", lane)
  if r.GetRegionOrMarkerInfo_Value(proj, object, "I_LANENUMBER") ~= lane then
    r.DeleteProjectMarker(proj, r.GetRegionOrMarkerInfo_Value(proj, object, "I_NUMBER"), true)
    error("Assegnazione alla Private Lane fallita; regione rimossa")
  end
  return object
end

local function owned_object(proj, owner, guid)
  assert(token(owner), "Owner non valido")
  local object = assert(r.GetRegionOrMarker(proj, -1, guid), "Regione non trovata")
  assert(r.GetRegionOrMarkerInfo_Value(proj, object, "B_ISREGION") ~= 0, "Non e una regione")
  local index = r.GetRegionOrMarkerInfo_Value(proj, object, "I_INDEX")
  assert(M.owner_at_index(proj, index) == owner, "Regione appartenente a un altro owner")
  return object
end

local function object_role(proj, object)
  local _, roles = M.registry(proj)
  return roles[M.lane_guid(proj, r.GetRegionOrMarkerInfo_Value(proj, object, "I_LANENUMBER"))]
end

function M.read(proj, owner, guid)
  local object = owned_object(proj, owner, guid)
  local _, name = r.GetSetRegionOrMarkerInfo_String(proj, object, "P_NAME", "", false)
  local role = object_role(proj, object)
  return { guid = guid, owner = owner, role = role,
    type = role or (token(name) and name or nil), name = name,
    start_pos = r.GetRegionOrMarkerInfo_Value(proj, object, "D_STARTPOS"),
    end_pos = r.GetRegionOrMarkerInfo_Value(proj, object, "D_ENDPOS") }
end

function M.update(proj, owner, guid, kind, start_pos, end_pos)
  assert(token(kind) and valid_range(start_pos, end_pos), "Tipo o intervallo non valido")
  local object = owned_object(proj, owner, guid)
  local role = object_role(proj, object)
  assert(role == nil or role == kind, "Tipo incompatibile con il ruolo della lane")
  r.SetRegionOrMarkerInfo_Value(proj, object, "D_STARTPOS", start_pos)
  r.SetRegionOrMarkerInfo_Value(proj, object, "D_ENDPOS", end_pos)
  assert(r.GetSetRegionOrMarkerInfo_String(proj, object, "P_NAME", kind, true), "Rinomina fallita")
end

function M.delete(proj, owner, guid)
  local object = owned_object(proj, owner, guid)
  return r.DeleteProjectMarker(proj, r.GetRegionOrMarkerInfo_Value(proj, object, "I_NUMBER"), true)
end

function M.has_private_regions(proj)
  local registry = M.registry(proj)
  if not next(registry) then return false end
  local _, markers, regions = r.CountProjectMarkers(proj)
  for i = 0, markers + regions - 1 do
    local ok, is_region = r.EnumProjectMarkers3(proj, i)
    if ok ~= 0 and is_region and M.is_private(proj, i, registry) then return true end
  end
  return false
end

-- Native selected-regions render: never delete/recreate private regions to filter.
function M.select_render_regions(proj, numbers)
  assert(M.supported() and r.SetRegionOrMarkerInfo_Value, "Selezione regioni non disponibile")
  local registry, selected = M.registry(proj), 0
  for i = 0, r.GetNumRegionsOrMarkers(proj) - 1 do
    local object = r.GetRegionOrMarker(proj, i, "")
    if r.GetRegionOrMarkerInfo_Value(proj, object, "B_ISREGION") ~= 0 then
      local number = r.GetRegionOrMarkerInfo_Value(proj, object, "I_NUMBER")
      local value = numbers[number] and not M.is_private(proj, i, registry) and 1 or 0
      r.SetRegionOrMarkerInfo_Value(proj, object, "B_UISEL", value)
      assert(r.GetRegionOrMarkerInfo_Value(proj, object, "B_UISEL") == value,
        "Selezione render non verificata")
      selected = selected + value
    end
  end
  assert(selected > 0, "Nessuna regione editoriale selezionata")
  r.GetSetProjectInfo(proj, "RENDER_BOUNDSFLAG", 5, true)
  return selected
end

return M
