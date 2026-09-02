-- @noindex

--[[
  ZP SOLO Recorder - Proof of Concept
  Autore: Paolo Balestri / ZP Studio Suite

  Telecomando operativo per registrazione voiceover in REAPER.

  Funzioni principali:
  - modulo separato, non modifica gli altri script ZP;
  - Folder Mode e' il default;
  - registrazione esclusiva verificata sull'intero progetto;
  - regione Take automatica a ogni registrazione completata;
  - Lane Mode e' previsto come placeholder futuro;
  - always-on-top e Nascondi/Mostra REAPER sono best-effort: servono js_ReaScriptAPI;
  - REAPER non viene mai nascosto da solo, solo col pulsante, e torna su alla chiusura;
  - NEXT TAKE usa la fine reale del nuovo item -> gap 5s -> REC.

  Riferimenti consultati, non usati come librerie:
  - ZP_UI.lua per stile UI;
  - ZP Gobbo / Project Viewer per gfx, ExtState, marker/regioni;
  - Track Navigator mod per focus/finestra;
  - Dfk Custom Toolbar Utility per idea toolbar gfx;
  - ACendan Insert new track respect folders per attenzione a folder depth;
  - BSmith96 Recording per concetto arm dentro folder;
  - FTC Record takes without new splits per confermare che NEXT TAKE complesso e' fuori scope POC.
]]

local SCRIPT_TITLE = "ZP SOLO Recorder"
local SCRIPT_VERSION = "v0.2.0"
local EXT_SECTION = "ZP_SOLO_Recorder"
local PROJ_SECTION = "ZP_SOLO_Recorder_Project"

local FOLDER_NAME = "ZP SOLO SESSION"
local TRACK_NAMES = {
  main = "VO_MAIN",
  inserts = "VO_INSERTS",
  retakes = "VO_RETAKES",
  alt = "VO_ALT",
  ref = "REF / VIDEO AUDIO"
}
local TRACK_ORDER = { "main", "inserts", "retakes", "alt", "ref" }
local RECORD_TRACK_KEYS = { "main", "inserts", "retakes", "alt" }

local MINI_W, MINI_H = 430, 164
local COMPACT_W, COMPACT_H = 720, 430
local EXPANDED_W, EXPANDED_H = 920, 620
local TOOLBAR_H = 96

local NEXT_TAKE_GAP_SECONDS = 5.0
local DEBOUNCE_SECONDS = 0.35
local STOP_REC_SETTLE_SECONDS = 0.45
local EPS = 0.000001

local ACTION = {
  play = 1007,
  pause = 1008,
  record = 1013,
  stop = 1016,
  save_project = 40026,
  undo = 40029,
  redo = 40030,
  toggle_metronome = 40364,
  show_mixer = 40078,
  show_routing = 40293,
  show_fx_chain = 40291,
  show_notes = 40850,
  region_marker_manager = 40326,
  navigator = 40268,
  video_window = 50125
}

local function script_dir()
  local info = debug.getinfo(1, "S")
  local source = info and info.source or ""
  source = source:gsub("^@", "")
  return source:match("^(.*)[/\\][^/\\]+$") or "."
end

local sep = package.config:sub(1, 1)
local ok_ui, ZP_UI = pcall(dofile, script_dir() .. sep .. "ZP_UI.lua")
if not ok_ui and reaper.GetResourcePath then
  ok_ui, ZP_UI = pcall(dofile, reaper.GetResourcePath() .. sep .. "Scripts" .. sep .. "ZP_Studio_Suite" .. sep .. "ZP_UI.lua")
end
if not ok_ui then ZP_UI = nil end

local state = {
  mode = "compact",
  pin = true,
  toolbar = false,
  preroll = 0,
  folder_mode = true,
  active_track_key = "main",
  take_counter = 1,
  status = "Pronto",
  warning = "",
  hidden_until = nil,
  last_click = {},
  mouse_was_down = false,
  pending = nil,
  countdown = nil,
  reaper_hidden = false,
  last_take = nil,
  last_window_save = 0,
  last_pin_try = 0,
  toolbar_buttons = {},
  record_session = nil
}

local colors = {
  bg = {0.055, 0.058, 0.066, 1},
  panel = {0.10, 0.105, 0.125, 1},
  border = {0.28, 0.29, 0.34, 1},
  text = {0.92, 0.92, 0.94, 1},
  muted = {0.62, 0.64, 0.70, 1},
  green = {0.09, 0.46, 0.22, 1},
  blue = {0.12, 0.32, 0.54, 1},
  yellow = {0.88, 0.66, 0.20, 1},
  orange = {0.76, 0.32, 0.12, 1},
  red = {0.72, 0.06, 0.04, 1},
  rec = {0.95, 0.02, 0.02, 1}
}

local function set_color(c)
  gfx.set(c[1], c[2], c[3], c[4] or 1)
end

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function bool_from_state(value, fallback)
  if value == nil or value == "" then return fallback end
  return value == "1" or value == "true"
end

local function ext_get(key, fallback)
  local value = reaper.GetExtState(EXT_SECTION, key)
  if value == nil or value == "" then return fallback end
  return value
end

local function ext_set(key, value)
  reaper.SetExtState(EXT_SECTION, key, tostring(value or ""), true)
end

local function proj_get(key, fallback)
  local ok, value = reaper.GetProjExtState(0, PROJ_SECTION, key)
  if ok ~= 1 or value == "" then return fallback end
  return value
end

local function proj_set(key, value)
  reaper.SetProjExtState(0, PROJ_SECTION, key, tostring(value or ""))
end

local function load_state()
  state.mode = ext_get("mode", state.mode)
  state.pin = bool_from_state(ext_get("pin", ""), state.pin)
  state.toolbar = bool_from_state(ext_get("toolbar", ""), state.toolbar)
  state.preroll = tonumber(ext_get("preroll", "")) or 0
  state.folder_mode = bool_from_state(ext_get("folder_mode", ""), state.folder_mode)
  state.active_track_key = proj_get("active_track_key", state.active_track_key)
  state.take_counter = tonumber(proj_get("take_counter", "")) or state.take_counter
end

