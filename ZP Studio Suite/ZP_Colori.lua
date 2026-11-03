-- @noindex

-- ZP Studio Suite for REAPER
-- ZP Colori: la logica dietro la toolbar "ZP Colori" (clicca e colora).
-- Ogni pulsante della toolbar e' un piccolo script in colori/ che legge dal proprio nome
-- cosa fare: ZP_Colori_07_Blu.lua = colore 7, ZP_Colori_Modo_Item.lua = modo, ZP_Colori_Togli.lua.
--
-- Si sceglie un modo, poi gli oggetti, infine un colore. Un solo modo resta acceso.
-- Auto applica il colore agli item, marker e regioni selezionati al momento del clic.
--   Item    = colora gli item selezionati (anche i take che hanno un colore loro).
--   Traccia = colora le tracce selezionate; gli item con un colore loro lo tengono.
--   Tutto   = colora le tracce selezionate e tutti gli item che ci stanno dentro.
--   Marker / Regione = colora solo i marker o le regioni selezionati nell'arrangiamento.
-- Senza tracce selezionate, Traccia e Tutto usano le tracce degli item selezionati.
-- Il modo resta salvato (ExtState ZP_COLORI/modo); di serie Auto.
-- Palette: la "Versione Saturata" di Paolo (16 colori SWS) + bianco, nero, grigio e rosso acceso.

local M = {}

M.SECTION = "ZP_COLORI"
M.MODES = { "auto", "item", "traccia", "tutto", "marker", "regione" }
M.MODE_FILES = {
  item = "ZP_Colori_Modo_Item.lua", traccia = "ZP_Colori_Modo_Traccia.lua",
  tutto = "ZP_Colori_Modo_Tutto.lua", marker = "ZP_Colori_Modo_Marker.lua",
  regione = "ZP_Colori_Modo_Regione.lua",
}
M.MODE_NAMES = { auto = "Auto", item = "Item", traccia = "Traccia", tutto = "Tutto", marker = "Marker", regione = "Regione" }
M.AUTO_KEY = "autocolor"

M.PALETTE = {
  { "Verde lime", 0x9e, 0xea, 0x64 }, { "Crema", 0xe2, 0xe0, 0x93 },
  { "Arancio", 0xec, 0xac, 0x6b }, { "Rosa", 0xe6, 0x86, 0xb2 },
  { "Lilla", 0xd3, 0x8c, 0xe6 }, { "Viola", 0x6f, 0x6a, 0xee },
  { "Blu", 0x4a, 0x79, 0xf4 }, { "Azzurro", 0x6c, 0xcc, 0xed },
  { "Acqua", 0x81, 0xe5, 0xbd }, { "Verde", 0x7f, 0xe5, 0x7d },
  { "Giallo", 0xeb, 0xd4, 0x6e }, { "Salmone", 0xe9, 0x95, 0x77 },
  { "Glicine", 0xca, 0xa6, 0xe0 }, { "Celeste", 0x70, 0xc1, 0xec },
  { "Turchese", 0x7d, 0xe6, 0xd8 }, { "Salvia", 0xc5, 0xdf, 0x9c },
  { "Bianco", 0xff, 0xff, 0xff }, { "Nero", 0x00, 0x00, 0x00 },
  { "Grigio", 0x80, 0x80, 0x80 }, { "Rosso", 0xff, 0x1a, 0x1a },
}

---------------------------------------------------------------------------
-- LOGICA PURA (collaudabile con lua fuori da REAPER)
---------------------------------------------------------------------------

-- Nome dello script del colore n: ZP_Colori_07_Blu.lua
function M.color_file(n)
  local p = M.PALETTE[n]
  return p and string.format("ZP_Colori_%02d_%s.lua", n, (p[1]:gsub(" ", "_"))) or nil
end

-- Dal nome del file del pulsante a cosa fare: "colore", n | "modo", "item" | "togli" | nil
function M.parse_button(path)
  local name = tostring(path or ""):match("([^/\\]+)$") or ""
  local mode = name:match("^ZP_Colori_Modo_(%a+)%.lua$")
  if mode then
    mode = mode:lower()
    if M.MODE_FILES[mode] then return "modo", mode end
    return nil
  end
  if name == "ZP_Colori_Togli.lua" then return "togli" end
  if name == "ZP_Colori_Auto.lua" then return "auto" end
  local n = tonumber(name:match("^ZP_Colori_(%d%d)_"))
  if n and M.PALETTE[n] then return "colore", n end
  return nil
end

function M.valid_mode(m)
  return (m == "auto" or M.MODE_FILES[m]) and m or "auto"
end

