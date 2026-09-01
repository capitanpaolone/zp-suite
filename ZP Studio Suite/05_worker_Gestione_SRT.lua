-- @noindex

-- WORKER GESTIONE SRT RYTHMOBAND
-- Linea: ZP Paolo Balestri
-- Suite: ZP Studio Suite for REAPER v1.0.5
-- Distribuzione gratuita.
-- Sostituisce, aggiunge reference/lingue, aggiorna regioni o fa batch omonimo.
-- Copia sempre gli SRT usati nella cartella progetto e crea backup prima di sovrascrivere.

local SUBTITLE_TRACK_NAME = "Rythmo Band Testi"
local SRT_TEMPLATE_NAME = "SRT Track.RTrackTemplate"
local SCRIPT_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "")
local COLOR_SUBS = 0x3498DB
local COLOR_OVERLAP = 0xE53935
local COLOR_BACKUP = 0xF2C94C
local DEBUG_LOG_PATH = "/tmp/RythmoBand_Aggiorna_SRT.log"

local function debug_log(message)
  local f = io.open(DEBUG_LOG_PATH, "a")
  if not f then return end
  f:write(os.date("%Y-%m-%d %H:%M:%S") .. "  " .. tostring(message) .. "\n")
  f:close()
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
  if not input then return false, "Impossibile leggere: " .. tostring(src) end
  local output = io.open(dst, "wb")
  if not output then
    input:close()
    return false, "Impossibile scrivere: " .. tostring(dst)
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

local function basename(path)
  return path:match("[^/\\]+$") or path
end

local function sanitize_filename(name)
  name = trim(name or "")
  name = name:gsub("[/\\:%*%?\"<>|]", "_")
  name = name:gsub("%s+", " ")
  if name == "" then name = "SRT" end
  return name
end

local function basename_without_ext(path)
  local name = basename(path)
  return name:gsub("%.[^%.]+$", "")
end

local function ext_lower(path)
  return (path:match("%.([^%.\\/]+)$") or ""):lower()
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

local function timestamp()
  return os.date("%Y%m%d_%H%M")
end

local function project_dir()
  local _, project_path = reaper.EnumProjects(-1, "")
  project_path = trim(project_path or "")
  local dir = dirname(project_path)
  if dir ~= "" then return dir end
  return nil, "Salva il progetto REAPER prima di copiare/gestire gli SRT."
end

local function ensure_directory(path)
  if reaper.RecursiveCreateDirectory then
    reaper.RecursiveCreateDirectory(path, 0)
    return true
  end
  return false, "REAPER non espone RecursiveCreateDirectory."
end

local function project_subdir(name)
  local base_dir, base_err = project_dir()
  if not base_dir then return nil, base_err end
  local dir = base_dir .. package.config:sub(1, 1) .. name
  local ok, err = ensure_directory(dir)
  if not ok then return nil, err end
  return dir
end

local function copy_srt_into_project(src_srt, target_name)
  local srt_dir, dir_err = project_subdir("SRT")
  if not srt_dir then return nil, nil, dir_err end
  local backup_dir, backup_dir_err = project_subdir("SRT_Backup")
  if not backup_dir then return nil, nil, backup_dir_err end

  target_name = sanitize_filename(target_name or basename(src_srt))
  if not target_name:lower():match("%.srt$") and not target_name:lower():match("%.vtt$") then
    target_name = target_name .. "." .. subtitle_extension(src_srt)
  end
  local dst = srt_dir .. package.config:sub(1, 1) .. target_name
  local backup_path = nil

  if file_exists(dst) then
    backup_path = backup_dir .. package.config:sub(1, 1) .. basename_without_ext(dst) .. "_BKP_" .. timestamp() .. "." .. subtitle_extension(dst)
    local ok_bkp, err_bkp = copy_file(dst, backup_path)
    if not ok_bkp then return nil, nil, err_bkp end
  end

  local ok_copy, err_copy = copy_file(src_srt, dst)
  if not ok_copy then return nil, nil, err_copy end
  return dst, backup_path, nil
end

local function is_video(path)
  local ext = ext_lower(path)
  return ext == "mp4" or ext == "mov" or ext == "m4v" or ext == "avi" or ext == "mkv"
end

