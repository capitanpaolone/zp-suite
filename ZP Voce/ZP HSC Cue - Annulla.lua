-- @description ZP HSC Cue - Annulla
-- @version 1.3
-- @author Paolo Balestri
-- @about Annulla l'ultima modifica ai cue di rientro rapido del Carver. Da assegnare a un tasto. Parla con il Carver della traccia selezionata (o con il primo del progetto).
-- @changelog
--   1.3: se l'helper sta usando la casella dei comandi, aspetta che si liberi invece di perdere il comando.
--   1.2: trova il Carver con il suo numero unico (Carver 2.6.3, helper 1.8).
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
      -- numero unico del Carver (2.6.3+, assegnato dall'helper), altrimenti traccia e posizione
      local b = 4096 + ((idx + 2) * 4096) + fx * 72
      for p = reaper.TrackFX_GetNumParams(track, fx) - 1, 0, -1 do
        local _, pname = reaper.TrackFX_GetParamName(track, fx, p, "")
        if pname and pname:find("HSC Slot", 1, true) then
          local slot = math.floor(reaper.TrackFX_GetParam(track, fx, p) + 0.5)
          if slot >= 1 and slot <= 900 then b = 8310000 + slot * 76 end
          break
        end
      end
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
local send
send = function(b, cmd, pos, on_done, force)
  -- se la casella e' occupata (l'helper sta mandando un elenco), aspetta che si liberi (max 0,5 s)
  local t_wait = reaper.time_precise()
  local function busy() return math.floor(reaper.gmem_read(MB + 4) + 0.5) ~= math.floor(reaper.gmem_read(MB + 3) + 0.5) end
  if not force and busy() then
    local function retry()
      if busy() and reaper.time_precise() - t_wait < 0.5 then reaper.defer(retry) else send(b, cmd, pos, on_done, true) end
    end
    reaper.defer(retry); return
  end
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
send(b, 4, 0, function(res, idx, n)
  if res == 5 then say(string.format("Annullato: tolto l'ultimo cue aggiunto, ne restano %d", n))
  elseif res == 6 then say(string.format("Annullato: cue rimessi, sono %d", n))
  else say("Niente da annullare") end
end)