local function save_state()
  ext_set("mode", state.mode)
  ext_set("pin", state.pin and "1" or "0")
  ext_set("toolbar", state.toolbar and "1" or "0")
  ext_set("preroll", state.preroll)
  ext_set("folder_mode", state.folder_mode and "1" or "0")
  proj_set("active_track_key", state.active_track_key)
  proj_set("take_counter", state.take_counter)
end

local function save_window_state()
  if not gfx or not gfx.dock then return end
  local now = reaper.time_precise()
  if now - state.last_window_save < 0.8 then return end
  state.last_window_save = now
  local dock, x, y, w, h = gfx.dock(-1, 0, 0, 0, 0)
  ext_set("window_dock", dock or 0)
  ext_set("window_x", x or 120)
  ext_set("window_y", y or 120)
  ext_set("window_w", w or gfx.w)
  ext_set("window_h", h or gfx.h)
end

local function speak(text)
  text = tostring(text or "")
  state.status = text
  if reaper.osara_outputMessage then
    reaper.osara_outputMessage(text)
  else
    reaper.ShowConsoleMsg(SCRIPT_TITLE .. ": " .. text .. "\n")
  end
end

local function warn(text)
  state.warning = tostring(text or "")
  speak(text)
end

local function point_in_rect(px, py, x, y, w, h)
  if ZP_UI and ZP_UI.point_in_rect then return ZP_UI.point_in_rect(px, py, x, y, w, h) end
  return px >= x and px <= x + w and py >= y and py <= y + h
end

local function fit_text(text, max_w)
  text = tostring(text or "")
  if ZP_UI and ZP_UI.fit_text then return ZP_UI.fit_text(text, max_w) end
  if gfx.measurestr(text) <= max_w then return text end
  local suffix = "..."
  local out = ""
  for i = 1, #text do
    local candidate = text:sub(1, i)
    if gfx.measurestr(candidate) + gfx.measurestr(suffix) > max_w then break end
    out = candidate
  end
  return trim(out) .. suffix
end

local function mouse_clicked()
  return (gfx.mouse_cap & 1) == 0 and state.mouse_was_down
end

local function draw_fallback_button(rect, label, active, enabled, clicked, style)
  enabled = enabled ~= false
  local hover = enabled and point_in_rect(gfx.mouse_x, gfx.mouse_y, rect.x, rect.y, rect.w, rect.h)
  local fill = colors.panel
  if style == "danger" or style == "stop" or style == "rec" then fill = active and colors.rec or colors.red
  elseif style == "play" or style == "save" then fill = active and colors.green or colors.green
  elseif style == "tab" or active then fill = colors.blue
  elseif hover then fill = {0.18, 0.19, 0.23, 1} end
  if not enabled then fill = {0.09, 0.09, 0.10, 1} end
  set_color(fill)
  gfx.rect(rect.x, rect.y, rect.w, rect.h, true)
  set_color(colors.border)
  gfx.rect(rect.x, rect.y, rect.w, rect.h, false)
  gfx.setfont(1, "Arial", rect.h <= 26 and 13 or 15, "b")
  gfx.set(enabled and 0.96 or 0.45, enabled and 0.96 or 0.45, enabled and 0.97 or 0.45, 1)
  local label_out = fit_text(label, rect.w - 14)
  local tw, th = gfx.measurestr(label_out)
  gfx.x = rect.x + math.max(6, (rect.w - tw) * 0.5)
  gfx.y = rect.y + math.max(4, (rect.h - th) * 0.5)
  gfx.drawstr(label_out)
  return clicked and enabled and hover
end

local function draw_button(rect, label, active, enabled, clicked, style)
  if ZP_UI and ZP_UI.draw_button and style ~= "rec" then
    return ZP_UI.draw_button(rect, label, active, enabled, clicked, style)
  end
  return draw_fallback_button(rect, label, active, enabled, clicked, style)
end

local function transport_state()
  local ps = reaper.GetPlayState()
  local recording = (ps & 4) == 4
  local paused = (ps & 2) == 2
  local playing = (ps & 1) == 1
  if recording then return "REC", ps end
  if paused then return "PAUSE", ps end
  if playing then return "PLAY", ps end
  return "STOP", ps
end

local function current_position()
  local label, ps = transport_state()
  if label == "PLAY" or label == "REC" then return reaper.GetPlayPosition() end
  return reaper.GetCursorPosition()
end

local function format_time(pos)
  if reaper.format_timestr_pos then return reaper.format_timestr_pos(pos or 0, "", 5) end
  local s = math.max(0, pos or 0)
  local h = math.floor(s / 3600)
  local m = math.floor((s - h * 3600) / 60)
  local sec = s - h * 3600 - m * 60
  return string.format("%02d:%02d:%06.3f", h, m, sec)
end

local function track_name(track)
  if not track then return "" end
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  return name or ""
end

local function find_track_exact(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    if track_name(track) == name then return track, i end
  end
  return nil, nil
end

local function track_index(track)
  if not track then return nil end
  local ptr = tostring(track)
  for i = 0, reaper.CountTracks(0) - 1 do
    local current = reaper.GetTrack(0, i)
    if tostring(current) == ptr then return i end
  end
  return nil
end

local function set_track_name(track, name)
  if track then reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true) end
end

local function native_color(r, g, b)
  return reaper.ColorToNative(r, g, b) | 0x1000000
end

local function set_track_color(track, r, g, b)
  if track then reaper.SetTrackColor(track, native_color(r, g, b)) end
end

local function find_folder_end(folder)
  local start_idx = track_index(folder)
  if not start_idx then return nil end
  local depth = 1
  for i = start_idx + 1, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    depth = depth + math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0)
    if depth <= 0 then return i end
  end
  return reaper.CountTracks(0) - 1
end

local function insert_named_track(index, name, color)
  reaper.InsertTrackAtIndex(index, true)
  local track = reaper.GetTrack(0, index)
  set_track_name(track, name)
  if color then set_track_color(track, color[1], color[2], color[3]) end
  return track
end

local function solo_tracks()
  local out = {}
  for _, key in ipairs(TRACK_ORDER) do
    local tr = find_track_exact(TRACK_NAMES[key])
    if tr then out[key] = tr end
  end
  return out
end