local function native_color(color)
  local r = (color >> 16) & 0xFF
  local g = (color >> 8) & 0xFF
  local b = color & 0xFF
  return reaper.ColorToNative(r, g, b) | 0x1000000
end

local function set_track_color(track, color)
  local r = (color >> 16) & 0xFF
  local g = (color >> 8) & 0xFF
  local b = color & 0xFF
  reaper.SetTrackColor(track, 0x1000000 | (b << 16) | (g << 8) | r)
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
    for line in block:gmatch("[^\n]+") do table.insert(lines, line) end
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
      for i = time_line_index + 1, #lines do table.insert(text_lines, lines[i]) end
      local text = clean_subtitle_text(table.concat(text_lines, "\n"))
      if start_pos and end_pos and end_pos > start_pos and text ~= "" then
        table.insert(cues, { start_pos = start_pos, end_pos = end_pos, text = text })
      end
    end
  end

  table.sort(cues, function(a, b)
    if a.start_pos == b.start_pos then return a.end_pos < b.end_pos end
    return a.start_pos < b.start_pos
  end)
  if #cues == 0 then return nil, "Nessun sottotitolo valido trovato in: " .. path end
  return cues
end

local function parse_srt(path)
  return parse_subtitle_file(path)
end

local function get_track_name(track)
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  return name or ""
end

