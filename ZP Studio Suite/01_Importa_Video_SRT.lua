-- @noindex

-- IMPORTA VIDEO + SRT IN REAPER
-- Linea: ZP Paolo Balestri
-- Suite: ZP Studio Suite for REAPER v1.0.5
-- Credito idea multivideo: da un'idea di Fabio Loi.
-- Distribuzione gratuita.
-- Scegli video e SRT, aggiunge nel progetto corrente traccia video
-- e traccia Rythmo Band Testi con empty items temporizzati.

local sep = package.config:sub(1, 1)

local SUBTITLE_TRACK_NAME = "Rythmo Band Testi"
local NOTES_TRACK_NAME = "Rythmo Band Note"
local SRT_TEMPLATE_NAME = "SRT Track.RTrackTemplate"
local SCRIPT_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "")
local GOBBO_STATE_SECTION = "RythmoBand_Gobbo_State"
local ZP_UI = dofile(SCRIPT_DIR .. "ZP_UI.lua")

local COLOR_VIDEO = 0xE74C3C
local COLOR_SUBS  = 0x3498DB
local COLOR_NOTES = 0xF2C94C
local COLOR_OVERLAP = 0xE53935

local function msg(text)
  reaper.ShowConsoleMsg(tostring(text) .. "\n")
end

local function trim(s)
  local out = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return out
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function copy_file(src, dst)
  if src == dst then return true end
  local input = io.open(src, "rb")
  if not input then return false, "Impossibile leggere: " .. src end
  local output = io.open(dst, "wb")
  if not output then
    input:close()
    return false, "Impossibile scrivere: " .. dst
  end
  while true do
    local block = input:read(1024 * 1024)
    if not block then break end
    output:write(block)
  end
  input:close()
  output:close()
  return true
end

local function dirname(path)
  return path:match("^(.*)[/\\][^/\\]+$") or ""
end

local function basename_without_ext(path)
  local name = path:match("[^/\\]+$") or path
  local out = name:gsub("%.[^%.]+$", "")
  return out
end

local function project_file_path()
  local _, project_path = reaper.EnumProjects(-1, "")
  project_path = trim(project_path or "")
  if project_path == "" then return nil end
  return project_path
end

local function project_dir()
  local path = project_file_path()
  if not path then return nil end
  return dirname(path)
end

local function ensure_saved_project()
  local path = project_file_path()
  if path then return path, project_dir() end

  local choice = reaper.ShowMessageBox(
    "Il progetto deve essere salvato prima dell'import cartella.\n\nVuoi aprire Salva progetto con nome?",
    "ZP Studio Suite",
    4
  )
  if choice ~= 6 then return nil, nil, "Progetto non salvato." end

  reaper.Main_SaveProject(0, true)
  path = project_file_path()
  if not path then return nil, nil, "Salvataggio progetto annullato." end
  return path, project_dir()
end

local function ensure_directory(path)
  if reaper.RecursiveCreateDirectory then
    reaper.RecursiveCreateDirectory(path, 0)
    return true
  end
  return false, "REAPER non espone RecursiveCreateDirectory."
end

local function set_track_color(track, color)
  local r = (color >> 16) & 0xFF
  local g = (color >> 8) & 0xFF
  local b = color & 0xFF
  reaper.SetTrackColor(track, 0x1000000 | (b << 16) | (g << 8) | r)
end

local function find_track_exact(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if track_name == name then return track, i end
  end
  return nil, nil
end

local function native_color(color)
  local r = (color >> 16) & 0xFF
  local g = (color >> 8) & 0xFF
  local b = color & 0xFF
  return reaper.ColorToNative(r, g, b) | 0x1000000
end

local function ext_lower(path)
  return (path:match("%.([^%.\\/]+)$") or ""):lower()
end

local function is_video(path)
  local ext = ext_lower(path)
  return ext == "mp4" or ext == "mov" or ext == "m4v" or ext == "avi" or ext == "mkv"
end

local function subtitle_time_to_seconds(t)
  t = trim(t or "")
  local h, m, s, ms = t:match("^(%d+):(%d%d):(%d%d)[,%.](%d%d%d)$")
  if not h then
    h = 0
    m, s, ms = t:match("^(%d%d):(%d%d)[,%.](%d%d%d)$")
  end
  if not m then return nil end
  return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + tonumber(ms) / 1000
end

local function clean_subtitle_text(text)
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  text = text:gsub("<[^>]->", "")
  text = text:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
  return trim(text)
end

local function parse_subtitle_file(path)
  local f = io.open(path, "rb")
  if not f then return nil, "Impossibile aprire sottotitolo: " .. path end

  local content = f:read("*a")
  f:close()

  content = content:gsub("^\239\187\191", "")
  content = content:gsub("\r\n", "\n"):gsub("\r", "\n")
  content = content:gsub("^WEBVTT[^\n]*\n", "")
  content = content .. "\n\n"

  local cues = {}
  for block in content:gmatch("([^\n].-)\n\n") do
    local lines = {}
    for line in block:gmatch("[^\n]+") do
      table.insert(lines, line)
    end
    local first = trim(lines[1] or "")
    if first == "NOTE" or first:match("^NOTE%s") or first == "STYLE" or first == "REGION" then
      lines = {}
    end

    local time_line_index = nil
    for i, line in ipairs(lines) do
      if line:match("[0-9:%.,]+%s+%-%->%s+[0-9:%.,]+") then
        time_line_index = i
        break
      end
    end

    if time_line_index then
      local start_txt, end_txt = lines[time_line_index]:match("([0-9:%.,]+)%s+%-%->%s+([0-9:%.,]+)")
      local start_pos = subtitle_time_to_seconds(start_txt)
      local end_pos = subtitle_time_to_seconds(end_txt)
      local text_lines = {}
      for i = time_line_index + 1, #lines do
        table.insert(text_lines, lines[i])
      end

      local text = clean_subtitle_text(table.concat(text_lines, "\n"))
      if start_pos and end_pos and end_pos > start_pos and text ~= "" then
        table.insert(cues, {
          start_pos = start_pos,
          end_pos = end_pos,
          text = text
        })
      end
    end
  end

  if #cues == 0 then return nil, "Nessun sottotitolo valido trovato in: " .. path end

  table.sort(cues, function(a, b)
    if a.start_pos == b.start_pos then return a.end_pos < b.end_pos end
    return a.start_pos < b.start_pos
  end)

  return cues
end

local function parse_srt(path)
  return parse_subtitle_file(path)
end

local function create_track(name, color, idx)
  idx = idx or reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local track = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
  set_track_color(track, color)
  return track
end

local function read_file(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  return text
end

local function extract_first_track_chunk(text)
  local current = nil
  local depth = 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    if not current and line:match("^%s*<TRACK") then
      current = {line}
      depth = 1
    elseif current then
      current[#current + 1] = line
      if line:match("^%s*<") then depth = depth + 1 end
      if line:match("^%s*>%s*$") then
        depth = depth - 1
        if depth == 0 then return table.concat(current, "\n") end
      end
    end
  end
  return nil
end

local function clean_template_chunk(chunk)
  return (chunk or ""):gsub("\n%s*TRACKID%s+%b{}\n", "\n")
end

local function create_subtitle_track(name, idx)
  if not reaper.SetTrackStateChunk then return create_track(name, COLOR_SUBS, idx) end
  local template_path = SCRIPT_DIR .. SRT_TEMPLATE_NAME
  local text = read_file(template_path)
  local chunk = text and extract_first_track_chunk(text) or nil
  if not chunk then return create_track(name, COLOR_SUBS, idx) end

  idx = idx or reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local track = reaper.GetTrack(0, idx)
  reaper.SetTrackStateChunk(track, clean_template_chunk(chunk), false)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
  set_track_color(track, COLOR_SUBS)
  return track
end

local function get_or_create_track(name, color, idx)
  local track = find_track_exact(name)
  if track then return track end
  if name == SUBTITLE_TRACK_NAME then return create_subtitle_track(name, idx) end
  return create_track(name, color, idx)
end

local function hide_track(track)
  if not track then return end
  reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
  reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
end

local function setup_subtitle_track(track)
  if not track then return end
  reaper.SetMediaTrackInfo_Value(track, "B_FREEMODE", 1)
  reaper.SetMediaTrackInfo_Value(track, "I_FREEMODE", 1)
  reaper.SetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE", 120)
end

local function refresh_track_visibility()
  if reaper.TrackList_AdjustWindows then reaper.TrackList_AdjustWindows(false) end
  reaper.UpdateArrange()
end

local function build_missing_peaks_after_import()
  reaper.UpdateArrange()
  reaper.Main_OnCommand(40047, 0) -- Peaks: Build any missing peaks
  reaper.UpdateArrange()
end

local function add_video_item(track, video_path, start_pos)
  local source = reaper.PCM_Source_CreateFromFile(video_path)
  if not source then return nil, "REAPER non riesce a caricare il video: " .. video_path end

  local item = reaper.AddMediaItemToTrack(track)
  local take = reaper.AddTakeToMediaItem(item)
  reaper.SetMediaItemTake_Source(take, source)
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", basename_without_ext(video_path), true)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", start_pos)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", reaper.GetMediaSourceLength(source))
  reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "RythmoBand video start=" .. tostring(start_pos), true)
  return item
end

local function add_empty_midi_reference_item(track, name, start_pos, length)
  local end_pos = start_pos + math.max(1, length or 1)
  local item = nil
  if reaper.CreateNewMIDIItemInProj then
    item = reaper.CreateNewMIDIItemInProj(track, start_pos, end_pos, false)
  end
  if not item then
    item = reaper.AddMediaItemToTrack(track)
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", start_pos)
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", math.max(1, length or 1))
  end
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", native_color(COLOR_VIDEO))
  reaper.GetSetMediaItemInfo_String(item, "P_NAME", name, true)
  reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "RythmoBand SRT-only MIDI reference", true)
  local take = reaper.GetActiveTake(item)
  if take then reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true) end
  return item
