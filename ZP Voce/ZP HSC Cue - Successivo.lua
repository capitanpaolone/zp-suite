-- @description ZP HSC Cue - Successivo
-- @version 1.1
-- @author Paolo Balestri
-- @about Porta il cursore al cue di rientro rapido successivo del Carver. Da assegnare a un tasto. Parla con il Carver della traccia selezionata (o con il primo del progetto).
-- @changelog
--   1.1: se ripremi il tasto mentre il messaggio e' ancora a schermo, riparte senza chiedere nulla.
--   1.0: prima versione (ZP Harmonic Space Carver 2.5).
-- Ripremuto mentre e' ancora attivo (messaggio a schermo): chiude il precedente e riparte, senza dialoghi.
if reaper.set_action_options then reaper.set_action_options(3) end
local GMEM, MAGIC = "ZPVoiceoverSharedBus", 905243
reaper.gmem_attach(GMEM)

-- Indirizzo gmem del Carver da comandare: traccia selezionata, poi master, poi la prima traccia che ne ha uno.
local function scan(track, idx)
  for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
    local ok, name = reaper.TrackFX_GetFXName(track, fx, "")
    if ok and name and name:lower():find("harmonic space carver", 1, true) then
      local b = 4096 + ((idx + 2) * 4096) + fx * 72
      if reaper.gmem_read(b + 69) == MAGIC then return b end
    end
  end
end
local function find_carver()
  local master = reaper.GetMasterTrack(0)
  for i = 0, reaper.CountSelectedTracks2(0, true) - 1 do
    local tr = reaper.GetSelectedTrack2(0, i, true)
    local idx = (tr == master) and -1 or (reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") - 1)
    local b = scan(tr, idx); if b then return b end
  end
  local b = scan(master, -1); if b then return b end
  for i = 0, reaper.CountTracks(0) - 1 do
    b = scan(reaper.GetTrack(0, i), i); if b then return b end
  end
end

local function fmt(t)
  local m = math.floor(t / 60)
  return string.format("%d:%04.1f", m, t - m * 60)
end

-- Messaggio non bloccante: OSARA se c'e', e un suggerimento vicino al mouse che sparisce da solo.
local function say(msg)
  if reaper.osara_outputMessage then reaper.osara_outputMessage(msg) end
  local x, y = reaper.GetMousePosition()
  reaper.TrackCtl_SetToolTip(msg, x + 14, y + 14, true)
  local t0 = reaper.time_precise()
  local function clear()
    if reaper.time_precise() - t0 < 2 then reaper.defer(clear) else reaper.TrackCtl_SetToolTip("", 0, 0, true) end
  end
  reaper.defer(clear)
end

local function now_pos()
  if (reaper.GetPlayState() & 1) == 1 then return (reaper.GetPlayPosition2 or reaper.GetPlayPosition)() end
  return reaper.GetCursorPosition()
end

local function read_cues(b)
  local n = math.max(0, math.min(64, math.floor(reaper.gmem_read(b + 4) + 0.5)))
  local cues = {}
  for i = 0, n - 1 do
    local t = reaper.gmem_read(b + 5 + i)
    if t >= 0 then cues[#cues + 1] = {time = t, index = i} end
  end
  table.sort(cues, function(a, c) return a.time < c.time end)
  return cues
end

local function go(dir)
  local b = find_carver()
  if not b then say("Nessun Harmonic Space Carver attivo nel progetto"); return end
  local cues, now, target = read_cues(b), now_pos(), nil
  if dir < 0 then
    for _, c in ipairs(cues) do if c.time < now - 0.001 then target = c else break end end
  else
    for _, c in ipairs(cues) do if c.time > now + 0.001 then target = c; break end end
  end
  if not target then
    say(#cues == 0 and "Nessun cue" or (dir < 0 and "Nessun cue prima" or "Nessun cue dopo"))
    return
  end
  reaper.SetEditCurPos2(0, target.time, true, (reaper.GetPlayState() & 1) == 1)
  reaper.gmem_write(b + 2, target.index)
  say(string.format("Cue %d di %d, %s", target.index + 1, #cues, fmt(target.time)))
end

go(1)
