-- CREA MARKER ALL'INIZIO DEGLI ITEM SELEZIONATI
-- Linea: ZP Paolo Balestri
-- Suite: ZP Studio Suite for REAPER v1.0.5
-- Distribuzione gratuita.
-- Modo:
--   0 = marker senza nome
--   1 = marker con nome fisso
--   2 = marker con nome numerato
-- TC video:
--   0 = non aggiunge timecode
--   1 = aggiunge il timecode video al nome marker

local DEBUG_LOG_PATH = "/tmp/RythmoBand_Marker_Item.log"

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

local function get_project_fps()
  local fps = 25
  if reaper.TimeMap_curFrameRate then fps = reaper.TimeMap_curFrameRate(0) end
  if not fps or fps <= 0 then fps = 25 end
  return fps
end

local function format_timecode(seconds)
  local fps = get_project_fps()
  local frame_base = math.max(1, math.floor(fps + 0.5))
  local time_val = math.max(0, seconds or 0)
  local h = math.floor(time_val / 3600)
  local m = math.floor((time_val / 60) % 60)
  local s = math.floor(time_val % 60)
  local f = math.floor(((time_val - math.floor(time_val)) * fps) + 0.0001)

  if f >= frame_base then
    f = 0
    s = s + 1
    if s >= 60 then
      s = 0
      m = m + 1
      if m >= 60 then
        m = 0
        h = h + 1
      end
    end
  end

  return string.format("%02d:%02d:%02d:%02d", h, m, s, f)
end

local function find_region_for_position(pos)
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local total = num_markers + num_regions
  for i = 0, total - 1 do
    local ok, is_region, rgn_pos, rgn_end = reaper.EnumProjectMarkers(i)
    if ok and is_region and pos >= rgn_pos and pos < rgn_end then
      return rgn_pos
    end
  end
  return nil
end

local function find_track_by_name(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if track_name == name or track_name:find(name) then return track end
  end
  return nil
end

local function find_video_item_start_for_position(pos)
  local track = find_track_by_name("VIDEO")
  if not track then return nil end

  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if pos >= item_pos and pos <= item_pos + item_len then
      return item_pos
    end
  end
  return nil
end

local function format_video_timecode(project_pos)
  local zero = find_region_for_position(project_pos)
  if not zero then zero = find_video_item_start_for_position(project_pos) end
  if not zero then zero = 0 end
  return format_timecode(project_pos - zero)
end

local function speak(text)
  if reaper.osara_outputMessage then
    reaper.osara_outputMessage(text)
  else
    reaper.ShowMessageBox(text, "ZP Studio Suite - Marker", 0)
  end
end

local function osara_active()
  return type(reaper.osara_outputMessage) == "function"
end

local function choose_marker_settings_numeric()
  local ok, values = reaper.GetUserInputs(
    "Marker da item selezionati",
    3,
    "Modo 0 vuoto 1 nome 2 numerati,Nome base,TC video 0 no 1 si",
    "2,NOME,1"
  )

  if not ok then return nil end

  local mode_text, base_name, tc_text = values:match("^([^,]*),([^,]*),(.*)$")
  if not mode_text then
    mode_text, base_name = values:match("^([^,]*),(.*)$")
    tc_text = "1"
  end
  mode_text = trim(mode_text)
  base_name = trim(base_name)
  tc_text = trim(tc_text)

  local mode_choice = mode_text:match("[012]") or "2"
  local mode = mode_choice == "0" and 0 or (mode_choice == "1" and 1 or 2)
  if base_name == "" and mode ~= 0 then base_name = "Marker" end
  local add_video_tc = (tc_text:match("0") == nil)
  return mode, base_name, add_video_tc
end

local function choose_marker_settings()
  if _G.RYTHMOBAND_MARKER_CONFIG then
    local cfg = _G.RYTHMOBAND_MARKER_CONFIG
    local mode = tonumber(cfg.mode) or 2
    if mode < 0 or mode > 2 then mode = 2 end
    local base_name = trim(cfg.base_name or "NOME")
    if base_name == "" and mode ~= 0 then base_name = "Marker" end
    local add_video_tc = cfg.add_video_tc ~= false
    return mode, base_name, add_video_tc
  end
  return choose_marker_settings_numeric()
end

local function create_markers(mode, base_name, add_video_tc)
  local selected_count = reaper.CountSelectedMediaItems(0)
  debug_log("selected_count=" .. tostring(selected_count))
  if selected_count == 0 then
    speak("Nessun item selezionato.")
    return
  end

  debug_log("settings mode=" .. tostring(mode) .. " base=" .. tostring(base_name) .. " tc=" .. tostring(add_video_tc))

  local items = {}
  for i = 0, selected_count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    if item then
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      table.insert(items, { item = item, pos = pos })
    end
  end

  table.sort(items, function(a, b) return a.pos < b.pos end)
  debug_log("items=" .. tostring(#items))

  reaper.Undo_BeginBlock()

  for i, entry in ipairs(items) do
    local marker_name = ""
    if mode == 1 then
      marker_name = base_name
    elseif mode == 2 then
      marker_name = string.format("%s %03d", base_name, i)
    end

    if add_video_tc then
      local tc = format_video_timecode(entry.pos)
      if marker_name == "" then
        marker_name = tc
      else
        marker_name = marker_name .. " " .. tc
      end
    end

    reaper.AddProjectMarker2(0, false, entry.pos, 0, marker_name, -1, 0)
  end

  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Crea marker all'inizio degli item selezionati", -1)
  debug_log("DONE")

  speak(string.format("Creati %d marker.", #items))
end

local function main()
  os.remove(DEBUG_LOG_PATH)
  debug_log("START")

  if reaper.CountSelectedMediaItems(0) == 0 then
    speak("Nessun item selezionato.")
    return
  end

  local mode, base_name, add_video_tc = choose_marker_settings()
  if mode == nil then return end
  create_markers(mode, base_name, add_video_tc)
end

main()