end

local function add_manual_text_item(track, text, start_pos, length)
  local item = reaper.AddMediaItemToTrack(track)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", start_pos)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", math.max(0.2, length or 5.0))
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", native_color(COLOR_SUBS))
  text = trim(text or "")
  if text == "" then text = "TESTO" end
  reaper.GetSetMediaItemInfo_String(item, "P_NOTES", text, true)
  reaper.GetSetMediaItemInfo_String(item, "P_NAME", text:gsub("[\r\n]+", " / "), true)
  return item
end

local function video_file_length(video_path)
  local source = reaper.PCM_Source_CreateFromFile(video_path)
  if not source then return nil end
  return reaper.GetMediaSourceLength(source)
end

local function next_free_video_position(track, desired_start, duration, gap)
  desired_start = math.max(0, desired_start or 0)
  duration = math.max(0, duration or 0)
  gap = math.max(0, gap or 0)
  if not track or duration <= 0 then return desired_start end

  local ranges = {}
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if len and len > 0 then
      table.insert(ranges, { start_pos = pos, end_pos = pos + len })
    end
  end

  table.sort(ranges, function(a, b) return a.start_pos < b.start_pos end)

  local candidate = desired_start
  local epsilon = 0.000001
  for _, range in ipairs(ranges) do
    if candidate + duration <= range.start_pos + epsilon then
      return candidate
    end
    if candidate < range.end_pos and candidate + duration > range.start_pos then
      candidate = range.end_pos + gap
    end
  end
  return candidate
end

local zp_choice_dialog

local function project_end_position()
  local project_end = 0
  for t = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, t)
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION") or 0
      local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
      if len > 0 then project_end = math.max(project_end, pos + len) end
    end
  end
  return project_end
end

local function range_overlaps_project(start_pos, duration)
  duration = math.max(0, duration or 0)
  if duration <= 0 then return false end
  local end_pos = start_pos + duration
  for t = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, t)
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION") or 0
      local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
      if len > 0 and start_pos < pos + len and end_pos > pos then
        return true
      end
    end
  end
  return false
end

local function resolve_single_video_position(desired_start, duration)
  desired_start = math.max(0, desired_start or 0)
  duration = math.max(0, duration or 0)
  if duration <= 0 or not range_overlaps_project(desired_start, duration) then
    return desired_start, "playhead"
  end

  local choice = zp_choice_dialog({
    title = "ZP Studio Suite - Sovrapposizione",
    heading = "La posizione scelta e' gia' occupata",
    message = "Il video cadrebbe sopra item gia' presenti in timeline. Puoi inserirlo qui, utile quando devi sovrapporre il video a un doppiaggio gia' registrato, oppure mandarlo in fondo al progetto con 10 secondi di respiro.",
    button_w = 150,
    buttons = {
      { label = "Sovrapponi qui", value = "overlap", style = "play_select" },
      { label = "Fondo +10s", value = "project_end", style = "play" },
      { label = "Annulla", value = "abort" },
    },
    cancel_value = "abort"
  })
  if choice == "overlap" then return desired_start, "overlap" end
  if choice == "project_end" then return project_end_position() + 10.0, "project_end" end
  return nil, "abort"
end