local function normalize_solo_folder_depths(tracks)
  local folder = find_track_exact(FOLDER_NAME)
  if not folder then return end
  reaper.SetMediaTrackInfo_Value(folder, "I_FOLDERDEPTH", 1)
  local last_key = nil
  for _, key in ipairs(TRACK_ORDER) do
    if tracks[key] then last_key = key end
  end
  for _, key in ipairs(TRACK_ORDER) do
    if tracks[key] then
      reaper.SetMediaTrackInfo_Value(tracks[key], "I_FOLDERDEPTH", key == last_key and -1 or 0)
    end
  end
end

local function ensure_solo_structure()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local folder, folder_idx = find_track_exact(FOLDER_NAME)
  if not folder then
    local idx = reaper.CountTracks(0)
    folder = insert_named_track(idx, FOLDER_NAME, {50, 145, 170})
    folder_idx = idx
    for offset, key in ipairs(TRACK_ORDER) do
      local tr = insert_named_track(folder_idx + offset, TRACK_NAMES[key], ({ 
        main = {80, 185, 110}, inserts = {240, 170, 60}, retakes = {215, 95, 70}, alt = {145, 115, 210}, ref = {92, 155, 215}
      })[key])
      reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 1)
      reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 1)
    end
  else
    local tracks = solo_tracks()
    local insert_at = (find_folder_end(folder) or folder_idx) + 1
    for _, key in ipairs(TRACK_ORDER) do
      if not tracks[key] then
        tracks[key] = insert_named_track(insert_at, TRACK_NAMES[key], nil)
        insert_at = insert_at + 1
      end
    end
  end

  normalize_solo_folder_depths(solo_tracks())
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ZP SOLO Recorder: crea/trova struttura SOLO", -1)
  reaper.UpdateArrange()
  return solo_tracks()
end

local function active_track()
  local tracks = solo_tracks()
  return tracks[state.active_track_key], TRACK_NAMES[state.active_track_key]
end

local function set_active_track_key(key)
  if not TRACK_NAMES[key] then return false end
  state.active_track_key = key
  proj_set("active_track_key", key)
  return true
end

local function arm_only_solo_target(key)
  local tracks = ensure_solo_structure()
  local target = tracks[key]
  if not target then warn("Traccia SOLO non trovata: " .. tostring(TRACK_NAMES[key] or key)); return nil end
  -- L'esclusivita' riguarda l'intero progetto, non soltanto le tracce SOLO.
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", tr == target and 1 or 0)
  end
  reaper.SetMediaTrackInfo_Value(target, "I_RECMON", 1)
  if reaper.GetMediaTrackInfo_Value(target, "I_RECINPUT") < 0 then
    reaper.SetMediaTrackInfo_Value(target, "I_RECINPUT", 0)
  end
  reaper.SetOnlyTrackSelected(target)
  set_active_track_key(key)
  local armed_count, armed_target = 0, false
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1 then
      armed_count = armed_count + 1
      armed_target = armed_target or tr == target
    end
  end
  if armed_count ~= 1 or not armed_target then
    warn("REC BLOCCATO: impossibile garantire la registrazione esclusiva.")
    return nil
  end
  state.status = "REC READY — " .. TRACK_NAMES[key]
  return target
end

local function item_guid(item)
  if not item then return nil end
  local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  return guid
end

local function snapshot_items()
  local seen = {}
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local guid = item_guid(reaper.GetMediaItem(0, i))
    if guid then seen[guid] = true end
  end
  return seen
end

local function last_item_end()
  local last_end = nil
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local item = reaper.GetMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_end = pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if not last_end or item_end > last_end then last_end = item_end end
  end
  return last_end
end

local function can_click(id)
  local now = reaper.time_precise()
  local last = state.last_click[id] or 0
  if now - last < DEBOUNCE_SECONDS then return false end
  state.last_click[id] = now
  return true
end

local function start_preroll(seconds, callback, label)
  seconds = tonumber(seconds) or 0
  if seconds <= 0 then callback(); return end
  state.countdown = { start = reaper.time_precise(), seconds = seconds, callback = callback, label = label or "REC" }
end

local function do_record_now()
  if (reaper.GetPlayState() & 4) == 4 then
    speak("REC gia' attivo.")
    return
  end
  local target = arm_only_solo_target(state.active_track_key)
  if not target then return end
  state.record_session = {
    before = snapshot_items(),
    track = target,
    track_key = state.active_track_key,
    started_at = reaper.GetCursorPosition()
  }
  reaper.Main_OnCommand(ACTION.record, 0)
  if (reaper.GetPlayState() & 4) ~= 4 then
    state.record_session = nil
    warn("REC BLOCCATO: REAPER non ha avviato la registrazione.")
    return
  end
  state.status = "● REC — " .. TRACK_NAMES[state.active_track_key]
end

local function record_on_track(key, label)
  if not can_click("record_" .. key) then return end
  if (reaper.GetPlayState() & 4) == 4 then
    speak("REAPER sta gia' registrando.")
    return
  end
  if not arm_only_solo_target(key) then return end
  start_preroll(state.preroll, do_record_now, label or "REC")
end

local function stop_transport()
  if not can_click("stop") then return end
  local was_recording = (reaper.GetPlayState() & 4) == 4
  reaper.Main_OnCommand(ACTION.stop, 0)
  if was_recording and state.record_session then
    state.pending = { kind = "finalize_recording", due = reaper.time_precise() + STOP_REC_SETTLE_SECONDS,
      session = state.record_session }
    state.record_session = nil
    state.status = "STOP — preparo indice take"
  else
    state.status = "STOP"
  end
end

local function play_transport()
  if not can_click("play") then return end
  if (reaper.GetPlayState() & 4) == 4 then
    warn("STOP prima del PLAY: registrazione in corso.")
    return
  end
  reaper.Main_OnCommand(ACTION.play, 0)
  state.status = "PLAY"
end

local function pause_transport()
  if not can_click("pause") then return end
  reaper.Main_OnCommand(ACTION.pause, 0)
  state.status = "PAUSE"
end

local function move_cursor(delta)
  if not can_click("move_" .. tostring(delta)) then return end
  local pos = math.max(0, current_position() + delta)
  reaper.SetEditCurPos(pos, true, false)
  state.status = delta < 0 and "Back 5s" or "Forward 5s"
end