-- Dal testo di reaper-kb.ini: selettore -> "_RS..." (sezione principale).
function M.mode_ids_from_kb(kb_text)
  local out = {}
  for line in (tostring(kb_text or "") .. "\n"):gmatch("([^\n]*)\n") do
    local id, rest = line:match('^SCR%s+%d+%s+0%s+(RS%x+)%s+"[^"]*"%s+(.-)%s*$')
    if id then
      local base = (rest:match('^"(.*)"$') or rest):match("([^/\\]+)$")
      for mode, file in pairs(M.MODE_FILES) do
        if base == file and not out[mode] then out[mode] = "_" .. id end
      end
      if base == "ZP_Colori_Auto.lua" and not out.auto then out.auto = "_" .. id end
    end
  end
  return out
end

if not reaper then return M end

---------------------------------------------------------------------------
-- PARTE REAPER
---------------------------------------------------------------------------

local Lingua
pcall(function()
  local here = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
  Lingua = dofile(here .. "ZP_Lingua.lua")
end)
local function T(s)
  if Lingua and Lingua.T then return Lingua.T(s) end
  return _G.T and _G.T(s) or s
end

-- M.notify(msg, ok): se c'e' (finestra 35 ZP Colori) i messaggi vanno li' invece che nel tooltip.
local function say(msg)
  if reaper.osara_outputMessage then reaper.osara_outputMessage(msg) end
  if M.notify then M.notify(msg, true) end
end

-- Avviso breve vicino al mouse (e a voce con OSARA); sparisce da solo dopo 2 secondi.
local function warn(msg)
  if M.notify then
    if reaper.osara_outputMessage then reaper.osara_outputMessage(msg) end
    return M.notify(msg, false)
  end
  say(msg)
  local x, y = reaper.GetMousePosition()
  reaper.TrackCtl_SetToolTip(msg, x + 12, y + 12, true)
  if reaper.set_action_options then reaper.set_action_options(1) end -- un clic nuovo chiude questo
  local t0 = reaper.time_precise()
  local function wait()
    if reaper.time_precise() - t0 < 2 then reaper.defer(wait) else reaper.TrackCtl_SetToolTip("", 0, 0, false) end
  end
  reaper.defer(wait)
end

function M.get_mode()
  -- La vecchia AutoColor poteva lasciare un monitor attivo e un modo Item salvato.
  -- Migrazione una sola volta: il nuovo Auto e' un selettore, non un monitor.
  if reaper.GetExtState(M.SECTION, "selector_version") ~= "2" then
    reaper.SetExtState(M.SECTION, "modo", "auto", true)
    reaper.SetExtState(M.SECTION, "selector_version", "2", true)
    reaper.SetExtState(M.SECTION, M.AUTO_KEY, "0", false)
    reaper.SetExtState(M.SECTION, "auto_generation",
      tostring((tonumber(reaper.GetExtState(M.SECTION, "auto_generation")) or 0) + 1), false)
  end
  -- Una finestrella della versione precedente puo' essere ancora aperta: il suo
  -- monitor non deve continuare a colorare al clic successivo sull'oggetto.
  if reaper.GetExtState(M.SECTION, M.AUTO_KEY) == "1" then
    reaper.SetExtState(M.SECTION, M.AUTO_KEY, "0", false)
    reaper.SetExtState(M.SECTION, "auto_generation",
      tostring((tonumber(reaper.GetExtState(M.SECTION, "auto_generation")) or 0) + 1), false)
  end
  return M.valid_mode(reaper.GetExtState(M.SECTION, "modo"))
end

function M.refresh_buttons()
  local active = M.get_mode()
  local ids = {}
  for _, mode in ipairs(M.MODES) do
    local s = reaper.GetExtState(M.SECTION, "cmd_" .. mode)
    if s ~= "" then ids[mode] = s end
  end
  local auto_id = reaper.GetExtState(M.SECTION, "cmd_auto")
  ids.auto = auto_id ~= "" and auto_id or nil
  if not (ids.item and ids.traccia and ids.tutto and ids.marker and ids.regione and ids.auto) then
    local f = io.open(reaper.GetResourcePath() .. "/reaper-kb.ini", "rb")
    if f then
      local found = M.mode_ids_from_kb(f:read("*a")); f:close()
      for mode, id in pairs(found) do
        if not ids[mode] then ids[mode] = id; reaper.SetExtState(M.SECTION, "cmd_" .. mode, id, true) end
      end
    end
  end
  for _, mode in ipairs(M.MODES) do
    local cmd = ids[mode] and reaper.NamedCommandLookup(ids[mode]) or 0
    if cmd and cmd > 0 then
      reaper.SetToggleCommandState(0, cmd, mode == active and 1 or 0)
      reaper.RefreshToolbar2(0, cmd)
    end
  end
end

