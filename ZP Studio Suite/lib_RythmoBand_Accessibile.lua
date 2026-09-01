local M = {}

M.track_name = "Rythmo Band Testi"

local function trim(s)
  local out = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return out
end

function M.clean_text(text)
  text = text or ""
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  local lines = {}
  for raw_line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local line = trim(raw_line:gsub("^\239\187\191", ""))
    local is_srt_number = line:match("^%d+$") ~= nil
    local is_timecode = line:match("%d%d:%d%d:%d%d[%.,]%d%d%d%s*%-%->") ~= nil
      or line:match("%d%d:%d%d:%d%d%s*%-%->") ~= nil
    local is_webvtt_noise = line == "WEBVTT" or line:match("^NOTE%s*$") ~= nil
    if line ~= "" and not is_srt_number and not is_timecode and not is_webvtt_noise then
      table.insert(lines, line)
    end
  end
  text = table.concat(lines, " ")
  text = text:gsub("%s+", " ")
  return trim(text)
end

function M.speak(text)
  text = M.clean_text(text)
  if text == "" then text = "Nessun testo." end

  if reaper.osara_outputMessage then
    reaper.osara_outputMessage(text)
  else
    reaper.ShowMessageBox(text, "ZP Studio Suite accessibile", 0)
  end
end

function M.get_track()
  local selected = reaper.GetSelectedTrack(0, 0)
  if selected then
    local _, name = reaper.GetSetMediaTrackInfo_String(selected, "P_NAME", "", false)
    if name:find(M.track_name) then return selected end
  end

  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if name:find(M.track_name) then return track end
  end

  return nil
end

function M.collect_items()
  local track = M.get_track()
  if not track then return nil, "Traccia Rythmo Band Testi non trovata." end

  local items = {}
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    if M.clean_text(notes) ~= "" then
      table.insert(items, { item = item, pos = pos, len = len, text = notes })
    end
  end

  table.sort(items, function(a, b) return a.pos < b.pos end)
  if #items == 0 then return nil, "Nessuna battuta trovata nella traccia testi." end
  return items, nil
end

function M.project_position()
  if (reaper.GetPlayState() & 1) == 1 then
    return reaper.GetPlayPosition()
  end
  return reaper.GetCursorPosition()
end

function M.find_current(items, pos)
  for index, entry in ipairs(items) do
    if pos >= entry.pos and pos <= entry.pos + entry.len then
      return index, entry
    end
  end
  return nil, nil
end

function M.find_next(items, pos)
  for index, entry in ipairs(items) do
    if entry.pos > pos then return index, entry end
  end
  return nil, nil
end

function M.find_previous(items, pos)
  local prev_index, prev_entry = nil, nil
  for index, entry in ipairs(items) do
    if entry.pos < pos then
      prev_index, prev_entry = index, entry
    else
      break
    end
  end
  return prev_index, prev_entry
end

function M.format_entry(prefix, index, total, entry)
  return M.clean_text(entry.text)
end

return M
