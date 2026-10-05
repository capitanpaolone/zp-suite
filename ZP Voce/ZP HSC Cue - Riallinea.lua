-- @description ZP HSC Cue - Riallinea
-- @version 1.1
-- @author Paolo Balestri
-- @about Riporta sulla loro voce tutti i cue del Harmonic Space Carver fuori posto (rossi). Da assegnare
--   a un tasto. Lo esegue l'helper Cue Navigator (1.6 o successivo), che deve essere in esecuzione.
-- @changelog
--   1.1: se ripremi il tasto mentre il messaggio e' ancora a schermo, riparte senza chiedere nulla.
--   1.0: prima versione (ZP Harmonic Space Carver 2.6.1).
-- Ripremuto mentre e' ancora attivo (messaggio a schermo): chiude il precedente e riparte, senza dialoghi.
if reaper.set_action_options then reaper.set_action_options(3) end
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

local seq = tostring(math.floor(reaper.time_precise() * 1000))
reaper.SetExtState("ZP_HSC", "req", "realign_all|" .. seq, false)
local t0 = reaper.time_precise()
local function wait()
  local rep = reaper.GetExtState("ZP_HSC", "rep")
  local rseq, n = rep:match("^(.-)|(%d+)$")
  if rseq == seq then
    n = tonumber(n)
    say(n == 0 and "Nessun cue fuori posto" or (n == 1 and "1 cue riallineato" or (n .. " cue riallineati")))
  elseif reaper.time_precise() - t0 < 1.5 then
    reaper.defer(wait)
  else
    say("L'helper Cue Navigator non risponde: avvialo dalla lista azioni")
  end
end
reaper.defer(wait)