function M.set_mode(mode)
  mode = M.valid_mode(mode)
  M.get_mode() -- esegue la migrazione prima di salvare la scelta
  reaper.SetExtState(M.SECTION, "modo", mode, true)
  M.refresh_buttons()
  say(string.format(T("ZP Colori: modo %s attivo. Seleziona, poi clicca un colore."), T(M.MODE_NAMES[mode])))
end

local function selected_items()
  local t = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do t[#t + 1] = reaper.GetSelectedMediaItem(0, i) end
  return t
end

-- Tracce selezionate; se non ce ne sono, le tracce degli item selezionati.
local function target_tracks()
  local t, seen = {}, {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do t[#t + 1] = reaper.GetSelectedTrack(0, i) end
  if #t == 0 then
    for _, it in ipairs(selected_items()) do
      local tr = reaper.GetMediaItem_Track(it)
      if tr and not seen[tr] then seen[tr] = true; t[#t + 1] = tr end
    end
  end
  return t
end

-- Marker e regioni selezionati nell'arrangiamento. L'API ProjectMarker mantiene nome e posizione.
local function selected_project_markers(want_region)
  local out = {}
  if not (reaper.GetNumRegionsOrMarkers and reaper.GetRegionOrMarker
      and reaper.GetRegionOrMarkerInfo_Value and reaper.SetRegionOrMarkerInfo_Value) then
    return nil, T("Questa versione di REAPER non espone l'API per marker e regioni.")
  end
  for i = 0, reaper.GetNumRegionsOrMarkers(0) - 1 do
    local marker = reaper.GetRegionOrMarker(0, i, "")
    if marker then
      local is_region = reaper.GetRegionOrMarkerInfo_Value(0, marker, "B_ISREGION") ~= 0
      local selected = reaper.GetRegionOrMarkerInfo_Value(0, marker, "B_UISEL") ~= 0
      if selected and is_region == want_region then out[#out + 1] = marker end
    end
  end
  return out
end

-- Selezione usata dalla palette: un solo clic colore applica lo stesso colore a tutti gli oggetti
-- supportati selezionati in timeline, anche se sono di tipi diversi.
local function selected_timeline_objects()
  local out = {}
  local project_key = tostring(reaper.EnumProjects(-1, ""))
  local function add(kind, obj, key)
    if obj then out[#out + 1] = { kind = kind, obj = obj, key = project_key .. ":" .. (key or (kind .. ":" .. tostring(obj))) } end
  end
  for _, it in ipairs(selected_items()) do add("item", it) end
  local markers, err = selected_project_markers(false)
  if not markers then return nil, err end
  for _, marker in ipairs(markers) do
    local idx = reaper.GetRegionOrMarkerInfo_Value(0, marker, "I_INDEX")
    add("project_marker", marker, "mrk:" .. tostring(idx))
  end
  local regions, region_err = selected_project_markers(true)
  if not regions then return nil, region_err end
  for _, region in ipairs(regions) do
    local idx = reaper.GetRegionOrMarkerInfo_Value(0, region, "I_INDEX")
    add("project_marker", region, "rgn:" .. tostring(idx))
  end
  return out
end

-- Oggetti selezionati del modo corrente. Le chiavi restano stabili fra i controlli del monitor.
function M.collect_targets(mode)
  if mode == nil or mode == "auto" or mode == "selezione" then return selected_timeline_objects() end
  mode = M.valid_mode(mode or M.get_mode())
  local out = {}
  local project_key = tostring(reaper.EnumProjects(-1, ""))
  local function add(kind, obj, key)
    if obj then out[#out + 1] = { kind = kind, obj = obj, key = project_key .. ":" .. (key or (kind .. ":" .. tostring(obj))) } end
  end
  if mode == "item" then
    for _, it in ipairs(selected_items()) do add("item", it) end
  elseif mode == "traccia" or mode == "tutto" then
    local tracks = target_tracks()
    for _, tr in ipairs(tracks) do
      add("track", tr)
      if mode == "tutto" then
        for i = 0, reaper.CountTrackMediaItems(tr) - 1 do add("item", reaper.GetTrackMediaItem(tr, i)) end
      end
    end
  else
    local markers, err = selected_project_markers(mode == "regione")
    if not markers then return nil, err end
    for _, marker in ipairs(markers) do
      local idx = reaper.GetRegionOrMarkerInfo_Value(0, marker, "I_INDEX")
      add("project_marker", marker, (mode == "regione" and "rgn:" or "mrk:") .. tostring(idx))
    end
  end
  return out
end

local paint_item

local function target_color(target)
  if target.kind == "item" then return reaper.GetMediaItemInfo_Value(target.obj, "I_CUSTOMCOLOR") end
  if target.kind == "track" then return reaper.GetMediaTrackInfo_Value(target.obj, "I_CUSTOMCOLOR") end
  return reaper.GetRegionOrMarkerInfo_Value(0, target.obj, "I_CUSTOMCOLOR")
end

local function paint_target(target, col)
  if target.kind == "item" then paint_item(target.obj, col)
  elseif target.kind == "track" then reaper.SetMediaTrackInfo_Value(target.obj, "I_CUSTOMCOLOR", col)
  else reaper.SetRegionOrMarkerInfo_Value(0, target.obj, "I_CUSTOMCOLOR", col) end
end

local function target_needs_paint(target, col)
  if target.kind ~= "item" then return target_color(target) ~= col end
  if reaper.GetMediaItemInfo_Value(target.obj, "I_CUSTOMCOLOR") ~= col then return true end
  for k = 0, reaper.CountTakes(target.obj) - 1 do
    local take = reaper.GetTake(target.obj, k)
    if take and reaper.GetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR") ~= 0
        and reaper.GetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR") ~= col then return true end
  end
  return false
end

function M.apply_targets(targets, col, label, mode, description)
  if not targets or #targets == 0 then return false end
  local changed = {}
  for _, target in ipairs(targets) do
    -- Evita undo inutili quando una selezione estesa include oggetti gia' colorati.
    if target_needs_paint(target, col) then changed[#changed + 1] = target end
  end
  if #changed == 0 then return false end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  for _, target in ipairs(changed) do
    paint_target(target, col)
    if target.kind == "item" and reaper.UpdateItemInProject then reaper.UpdateItemInProject(target.obj) end
  end
  reaper.PreventUIRefresh(-1)
  -- UpdateArrange ridisegna solo l'arrangiamento; i colori dei marker e delle
  -- regioni sono nel righello e richiedono anche il ridisegno della timeline.
  if reaper.UpdateTimeline then reaper.UpdateTimeline() else reaper.UpdateArrange() end
  local noun = mode == "marker" and T("marker") or mode == "regione" and T("regioni")
    or mode == "item" and T("item") or mode == "traccia" and T("tracce") or T("oggetti")
  local what = description or ("AutoColor, " .. #changed .. " " .. noun)
  reaper.Undo_EndBlock(T("ZP Colori: ") .. T(label) .. " (" .. what .. ")", -1)
  say(T(label) .. ": " .. what)
  return true
end

-- Colore dell'item; i take che hanno un colore loro (che coprirebbe quello dell'item) lo prendono
-- anche loro. col = 0 toglie il colore a item e take.
paint_item = function(it, col)
  reaper.SetMediaItemInfo_Value(it, "I_CUSTOMCOLOR", col)
  for k = 0, reaper.CountTakes(it) - 1 do
    local tk = reaper.GetTake(it, k)
    if tk and (col == 0 or reaper.GetMediaItemTakeInfo_Value(tk, "I_CUSTOMCOLOR") ~= 0) then
      reaper.SetMediaItemTakeInfo_Value(tk, "I_CUSTOMCOLOR", col)
    end
  end
end

-- col: colore nativo con il bit 0x1000000, oppure 0 = togli colore
function M.apply(col, label)
  local mode = M.get_mode()
  local targets, err = M.collect_targets(mode)
  if not targets then return warn(err) end
  if #targets == 0 then
    return warn(string.format(T("ZP Colori: nessun oggetto selezionato per il modo %s."), T(M.MODE_NAMES[mode])))
  end
  local what = #targets .. T(" oggetti selezionati")
  return M.apply_targets(targets, col, label, mode, what)
end

function M.color(n)
  local p = M.PALETTE[n]
  if not p then return end
  M.apply(reaper.ColorToNative(p[2], p[3], p[4]) | 0x1000000, p[1])
end

-- Punto d'ingresso degli script della toolbar: il nome del file dice cosa fare.
function M.button(path)
  local kind, arg = M.parse_button(path)
  if kind == "modo" then
    local _, _, _, cmd = reaper.get_action_context()
    local named = cmd and cmd > 0 and reaper.ReverseNamedCommandLookup(cmd)
    if named and named ~= "" then reaper.SetExtState(M.SECTION, "cmd_" .. arg, "_" .. named:gsub("^_", ""), true) end
    M.set_mode(arg)
  elseif kind == "auto" then
    local _, _, _, cmd = reaper.get_action_context()
    local named = cmd and cmd > 0 and reaper.ReverseNamedCommandLookup(cmd)
    if named and named ~= "" then reaper.SetExtState(M.SECTION, "cmd_auto", "_" .. named:gsub("^_", ""), true) end
    M.set_mode("auto")
  elseif kind == "togli" then
    M.refresh_buttons()
    M.apply(0, "Colore tolto")
  elseif kind == "colore" then
    M.refresh_buttons()
    M.color(arg)
  end
end

return M
