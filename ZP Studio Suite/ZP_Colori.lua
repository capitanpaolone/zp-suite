-- @noindex

-- ZP Studio Suite for REAPER
-- ZP Colori: la logica dietro la toolbar "ZP Colori" (clicca e colora).
-- Ogni pulsante della toolbar e' un piccolo script in colori/ che legge dal proprio nome
-- cosa fare: ZP_Colori_07_Blu.lua = colore 7, ZP_Colori_Modo_Item.lua = modo, ZP_Colori_Togli.lua.
--
-- Tre modi, uno acceso alla volta (i tre pulsanti sono interruttori):
--   Item    = colora gli item selezionati (anche i take che hanno un colore loro).
--   Traccia = colora le tracce selezionate; gli item con un colore loro lo tengono.
--   Tutto   = colora le tracce selezionate e tutti gli item che ci stanno dentro.
-- Senza tracce selezionate, Traccia e Tutto usano le tracce degli item selezionati.
-- Il modo resta salvato (ExtState ZP_COLORI/modo); di serie Item.
-- Palette: la "Versione Saturata" di Paolo (16 colori SWS) + bianco, nero, grigio e rosso acceso.

local M = {}

M.SECTION = "ZP_COLORI"
M.MODES = { "item", "traccia", "tutto" }
M.MODE_FILES = { item = "ZP_Colori_Modo_Item.lua", traccia = "ZP_Colori_Modo_Traccia.lua", tutto = "ZP_Colori_Modo_Tutto.lua" }
M.MODE_NAMES = { item = "Item", traccia = "Traccia", tutto = "Tutto" }

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
  local n = tonumber(name:match("^ZP_Colori_(%d%d)_"))
  if n and M.PALETTE[n] then return "colore", n end
  return nil
end

function M.valid_mode(m)
  return M.MODE_FILES[m] and m or "item"
end

-- Dal testo di reaper-kb.ini: modo -> "_RS..." dei tre script dei modi (sezione principale).
function M.mode_ids_from_kb(kb_text)
  local out = {}
  for line in (tostring(kb_text or "") .. "\n"):gmatch("([^\n]*)\n") do
    local id, rest = line:match('^SCR%s+%d+%s+0%s+(RS%x+)%s+"[^"]*"%s+(.-)%s*$')
    if id then
      local base = (rest:match('^"(.*)"$') or rest):match("([^/\\]+)$")
      for mode, file in pairs(M.MODE_FILES) do
        if base == file and not out[mode] then out[mode] = "_" .. id end
      end
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
  return M.valid_mode(reaper.GetExtState(M.SECTION, "modo"))
end

-- Accende il pulsante del modo attivo e spegne gli altri due.
function M.refresh_buttons()
  local ids = {}
  for _, mode in ipairs(M.MODES) do
    local s = reaper.GetExtState(M.SECTION, "cmd_" .. mode)
    if s ~= "" then ids[mode] = s end
  end
  if not (ids.item and ids.traccia and ids.tutto) then
    local f = io.open(reaper.GetResourcePath() .. "/reaper-kb.ini", "rb")
    if f then
      local found = M.mode_ids_from_kb(f:read("*a")); f:close()
      for mode, id in pairs(found) do
        if not ids[mode] then ids[mode] = id; reaper.SetExtState(M.SECTION, "cmd_" .. mode, id, true) end
      end
    end
  end
  local current = M.get_mode()
  for _, mode in ipairs(M.MODES) do
    local cmd = ids[mode] and reaper.NamedCommandLookup(ids[mode]) or 0
    if cmd and cmd > 0 then
      reaper.SetToggleCommandState(0, cmd, mode == current and 1 or 0)
      reaper.RefreshToolbar2(0, cmd)
    end
  end
end

function M.set_mode(mode)
  mode = M.valid_mode(mode)
  reaper.SetExtState(M.SECTION, "modo", mode, true)
  M.refresh_buttons()
  say(T("Colori: modo ") .. T(M.MODE_NAMES[mode]))
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

-- Colore dell'item; i take che hanno un colore loro (che coprirebbe quello dell'item) lo prendono
-- anche loro. col = 0 toglie il colore a item e take.
local function paint_item(it, col)
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
  local items, tracks = {}, {}
  if mode == "item" then
    items = selected_items()
    if #items == 0 then return warn(T("Colori (modo Item): nessun item selezionato")) end
  else
    tracks = target_tracks()
    if #tracks == 0 then return warn(T("Colori (modo ") .. T(M.MODE_NAMES[mode]) .. T("): nessuna traccia selezionata")) end
    if mode == "tutto" then
      for _, tr in ipairs(tracks) do
        for i = 0, reaper.CountTrackMediaItems(tr) - 1 do items[#items + 1] = reaper.GetTrackMediaItem(tr, i) end
      end
    end
  end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  for _, tr in ipairs(tracks) do reaper.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", col) end
  for _, it in ipairs(items) do paint_item(it, col) end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  local what = mode == "item" and (#items .. " item")
    or mode == "traccia" and (#tracks .. (#tracks == 1 and T(" traccia") or T(" tracce")))
    or (#tracks .. (#tracks == 1 and T(" traccia") or T(" tracce")) .. T(" con ") .. #items .. " item")
  reaper.Undo_EndBlock(T("ZP Colori: ") .. T(label) .. " (" .. what .. ")", -1)
  say(T(label) .. ": " .. what)
end

function M.color(n)
  local p = M.PALETTE[n]
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
  elseif kind == "togli" then
    M.refresh_buttons()
    M.apply(0, "Colore tolto")
  elseif kind == "colore" then
    M.refresh_buttons()
    M.color(arg)
  end
end

return M
