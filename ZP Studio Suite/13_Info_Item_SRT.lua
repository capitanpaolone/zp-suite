-- @noindex

-- INFO ITEM SRT RYTHMOBAND
-- Linea: ZP Paolo Balestri
-- Suite: ZP Studio Suite for REAPER v1.0.5
-- Distribuzione gratuita.
-- Mostra origine SRT, cue e testo dell'item selezionato.

local function trim(s)
  local out = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return out
end

local function file_exists(path)
  if not path or path == "" then return false end
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function basename(path)
  return (path or ""):match("[^/\\]+$") or (path or "")
end

local function get_item_string(item, key)
  local _, value = reaper.GetSetMediaItemInfo_String(item, key, "", false)
  return trim(value)
end

local function get_track_name(track)
  if not track then return "" end
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  return trim(name)
end

local function item_track(item)
  if reaper.GetMediaItemTrack then return reaper.GetMediaItemTrack(item) end
  for t = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, t)
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
      if reaper.GetTrackMediaItem(track, i) == item then return track end
    end
  end
  return nil
end

local function format_time(seconds)
  if reaper.format_timestr_pos then
    return reaper.format_timestr_pos(seconds or 0, "", 5)
  end
  return string.format("%.3f", seconds or 0)
end

local function speak_or_show(title, message)
  if type(reaper.osara_outputMessage) == "function" then
    local short = message:gsub("\n", ". ")
    reaper.osara_outputMessage(short)
  end
  reaper.ShowMessageBox(message, title, 0)
end

local count = reaper.CountSelectedMediaItems(0)
if count == 0 then
  speak_or_show("ZP Studio Suite - Info item SRT", "Seleziona un item SRT/testo.")
  return
end

local item = reaper.GetSelectedMediaItem(0, 0)
local track = item_track(item)
local track_name = get_track_name(track)
local item_name = get_item_string(item, "P_NAME")
local text = get_item_string(item, "P_NOTES")
local srt_path = get_item_string(item, "P_EXT:RythmoBand_SRT_PATH")
local srt_file = get_item_string(item, "P_EXT:RythmoBand_SRT_FILE")
local srt_cue = get_item_string(item, "P_EXT:RythmoBand_SRT_CUE")
local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

if srt_file == "" and srt_path ~= "" then srt_file = basename(srt_path) end

local lines = {}
lines[#lines + 1] = "Info item SRT"
lines[#lines + 1] = ""
if count > 1 then lines[#lines + 1] = "Item selezionati: " .. tostring(count) .. " (mostro il primo)" end
lines[#lines + 1] = "Traccia: " .. (track_name ~= "" and track_name or "(senza nome)")
lines[#lines + 1] = "Item: " .. (item_name ~= "" and item_name or "(senza nome)")
lines[#lines + 1] = "Posizione: " .. format_time(pos)
lines[#lines + 1] = "Durata: " .. format_time(len)
lines[#lines + 1] = ""

if srt_path ~= "" or srt_file ~= "" or srt_cue ~= "" then
  lines[#lines + 1] = "Origine SRT:"
  lines[#lines + 1] = "File: " .. (srt_file ~= "" and srt_file or "(non salvato)")
  lines[#lines + 1] = "Cue: " .. (srt_cue ~= "" and srt_cue or "(non salvata)")
  lines[#lines + 1] = "Percorso: " .. (srt_path ~= "" and srt_path or "(non salvato)")
  if srt_path ~= "" then
    lines[#lines + 1] = "Stato file: " .. (file_exists(srt_path) and "trovato" or "non trovato")
  end
else
  lines[#lines + 1] = "Origine SRT: metadata non presenti."
  lines[#lines + 1] = "Gli item vecchi vanno ricreati con Importa/Aggiorna SRT per salvare questi dati."
end

lines[#lines + 1] = ""
lines[#lines + 1] = "Testo:"
lines[#lines + 1] = text ~= "" and text or "(vuoto)"

speak_or_show("ZP Studio Suite - Info item SRT", table.concat(lines, "\n"))