local function find_track_by_name(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    if get_track_name(track) == name then return track end
  end
  return nil
end

local function create_track(name, color)
  local idx = reaper.CountTracks(0)
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

local function create_subtitle_track(name)
  if not reaper.SetTrackStateChunk then return create_track(name, COLOR_SUBS) end
  local text = read_file(SCRIPT_DIR .. SRT_TEMPLATE_NAME)
  local chunk = text and extract_first_track_chunk(text) or nil
  if not chunk then return create_track(name, COLOR_SUBS) end

  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local track = reaper.GetTrack(0, idx)
  reaper.SetTrackStateChunk(track, clean_template_chunk(chunk), false)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
  set_track_color(track, COLOR_SUBS)
  return track
end

local function setup_subtitle_track(track)
  if not track then return end
  reaper.SetMediaTrackInfo_Value(track, "B_FREEMODE", 1)
  reaper.SetMediaTrackInfo_Value(track, "I_FREEMODE", 1)
  reaper.SetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE", 120)
  set_track_color(track, COLOR_SUBS)
end

local function clear_track_items(track)
  for i = reaper.CountTrackMediaItems(track) - 1, 0, -1 do
    local item = reaper.GetTrackMediaItem(track, i)
    reaper.DeleteTrackMediaItem(track, item)
  end
end

local function item_touches_range(item, range_start, range_end)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = pos + len
  if not range_start or not range_end then return true end
  return pos < range_end and item_end > range_start
end

local function get_item_string(item, key)
  local _, value = reaper.GetSetMediaItemInfo_String(item, key, "", false)
  return value or ""
end

local function set_item_string(item, key, value)
  reaper.GetSetMediaItemInfo_String(item, key, value or "", true)
end

local function copy_item_to_track(src_item, dst_track)
  local dst_item = reaper.AddMediaItemToTrack(dst_track)
  local pos = reaper.GetMediaItemInfo_Value(src_item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(src_item, "D_LENGTH")
  reaper.SetMediaItemInfo_Value(dst_item, "D_POSITION", pos)
  reaper.SetMediaItemInfo_Value(dst_item, "D_LENGTH", len)
  reaper.SetMediaItemInfo_Value(dst_item, "I_CUSTOMCOLOR", reaper.GetMediaItemInfo_Value(src_item, "I_CUSTOMCOLOR"))
  reaper.SetMediaItemInfo_Value(dst_item, "F_FREEMODE_Y", reaper.GetMediaItemInfo_Value(src_item, "F_FREEMODE_Y"))
  reaper.SetMediaItemInfo_Value(dst_item, "F_FREEMODE_H", reaper.GetMediaItemInfo_Value(src_item, "F_FREEMODE_H"))
  set_item_string(dst_item, "P_NAME", get_item_string(src_item, "P_NAME"))
  set_item_string(dst_item, "P_NOTES", get_item_string(src_item, "P_NOTES"))
  set_item_string(dst_item, "P_EXT:RythmoBand_SRT_PATH", get_item_string(src_item, "P_EXT:RythmoBand_SRT_PATH"))
  set_item_string(dst_item, "P_EXT:RythmoBand_SRT_FILE", get_item_string(src_item, "P_EXT:RythmoBand_SRT_FILE"))
  set_item_string(dst_item, "P_EXT:RythmoBand_SRT_CUE", get_item_string(src_item, "P_EXT:RythmoBand_SRT_CUE"))
  return dst_item
end

local function backup_items_in_range(track, range_start, range_end, label)
  if not track then return 0, nil end
  local items = {}
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    if item_touches_range(item, range_start, range_end) then
      table.insert(items, item)
    end
  end
  if #items == 0 then return 0, nil end

  local backup_name = (label or get_track_name(track) or SUBTITLE_TRACK_NAME) .. " BKP " .. timestamp()
  local backup_track = create_track(backup_name, COLOR_BACKUP)
  setup_subtitle_track(backup_track)
  for _, item in ipairs(items) do copy_item_to_track(item, backup_track) end
  return #items, backup_name
end

local function source_file_from_item(item)
  local take = reaper.GetActiveTake(item)
  if not take then return nil end
  local source = reaper.GetMediaItemTake_Source(take)
  if not source then return nil end
  local path = reaper.GetMediaSourceFileName(source, "")
  path = trim(path)
  if path == "" then return nil end
  return path
end

local function collect_video_items()
  local video_track = find_track_by_name("VIDEO")
  local out = {}

  local function scan_track(track)
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      local path = source_file_from_item(item)
      if path and is_video(path) then
        table.insert(out, {
          item = item,
          path = path,
          start_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION"),
          end_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION") + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        })
      end
    end
  end

  if video_track then
    scan_track(video_track)
  else
    for t = 0, reaper.CountTracks(0) - 1 do scan_track(reaper.GetTrack(0, t)) end
  end

  table.sort(out, function(a, b) return a.start_pos < b.start_pos end)
  return out
end

local function collect_selected_video_items()
  local out = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local path = source_file_from_item(item)
    if path and is_video(path) then
      local start_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      table.insert(out, {
        item = item,
        path = path,
        start_pos = start_pos,
        end_pos = start_pos + length
      })
    end
  end
  table.sort(out, function(a, b) return a.start_pos < b.start_pos end)
  return out
end

local function region_at_position(pos)
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local total = num_markers + num_regions
  for i = 0, total - 1 do
    local ok, is_region, rgn_pos, rgn_end, name = reaper.EnumProjectMarkers(i)
    if ok and is_region and pos >= rgn_pos and pos < rgn_end then
      return { name = trim(name or ""), start_pos = rgn_pos, end_pos = rgn_end }
    end
  end
  return nil
end

local function delete_subtitle_items_in_block(track, block_start, block_end)
  local deleted = 0
  for i = reaper.CountTrackMediaItems(track) - 1, 0, -1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    if pos >= block_start and pos < block_end then
      reaper.DeleteTrackMediaItem(track, item)
      deleted = deleted + 1
    end
  end
  return deleted
end

local function choose_srt_for_video(video_path, force_choose)
  local base_path = dirname(video_path) .. package.config:sub(1, 1) .. basename_without_ext(video_path)
  local default_srt = base_path .. ".srt"
  local default_vtt = base_path .. ".vtt"
  local default_sub = file_exists(default_srt) and default_srt or (file_exists(default_vtt) and default_vtt or default_srt)
  if file_exists(default_sub) and not force_choose then return default_sub end

  local ok_srt, srt_path = reaper.GetUserFileNameForRead(
    file_exists(default_sub) and default_sub or dirname(video_path),
    "Scegli SRT/VTT per " .. basename(video_path),
    subtitle_dialog_ext()
  )
  if not ok_srt then return nil, "SRT/VTT non trovato:\n" .. default_sub end
  srt_path = trim(srt_path)
  if not file_exists(srt_path) then return nil, "SRT/VTT non trovato:\n" .. srt_path end
  if not is_subtitle_file(srt_path) then return nil, "Il file scelto non sembra un SRT/VTT:\n" .. srt_path end
  return srt_path
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

local function set_item_srt_metadata(item, srt_path, cue_index)
  if not item then return end
  reaper.GetSetMediaItemInfo_String(item, "P_EXT:RythmoBand_SRT_PATH", srt_path or "", true)
  reaper.GetSetMediaItemInfo_String(item, "P_EXT:RythmoBand_SRT_FILE", basename(srt_path or ""), true)
  reaper.GetSetMediaItemInfo_String(item, "P_EXT:RythmoBand_SRT_CUE", tostring(cue_index or ""), true)
end

local function add_subtitle_item(track, cue, index, block_start, previous_end, flag_overlaps, srt_path)
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

local function osara_active()
  return type(reaper.osara_outputMessage) == "function"
end

local function point_in_rect(x, y, rx, ry, rw, rh)
  return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
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

local function draw_button(rect, label, active, enabled, clicked)
  local x, y, w, h = rect.x, rect.y, rect.w, rect.h
  local hover = enabled and point_in_rect(gfx.mouse_x, gfx.mouse_y, x, y, w, h)
  if active then gfx.set(0.18, 0.34, 0.72, 1)
  elseif hover then gfx.set(0.25, 0.24, 0.34, 1)
  else gfx.set(0.16, 0.15, 0.22, 1) end
  if not enabled then gfx.set(0.10, 0.10, 0.12, 1) end
  gfx.rect(x, y, w, h, true)
  gfx.set(0.42, 0.39, 0.55, 1)
  gfx.rect(x, y, w, h, false)
  gfx.set(enabled and 0.92 or 0.45, enabled and 0.90 or 0.45, enabled and 0.95 or 0.45, 1)
  gfx.x = x + 12
  gfx.y = y + 9
  gfx.drawstr(fit_text(label, w - 24))
  return clicked and enabled and hover
end

local function choose_settings_visual()
  if not gfx or not gfx.init then return nil end

  local selected_op = nil
  local flag_overlaps = true
  local save_after = false
  local last_mouse_down = false

  gfx.init("ZP Studio Suite v1.0.5 - Gestione SRT", 720, 430)
  gfx.setfont(1, "Arial", 16)

  while true do
    local ch = gfx.getchar()
    if ch < 0 or ch == 27 then gfx.quit() return nil end
    local mouse_down = (gfx.mouse_cap & 1) == 1
    local clicked = mouse_down and not last_mouse_down
    last_mouse_down = mouse_down

    local selected_videos = collect_selected_video_items()
    local all_videos = collect_video_items()
    local cursor_region = region_at_position(reaper.GetCursorPosition())

    local operations = {
      {
        id = 1,
        mode = "selected",
        operation = "replace",
        label = "Sostituisci SRT - video selezionati (" .. #selected_videos .. ")",
        enabled = #selected_videos > 0
      },
      {
        id = 2,
        mode = "selected",
        operation = "reference",
        label = "Aggiungi lingua/reference (" .. #selected_videos .. " video selezionati)",
        enabled = #selected_videos == 1
      },
      {
        id = 3,
        mode = "region",
        operation = "replace",
        label = "Sostituisci regione al cursore" .. (cursor_region and (" - " .. (cursor_region.name ~= "" and cursor_region.name or "senza nome")) or " (nessuna)"),
        enabled = cursor_region ~= nil
      },
      {
        id = 4,
        mode = "all",
        operation = "batch",
        label = "Batch omonimi - tutti i video (" .. #all_videos .. ")",
        enabled = #all_videos > 0
      }
    }

    if not selected_op then
      if #selected_videos > 0 then selected_op = 1
      elseif cursor_region then selected_op = 3
      elseif #all_videos > 0 then selected_op = 4 end
    end
    local selected_valid = false
    for _, op in ipairs(operations) do
      if selected_op == op.id and op.enabled then selected_valid = true end
    end
    if not selected_valid then selected_op = nil end

    gfx.set(0.07, 0.07, 0.09, 1)
    gfx.rect(0, 0, gfx.w, gfx.h, true)

    gfx.set(0.10, 0.42, 0.48, 1)
    gfx.rect(22, 16, 34, 34, true)
    gfx.set(0.92, 0.88, 0.70, 1)
    gfx.circle(39, 33, 10, false)
    gfx.triangle(47, 25, 47, 34, 54, 29, true)
    gfx.triangle(31, 41, 31, 32, 24, 37, true)
    gfx.set(0.92, 0.88, 0.78, 1)
    gfx.x = 66
    gfx.y = 18
    gfx.setfont(1, "Arial", 20)
    gfx.drawstr("Gestione SRT")

    gfx.setfont(1, "Arial", 12)
    gfx.set(0.56, 0.72, 0.86, 1)
    gfx.x = 66
    gfx.y = 42
    gfx.drawstr("ZP Studio Suite v1.0.5 - Paolo Balestri")

    gfx.setfont(1, "Arial", 15)
    gfx.set(0.68, 0.66, 0.74, 1)
    gfx.x = 22
    gfx.y = 60
    gfx.drawstr("Scegli se sostituire, aggiungere una lingua/reference o fare un batch omonimo.")

    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x = 22
    gfx.y = 96
    gfx.drawstr("Operazione")

    for i, op in ipairs(operations) do
      local rect = { x = 22, y = 112 + ((i - 1) * 44), w = 470, h = 36 }
      if draw_button(rect, op.label, selected_op == op.id, op.enabled, clicked) then
        selected_op = op.id
      end
    end

    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x = 524
    gfx.y = 88
    gfx.drawstr("Opzioni")

    if draw_button({ x = 524, y = 112, w = 168, h = 36 }, "Overlap in rosso", flag_overlaps, true, clicked) then
      flag_overlaps = not flag_overlaps
    end
    if draw_button({ x = 524, y = 156, w = 168, h = 36 }, "Salva progetto dopo", save_after, true, clicked) then
      save_after = not save_after
    end

    gfx.set(0.48, 0.47, 0.54, 1)
    gfx.x = 22
    gfx.y = 318
    if #selected_videos == 0 and not cursor_region then
      gfx.drawstr(fit_text("Suggerimento: seleziona un video o metti la playhead dentro una regione per abilitare le operazioni mirate.", gfx.w - 44))
    else
      gfx.drawstr(fit_text("Gli SRT scelti vengono copiati nel progetto e gli item vecchi finiscono su una traccia BKP.", gfx.w - 44))
    end

    local chosen = nil
    for _, op in ipairs(operations) do
      if op.id == selected_op and op.enabled then chosen = op end
    end
    local ready = chosen ~= nil

    if draw_button({ x = 430, y = 370, w = 124, h = 38 }, "Procedi", false, ready, clicked) then
      gfx.quit()
      return chosen.mode, chosen.operation, flag_overlaps, save_after
    end
    if draw_button({ x = 566, y = 370, w = 124, h = 38 }, "Annulla", false, true, clicked) then
      gfx.quit()
      return nil
    end
    gfx.update()
  end
end

local function choose_settings_numeric()
  if _G.RYTHMOBAND_UPDATE_MODE == "selected" then
    return "selected", "replace", true, false
  end
  if _G.RYTHMOBAND_UPDATE_MODE == "reference" then
    return "selected", "reference", true, false
  end
  if _G.RYTHMOBAND_UPDATE_MODE == "region" then
    return "region", "replace", true, false
  end

  local selected_count = #collect_selected_video_items()
  local default_mode = selected_count > 0 and "1" or "2"
  local ok, choice_txt = reaper.GetUserInputs(
    "Gestione SRT - ZP Studio Suite",
    1,
    "1 sostituisci video sel 2 lingua/ref sel 3 regione cursore 4 batch omonimi:,extrawidth=700",
    default_mode
  )
  if not ok then return nil end

  local op = trim(choice_txt):match("[1234]") or default_mode
  if op == "1" then return "selected", "replace", true, false end
  if op == "2" then return "selected", "reference", true, false end
  if op == "3" then return "region", "replace", true, false end
  return "all", "batch", true, false
end

local function choose_settings()
  if _G.RYTHMOBAND_SRT_CONFIG then
    local cfg = _G.RYTHMOBAND_SRT_CONFIG
    return cfg.mode, cfg.operation, cfg.flag_overlaps ~= false, cfg.save_after == true
  end
  -- Stabilita': la finestra gfx bloccante puo' mandare REAPER in beachball
  -- quando lo script prosegue poi con file picker e import. Per ora usiamo i
  -- dialog nativi; la UI visuale richiede un refactor defer completo.
  return choose_settings_numeric()
end

local function choose_free_srt(title, start_dir)
  local default_dir = start_dir
  if not default_dir or default_dir == "" then default_dir = reaper.GetResourcePath() end
  local ok, path = reaper.GetUserFileNameForRead(default_dir, title or "Scegli SRT/VTT", subtitle_dialog_ext())
  if not ok then return nil end
  path = trim(path)
  if path == "" then return nil end
  if not file_exists(path) then return nil, "SRT/VTT non trovato:\n" .. path end
  if not is_subtitle_file(path) then return nil, "Il file scelto non sembra un SRT/VTT:\n" .. path end
  return path
end

local function choose_reference_suffix()
  if _G.RYTHMOBAND_SRT_CONFIG and _G.RYTHMOBAND_SRT_CONFIG.reference_suffix then
    local suffix = sanitize_filename(trim(_G.RYTHMOBAND_SRT_CONFIG.reference_suffix))
    if suffix == "" then suffix = "REF" end
    return suffix
  end
  local ok, suffix = reaper.GetUserInputs("SRT reference", 1, "Suffisso traccia:,extrawidth=500", "REF")
  if not ok then return nil end
  suffix = sanitize_filename(trim(suffix))
  if suffix == "" then suffix = "REF" end
  return suffix
end

local function ask_confirm(summary)
  local choice = reaper.ShowMessageBox(summary .. "\n\nProcedere?", "ZP Studio Suite - Gestione SRT", 1)
  return choice == 1
end

local function main()
  os.remove(DEBUG_LOG_PATH)
  debug_log("START")
  debug_log("before settings")
  local mode, operation, flag_overlaps, save_after = choose_settings()
  if mode == nil then return end
  debug_log("settings mode=" .. tostring(mode) .. " operation=" .. tostring(operation) .. " overlaps=" .. tostring(flag_overlaps) .. " save=" .. tostring(save_after))

  local ui_locked = false
  local undo_open = false

  local ok, result = xpcall(function()
    local blocks = {}
    local skipped_videos = {}
    local target_track_name = SUBTITLE_TRACK_NAME
    local backup_label = SUBTITLE_TRACK_NAME

    if mode == "selected" then
      local videos = collect_selected_video_items()
      debug_log("selected videos=" .. tostring(#videos))
      if #videos == 0 then
        reaper.ShowMessageBox("Non trovo item video selezionati.", "ZP Studio Suite", 0)
        return nil
      end
      if operation == "reference" and #videos > 1 then
        reaper.ShowMessageBox("Per aggiungere una lingua/reference seleziona un solo video.", "ZP Studio Suite", 0)
        return nil
      end

      local suffix = nil
      if operation == "reference" then
        suffix = choose_reference_suffix()
        if not suffix then return nil end
        target_track_name = SUBTITLE_TRACK_NAME .. " " .. suffix
        backup_label = target_track_name
      end

      for _, video in ipairs(videos) do
        local chosen_srt, choose_err = choose_srt_for_video(video.path, true)
        if not chosen_srt then
          if choose_err then debug_log(choose_err) end
          return nil
        end
        local target_name = basename_without_ext(video.path) .. (suffix and ("_" .. suffix) or "") .. "." .. subtitle_extension(chosen_srt)
        local project_srt, file_backup, copy_err = copy_srt_into_project(chosen_srt, target_name)
        if not project_srt then
          reaper.ShowMessageBox(copy_err or "Errore copia SRT nel progetto.", "ZP Studio Suite", 0)
          return nil
        end
        local cues, err = parse_srt(project_srt)
        if not cues then
          reaper.ShowMessageBox(err or "SRT non valido.", "ZP Studio Suite", 0)
          return nil
        end
        table.insert(blocks, { label = basename(video.path), start_pos = video.start_pos, end_pos = video.end_pos, srt_path = project_srt, source_srt = chosen_srt, file_backup = file_backup, cues = cues })
      end
    elseif mode == "region" then
      local region = region_at_position(reaper.GetCursorPosition())
      if not region then
        reaper.ShowMessageBox("Non trovo una regione sotto il cursore/playhead.", "ZP Studio Suite", 0)
        return nil
      end
      local chosen_srt, choose_err = choose_free_srt("Scegli SRT per regione " .. (region.name ~= "" and region.name or "senza nome"), project_dir())
      if not chosen_srt then
        if choose_err then reaper.ShowMessageBox(choose_err, "ZP Studio Suite", 0) end
        return nil
      end
      local target_name = sanitize_filename(region.name ~= "" and region.name or "Regione") .. "." .. subtitle_extension(chosen_srt)
      local project_srt, file_backup, copy_err = copy_srt_into_project(chosen_srt, target_name)
      if not project_srt then
        reaper.ShowMessageBox(copy_err or "Errore copia SRT nel progetto.", "ZP Studio Suite", 0)
        return nil
      end
      local cues, err = parse_srt(project_srt)
      if not cues then
        reaper.ShowMessageBox(err or "SRT non valido.", "ZP Studio Suite", 0)
        return nil
      end
      table.insert(blocks, { label = region.name ~= "" and region.name or "Regione", start_pos = region.start_pos, end_pos = region.end_pos, srt_path = project_srt, source_srt = chosen_srt, file_backup = file_backup, cues = cues })
    else
      local videos = collect_video_items()
      debug_log("all videos=" .. tostring(#videos))
      if #videos == 0 then
        reaper.ShowMessageBox("Non trovo item video nel progetto aperto.", "ZP Studio Suite", 0)
        return nil
      end
      for _, video in ipairs(videos) do
        local base_path = dirname(video.path) .. package.config:sub(1, 1) .. basename_without_ext(video.path)
        local default_srt = base_path .. ".srt"
        local default_vtt = base_path .. ".vtt"
        local default_sub = file_exists(default_srt) and default_srt or (file_exists(default_vtt) and default_vtt or nil)
        if default_sub then
          local project_srt, file_backup, copy_err = copy_srt_into_project(default_sub, basename(default_sub))
          if not project_srt then
            reaper.ShowMessageBox(copy_err or "Errore copia SRT nel progetto.", "ZP Studio Suite", 0)
            return nil
          end
          local cues, err = parse_srt(project_srt)
          if cues then
            table.insert(blocks, { label = basename(video.path), start_pos = video.start_pos, end_pos = video.end_pos, srt_path = project_srt, source_srt = default_sub, file_backup = file_backup, cues = cues })
          else
            debug_log(err)
            table.insert(skipped_videos, basename(video.path))
          end
        else
          table.insert(skipped_videos, basename(video.path))
        end
      end
    end

    if #blocks == 0 then
      reaper.ShowMessageBox("Nessun SRT valido da importare.", "ZP Studio Suite", 0)
      return nil
    end

    local subs_track = find_track_by_name(target_track_name) or create_subtitle_track(target_track_name)
    setup_subtitle_track(subs_track)

    local summary = "Operazione: " .. tostring(operation) ..
      "\nTraccia: " .. target_track_name ..
      "\nBlocchi da aggiornare: " .. tostring(#blocks) ..
      "\nBackup item: si, su traccia BKP" ..
      "\nCopia SRT nel progetto: si, cartella SRT"
    if not ask_confirm(summary) then return nil end

    debug_log("begin undo/ui lock")
    reaper.Undo_BeginBlock()
    undo_open = true
    reaper.PreventUIRefresh(1)
    ui_locked = true

    local deleted_items = 0
    local backup_items = 0
    local backup_tracks = {}
    if mode == "all" then
      local n, backup_name = backup_items_in_range(subs_track, nil, nil, backup_label)
      backup_items = backup_items + n
      if backup_name then table.insert(backup_tracks, backup_name) end
      clear_track_items(subs_track)
    else
      for _, block in ipairs(blocks) do
        local n, backup_name = backup_items_in_range(subs_track, block.start_pos, block.end_pos, backup_label)
        backup_items = backup_items + n
        if backup_name then table.insert(backup_tracks, backup_name) end
        deleted_items = deleted_items + delete_subtitle_items_in_block(subs_track, block.start_pos, block.end_pos)
      end
    end

    local total_cues = 0
    local total_skipped_cues = 0
    local total_overlap_cues = 0
    local used_srts = {}
    local file_backups = {}

    for _, block in ipairs(blocks) do
      table.insert(used_srts, block.srt_path)
      if block.file_backup then table.insert(file_backups, block.file_backup) end
      local previous_end = nil
      for i, cue in ipairs(block.cues) do
        local new_end, cue_ok, cue_overlap = add_subtitle_item(subs_track, cue, i, block.start_pos, previous_end, flag_overlaps, block.srt_path)
        previous_end = new_end
        if cue_ok then
          total_cues = total_cues + 1
          if cue_overlap then total_overlap_cues = total_overlap_cues + 1 end
        else
          total_skipped_cues = total_skipped_cues + 1
        end
      end
    end

    debug_log("unlock ui/update arrange")
    reaper.SetOnlyTrackSelected(subs_track)
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    ui_locked = false
    reaper.Undo_EndBlock("Aggiorna SRT da video esistenti - ZP Studio Suite", -1)
    undo_open = false

    if save_after then
      debug_log("save project")
      reaper.Main_SaveProject(0, false)
      debug_log("save done")
    end

    debug_log("DONE")
    return {
      blocks = blocks,
      videos_with_srt = #blocks,
      skipped_videos = skipped_videos,
      used_srts = used_srts,
      file_backups = file_backups,
      backup_tracks = backup_tracks,
      backup_items = backup_items,
      total_cues = total_cues,
      total_skipped_cues = total_skipped_cues,
      total_overlap_cues = total_overlap_cues,
      deleted_items = deleted_items,
      mode = mode,
      operation = operation,
      target_track_name = target_track_name,
      saved = save_after
    }
  end, debug.traceback)

  if ui_locked then reaper.PreventUIRefresh(-1) end
  if undo_open then reaper.Undo_EndBlock("Aggiorna SRT da video esistenti interrotto", -1) end
  reaper.UpdateArrange()

  if not ok then
    reaper.ShowMessageBox("Aggiornamento SRT interrotto da un errore:\n\n" .. tostring(result), "ZP Studio Suite", 0)
    return
  end
  if not result then return end

  local skipped_msg = ""
  if #result.skipped_videos > 0 then skipped_msg = "\nVideo senza SRT: " .. #result.skipped_videos end
  local used_srt_msg = ""
  if result.used_srts and #result.used_srts > 0 then
    used_srt_msg = "\n\nSRT usati:"
    for i, path in ipairs(result.used_srts) do
      if i > 5 then
        used_srt_msg = used_srt_msg .. "\n... +" .. tostring(#result.used_srts - 5)
        break
      end
      used_srt_msg = used_srt_msg .. "\n" .. path
    end
  end
  local file_backup_msg = ""
  if result.file_backups and #result.file_backups > 0 then
    file_backup_msg = "\n\nBackup file SRT:"
    for i, path in ipairs(result.file_backups) do
      if i > 3 then
        file_backup_msg = file_backup_msg .. "\n... +" .. tostring(#result.file_backups - 3)
        break
      end
      file_backup_msg = file_backup_msg .. "\n" .. path
    end
  end
  local item_backup_msg = ""
  if (result.backup_items or 0) > 0 then
    item_backup_msg = "\nItem backup: " .. tostring(result.backup_items)
    if result.backup_tracks and #result.backup_tracks > 0 then
      item_backup_msg = item_backup_msg .. "\nTraccia BKP: " .. result.backup_tracks[1]
      if #result.backup_tracks > 1 then item_backup_msg = item_backup_msg .. " (+" .. tostring(#result.backup_tracks - 1) .. ")" end
    end
  end
  local saved_msg = result.saved and "\nProgetto salvato." or "\nProgetto non salvato."

  reaper.ShowMessageBox(
    "Gestione SRT completata.\n\nOperazione: " .. tostring(result.operation) ..
    "\nTraccia: " .. tostring(result.target_track_name) ..
    "\nBlocchi aggiornati: " .. tostring(result.videos_with_srt) ..
    (result.mode == "selected" and ("\nVecchi item cancellati: " .. result.deleted_items) or "") ..
    "\nSottotitoli importati: " .. result.total_cues ..
    "\nCue sovrapposte in rosso: " .. result.total_overlap_cues ..
    "\nCue saltate: " .. result.total_skipped_cues ..
    skipped_msg ..
    item_backup_msg ..
    used_srt_msg ..
    file_backup_msg ..
    "\n" .. saved_msg,
    "ZP Studio Suite",
    0
  )
end

main()