local function draw_wrapped_text(text, x, y, max_w, line_h, max_lines)
  text = tostring(text or "")
  local lines = {}
  for paragraph in (text .. "\n"):gmatch("(.-)\n") do
    local current = ""
    for word in paragraph:gmatch("%S+") do
      local candidate = current == "" and word or (current .. " " .. word)
      if gfx.measurestr(candidate) <= max_w then
        current = candidate
      else
        if current ~= "" then lines[#lines + 1] = current end
        current = word
      end
    end
    if current ~= "" then lines[#lines + 1] = current end
    if paragraph == "" then lines[#lines + 1] = "" end
  end
  local count = math.min(#lines, max_lines or #lines)
  for i = 1, count do
    gfx.x = x
    gfx.y = y + (i - 1) * line_h
    gfx.drawstr(ZP_UI.fit_text(lines[i], max_w))
  end
end

zp_choice_dialog = function(opts)
  opts = opts or {}
  local buttons = opts.buttons or {}
  if #buttons == 0 then return opts.cancel_value or "abort", false end

  local lines = {}
  if opts.heading and opts.heading ~= "" then
    lines[#lines + 1] = tostring(opts.heading)
    lines[#lines + 1] = ""
  end
  if opts.message and opts.message ~= "" then
    lines[#lines + 1] = tostring(opts.message)
    lines[#lines + 1] = ""
  end

  lines[#lines + 1] = "Opzioni disponibili:"
  for i, btn in ipairs(buttons) do
    lines[#lines + 1] = tostring(i) .. " - " .. tostring(btn.label or btn.value or "Scelta")
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Nella prossima casella inserisci solo il numero della scelta."

  reaper.ShowMessageBox(table.concat(lines, "\n"), opts.title or "ZP Studio Suite", 0)

  local ok, value = reaper.GetUserInputs(
    opts.title or "ZP Studio Suite",
    1,
    "Numero scelta 1-" .. tostring(#buttons) .. ":,extrawidth=260",
    "1"
  )
  if not ok then return opts.cancel_value or "abort", false end

  local index = tonumber((trim(value):match("%d+"))) or 0
  local button = buttons[index]
  if not button then
    reaper.ShowMessageBox("Scelta non valida. Operazione annullata.", opts.title or "ZP Studio Suite", 0)
    return opts.cancel_value or "abort", false
  end

  local result = button.value or (opts.cancel_value or "abort")
  local apply_all = false
  if opts.apply_all_label and result ~= (opts.cancel_value or "abort") then
    local apply = reaper.ShowMessageBox(
      tostring(opts.apply_all_label) .. "?",
      opts.title or "ZP Studio Suite",
      4
    )
    apply_all = apply == 6
  end
  return result, apply_all
end

local function add_video_region(name, start_pos, end_pos)
  if end_pos <= start_pos then return end
  reaper.AddProjectMarker2(0, true, start_pos, end_pos, name, -1, 0)
end

local function show_video_window()
  local state = reaper.GetToggleCommandState(50125) -- Video: Show/hide video window
  if state == 0 then reaper.Main_OnCommand(50125, 0) end
end

local function osara_active()
  return type(reaper.osara_outputMessage) == "function"
end

local function gobbo_is_open()
  local now = reaper.time_precise()
  local vertical_ts = tonumber(reaper.GetExtState(GOBBO_STATE_SECTION, "vertical_ts")) or 0
  local horizontal_ts = tonumber(reaper.GetExtState(GOBBO_STATE_SECTION, "horizontal_ts")) or 0
  return (now - vertical_ts) < 3.0 or (now - horizontal_ts) < 3.0
end

local function point_in_rect(x, y, rx, ry, rw, rh)
  return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function draw_button(rect, label, active, enabled, clicked, style)
  return ZP_UI.draw_button(rect, label, active, enabled, clicked, style)
end

local function draw_text_box(rect, text, muted)
  gfx.set(0.09, 0.10, 0.15, 1)
  gfx.rect(rect.x, rect.y, rect.w, rect.h, true)
  gfx.set(0.30, 0.34, 0.46, 1)
  gfx.rect(rect.x, rect.y, rect.w, rect.h, false)
  gfx.set(muted and 0.58 or 0.92, muted and 0.58 or 0.90, muted and 0.66 or 0.95, 1)
  gfx.x = rect.x + 10
  gfx.y = rect.y + math.floor((rect.h - 15) / 2)
  gfx.drawstr(ZP_UI.fit_text(text or "", rect.w - 20))
end

local function fit_text(text, max_w)
  text = tostring(text or "")
  if gfx.measurestr(text) <= max_w then return text end

  local suffix = "..."
  local suffix_w = gfx.measurestr(suffix)
  local out = ""
  for i = 1, #text do
    local candidate = text:sub(1, i)
    if gfx.measurestr(candidate) + suffix_w > max_w then break end
    out = candidate
  end
  out = out:gsub("%s+$", "")
  if out == "" then return suffix end
  return out .. suffix
end

local function basename(path)
  return path:match("[^/\\]+$") or path
end

local function is_subtitle_file(path)
  local ext = ext_lower(path)
  return ext == "srt" or ext == "vtt"
end

local function subtitle_extension(path)
  local ext = ext_lower(path)
  if ext == "vtt" then return "vtt" end
  return "srt"
end

local function subtitle_dialog_ext()
  return ""
end

local function is_srt(path)
  return is_subtitle_file(path)
end

local function find_matching_srt(video_path)
  local base_path = dirname(video_path) .. sep .. basename_without_ext(video_path)
  local candidate_srt = base_path .. ".srt"
  if file_exists(candidate_srt) then return candidate_srt end
  local candidate_vtt = base_path .. ".vtt"
  if file_exists(candidate_vtt) then return candidate_vtt end
  return nil
end

local function quote(path)
  return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end

local function scan_folder(folder)
  local files = {}
  local cmd = "find " .. quote(folder) .. " -maxdepth 1 -type f"
  local p = io.popen(cmd)
  if not p then return files end
  for path in p:lines() do table.insert(files, path) end
  p:close()
  return files
end

local function find_pairs(folder)
  local srts_by_base = {}
  local videos = {}
  for _, path in ipairs(scan_folder(folder)) do
    local ext = ext_lower(path)
    local base = basename_without_ext(path)
    if is_subtitle_file(path) then
      local key = base:lower()
      if ext == "srt" or not srts_by_base[key] then srts_by_base[key] = path end
    elseif is_video(path) then
      table.insert(videos, path)
    end
  end

  table.sort(videos, function(a, b) return basename(a):lower() < basename(b):lower() end)

  local pairs = {}
  local skipped = {}
  for _, video in ipairs(videos) do
    local base = basename_without_ext(video)
    local srt = srts_by_base[base:lower()]
    if srt then
      table.insert(pairs, { video = video, srt = srt, base = base })
    else
      table.insert(skipped, basename(video))
    end
  end
  return pairs, skipped
end

local function scan_video_files(folder)
  local videos = {}
  for _, path in ipairs(scan_folder(folder)) do
    if is_video(path) then table.insert(videos, path) end
  end
  table.sort(videos, function(a, b) return basename(a):lower() < basename(b):lower() end)
  return videos
end

local function select_folder_dialog(title, start_dir)
  start_dir = trim(start_dir or "")
  if reaper.JS_Dialog_BrowseForFolder then
    local ok, folder_path = reaper.JS_Dialog_BrowseForFolder(title or "Scegli cartella", start_dir)
    if ok and folder_path and trim(folder_path) ~= "" then return trim(folder_path) end
    return nil
  end
  local ok, folder_path = reaper.GetUserInputs(title or "Scegli cartella", 1, "Percorso cartella:,extrawidth=560", start_dir)
  if ok and folder_path and trim(folder_path) ~= "" then return trim(folder_path) end
  return nil
end

local function unique_media_path(media_dir, src_path)
  local name = basename(src_path)
  local candidate = media_dir .. sep .. name
  if not file_exists(candidate) then return candidate end

  local stem = name:gsub("%.[^%.]+$", "")
  local ext = name:match("(%.[^%.]+)$") or ""
  local index = 2
  while true do
    candidate = media_dir .. sep .. stem .. "_" .. tostring(index) .. ext
    if not file_exists(candidate) then return candidate end
    index = index + 1
  end
end

local function normalize_path(path)
  return tostring(path or ""):gsub("\\", "/"):gsub("/+$", "")
end

local function path_is_inside(path, folder)
  local p = normalize_path(path)
  local f = normalize_path(folder)
  if p == "" or f == "" then return false end
  return p == f or p:sub(1, #f + 1) == f .. "/"
end

local function file_size(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  f:close()
  return size
end

local function project_candidate_dirs(project_folder, media_dir)
  local dirs = {}
  local seen = {}
  local function add(dir)
    dir = tostring(dir or "")
    if dir == "" then return end
    local key = normalize_path(dir)
    if key ~= "" and not seen[key] then
      seen[key] = true
      dirs[#dirs + 1] = dir
    end
  end
  add(project_folder)
  add(media_dir)
  local media_parent = dirname(media_dir)
  if basename(media_parent) == "Media" then add(media_parent) end
  return dirs
end

local function find_existing_project_file(src_path, project_folder, media_dir, preferred_name)
  local wanted_name = preferred_name or basename(src_path)
  local src_size = file_size(src_path)
  local fallback = nil
  for _, dir in ipairs(project_candidate_dirs(project_folder, media_dir)) do
    local candidate = dir .. sep .. wanted_name
    if file_exists(candidate) then
      local candidate_size = file_size(candidate)
      if src_size and candidate_size == src_size then
        return candidate, true
      end
      fallback = fallback or candidate
    end
  end
  return fallback, false
end

local function ask_project_file_policy(src_path, existing_path, same_size, copy_state)
  copy_state = copy_state or {}
  if copy_state.policy then return copy_state.policy end

  local size_note = same_size and "Dimensione uguale: sembra lo stesso file." or "Attenzione: dimensione diversa o non verificabile."
  local policy, apply_all = zp_choice_dialog({
    title = "ZP Studio Suite - File gia presente",
    heading = "Occhio: questo file sembra gia' nel progetto",
    message = "File: " .. basename(src_path) .. "\nTrovato in: " .. existing_path .. "\n" .. size_note .. "\nChe facciamo?",
    apply_all_label = "Applica a tutti",
    button_w = 132,
    buttons = {
      { label = "Usa questo", value = "use_existing", style = "play_select" },
      { label = "Sovrascrivi", value = "overwrite", style = "danger" },
      { label = "Tieni entrambi", value = "copy_new", style = "tab" },
      { label = "Annulla", value = "abort" },
    },
    cancel_value = "abort"
  })
  if apply_all and policy ~= "abort" then copy_state.policy = policy end
  return policy
end

local function ensure_project_media_dir(media_dir)
  local dir_ok, dir_err = ensure_directory(media_dir)
  if not dir_ok then return false, dir_err or ("Impossibile creare cartella: " .. media_dir) end
  return true, nil
end

local function resolve_project_copy(src_path, project_folder, media_dir, copy_state, preferred_name)
  if path_is_inside(src_path, project_folder) then
    return src_path, "already_in_project"
  end

  local existing, same_size = find_existing_project_file(src_path, project_folder, media_dir, preferred_name)
  if existing then
    local policy = ask_project_file_policy(src_path, existing, same_size, copy_state)
    if policy == "use_existing" then
      return existing, "used_existing"
    elseif policy == "overwrite" then
      local ok, err = copy_file(src_path, existing)
      if not ok then return nil, err end
      return existing, "overwritten"
    elseif policy == "copy_new" then
      local ok_dir, dir_err = ensure_project_media_dir(media_dir)
      if not ok_dir then return nil, dir_err end
      local dst = unique_media_path(media_dir, preferred_name or src_path)
      local ok, err = copy_file(src_path, dst)
      if not ok then return nil, err end
      return dst, "copied_new"
    else
      return nil, "Operazione annullata."
    end
  end

  local ok_dir, dir_err = ensure_project_media_dir(media_dir)
  if not ok_dir then return nil, dir_err end
  local dst = media_dir .. sep .. (preferred_name or basename(src_path))
  if file_exists(dst) then dst = unique_media_path(media_dir, preferred_name or src_path) end
  local ok, err = copy_file(src_path, dst)
  if not ok then return nil, err end
  return dst, "copied"
end

local function copy_pair_to_media(pair, project_folder, media_dir, copy_state)
  local video_dst, video_err = resolve_project_copy(pair.video, project_folder, media_dir, copy_state)
  if not video_dst then return nil, video_err end

  local srt_name = basename_without_ext(video_dst) .. "." .. subtitle_extension(pair.srt)
  local srt_dst, srt_err = resolve_project_copy(pair.srt, project_folder, media_dir, copy_state, srt_name)
  if not srt_dst then return nil, srt_err end

  return { video = video_dst, srt = srt_dst, base = basename_without_ext(video_dst) }
end

local function copy_single_to_project(video_path, srt_path)
  local _, project_folder, project_err = ensure_saved_project()
  if not project_folder then return nil, nil, project_err or "Progetto non salvato." end

  local media_dir = project_folder .. sep .. "Media"
  local copy_state = {}
  local video_dst, video_err = resolve_project_copy(video_path, project_folder, media_dir, copy_state)
  if not video_dst then return nil, nil, video_err end

  if srt_path and srt_path ~= "" then
    local srt_name = basename_without_ext(video_dst) .. "." .. subtitle_extension(srt_path)
    local srt_dst, srt_err = resolve_project_copy(srt_path, project_folder, media_dir, copy_state, srt_name)
    if not srt_dst then return nil, nil, srt_err end
    return video_dst, srt_dst, nil
  end

  return video_dst, "", nil
end

local function copy_srt_to_project(srt_path)
  local _, project_folder, project_err = ensure_saved_project()
  if not project_folder then return nil, project_err or "Progetto non salvato." end

  local media_dir = project_folder .. sep .. "Media"
  local dir_ok, dir_err = ensure_directory(media_dir)
  if not dir_ok then return nil, dir_err or ("Impossibile creare cartella: " .. media_dir) end

  local srt_dst = unique_media_path(media_dir, srt_path)
  local ok_srt, err_srt = copy_file(srt_path, srt_dst)
  if not ok_srt then return nil, err_srt end

  return srt_dst, nil
end

local function choose_import_options_numeric()
  local ok, csv = reaper.GetUserInputs(
    "ZP Studio Suite",
    1,
    "Correggi overlap? 1 si 0 no:,extrawidth=380",
    "1"
  )
  if not ok then return nil end

  local fix_overlaps = trim(csv) ~= "0"
  return fix_overlaps
end

local function choose_paths_numeric()
  local ok_video, video_path = reaper.GetUserFileNameForRead("", "Scegli il video da importare", "")
  if not ok_video then return nil end
  video_path = trim(video_path)

  if not file_exists(video_path) then return nil, "Video non trovato:\n" .. video_path end
  if not is_video(video_path) then
    return nil, "Il file scelto non sembra un video supportato:\n" .. video_path ..
      "\n\nEstensioni supportate: mp4, mov, m4v, avi, mkv"
  end

  local ok_srt, srt_path = reaper.GetUserFileNameForRead(dirname(video_path), "Scegli SRT/VTT", subtitle_dialog_ext())
  if not ok_srt then return nil end
  srt_path = trim(srt_path)

  if not file_exists(srt_path) then return nil, "Sottotitolo non trovato:\n" .. srt_path end
  if not is_srt(srt_path) then return nil, "Il file scelto non sembra un SRT/VTT:\n" .. srt_path end

  local fix_overlaps = choose_import_options_numeric()
  if fix_overlaps == nil then return nil end

  return video_path, srt_path, fix_overlaps
end

local function open_import_bridge(on_done)
  if not gfx or not gfx.init then return false end

  local mode = _G.RYTHMOBAND_IMPORT_MODE == "batch" and "batch" or "single"
  local fix_overlaps = true
  local video_path = ""
  local srt_path = ""
  local folder = ""
  local gap = 10
  local manual_len = 5
  local copy_files = true
  local save_after = true
  local warning = ""
  local last_mouse_down = false
  local existing_gobbo = gobbo_is_open()

  gfx.init("ZP Studio Suite v1.0.5 - Import Video/SRT", 790, 520)
  gfx.setfont(1, "Arial", 15)

  local function set_video_path(path)
    path = trim(path or "")
    if path == "" then return end
    if not is_video(path) then
      warning = "Il file scelto non sembra un video supportato."
      return
    end
    video_path = path
    warning = ""
    local matched = find_matching_srt(video_path)
    if matched and srt_path == "" then srt_path = matched end
  end

  local function choose_video()
    local ok, path = reaper.GetUserFileNameForRead(dirname(video_path), "Scegli video", "")
    if not ok then return end
    set_video_path(path)
  end

  local function choose_video_from_folder()
    local start_dir = dirname(video_path)
    if start_dir == "" then start_dir = folder end
    local selected_folder = select_folder_dialog("Scegli cartella che contiene video", start_dir)
    if not selected_folder then return end
    local videos = scan_video_files(selected_folder)
    if #videos == 0 then
      warning = "Nessun video trovato nella cartella scelta."
      return
    end
    if #videos == 1 then
      set_video_path(videos[1])
      return
    end

    local lines = { "Video trovati nella cartella:", "" }
    for i = 1, math.min(12, #videos) do
      lines[#lines + 1] = tostring(i) .. " - " .. basename(videos[i])
    end
    if #videos > 12 then lines[#lines + 1] = "... altri " .. tostring(#videos - 12) .. " video" end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Nella prossima casella inserisci il numero del video."
    reaper.ShowMessageBox(table.concat(lines, "\n"), "ZP Studio Suite - Video nella cartella", 0)

    local ok, value = reaper.GetUserInputs("ZP Studio Suite", 1, "Numero video 1-" .. tostring(#videos) .. ":,extrawidth=260", "1")
    if not ok then return end
    local index = tonumber((trim(value):match("%d+"))) or 0
    if not videos[index] then
      warning = "Numero video non valido."
      return
    end
    set_video_path(videos[index])
  end

  local function choose_srt()
    local start_dir = dirname(srt_path)
    if start_dir == "" then start_dir = dirname(video_path) end
    local ok, path = reaper.GetUserFileNameForRead(start_dir, "Scegli SRT/VTT", subtitle_dialog_ext())
    if not ok then return end
    path = trim(path)
    if not is_srt(path) then
      warning = "Il file scelto non sembra un SRT/VTT."
      return
    end
    srt_path = path
    warning = ""
  end

  local function choose_folder_from_video()
    local selected_folder = select_folder_dialog("Scegli cartella con video e SRT/VTT", folder)
    if not selected_folder then return end
    folder = selected_folder
    local pairs, skipped = find_pairs(folder)
    if #pairs == 0 then
      if #skipped > 0 then
        warning = "Video trovati, ma senza SRT/VTT corrispondente."
      else
        warning = "Nessun video trovato nella cartella scelta."
      end
      return
    end
    warning = ""
  end

  local function loop()
    local ch = gfx.getchar()
    if ch < 0 or ch == 27 then gfx.quit() return end
    local mouse_down = (gfx.mouse_cap & 1) == 1
    local clicked = mouse_down and not last_mouse_down
    last_mouse_down = mouse_down
    existing_gobbo = gobbo_is_open()

    ZP_UI.fill_background()
    gfx.set(0.10, 0.42, 0.48, 1)
    gfx.rect(22, 18, 34, 34, true)
    gfx.set(0.92, 0.88, 0.70, 1)
    gfx.triangle(36, 25, 36, 42, 46, 33, true)
    gfx.rect(28, 42, 22, 4, true)
    gfx.set(0.92, 0.88, 0.78, 1)
    gfx.x = 66
    gfx.y = 20
    gfx.setfont(1, "Arial", 20)
    gfx.drawstr("Import video/SRT-VTT")
    gfx.setfont(1, "Arial", 12)
    gfx.set(0.56, 0.72, 0.86, 1)
    gfx.x = 66
    gfx.y = 42
    gfx.drawstr("ZP Studio Suite v1.0.5 - Paolo Balestri & Fabio Loi")
    gfx.setfont(1, "Arial", 15)
    gfx.set(0.68, 0.66, 0.74, 1)
    gfx.x = 22
    gfx.y = 62
    gfx.drawstr("Importa video+SRT/VTT, una cartella, solo SRT o una traccia testo vuota.")
    ZP_UI.draw_help_button({ x = gfx.w - 54, y = 18, w = 34, h = 28 }, clicked, "zp-import")

    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x = 22
    gfx.y = 86
    gfx.drawstr("Modalita'")
    if draw_button({ x = 22, y = 110, w = 126, h = 38 }, "Singolo", mode == "single", true, clicked, "tab") then mode = "single" end
    if draw_button({ x = 158, y = 110, w = 126, h = 38 }, "Cartella", mode == "batch", true, clicked, "tab") then mode = "batch" end
    if draw_button({ x = 294, y = 110, w = 142, h = 38 }, "Solo SRT/VTT", mode == "srt_only", true, clicked, "tab") then mode = "srt_only" end
    if draw_button({ x = 446, y = 110, w = 154, h = 38 }, "Traccia testo", mode == "text_empty", true, clicked, "tab") then mode = "text_empty" end

    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x = 22
    gfx.y = 170
    gfx.drawstr("File")

    if mode == "single" then
      if draw_button({ x = 22, y = 194, w = 132, h = 38 }, "Scegli video", false, true, clicked) then choose_video() end
      if draw_button({ x = 164, y = 194, w = 118, h = 38 }, "Da cartella", false, true, clicked) then choose_video_from_folder() end
      gfx.set(0.92, 0.90, 0.95, 1)
      gfx.x = 300
      gfx.y = 205
      gfx.drawstr(video_path ~= "" and fit_text(basename(video_path), 450) or "Nessun video scelto")

      if draw_button({ x = 22, y = 244, w = 150, h = 38 }, "Scegli SRT/VTT", false, true, clicked) then choose_srt() end
      gfx.set(0.92, 0.90, 0.95, 1)
      gfx.x = 190
      gfx.y = 255
      gfx.drawstr(srt_path ~= "" and fit_text(basename(srt_path), 530) or "Nessun SRT/VTT scelto")
    elseif mode == "batch" then
      if draw_button({ x = 22, y = 194, w = 210, h = 38 }, "Scegli cartella", false, true, clicked) then choose_folder_from_video() end
      draw_text_box({ x = 250, y = 194, w = 500, h = 38 }, folder ~= "" and folder or "Nessuna cartella scelta", folder == "")

      if folder ~= "" then
        local pairs, skipped = find_pairs(folder)
        gfx.set(0.68, 0.82, 0.70, 1)
        gfx.x = 250
        gfx.y = 242
        gfx.drawstr(string.format("Coppie video+SRT: %d  |  Video senza SRT: %d", #pairs, #skipped))
        gfx.set(0.70, 0.74, 0.82, 1)
        for i = 1, math.min(3, #pairs) do
          gfx.x = 250
          gfx.y = 262 + (i - 1) * 18
          gfx.drawstr(fit_text("- " .. basename(pairs[i].video), 470))
        end
      end

      gfx.set(0.86, 0.82, 0.70, 1)
      gfx.x = 22
      gfx.y = 302
      gfx.drawstr("Pausa tra video")
      if draw_button({ x = 22, y = 322, w = 52, h = 38 }, "-", false, gap > 0, clicked) then gap = math.max(0, gap - 1) end
      draw_text_box({ x = 86, y = 322, w = 96, h = 38 }, tostring(gap) .. " sec", false)
      if draw_button({ x = 194, y = 322, w = 52, h = 38 }, "+", false, true, clicked) then gap = gap + 1 end
    elseif mode == "srt_only" then
      if draw_button({ x = 22, y = 194, w = 150, h = 38 }, "Scegli SRT/VTT", false, true, clicked) then choose_srt() end
      gfx.set(0.92, 0.90, 0.95, 1)
      gfx.x = 190
      gfx.y = 205
      gfx.drawstr(srt_path ~= "" and fit_text(basename(srt_path), 530) or "Nessun SRT/VTT scelto")

      gfx.set(0.68, 0.66, 0.74, 1)
      gfx.x = 22
      gfx.y = 255
      gfx.drawstr("Crea una regione e un item vuoto sulla traccia VIDEO, usando il TC del sottotitolo.")
    else
      gfx.set(0.92, 0.90, 0.95, 1)
      gfx.x = 22
      gfx.y = 205
      gfx.drawstr("Crea/mostra la traccia testi e inserisce un item manuale alla playhead.")
      gfx.set(0.86, 0.82, 0.70, 1)
      gfx.x = 22
      gfx.y = 255
      gfx.drawstr("Durata item")
      if draw_button({ x = 122, y = 244, w = 52, h = 38 }, "-", false, manual_len > 1, clicked) then manual_len = math.max(1, manual_len - 1) end
      gfx.set(0.92, 0.90, 0.95, 1)
      gfx.x = 194
      gfx.y = 255
      gfx.drawstr(tostring(manual_len) .. " sec")
      if draw_button({ x = 274, y = 244, w = 52, h = 38 }, "+", false, true, clicked) then manual_len = manual_len + 1 end
    end

    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x = 22
    gfx.y = 316
    gfx.drawstr("Gobbo")

    if existing_gobbo then
      gfx.set(0.68, 0.66, 0.74, 1)
      gfx.x = 22
      gfx.y = 344
      gfx.drawstr("Gia' aperto: l'import usera' quello.")
    else
      gfx.set(0.68, 0.66, 0.74, 1)
      gfx.x = 22
      gfx.y = 344
      gfx.drawstr("Aprilo dalla toolbar quando ti serve.")
    end

    if draw_button({ x = 22, y = 402, w = 220, h = 38 }, mode == "batch" and "Segnala overlap" or "Correggi overlap", fix_overlaps, true, clicked, "tab") then
      fix_overlaps = not fix_overlaps
    end
    if draw_button({ x = 260, y = 402, w = 176, h = 38 }, "Copia nel progetto", copy_files, mode ~= "batch" and mode ~= "text_empty", clicked, "tab") then
      copy_files = not copy_files
      if copy_files then save_after = true end
    end
    if draw_button({ x = 454, y = 402, w = 138, h = 38 }, "Salva progetto", save_after, true, clicked, "tab") then
      save_after = not save_after
    end

    if warning ~= "" then
      gfx.set(0.95, 0.50, 0.40, 1)
      gfx.x = 604
      gfx.y = 414
      gfx.drawstr(fit_text(warning, 160))
    end

    local ready = false
    if mode == "single" then
      local has_valid_video = video_path ~= "" and file_exists(video_path) and is_video(video_path)
      local has_no_subtitle = srt_path == ""
      local has_valid_subtitle = srt_path ~= "" and file_exists(srt_path) and is_srt(srt_path)
      ready = has_valid_video and (has_no_subtitle or has_valid_subtitle)
    elseif mode == "batch" then
      ready = folder ~= ""
    elseif mode == "srt_only" then
      ready = srt_path ~= "" and file_exists(srt_path) and is_srt(srt_path)
    else
      ready = true
    end

    if draw_button({ x = 548, y = 452, w = 96, h = 38 }, "Importa", false, ready, clicked, "play") then
      gfx.quit()
      if mode == "single" then
        on_done({ mode = "single", video = video_path, srt = srt_path, fix_overlaps = fix_overlaps, copy_files = copy_files, save_after = save_after })
      elseif mode == "batch" then
        on_done({ mode = "batch", folder = folder, gap = gap, flag_overlaps = fix_overlaps, save_after = save_after })
      elseif mode == "srt_only" then
        on_done({ mode = "srt_only", srt = srt_path, fix_overlaps = fix_overlaps, copy_files = copy_files, save_after = save_after })
      else
        on_done({ mode = "text_empty", item_len = manual_len, save_after = save_after })
      end
      return
    end
    if draw_button({ x = 662, y = 452, w = 96, h = 38 }, "Annulla", false, true, clicked) then
      gfx.quit()
      return
    end
    gfx.update()
    reaper.defer(loop)
  end

  reaper.defer(loop)
  return true
end

local set_item_srt_metadata

local function run_create_empty_text_track(item_len, save_after)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local subs_track = get_or_create_track(SUBTITLE_TRACK_NAME, COLOR_SUBS)
  setup_subtitle_track(subs_track)
  local pos = reaper.GetCursorPosition()
  local item = add_manual_text_item(subs_track, "TESTO", pos, item_len or 5.0)

  reaper.Main_OnCommand(40289, 0) -- Unselect all items
  if item then reaper.SetMediaItemSelected(item, true) end
  reaper.SetOnlyTrackSelected(subs_track)
  refresh_track_visibility()

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ZP Studio Suite crea traccia testo/manual item", -1)
  if save_after then reaper.Main_SaveProject(0, false) end

  reaper.ShowMessageBox(
    "Traccia testo pronta.\n\nCreato item manuale alla playhead: TESTO\nDurata: " .. tostring(item_len or 5) .. " sec" ..
    (save_after and "\nProgetto salvato." or "\nProgetto non salvato."),
    "ZP Studio Suite",
    0
  )
end

local function add_subtitle_item(track, cue, index, block_start, previous_end, fix_overlaps, srt_path)
  local start_pos = block_start + cue.start_pos
  local end_pos = block_start + cue.end_pos

  if fix_overlaps and previous_end and start_pos < previous_end then
    start_pos = previous_end
  end

  if end_pos <= start_pos then
    return previous_end, false
  end

  local item = reaper.AddMediaItemToTrack(track)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", start_pos)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", end_pos - start_pos)
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", native_color(COLOR_SUBS))
  reaper.GetSetMediaItemInfo_String(item, "P_NOTES", cue.text, true)
  set_item_srt_metadata(item, srt_path, index)

  local one_line = cue.text:gsub("\n+", " / ")
  if #one_line > 70 then one_line = one_line:sub(1, 67) .. "..." end
  reaper.GetSetMediaItemInfo_String(item, "P_NAME", string.format("%03d %s", index, one_line), true)

  return end_pos, true
end

function set_item_srt_metadata(item, srt_path, cue_index)
  if not item then return end
  reaper.GetSetMediaItemInfo_String(item, "P_EXT:RythmoBand_SRT_PATH", srt_path or "", true)
  reaper.GetSetMediaItemInfo_String(item, "P_EXT:RythmoBand_SRT_FILE", basename(srt_path or ""), true)
  reaper.GetSetMediaItemInfo_String(item, "P_EXT:RythmoBand_SRT_CUE", tostring(cue_index or ""), true)
end

local function place_item_in_visual_lane(item, is_overlap)
  if is_overlap then
    reaper.SetMediaItemInfo_Value(item, "F_FREEMODE_Y", 0.52)
    reaper.SetMediaItemInfo_Value(item, "F_FREEMODE_H", 0.46)
  else
    reaper.SetMediaItemInfo_Value(item, "F_FREEMODE_Y", 0.02)
    reaper.SetMediaItemInfo_Value(item, "F_FREEMODE_H", 0.46)
  end
end

local function add_batch_subtitle_item(track, cue, index, block_start, previous_end, flag_overlaps, srt_path)
  local start_pos = block_start + cue.start_pos
  local end_pos = block_start + cue.end_pos

  if end_pos <= start_pos then return previous_end, false end
  local is_overlap = flag_overlaps and previous_end and start_pos < previous_end

  local item = reaper.AddMediaItemToTrack(track)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", start_pos)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", end_pos - start_pos)
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", native_color(is_overlap and COLOR_OVERLAP or COLOR_SUBS))
  place_item_in_visual_lane(item, is_overlap)
  reaper.GetSetMediaItemInfo_String(item, "P_NOTES", cue.text, true)
  set_item_srt_metadata(item, srt_path, index)

  local one_line = cue.text:gsub("\n+", " / ")
  if #one_line > 70 then one_line = one_line:sub(1, 67) .. "..." end
  local prefix = is_overlap and "OVERLAP " or ""
  reaper.GetSetMediaItemInfo_String(item, "P_NAME", string.format("%s%03d %s", prefix, index, one_line), true)

  local running_end = previous_end and math.max(previous_end, end_pos) or end_pos
  return running_end, true, is_overlap
end

local function run_import(video_path, srt_path, fix_overlaps, copy_files, save_after)
  local copied_files = false
  if copy_files then
    local local_video, local_srt, copy_err = copy_single_to_project(video_path, srt_path)
    if not local_video then
      reaper.ShowMessageBox(copy_err or "Copia nel progetto non riuscita.", "ZP Studio Suite", 0)
      return
    end
    video_path = local_video
    srt_path = local_srt
    copied_files = true
  end

  local has_subtitle = srt_path and srt_path ~= "" and file_exists(srt_path) and is_srt(srt_path)
  local cues = {}
  if has_subtitle then
    local parsed, err = parse_srt(srt_path)
    if not parsed then
      reaper.ShowMessageBox(err, "Errore SRT", 0)
      return
    end
    cues = parsed
  end

  local desired_start = reaper.GetCursorPosition()
  local source_len = video_file_length(video_path)
  local block_start = resolve_single_video_position(desired_start, source_len or 0)
  if not block_start then return end

  reaper.ClearConsole()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local video_track = get_or_create_track("VIDEO", COLOR_VIDEO, 0)
  local ok_item, video_err = add_video_item(video_track, video_path, block_start)
  if not ok_item then
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Importa video + SRT", -1)
    reaper.ShowMessageBox(video_err, "Errore video", 0)
    return
  end
  show_video_window()

  local video_len = reaper.GetMediaItemInfo_Value(ok_item, "D_LENGTH")
  add_video_region(basename_without_ext(video_path), block_start, block_start + video_len)

  local inserted = 0
  local skipped = 0
  if has_subtitle then
    local subs_track = get_or_create_track(SUBTITLE_TRACK_NAME, COLOR_SUBS)
    setup_subtitle_track(subs_track)
    local notes_track = get_or_create_track(NOTES_TRACK_NAME, COLOR_NOTES)
    hide_track(notes_track)
    reaper.SetOnlyTrackSelected(subs_track)
    local previous_end = nil
    for i, cue in ipairs(cues) do
      local new_end, did_insert = add_subtitle_item(subs_track, cue, i, block_start, previous_end, fix_overlaps, srt_path)
      previous_end = new_end
      if did_insert then inserted = inserted + 1 else skipped = skipped + 1 end
    end
  else
    reaper.SetOnlyTrackSelected(video_track)
  end

  reaper.UpdateArrange()
  reaper.PreventUIRefresh(-1)
  build_missing_peaks_after_import()
  reaper.Undo_EndBlock("Importa video + SRT", -1)
  if save_after then reaper.Main_SaveProject(0, false) end

  msg("Video: " .. video_path)
  msg("SRT/VTT: " .. (has_subtitle and srt_path or "nessuno"))
  msg("Sottotitoli importati: " .. inserted)
  msg("Sottotitoli saltati dopo correzione overlap: " .. skipped)
  msg("Inserito da timeline: " .. string.format("%.3f", block_start) .. " sec")
  if math.abs(block_start - desired_start) > 0.0001 then
    msg("Playhead occupata: spostato al primo spazio libero sulla traccia VIDEO.")
  end

  local moved_text = ""
  if math.abs(block_start - desired_start) > 0.0001 then
    moved_text = "\n\nPlayhead occupata: inserito al primo spazio libero sulla traccia VIDEO."
  end

  local subtitle_text = has_subtitle and ("Sottotitoli importati: " .. inserted) or "Video importato senza SRT/VTT."
  reaper.ShowMessageBox(
    "Import completato.\n\n" .. subtitle_text ..
    "\nInserito da:\n" .. string.format("%.3f", block_start) .. " sec" ..
    (copied_files and "\nFile copiati nel progetto: si" or "\nFile copiati nel progetto: no") ..
    (save_after and "\nProgetto salvato." or "\nProgetto non salvato.") ..
    moved_text,
    has_subtitle and "Video + SRT/VTT" or "Video",
    0
  )

end

local function run_srt_only_import(srt_path, fix_overlaps, copy_files, save_after)
  local copied_files = false
  if copy_files then
    local local_srt, copy_err = copy_srt_to_project(srt_path)
    if not local_srt then
      reaper.ShowMessageBox(copy_err or "Copia SRT nel progetto non riuscita.", "ZP Studio Suite", 0)
      return
    end
    srt_path = local_srt
    copied_files = true
  end

  local cues, err = parse_srt(srt_path)
  if not cues then
    reaper.ShowMessageBox(err, "Errore SRT", 0)
    return
  end

  local srt_len = 0
  for _, cue in ipairs(cues) do
    if cue.end_pos and cue.end_pos > srt_len then srt_len = cue.end_pos end
  end
  srt_len = math.max(1, srt_len)

  reaper.ClearConsole()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local video_track = get_or_create_track("VIDEO", COLOR_VIDEO, 0)
  local desired_start = reaper.GetCursorPosition()
  local block_start = next_free_video_position(video_track, desired_start, srt_len, 0)
  local base = basename_without_ext(srt_path)
  add_empty_midi_reference_item(video_track, base, block_start, srt_len)

  local subs_track = get_or_create_track(SUBTITLE_TRACK_NAME, COLOR_SUBS)
  setup_subtitle_track(subs_track)
  local notes_track = get_or_create_track(NOTES_TRACK_NAME, COLOR_NOTES)
  hide_track(notes_track)
  add_video_region(base, block_start, block_start + srt_len)

  reaper.SetOnlyTrackSelected(subs_track)
  local inserted = 0
  local skipped = 0
  local previous_end = nil

  for i, cue in ipairs(cues) do
    local new_end, did_insert = add_subtitle_item(subs_track, cue, i, block_start, previous_end, fix_overlaps, srt_path)
    previous_end = new_end
    if did_insert then inserted = inserted + 1 else skipped = skipped + 1 end
  end

  reaper.UpdateArrange()
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Importa solo SRT - ZP Studio Suite", -1)
  if save_after then reaper.Main_SaveProject(0, false) end

  msg("SRT senza video: " .. srt_path)
  msg("Sottotitoli importati: " .. inserted)
  msg("Sottotitoli saltati dopo correzione overlap: " .. skipped)
  msg("Regione/item vuoto: " .. base .. " da " .. string.format("%.3f", block_start) .. " sec")

  local moved_text = ""
  if math.abs(block_start - desired_start) > 0.0001 then
    moved_text = "\n\nPlayhead occupata: inserito al primo spazio libero sulla traccia VIDEO."
  end

  reaper.ShowMessageBox(
    "Import solo SRT completato.\n\n" ..
    "Regione/item vuoto: " .. base ..
    "\nDurata da SRT: " .. string.format("%.3f", srt_len) .. " sec" ..
    "\nSottotitoli importati: " .. inserted ..
    (copied_files and "\nSRT copiato nel progetto: si" or "\nSRT copiato nel progetto: no") ..
    (save_after and "\nProgetto salvato." or "\nProgetto non salvato.") ..
    moved_text,
    "ZP Studio Suite",
    0
  )
end

local function run_batch_import(folder, start_at, gap, flag_overlaps)
  local ui_locked = false
  local undo_open = false

  local ok, result = xpcall(function()
    local project_path, project_folder, project_err = ensure_saved_project()
    if not project_path then
      reaper.ShowMessageBox(project_err or "Progetto non salvato.", "ZP Studio Suite", 0)
      return nil
    end

    local media_dir = project_folder .. sep .. "Media"
    local dir_ok, dir_err = ensure_directory(media_dir)
    if not dir_ok then error(dir_err or ("Impossibile creare cartella: " .. media_dir)) end

    local pairs, skipped = find_pairs(folder)
    if #pairs == 0 then
      reaper.ShowMessageBox("Nessuna coppia video+SRT trovata nella cartella:\n" .. folder, "ZP Studio Suite", 0)
      return nil
    end

    reaper.ClearConsole()
    reaper.ShowConsoleMsg("ZP Studio Suite batch: trovate " .. #pairs .. " coppie video+SRT.\n")
    reaper.Undo_BeginBlock()
    undo_open = true
    reaper.PreventUIRefresh(1)
    ui_locked = true

    local video_track = get_or_create_track("VIDEO", COLOR_VIDEO, 0)
    local subs_track = get_or_create_track(SUBTITLE_TRACK_NAME, COLOR_SUBS)
    setup_subtitle_track(subs_track)
    local notes_track = get_or_create_track(NOTES_TRACK_NAME, COLOR_NOTES)
    hide_track(notes_track)

    local cursor = start_at
    local total_cues = 0
    local total_skipped_cues = 0
    local total_overlap_cues = 0
    local imported_pairs = 0
    local copy_state = {}

    for index, pair in ipairs(pairs) do
      reaper.ShowConsoleMsg(string.format("[%d/%d] %s\n", index, #pairs, basename(pair.video)))
      local local_pair, copy_err = copy_pair_to_media(pair, project_folder, media_dir, copy_state)
      if not local_pair then
        reaper.ShowConsoleMsg(copy_err .. "\n")
      else
        local cues, err = parse_srt(local_pair.srt)
        if cues then
          local video_len_preview = video_file_length(local_pair.video) or 0
          cursor = next_free_video_position(video_track, cursor, video_len_preview, gap)
          local video_item, video_err = add_video_item(video_track, local_pair.video, cursor)
          if video_item then
            imported_pairs = imported_pairs + 1
            local video_len = reaper.GetMediaItemInfo_Value(video_item, "D_LENGTH")
            add_video_region(local_pair.base, cursor, cursor + video_len)
            local previous_end = nil
            for i, cue in ipairs(cues) do
              local new_end, cue_ok, cue_overlap = add_batch_subtitle_item(subs_track, cue, i, cursor, previous_end, flag_overlaps, pair.srt)
              previous_end = new_end
              if cue_ok then
                total_cues = total_cues + 1
                if cue_overlap then total_overlap_cues = total_overlap_cues + 1 end
              else
                total_skipped_cues = total_skipped_cues + 1
              end
            end
            cursor = cursor + video_len + gap
          else
            reaper.ShowConsoleMsg(video_err .. "\n")
          end
        else
          reaper.ShowConsoleMsg(err .. "\n")
        end
      end
    end

    show_video_window()
    reaper.SetOnlyTrackSelected(subs_track)
    hide_track(notes_track)
    refresh_track_visibility()

    reaper.PreventUIRefresh(-1)
    ui_locked = false
    reaper.Undo_EndBlock("Importa cartella video + SRT", -1)
    undo_open = false
    reaper.Main_SaveProject(0, false)

    reaper.ShowMessageBox(
      "Import cartella completato.\n\n" ..
      "Cartella: " .. folder ..
      "\nCopie importate: " .. imported_pairs ..
      "\nSottotitoli importati: " .. total_cues ..
      "\nCue sovrapposte in rosso: " .. total_overlap_cues ..
      "\nCue saltate: " .. total_skipped_cues ..
      "\n\nProgetto salvato.",
      "ZP Studio Suite",
      0
    )

  end, debug.traceback)

  if ui_locked then reaper.PreventUIRefresh(-1) end
  if undo_open then reaper.Undo_EndBlock("Importa cartella video + SRT", -1) end
  if not ok then
    reaper.ShowMessageBox("Import batch interrotto da un errore:\n\n" .. tostring(result), "ZP Studio Suite", 0)
  end
end

local function dispatch_import(settings)
  if settings.mode == "batch" then
    run_batch_import(settings.folder, reaper.GetCursorPosition(), settings.gap, settings.flag_overlaps)
  elseif settings.mode == "text_empty" then
    run_create_empty_text_track(settings.item_len, settings.save_after)
  elseif settings.mode == "srt_only" then
    run_srt_only_import(settings.srt, settings.fix_overlaps, settings.copy_files, settings.save_after)
  else
    run_import(settings.video, settings.srt, settings.fix_overlaps, settings.copy_files, settings.save_after)
  end
end

local function main()
  if not osara_active() then
    local opened = open_import_bridge(dispatch_import)
    if opened then return end
  end

  if _G.RYTHMOBAND_IMPORT_MODE == "batch" then
    local folder = select_folder_dialog("Scegli cartella con video e SRT/VTT", "")
    if not folder then return end
    local pairs, skipped = find_pairs(folder)
    if #pairs == 0 then
      reaper.ShowMessageBox("Nessuna coppia video+SRT/VTT trovata nella cartella:\n" .. folder ..
        (#skipped > 0 and ("\n\nVideo senza SRT/VTT corrispondente: " .. tostring(#skipped)) or ""), "ZP Studio Suite", 0)
      return
    end
    local ok, csv = reaper.GetUserInputs(
      "Importa cartella - ZP Studio Suite",
      2,
      "Pausa tra video sec:,Segnala overlap? 1 si 0 no:,extrawidth=470",
      "10,1"
    )
    if not ok then return end
    local gap_txt, overlap_txt = csv:match("^(.-),(.*)$")
    run_batch_import(folder, reaper.GetCursorPosition(), tonumber(trim(gap_txt)) or 10, trim(overlap_txt) ~= "0")
  else
    local video_path, srt_path_or_err, fix_overlaps = choose_paths_numeric()
    if not video_path then
      if srt_path_or_err then reaper.ShowMessageBox(srt_path_or_err, "Errore", 0) end
      return
    end
    run_import(video_path, srt_path_or_err, fix_overlaps)
  end
end

main()