local function goto_after_last_item()
  if not can_click("after_last_item") then return end
  local item_end = last_item_end()
  if not item_end then
    reaper.SetEditCurPos(0, true, false)
    warn("Nessun item presente: cursore a 0:00.")
    return
  end
  reaper.SetEditCurPos(item_end + NEXT_TAKE_GAP_SECONDS, true, false)
  state.status = "Dopo ultimo item +" .. tostring(NEXT_TAKE_GAP_SECONDS) .. "s"
end

local function add_marker_named(prefix, prompt)
  local pos = current_position()
  local idx = tonumber(proj_get(prefix .. "_counter", "")) or 1
  local name = string.format("%s_%03d", prefix, idx)
  if prompt then
    local ok, value = reaper.GetUserInputs("ZP SOLO marker", 1, "Nome marker,extrawidth=420", name)
    if not ok then return end
    name = trim(value)
    if name == "" then return end
  end
  local color_map = {
    SOLO_MARK = native_color(100, 180, 230),
    BAD = native_color(230, 60, 50),
    OK = native_color(80, 200, 110),
    ALT = native_color(160, 115, 220),
    NOISE = native_color(235, 170, 60),
    INSERT = native_color(245, 145, 50)
  }
  reaper.AddProjectMarker2(0, false, pos, 0, name, -1, color_map[prefix] or 0)
  proj_set(prefix .. "_counter", idx + 1)
  reaper.UpdateArrange()
  state.status = "Marker: " .. name
end

