-- CREA REGIONI EXPORT DA ITEM NOMINATI
-- Linea: ZP Paolo Balestri
-- Suite: ZP Studio Suite for REAPER v1.0.5
-- Distribuzione gratuita.
-- Raggruppa gli item in base al gap tra fine item e inizio item successivo.
-- Crea regioni colorate e nominate da una lista testuale, senza modificare gli item.

local SCRIPT_TITLE = "ZP Studio Suite v1.0.5 - Gestore Progetto"
local EXT_SECTION = "ZP_RythmoBand_ExportRegions"
local REGION_COLOR = reaper.ColorToNative(40, 170, 210) | 0x1000000
local MARKER_COLOR = reaper.ColorToNative(238, 116, 46) | 0x1000000
local WARMUP_REGION_NAME = "__ZP_WARMUP_GHOST__"
local WARMUP_SECONDS = 5.0
local WARMUP_COLOR = reaper.ColorToNative(115, 115, 125) | 0x1000000
local WARMUP_EXT_KEY = "ZP_WARMUP_GHOST"
local WARMUP_SOURCE_NAME = "__ZP_WARMUP_SOURCE__.wav"
local EPS = 0.000001
local DEBUG_KEYS = false
local DEBUG_LOG_PATH = (reaper.GetResourcePath and (reaper.GetResourcePath() .. "/RythmoBand_ExportRegions_keylog.txt")) or "/tmp/RythmoBand_ExportRegions_keylog.txt"
local PLAY_PREROLL = 0.10
local FIXED_WINDOW_W = 980
local MIN_WINDOW_H = 620
local ADD_TO_RENDER_QUEUE_CMD = 41823
local OPEN_RENDER_QUEUE_CMD = 40929
local sep = package.config:sub(1, 1)
local RENDER_DEBUG_LOG_PATH = (reaper.GetResourcePath and (reaper.GetResourcePath() .. sep .. "ZP_StudioSuite_Render_Debug.log")) or "/tmp/ZP_StudioSuite_Render_Debug.log"

local function script_dir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*)[/\\]") or "."
end

local ZP_UI = dofile(script_dir() .. "/ZP_UI.lua")

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function tonumber_locale(s, fallback)
  s = trim(s):gsub(",", ".")
  local n = tonumber(s)
  if not n then return fallback end
  return n
end

local function bool_from_state(value, fallback)
  if value == nil or value == "" then return fallback end
  return value == "1" or value == "true"
end

local render_debug_log

local function speak(text)
  if reaper.osara_outputMessage then
    reaper.osara_outputMessage(text)
  else
    reaper.ShowMessageBox(text, SCRIPT_TITLE, 0)
  end
end

local function notify_status(message)
  if reaper.osara_outputMessage then
    reaper.osara_outputMessage(message)
  else
    render_debug_log("status | " .. tostring(message or ""):gsub("\n", "\\n"):gsub("\r", "\\r"):sub(1, 180))
  end
end

render_debug_log = function(message)
  local f = io.open(RENDER_DEBUG_LOG_PATH, "a")
  if not f then return end
  f:write(os.date("%Y-%m-%d %H:%M:%S"), "  ", tostring(message or ""), "\n")
  f:close()
end

local function render_debug_project_state(context)
  local _, render_file = reaper.GetSetProjectInfo_String(0, "RENDER_FILE", "", false)
  local _, render_pattern = reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "", false)
  render_debug_log(string.format(
    "%s | bounds=%s file=%s pattern=%s queue_cmd=%s open_queue_cmd=%s",
    tostring(context or "render-state"),
    tostring(reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 0, false)),
    tostring(render_file or ""),
    tostring(render_pattern or ""),
    tostring(ADD_TO_RENDER_QUEUE_CMD),
    tostring(OPEN_RENDER_QUEUE_CMD)
  ))
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
  return (out ~= "" and out:gsub("%s+$", "") or "") .. suffix
end

