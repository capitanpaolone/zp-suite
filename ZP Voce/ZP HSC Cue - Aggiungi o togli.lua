-- @description ZP HSC Cue - Aggiungi o togli
-- @version 1.0
-- @author Paolo Balestri
-- @about Mette o toglie un cue di rientro rapido del Carver sul playhead (in Play) o sul cursore (da fermo). Da assegnare a un tasto. Parla con il Carver della traccia selezionata (o con il primo del progetto).
-- @changelog
--   1.0: prima versione (ZP Harmonic Space Carver 2.5).
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

-- Manda un comando al Carver nella casella comune (gmem 3800: +0 destinatario, +1 comando,
-- +2 posizione, +3 seq) e aspetta l'esito (+4 ack, +5 esito, +6 cue, +7 numero cue).
local MB = 3800
local function send(b, cmd, pos, on_done)
  local seq = math.floor(reaper.gmem_read(MB + 3) + 0.5) + 1
  reaper.gmem_write(MB, b)
  reaper.gmem_write(MB + 1, cmd)
  reaper.gmem_write(MB + 2, pos or 0)
  reaper.gmem_write(MB + 3, seq)
  local t0 = reaper.time_precise()
  local function wait()
    if math.floor(reaper.gmem_read(MB + 4) + 0.5) == seq then
      on_done(math.floor(reaper.gmem_read(MB + 5) + 0.5), math.floor(reaper.gmem_read(MB + 6) + 0.5), math.floor(reaper.gmem_read(MB + 7) + 0.5))
    elseif reaper.time_precise() - t0 < 1.5 then
      reaper.defer(wait)
    else
      say("Il Carver non risponde: avvia il Play o apri la sua finestra")
    end
  end
  reaper.defer(wait)
end

local b = find_carver()
if not b then say("Nessun Harmonic Space Carver attivo nel progetto") return end
local pos = now_pos()
send(b, 1, pos, function(res, idx, n)
  if res == 1 then say(string.format("Cue %d di %d aggiunto a %s", idx, n, fmt(pos)))
  elseif res == 2 then say(string.format("Cue tolto a %s, ne restano %d", fmt(pos), n))
  else say("Cue pieni: massimo 64") end
end)