local function collect_regions()
  local regions = {}
  local _, marker_count, region_count = reaper.CountProjectMarkers(0)
  local total = marker_count + region_count
  for i = 0, total - 1 do
    local ok, is_region, pos, rgn_end, name, idx, color = reaper.EnumProjectMarkers3(0, i)
    if ok and is_region then
      regions[#regions + 1] = { pos = pos, end_pos = rgn_end, name = trim(name or ""), idx = idx, color = color or 0 }
    end
  end
  table.sort(regions, function(a, b) return a.pos < b.pos end)
  return regions
end

local function current_region()
  local pos = current_position()
  for _, r in ipairs(collect_regions()) do
    if pos >= r.pos - EPS and pos <= r.end_pos + EPS then return r end
  end
  return nil
end

local function region_label()
  local r = current_region()
  if not r then return "Nessuna regione" end
  return r.name ~= "" and r.name or ("Regione " .. tostring(r.idx or "?"))
end

local function goto_region(delta)
  if not can_click("region_" .. tostring(delta)) then return end
  local regions = collect_regions()
  if #regions == 0 then warn("Nessuna regione nel progetto."); return end
  local pos = current_position()
  local target = nil
  if delta < 0 then
    for i = #regions, 1, -1 do
      if regions[i].pos < pos - 0.05 then target = regions[i]; break end
    end
    target = target or regions[1]
  else
    for _, r in ipairs(regions) do
      if r.pos > pos + 0.05 then target = r; break end
    end
    target = target or regions[#regions]
  end
  reaper.SetEditCurPos(target.pos, true, false)
  state.status = "Regione: " .. (target.name ~= "" and target.name or tostring(target.idx))
end

local function goto_region_start()
  local r = current_region()
  if not r then warn("Il cursore non e' dentro una regione."); return end
  reaper.SetEditCurPos(r.pos, true, false)
  state.status = "Inizio regione"
end

local function rec_region(key)
  local r = current_region()
  if not r then warn("Il cursore non e' dentro una regione."); return end
  reaper.SetEditCurPos(r.pos, true, false)
  record_on_track(key, key == "retakes" and "RETAKE" or "REC REGION")
end

local function insert_record()
  add_marker_named("INSERT", false)
  record_on_track("inserts", "INSERT")
end

local function alt_take()
  add_marker_named("ALT", false)
  record_on_track("alt", "ALT TAKE")
end

local function next_take()
  if not can_click("next_take") then return end
  if (reaper.GetPlayState() & 4) ~= 4 then
    warn("NEXT TAKE disponibile solo durante REC nella POC.")
    return
  end
  local key = state.active_track_key
  reaper.Main_OnCommand(ACTION.stop, 0)
  state.pending = {
    kind = "finalize_and_next_take",
    due = reaper.time_precise() + STOP_REC_SETTLE_SECONDS,
    track_key = key,
    session = state.record_session
  }
  state.record_session = nil
  state.status = "NEXT TAKE: stop e preparo nuovo take"
end

-- Toglie dalla timeline il take appena registrato e riporta il cursore
-- dov'era partito, pronto a rifarlo. Il file audio NON viene cancellato:
-- resta nella cartella del progetto. Tutto dentro un blocco di undo, quindi
-- un Ctrl+Z lo rimette esattamente com'era.
local function undo_last_take()
  local lt = state.last_take
  if not lt or not lt.guids or #lt.guids == 0 then
    warn("Nessun take di questa sessione da togliere. Per quelli di prima usa l'Undo di REAPER.")
    return
  end
  reaper.Undo_BeginBlock()
  local cercati = {}
  for _, g in ipairs(lt.guids) do cercati[g] = true end
  local tolti = 0
  for i = reaper.CountMediaItems(0) - 1, 0, -1 do
    local item = reaper.GetMediaItem(0, i)
    local guid = item and item_guid(item)
    if guid and cercati[guid] then
      local tr = reaper.GetMediaItemTrack(item)
      if tr and reaper.DeleteTrackMediaItem(tr, item) then tolti = tolti + 1 end
    end
  end
  if lt.region then
    local i = 0
    while true do
      local retval, isrgn, _, _, nome, idx = reaper.EnumProjectMarkers(i)
      if retval == 0 then break end
      if isrgn and nome == lt.region then
        reaper.DeleteProjectMarker(0, idx, true)
        break
      end
      i = i + 1
    end
  end
  if state.take_counter > 1 then
    state.take_counter = state.take_counter - 1
    proj_set("take_counter", state.take_counter)
  end
  if lt.start then reaper.SetEditCurPos(lt.start, true, false) end
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("ZP SOLO: tolto " .. (lt.region or "l'ultimo take") .. " dalla timeline", -1)
  state.last_take = nil
  if tolti == 0 then
    warn("Non ho trovato gli item di quel take: forse li hai gia' spostati o tolti a mano.")
    return
  end
  state.status = (lt.region or "Ultimo take") ..
    " tolto dalla timeline, cursore all'inizio. Il file resta nella cartella del progetto; Ctrl+Z lo rimette."
end

local function finalize_recording(session)
  if not session then return nil end
  local first_pos, final_end = nil, nil
  local nuovi = {}
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local item = reaper.GetMediaItem(0, i)
    local guid = item_guid(item)
    local belongs_to_target = reaper.GetMediaItemTrack(item) == session.track
    if guid and not session.before[guid] and belongs_to_target then
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_end = pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      first_pos = not first_pos and pos or math.min(first_pos, pos)
      final_end = not final_end and item_end or math.max(final_end, item_end)
      nuovi[#nuovi + 1] = guid
    end
  end
  if not first_pos or not final_end or final_end <= first_pos + EPS then
    warn("STOP: nessun nuovo item registrato identificato.")
    return nil
  end
  local take_number = state.take_counter
  local name = string.format("Take %03d", take_number)
  reaper.AddProjectMarker2(0, true, first_pos, final_end, name, -1, native_color(70, 155, 220))
  state.take_counter = take_number + 1
  proj_set("take_counter", state.take_counter)
  -- Mi segno cos'e' appena entrato in timeline: serve a TOGLI TAKE.
  state.last_take = { guids = nuovi, start = first_pos, region = name,
                      track_key = session.track_key }
  reaper.UpdateArrange()
  state.status = name .. " indicizzato — " .. TRACK_NAMES[session.track_key]
  return final_end, name
end

local function rename_last_take_region()
  local regions = collect_regions()
  if #regions == 0 then warn("Nessuna regione da rinominare."); return end
  local r = regions[#regions]
  local current_name = r.name ~= "" and r.name or "Take"
  local ok, value = reaper.GetUserInputs("Nome / nota ultima registrazione", 1,
    "Nome o nota,extrawidth=520", current_name)
  if not ok then return end
  value = trim(value)
  if value == "" then return end
  reaper.SetProjectMarker3(0, r.idx, true, r.pos, r.end_pos, value, r.color)
  reaper.UpdateArrange()
  state.status = "Ultima regione: " .. value
end

local function process_pending()
  if state.countdown then
    local elapsed = reaper.time_precise() - state.countdown.start
    if elapsed >= state.countdown.seconds then
      local cb = state.countdown.callback
      state.countdown = nil
      cb()
    end
  end
  if not state.pending then return end
  if reaper.time_precise() < state.pending.due then return end
  local pending = state.pending
  state.pending = nil
  if pending.kind == "finalize_recording" then
    finalize_recording(pending.session)
  elseif pending.kind == "finalize_and_next_take" then
    local recorded_end = finalize_recording(pending.session)
    local base = recorded_end or last_item_end()
    if not base then
      warn("NEXT TAKE: nessun item da cui proseguire.")
      return
    end
    reaper.SetEditCurPos(base + NEXT_TAKE_GAP_SECONDS, true, false)
    if not arm_only_solo_target(pending.track_key) then
      warn("NEXT TAKE: impossibile riarmare la traccia SOLO.")
      return
    end
    start_preroll(state.preroll, do_record_now, "NEXT TAKE")
  elseif pending.kind == "show_after_hide" then
    state.hidden_until = nil
    if gfx.init then
      -- gfx non espone una vera hide/show cross-platform; il POC ridisegna la finestra e prova a riportarla davanti.
      state.status = "Recorder richiamato"
    end
  end
end

local function meter_for_track(track)
  if not track or not reaper.Track_GetPeakInfo then return 0, "N/A" end
  local l = math.abs(reaper.Track_GetPeakInfo(track, 0) or 0)
  local r = math.abs(reaper.Track_GetPeakInfo(track, 1) or l)
  local peak = math.max(l, r)
  local db = peak > 0 and (20 * math.log(peak, 10)) or -150
  local label = "LOW"
  if db > -1 then label = "CLIP"
  elseif db > -9 then label = "HOT"
  elseif db > -30 then label = "OK" end
  return math.min(1, peak), label
end

local function master_meter()
  return meter_for_track(reaper.GetMasterTrack(0))
end

local function show_video_window()
  local state_before = reaper.GetToggleCommandState(ACTION.video_window)
  if state_before == 0 then reaper.Main_OnCommand(ACTION.video_window, 0) end
  state.status = "Video Window"
end

local function show_navigator()
  local ok = pcall(reaper.Main_OnCommand, ACTION.navigator, 0)
  if ok then state.status = "Navigator" else warn("Navigator non disponibile.") end
end

local function run_action(action_id, label)
  if not action_id then return end
  reaper.Main_OnCommand(action_id, 0)
  state.status = label or ("Action " .. tostring(action_id))
end

local function try_pin_window()
  if not state.pin then return end
  if reaper.time_precise() - state.last_pin_try < 1.0 then return end
  state.last_pin_try = reaper.time_precise()
  if not (reaper.JS_Window_Find and reaper.JS_Window_SetZOrder) then return end
  local hwnd = reaper.JS_Window_Find(SCRIPT_TITLE, true)
  if hwnd then pcall(reaper.JS_Window_SetZOrder, hwnd, "TOPMOST") end
end

local function try_unpin_window()
  if not (reaper.JS_Window_Find and reaper.JS_Window_SetZOrder) then return end
  local hwnd = reaper.JS_Window_Find(SCRIPT_TITLE, true)
  if hwnd then pcall(reaper.JS_Window_SetZOrder, hwnd, "NOTOPMOST") end
end

-- Nascondi / mostra la finestra di REAPER. E' un interruttore, e non viene
-- mai premuto da solo: all'avvio REAPER resta dov'e'.
local function toggle_reaper_window()
  if not (reaper.GetMainHwnd and reaper.JS_Window_Show) then
    state.warning = "Serve js_ReaScriptAPI per nascondere e rimettere su REAPER."
    return
  end
  local hwnd = reaper.GetMainHwnd()
  if not hwnd then
    state.warning = "Finestra di REAPER non trovata."
    return
  end
  if state.reaper_hidden then
    local ok = pcall(reaper.JS_Window_Show, hwnd, "RESTORE")
    if not ok then
      state.warning = "Non sono riuscito a rimettere su REAPER: usa il Dock."
      return
    end
    if reaper.JS_Window_SetForeground then
      pcall(reaper.JS_Window_SetForeground, hwnd)
    end
    state.reaper_hidden = false
    state.warning = ""
    state.status = "REAPER di nuovo visibile"
  else
    local ok = pcall(reaper.JS_Window_Show, hwnd, "MINIMIZE")
    if not ok then
      state.warning = "Minimize non disponibile su questo sistema."
      return
    end
    state.reaper_hidden = true
    state.warning = ""
    state.status = "REAPER nascosto: premi Mostra REAPER per riportarlo su"
  end
end

-- Monitoring d'ingresso della traccia attiva. REAPER tende ad accenderlo
-- da solo quando armi: qui si spegne e si riaccende senza aprire la finestra
-- principale. I_RECMON: 0 spento, 1 acceso, 2 automatico.
local function monitoring_label()
  local tr = active_track()
  if not tr then return "Monitor -", false end
  local mon = reaper.GetMediaTrackInfo_Value(tr, "I_RECMON")
  if mon == 2 then return "Monitor auto", true end
  if mon == 1 then return "Monitor ON", true end
  return "Monitor OFF", false
end

local function toggle_monitoring()
  local tr, nome = active_track()
  if not tr then
    warn("Traccia non trovata: scegline un'altra o costruisci la catena.")
    return
  end
  local mon = reaper.GetMediaTrackInfo_Value(tr, "I_RECMON")
  local nuovo = (mon == 0) and 1 or 0
  reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", nuovo)
  state.status = (nuovo == 1 and "Monitoring acceso su " or "Monitoring spento su ") .. (nome or "?")
end

-- Se chiudi il telecomando mentre REAPER e' nascosto, non lo lascio sparito.
local function restore_reaper_on_exit()
  if not state.reaper_hidden then return end
  if not (reaper.GetMainHwnd and reaper.JS_Window_Show) then return end
  local hwnd = reaper.GetMainHwnd()
  if hwnd then pcall(reaper.JS_Window_Show, hwnd, "RESTORE") end
  state.reaper_hidden = false
end

local function park_window()
  local w, h = gfx.w, gfx.h
  local _, _, screen_w, screen_h = reaper.my_getViewport(0, 0, 0, 0, 0, 0, 0, 0, true)
  gfx.init(SCRIPT_TITLE, w, h, 0, math.max(0, screen_w - w - 24), 42)
  state.status = "Finestra parcheggiata"
end

local function hide_5s()
  state.hidden_until = reaper.time_precise() + 5
  state.pending = { kind = "show_after_hide", due = state.hidden_until }
  state.status = "Hide 5s"
end

local function mode_size(mode)
  if mode == "mini" then return MINI_W, MINI_H end
  if mode == "expanded" then return EXPANDED_W, EXPANDED_H end
  return COMPACT_W, COMPACT_H
end

local function set_mode(mode)
  if mode ~= "mini" and mode ~= "compact" and mode ~= "expanded" then return end
  state.mode = mode
  local w, h = mode_size(mode)
  if mode ~= "mini" and state.toolbar then h = h + TOOLBAR_H end
  local dock, x, y = gfx.dock(-1, 0, 0, 0, 0)
  gfx.init(SCRIPT_TITLE, w, h, dock or 0, x or 140, y or 120)
  save_state()
end

local function cycle_preroll()
  local options = {0, 1, 2, 3, 5}
  local next_value = 0
  for i, value in ipairs(options) do
    if value == state.preroll then next_value = options[(i % #options) + 1]; break end
  end
  state.preroll = next_value
  save_state()
end

local function draw_status_header(clicked)
  local label, ps = transport_state()
  local rec = label == "REC"
  set_color(rec and colors.rec or colors.panel)
  gfx.rect(0, 0, gfx.w, state.mode == "mini" and 56 or 78, true)
  set_color(colors.border)
  gfx.rect(0, state.mode == "mini" and 55 or 77, gfx.w, 1, true)
  gfx.setfont(1, "Arial", rec and 28 or 22, "b")
  gfx.set(1, 1, 1, 1)
  gfx.x, gfx.y = 14, rec and 10 or 12
  local active_name = TRACK_NAMES[state.active_track_key] or "?"
  gfx.drawstr(rec and ("● REC — " .. active_name) or label)
  gfx.setfont(2, "Arial", state.mode == "mini" and 22 or 30, "b")
  local tc = format_time(current_position())
  local tw = gfx.measurestr(tc)
  gfx.x, gfx.y = gfx.w - tw - 16, state.mode == "mini" and 17 or 18
  gfx.drawstr(tc)
  if state.mode ~= "mini" then
    gfx.setfont(3, "Arial", 13)
    gfx.set(0.82, 0.84, 0.88, 1)
    gfx.x, gfx.y = 16, 50
    local tr = TRACK_NAMES[state.active_track_key] or "?"
    gfx.drawstr(fit_text("Track: " .. tr .. "   Region: " .. region_label() .. "   Take: " .. tostring(state.take_counter) .. "   Preroll: " .. tostring(state.preroll) .. "s", gfx.w - 32))
  end
end

local function draw_meter(x, y, w, h, value, label)
  set_color({0.055, 0.055, 0.065, 1})
  gfx.rect(x, y, w, h, true)
  local col = colors.green
  if label == "HOT" then col = colors.yellow elseif label == "CLIP" then col = colors.rec elseif label == "LOW" then col = colors.blue end
  set_color(col)
  gfx.rect(x + 2, y + 2, math.max(2, (w - 4) * math.min(1, value or 0)), h - 4, true)
  set_color(colors.border)
  gfx.rect(x, y, w, h, false)
  gfx.setfont(1, "Arial", 12, "b")
  gfx.set(1, 1, 1, 1)
  gfx.x, gfx.y = x + 8, y + 4
  gfx.drawstr(label or "N/A")
end

local function draw_transport(y, clicked)
  local gap, margin, count = state.mode == "mini" and 5 or 9, 14, 5
  local bw = math.floor((gfx.w - margin * 2 - gap * (count - 1)) / count)
  local bh = state.mode == "mini" and 42 or 52
  -- Le etichette lunghe venivano tagliate a meta' parola quando il pulsante
  -- si stringe: in Mini, o quando rimpicciolisci la finestra a mano.
  -- Meglio una parola corta e intera che una lunga con i puntini.
  local stretto = bw < 104
  local x = margin
  if draw_button({x=x, y=y, w=bw, h=bh}, "REC", transport_state() == "REC", true, clicked, "rec") then
    record_on_track(state.active_track_key, "REC")
  end
  x = x + bw + gap
  if draw_button({x=x, y=y, w=bw, h=bh}, "STOP", false, true, clicked, "stop") then stop_transport() end
  x = x + bw + gap
  if draw_button({x=x, y=y, w=bw, h=bh}, "PLAY", transport_state() == "PLAY", true, clicked, "play") then play_transport() end
  x = x + bw + gap
  if draw_button({x=x, y=y, w=bw, h=bh}, stretto and "-5s" or "INDIETRO 5s", false, true, clicked) then move_cursor(-5) end
  x = x + bw + gap
  if draw_button({x=x, y=y, w=bw, h=bh}, stretto and "FINE +5s" or "ULTIMO ITEM +5s", false, true, clicked) then goto_after_last_item() end
end

local function draw_track_selector(y, clicked)
  local margin, gap = 14, 8
  local bw = math.floor((gfx.w - margin * 2 - gap * (#RECORD_TRACK_KEYS - 1)) / #RECORD_TRACK_KEYS)
  for i, key in ipairs(RECORD_TRACK_KEYS) do
    local x = margin + (i - 1) * (bw + gap)
    local label = TRACK_NAMES[key]:gsub("^VO_", "")
    if draw_button({x=x, y=y, w=bw, h=32}, label, state.active_track_key == key, true, clicked, "tab") then
      if arm_only_solo_target(key) then state.warning = "" end
    end
  end
end

local function draw_mode_buttons(y, clicked)
  local x = gfx.w - 318
  if draw_button({x=x, y=y, w=94, h=30}, "Mini", state.mode == "mini", true, clicked, "tab") then set_mode("mini") end
  if draw_button({x=x+102, y=y, w=94, h=30}, "Compact", state.mode == "compact", true, clicked, "tab") then set_mode("compact") end
  if draw_button({x=x+204, y=y, w=94, h=30}, "Expanded", state.mode == "expanded", true, clicked, "tab") then set_mode("expanded") end
end

local function draw_compact(clicked)
  draw_transport(96, clicked)
  draw_track_selector(158, clicked)
  local y = 204
  local bw, bh, gap = 128, 36, 10
  local x = 14
  if draw_button({x=x, y=y, w=bw, h=bh}, "MARK", false, true, clicked) then add_marker_named("SOLO_MARK", false) end
  if draw_button({x=x+bw+gap, y=y, w=bw, h=bh}, "MARK NAME", false, true, clicked) then add_marker_named("SOLO_MARK", true) end
  if draw_button({x=x+(bw+gap)*2, y=y, w=bw, h=bh}, "REG PREV", false, true, clicked) then goto_region(-1) end
  if draw_button({x=x+(bw+gap)*3, y=y, w=bw, h=bh}, "REG NEXT", false, true, clicked) then goto_region(1) end
  if draw_button({x=x+(bw+gap)*4, y=y, w=bw, h=bh}, "REG START", false, true, clicked) then goto_region_start() end

  y = 256
  local tr = active_track()
  local peak, in_label = meter_for_track(tr)
  local master_peak, master_label = master_meter()
  gfx.setfont(1, "Arial", 13, "b")
  gfx.set(0.86, 0.86, 0.90, 1)
  gfx.x, gfx.y = 16, y
  gfx.drawstr("INPUT")
  draw_meter(78, y - 4, 250, 24, peak, in_label)
  gfx.x, gfx.y = 350, y
  gfx.drawstr("RETURN")
  draw_meter(424, y - 4, 250, 24, master_peak, master_label)

  y = 302
  if draw_button({x=14, y=y, w=112, h=34}, "Preroll " .. state.preroll .. "s", false, true, clicked) then cycle_preroll() end
  if draw_button({x=138, y=y, w=112, h=34}, "Toolbar", state.toolbar, true, clicked, "tab") then state.toolbar = not state.toolbar; save_state(); set_mode(state.mode) end
  if draw_button({x=262, y=y, w=88, h=34}, "Pin", state.pin, true, clicked, "tab") then state.pin = not state.pin; if not state.pin then try_unpin_window() end; save_state() end
  if draw_button({x=362, y=y, w=96, h=34}, "Hide 5s", false, true, clicked) then hide_5s() end
  if draw_button({x=470, y=y, w=88, h=34}, "Park", false, true, clicked) then park_window() end
  if draw_button({x=570, y=y, w=136, h=34},
                 state.reaper_hidden and "Mostra REAPER" or "Nascondi REAPER",
                 state.reaper_hidden, true, clicked, "tab") then toggle_reaper_window() end
  local mon_label, mon_on = monitoring_label()
  if draw_button({x=14, y=y + 44, w=132, h=30}, mon_label, mon_on, true, clicked, "tab") then
    toggle_monitoring()
  end
  draw_mode_buttons(y + 44, clicked)

  y = 388
  gfx.setfont(1, "Arial", 13)
  gfx.set(0.74, 0.76, 0.82, 1)
  gfx.x, gfx.y = 16, y
  gfx.drawstr(fit_text(state.warning ~= "" and state.warning or state.status, gfx.w - 32))
end

local function draw_expanded(clicked)
  draw_compact(clicked)
  local y = 430
  local bw, bh, gap = 128, 36, 10
  local labels = {
    {"NOME / NOTA TAKE", rename_last_take_region, "play"},
    {"RETAKE REGION", function() rec_region("retakes") end, "danger"},
    {"INSERT", insert_record, nil},
    {"ALT TAKE", alt_take, nil},
    {"NEXT TAKE", next_take, "danger"},
    {"TOGLI TAKE", undo_last_take, "danger"}
  }
  for i, item in ipairs(labels) do
    local col = (i - 1) % 3
    local row = math.floor((i - 1) / 3)
    if draw_button({x=14 + col * (bw + gap), y=y + row * 46, w=bw, h=bh}, item[1], false, true, clicked, item[3]) then item[2]() end
  end
  local x2 = 466
  if draw_button({x=x2, y=y, w=92, h=34}, "BAD", false, true, clicked, "danger") then add_marker_named("BAD", false) end
  if draw_button({x=x2+102, y=y, w=92, h=34}, "OK", false, true, clicked, "save") then add_marker_named("OK", false) end
  if draw_button({x=x2+204, y=y, w=92, h=34}, "ALT", false, true, clicked) then add_marker_named("ALT", false) end
  if draw_button({x=x2+306, y=y, w=92, h=34}, "NOISE", false, true, clicked) then add_marker_named("NOISE", false) end

  y = y + 50
  if draw_button({x=x2, y=y, w=150, h=34}, state.folder_mode and "Folder Mode" or "Lane Mode TODO", state.folder_mode, true, clicked, "tab") then
    state.folder_mode = true
    warn("Lane Mode e' placeholder futuro nella POC.")
    save_state()
  end
  if draw_button({x=x2+162, y=y, w=150, h=34}, "Navigator", false, true, clicked) then show_navigator() end
  if draw_button({x=x2+324, y=y, w=150, h=34}, "Video", false, true, clicked) then show_video_window() end

  y = y + 54
  set_color(colors.panel)
  gfx.rect(14, y, gfx.w - 28, 64, true)
  set_color(colors.border)
  gfx.rect(14, y, gfx.w - 28, 64, false)
  gfx.setfont(1, "Arial", 15, "b")
  gfx.set(0.82, 0.84, 0.90, 1)
  gfx.x, gfx.y = 28, y + 12
  gfx.drawstr("Reference Wave Viewer")
  gfx.setfont(1, "Arial", 13)
  gfx.x, gfx.y = 28, y + 36
  gfx.drawstr("Placeholder futuro: waveform reference, marker/regioni, playhead, zoom.")
end

local function draw_mini(clicked)
  draw_transport(74, clicked)
  gfx.setfont(1, "Arial", 12, "b")
  gfx.set(0.78, 0.80, 0.85, 1)
  gfx.x, gfx.y = 14, 126
  gfx.drawstr("Traccia: " .. (TRACK_NAMES[state.active_track_key] or "?"))
  if draw_button({x=348, y=124, w=68, h=28}, "Espandi", false, true, clicked, "tab") then set_mode("compact") end
end

local function draw_toolbar(clicked)
  if not state.toolbar or state.mode == "mini" then return end
  local y = gfx.h - TOOLBAR_H + 8
  set_color({0.075, 0.078, 0.090, 1})
  gfx.rect(0, gfx.h - TOOLBAR_H, gfx.w, TOOLBAR_H, true)
  set_color(colors.border)
  gfx.rect(0, gfx.h - TOOLBAR_H, gfx.w, 1, true)
  local buttons = {
    {"Save", ACTION.save_project, "save"},
    {"Undo", ACTION.undo},
    {"Redo", ACTION.redo},
    {"Metro", ACTION.toggle_metronome},
    {"Mixer", ACTION.show_mixer},
    {"Routing", ACTION.show_routing},
    {"FX Chain", ACTION.show_fx_chain},
    {"Notes", ACTION.show_notes},
    {"Markers", ACTION.region_marker_manager},
    {"Navigator", ACTION.navigator},
    {"Video", ACTION.video_window}
  }
  local x, bw, bh, gap = 14, 78, 30, 8
  for _, b in ipairs(buttons) do
    if x + bw > gfx.w - 10 then x = 14; y = y + 38 end
    if draw_button({x=x, y=y, w=bw, h=bh}, b[1], false, true, clicked, b[3]) then run_action(b[2], b[1]) end
    x = x + bw + gap
  end
end

local function draw_countdown()
  if not state.countdown then return end
  local remain = math.max(0, state.countdown.seconds - (reaper.time_precise() - state.countdown.start))
  gfx.set(0, 0, 0, 0.72)
  gfx.rect(0, 0, gfx.w, gfx.h, true)
  gfx.setfont(1, "Arial", 58, "b")
  gfx.set(1, 1, 1, 1)
  local text = string.format("%s %.1f", state.countdown.label or "REC", remain)
  local tw, th = gfx.measurestr(text)
  gfx.x, gfx.y = (gfx.w - tw) * 0.5, (gfx.h - th) * 0.45
  gfx.drawstr(text)
end

local function draw_gui()
  if state.hidden_until and reaper.time_precise() < state.hidden_until then
    set_color(colors.bg)
    gfx.rect(0, 0, gfx.w, gfx.h, true)
    gfx.setfont(1, "Arial", 18, "b")
    gfx.set(0.75, 0.78, 0.84, 1)
    gfx.x, gfx.y = 20, 20
    gfx.drawstr("ZP SOLO nascosto per pochi secondi...")
    gfx.update()
    return
  end

  set_color(colors.bg)
  gfx.rect(0, 0, gfx.w, gfx.h, true)
  local clicked = mouse_clicked()
  draw_status_header(clicked)
  if state.mode == "mini" then draw_mini(clicked)
  elseif state.mode == "expanded" then draw_expanded(clicked)
  else draw_compact(clicked) end
  draw_toolbar(clicked)
  draw_countdown()
  gfx.update()
end

local function init_gui()
  load_state()
  local w, h = mode_size(state.mode)
  if state.mode ~= "mini" and state.toolbar then h = h + TOOLBAR_H end
  local x = tonumber(ext_get("window_x", "")) or 140
  local y = tonumber(ext_get("window_y", "")) or 120
  local dock = tonumber(ext_get("window_dock", "")) or 0
  gfx.init(SCRIPT_TITLE, w, h, dock, x, y)
  gfx.setfont(1, "Arial", 15)
end

local function main_loop()
  local char = gfx.getchar()
  if char < 0 then
    save_window_state()
    save_state()
    restore_reaper_on_exit()
    return
  end
  if char == 27 then
    -- Esc non chiude: evita chiusure accidentali durante sessione.
    state.status = "Esc ignorato: chiudi dalla X finestra se necessario."
  elseif char == 32 and not state.countdown then
    play_transport()
  end

  process_pending()
  try_pin_window()
  draw_gui()
  save_window_state()
  state.mouse_was_down = (gfx.mouse_cap & 1) == 1
  reaper.defer(main_loop)
end

-- Rete di sicurezza: se lo script viene fermato in un altro modo
-- (Action List, ReaScript ricaricato), REAPER torna comunque su.
reaper.atexit(restore_reaper_on_exit)

init_gui()
main_loop()