local function fit_text_middle(text, max_w)
  text = tostring(text or "")
  if gfx.measurestr(text) <= max_w then return text end
  local ellipsis = "..."
  local keep_left = math.max(6, math.floor(#text * 0.52))
  local keep_right = math.max(6, #text - keep_left)
  while keep_left > 3 or keep_right > 3 do
    local candidate = text:sub(1, keep_left) .. ellipsis .. text:sub(#text - keep_right + 1)
    if gfx.measurestr(candidate) <= max_w then return candidate end
    if keep_left >= keep_right and keep_left > 3 then
      keep_left = keep_left - 1
    elseif keep_right > 3 then
      keep_right = keep_right - 1
    else
      break
    end
  end
  return fit_text(text, max_w)
end

local function log_escape(value)
  return tostring(value or ""):gsub("\n", "\\n"):gsub("\r", "\\r"):sub(1, 180)
end

local function log_debug(event, details)
  if not DEBUG_KEYS then return end
  local file = io.open(DEBUG_LOG_PATH, "a")
  if not file then return end
  file:write(string.format("%s | %s | %s\n", os.date("%H:%M:%S"), event, details or ""))
  file:close()
end

local function reset_debug_log()
  if not DEBUG_KEYS then return end
  local file = io.open(DEBUG_LOG_PATH, "w")
  if not file then return end
  file:write(string.format("ZP Studio Suite - Export Regions keylog - %s\n", os.date("%Y-%m-%d %H:%M:%S")))
  file:write("Formato: ora | evento | dettagli\n")
  file:close()
end

local function decode_draft_names(text)
  local draft = {}
  text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local key, value = line:match("^(.-)\t(.*)$")
    if key and key ~= "" then
      draft[key] = (value or ""):gsub("\\n", "\n"):gsub("\\t", "\t")
    end
  end
  return draft
end

local function encode_draft_names(draft)
  local keys = {}
  for key, value in pairs(draft or {}) do
    if value and trim(value) ~= "" then table.insert(keys, key) end
  end
  table.sort(keys)
  local lines = {}
  for _, key in ipairs(keys) do
    local value = tostring(draft[key] or ""):gsub("\t", "\\t"):gsub("\n", "\\n")
    table.insert(lines, key .. "\t" .. value)
  end
  return table.concat(lines, "\n")
end

local function decode_draft_order(text)
  local draft = {}
  text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  local index = 1
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line ~= "" then draft[index] = line:gsub("\\n", "\n"):gsub("\\t", "\t") end
    index = index + 1
  end
  return draft
end

local function encode_draft_order(draft)
  local max_index = 0
  for index, value in pairs(draft or {}) do
    if type(index) == "number" and value and trim(value) ~= "" then
      max_index = math.max(max_index, index)
    end
  end
  local lines = {}
  for i = 1, max_index do
    lines[i] = tostring(draft[i] or ""):gsub("\t", "\\t"):gsub("\n", "\\n")
  end
  return table.concat(lines, "\n"):gsub("\n+$", "")
end

local function get_state()
  return {
    gap = tonumber_locale(reaper.GetExtState(EXT_SECTION, "gap"), 2.0),
    pad_in = tonumber_locale(reaper.GetExtState(EXT_SECTION, "pad_in"), 0.2),
    pad_out = tonumber_locale(reaper.GetExtState(EXT_SECTION, "pad_out"), 0.5),
    collect_mode = reaper.GetExtState(EXT_SECTION, "collect_mode") ~= "" and reaper.GetExtState(EXT_SECTION, "collect_mode") or "tracks",
    delete_old = bool_from_state(reaper.GetExtState(EXT_SECTION, "delete_old"), false),
    make_markers = bool_from_state(reaper.GetExtState(EXT_SECTION, "make_markers"), false),
    number_names = bool_from_state(reaper.GetExtState(EXT_SECTION, "number_names"), false),
    mixdown_index_enabled = bool_from_state(reaper.GetExtState(EXT_SECTION, "mixdown_index_enabled"), false),
    preroll_warmup = bool_from_state(reaper.GetExtState(EXT_SECTION, "preroll_warmup"), false),
    names_text = reaper.GetExtState(EXT_SECTION, "names_text") or "",
    draft_names = reaper.GetExtState(EXT_SECTION, "draft_names") or "",
    draft_order = reaper.GetExtState(EXT_SECTION, "draft_order") or ""
  }
end

local function save_state(state)
  reaper.SetExtState(EXT_SECTION, "gap", tostring(state.gap), true)
  reaper.SetExtState(EXT_SECTION, "pad_in", tostring(state.pad_in), true)
  reaper.SetExtState(EXT_SECTION, "pad_out", tostring(state.pad_out), true)
  reaper.SetExtState(EXT_SECTION, "collect_mode", tostring(state.collect_mode or "tracks"), true)
  reaper.SetExtState(EXT_SECTION, "delete_old", state.delete_old and "1" or "0", true)
  reaper.SetExtState(EXT_SECTION, "make_markers", state.make_markers and "1" or "0", true)
  reaper.SetExtState(EXT_SECTION, "number_names", state.number_names and "1" or "0", true)
  reaper.SetExtState(EXT_SECTION, "mixdown_index_enabled", state.mixdown_index_enabled and "1" or "0", true)
  reaper.SetExtState(EXT_SECTION, "preroll_warmup", state.preroll_warmup and "1" or "0", true)
  reaper.SetExtState(EXT_SECTION, "names_text", state.names_text or "", true)
  reaper.SetExtState(EXT_SECTION, "draft_names", state.draft_names or "", true)
  reaper.SetExtState(EXT_SECTION, "draft_order", state.draft_order or "", true)
end

local function get_clipboard()
  if reaper.CF_GetClipboard then
    local a, b = reaper.CF_GetClipboard("")
    if type(b) == "string" then return b end
    if type(a) == "string" then return a end
  end
  return nil
end

local function normalize_name_list(text)
  text = tostring(text or "")
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  text = text:gsub("\11", "\n"):gsub("\12", "\n")
  text = text:gsub("\226\128\168", "\n"):gsub("\226\128\169", "\n")
  text = text:gsub("\\n", "\n"):gsub(";", "\n")
  return text
end

local function looks_like_numbered_list_line(text)
  local count = 0
  for token in tostring(text or ""):gmatch("%S+") do
    if not token:match("^%d+[%d%.]*$") then return false end
    count = count + 1
  end
  return count > 1
end

local function set_clipboard_or_prompt()
  local text = get_clipboard()
  if text and text ~= "" then return normalize_name_list(text) end

  local ok, value = reaper.GetUserInputs(
    "Incolla lista nomi",
    1,
    "Nomi separati da \\n oppure ;,extrawidth=700",
    ""
  )
  if not ok then return nil end
  return normalize_name_list(value)
end

local function parse_names(text)
  local names = {}
  text = normalize_name_list(text)
  if not text:find("\n", 1, true) and looks_like_numbered_list_line(text) then
    for token in text:gmatch("%S+") do table.insert(names, trim(token)) end
    return names
  end
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local name = trim(line)
    if name ~= "" then table.insert(names, name) end
  end
  return names
end

local function parse_names_preserve_rows(text)
  local names = {}
  text = normalize_name_list(text)
  if text == "" then return names end
  if not text:find("\n", 1, true) and looks_like_numbered_list_line(text) then
    for token in text:gmatch("%S+") do names[#names + 1] = trim(token) end
    return names
  end
  local index = 1
  for line in (text .. "\n"):gmatch("(.-)\n") do
    names[index] = trim(line)
    index = index + 1
  end
  return names
end

local function item_is_midi(item)
  local take = reaper.GetActiveTake(item)
  return take and reaper.TakeIsMIDI and reaper.TakeIsMIDI(take)
end

local function is_warmup_item_candidate(item)
  if not item then return false end
  local color = math.floor(reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR") or 0)
  if color == WARMUP_COLOR then return true end
  if reaper.GetSetMediaItemInfo_String then
    local ok, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    if ok and trim(notes or "") == WARMUP_REGION_NAME then return true end
  end
  local take = reaper.GetActiveTake(item)
  if take and reaper.GetSetMediaItemTakeInfo_String then
    local ok, take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    if ok and trim(take_name or "") == WARMUP_REGION_NAME then return true end
  end
  return false
end

local function add_region_candidate(items, item, track)
  if item_is_midi(item) or is_warmup_item_candidate(item) then return end
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  if len > EPS then
    table.insert(items, { item = item, track = track, pos = pos, len = len, end_pos = pos + len })
  end
end

local function get_track_items(track)
  local items = {}
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    add_region_candidate(items, item, track)
  end
  return items
end

local function append_track_items(items, track, seen_tracks)
  if not track then return end
  local key = tostring(track)
  if seen_tracks[key] then return end
  seen_tracks[key] = true
  local track_items = get_track_items(track)
  for _, entry in ipairs(track_items) do table.insert(items, entry) end
end

local function append_track_and_folder_children(items, track, seen_tracks)
  append_track_items(items, track, seen_tracks)
  if not track then return end

  local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
  if depth <= 0 then return end

  local track_index = math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
  local folder_depth = depth
  local total_tracks = reaper.CountTracks(0)
  for i = track_index, total_tracks - 1 do
    local child = reaper.GetTrack(0, i)
    append_track_items(items, child, seen_tracks)
    folder_depth = folder_depth + reaper.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
    if folder_depth <= 0 then break end
  end
end

local function collect_items(state)
  local items = {}
  local seen_tracks = {}
  local selected_count = reaper.CountSelectedMediaItems(0)
  local mode = state and state.collect_mode or "tracks"

  if mode == "items" then
    for i = 0, selected_count - 1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      local track = reaper.GetMediaItemTrack(item)
      add_region_candidate(items, item, track)
    end
  elseif mode == "all" then
    for i = 0, reaper.CountTracks(0) - 1 do
      append_track_items(items, reaper.GetTrack(0, i), seen_tracks)
    end
  else
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
      local track = reaper.GetSelectedTrack(0, i)
      if mode == "folder" then
        append_track_and_folder_children(items, track, seen_tracks)
      else
        append_track_items(items, track, seen_tracks)
      end
    end
  end

  table.sort(items, function(a, b)
    if math.abs(a.pos - b.pos) > EPS then return a.pos < b.pos end
    return a.end_pos < b.end_pos
  end)

  if mode == "items" then
    return items, "item selezionati"
  elseif mode == "folder" then
    return items, "tracce selezionate + sottotracce"
  elseif mode == "all" then
    return items, "tutte le tracce"
  end
  return items, "tracce selezionate"
end

local function analyze_groups(items, gap, pad_in, pad_out)
  local groups = {}
  if #items == 0 then return groups end

  local current = {
    start_pos = items[1].pos,
    end_pos = items[1].end_pos,
    first_item = items[1],
    last_item = items[1],
    count = 1
  }

  for i = 2, #items do
    local item = items[i]
    -- Treat the selected material as one covered timeline. If music/effects or
    -- folder children keep sounding under short voice clips, they must bridge
    -- the zone instead of letting a short item create a false split.
    local distance = item.pos - current.end_pos
    if distance > gap then
      current.region_start = math.max(0, current.start_pos - pad_in)
      current.region_end = current.end_pos + pad_out
      table.insert(groups, current)
      current = {
        start_pos = item.pos,
        end_pos = item.end_pos,
        first_item = item,
        last_item = item,
        count = 1
      }
    else
      current.end_pos = math.max(current.end_pos, item.end_pos)
      current.last_item = item
      current.count = current.count + 1
    end
  end

  current.region_start = math.max(0, current.start_pos - pad_in)
  current.region_end = current.end_pos + pad_out
  table.insert(groups, current)
  return groups
end

local function get_item_bounds(items)
  if #items == 0 then return nil, nil end
  local start_pos = items[1].pos
  local end_pos = items[1].end_pos
  for _, item in ipairs(items) do
    start_pos = math.min(start_pos, item.pos)
    end_pos = math.max(end_pos, item.end_pos)
  end
  return start_pos, end_pos
end

local function ranges_overlap(a_start, a_end, b_start, b_end)
  return a_start < b_end - EPS and a_end > b_start + EPS
end

local function lane_number_at_enum_index(enum_index)
  if not (reaper.GetRegionOrMarker and reaper.GetRegionOrMarkerInfo_Value) then return 1 end
  local entry = reaper.GetRegionOrMarker(0, enum_index, "")
  if not entry then return 1 end
  -- REAPER stores marker/region lanes zero-based here: UI Lane 1 => 0.
  local lane = tonumber(reaper.GetRegionOrMarkerInfo_Value(0, entry, "I_LANENUMBER"))
  if lane == nil then lane = 0 end
  lane = lane + 1
  if lane < 1 then lane = 1 end
  return math.floor(lane + 0.5)
end

local function is_lane1_enum_index(enum_index)
  return lane_number_at_enum_index(enum_index) == 1
end

local function collect_existing_regions(items)
  local range_start, range_end = nil, nil
  range_start, range_end = get_item_bounds(items)
  if not range_start or not range_end then
    local ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if ts_end and ts_start and ts_end > ts_start + EPS then
      range_start, range_end = ts_start, ts_end
    end
  end
  if not range_start or not range_end then return {} end

  local regions = {}
  local _, marker_count, region_count = reaper.CountProjectMarkers(0)
  local total = marker_count + region_count
  for i = 0, total - 1 do
    local ok, is_region, pos, rgn_end, name, idx, color = reaper.EnumProjectMarkers3(0, i)
    if ok and is_region and is_lane1_enum_index(i) and not (trim(name or "") == WARMUP_REGION_NAME or color == WARMUP_COLOR) and ranges_overlap(pos, rgn_end, range_start, range_end) then
      local count = 0
      for _, item in ipairs(items) do
        if ranges_overlap(item.pos, item.end_pos, pos, rgn_end) then count = count + 1 end
      end
      table.insert(regions, {
        region_start = pos,
        region_end = rgn_end,
        start_pos = pos,
        end_pos = rgn_end,
        count = count,
        existing_region = true,
        existing_idx = idx,
        existing_color = color,
        name = trim(name or "")
      })
    end
  end
  table.sort(regions, function(a, b) return a.region_start < b.region_start end)
  return regions
end

local function marker_lane_at_enum_index(enum_index)
  return lane_number_at_enum_index(enum_index)
end

local function collect_project_markers()
  local markers = {}
  local _, marker_count, region_count = reaper.CountProjectMarkers(0)
  local total = marker_count + region_count
  local marker_number = 0
  for i = 0, total - 1 do
    local ok, is_region, pos, _, name, idx, color = reaper.EnumProjectMarkers3(0, i)
    if ok and not is_region then
      local lane = marker_lane_at_enum_index(i)
      -- Lane 1 = cartella Mixdown principale; Lane 2 = sottocartella della Lane 1 precedente.
      -- Lane 3+ restano marker standard/metadati e non spezzano le sezioni render.
      if lane == 1 or lane == 2 then
        marker_number = marker_number + 1
        markers[#markers + 1] = {
          pos = pos,
          name = trim(name or "") ~= "" and trim(name or "") or "(marker senza nome)",
          idx = idx,
          number = marker_number,
          color = color,
          lane = lane
        }
      end
    end
  end
  table.sort(markers, function(a, b)
    if math.abs((a.pos or 0) - (b.pos or 0)) > EPS then return (a.pos or 0) < (b.pos or 0) end
    return (a.lane or 1) < (b.lane or 1)
  end)
  local current_lane1 = nil
  for _, marker in ipairs(markers) do
    if marker.lane == 1 then
      current_lane1 = marker
      marker.parent_name = nil
      marker.folder_parts = { marker.name }
      marker.folder_depth = 1
    elseif marker.lane == 2 then
      marker.parent_name = current_lane1 and current_lane1.name or nil
      if current_lane1 then
        marker.folder_parts = { current_lane1.name, marker.name }
        marker.folder_depth = 2
      else
        marker.folder_parts = { marker.name }
        marker.folder_depth = 1
        marker.missing_parent_lane1 = true
      end
    end
  end
  return markers
end

local function marker_for_position(markers, pos)
  local current = nil
  for _, marker in ipairs(markers or {}) do
    if marker.pos <= pos + EPS then
      current = marker
    else
      break
    end
  end
  return current
end

local function annotate_groups_with_marker_rows(groups)
  local markers = collect_project_markers()
  local rows = {}
  local last_key = nil
  for _, group in ipairs(groups or {}) do
    local marker = marker_for_position(markers, group.region_start or group.start_pos or 0)
    local key = marker and tostring(marker.idx) or "__before_first_marker"
    local label
    if marker then
      if marker.lane == 2 and marker.parent_name then
        label = string.format("[M%d L2] %s / %s", marker.number or marker.idx or 0, marker.parent_name, marker.name or "")
      elseif marker.lane == 2 then
        label = string.format("[M%d L2] %s", marker.number or marker.idx or 0, marker.name or "")
      else
        label = string.format("[M%d L1] %s", marker.number or marker.idx or 0, marker.name or "")
      end
    else
      label = "[Prima del primo marker]"
    end
    if key ~= last_key then
      rows[#rows + 1] = {
        marker_only = true,
        marker_label = label,
        marker_name = marker and marker.name or "",
        marker_idx = marker and marker.idx or nil,
        marker_pos = marker and marker.pos or nil,
        marker_color = marker and marker.color or 0,
        marker_number = marker and marker.number or nil,
        marker_lane = marker and marker.lane or nil,
        marker_parent_name = marker and marker.parent_name or nil,
        marker_folder_parts = marker and marker.folder_parts or nil,
        marker_missing_parent_lane1 = marker and marker.missing_parent_lane1 or nil,
        name = label,
        region_start = group.region_start or group.start_pos or 0,
        region_end = group.region_start or group.start_pos or 0,
        existing = false
      }
      last_key = key
    end
    group.marker_label = label
    rows[#rows + 1] = group
  end
  return rows
end

local function is_region_row(group)
  return group and not group.marker_only
end

local function count_region_rows(groups)
  local count = 0
  for _, group in ipairs(groups or {}) do
    if is_region_row(group) then count = count + 1 end
  end
  return count
end

local function first_non_empty_name_row(names)
  for i, name in ipairs(names or {}) do
    if trim(name or "") ~= "" then return i end
  end
  return nil
end

local function next_region_row_index(groups, start_index)
  for i = math.max(1, start_index or 1), #(groups or {}) do
    if is_region_row(groups[i]) then return i end
  end
  return nil
end

local function build_preview_groups(items, gap, pad_in, pad_out)
  local item_groups = analyze_groups(items, gap, pad_in, pad_out)
  local existing_regions = collect_existing_regions(items)
  if #existing_regions == 0 then return annotate_groups_with_marker_rows(item_groups) end

  local groups = {}
  for _, region in ipairs(existing_regions) do table.insert(groups, region) end

  for _, group in ipairs(item_groups) do
    local covered = false
    for _, region in ipairs(existing_regions) do
      if ranges_overlap(group.region_start, group.region_end, region.region_start, region.region_end) then
        covered = true
        break
      end
    end
    if not covered then table.insert(groups, group) end
  end

  table.sort(groups, function(a, b) return a.region_start < b.region_start end)
  return annotate_groups_with_marker_rows(groups)
end

local function count_own_regions()
  local _, marker_count, region_count = reaper.CountProjectMarkers(0)
  local total = marker_count + region_count
  local count = 0
  for i = 0, total - 1 do
    local ok, is_region, _, _, _, _, color = reaper.EnumProjectMarkers3(0, i)
    if ok and is_region and is_lane1_enum_index(i) and color == REGION_COLOR then count = count + 1 end
  end
  return count
end

local function delete_own_regions()
  local _, marker_count, region_count = reaper.CountProjectMarkers(0)
  local total = marker_count + region_count
  local ids = {}
  for i = 0, total - 1 do
    local ok, is_region, _, _, _, idx, color = reaper.EnumProjectMarkers3(0, i)
    if ok and is_region and is_lane1_enum_index(i) and color == REGION_COLOR then table.insert(ids, idx) end
  end
  for _, idx in ipairs(ids) do
    reaper.DeleteProjectMarker(0, idx, true)
  end
  return #ids
end


local function is_warmup_region_name(name)
  return trim(name or "") == WARMUP_REGION_NAME
end

local function is_warmup_region(region)
  return region and (region.is_warmup or is_warmup_region_name(region.name))
end

local function real_mixdown_regions(regions)
  local out = {}
  for _, region in ipairs(regions or {}) do
    if not is_warmup_region(region) then out[#out + 1] = region end
  end
  return out
end

local function delete_warmup_regions()
  local _, marker_count, region_count = reaper.CountProjectMarkers(0)
  local ids = {}
  for i = 0, marker_count + region_count - 1 do
    local ok, is_region, _, _, name, idx, color = reaper.EnumProjectMarkers3(0, i)
    if ok and is_region and (is_warmup_region_name(name) or color == WARMUP_COLOR) then
      ids[#ids + 1] = idx
    end
  end
  for _, idx in ipairs(ids) do reaper.DeleteProjectMarker(0, idx, true) end
  return #ids
end

local function get_item_ext(item, key)
  if not (item and reaper.GetSetMediaItemInfo_String) then return "" end
  local ok, value = reaper.GetSetMediaItemInfo_String(item, "P_EXT:" .. key, "", false)
  return ok and tostring(value or "") or ""
end

local function set_item_ext(item, key, value)
  if item and reaper.GetSetMediaItemInfo_String then
    reaper.GetSetMediaItemInfo_String(item, "P_EXT:" .. key, tostring(value or ""), true)
  end
end

local function delete_warmup_items()
  local removed = 0
  for ti = reaper.CountTracks(0) - 1, 0, -1 do
    local track = reaper.GetTrack(0, ti)
    for ii = reaper.CountTrackMediaItems(track) - 1, 0, -1 do
      local item = reaper.GetTrackMediaItem(track, ii)
      local marked = get_item_ext(item, WARMUP_EXT_KEY) == "1"
      local color = math.floor(reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR") or 0)
      local len = tonumber(reaper.GetMediaItemInfo_Value(item, "D_LENGTH")) or 0
      if marked or (color == WARMUP_COLOR and len <= WARMUP_SECONDS + 0.25) then
        reaper.DeleteTrackMediaItem(track, item)
        removed = removed + 1
      end
    end
  end
  return removed
end

local function track_for_warmup(groups)
  for _, group in ipairs(groups or {}) do
    local entry = group.first_item or group.last_item
    if entry and entry.track then return entry.track end
  end
  local track = reaper.GetSelectedTrack(0, 0) or reaper.GetTrack(0, 0)
  if track then return track end
  reaper.InsertTrackAtIndex(0, true)
  track = reaper.GetTrack(0, 0)
  if track then reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "ZP Warmup Ghost", true) end
  return track
end

local function warmup_temp_dir()
  local dir = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
  return tostring(dir):gsub("[/\\]+$", "")
end

local function le16(n)
  n = math.floor(n or 0)
  return string.char(n % 256, math.floor(n / 256) % 256)
end

local function le32(n)
  n = math.floor(n or 0)
  return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

local function warmup_source_path()
  return warmup_temp_dir() .. sep .. WARMUP_SOURCE_NAME
end

local function write_warmup_source(path, duration)
  local sample_rate = 44100
  local samples = math.max(1, math.floor((duration or WARMUP_SECONDS) * sample_rate))
  local channels, bits = 1, 16
  local data_bytes = samples * channels * (bits // 8)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write("RIFF", le32(36 + data_bytes), "WAVE")
  f:write("fmt ", le32(16), le16(1), le16(channels), le32(sample_rate), le32(sample_rate * channels * bits // 8), le16(channels * bits // 8), le16(bits))
  f:write("data", le32(data_bytes))
  -- Real warm-up signal: low-level sine, not silence. It is rendered only into
  -- the technical ghost region and removed from customer-facing reports/files.
  local amp = math.floor(32767 * 0.03) -- about -30 dBFS
  local two_pi = math.pi * 2
  for i = 0, samples - 1 do
    local fade = 1
    local t = i / sample_rate
    if t < 0.05 then fade = t / 0.05 end
    if (duration - t) < 0.05 then fade = math.min(fade, math.max(0, (duration - t) / 0.05)) end
    local s = math.floor(math.sin(two_pi * 440 * t) * amp * fade)
    if s < 0 then s = s + 65536 end
    f:write(le16(s))
  end
  f:close()
  return true
end

local function delete_warmup_source()
  os.remove(warmup_source_path())
end

local function create_warmup_item(track, start_pos, end_pos)
  if not track or end_pos <= start_pos + EPS then return nil end
  local source_path = warmup_source_path()
  write_warmup_source(source_path, end_pos - start_pos)
  local item = reaper.AddMediaItemToTrack(track)
  if not item then return nil end
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", start_pos)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", end_pos - start_pos)
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", WARMUP_COLOR)
  set_item_ext(item, WARMUP_EXT_KEY, "1")
  if reaper.GetSetMediaItemInfo_String then
    reaper.GetSetMediaItemInfo_String(item, "P_NOTES", WARMUP_REGION_NAME, true)
  end
  if reaper.PCM_Source_CreateFromFile and reaper.AddTakeToMediaItem and reaper.SetMediaItemTake_Source then
    local src = reaper.PCM_Source_CreateFromFile(source_path)
    if src then
      local take = reaper.AddTakeToMediaItem(item)
      if take then
        reaper.SetMediaItemTake_Source(take, src)
        if reaper.GetSetMediaItemTakeInfo_String then
          reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", WARMUP_REGION_NAME, true)
        end
      end
    end
  end
  return item
end

local function first_real_region_start(groups)
  local first = nil
  for _, group in ipairs(groups or {}) do
    if is_region_row(group) then
      local pos = group.region_start or group.start_pos or 0
      first = first and math.min(first, pos) or pos
    end
  end
  return first
end

local function create_or_refresh_warmup_for_groups(groups)
  local has_region = false
  for _, group in ipairs(groups or {}) do
    if is_region_row(group) then has_region = true break end
  end
  if not has_region then return nil, "nessuna regione reale" end
  local warm_start = 0
  local warm_end = WARMUP_SECONDS

  delete_warmup_regions()
  delete_warmup_items()
  local idx = reaper.AddProjectMarker2(0, true, warm_start, warm_end, WARMUP_REGION_NAME, -1, WARMUP_COLOR)
  create_warmup_item(track_for_warmup(groups), warm_start, warm_end)
  return { idx = idx, pos = warm_start, rgn_end = warm_end, name = WARMUP_REGION_NAME, is_warmup = true }, nil
end

local function prepend_warmup_region(regions, groups)
  local warmup = create_or_refresh_warmup_for_groups(groups)
  if warmup then
    local out = { warmup }
    for _, region in ipairs(regions or {}) do out[#out + 1] = region end
    return out, warmup
  end
  return regions, nil
end

local mixdown_settings

local function delete_warmup_render_file(out_dir, settings)
  if not out_dir or out_dir == "" then return false end
  settings = settings or mixdown_settings()
  local extension = settings.format == "wav" and ".wav" or settings.format == "flac" and ".flac" or ".mp3"
  local path = out_dir .. "/" .. WARMUP_REGION_NAME .. extension
  os.remove(path)
  return true
end

local function read_text_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function write_text_file(path, data)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(data or "")
  f:close()
  return true
end

local function strip_warmup_row_from_render_stats(html)
  html = tostring(html or "")
  local safe_name = WARMUP_REGION_NAME:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  html = html:gsub("<tr>%s*<td>" .. safe_name .. "%.[^<]*</td>.-</tr>%s*", "")
  -- REAPER names the stats HTML after the first rendered file and also creates
  -- a first chart block for it. Keep the useful stats for real files, but hide
  -- the technical warm-up chart.
  html = html:gsub("<br><br>%s*<canvas id='chart_0'.-<canvas id='chart_1'", "<br><br>\n<canvas id='chart_1'")
  html = html:gsub(WARMUP_REGION_NAME .. "%.[%w]+", "")
  return html
end

local function normalize_warmup_render_stats(out_dir)
  if not out_dir or out_dir == "" then return nil end
  local src = out_dir .. "/" .. WARMUP_REGION_NAME .. ".render_stats.html"
  local html = read_text_file(src)
  if not html then return nil end
  local dst = out_dir .. "/Mixdown_Render_Stats.html"
  local cleaned = strip_warmup_row_from_render_stats(html)
  os.remove(dst)
  if write_text_file(dst, cleaned) then
    os.remove(src)
    return dst
  end
  return nil
end

local function basename_without_extension(path)
  local name = tostring(path or ""):match("([^/\\]+)$") or tostring(path or "")
  return (name:gsub("%.[^%.]+$", ""))
end

local function normalize_real_render_stats(out_dir, regions, settings)
  if not out_dir or out_dir == "" then return nil end
  -- Scan the output directory for any .render_stats.html file that is NOT the warmup one.
  -- REAPER names the stats file after the first rendered file, which may not match regions[1].name.
  local src = nil
  local p = io.popen('ls -1 "' .. out_dir:gsub('"', '\\"') .. '"')
  if p then
    for entry in p:lines() do
      if entry:match("%.render_stats%.html$") and not is_warmup_region_name(entry:match("^(.-)%.render_stats%.html$") or "") then
        src = out_dir .. "/" .. entry
        break
      end
    end
    p:close()
  end
  if not src then return nil end
  local html = read_text_file(src)
  if not html then return nil end
  local dst = out_dir .. "/Mixdown_Render_Stats.html"
  os.remove(dst)
  if write_text_file(dst, html) then
    os.remove(src)
    return dst
  end
  return nil
end

local function cleanup_warmup_after_render(out_dir, settings)
  delete_warmup_render_file(out_dir, settings)
  local stats_path = normalize_warmup_render_stats(out_dir)
  local removed_regions = delete_warmup_regions()
  local removed_items = delete_warmup_items()
  delete_warmup_source()
  reaper.UpdateArrange()
  return removed_regions, removed_items, stats_path
end

local function create_regions(groups, names, state)
  if #groups == 0 then
    speak("Nessun gruppo trovato.")
    return false
  end

  local old_count = count_own_regions()
  if state.delete_old and old_count > 0 then
    local message = string.format("Rimuovere prima %d regioni export create da questo script?", old_count)
    if reaper.ShowMessageBox(message, SCRIPT_TITLE, 4) ~= 6 then return false end
  end

  reaper.PreventUIRefresh(1)
  reaper.Undo_BeginBlock()

  if state.delete_old then delete_own_regions() end

  local created_count, updated_count, marker_count = 0, 0, 0
  local region_number_index = 0
  for _, group in ipairs(groups) do
    if group.marker_only then goto continue_create_region end
    region_number_index = region_number_index + 1
    local order = group.region_order or region_number_index
    local base_name = trim(group.edited_name or names[order] or names[region_number_index] or group.name or "")
    local region_number = string.format("%02d", region_number_index)
    local name = base_name ~= "" and base_name or region_number
    if state.number_names and base_name ~= "" then name = region_number .. " " .. base_name end
    if group.existing_region and group.existing_idx and (not state.delete_old or group.existing_color ~= REGION_COLOR) then
      if reaper.SetProjectMarker3 then
        reaper.SetProjectMarker3(0, group.existing_idx, true, group.region_start, group.region_end, name, REGION_COLOR)
      else
        reaper.DeleteProjectMarker(0, group.existing_idx, true)
        reaper.AddProjectMarker2(0, true, group.region_start, group.region_end, name, -1, REGION_COLOR)
      end
      updated_count = updated_count + 1
    else
      reaper.AddProjectMarker2(0, true, group.region_start, group.region_end, name, -1, REGION_COLOR)
      created_count = created_count + 1
    end
    if state.make_markers then
      reaper.AddProjectMarker2(0, false, group.start_pos, 0, name, -1, MARKER_COLOR)
      marker_count = marker_count + 1
    end
    ::continue_create_region::
  end

  reaper.Undo_EndBlock("Crea regioni export da item nominati", -1)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()

  local parts = {}
  if created_count > 0 then table.insert(parts, string.format("create %d", created_count)) end
  if updated_count > 0 then table.insert(parts, string.format("aggiornate %d", updated_count)) end
  if marker_count > 0 then table.insert(parts, string.format("marker %d", marker_count)) end
  if #parts == 0 then table.insert(parts, "nessuna modifica") end
  notify_status("Regioni export: " .. table.concat(parts, ", ") .. ".")
  return true
end


local function project_file_path()
  local _, path = reaper.EnumProjects(-1, "")
  path = trim(path or "")
  if path == "" then return nil end
  return path
end

local function path_dirname(path)
  return tostring(path or ""):match("^(.*)[/\\][^/\\]+$") or ""
end

local function project_dir()
  local path = project_file_path()
  if not path then return nil end
  return path_dirname(path)
end

local function project_name_without_ext()
  local path = project_file_path()
  if not path then return "" end
  local name = tostring(path):match("[^/\\]+$") or ""
  return (name:gsub("%.[Rr][Pp][Pp]$", ""))
end

local function sanitize_folder_name(name)
  local value = trim(tostring(name or ""))
  value = value:gsub("[/\\:*?\"<>|]", "_")
  value = value:gsub("[%c]", "_")
  value = value:gsub("%s+", " ")
  value = value:gsub("^%.+", ""):gsub("%s+$", "")
  if value == "" then value = "Mixdown_Export" end
  return value
end

local function sanitize_folder_path_parts(parts)
  local safe = {}
  for _, part in ipairs(parts or {}) do
    local value = sanitize_folder_name(part)
    if value ~= "" then safe[#safe + 1] = value end
  end
  if #safe == 0 then safe[1] = "Mixdown_Export" end
  return table.concat(safe, "/")
end

local function raw_folder_path_parts(parts)
  local raw = {}
  for _, part in ipairs(parts or {}) do
    local value = trim(part or "")
    if value ~= "" then raw[#raw + 1] = value end
  end
  if #raw == 0 then raw[1] = "Mixdown_Export" end
  return table.concat(raw, "/")
end

local function directory_exists(path)
  path = trim(path)
  if path == "" then return false end
  local ok, _, code = os.rename(path, path)
  if ok then return true end
  return code == 13 -- permission denied means the path exists
end

local function ensure_directory(path)
  path = trim(path)
  if path == "" then return false end
  if directory_exists(path) then return true end
  if reaper.RecursiveCreateDirectory then
    reaper.RecursiveCreateDirectory(path, 0)
    return directory_exists(path)
  end
  return false
end

local function region_rows_for_render(groups)
  local rows = {}
  for _, group in ipairs(groups or {}) do
    if is_region_row(group) and not is_warmup_region(group) then rows[#rows + 1] = group end
  end
  return rows
end

local function first_region_start(groups)
  local first = nil
  for _, group in ipairs(groups or {}) do
    if is_region_row(group) then
      local pos = group.region_start or group.start_pos or 0
      first = first and math.min(first, pos) or pos
    end
  end
  return first
end

local function render_folder_info(groups)
  local first_pos = first_region_start(groups)
  local markers = collect_project_markers()
  local marker = first_pos and marker_for_position(markers, first_pos) or nil
  local parts = marker and marker.folder_parts or { project_name_without_ext() }
  local source = marker and "marker" or "progetto"
  local raw_name = raw_folder_path_parts(parts)
  if trim(raw_name) == "" then raw_name = "Mixdown_Export" source = "fallback" end
  local safe_path = sanitize_folder_path_parts(parts)
  local safe_name = safe_path:match("([^/]+)$") or safe_path
  return {
    raw_name = raw_name,
    safe_name = safe_name,
    safe_path = safe_path,
    source = source,
    marker_lane = marker and marker.lane or nil,
    relative = "Mixdown/" .. safe_path .. "/"
  }
end

local function region_groups_for_marker_section(marker_row)
  if not (marker_row and marker_row.marker_pos) then return {} end
  local section_start = marker_row.marker_pos
  local section_end = nil
  for _, marker in ipairs(collect_project_markers()) do
    if marker.pos > section_start + EPS then
      section_end = marker.pos
      break
    end
  end

  local groups = {}
  local _, marker_count, region_count = reaper.CountProjectMarkers(0)
  local total = marker_count + region_count
  for i = 0, total - 1 do
    local ok, is_region, pos, rgn_end, name, idx, color = reaper.EnumProjectMarkers3(0, i)
    if ok and is_region and is_lane1_enum_index(i) and not (trim(name or "") == WARMUP_REGION_NAME or color == WARMUP_COLOR) and pos >= section_start - EPS and (not section_end or pos < section_end - EPS) then
      groups[#groups + 1] = {
        region_start = pos,
        region_end = rgn_end,
        start_pos = pos,
        end_pos = rgn_end,
        count = 0,
        existing_region = true,
        existing_idx = idx,
        existing_color = color,
        name = trim(name or ""),
        edited_name = trim(name or ""),
        region_order = #groups + 1
      }
    end
  end
  table.sort(groups, function(a, b) return (a.region_start or 0) < (b.region_start or 0) end)
  for i, group in ipairs(groups) do group.region_order = i end
  return groups
end

local function matching_export_regions(groups)
  local targets = region_rows_for_render(groups)
  local found = {}
  if #targets == 0 then return found end

  local _, marker_count, region_count = reaper.CountProjectMarkers(0)
  local total = marker_count + region_count
  for i = 0, total - 1 do
    local ok, is_region, pos, rgn_end, name, idx, color = reaper.EnumProjectMarkers3(0, i)
    if ok and is_region and is_lane1_enum_index(i) and not (trim(name or "") == WARMUP_REGION_NAME or color == WARMUP_COLOR) then
      for _, group in ipairs(targets) do
        local gs = group.region_start or group.start_pos or 0
        local ge = group.region_end or group.end_pos or 0
        if math.abs(pos - gs) <= 0.002 and math.abs(rgn_end - ge) <= 0.002 then
          found[#found + 1] = { idx = idx, pos = pos, rgn_end = rgn_end, name = trim(name or "") }
          break
        end
      end
    end
  end
  table.sort(found, function(a, b) return (a.pos or 0) < (b.pos or 0) end)
  return found
end

local function problematic_region_names(regions)
  local bad = {}
  for _, region in ipairs(regions or {}) do
    local name = trim(region.name or "")
    if name ~= "" and (name:find("[/\\:*?\"<>|]") or name:find("[%c]")) then
      bad[#bad + 1] = name
    end
  end
  return bad
end

local function listview_region_id(list, row_index)
  for col = 0, 4 do
    local text = reaper.JS_ListView_GetItemText(list, row_index, col) or ""
    local region_id = tonumber(text:match("^%s*R(%d+)%s*$"))
    if region_id then
      -- Verify it's actually the ID column by checking if it's very short. Names are usually longer.
      -- A safer way is to just return it, but if a name is exactly "R5", it might clash.
      return region_id
    end
  end
  return nil
end

local function select_regions_in_region_manager(regions)
  if not (reaper.JS_Window_Find and reaper.JS_Window_FindChildByID and
    reaper.JS_ListView_GetItemCount and reaper.JS_ListView_GetItemText and
    reaper.JS_ListView_SetItemState) then
    return false, "JS_ReaScript non disponibile: non posso selezionare con certezza solo le regioni export."
  end

  local selected_region_ids = {}
  for _, region in ipairs(regions or {}) do
    if not is_warmup_region(region) then
      selected_region_ids[region.idx] = true
    end
  end

  local title = reaper.JS_Localize and reaper.JS_Localize("Region/Marker Manager", "common") or "Region/Marker Manager"
  local manager = reaper.JS_Window_Find(title, true)
  local opened_manager = false
  if not manager then
    reaper.Main_OnCommand(40326, 0) -- View: Region/Marker Manager, open fresh
    manager = reaper.JS_Window_Find(title, true)
    opened_manager = manager ~= nil
  end
  if not manager then return false, "Non riesco ad aprire Region/Marker Manager." end

  local list = reaper.JS_Window_FindChildByID(manager, 1071)
  if not list then return false, "Non trovo la lista del Region/Marker Manager." end

  local item_count = reaper.JS_ListView_GetItemCount(list)
  reaper.JS_ListView_SetItemState(list, -1, 0x0, 0x3)
  local selected = 0
  for i = 0, item_count - 1 do
    local region_id = listview_region_id(list, i)
    if region_id and selected_region_ids[region_id] then
      reaper.JS_ListView_SetItemState(list, i, 0x3, 0x3)
      selected = selected + 1
    end
  end
  if opened_manager and reaper.JS_Window_Show then reaper.JS_Window_Show(manager, "HIDE") end
  if selected == 0 then return false, "Nessuna regione export selezionata nel Region/Marker Manager." end
  return true, nil, selected
end


local function set_time_selection_for_regions_or_groups(regions_or_groups)
  local first_pos, last_pos = nil, nil
  for _, entry in ipairs(regions_or_groups or {}) do
    local start_pos = entry.pos or entry.region_start or entry.start_pos
    local end_pos = entry.rgn_end or entry.region_end or entry.end_pos
    if start_pos and end_pos and end_pos > start_pos + EPS then
      first_pos = first_pos and math.min(first_pos, start_pos) or start_pos
      last_pos = last_pos and math.max(last_pos, end_pos) or end_pos
    end
  end
  if first_pos and last_pos then
    reaper.GetSet_LoopTimeRange(true, false, first_pos, last_pos, false)
    reaper.SetEditCurPos(first_pos, true, false)
    return true
  end
  return false
end

local function select_items_overlapping_groups(groups, state)
  local items = collect_items(state)
  if not items or #items == 0 then return 0 end
  reaper.SelectAllMediaItems(0, false)
  local selected = 0
  for _, item_entry in ipairs(items) do
    for _, group in ipairs(groups or {}) do
      local gs = group.region_start or group.start_pos or 0
      local ge = group.region_end or group.end_pos or 0
      if ranges_overlap(item_entry.pos, item_entry.end_pos, gs, ge) then
        reaper.SetMediaItemSelected(item_entry.item, true)
        selected = selected + 1
        break
      end
    end
  end
  if selected > 0 then
    set_time_selection_for_regions_or_groups(groups)
    reaper.UpdateArrange()
  end
  return selected
end

local function select_project_material_for_groups(groups, state)
  local existing = matching_export_regions(groups or {})
  if #existing > 0 then
    select_regions_in_region_manager(existing)
    set_time_selection_for_regions_or_groups(existing)
    reaper.UpdateArrange()
    return "regions", #existing
  end
  local selected_items = select_items_overlapping_groups(groups or {}, state)
  if selected_items > 0 then return "items", selected_items end
  set_time_selection_for_regions_or_groups(groups or {})
  return "range", 0
end

local function render_window_is_open(activate)
  local should_activate = activate ~= false
  if not reaper.JS_Window_Find then
    render_debug_log("render_window_is_open | JS_Window_Find non disponibile")
    return false
  end
  local probes = {
    { title = "Render to File", exact = true },
    { title = "Rendering to file", exact = false },
    { title = "Finished in", exact = false }
  }
  for _, probe in ipairs(probes) do
    local hwnd = reaper.JS_Window_Find(probe.title, probe.exact)
    render_debug_log("render_window_probe | title=" .. tostring(probe.title) .. " exact=" .. tostring(probe.exact) .. " hwnd=" .. tostring(hwnd))
    if hwnd then
      local visible = true
      if reaper.JS_Window_IsVisible then visible = reaper.JS_Window_IsVisible(hwnd) end
      render_debug_log("render_window_probe_found | title=" .. tostring(probe.title) .. " visible=" .. tostring(visible) .. " hwnd=" .. tostring(hwnd))
      if should_activate and not visible and reaper.JS_Window_Show then
        reaper.JS_Window_Show(hwnd, "RESTORE")
        if reaper.JS_Window_IsVisible then visible = reaper.JS_Window_IsVisible(hwnd) end
        render_debug_log("render_window_restore | title=" .. tostring(probe.title) .. " visible_after=" .. tostring(visible) .. " hwnd=" .. tostring(hwnd))
      end
      if visible then
        if should_activate and reaper.JS_Window_Show then reaper.JS_Window_Show(hwnd, "RESTORE") end
        if should_activate and reaper.JS_Window_SetForeground then reaper.JS_Window_SetForeground(hwnd) end
        render_debug_log("render_window_is_open | true title=" .. tostring(probe.title) .. " hwnd=" .. tostring(hwnd))
        return true, probe.title
      end
    end
  end
  render_debug_log("render_window_is_open | false")
  return false
end

-- Render Queue snapshot: REAPER salva il progetto corrente nel job.
-- Per accodare una sola sezione senza dipendere dal Region/Marker Manager,
-- togliamo temporaneamente dalla snapshot le altre regioni e le ripristiniamo subito.
local function queue_with_only_regions(regions, callback)
  local keep = {}
  for _, region in ipairs(regions or {}) do keep[region.idx] = true end
  local hidden = {}
  local _, marker_count, region_count = reaper.CountProjectMarkers(0)
  for i = 0, marker_count + region_count - 1 do
    local ok, is_region, pos, region_end, name, idx, color = reaper.EnumProjectMarkers3(0, i)
    if ok and is_region and not keep[idx] then
      hidden[#hidden + 1] = {
        idx = idx, pos = pos, region_end = region_end,
        name = name or "", color = color or 0
      }
    end
  end

  reaper.PreventUIRefresh(1)
  for _, region in ipairs(hidden) do
    reaper.DeleteProjectMarker(0, region.idx, true)
  end
  local ok, err = xpcall(callback, debug.traceback)
  for _, region in ipairs(hidden) do
    reaper.AddProjectMarker2(0, true, region.pos, region.region_end, region.name, region.idx, region.color)
  end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  return ok, err, #hidden
end

local function save_render_settings_snapshot()
  local fields = {
    "RENDER_BOUNDSFLAG", "RENDER_STARTPOS", "RENDER_ENDPOS", "RENDER_ADDTOPROJ",
    "RENDER_SRATE", "RENDER_CHANNELS", "RENDER_SETTINGS", "RENDER_NORMALIZE",
    "RENDER_FADEIN", "RENDER_FADEOUT", "RENDER_PADSTART", "RENDER_PADEND"
  }
  local lines = {}
  for _, key in ipairs(fields) do
    lines[#lines + 1] = key .. "=" .. tostring(reaper.GetSetProjectInfo(0, key, 0, false))
  end
  local _, render_file = reaper.GetSetProjectInfo_String(0, "RENDER_FILE", "", false)
  local _, render_pattern = reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "", false)
  lines[#lines + 1] = "RENDER_FILE=" .. tostring(render_file or "")
  lines[#lines + 1] = "RENDER_PATTERN=" .. tostring(render_pattern or "")
  reaper.SetProjExtState(0, EXT_SECTION, "previous_render_settings", table.concat(lines, "\n"))
end


local MIXDOWN_PRESETS = {
  { id = "wav24_project_mono", label = "WAV 24 Progetto mono", format = "wav", sample_rate = "project", quality = "24", channels = "mono" },
  { id = "wav16_48_mono", label = "WAV 16 48 mono", format = "wav", sample_rate = "48000", quality = "16", channels = "mono" },
  { id = "wav24_48_mono", label = "WAV 24 48 mono", format = "wav", sample_rate = "48000", quality = "24", channels = "mono" },
  { id = "mp3_128_441_mono", label = "MP3 44.1 128 mono", format = "mp3", sample_rate = "44100", quality = "128", channels = "mono" },
  { id = "mp3_192_48_mono", label = "MP3 48 192 mono", format = "mp3", sample_rate = "48000", quality = "192", channels = "mono" },
  { id = "mp3_320_48_stereo", label = "MP3 48 320 stereo", format = "mp3", sample_rate = "48000", quality = "320", channels = "stereo" }
}

local function mixdown_project_get(key)
  local ok, value = reaper.GetProjExtState(0, EXT_SECTION, key)
  return ok == 1 and trim(value or "") or ""
end

local function mixdown_project_set(key, value)
  reaper.SetProjExtState(0, EXT_SECTION, key, tostring(value or ""))
end

local function mixdown_preset_by_id(id)
  if id == "mp3_120_441_mono" then id = "mp3_128_441_mono" end
  for _, preset in ipairs(MIXDOWN_PRESETS) do
    if preset.id == id then return preset end
  end
  return MIXDOWN_PRESETS[4]
end

function mixdown_settings()
  local preset_id = mixdown_project_get("mixdown_render_preset")
  if preset_id == "custom" then
    return {
      id = "custom",
      label = "Custom",
      format = mixdown_project_get("mixdown_render_format") ~= "" and mixdown_project_get("mixdown_render_format") or "mp3",
      sample_rate = mixdown_project_get("mixdown_render_sample_rate") ~= "" and mixdown_project_get("mixdown_render_sample_rate") or "44100",
      quality = mixdown_project_get("mixdown_render_quality") ~= "" and mixdown_project_get("mixdown_render_quality") or "128",
      channels = mixdown_project_get("mixdown_render_channels") ~= "" and mixdown_project_get("mixdown_render_channels") or "mono"
    }
  end
  return mixdown_preset_by_id(preset_id)
end

local function sample_rate_value(id)
  if id == "44100" then return 44100 end
  if id == "48000" then return 48000 end
  if id == "96000" then return 96000 end
  return 0
end

local function channels_value(id)
  return id == "stereo" and 2 or 1
end

local function mixdown_summary(settings)
  settings = settings or mixdown_settings()
  local sr = settings.sample_rate == "project" and "Progetto" or (settings.sample_rate == "44100" and "44.1" or (settings.sample_rate == "48000" and "48" or "96"))
  local fmt = string.upper(settings.format or "mp3")
  local quality = trim(settings.quality or "")
  if fmt == "MP3" and quality == "120" then quality = "128" end
  local ch = settings.channels == "stereo" and "stereo" or "mono"
  return trim(table.concat({ fmt, sr, quality, ch }, " "))
end

local function base64_encode(data)
  local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  return ((data:gsub(".", function(x)
    local r, byte = "", x:byte()
    for i = 8, 1, -1 do r = r .. (byte % 2 ^ i - byte % 2 ^ (i - 1) > 0 and "1" or "0") end
    return r
  end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
    if #x < 6 then return "" end
    local c = 0
    for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
    return b:sub(c + 1, c + 1)
  end) .. ({ "", "==", "=" })[#data % 3 + 1])
end

local function bytes_from_table(conf)
  local out = ""
  local len = conf.len or #conf
  for i = 1, len do out = out .. string.char(conf[i] or 0) end
  return out
end

local function encoded_mixdown_render_format(settings)
  settings = settings or mixdown_settings()
  if settings.format == "wav" then
    local depth = tonumber(settings.quality) or 24
    return base64_encode("evaw" .. bytes_from_table({ [1] = depth, [2] = 1 }))
  elseif settings.format == "mp3" then
    local bitrate = tonumber(settings.quality) or 128
    if bitrate == 120 then bitrate = 128 end
    return base64_encode("l3pm" .. bytes_from_table({
      [1] = bitrate, [2] = 0, [5] = 232, [6] = 3, [9] = 2,
      [13] = 255, [14] = 255, [15] = 255, [16] = 255, [17] = 4,
      [21] = bitrate, len = 28
    }))
  end
  return nil
end

local function apply_mixdown_render_settings()
  local settings = mixdown_settings()
  local encoded = encoded_mixdown_render_format(settings)
  if encoded then
    reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT", encoded, true)
    reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT2", "", true)
  end
  reaper.GetSetProjectInfo(0, "RENDER_SRATE", sample_rate_value(settings.sample_rate), true)
  reaper.GetSetProjectInfo(0, "RENDER_CHANNELS", channels_value(settings.channels), true)
end

local function copy_mixdown_settings(settings)
  settings = settings or mixdown_settings()
  return {
    id = settings.id or "custom",
    label = settings.label or "Custom",
    format = settings.format or "mp3",
    sample_rate = settings.sample_rate or "44100",
    quality = (settings.format == "mp3" and settings.quality == "120") and "128" or (settings.quality or "128"),
    channels = settings.channels or "mono"
  }
end

local function save_mixdown_settings(settings)
  settings = copy_mixdown_settings(settings)
  mixdown_project_set("mixdown_render_preset", "custom")
  mixdown_project_set("mixdown_render_format", settings.format)
  mixdown_project_set("mixdown_render_sample_rate", settings.sample_rate)
  mixdown_project_set("mixdown_render_quality", settings.quality)
  mixdown_project_set("mixdown_render_channels", settings.channels)
end

local function render_folder_info_from_marker_row(group)
  if not (group and group.marker_only) then return nil end
  local parts = group.marker_folder_parts or { group.marker_name or "" }
  if raw_folder_path_parts(parts) == "Mixdown_Export" and trim(group.marker_name or "") == "" then
    parts = { project_name_without_ext() }
  end
  local raw_name = raw_folder_path_parts(parts)
  if trim(raw_name) == "" then raw_name = "Mixdown_Export" end
  local safe_path = sanitize_folder_path_parts(parts)
  local safe_name = safe_path:match("([^/]+)$") or safe_path
  return {
    raw_name = raw_name,
    safe_name = safe_name,
    safe_path = safe_path,
    source = "marker",
    marker_lane = group.marker_lane,
    relative = "Mixdown/" .. safe_path .. "/"
  }
end

local function mixdown_folder_path(info)
  local proj_dir = project_dir()
  if not proj_dir or not info then return nil end
  return proj_dir .. "/Mixdown/" .. (info.safe_path or info.safe_name)
end

local function directory_has_files(path)
  if not directory_exists(path) then return false end
  if reaper.EnumerateFiles then
    return reaper.EnumerateFiles(path, 0) ~= nil
  end
  return false
end

local function render_queue_files()
  local dir = reaper.GetResourcePath() .. sep .. "QueuedRenders"
  local files = {}
  local i = 0
  while true do
    local name = reaper.EnumerateFiles(dir, i)
    if not name then break end
    files[name] = true
    i = i + 1
  end
  return files
end

local function render_queue_count()
  local count = 0
  for _ in pairs(render_queue_files()) do count = count + 1 end
  return count
end

local function mixdown_folder_status(info)
  if not info then return "gray", "nessuna sezione" end
  local path = mixdown_folder_path(info)
  if not path then return "red", "salva progetto" end
  if directory_exists(path) and directory_has_files(path) then return "yellow", "cartella con file" end
  if directory_exists(path) then return "green", "cartella pronta" end
  return "green", "cartella da creare"
end

local function draw_mixdown_status_dot(x, y, status)
  if status == "green" then gfx.set(0.25, 0.85, 0.48, 1)
  elseif status == "yellow" then gfx.set(0.95, 0.76, 0.22, 1)
  elseif status == "red" then gfx.set(0.95, 0.30, 0.26, 1)
  else gfx.set(0.42, 0.43, 0.48, 1) end
  gfx.circle(x, y, 5, true)
end

local function csv_escape(value)
  value = tostring(value or "")
  if value:find('[,"\n\r]') then return '"' .. value:gsub('"', '""') .. '"' end
  return value
end

local function csv_parse_line(line)
  local out, value, i, quoted = {}, "", 1, false
  line = tostring(line or "")
  while i <= #line do
    local ch = line:sub(i, i)
    if quoted then
      if ch == '"' then
        if line:sub(i + 1, i + 1) == '"' then
          value = value .. '"'
          i = i + 1
        else
          quoted = false
        end
      else
        value = value .. ch
      end
    else
      if ch == '"' and value == "" then
        quoted = true
      elseif ch == "," then
        out[#out + 1] = value
        value = ""
      else
        value = value .. ch
      end
    end
    i = i + 1
  end
  out[#out + 1] = value
  return out
end

local function report_time(seconds)
  local value = math.max(0, tonumber(seconds) or 0)
  local hours = math.floor(value / 3600)
  local minutes = math.floor((value - hours * 3600) / 60)
  local secs = value - hours * 3600 - minutes * 60
  return string.format("%02d:%02d:%06.3f", hours, minutes, secs)
end

local function save_mixdown_index_csv(regions, folder, out_dir, settings, extension)
  regions = real_mixdown_regions(regions)
  local proj_dir = project_dir()
  if not proj_dir then return nil, "Progetto non salvato" end
  local mixdown_root = proj_dir .. "/Mixdown"
  ensure_directory(mixdown_root)
  local folder_path = tostring((folder and folder.safe_path) or (folder and folder.safe_name) or "")
  local lane1_folder = folder_path:match("^([^/]+)") or ""
  if lane1_folder == "" then lane1_folder = sanitize_folder_name((folder and folder.raw_name) or project_name_without_ext()) end
  local index_dir = mixdown_root .. "/" .. lane1_folder
  ensure_directory(index_dir)
  local index_path = index_dir .. "/Mixdown_Index.csv"
  local header = "Aggiornato,Progetto,Sezione,Cartella,Formato,Regione,Start,End,Durata,File previsto,Presente"
  local current_keys = {}
  for _, region in ipairs(regions or {}) do
    local start_pos = tonumber(region.pos) or 0
    local end_pos = tonumber(region.rgn_end) or start_pos
    local key = table.concat({
      tostring(folder.relative or out_dir or ""),
      tostring(region.name or ""),
      report_time(start_pos),
      report_time(end_pos)
    }, "\t")
    current_keys[key] = true
  end

  local kept = {}
  local existing = io.open(index_path, "r")
  if existing then
    for line in existing:lines() do
      if line ~= "" and line ~= header then
        local cols = csv_parse_line(line)
        local key = table.concat({
          tostring(cols[4] or ""),
          tostring(cols[6] or ""),
          tostring(cols[7] or ""),
          tostring(cols[8] or "")
        }, "\t")
        if not current_keys[key] then
          if #cols < 11 then
            cols[11] = ""
            local normalized = {}
            for ci = 1, 11 do normalized[ci] = csv_escape(cols[ci] or "") end
            kept[#kept + 1] = table.concat(normalized, ",")
          else
            kept[#kept + 1] = line
          end
        end
      end
    end
    existing:close()
  end

  local now = os.date("%Y-%m-%d %H:%M:%S")
  local rows = { header }
  for _, line in ipairs(kept) do rows[#rows + 1] = line end
  for _, region in ipairs(regions or {}) do
    local start_pos = tonumber(region.pos) or 0
    local end_pos = tonumber(region.rgn_end) or start_pos
    local duration = math.max(0, end_pos - start_pos)
    local file_name = tostring(region.name or "") .. extension
    local present = ""
    local present_file = io.open((out_dir or "") .. sep .. file_name, "rb")
    if present_file then
      present_file:close()
      present = "X"
    end
    rows[#rows + 1] = table.concat({
      csv_escape(now),
      csv_escape(project_name_without_ext()),
      csv_escape(folder.raw_name or folder.safe_name or ""),
      csv_escape(folder.relative or out_dir or ""),
      csv_escape(mixdown_summary(settings)),
      csv_escape(region.name or ""),
      csv_escape(report_time(start_pos)),
      csv_escape(report_time(end_pos)),
      csv_escape(string.format("%.3f", duration)),
      csv_escape(file_name),
      csv_escape(present)
    }, ",")
  end

  local file, err = io.open(index_path, "w")
  if not file then return nil, err or "Impossibile scrivere Mixdown_Index.csv" end
  file:write(table.concat(rows, "\n"))
  file:write("\n")
  file:close()
  reaper.SetProjExtState(0, EXT_SECTION, "mixdown_index_csv", index_path)
  return index_path, nil
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function expected_mixdown_files(regions, out_dir, settings)
  regions = real_mixdown_regions(regions)
  local extension = settings.format == "wav" and ".wav" or settings.format == "flac" and ".flac" or ".mp3"
  local files = {}
  for _, region in ipairs(regions or {}) do
    files[#files + 1] = out_dir .. "/" .. tostring(region.name or "") .. extension
  end
  return files
end

local function all_expected_mixdown_files_exist(regions, out_dir, settings)
  local files = expected_mixdown_files(regions, out_dir, settings)
  if #files == 0 then return false, files end
  for _, path in ipairs(files) do
    if not file_exists(path) then return false, files end
  end
  return true, files
end

local function save_mixdown_reports(regions, folder, out_dir, settings_override)
  regions = real_mixdown_regions(regions)
  local settings = settings_override or mixdown_settings()
  local extension = settings.format == "wav" and ".wav" or settings.format == "flac" and ".flac" or ".mp3"
  local proj_dir = project_dir()
  if not proj_dir then return nil, "Progetto non salvato" end

  local mixdown_root = proj_dir .. "/Mixdown"
  local dest_dir = directory_exists(mixdown_root) and mixdown_root or proj_dir
  if not directory_exists(mixdown_root) then
    ensure_directory(mixdown_root)
    if directory_exists(mixdown_root) then dest_dir = mixdown_root end
  end

  local index_path, index_err = nil, nil
  if bool_from_state(reaper.GetExtState(EXT_SECTION, "mixdown_index_enabled"), false) then
    index_path, index_err = save_mixdown_index_csv(regions, folder, out_dir, settings, extension)
  else
    reaper.SetProjExtState(0, EXT_SECTION, "mixdown_index_csv", "")
  end

  if not bool_from_state(reaper.GetExtState(EXT_SECTION, "mixdown_log_enabled"), false) then
    -- Log OFF is an intentional skip, not a failed CSV write.
    return nil, nil, nil, index_path, index_err, true
  end

  local history_path = dest_dir .. "/Mixdown_History.csv"
  local created = os.date("%Y-%m-%d %H:%M:%S")
  local file_existed = file_exists(history_path)

  local c, csv_err = io.open(history_path, "a")
  if not c then return nil, csv_err or "Impossibile scrivere Mixdown_History.csv", nil, index_path, index_err end

  if not file_existed then
    c:write("Data e Ora,Progetto,Sezione,Cartella Destinazione,Regione,Start,End,Durata,Durata sec\n")
  end

  for _, region in ipairs(regions or {}) do
    local start_pos = tonumber(region.pos) or 0
    local end_pos = tonumber(region.rgn_end) or start_pos
    local duration = math.max(0, end_pos - start_pos)
    local row = table.concat({
      csv_escape(created),
      csv_escape(project_name_without_ext()),
      csv_escape(folder.raw_name or folder.safe_name or ""),
      csv_escape(folder.relative or out_dir),
      csv_escape(region.name or ""),
      csv_escape(report_time(start_pos)),
      csv_escape(report_time(end_pos)),
      csv_escape(report_time(duration)),
      csv_escape(string.format("%.3f", duration))
    }, ",")
    c:write(row .. "\n")
  end
  c:close()

  reaper.SetProjExtState(0, EXT_SECTION, "mixdown_report_txt", "")
  reaper.SetProjExtState(0, EXT_SECTION, "mixdown_report_csv", history_path)
  if index_path then reaper.SetProjExtState(0, EXT_SECTION, "mixdown_index_csv", index_path) end
  return history_path, nil, history_path, index_path, index_err
end

local function setup_mixdown_render_target(groups, folder_override, action_label, allow_all_regions_fallback, queue_snapshot_mode, enable_preroll_warmup)
  enable_preroll_warmup = enable_preroll_warmup and true or false
  local rows = region_rows_for_render(groups)
  render_debug_log(string.format(
    "setup_mixdown_render_target | start action=%s groups=%d rows=%d fallback=%s queue_snapshot=%s warmup=%s",
    log_escape(action_label or ""),
    #(groups or {}),
    #rows,
    tostring(allow_all_regions_fallback),
    tostring(queue_snapshot_mode),
    tostring(enable_preroll_warmup)
  ))
  if #rows == 0 then
    render_debug_log("setup_mixdown_render_target | stop nessuna regione valida")
    speak("Nessuna regione valida da preparare per il render.")
    return false
  end

  local regions = matching_export_regions(groups)
  if #regions == 0 then
    render_debug_log("setup_mixdown_render_target | stop nessuna regione allineata")
    reaper.ShowMessageBox(
      "Non trovo regioni gia' create/allineate nel progetto.\n\nPrima usa 'Crea regioni', oppure verifica che le regioni esistenti combacino con l'anteprima.",
      SCRIPT_TITLE,
      0
    )
    return false
  end

  if enable_preroll_warmup then
    regions = prepend_warmup_region(regions, groups)
    render_debug_log("setup_mixdown_render_target | warmup region prepended regions=" .. tostring(#regions))
    if reaper.JS_Window_Find and reaper.JS_Window_Show then
      local title = reaper.JS_Localize and reaper.JS_Localize("Region/Marker Manager", "common") or "Region/Marker Manager"
      local manager = reaper.JS_Window_Find(title, true)
      if manager then
        local was_visible = reaper.JS_Window_IsVisible and reaper.JS_Window_IsVisible(manager)
        reaper.Main_OnCommand(40326, 0) -- close
        reaper.Main_OnCommand(40326, 0) -- open
        manager = reaper.JS_Window_Find(title, true)
        if manager and not was_visible then reaper.JS_Window_Show(manager, "HIDE") end
      end
    end
  else
    delete_warmup_regions()
    delete_warmup_items()
    delete_warmup_source()
  end

  local bad_names = problematic_region_names(real_mixdown_regions(regions))
  if #bad_names > 0 then
    local preview = {}
    for i = 1, math.min(#bad_names, 12) do preview[#preview + 1] = "- " .. bad_names[i] end
    if #bad_names > 12 then preview[#preview + 1] = string.format("... altre %d", #bad_names - 12) end
    local msg = "Alcune regioni contengono caratteri potenzialmente problematici per i nomi file.\n\n" ..
      table.concat(preview, "\n") ..
      "\n\nNon le modifico automaticamente. REAPER o il sistema operativo potrebbero rifiutare o adattare i nomi finali.\n\nProcedere comunque " .. tostring(action_label or "preparando il render") .. "?"
    if reaper.ShowMessageBox(msg, SCRIPT_TITLE, 4) ~= 6 then return false end
  end

  local proj_dir = project_dir()
  if not proj_dir then
    render_debug_log("setup_mixdown_render_target | stop progetto non salvato")
    reaper.ShowMessageBox("Salva prima il progetto: la cartella Mixdown viene creata accanto al file .RPP.", SCRIPT_TITLE, 0)
    return false
  end

  local folder = folder_override or render_folder_info(groups)
  local out_dir = mixdown_folder_path(folder)
  render_debug_log(string.format(
    "setup_mixdown_render_target | target folder=%s out_dir=%s",
    log_escape((folder and (folder.relative or folder.safe_name or folder.raw_name)) or ""),
    log_escape(out_dir or "")
  ))
  if not ensure_directory(out_dir) then
    render_debug_log("setup_mixdown_render_target | stop impossibile creare cartella")
    reaper.ShowMessageBox("Non riesco a creare la cartella:\n" .. out_dir, SCRIPT_TITLE, 0)
    return false
  end

  save_render_settings_snapshot()

  local selected_ok, select_err, selected_count
  if queue_snapshot_mode then
    selected_ok, selected_count = true, #regions
    reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 3, true) -- sole regioni presenti nella snapshot del job
    render_debug_log("setup_mixdown_render_target | queue snapshot mode selected_count=" .. tostring(selected_count))
  else
    selected_ok, select_err, selected_count = select_regions_in_region_manager(regions)
    render_debug_log(string.format(
      "setup_mixdown_render_target | region manager selection ok=%s count=%s err=%s",
      tostring(selected_ok),
      tostring(selected_count),
      log_escape(select_err or "")
    ))
  end
  if queue_snapshot_mode then
    -- +Queue usa una snapshot multi-regione autonoma: nessun Region/Marker Manager richiesto.
  elseif selected_ok then
    local expected_selected_count = #real_mixdown_regions(regions)
    if selected_count and selected_count ~= expected_selected_count then
      if enable_preroll_warmup then
        delete_warmup_regions()
        delete_warmup_items()
        delete_warmup_source()
        reaper.UpdateArrange()
      end
      reaper.ShowMessageBox(
        "Selezione regioni non coerente: REAPER ha selezionato " .. tostring(selected_count) ..
        " regioni reali, ma il render ne richiede " .. tostring(expected_selected_count) .. ".\n\n" ..
        "Fermo il render per evitare nomi scalati o file mancanti. Ho gia' aggiornato il Region/Marker Manager prima del controllo; riprova una volta. Se il problema resta, spegni Ghost per questa sessione.",
        SCRIPT_TITLE,
        0
      )
      return false
    end
    reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 5, true) -- Selected regions
  else
    if not allow_all_regions_fallback then
      render_debug_log("setup_mixdown_render_target | stop no fallback select_err=" .. log_escape(select_err or ""))
      reaper.ShowMessageBox(
        tostring(select_err or "Selezione regioni non disponibile") ..
        "\n\nNon aggiungo alla Render Queue per evitare una coda troppo ampia o sbagliata. Installa/attiva JS_ReaScript oppure usa 'Render' e controlla manualmente.",
        SCRIPT_TITLE,
        0
      )
      return false
    end
    local msg = tostring(select_err or "Selezione regioni non disponibile") ..
      "\n\nPosso aprire Render to File su TUTTE le regioni del progetto, ma controlla bene prima di premere Render.\n\nProcedere comunque?"
    if reaper.ShowMessageBox(msg, SCRIPT_TITLE, 4) ~= 6 then return false end
    reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 3, true) -- Project regions
    render_debug_log("setup_mixdown_render_target | fallback tutte le regioni accettato")
  end

  reaper.GetSetProjectInfo(0, "RENDER_SETTINGS", 0, true) -- Master mix
  reaper.GetSetProjectInfo(0, "RENDER_ADDTOPROJ", 0, true)
  apply_mixdown_render_settings()
  reaper.GetSetProjectInfo(0, "RENDER_FADEIN", 0, true)
  reaper.GetSetProjectInfo_String(0, "RENDER_FILE", out_dir, true)
  reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "$region", true)

  reaper.SetProjExtState(0, EXT_SECTION, "mixdown_pending_report_folder", out_dir)
  reaper.SetProjExtState(0, EXT_SECTION, "mixdown_pending_report_section", folder.raw_name or folder.safe_name or "")
  reaper.SetProjExtState(0, EXT_SECTION, "mixdown_pending_report_note", "Report CSV audio da generare dopo render/dry run.")

  local detail = selected_ok and string.format("%d regioni selezionate", selected_count or #regions) or "tutte le regioni del progetto"
  render_debug_project_state("setup_mixdown_render_target | ready detail=" .. detail)
  return true, folder, detail, nil, regions
end

local function prepare_render_mixdown(groups, folder_override, enable_preroll_warmup)
  render_debug_log(string.format(
    "prepare_render_mixdown | start groups=%d warmup=%s folder=%s",
    #(groups or {}),
    tostring(enable_preroll_warmup and true or false),
    log_escape((folder_override and (folder_override.relative or folder_override.safe_name or folder_override.raw_name)) or "")
  ))
  local already_open, render_window_title = render_window_is_open(true)
  if already_open then
    render_debug_log("prepare_render_mixdown | stop render gia aperto title=" .. tostring(render_window_title or ""))
    reaper.ShowMessageBox("Ho trovato una finestra render visibile o ripristinabile (" .. tostring(render_window_title or "Render") .. ").\n\nL'ho riportata davanti se possibile: chiudila prima di aprire un nuovo Render to File. Questo evita la doppia finestra che puo' bloccare REAPER.", SCRIPT_TITLE, 0)
    return false
  end
  local ok, folder, detail, report_path, regions = setup_mixdown_render_target(groups, folder_override, "preparando Render to File", true, false, enable_preroll_warmup)
  if not ok then
    render_debug_log("prepare_render_mixdown | setup fallito")
    return false
  end
  render_debug_project_state("prepare_render_mixdown | before Main_OnCommand 40015")
  reaper.Main_OnCommand(40015, 0) -- File: Render project to disk... apre Render to File, non avvia il render
  render_debug_project_state("prepare_render_mixdown | after Main_OnCommand 40015")
  return true, folder, regions
end

local function add_mixdown_section_to_queue(groups, folder_override)
  render_debug_log(string.format(
    "add_mixdown_section_to_queue | start groups=%d folder=%s",
    #(groups or {}),
    log_escape((folder_override and (folder_override.relative or folder_override.safe_name or folder_override.raw_name)) or "")
  ))
  local ok, folder, detail, report_path, regions = setup_mixdown_render_target(groups, folder_override, "aggiungendo la sezione alla Render Queue", false, true)
  if not ok then
    render_debug_log("add_mixdown_section_to_queue | setup fallito")
    return false
  end
  local before = render_queue_files()
  local before_count = 0
  for _ in pairs(before) do before_count = before_count + 1 end
  render_debug_log("add_mixdown_section_to_queue | before queue files=" .. tostring(before_count))
  -- Un solo job contiene tutte le regioni della sezione/cartella scelta.
  -- La snapshot temporanea esclude le altre sezioni senza alterare il progetto finale.
  local snapshot_ok, snapshot_err = queue_with_only_regions(regions, function()
    render_debug_project_state("add_mixdown_section_to_queue | inside snapshot before command")
    reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 3, true) -- Project regions presenti nella snapshot
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE", mixdown_folder_path(folder), true)
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "$region", true)
    reaper.Main_OnCommand(ADD_TO_RENDER_QUEUE_CMD, 0)
  end)
  if not snapshot_ok then
    render_debug_log("add_mixdown_section_to_queue | snapshot fallita err=" .. log_escape(snapshot_err or ""))
    reaper.ShowMessageBox("Non riesco a preparare il job multi-regione:\n" .. tostring(snapshot_err or "errore sconosciuto"), SCRIPT_TITLE, 0)
    return false
  end
  local after = render_queue_files()
  local queued = 0
  for name in pairs(after) do
    if not before[name] then queued = queued + 1 end
  end
  render_debug_log("add_mixdown_section_to_queue | queued_delta=" .. tostring(queued))
  if queued == 0 then
    render_debug_log("add_mixdown_section_to_queue | stop nessun job creato")
    reaper.ShowMessageBox("REAPER non ha creato alcun job nella Render Queue.\n\nControlla che il progetto sia salvato e che il formato Render sia valido.", SCRIPT_TITLE, 0)
    return false
  end
  notify_status(string.format("Aggiunto un job multi-regione alla Render Queue: %s, %d regioni incluse. Il warm-up fantasma e' usato solo nel render manuale, non nella Queue. Report audio CSV da generare dopo il render/dry run.", folder.relative, #real_mixdown_regions(regions)))
  return true
end

local function format_time(seconds)
  local value = math.max(0, seconds or 0)
  local m = math.floor(value / 60)
  local s = value - (m * 60)
  return string.format("%02d:%06.3f", m, s)
end

local function draw_button(rect, label, active, enabled, clicked, style)
  return ZP_UI.draw_button(rect, label, active, enabled, clicked, style)
end

local function draw_export_icon(x, y, size)
  gfx.set(0.10, 0.42, 0.48, 1)
  gfx.rect(x, y, size, size, true)
  gfx.set(0.05, 0.18, 0.22, 1)
  gfx.rect(x, y, size, size, false)
  gfx.set(0.92, 0.88, 0.70, 1)
  local pad = math.max(5, math.floor(size * 0.17))
  gfx.rect(x + pad, y + pad + 2, size - pad * 2, size - pad * 2 - 4, false)
  gfx.line(x + pad, y + size * 0.46, x + size - pad, y + size * 0.46)
  gfx.line(x + size * 0.38, y + pad + 2, x + size * 0.38, y + size - pad - 2)
  gfx.line(x + size * 0.62, y + pad + 2, x + size * 0.62, y + size - pad - 2)
end

local function draw_v_scroll(box, total, visible, scroll)
  if total <= visible or visible <= 0 then return end
  local track_x = box.x + box.w - 8
  local track_y = box.y + 6
  local track_h = math.max(20, box.h - 12)
  local thumb_h = math.max(24, math.floor(track_h * (visible / total)))
  local max_scroll = math.max(1, total - visible)
  local thumb_y = track_y + math.floor((track_h - thumb_h) * (scroll / max_scroll))
  gfx.set(0.18, 0.18, 0.23, 1)
  gfx.rect(track_x, track_y, 4, track_h, true)
  gfx.set(0.30, 0.58, 0.72, 1)
  gfx.rect(track_x, thumb_y, 4, thumb_h, true)
end

local KEY_BACKSPACE = 8
local KEY_DELETE = 6579564
local KEY_LEFT = 1818584692
local KEY_RIGHT = 1919379572
local KEY_UP = 30064
local KEY_DOWN = 1685026670
local KEY_HOME = 1752132965
local KEY_END = 6647396
local KEY_TAB = 9

local function is_select_all_key(ch)
  if ch == 1 then return true end
  local ctrl_or_cmd = (gfx.mouse_cap & 4) == 4 or (gfx.mouse_cap & 32) == 32
  return ctrl_or_cmd and (ch == 65 or ch == 97)
end

local function is_navigation_key(ch)
  return ch == KEY_LEFT or ch == KEY_RIGHT or ch == KEY_HOME or ch == KEY_END
end

local function is_delete_key(ch)
  return ch == KEY_BACKSPACE or ch == KEY_DELETE
end

local function prev_cursor(text, cursor)
  text = tostring(text or "")
  cursor = math.max(1, math.min(cursor or (#text + 1), #text + 1))
  if cursor <= 1 then return 1 end
  if utf8 and utf8.offset then
    local p = utf8.offset(text, -1, cursor)
    if p then return p end
  end
  return math.max(1, cursor - 1)
end

local function next_cursor(text, cursor)
  text = tostring(text or "")
  cursor = math.max(1, math.min(cursor or (#text + 1), #text + 1))
  if cursor > #text then return #text + 1 end
  if utf8 and utf8.offset then
    local n = utf8.offset(text, 2, cursor)
    if n then return n end
  end
  return math.min(#text + 1, cursor + 1)
end

local function cursor_from_x(text, target_x, left_x)
  text = tostring(text or "")
  target_x = target_x or left_x
  local last_pos = 1
  local pos = 1
  while pos <= #text do
    local next_pos = next_cursor(text, pos)
    local before = text:sub(1, pos - 1)
    local chunk = text:sub(1, next_pos - 1)
    local mid = left_x + gfx.measurestr(before) + ((gfx.measurestr(chunk) - gfx.measurestr(before)) * 0.5)
    if target_x < mid then return pos end
    last_pos = next_pos
    pos = next_pos
  end
  return #text + 1
end

local caps_lock_cache_time = nil
local caps_lock_cache_value = false

local function caps_lock_on()
  if reaper.GetOS and tostring(reaper.GetOS()):match("OSX") then
    local now = reaper.time_precise and reaper.time_precise() or os.clock()
    if caps_lock_cache_time and (now - caps_lock_cache_time) < 0.12 then
      return caps_lock_cache_value
    end
    local ok, pipe = pcall(io.popen, "ioreg -r -k IOHIDKeyboardCapsLockState -d 1 2>/dev/null")
    if ok and pipe then
      local out = pipe:read("*a") or ""
      pipe:close()
      caps_lock_cache_time = now
      caps_lock_cache_value = out:match("IOHIDKeyboardCapsLockState%s*=%s*1") ~= nil
      if caps_lock_cache_value then return true end
    end
  end
  if reaper.JS_VKeys_GetState then
    for _, cutoff in ipairs({-2, -1, 0}) do
      local ok, state = pcall(reaper.JS_VKeys_GetState, cutoff)
      if ok and type(state) == "string" then
        for _, key in ipairs({0x14, 57}) do
          local caps_byte = state:byte(key + 1)
          if caps_byte and caps_byte ~= 0 then return true end
        end
      end
    end
  end
  return false
end

local function text_from_char(ch, force_upper)
  -- gfx.getchar() uses large numeric codes for special keys. Treat only
  -- Latin-1 printable codes as typed text; paste still supports Unicode.
  if ch < 32 or ch > 255 then return nil end
  local caps_on = caps_lock_on()
  if (force_upper or caps_on or (gfx.mouse_cap & 8) == 8) and ch >= 97 and ch <= 122 then
    ch = ch - 32
  end
  local ok, typed = false, nil
  if utf8 and utf8.char then ok, typed = pcall(utf8.char, ch) end
  if not ok and ch <= 255 then typed = string.char(ch) end
  return typed
end

local function edit_text_at_cursor(text, cursor, ch, allow_newline, force_upper)
  text = tostring(text or "")
  cursor = math.max(1, math.min(cursor or (#text + 1), #text + 1))
  if ch == KEY_BACKSPACE then
    local p = prev_cursor(text, cursor)
    if p < cursor then text = text:sub(1, p - 1) .. text:sub(cursor) end
    return text, p
  elseif ch == KEY_DELETE then
    local n = next_cursor(text, cursor)
    if n > cursor then text = text:sub(1, cursor - 1) .. text:sub(n) end
    return text, cursor
  elseif ch == KEY_LEFT then
    return text, prev_cursor(text, cursor)
  elseif ch == KEY_RIGHT then
    return text, next_cursor(text, cursor)
  elseif ch == KEY_HOME then
    return text, 1
  elseif ch == KEY_END then
    return text, #text + 1
  elseif ch == 13 and allow_newline then
    return text:sub(1, cursor - 1) .. "\n" .. text:sub(cursor), cursor + 1
  end

  local typed = text_from_char(ch, force_upper)
  if typed then
    return text:sub(1, cursor - 1) .. typed .. text:sub(cursor), cursor + #typed
  end
  return text, cursor
end

local function edit_numeric_at_cursor(text, cursor, ch)
  text = tostring(text or "")
  cursor = math.max(1, math.min(cursor or (#text + 1), #text + 1))
  if ch == KEY_BACKSPACE or ch == KEY_DELETE or ch == KEY_LEFT or ch == KEY_RIGHT or ch == KEY_HOME or ch == KEY_END then
    return edit_text_at_cursor(text, cursor, ch, false)
  elseif ch >= 48 and ch <= 57 then
    local typed = string.char(ch)
    return text:sub(1, cursor - 1) .. typed .. text:sub(cursor), cursor + 1
  elseif ch == 46 or ch == 44 then
    if not text:find("[%.%,]") then
      return text:sub(1, cursor - 1) .. "." .. text:sub(cursor), cursor + 1
    end
  end
  return text, cursor
end

local function edit_selected_text(text, ch, allow_newline, force_upper)
  text = tostring(text or "")
  if is_select_all_key(ch) then return text, #text + 1, true end
  if ch == KEY_LEFT or ch == KEY_HOME then return text, 1, false end
  if ch == KEY_RIGHT or ch == KEY_END then return text, #text + 1, false end
  if is_delete_key(ch) then return "", 1, false end
  local typed = nil
  if ch == 13 and allow_newline then typed = "\n" else typed = text_from_char(ch, force_upper) end
  if typed then return typed, #typed + 1, false end
  return text, #text + 1, true
end

local function edit_selected_numeric(text, ch)
  text = tostring(text or "")
  if is_select_all_key(ch) then return text, #text + 1, true end
  if ch == KEY_LEFT or ch == KEY_HOME then return text, 1, false end
  if ch == KEY_RIGHT or ch == KEY_END then return text, #text + 1, false end
  if is_delete_key(ch) then return "", 1, false end
  if ch >= 48 and ch <= 57 then return string.char(ch), 2, false end
  if ch == 46 or ch == 44 then return ".", 2, false end
  return text, #text + 1, true
end

local function draw_input(rect, label, value, active, enabled, clicked, cursor_pos, select_all)
  gfx.set(0.80, 0.78, 0.68, 1)
  gfx.x = rect.x
  gfx.y = rect.y - 20
  gfx.drawstr(label)

  local hover = enabled and point_in_rect(gfx.mouse_x, gfx.mouse_y, rect.x, rect.y, rect.w, rect.h)
  gfx.set(active and 0.16 or (hover and 0.13 or 0.10), active and 0.22 or 0.13, active and 0.28 or 0.17, 1)
  if not enabled then gfx.set(0.08, 0.08, 0.10, 1) end
  gfx.rect(rect.x, rect.y, rect.w, rect.h, true)
  gfx.set(active and 0.20 or 0.34, active and 0.62 or 0.36, active and 0.78 or 0.42, 1)
  gfx.rect(rect.x, rect.y, rect.w, rect.h, false)
  gfx.set(enabled and 0.95 or 0.45, enabled and 0.94 or 0.45, enabled and 0.96 or 0.45, 1)
  gfx.x = rect.x + 8
  gfx.y = rect.y + 8
  if active and select_all and value ~= "" then
    local tw = math.min(gfx.measurestr(tostring(value or "")), rect.w - 18)
    gfx.set(0.22, 0.48, 0.70, 0.95)
    gfx.rect(rect.x + 7, rect.y + 6, tw + 4, rect.h - 12, true)
    gfx.set(enabled and 0.98 or 0.45, enabled and 0.97 or 0.45, enabled and 1.0 or 0.45, 1)
    gfx.x = rect.x + 8
    gfx.y = rect.y + 8
  end
  gfx.drawstr(fit_text(value, rect.w - 16))
  if active and not select_all and math.floor(reaper.time_precise() * 2) % 2 == 0 then
    local v = tostring(value or "")
    local cursor = math.max(1, math.min(cursor_pos or (#v + 1), #v + 1))
    local tw = gfx.measurestr(v:sub(1, cursor - 1))
    gfx.set(1.0, 0.78, 0.18, 1)
    gfx.rect(rect.x + 9 + math.min(tw, rect.w - 22), rect.y + 7, 2, rect.h - 14, true)
  end
  return clicked and enabled and hover
end

local function set_line_in_text(text, line_index, value)
  local lines = {}
  text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  for line in (text .. "\n"):gmatch("(.-)\n") do table.insert(lines, line) end
  while #lines < line_index do table.insert(lines, "") end
  lines[line_index] = value or ""
  return table.concat(lines, "\n"):gsub("\n+$", "")
end

local function first_clipboard_line()
  local pasted = get_clipboard()
  if not pasted or pasted == "" then return nil end
  pasted = normalize_name_list(pasted)
  local first = pasted:match("^(.-)\n") or pasted
  return trim(first)
end


local function draw_help_overlay(clicked)
  local margin_x = 58
  local margin_y = 38
  local rect = {
    x = margin_x,
    y = margin_y,
    w = math.max(720, gfx.w - margin_x * 2),
    h = math.max(560, gfx.h - margin_y * 2)
  }
  local close_rect = { x = rect.x + rect.w - 126, y = rect.y + rect.h - 48, w = 100, h = 32 }
  local text_bottom = close_rect.y - 16

  gfx.set(0, 0, 0, 0.62)
  gfx.rect(0, 0, gfx.w, gfx.h, true)
  gfx.set(0.10, 0.10, 0.14, 1)
  gfx.rect(rect.x, rect.y, rect.w, rect.h, true)
  gfx.set(0.42, 0.39, 0.55, 1)
  gfx.rect(rect.x, rect.y, rect.w, rect.h, false)

  gfx.setfont(1, "Arial", 20)
  gfx.set(0.92, 0.88, 0.78, 1)
  gfx.x = rect.x + 22
  gfx.y = rect.y + 18
  gfx.drawstr("Help rapido")

  gfx.setfont(1, "Arial", 13)
  local y = rect.y + 54
  local line_h = 17
  local blank_h = 7
  local lines = {
    "Gap nuovo file: se tra due item passa piu' di questo tempo, nasce una nuova regione.",
    "Esempi utili: 0.5, 1.0, 1.5, 2.0 secondi.",
    "",
    "Padding inizio: anticipa l'inizio della regione senza spostare gli item.",
    "Esempio: 0.2 = 200 ms prima.",
    "",
    "Padding fine: allunga la fine della regione. Esempio: 0.5 = mezzo secondo dopo l'ultimo item.",
    "",
    "Sorgente: Item usa gli item selezionati; Tracce usa le tracce selezionate.",
    "Folder+: include le tracce selezionate e tutte le sottotracce folder.",
    "Tutte guarda tutto il progetto.",
    "",
    "Rimuovi export precedenti: cancella solo le regioni azzurre create da questo script.",
    "Marker inizio: crea anche un marker all'inizio di ogni regione.",
    "",
    "Anteprima: doppio click su regioni o marker per rinominarli dentro la finestra.",
    "Nomi: seleziona una riga nell'anteprima o nei nomi, poi incolla per partire da li'.",
    "",
    "Prepara Mixdown: Selezione sceglie marker/regioni; Crea Selez. crea solo quelle.",
    "Render apre Render to File. + Queue aggiunge un solo job per la sezione scelta.",
    "Que apre la Render Queue: nero se vuota, verde quando contiene almeno un job.",
    "",
    "Index ON: aggiorna anche Mixdown/<Lane1>/Mixdown_Index.csv con colonna Presente = X se il file esiste.",
    "Index OFF: aggiorna solo Mixdown/Mixdown_Report.csv.",
    "Ghost ON: aggiunge una regione tecnica di preroll per scaldare i plugin prima del primo file.",
    "Ghost OFF: nessuna regione o file fantasma viene aggiunto.",
    "",
    "Directory: Lane 1 = Mixdown/<marker>/; Lane 2 = Mixdown/<Lane1>/<Lane2>/.",
    "Le regioni fuori Lane 1 sono ignorate da anteprima, selezione e render. Pattern file: $region.",
    "I nomi regione non vengono modificati.",
    "Il CSV con LUFS/Peak/RMS va generato dopo render o dry run con statistiche REAPER."
  }
  for _, line in ipairs(lines) do
    if y + line_h > text_bottom then break end
    gfx.set(line == "" and 0.40 or 0.82, line == "" and 0.40 or 0.80, line == "" and 0.45 or 0.86, 1)
    gfx.x = rect.x + 22
    gfx.y = y
    if line ~= "" then gfx.drawstr(fit_text(line, rect.w - 44)) end
    y = y + (line == "" and blank_h or line_h)
  end

  return draw_button(close_rect, "Chiudi", false, true, clicked)
end

local function open_window()
  if not gfx or not gfx.init then return false end
  render_debug_log("open_window | Gestore Progetto aperto log=" .. tostring(RENDER_DEBUG_LOG_PATH))

  local state = get_state()
  local gap_text = tostring(state.gap)
  local pad_in_text = tostring(state.pad_in)
  local pad_out_text = tostring(state.pad_out)
  local active_field = nil
  local last_mouse_down = false
  local preview_scroll = 0
  local selected_preview = 1
  local selected_marker_index = nil
  local selected_marker_indices = {}
  local selected_rows = {}
  local last_range_anchor = 1
  local last_rm_selection_hash = ""
  local last_rm_sync_time = 0
  local suppress_rm_sync_until = 0
  local play_row = bool_from_state(reaper.GetExtState(EXT_SECTION, "play_row"), false)
  local last_preview_click_time = 0
  local last_names_click_time = 0
  local custom_names = decode_draft_names(state.draft_names)
  local draft_order = decode_draft_order(state.draft_order)
  local names_scroll = 0
  local names_anchor_row = nil
  local show_help = false
  local chosen_mixdown_info = nil
  local chosen_mixdown_groups = nil
  local show_mixdown_settings = false
  local mixdown_draft = nil
  local edit_name_index = nil
  local edit_name_text = ""
  local edit_name_source = nil
  local edit_name_cursor = 1
  local edit_name_select_all = false
  local numeric_cursor = {
    gap = #gap_text + 1,
    pad_in = #pad_in_text + 1,
    pad_out = #pad_out_text + 1
  }
  local numeric_select_all = { gap = false, pad_in = false, pad_out = false }
  local last_input_click_time = 0
  local last_input_click_field = nil
  local names_cursor = #(state.names_text or "") + 1
  local names_select_all = false
  local play_until = nil
  local last_saved_time = 0
  local pending_mixdown_report = nil
  local render_dialog_lock_until = 0
  local last_pending_report_check = 0
  local last_render_window_check = 0
  local preview_visible_rows = 14
  local _, _, last_project_region_count = reaper.CountProjectMarkers(0)

  gfx.init(SCRIPT_TITLE, FIXED_WINDOW_W, 660)
  gfx.setfont(1, "Arial", 15)
  reset_debug_log()
  log_debug("OPEN", "finestra aperta")

  if reaper.JS_Window_Find and reaper.JS_Window_Show then
    local title = reaper.JS_Localize and reaper.JS_Localize("Region/Marker Manager", "common") or "Region/Marker Manager"
    local manager = reaper.JS_Window_Find(title, true)
    if not manager then
      reaper.Main_OnCommand(40326, 0)
      manager = reaper.JS_Window_Find(title, true)
      if manager then reaper.JS_Window_Show(manager, "HIDE") end
    end
  end

  local cancel_name_edit
  local save_draft_state
  local commit_name_edit
  local selected_or_all_groups

  local function current_mixdown_report_context(groups, names)
    local render_groups = chosen_mixdown_groups
    if not render_groups then render_groups = selected_or_all_groups(groups, names) end
    local folder = chosen_mixdown_info or render_folder_info(render_groups)
    local out_dir = mixdown_folder_path(folder)
    if not (render_groups and folder and out_dir) then return nil, nil, nil end
    return region_rows_for_render(render_groups), folder, out_dir
  end



  local function arm_mixdown_report_monitor(regions, folder, out_dir, warmup_enabled)
    if not (regions and folder and out_dir and out_dir ~= "") then return end
    pending_mixdown_report = {
      regions = regions,
      folder = folder,
      out_dir = out_dir,
      settings = copy_mixdown_settings(),
      warmup_enabled = warmup_enabled and true or false,
      armed_at = reaper.time_precise(),
      ready_at = nil,
      files_ready_at = nil,
      waiting_render_window_announced = false,
      announced = false
    }
    last_pending_report_check = 0
    render_debug_log(string.format(
      "arm_mixdown_report_monitor | regions=%d folder=%s out_dir=%s warmup=%s",
      #(regions or {}),
      log_escape((folder and (folder.relative or folder.safe_name or folder.raw_name)) or ""),
      log_escape(out_dir or ""),
      tostring(warmup_enabled and true or false)
    ))
  end

  local function poll_mixdown_report_monitor()
    if not pending_mixdown_report then return end
    local now = reaper.time_precise()
    if now - last_pending_report_check < 1.0 then return end
    last_pending_report_check = now
    local ready = all_expected_mixdown_files_exist(
      pending_mixdown_report.regions,
      pending_mixdown_report.out_dir,
      pending_mixdown_report.settings
    )
    if not ready then
      if now - pending_mixdown_report.armed_at > 5.0 and not render_window_is_open(false) then
        render_debug_log("poll_mixdown_report_monitor | files non pronti e finestra render chiusa: disarmo monitor")
        pending_mixdown_report = nil
      end
      return
    end
    render_debug_log("poll_mixdown_report_monitor | file render attesi trovati")
    pending_mixdown_report.files_ready_at = pending_mixdown_report.files_ready_at or now
    local render_still_open, render_title = render_window_is_open(false)
    if render_still_open then
      if not pending_mixdown_report.waiting_render_window_announced then
        render_debug_log("poll_mixdown_report_monitor | attendo chiusura finestra render title=" .. tostring(render_title or ""))
        pending_mixdown_report.waiting_render_window_announced = true
      end
      return
    end
    if pending_mixdown_report.warmup_enabled then
      pending_mixdown_report.ready_at = pending_mixdown_report.ready_at or now
      local stats_path = pending_mixdown_report.out_dir .. "/" .. WARMUP_REGION_NAME .. ".render_stats.html"
      local stats_present = file_exists(stats_path)
      if not stats_present and now - pending_mixdown_report.ready_at < 8.0 then
        render_debug_log("poll_mixdown_report_monitor | attendo stats warmup path=" .. log_escape(stats_path))
        return
      end
    end
    local csv_path, err, _, index_path, index_err, log_skipped = save_mixdown_reports(
      pending_mixdown_report.regions,
      pending_mixdown_report.folder,
      pending_mixdown_report.out_dir,
      pending_mixdown_report.settings
    )
    if csv_path or log_skipped then
      local stats_path = nil
      if pending_mixdown_report.warmup_enabled then
        local _, _, cleaned_stats_path = cleanup_warmup_after_render(pending_mixdown_report.out_dir, pending_mixdown_report.settings)
        stats_path = cleaned_stats_path
      else
        stats_path = normalize_real_render_stats(pending_mixdown_report.out_dir, pending_mixdown_report.regions, pending_mixdown_report.settings)
      end
      local msg = csv_path and ("Report Mixdown CSV creato: " .. csv_path)
        or "Render completato. Log Mixdown History disattivato: CSV storico non richiesto."
      if stats_path then msg = msg .. "\nStats HTML normalizzato: " .. stats_path end
      if index_path then msg = msg .. "\nIndice aggiornato: " .. index_path end
      if index_err then msg = msg .. "\nNota indice: " .. tostring(index_err) end
      render_debug_log("poll_mixdown_report_monitor | report completato log_skipped=" .. tostring(log_skipped and true or false) .. " csv=" .. log_escape(csv_path or "") .. " index=" .. log_escape(index_path or ""))
      notify_status(msg)
      pending_mixdown_report = nil
      render_dialog_lock_until = 0
      render_debug_log("poll_mixdown_report_monitor | render lock rilasciato dopo report")
    elseif not pending_mixdown_report.announced then
      speak("File renderizzati trovati, ma non riesco a scrivere il CSV: " .. tostring(err or "errore sconosciuto"))
      render_debug_log("poll_mixdown_report_monitor | errore report err=" .. log_escape(err or ""))
      pending_mixdown_report.announced = true
    end
  end

  function save_draft_state()
    state.draft_names = encode_draft_names(custom_names)
    state.draft_order = encode_draft_order(draft_order)
    save_state(state)
  end

  local function save_project_file()
    if reaper.Main_SaveProject then
      reaper.Main_SaveProject(0, false)
    else
      reaper.Main_OnCommand(40026, 0) -- File: Save project
    end
  end


  local function draw_mixdown_settings_overlay(clicked)
    mixdown_draft = mixdown_draft or copy_mixdown_settings()
    local rect = { x = 128, y = 78, w = 724, h = 510 }
    gfx.set(0, 0, 0, 0.66)
    gfx.rect(0, 0, gfx.w, gfx.h, true)
    gfx.set(0.10, 0.10, 0.14, 1)
    gfx.rect(rect.x, rect.y, rect.w, rect.h, true)
    gfx.set(0.42, 0.39, 0.55, 1)
    gfx.rect(rect.x, rect.y, rect.w, rect.h, false)

    gfx.setfont(1, "Arial", 20)
    gfx.set(0.92, 0.88, 0.78, 1)
    gfx.x = rect.x + 22
    gfx.y = rect.y + 18
    gfx.drawstr("Impostazioni Mixdown")
    gfx.setfont(1, "Arial", 15)

    local function label(text, x, y)
      gfx.set(0.78, 0.76, 0.68, 1)
      gfx.x = x
      gfx.y = y
      gfx.drawstr(text)
    end

    local function option_button(x, y, w, text, active)
      return draw_button({ x = x, y = y, w = w, h = 30 }, text, active, true, clicked, "tab")
    end

    local x = rect.x + 24
    local y = rect.y + 62
    label("Preset rapido", x, y)
    y = y + 22
    local preset_w = 210
    for i, preset in ipairs(MIXDOWN_PRESETS) do
      local col = (i - 1) % 2
      local row = math.floor((i - 1) / 2)
      if option_button(x + col * (preset_w + 14), y + row * 36, preset_w, preset.label, false) then
        mixdown_draft = copy_mixdown_settings(preset)
      end
    end

    y = y + 112
    label("Formato", x, y)
    y = y + 22
    if option_button(x, y, 90, "WAV", mixdown_draft.format == "wav") then
      mixdown_draft.format = "wav"
      if mixdown_draft.quality ~= "16" and mixdown_draft.quality ~= "24" and mixdown_draft.quality ~= "32" then mixdown_draft.quality = "24" end
    end
    if option_button(x + 100, y, 90, "MP3", mixdown_draft.format == "mp3") then
      mixdown_draft.format = "mp3"
      if mixdown_draft.quality == "120" then mixdown_draft.quality = "128" end
      if mixdown_draft.quality ~= "128" and mixdown_draft.quality ~= "192" and mixdown_draft.quality ~= "256" and mixdown_draft.quality ~= "320" then mixdown_draft.quality = "128" end
    end

    label("Qualita'", x + 260, y - 22)
    local qualities = mixdown_draft.format == "wav" and { "16", "24", "32" } or { "128", "192", "256", "320" }
    for i, q in ipairs(qualities) do
      local text = mixdown_draft.format == "wav" and (q .. " bit") or q
      if option_button(x + 260 + (i - 1) * 82, y, 74, text, mixdown_draft.quality == q) then mixdown_draft.quality = q end
    end

    y = y + 62
    label("Sample rate", x, y)
    y = y + 22
    local sample_buttons = {
      { id = "project", label = "Progetto", w = 96 },
      { id = "44100", label = "44.1", w = 72 },
      { id = "48000", label = "48", w = 72 },
      { id = "96000", label = "96", w = 72 }
    }
    local sx = x
    for _, opt in ipairs(sample_buttons) do
      if option_button(sx, y, opt.w, opt.label, mixdown_draft.sample_rate == opt.id) then mixdown_draft.sample_rate = opt.id end
      sx = sx + opt.w + 10
    end

    label("Canali", x + 430, y - 22)
    if option_button(x + 430, y, 100, "Mono", mixdown_draft.channels == "mono") then mixdown_draft.channels = "mono" end
    if option_button(x + 540, y, 100, "Stereo", mixdown_draft.channels == "stereo") then mixdown_draft.channels = "stereo" end

    y = y + 70
    gfx.set(0.82, 0.86, 0.90, 1)
    gfx.x = x
    gfx.y = y
    gfx.drawstr("Attuale: " .. mixdown_summary(mixdown_draft))

    local save_rect = { x = rect.x + rect.w - 214, y = rect.y + rect.h - 52, w = 96, h = 32 }
    local cancel_rect = { x = rect.x + rect.w - 108, y = rect.y + rect.h - 52, w = 86, h = 32 }
    if draw_button(save_rect, "Salva", false, true, clicked, "save") then
      save_mixdown_settings(mixdown_draft)
      mixdown_draft = nil
      show_mixdown_settings = false
    end
    if draw_button(cancel_rect, "Annulla", false, true, clicked) then
      mixdown_draft = nil
      show_mixdown_settings = false
    end
  end

  local function mark_saved()
    last_saved_time = reaper.time_precise()
  end

  local function selected_row_count(groups)
    local count = 0
    for i, group in ipairs(groups or {}) do
      if selected_rows[i] and is_region_row(group) then count = count + 1 end
    end
    return count
  end

  function selected_or_all_groups(groups, names)
    local count = selected_row_count(groups)
    local out_groups, out_names = {}, {}
    if count == 0 then
      for _, group in ipairs(groups or {}) do
        if is_region_row(group) then
          table.insert(out_groups, group)
          table.insert(out_names, names[group.region_order or #out_names + 1] or group.edited_name or group.name or "")
        end
      end
      return out_groups, out_names, false
    end
    for i, group in ipairs(groups or {}) do
      if selected_rows[i] and is_region_row(group) then
        table.insert(out_groups, group)
        table.insert(out_names, names[group.region_order or #out_names + 1] or group.edited_name or group.name or "")
      end
    end
    return out_groups, out_names, true
  end

  local function row_matches_target(group, target)
    if not (group and target) then return false end
    local gs = group.region_start or group.start_pos or 0
    local ge = group.region_end or group.end_pos or 0
    local ts = target.region_start or target.start_pos or 0
    local te = target.region_end or target.end_pos or 0
    return math.abs(gs - ts) <= 0.002 and math.abs(ge - te) <= 0.002
  end

  local function mark_selected_rows_for_render_groups(all_groups, render_groups)
    selected_rows = {}
    if not render_groups or #render_groups == 0 then return end
    for i, group in ipairs(all_groups or {}) do
      if is_region_row(group) then
        for _, target in ipairs(render_groups) do
          if row_matches_target(group, target) then
            selected_rows[i] = true
            break
          end
        end
      end
    end
  end

  local function mixdown_selection_from_active_marker(all_groups)
    local group = all_groups and all_groups[selected_preview] or nil
    if not (group and group.marker_only) then return nil, nil end
    local render_groups = region_groups_for_marker_section(group)
    if not render_groups or #render_groups == 0 then return nil, nil end
    local folder = render_folder_info_from_marker_row(group)
    return render_groups, folder
  end


  local function folder_info_from_marker_for_queue(marker)
    if not marker then return nil end
    local parts = marker.folder_parts or { marker.name or "" }
    local raw_name = raw_folder_path_parts(parts)
    if trim(raw_name) == "" then raw_name = "Mixdown_Export" end
    local safe_path = sanitize_folder_path_parts(parts)
    local safe_name = safe_path:match("([^/]+)$") or safe_path
    return {
      raw_name = raw_name,
      safe_name = safe_name,
      safe_path = safe_path,
      source = "marker",
      marker_lane = marker.lane,
      relative = "Mixdown/" .. safe_path .. "/"
    }
  end

  local function queue_sections_from_region_groups(render_groups)
    local sections = {}
    local markers = collect_project_markers()
    local buckets = {}
    local order = {}
    for _, group in ipairs(region_rows_for_render(render_groups or {})) do
      local marker = marker_for_position(markers, group.region_start or group.start_pos or 0)
      local folder = marker and folder_info_from_marker_for_queue(marker) or render_folder_info({ group })
      local key = folder and folder.safe_path or "__fallback"
      if not buckets[key] then
        buckets[key] = { groups = {}, folder = folder, label = folder and folder.relative or key }
        order[#order + 1] = key
      end
      buckets[key].groups[#buckets[key].groups + 1] = group
    end
    for _, key in ipairs(order) do
      if #region_rows_for_render(buckets[key].groups) > 0 then
        sections[#sections + 1] = buckets[key]
      end
    end
    return sections
  end

  local function queue_sections_from_current_selection(all_groups, fallback_groups, fallback_folder)
    local sections = {}
    local seen_markers = {}

    local function add_marker_section(marker_row)
      if not (marker_row and marker_row.marker_only and marker_row.marker_pos) then return end
      local marker_key = tostring(marker_row.marker_idx or marker_row.marker_pos or marker_row.__row_index or (#sections + 1))
      if seen_markers[marker_key] then return end
      seen_markers[marker_key] = true
      local section_groups = region_groups_for_marker_section(marker_row)
      if #region_rows_for_render(section_groups) == 0 then return end
      sections[#sections + 1] = {
        groups = section_groups,
        folder = render_folder_info_from_marker_row(marker_row),
        label = marker_row.marker_label or marker_row.marker_name or marker_key
      }
    end

    for i, group in ipairs(all_groups or {}) do
      if selected_marker_indices[i] and group and group.marker_only then
        add_marker_section(group)
      end
    end
    if #sections > 0 then return sections end

    local active_group = all_groups and all_groups[selected_preview] or nil
    if active_group and active_group.marker_only then
      add_marker_section(active_group)
    end
    if #sections > 0 then return sections end

    if fallback_groups and #region_rows_for_render(fallback_groups) > 0 then
      local grouped_sections = queue_sections_from_region_groups(fallback_groups)
      if #grouped_sections > 0 then return grouped_sections end
      return { { groups = fallback_groups, folder = fallback_folder or render_folder_info(fallback_groups), label = "selezione" } }
    end

    return {}
  end

  local function sync_preview_to_region_manager(groups)
    if not (reaper.JS_Window_Find and reaper.JS_Window_FindChildByID and
      reaper.JS_ListView_GetItemCount and reaper.JS_ListView_GetItemText and
      reaper.JS_ListView_SetItemState) then
      return
    end
    local selected_region_ids = {}
    for i, group in ipairs(groups or {}) do
      if selected_rows[i] and is_region_row(group) then
        local regions = matching_export_regions({ group })
        for _, region in ipairs(regions) do
          selected_region_ids[region.idx] = true
        end
      end
    end
    local title = reaper.JS_Localize and reaper.JS_Localize("Region/Marker Manager", "common") or "Region/Marker Manager"
    local manager = reaper.JS_Window_Find(title, true)
    if not manager then return end
    local list = reaper.JS_Window_FindChildByID(manager, 1071)
    if not list then return end
    local item_count = reaper.JS_ListView_GetItemCount(list)
    reaper.JS_ListView_SetItemState(list, -1, 0x0, 0x3)
    for i = 0, item_count - 1 do
      local region_id = listview_region_id(list, i)
      if region_id and selected_region_ids[region_id] then
        reaper.JS_ListView_SetItemState(list, i, 0x3, 0x3)
      end
    end
    suppress_rm_sync_until = reaper.time_precise() + 0.5
    -- Update hash so reverse sync doesn't immediately overwrite
    local hash_parts = {}
    for id in pairs(selected_region_ids) do hash_parts[#hash_parts + 1] = tostring(id) end
    table.sort(hash_parts)
    last_rm_selection_hash = table.concat(hash_parts, ",")
  end

  local function toggle_marker_section_selection(all_groups, marker_row, additive)
    local section_groups = region_groups_for_marker_section(marker_row)
    if #section_groups == 0 then return false end
    if not additive then
      selected_rows = {}
      selected_marker_indices = {}
    end
    local all_selected = true
    for i, group in ipairs(all_groups or {}) do
      if is_region_row(group) then
        for _, target in ipairs(section_groups) do
          if row_matches_target(group, target) and not selected_rows[i] then all_selected = false end
        end
      end
    end
    local should_select = not (additive and all_selected)
    for i, group in ipairs(all_groups or {}) do
      if is_region_row(group) then
        for _, target in ipairs(section_groups) do
          if row_matches_target(group, target) then
            selected_rows[i] = should_select and true or nil
            break
          end
        end
      end
    end
    selected_marker_indices[marker_row and marker_row.__row_index or 0] = should_select and true or nil
    selected_marker_index = should_select and marker_row.__row_index or nil
    chosen_mixdown_groups = selected_or_all_groups(all_groups, {})
    chosen_mixdown_info = render_folder_info(chosen_mixdown_groups)
    sync_preview_to_region_manager(all_groups)
    return true
  end

  local function sync_preview_from_region_manager(groups)
    if not (reaper.JS_Window_Find and reaper.JS_Window_FindChildByID and
      reaper.JS_ListView_GetItemCount and reaper.JS_ListView_GetItemText and
      reaper.JS_ListView_GetItemState) then
      return
    end
    local now = reaper.time_precise()
    if now < suppress_rm_sync_until then return end
    if now - last_rm_sync_time < 0.5 then return end
    last_rm_sync_time = now
    local title = reaper.JS_Localize and reaper.JS_Localize("Region/Marker Manager", "common") or "Region/Marker Manager"
    local manager = reaper.JS_Window_Find(title, true)
    if not manager then return end
    local list = reaper.JS_Window_FindChildByID(manager, 1071)
    if not list then return end
    local item_count = reaper.JS_ListView_GetItemCount(list)
    local selected_ids = {}
    for i = 0, item_count - 1 do
      local state = reaper.JS_ListView_GetItemState(list, i) or 0
      if (state & 0x2) == 0x2 then
        local region_id = listview_region_id(list, i)
        if region_id then selected_ids[region_id] = true end
      end
    end
    local hash_parts = {}
    for id in pairs(selected_ids) do hash_parts[#hash_parts + 1] = tostring(id) end
    table.sort(hash_parts)
    local current_hash = table.concat(hash_parts, ",")
    if current_hash == last_rm_selection_hash then return end
    last_rm_selection_hash = current_hash
    local new_selected = {}
    for i, group in ipairs(groups or {}) do
      if is_region_row(group) then
        local existing_idx = group.existing_idx
        if not existing_idx then
          local regions = matching_export_regions({ group })
          if #regions > 0 then existing_idx = regions[1].idx end
        end
        if existing_idx and selected_ids[existing_idx] then
          new_selected[i] = true
        end
      end
    end
    selected_rows = new_selected
    chosen_mixdown_groups = nil
    chosen_mixdown_info = nil
    selected_marker_index = nil
    selected_marker_indices = {}
  end

  local function select_preview_row(index, groups)
    if groups and groups[index] and groups[index].marker_only then return end
    local cmd = (gfx.mouse_cap & 4) == 4 or (gfx.mouse_cap & 32) == 32
    local shift = (gfx.mouse_cap & 8) == 8
    if shift then
      selected_rows = {}
      local a = math.min(last_range_anchor or index, index)
      local b = math.max(last_range_anchor or index, index)
      for i = a, b do
        if not groups or is_region_row(groups[i]) then selected_rows[i] = true end
      end
    elseif cmd then
      selected_rows[index] = not selected_rows[index]
      last_range_anchor = index
    else
      selected_rows = { [index] = true }
      last_range_anchor = index
    end
    sync_preview_to_region_manager(groups)
    chosen_mixdown_groups = nil
    chosen_mixdown_info = nil
    selected_marker_index = nil
    selected_marker_indices = {}
  end

  local function clear_name_state()
    state.names_text = ""
    state.draft_names = ""
    state.draft_order = ""
    custom_names = {}
    draft_order = {}
    names_cursor = 1
    names_select_all = false
    names_scroll = 0
    names_anchor_row = nil
    cancel_name_edit()
    save_state(state)
  end

  local function replace_name_list(text)
    state.names_text = normalize_name_list(text or "")
    state.draft_names = ""
    state.draft_order = ""
    custom_names = {}
    draft_order = {}
    names_cursor = #(state.names_text or "") + 1
    names_select_all = false
    names_scroll = 0
    names_anchor_row = nil
    cancel_name_edit()
    save_state(state)
  end

  local function paste_name_list_from_row(text, start_row, groups)
    local pasted_names = parse_names(text)
    start_row = math.max(1, tonumber(start_row) or 1)
    if #pasted_names == 0 then return false end

    local last_row = start_row + #pasted_names - 1
    for offset, name in ipairs(pasted_names) do
      local row = start_row + offset - 1
      state.names_text = set_line_in_text(state.names_text, row, name)
      draft_order[row] = nil
    end
    selected_rows = {}
    local first_selected_index = nil
    for index, group in ipairs(groups or {}) do
      local row = group.region_order
      if row and row >= start_row and row <= last_row then
        if group.preview_key then custom_names[group.preview_key] = nil end
        if is_region_row(group) then
          selected_rows[index] = true
          first_selected_index = first_selected_index or index
        end
      end
    end
    if first_selected_index then
      selected_preview = first_selected_index
      last_range_anchor = first_selected_index
    end

    names_cursor = #(state.names_text or "") + 1
    names_select_all = false
    names_anchor_row = start_row
    names_scroll = math.max(0, start_row - 1)
    selected_preview = selected_preview or 1
    cancel_name_edit()
    save_draft_state()
    return true
  end

  local function paste_start_row_for_groups(groups)
    if active_field == "inline_name" and edit_name_source == "names" and edit_name_index then
      return math.max(1, edit_name_index)
    end
    if active_field == "inline_name" and edit_name_source == "preview" and edit_name_index then
      local group = groups and groups[edit_name_index]
      if group and group.region_order then return group.region_order end
    end
    local first_selected_order = nil
    for index in pairs(selected_rows or {}) do
      local group = groups and groups[index]
      if group and group.region_order then
        first_selected_order = first_selected_order and math.min(first_selected_order, group.region_order) or group.region_order
      end
    end
    if first_selected_order then return first_selected_order end
    local group = groups and groups[selected_preview]
    if group and group.region_order then return group.region_order end
    if group and group.marker_only then
      local next_index = next_region_row_index(groups, selected_preview + 1)
      local next_group = next_index and groups[next_index] or nil
      if next_group and next_group.region_order then return next_group.region_order end
    end
    return nil
  end

  local function rebuild()
    state.gap = math.max(0, tonumber_locale(gap_text, state.gap))
    state.pad_in = math.max(0, tonumber_locale(pad_in_text, state.pad_in))
    state.pad_out = math.max(0, tonumber_locale(pad_out_text, state.pad_out))

    local items, source = collect_items(state)
    local groups = build_preview_groups(items, state.gap, state.pad_in, state.pad_out)
    local names = parse_names_preserve_rows(state.names_text)
    local region_order = 0
    for _, group in ipairs(groups) do
      if is_region_row(group) then
        region_order = region_order + 1
        group.region_order = region_order
        local key = string.format("%.6f|%.6f|%s", group.region_start or 0, group.region_end or 0, tostring(group.existing_idx or "new"))
        local pasted_name = names[region_order]
        if custom_names[key] then
          group.edited_name = custom_names[key]
        elseif draft_order[region_order] and draft_order[region_order] ~= "" then
          group.edited_name = draft_order[region_order]
        elseif pasted_name and pasted_name ~= "" then
          group.edited_name = pasted_name
        elseif group.name and group.name ~= "" then
          group.edited_name = group.name
        end
        group.preview_key = key
      end
    end
    return items, groups, names, source
  end


  local function rename_marker_row(group, new_name)
    if not (group and group.marker_only and group.marker_idx and group.marker_pos) then return false end
    local value = trim(new_name or "")
    local shown = value ~= "" and value or "(marker senza nome)"
    if reaper.SetProjectMarker3 then
      reaper.SetProjectMarker3(0, group.marker_idx, false, group.marker_pos, 0, value, group.marker_color or 0)
    else
      reaper.DeleteProjectMarker(0, group.marker_idx, false)
      reaper.AddProjectMarker2(0, false, group.marker_pos, 0, value, group.marker_idx, group.marker_color or 0)
    end
    group.marker_name = value
    group.marker_label = string.format("[M%d] %s", group.marker_number or group.marker_idx or 0, shown)
    group.name = group.marker_label
    reaper.UpdateArrange()
    return true
  end

  function commit_name_edit(groups)
    if not edit_name_index then return end
    local new_name = trim(edit_name_text)
    if edit_name_source == "names" then
      state.names_text = set_line_in_text(state.names_text, edit_name_index, new_name)
      names_cursor = #(state.names_text or "") + 1
      local group = groups and groups[edit_name_index]
      if group and group.preview_key then custom_names[group.preview_key] = new_name end
      draft_order[edit_name_index] = new_name
    elseif edit_name_source == "marker" then
      local group = groups and groups[edit_name_index]
      if group and group.marker_only then rename_marker_row(group, new_name) end
    else
      local group = groups and groups[edit_name_index]
      if group and group.marker_only then return cancel_name_edit() end
      if group and group.preview_key then custom_names[group.preview_key] = new_name end
      if group and group.region_order then draft_order[group.region_order] = new_name end
    end
    save_draft_state()
    edit_name_index = nil
    edit_name_text = ""
    edit_name_source = nil
    edit_name_cursor = 1
    edit_name_select_all = false
    active_field = nil
  end

  function cancel_name_edit()
    edit_name_index = nil
    edit_name_text = ""
    edit_name_source = nil
    edit_name_cursor = 1
    edit_name_select_all = false
    active_field = nil
  end

  local function save_preview_name(groups, index, new_name)
    local group = groups and groups[index]
    if not group or group.marker_only then return false end
    local value = tostring(new_name or "")
    if group.preview_key then custom_names[group.preview_key] = value end
    if group.region_order then draft_order[group.region_order] = value end
    save_draft_state()
    return true
  end

  local function start_preview_inline_name_input(groups, index, select_all)
    local group = groups and groups[index]
    if not group or group.marker_only then return false end
    if edit_name_index and active_field == "inline_name" then commit_name_edit(groups) end
    selected_preview = index
    edit_name_index = index
    edit_name_text = group.edited_name or group.name or ""
    edit_name_source = "preview"
    edit_name_cursor = #edit_name_text + 1
    edit_name_select_all = select_all and edit_name_text ~= ""
    active_field = "inline_name"
    return true
  end


  local function start_marker_inline_name_input(groups, index, select_all)
    local group = groups and groups[index]
    if not (group and group.marker_only and group.marker_idx) then return false end
    if edit_name_index and active_field == "inline_name" then commit_name_edit(groups) end
    selected_preview = index
    edit_name_index = index
    edit_name_text = group.marker_name or ""
    edit_name_source = "marker"
    edit_name_cursor = #edit_name_text + 1
    edit_name_select_all = select_all and edit_name_text ~= ""
    active_field = "inline_name"
    return true
  end

  local function start_region_play(group)
    if not group then return end
    play_until = group.region_end
    reaper.SetEditCurPos(math.max(0, group.region_start - PLAY_PREROLL), true, false)
    reaper.Main_OnCommand(1007, 0)
  end

  local function create_selected_regions_from_preview(groups, names, state)
    if edit_name_index and active_field == "inline_name" then commit_name_edit(groups) end
    save_draft_state()
    local _, fresh_groups, fresh_names, _ = rebuild()
    fresh_groups, fresh_names = selected_or_all_groups(fresh_groups, fresh_names)
    local final_names = {}
    for i, group in ipairs(fresh_groups) do final_names[i] = group.edited_name or fresh_names[i] or group.name end
    local created_ok = create_regions(fresh_groups, final_names, state)
    if created_ok then
      local created_regions = matching_export_regions(fresh_groups)
      if #created_regions > 0 then
        select_regions_in_region_manager(created_regions)
        set_time_selection_for_regions_or_groups(created_regions)
      end
      chosen_mixdown_groups = fresh_groups
      chosen_mixdown_info = render_folder_info(fresh_groups)
      reaper.UpdateArrange()
    end
    return created_ok
  end

  local function stop_region_play()
    play_until = nil
    reaper.Main_OnCommand(1016, 0)
  end

  local function ensure_preview_row_visible(index)
    if not index then return end
    local rows = math.max(1, preview_visible_rows or 14)
    if index < preview_scroll + 1 then
      preview_scroll = math.max(0, index - 1)
    elseif index > preview_scroll + rows then
      preview_scroll = math.max(0, index - rows)
    end
  end

  local function advance_name_edit(groups)
    local source_before = edit_name_source
    local next_index = (edit_name_index or 0) + 1
    commit_name_edit(groups)
    if source_before == "preview" then
      next_index = next_region_row_index(groups, next_index)
    end
    if source_before == "preview" and next_index and groups[next_index] then
      local next_group = groups[next_index]
      edit_name_index = next_index
      edit_name_text = next_group.edited_name or next_group.name or ""
      edit_name_source = "preview"
      edit_name_cursor = #edit_name_text + 1
      edit_name_select_all = edit_name_text ~= ""
      selected_preview = next_index
      ensure_preview_row_visible(selected_preview)
      active_field = "inline_name"
      if play_row then start_region_play(next_group) end
    elseif source_before == "names" then
      local _, next_groups, next_names = rebuild()
      local next_limit = math.max(#next_groups, #next_names + 1, 1)
      if next_index <= next_limit then
        edit_name_index = next_index
        edit_name_text = next_names[next_index] or ""
        edit_name_source = "names"
        edit_name_cursor = #edit_name_text + 1
        edit_name_select_all = edit_name_text ~= ""
        names_scroll = math.max(0, next_index - 8)
        active_field = "inline_name"
        if play_row then
          for row_idx, row_group in ipairs(next_groups) do
            if row_group.region_order == next_index then
              selected_preview = row_idx
              start_region_play(row_group)
              break
            end
          end
        end
      end
    end
  end

  local function loop()
    local _, _, current_region_count = reaper.CountProjectMarkers(0)
    if current_region_count ~= last_project_region_count then
      last_project_region_count = current_region_count
      if reaper.JS_Window_Find and reaper.JS_Window_Show then
        local title = reaper.JS_Localize and reaper.JS_Localize("Region/Marker Manager", "common") or "Region/Marker Manager"
        local manager = reaper.JS_Window_Find(title, true)
        if manager then
          local was_visible = reaper.JS_Window_IsVisible and reaper.JS_Window_IsVisible(manager)
          reaper.Main_OnCommand(40326, 0) -- close
          reaper.Main_OnCommand(40326, 0) -- open
          manager = reaper.JS_Window_Find(title, true)
          if manager and reaper.JS_Window_Show and not was_visible then
            reaper.JS_Window_Show(manager, "HIDE")
          end
        end
      end
    end

    local ch = gfx.getchar()
    if ch < 0 then save_draft_state() gfx.quit() return end
    if gfx.w ~= FIXED_WINDOW_W or gfx.h < MIN_WINDOW_H then
      gfx.init(SCRIPT_TITLE, FIXED_WINDOW_W, math.max(gfx.h, MIN_WINDOW_H))
    end
    poll_mixdown_report_monitor()
    if render_dialog_lock_until > 0 then
      if not pending_mixdown_report then
        local now = reaper.time_precise()
        if now - last_render_window_check > 0.5 then
          last_render_window_check = now
          if not render_window_is_open(false) then
            render_debug_log("render_dialog_lock | rilascio: finestra render non trovata")
            render_dialog_lock_until = 0
          end
        end
      end
    end
    if play_until then
      local play_state = reaper.GetPlayState()
      if (play_state & 1) == 1 then
        if reaper.GetPlayPosition() >= play_until - 0.02 then stop_region_play() end
      else
        play_until = nil
      end
    end
    if ch > 0 then
      log_debug(
        "KEY_IN",
        string.format(
          "ch=%s active=%s edit_src=%s edit_idx=%s edit_cursor=%s names_cursor=%s gap='%s' pad_in='%s' pad_out='%s' edit='%s' names_len=%d mouse=%d,%d cap=%d",
          tostring(ch),
          tostring(active_field),
          tostring(edit_name_source),
          tostring(edit_name_index),
          tostring(edit_name_cursor),
          tostring(names_cursor),
          log_escape(gap_text),
          log_escape(pad_in_text),
          log_escape(pad_out_text),
          log_escape(edit_name_text),
          #(state.names_text or ""),
          gfx.mouse_x,
          gfx.mouse_y,
          gfx.mouse_cap
        )
      )
    end
    if ch == 27 then
      if show_mixdown_settings then show_mixdown_settings = false mixdown_draft = nil
      elseif show_help then show_help = false
      elseif edit_name_index then cancel_name_edit()
      else save_draft_state() gfx.quit() return end
    end

    local items, groups, names, source = rebuild()
    sync_preview_from_region_manager(groups)

    if active_field == "inline_name" and ch > 0 then
      if ch == 22 then
        if edit_name_source == "names" then
          local pasted = get_clipboard()
          if pasted and pasted ~= "" then
            paste_name_list_from_row(pasted, edit_name_index or 1, groups)
          end
        else
          local pasted = first_clipboard_line()
          if pasted then
            if edit_name_select_all then
              edit_name_text = pasted
              edit_name_cursor = #pasted + 1
            else
              edit_name_text = edit_name_text:sub(1, edit_name_cursor - 1) .. pasted .. edit_name_text:sub(edit_name_cursor)
              edit_name_cursor = edit_name_cursor + #pasted
            end
            edit_name_select_all = false
          end
        end
      elseif is_select_all_key(ch) then
        edit_name_select_all = true
        edit_name_cursor = #edit_name_text + 1
      elseif ch == KEY_TAB or ch == 13 then
        advance_name_edit(groups)
      elseif edit_name_select_all then
        edit_name_text, edit_name_cursor, edit_name_select_all = edit_selected_text(edit_name_text, ch, false)
      else
        edit_name_text, edit_name_cursor = edit_text_at_cursor(edit_name_text, edit_name_cursor, ch, false)
        edit_name_select_all = false
      end
    elseif active_field and ch > 0 then
      if is_select_all_key(ch) and (active_field == "gap" or active_field == "pad_in" or active_field == "pad_out") then
        numeric_select_all[active_field] = true
        numeric_cursor[active_field] = #(active_field == "gap" and gap_text or active_field == "pad_in" and pad_in_text or pad_out_text) + 1
      elseif is_select_all_key(ch) and active_field == "names" then
        names_select_all = true
        names_cursor = #(state.names_text or "") + 1
      elseif active_field == "names" and ch == 22 then
        local pasted = get_clipboard()
        if pasted and pasted ~= "" then
          replace_name_list(pasted)
        end
      elseif ch == 13 then
        if active_field == "names" then
          if names_select_all then
            state.names_text, names_cursor, names_select_all = edit_selected_text(state.names_text, ch, true)
          else
            state.names_text, names_cursor = edit_text_at_cursor(state.names_text, names_cursor, ch, true)
          end
        else
          active_field = nil
        end
      elseif active_field == "gap" then
        if numeric_select_all.gap then
          gap_text, numeric_cursor.gap, numeric_select_all.gap = edit_selected_numeric(gap_text, ch)
        else
          gap_text, numeric_cursor.gap = edit_numeric_at_cursor(gap_text, numeric_cursor.gap, ch)
        end
      elseif active_field == "pad_in" then
        if numeric_select_all.pad_in then
          pad_in_text, numeric_cursor.pad_in, numeric_select_all.pad_in = edit_selected_numeric(pad_in_text, ch)
        else
          pad_in_text, numeric_cursor.pad_in = edit_numeric_at_cursor(pad_in_text, numeric_cursor.pad_in, ch)
        end
      elseif active_field == "pad_out" then
        if numeric_select_all.pad_out then
          pad_out_text, numeric_cursor.pad_out, numeric_select_all.pad_out = edit_selected_numeric(pad_out_text, ch)
        else
          pad_out_text, numeric_cursor.pad_out = edit_numeric_at_cursor(pad_out_text, numeric_cursor.pad_out, ch)
        end
      elseif active_field == "names" then
        if names_select_all then
          state.names_text, names_cursor, names_select_all = edit_selected_text(state.names_text, ch, true)
        else
          state.names_text, names_cursor = edit_text_at_cursor(state.names_text, names_cursor, ch, true)
        end
      end
    elseif ch == 13 then
      start_preview_inline_name_input(groups, selected_preview, false)
    elseif ch == 22 then
      local pasted = set_clipboard_or_prompt()
      if pasted then
        local start_row = paste_start_row_for_groups(groups) or 1
        paste_name_list_from_row(pasted, start_row, groups)
      end
    end
    if ch > 0 then
      log_debug(
        "KEY_OUT",
        string.format(
          "ch=%s active=%s edit_src=%s edit_idx=%s edit_cursor=%s names_cursor=%s gap='%s' pad_in='%s' pad_out='%s' edit='%s' names_len=%d",
          tostring(ch),
          tostring(active_field),
          tostring(edit_name_source),
          tostring(edit_name_index),
          tostring(edit_name_cursor),
          tostring(names_cursor),
          log_escape(gap_text),
          log_escape(pad_in_text),
          log_escape(pad_out_text),
          log_escape(edit_name_text),
          #(state.names_text or "")
        )
      )
    end

    local mouse_down = (gfx.mouse_cap & 1) == 1
    local clicked = mouse_down and not last_mouse_down
    local overlay_clicked = clicked
    if show_mixdown_settings then clicked = false end
    last_mouse_down = mouse_down
    local wheel = gfx.mouse_wheel
    gfx.mouse_wheel = 0

    items, groups, names, source = rebuild()
    for group_index, group in ipairs(groups) do group.__row_index = group_index end
    local region_count = count_region_rows(groups)
    if selected_preview > #groups then selected_preview = math.max(1, #groups) end
    for index in pairs(selected_rows) do
      if index > #groups then selected_rows[index] = nil end
    end
    if ch == KEY_UP or ch == KEY_DOWN then
      if edit_name_index and active_field == "inline_name" then commit_name_edit(groups) end
      local step = ch == KEY_UP and -1 or 1
      local next_index = selected_preview + step
      while next_index >= 1 and next_index <= #groups and not is_region_row(groups[next_index]) do
        next_index = next_index + step
      end
      if next_index >= 1 and next_index <= #groups and is_region_row(groups[next_index]) then
        selected_preview = next_index
        selected_marker_index = nil
        selected_marker_indices = {}
        select_preview_row(next_index, groups)
        if selected_preview < preview_scroll + 1 then preview_scroll = selected_preview - 1 end
        if selected_preview > preview_scroll + 14 then preview_scroll = selected_preview - 14 end
        if play_row then start_region_play(groups[next_index]) end
        speak(string.format("Regione %02d: %s", groups[next_index].region_order or next_index, groups[next_index].edited_name or groups[next_index].name or "senza nome"))
      end
    end

    if clicked then
      log_debug(
        "CLICK",
        string.format("x=%d y=%d active_before=%s edit_src=%s edit_idx=%s groups=%d names=%d", gfx.mouse_x, gfx.mouse_y, tostring(active_field), tostring(edit_name_source), tostring(edit_name_index), #groups, #names)
      )
    end

    ZP_UI.fill_background()
    ZP_UI.draw_header({
      fallback_icon = draw_export_icon,
      title = "Gestore Progetto",
      description = "Crea regioni nominate per esportare file separati. Gli item non vengono modificati."
    })

    local content_right = FIXED_WINDOW_W - 22
    if draw_button({ x = content_right - 100, y = 22, w = 100, h = 34 }, "HELP ME", show_help, true, clicked) then
      show_help = not show_help
    end

    local render_info = chosen_mixdown_info or render_folder_info(groups)
    local status_color, status_label = mixdown_folder_status(chosen_mixdown_info)
    local render_panel_x = content_right - 394
    local render_panel_w = 394
    local choose_btn = { x = render_panel_x, y = 64, w = 94, h = 28 }
    local create_top_btn = { x = render_panel_x + 100, y = 64, w = 104, h = 28 }
    local prepare_btn = { x = render_panel_x + 210, y = 64, w = 88, h = 28 }
    local queue_btn = { x = render_panel_x + 304, y = 64, w = 88, h = 28 }
    local index_btn = { x = render_panel_x + 104, y = 98, w = 150, h = 24 }
    local set_btn = { x = render_panel_x + 260, y = 98, w = 42, h = 24 }
    local open_queue_btn = { x = render_panel_x + 310, y = 98, w = 82, h = 24 }
    local selection_active = selected_row_count(groups) > 0
    if draw_button(choose_btn, "Selezione", selection_active, region_count > 0, clicked, "tab") then
      if edit_name_index and active_field == "inline_name" then commit_name_edit(groups) end
      save_draft_state()
      local group = groups[selected_preview]
      if group and group.marker_only then
        chosen_mixdown_info = render_folder_info_from_marker_row(group)
        chosen_mixdown_groups = region_groups_for_marker_section(group)
        mark_selected_rows_for_render_groups(groups, chosen_mixdown_groups)
        selected_marker_indices = { [selected_preview] = true }
        selected_marker_index = selected_preview
      else
        local render_groups = selected_or_all_groups(groups, names)
        chosen_mixdown_groups = render_groups
        chosen_mixdown_info = render_folder_info(render_groups)
      end
      select_project_material_for_groups(chosen_mixdown_groups or {}, state)
    end
    local chosen_count_top = selected_row_count(groups)
    local create_top_label = chosen_count_top > 0 and "Crea Selez." or "Crea Regioni"
    if draw_button(create_top_btn, create_top_label, false, region_count > 0, clicked, "tab") then
      create_selected_regions_from_preview(groups, names, state)
      items, groups, names, source = rebuild()
      region_count = count_region_rows(groups)
    end
    state.preroll_warmup = false -- Forza la disattivazione del ghost in background
    if draw_button(index_btn, "Index", state.mixdown_index_enabled, true, clicked, state.mixdown_index_enabled and "save" or "tab") then
      state.mixdown_index_enabled = not state.mixdown_index_enabled
      save_draft_state()
      if state.mixdown_index_enabled then
        notify_status("Mixdown Index attivo: aggiorno anche Mixdown Index CSV.")
      else
        notify_status("Mixdown Index disattivato: aggiorno solo Mixdown Report CSV.")
      end
    end
    local render_button_ready = region_count > 0 and reaper.time_precise() >= render_dialog_lock_until and not pending_mixdown_report
    if draw_button(prepare_btn, "Render", false, render_button_ready, clicked, "save") then
      render_dialog_lock_until = reaper.time_precise() + 300.0
      render_debug_log("render_button | click Render lock_until=" .. tostring(render_dialog_lock_until))
      if edit_name_index and active_field == "inline_name" then commit_name_edit(groups) end
      save_draft_state()
      local render_groups = chosen_mixdown_groups
      local folder = chosen_mixdown_info
      if not render_groups then
        render_groups, folder = mixdown_selection_from_active_marker(groups)
      end
      if not render_groups then render_groups = selected_or_all_groups(groups, names) end
      folder = folder or render_folder_info(render_groups)
      local folder_path = mixdown_folder_path(folder)
      render_debug_log(string.format(
        "render_button | selection groups=%d folder=%s folder_path=%s",
        #(render_groups or {}),
        log_escape((folder and (folder.relative or folder.safe_name or folder.raw_name)) or ""),
        log_escape(folder_path or "")
      ))
      if folder_path and directory_exists(folder_path) and directory_has_files(folder_path) then
        local msg = "La cartella Mixdown contiene gia' file:\n" .. folder.relative .. "\n\nNon sovrascrivo nulla automaticamente. Controlla la finestra Render to File prima di premere Render.\n\nProcedere?"
        if reaper.ShowMessageBox(msg, SCRIPT_TITLE, 4) ~= 6 then
          render_debug_log("render_button | annullato: cartella mixdown gia piena")
          render_dialog_lock_until = 0
          goto skip_prepare_mixdown
        end
        render_debug_log("render_button | confermata cartella mixdown gia piena")
      end
      local prepared_ok, prepared_folder, prepared_regions = prepare_render_mixdown(render_groups, folder, state.preroll_warmup)
      if prepared_ok then
        local expected_folder = mixdown_folder_path(prepared_folder or folder)
        if expected_folder then arm_mixdown_report_monitor(prepared_regions or region_rows_for_render(render_groups), prepared_folder or folder, expected_folder, state.preroll_warmup) end
        render_debug_log("render_button | Render to File preparato")
      else
        render_debug_log("render_button | preparazione fallita, rilascio lock")
        render_dialog_lock_until = 0
      end
      ::skip_prepare_mixdown::
    end
    if draw_button(queue_btn, "+ Queue", false, region_count > 0, clicked, "tab") then
      if edit_name_index and active_field == "inline_name" then commit_name_edit(groups) end
      save_draft_state()
      local sections = queue_sections_from_current_selection(groups, chosen_mixdown_groups, chosen_mixdown_info)
      if not sections or #sections == 0 then
        reaper.ShowMessageBox("Prima scegli una o piu' sezioni/marker con 'Selezione', oppure lascia attiva una riga marker Lane 1/Lane 2.\n\nLa queue lavora per cartella marker: ogni job contiene tutte le regioni della sua sezione.", SCRIPT_TITLE, 0)
        goto skip_queue_mixdown
      end
      local added_jobs = 0
      local added_regions = 0
      for _, section in ipairs(sections) do
        local section_groups = section.groups or {}
        local section_folder = section.folder or render_folder_info(section_groups)
        if #region_rows_for_render(section_groups) > 0 and add_mixdown_section_to_queue(section_groups, section_folder) then
          added_jobs = added_jobs + 1
          added_regions = added_regions + #real_mixdown_regions(region_rows_for_render(section_groups))
        end
      end
      if added_jobs > 1 then
        notify_status(string.format("Aggiunti %d job alla Render Queue, uno per cartella marker, con %d regioni totali.", added_jobs, added_regions))
      end
      ::skip_queue_mixdown::
    end
    if draw_button(set_btn, "Set", false, true, clicked, "tab") then
      mixdown_draft = copy_mixdown_settings()
      show_mixdown_settings = true
    end
    local native_queue_count = render_queue_count()
    if draw_button(open_queue_btn, "Que", native_queue_count > 0, native_queue_count > 0, clicked, native_queue_count > 0 and "save" or nil) then
      render_debug_log("open_queue_button | apro Render Queue count=" .. tostring(native_queue_count))
      reaper.Main_OnCommand(OPEN_RENDER_QUEUE_CMD, 0)
    end
    local render_summary_x = create_top_btn.x
    local render_summary_w = content_right - render_summary_x
    draw_mixdown_status_dot(render_summary_x + 5, 136, status_color)
    gfx.set(0.72, 0.77, 0.82, 1)
    gfx.x = render_summary_x + 18
    gfx.y = 127
    gfx.drawstr(fit_text("Formato: " .. mixdown_summary(), render_summary_w - 24))
    gfx.x = render_summary_x
    gfx.y = 149
    gfx.drawstr("Cartella:")
    gfx.set(0.58, 0.78, 0.62, 1)
    gfx.x = render_summary_x + 72
    gfx.y = 149
    gfx.drawstr(fit_text(status_label, render_summary_w - 78))
    gfx.set(0.72, 0.77, 0.82, 1)
    gfx.x = render_summary_x
    gfx.y = 167
    gfx.drawstr(fit_text_middle(tostring(render_info.relative or "Mixdown/"), render_summary_w))

    local compact_top = false
    local compact_actions = false

    local gap_rect = { x = 22, y = 104, w = 126, h = 32 }
    local pad_in_rect = { x = 168, y = 104, w = 126, h = 32 }
    local pad_out_rect = { x = 314, y = 104, w = 126, h = 32 }
    if draw_input(gap_rect, "Gap nuovo file (s)", gap_text, active_field == "gap", true, clicked, numeric_cursor.gap, numeric_select_all.gap) then
      local now = reaper.time_precise()
      local is_double = last_input_click_field == "gap" and (now - last_input_click_time) < 0.35
      active_field = "gap"
      numeric_select_all.gap = is_double
      numeric_cursor.gap = is_double and (#gap_text + 1) or cursor_from_x(gap_text, gfx.mouse_x, gap_rect.x + 8)
      last_input_click_field, last_input_click_time = "gap", now
      log_debug("FOCUS", string.format("gap cursor=%d", numeric_cursor.gap))
    end
    if draw_input(pad_in_rect, "Padding inizio (s)", pad_in_text, active_field == "pad_in", true, clicked, numeric_cursor.pad_in, numeric_select_all.pad_in) then
      local now = reaper.time_precise()
      local is_double = last_input_click_field == "pad_in" and (now - last_input_click_time) < 0.35
      active_field = "pad_in"
      numeric_select_all.pad_in = is_double
      numeric_cursor.pad_in = is_double and (#pad_in_text + 1) or cursor_from_x(pad_in_text, gfx.mouse_x, pad_in_rect.x + 8)
      last_input_click_field, last_input_click_time = "pad_in", now
      log_debug("FOCUS", string.format("pad_in cursor=%d", numeric_cursor.pad_in))
    end
    if draw_input(pad_out_rect, "Padding fine (s)", pad_out_text, active_field == "pad_out", true, clicked, numeric_cursor.pad_out, numeric_select_all.pad_out) then
      local now = reaper.time_precise()
      local is_double = last_input_click_field == "pad_out" and (now - last_input_click_time) < 0.35
      active_field = "pad_out"
      numeric_select_all.pad_out = is_double
      numeric_cursor.pad_out = is_double and (#pad_out_text + 1) or cursor_from_x(pad_out_text, gfx.mouse_x, pad_out_rect.x + 8)
      last_input_click_field, last_input_click_time = "pad_out", now
      log_debug("FOCUS", string.format("pad_out cursor=%d", numeric_cursor.pad_out))
    end

    local list_btn_y = 104
    local list_btn_x = 454
    local paste_start_row = paste_start_row_for_groups(groups)
    local paste_button_label = paste_start_row and string.format("Incolla da %02d", paste_start_row) or "Incolla lista"
    if draw_button({ x = list_btn_x, y = list_btn_y, w = 142, h = 32 }, paste_button_label, false, true, clicked) then
      local pasted = set_clipboard_or_prompt()
      if pasted then
        paste_name_list_from_row(pasted, paste_start_row or 1, groups)
      end
    end
    if draw_button({ x = list_btn_x, y = list_btn_y + 38, w = 142, h = 32 }, "Svuota lista", false, true, clicked) then
      clear_name_state()
    end

    local mode_y = 178
    gfx.set(0.80, 0.78, 0.68, 1)
    gfx.x = 22
    gfx.y = mode_y - 19
    gfx.drawstr("Sorgente")
    if draw_button({ x = 22, y = mode_y, w = 80, h = 30 }, "Item", state.collect_mode == "items", true, clicked) then
      state.collect_mode = "items"
      save_state(state)
    end
    if draw_button({ x = 110, y = mode_y, w = 88, h = 30 }, "Tracce", state.collect_mode == "tracks", true, clicked) then
      state.collect_mode = "tracks"
      save_state(state)
    end
    if draw_button({ x = 206, y = mode_y, w = 92, h = 30 }, "Folder+", state.collect_mode == "folder", true, clicked) then
      state.collect_mode = "folder"
      save_state(state)
    end
    if draw_button({ x = 306, y = mode_y, w = 74, h = 30 }, "Tutte", state.collect_mode == "all", true, clicked) then
      state.collect_mode = "all"
      save_state(state)
    end

    local action_y = mode_y + 42
    local old_count = count_own_regions()
    local transport_y = compact_actions and (action_y + 38) or action_y
    if draw_button({ x = 22, y = action_y, w = 170, h = 30 }, "Rimuovi export", state.delete_old, true, clicked) then
      state.delete_old = not state.delete_old
    end
    if draw_button({ x = 200, y = action_y, w = 92, h = 30 }, "Marker", state.make_markers, true, clicked) then
      state.make_markers = not state.make_markers
    end
    if draw_button({ x = 300, y = action_y, w = 105, h = 30 }, "N. + nome", state.number_names, true, clicked) then
      state.number_names = not state.number_names
    end
    local transport_x = compact_actions and 22 or 420
    if draw_button({ x = transport_x, y = transport_y, w = 86, h = 30 }, "Sel", play_row, region_count > 0, clicked, "play_select") then
      play_row = not play_row
      reaper.SetExtState(EXT_SECTION, "play_row", play_row and "1" or "0", true)
    end
    if draw_button({ x = transport_x + 94, y = transport_y, w = 82, h = 30 }, "Play", false, region_count > 0, clicked, "play_now") then
      local group = groups[selected_preview]
      if is_region_row(group) then start_region_play(group) end
    end
    if draw_button({ x = transport_x + 184, y = transport_y, w = 58, h = 30 }, "", false, true, clicked, "stop") then
      stop_region_play()
    end
    local saved_recently = (reaper.time_precise() - last_saved_time) < 1.3
    if draw_button({ x = transport_x + 250, y = transport_y, w = 88, h = 30 }, saved_recently and "OK" or "Salva", saved_recently, true, clicked, "save") then
      if edit_name_index and active_field == "inline_name" then commit_name_edit(groups) end
      save_draft_state()
      save_project_file()
      notify_status("Stato Gestore Progetto e progetto REAPER salvati.")
      mark_saved()
    end
    local log_enabled = bool_from_state(reaper.GetExtState(EXT_SECTION, "mixdown_log_enabled"), false)
    if draw_button({ x = transport_x + 346, y = transport_y, w = 76, h = 30 }, "Log", log_enabled, region_count > 0, clicked, log_enabled and "save" or "tab") then
      local next_log = not log_enabled
      reaper.SetExtState(EXT_SECTION, "mixdown_log_enabled", tostring(next_log), true)
      save_draft_state()
      if next_log then
        notify_status("Log Mixdown History attivo.")
      else
        notify_status("Log Mixdown History disattivato.")
      end
    end
    local final_x = compact_actions and math.max(22, content_right - 92) or (content_right - 78)
    local final_y = compact_actions and transport_y or action_y
    if draw_button({ x = final_x, y = final_y, w = 72, h = 30 }, "Annulla", false, true, clicked) then
      if edit_name_index and active_field == "inline_name" then commit_name_edit(groups) end
      save_draft_state()
      gfx.quit()
      return
    end

    local status
    local effective_named = 0
    for _, group in ipairs(groups) do
      if is_region_row(group) then
        local order = group.region_order or 0
        local name = group.edited_name or names[order] or group.name
        if name and trim(name) ~= "" then effective_named = effective_named + 1 end
      end
    end
    if region_count > 0 and #items == 0 then
      status = string.format("%d regioni esistenti nella time selection, %d nomi. Senza nome = numero regione.", region_count, effective_named)
    elseif #items == 0 then
      status = "Nessun item/regione trovato. Seleziona item, tracce o una time selection con regioni."
    elseif effective_named == region_count then
      status = string.format("%d item da %s, %d regioni, %d nomi effettivi. Tutto allineato.", #items, source, region_count, effective_named)
    else
      status = string.format("%d item, %d regioni, %d nomi. Le regioni senza nome useranno il numero regione.", #items, region_count, effective_named)
    end
    if state.number_names then status = status .. " Numero + nome attivo." end
    local selected_count = selected_row_count(groups)
    if selected_count > 0 then status = status .. string.format(" Creerai solo %d righe selezionate.", selected_count) end
    if old_count > 0 then
      status = status .. string.format(" Regioni export gia' presenti: %d.", old_count)
    end
    gfx.set(effective_named == region_count and region_count > 0 and 0.64 or 0.95, effective_named == region_count and region_count > 0 and 0.85 or 0.70, effective_named == region_count and region_count > 0 and 0.72 or 0.44, 1)
    gfx.x = 22
    local status_y = action_y + 44
    gfx.y = status_y
    gfx.drawstr(fit_text(status, FIXED_WINDOW_W - 44))

    local box_y = status_y + 54
    local box_gap = 28
    local box_w = math.floor((FIXED_WINDOW_W - 44 - box_gap) * 0.5)
    local box_h = math.max(150, gfx.h - box_y - 24)
    local preview_box = { x = 22, y = box_y, w = box_w, h = box_h }
    local names_box = { x = preview_box.x + preview_box.w + box_gap, y = box_y, w = FIXED_WINDOW_W - (preview_box.x + preview_box.w + box_gap) - 22, h = box_h }
    local preview_row_h = 24
    local names_row_h = 20
    local preview_rows = math.max(1, math.floor((preview_box.h - 16) / preview_row_h))
    preview_visible_rows = preview_rows
    local names_rows = math.max(1, math.floor((names_box.h - 28) / names_row_h))
    preview_scroll = math.max(0, math.min(math.max(0, #groups - preview_rows), preview_scroll))
    local first_named_row = first_non_empty_name_row(names)
    local names_min_row = names_anchor_row or first_named_row
    local names_min_scroll = (names_min_row and names_min_row > 1) and (names_min_row - 1) or 0
    local names_max_scroll = math.max(names_min_scroll, math.max(0, #names - names_rows))
    names_scroll = math.max(names_min_scroll, math.min(names_max_scroll, names_scroll))

    gfx.set(0.80, 0.78, 0.68, 1)
    gfx.x = preview_box.x
    gfx.y = preview_box.y - 24
    gfx.drawstr("Anteprima regioni")
    gfx.set(0.10, 0.10, 0.13, 1)
    gfx.rect(preview_box.x, preview_box.y, preview_box.w, preview_box.h, true)
    gfx.set(0.34, 0.36, 0.42, 1)
    gfx.rect(preview_box.x, preview_box.y, preview_box.w, preview_box.h, false)

    if point_in_rect(gfx.mouse_x, gfx.mouse_y, preview_box.x, preview_box.y, preview_box.w, preview_box.h) and wheel ~= 0 then
      preview_scroll = math.max(0, math.min(math.max(0, #groups - preview_rows), preview_scroll - (wheel > 0 and 1 or -1)))
    end

	    for row = 1, math.min(preview_rows, #groups) do
	      local idx = preview_scroll + row
	      local group = groups[idx]
	      local y = preview_box.y + 8 + ((row - 1) * preview_row_h)
	      local row_rect = { x = preview_box.x + 5, y = y - 3, w = preview_box.w - 10, h = preview_row_h - 1 }
	      local hovered = point_in_rect(gfx.mouse_x, gfx.mouse_y, row_rect.x, row_rect.y, row_rect.w, row_rect.h)
	      local is_marker = group and group.marker_only
	      if is_marker then
	        gfx.set(0.18, 0.19, 0.24, 1)
	        gfx.rect(row_rect.x, row_rect.y, row_rect.w, row_rect.h, true)
	        if hovered then
	          gfx.set(0.23, 0.22, 0.28, 1)
	          gfx.rect(row_rect.x, row_rect.y, row_rect.w, row_rect.h, true)
	        end
	        if clicked and hovered then
	          local now = reaper.time_precise()
	          local same_inline = active_field == "inline_name" and edit_name_source == "marker" and edit_name_index == idx
	          local is_double = (now - last_preview_click_time) < 0.35
	          if same_inline then
	            if is_double then
	              edit_name_select_all = true
	              edit_name_cursor = #edit_name_text + 1
	            else
	              edit_name_select_all = false
	              local prefix = string.format("[M%d] ", group.marker_number or group.marker_idx or 0)
	              edit_name_cursor = cursor_from_x(edit_name_text, gfx.mouse_x, preview_box.x + 10 + gfx.measurestr(prefix))
	            end
	          else
	            if edit_name_index and active_field == "inline_name" then commit_name_edit(groups) end
	            active_field = nil
	            selected_preview = idx
	            local additive = (gfx.mouse_cap & 4) == 4 or (gfx.mouse_cap & 32) == 32
	            toggle_marker_section_selection(groups, group, additive)
	            if is_double then
	              start_marker_inline_name_input(groups, idx, true)
	              log_debug("FOCUS", string.format("inline marker row=%d", idx))
	            end
	          end
	          last_preview_click_time = now
	        end
	      	local marker_prefix = string.format("[M%d] ", group.marker_number or group.marker_idx or 0)
	        if selected_marker_index == idx or selected_marker_indices[idx] then
	          gfx.set(0.10, 0.34, 0.47, 1)
	          gfx.rect(row_rect.x, row_rect.y, row_rect.w, row_rect.h, true)
	          gfx.set(0.38, 0.86, 1.0, 1)
	          gfx.rect(row_rect.x, row_rect.y, row_rect.w, row_rect.h, false)
	          gfx.rect(row_rect.x + 2, row_rect.y + 2, 4, row_rect.h - 4, true)
	        end
	        if edit_name_source == "marker" and edit_name_index == idx then
	          gfx.set(0.13, 0.17, 0.24, 1)
	          gfx.rect(row_rect.x + 4, row_rect.y + 1, row_rect.w - 8, row_rect.h - 2, true)
	          gfx.set(1.0, 0.78, 0.18, 1)
	          gfx.rect(row_rect.x + 4, row_rect.y + 1, row_rect.w - 8, row_rect.h - 2, false)
	          gfx.set(0.95, 0.68, 0.28, 1)
	          gfx.x = preview_box.x + 10
	          gfx.y = y
	          gfx.drawstr(marker_prefix)
	          local prefix_w = gfx.measurestr(marker_prefix)
	          if edit_name_select_all and edit_name_text ~= "" then
	            local text_w = math.min(gfx.measurestr(edit_name_text), preview_box.w - prefix_w - 26)
	            gfx.set(0.22, 0.48, 0.70, 0.95)
	            gfx.rect(preview_box.x + 10 + prefix_w, y - 2, text_w + 4, 19, true)
	          end
	          gfx.set(0.95, 0.86, 0.66, 1)
	          gfx.x = preview_box.x + 10 + prefix_w
	          gfx.y = y
	          local edit_label = edit_name_text ~= "" and edit_name_text or "(nome marker)"
	          gfx.drawstr(fit_text(edit_label, preview_box.w - prefix_w - 22))
	          if not edit_name_select_all and math.floor(reaper.time_precise() * 2) % 2 == 0 then
	            local tw = prefix_w + gfx.measurestr(edit_name_text:sub(1, edit_name_cursor - 1))
	            gfx.set(1.0, 0.78, 0.18, 1)
	            gfx.rect(preview_box.x + 10 + math.min(tw, preview_box.w - 24), y - 2, 2, 18, true)
	          end
	        else
	          gfx.set(0.95, 0.68, 0.28, 1)
	          gfx.x = preview_box.x + 10
	          gfx.y = y
	          gfx.drawstr(fit_text(group.marker_label or group.name or "[Marker]", preview_box.w - 24))
	        end
	        goto continue_preview_row
	      end
	      if idx == selected_preview then
	        gfx.set(0.12, 0.34, 0.46, 1)
	        gfx.rect(row_rect.x, row_rect.y, row_rect.w, row_rect.h, true)
      elseif hovered then
        gfx.set(0.16, 0.16, 0.20, 1)
        gfx.rect(row_rect.x, row_rect.y, row_rect.w, row_rect.h, true)
      end
      if selected_rows[idx] then
        gfx.set(0.96, 0.76, 0.28, 1)
        gfx.rect(row_rect.x + 2, row_rect.y + 2, 4, row_rect.h - 4, true)
        gfx.rect(row_rect.x + row_rect.w - 6, row_rect.y + 2, 4, row_rect.h - 4, true)
      end
	      if clicked and hovered then
	        local now = reaper.time_precise()
	        local row_number = group.region_order or idx
	        local prefix_for_edit = string.format("  %02d  ", row_number)
	        local same_inline = active_field == "inline_name" and edit_name_source == "preview" and edit_name_index == idx
	        local is_double = (now - last_preview_click_time) < 0.35
        if same_inline then
          if is_double then
            edit_name_select_all = true
            edit_name_cursor = #edit_name_text + 1
          else
            edit_name_select_all = false
            edit_name_cursor = cursor_from_x(edit_name_text, gfx.mouse_x, preview_box.x + 10 + gfx.measurestr(prefix_for_edit))
          end
	          selected_preview = idx
	          selected_marker_index = nil
	          last_preview_click_time = now
        else
        if edit_name_index and active_field == "inline_name" then commit_name_edit(groups) end
	        selected_preview = idx
	        selected_marker_index = nil
	        select_preview_row(idx, groups)
        active_field = nil
	        if play_row then
	          start_region_play(group)
	        end
        if is_double then
          start_preview_inline_name_input(groups, idx, true)
          log_debug("FOCUS", string.format("inline preview row=%d", idx))
        end
        last_preview_click_time = now
        end
      end
      local label = group.edited_name or group.name or "(senza nome)"
      if label == "" then label = "(senza nome)" end
      if edit_name_source == "preview" and edit_name_index == idx then
        gfx.set(0.13, 0.17, 0.24, 1)
        gfx.rect(row_rect.x + 4, row_rect.y + 1, row_rect.w - 8, row_rect.h - 2, true)
        gfx.set(1.0, 0.78, 0.18, 1)
        gfx.rect(row_rect.x + 4, row_rect.y + 1, row_rect.w - 8, row_rect.h - 2, false)
	        local row_number = group.region_order or idx
	        local prefix = string.format("  %02d  ", row_number)
	        gfx.set(0.58, 0.58, 0.66, 1)
	        gfx.x = preview_box.x + 10
        gfx.y = y
        gfx.drawstr(prefix)
        if edit_name_select_all and edit_name_text ~= "" then
          local prefix_w = gfx.measurestr(prefix)
          local text_w = math.min(gfx.measurestr(edit_name_text), preview_box.w - prefix_w - 26)
          gfx.set(0.22, 0.48, 0.70, 0.95)
          gfx.rect(preview_box.x + 10 + prefix_w, y - 2, text_w + 4, 19, true)
          gfx.set(0.98, 0.97, 1.0, 1)
          gfx.x = preview_box.x + 10
          gfx.y = y
        end
        gfx.set(0.88, 0.88, 0.91, 1)
        gfx.x = preview_box.x + 10 + gfx.measurestr(prefix)
        gfx.y = y
        local edit_label = edit_name_text ~= "" and edit_name_text or "(nome regione)"
        gfx.drawstr(fit_text(edit_label, preview_box.w - 70))
        if not edit_name_select_all and math.floor(reaper.time_precise() * 2) % 2 == 0 then
          local tw = gfx.measurestr(prefix) + gfx.measurestr(edit_name_text:sub(1, edit_name_cursor - 1))
          gfx.set(1.0, 0.78, 0.18, 1)
          gfx.rect(preview_box.x + 10 + math.min(tw, preview_box.w - 24), y - 2, 2, 18, true)
        end
	      else
	        local row_number = group.region_order or idx
	        local text = string.format("  %02d  %s", row_number, label)
	        gfx.set(0.88, 0.88, 0.91, 1)
	        gfx.x = preview_box.x + 10
	        gfx.y = y
	        gfx.drawstr(fit_text(text, preview_box.w - 20))
	      end
	      ::continue_preview_row::
	    end
    if #groups == 0 then
      gfx.set(0.50, 0.50, 0.56, 1)
      gfx.x = preview_box.x + 10
      gfx.y = preview_box.y + 10
      gfx.drawstr("Seleziona item, tracce con item, o una time selection con regioni.")
    end
    draw_v_scroll(preview_box, #groups, preview_rows, preview_scroll)

    gfx.set(0.80, 0.78, 0.68, 1)
    gfx.x = names_box.x
    gfx.y = names_box.y - 24
    gfx.drawstr("Nomi incollabili/editabili")
    gfx.set(0.10, 0.10, 0.13, 1)
    gfx.rect(names_box.x, names_box.y, names_box.w, names_box.h, true)
    gfx.set(0.34, 0.36, 0.42, 1)
    gfx.rect(names_box.x, names_box.y, names_box.w, names_box.h, false)
    if point_in_rect(gfx.mouse_x, gfx.mouse_y, names_box.x, names_box.y, names_box.w, names_box.h) and wheel ~= 0 then
      local names_min_row = names_anchor_row or first_non_empty_name_row(names)
      local names_min_scroll = (names_min_row and names_min_row > 1) and (names_min_row - 1) or 0
      local names_max_scroll = math.max(names_min_scroll, math.max(0, #names - names_rows))
      names_scroll = math.max(names_min_scroll, math.min(names_max_scroll, names_scroll - (wheel > 0 and 1 or -1)))
    end
    if clicked and point_in_rect(gfx.mouse_x, gfx.mouse_y, names_box.x, names_box.y, names_box.w, names_box.h) then
      local now = reaper.time_precise()
      local row = names_scroll + math.floor((gfx.mouse_y - names_box.y - 10) / names_row_h) + 1
      row = math.max(1, math.min(row, math.max(#names + 1, 1)))
      local same_inline = active_field == "inline_name" and edit_name_source == "names" and edit_name_index == row
      local is_double = (now - last_names_click_time) < 0.35
      if same_inline then
        if is_double then
          edit_name_select_all = true
          edit_name_cursor = #edit_name_text + 1
        else
          local prefix = string.format("%02d  ", row)
          edit_name_select_all = false
          edit_name_cursor = cursor_from_x(edit_name_text, gfx.mouse_x, names_box.x + 10 + gfx.measurestr(prefix))
        end
      else
        if edit_name_index and active_field == "inline_name" then commit_name_edit(groups) end
        local current_name = names[row] or ""
        edit_name_index = row
        edit_name_text = current_name
        edit_name_source = "names"
        edit_name_cursor = #edit_name_text + 1
        edit_name_select_all = is_double
        active_field = "inline_name"
        log_debug("FOCUS", string.format("inline names row=%d cursor=%d text='%s'", row, edit_name_cursor, log_escape(edit_name_text)))
      end
      last_names_click_time = now
    end

    gfx.set(0.88, 0.88, 0.91, 1)
    local line_y = names_box.y + 10
    local visible_name_count = math.max(#names, edit_name_source == "names" and (edit_name_index or 0) or 0)
    for row = 1, math.min(names_rows, math.max(visible_name_count, 1)) do
      local i = names_scroll + row
      if edit_name_source == "names" and edit_name_index == i then
        local row_rect = { x = names_box.x + 6, y = line_y - 3, w = names_box.w - 12, h = names_row_h - 1 }
        gfx.set(0.13, 0.17, 0.24, 1)
        gfx.rect(row_rect.x, row_rect.y, row_rect.w, row_rect.h, true)
        gfx.set(1.0, 0.78, 0.18, 1)
        gfx.rect(row_rect.x, row_rect.y, row_rect.w, row_rect.h, false)
        local prefix = string.format("%02d  ", i)
        gfx.set(0.88, 0.88, 0.91, 1)
        gfx.x = names_box.x + 10
        gfx.y = line_y
        if edit_name_select_all and edit_name_text ~= "" then
          local prefix_w = gfx.measurestr(prefix)
          local text_w = math.min(gfx.measurestr(edit_name_text), names_box.w - prefix_w - 26)
          gfx.set(0.22, 0.48, 0.70, 0.95)
          gfx.rect(names_box.x + 10 + prefix_w, line_y - 2, text_w + 4, 19, true)
          gfx.set(0.98, 0.97, 1.0, 1)
          gfx.x = names_box.x + 10
          gfx.y = line_y
        end
        gfx.drawstr(prefix .. fit_text(edit_name_text, names_box.w - 58))
        if not edit_name_select_all and math.floor(reaper.time_precise() * 2) % 2 == 0 then
          local tw = gfx.measurestr(prefix .. edit_name_text:sub(1, edit_name_cursor - 1))
          gfx.set(1.0, 0.78, 0.18, 1)
          gfx.rect(names_box.x + 10 + math.min(tw, names_box.w - 24), line_y - 2, 2, 18, true)
        end
      else
        if names[i] then
          gfx.x = names_box.x + 10
          gfx.y = line_y
          gfx.drawstr(fit_text(string.format("%02d  %s", i, names[i]), names_box.w - 20))
        end
      end
      line_y = line_y + names_row_h
    end
    if #names == 0 and not (edit_name_source == "names" and edit_name_index) then
      gfx.set(0.50, 0.50, 0.56, 1)
      gfx.x = names_box.x + 10
      gfx.y = names_box.y + 10
      gfx.drawstr("Scrivi qui; seleziona una riga o una regione per incollare da li'.")
    elseif names_anchor_row and names_anchor_row > 1 then
      gfx.set(0.58, 0.58, 0.64, 1)
      gfx.x = names_box.x + 10
      gfx.y = names_box.y + names_box.h - 24
      gfx.drawstr(string.format("Vista dal %02d: righe precedenti non interessate.", names_anchor_row))
    elseif first_named_row and first_named_row > 1 and names_scroll >= first_named_row - 1 then
      gfx.set(0.58, 0.58, 0.64, 1)
      gfx.x = names_box.x + 10
      gfx.y = names_box.y + names_box.h - 24
      gfx.drawstr(string.format("Righe 1-%d vuote: non rinominano nulla.", first_named_row - 1))
    elseif #names > names_rows then
      gfx.set(0.58, 0.58, 0.64, 1)
      gfx.x = names_box.x + 10
      gfx.y = names_box.y + names_box.h - 24
      gfx.drawstr(string.format("... altri %d nomi", #names - names_rows))
    end
    draw_v_scroll(names_box, #names, names_rows, names_scroll)

    if show_mixdown_settings then
      draw_mixdown_settings_overlay(overlay_clicked)
    elseif show_help then
      if draw_help_overlay(clicked) then show_help = false end
    end

    gfx.update()
    reaper.defer(loop)
  end

  reaper.defer(loop)
  return true
end

local function osara_region_rows(groups)
  local rows = {}
  for _, group in ipairs(groups or {}) do
    if is_region_row(group) then rows[#rows + 1] = group end
  end
  return rows
end

local function osara_marker_rows(groups)
  local rows = {}
  for _, group in ipairs(groups or {}) do
    if group and group.marker_only and group.marker_pos then rows[#rows + 1] = group end
  end
  return rows
end

local function osara_groups_for_marker_row(groups, marker_row)
  if not (groups and marker_row) then return {} end
  local out = {}
  local in_section = false
  for _, group in ipairs(groups) do
    if group.marker_only then
      if in_section then break end
      if group == marker_row or (group.marker_idx and marker_row.marker_idx and group.marker_idx == marker_row.marker_idx) then
        in_section = true
      end
    elseif in_section and is_region_row(group) then
      out[#out + 1] = group
    end
  end
  return out
end

local function osara_section_summary(marker_rows)
  local lines = { "Sezioni disponibili:" }
  for i, marker in ipairs(marker_rows or {}) do
    local label = marker.marker_label or marker.marker_name or marker.name or ("Sezione " .. i)
    lines[#lines + 1] = string.format("%d: %s", i, label)
  end
  if #lines == 1 then lines[#lines + 1] = "Nessun marker/sezione trovato." end
  return table.concat(lines, "\n")
end

local function run_osara_mode()
  local state = get_state()
  local ok, values = reaper.GetUserInputs(
    "Gestore Progetto OSARA",
    7,
    "Azione 1=seleziona 2=crea 3=nomi+crea,Sezione 0=tutte,Modo 1=item 2=tracce 3=folder 4=tutte,Gap nuovo file s,Padding inizio s,Padding fine s,Cancella vecchie 0/1",
    string.format("1,0,%s,%s,%s,%s,%s",
      state.collect_mode == "items" and "1" or state.collect_mode == "folder" and "3" or state.collect_mode == "all" and "4" or "2",
      state.gap, state.pad_in, state.pad_out, state.delete_old and "1" or "0")
  )
  if not ok then return end

  local action, section, mode, gap, pad_in, pad_out, delete_old =
    values:match("^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),(.*)$")
  action = math.floor(tonumber_locale(action, 1))
  section = math.floor(tonumber_locale(section, 0))
  mode = math.floor(tonumber_locale(mode, 2))
  if mode == 1 then
    state.collect_mode = "items"
  elseif mode == 3 then
    state.collect_mode = "folder"
  elseif mode == 4 then
    state.collect_mode = "all"
  else
    state.collect_mode = "tracks"
  end
  state.gap = math.max(0, tonumber_locale(gap, state.gap))
  state.pad_in = math.max(0, tonumber_locale(pad_in, state.pad_in))
  state.pad_out = math.max(0, tonumber_locale(pad_out, state.pad_out))
  state.delete_old = tonumber_locale(delete_old, 0) ~= 0
  save_state(state)

  local items, source_label = collect_items(state)
  local groups = build_preview_groups(items, state.gap, state.pad_in, state.pad_out)
  local markers = osara_marker_rows(groups)
  local target_groups

  if #markers > 0 then speak(osara_section_summary(markers)) end

  if section > 0 then
    local marker = markers[section]
    if not marker then
      speak(string.format("Sezione %d non trovata. Usa 0 per tutte oppure un numero tra 1 e %d.", section, #markers))
      return
    end
    target_groups = osara_groups_for_marker_row(groups, marker)
    if #target_groups == 0 then
      speak("La sezione scelta non contiene regioni o gruppi da creare.")
      return
    end
    speak(string.format("Sezione scelta: %s. Righe operative: %d.", marker.marker_label or marker.marker_name or marker.name or section, #target_groups))
  else
    target_groups = osara_region_rows(groups)
    if #target_groups == 0 then
      speak("Nessuna regione o gruppo trovato.")
      return
    end
    speak(string.format("Tutto il materiale: %d righe operative da %s.", #target_groups, source_label or "progetto"))
  end

  if action == 1 then
    local kind, count = select_project_material_for_groups(target_groups, state)
    if kind == "regions" then
      speak(string.format("Selezionate %d regioni export nel progetto.", count))
    elseif kind == "items" then
      speak(string.format("Selezionati %d item sorgente per creare le regioni.", count))
    else
      speak("Impostata la time selection della sezione. Non ho trovato regioni o item selezionabili.")
    end
    return
  end

  if action == 3 then
    local pasted = set_clipboard_or_prompt()
    if pasted then state.names_text = pasted end
    save_state(state)
  end

  local names = {}
  if action == 3 then names = parse_names_preserve_rows(state.names_text) end
  if create_regions(target_groups, names, state) then
    local created_regions = matching_export_regions(target_groups)
    if #created_regions > 0 then
      select_regions_in_region_manager(created_regions)
      set_time_selection_for_regions_or_groups(created_regions)
      speak(string.format("Regioni create o aggiornate. Selezionate %d regioni nel progetto.", #created_regions))
    else
      speak("Regioni create o aggiornate. Non sono riuscito a selezionarle nel Region Manager.")
    end
  end
end

local function main()
  if type(reaper.osara_outputMessage) == "function" then
    run_osara_mode()
    return
  end
  if not open_window() then run_osara_mode() end
end

main()
