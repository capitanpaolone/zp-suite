-- @description ZP HSC - Mostra tracce voce
-- @version 1.0
-- @author Paolo Balestri
-- @about Seleziona le tracce che il Harmonic Space Carver considera voce: quelle che arrivano ai
--   pin delle fonti sidechain accese (invii e figlie del folder, risalendo le cartelle). Tracce mute
--   escluse. Serve per controllare il routing e il riferimento dei cue. Richiede l'helper Cue Navigator 1.5
--   nella stessa cartella. Parla con il Carver della traccia selezionata, o con il primo del progetto.
-- @changelog
--   1.0: prima versione (Carver 2.6, helper Cue Navigator 1.5).
local dir = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or ""
HSC_LIBRARY = true
local okload, HSC = pcall(dofile, dir .. "ZP Harmonic Space Carver Cue Navigator.lua")
HSC_LIBRARY = nil

local function say(msg)
  if reaper.osara_outputMessage then reaper.osara_outputMessage(msg) end
  local x, y = reaper.GetMousePosition()
  reaper.TrackCtl_SetToolTip(msg, x + 14, y + 14, true)
  local t0 = reaper.time_precise()
  local function clear()
    if reaper.time_precise() - t0 < 4 then reaper.defer(clear) else reaper.TrackCtl_SetToolTip("", 0, 0, true) end
  end
  reaper.defer(clear)
end

if not okload or type(HSC) ~= "table" or not HSC.voice_tracks then
  say("Manca l'helper Cue Navigator 1.5 nella cartella di questo script")
  return
end

local function carver_on(track)
  for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
    local ok, name = reaper.TrackFX_GetFXName(track, fx, "")
    if ok and name and name:lower():find("harmonic space carver", 1, true) then return fx end
  end
end

local track, fx
for i = 0, reaper.CountSelectedTracks2(0, true) - 1 do
  local t = reaper.GetSelectedTrack2(0, i, true)
  fx = carver_on(t); if fx then track = t; break end
end
if not track then
  for i = 0, reaper.CountTracks(0) - 1 do
    local t = reaper.GetTrack(0, i)
    fx = carver_on(t); if fx then track = t; break end
  end
end
if not track then say("Nessun Harmonic Space Carver nel progetto") return end

local _, carver_name = reaper.GetTrackName(track)
local voices = HSC.voice_tracks(track, fx)
if #voices == 0 then
  say(string.format("Carver su '%s': nessuna traccia arriva alle fonti sidechain accese. Controlla invii e pin.", carver_name))
  return
end

reaper.PreventUIRefresh(1)
reaper.Main_OnCommand(40297, 0)          -- Track: Unselect all tracks
local with_audio, names = 0, {}
for _, t in ipairs(voices) do
  reaper.SetTrackSelected(t, true)
  if HSC.has_audio(t) then
    with_audio = with_audio + 1
    local _, n = reaper.GetTrackName(t)
    names[#names + 1] = n
  end
end
reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
say(string.format("Voce del Carver su '%s': %d tracce selezionate, %d con audio: %s",
  carver_name, #voices, with_audio, table.concat(names, ", ")))
