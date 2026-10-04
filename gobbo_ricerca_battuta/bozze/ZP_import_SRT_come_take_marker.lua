-- ZP import SRT come take marker (bozza, NON ancora nella Suite)
--
-- Per l'item audio selezionato: legge un SRT e scrive un take marker per ogni
-- cue. Il nome del marker e' solo il testo. Il tempo e' quello di inizio cue,
-- che per l'SRT di Whisper e' gia' il tempo SORGENTE: va scritto cosi' com'e',
-- senza compensare start offset o playrate (servono solo quando si torna in
-- timeline, non qui).
--
-- LA PARTE TUA: parse_time(). Sotto trovi cosa deve fare e tre prove.
-- Finche' non e' giusta lo script si ferma da solo e ti dice quale prova fallisce.

local function log(s) reaper.ShowConsoleMsg(tostring(s) .. "\n") end

-- ---------------------------------------------------------------------------
-- DA SCRIVERE: converte "HH:MM:SS,mmm" in secondi (numero).
--   "00:00:01,500" -> 1.5
-- Suggerimenti:
--   * s:match("(%d+):(%d+):(%d+)[,%.](%d+)") restituisce quattro stringhe
--     (ore, minuti, secondi, millisecondi): tonumber() le trasforma in numeri.
--   * Attento ai millisecondi: "5" non vale 5 ms. Pensa a "0." .. ms.
--   * Se la stringa non e' valida restituisci nil.
-- ---------------------------------------------------------------------------
local function parse_time(s)
  return nil -- <-- sostituisci con il tuo codice
end

local TESTS = {
  { "00:00:01,500", 1.5 },
  { "00:01:02,250", 62.25 },
  { "01:00:00,000", 3600 },
}
for _, t in ipairs(TESTS) do
  local got = parse_time(t[1])
  if not got or math.abs(got - t[2]) > 0.0005 then
    reaper.MB("parse_time(\"" .. t[1] .. "\") ha dato " .. tostring(got) ..
              ", doveva dare " .. t[2], "Prova fallita", 0)
    return
  end
end

-- ---------------------------------------------------------------------------
-- Da qui in poi e' gia' pronto. Leggilo: e' la parte che riusiamo nel gobbo.
-- ---------------------------------------------------------------------------
local function file_exists(p)
  local f = io.open(p, "rb")
  if f then f:close() return true end
  return false
end

local function read_all(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

-- Un cue SRT: riga indice, riga "inizio --> fine", poi una o piu' righe di
-- testo, poi riga vuota. L'indice lo ignoriamo: ci basta riconoscere "-->".
local function parse_srt(data)
  data = data:gsub("^\239\187\191", ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  local cues, cur = {}, nil
  for line in (data .. "\n"):gmatch("(.-)\n") do
    if line:find("%-%->") then
      local start = parse_time(line:match("^%s*(%S+)%s*%-%->"))
      cur = start and { start = start, text = {} } or nil
    elseif line:match("^%s*$") then
      if cur and #cur.text > 0 then cues[#cues + 1] = cur end
      cur = nil
    elseif cur then
      cur.text[#cur.text + 1] = line
    end
  end
  if cur and #cur.text > 0 then cues[#cues + 1] = cur end
  return cues
end

local item = reaper.GetSelectedMediaItem(0, 0)
if not item then reaper.MB("Seleziona un item audio.", "Import SRT", 0) return end
local take = reaper.GetActiveTake(item)
if not take then reaper.MB("L'item non ha take.", "Import SRT", 0) return end

-- 1) cerco l'SRT con lo stesso nome del WAV, altrimenti lo faccio scegliere
local src_path = reaper.GetMediaSourceFileName(reaper.GetMediaItemTake_Source(take), "")
local guess = src_path:gsub("%.[^./\\]+$", "") .. ".srt"
local srt_path = guess
if not file_exists(srt_path) then
  local ok, chosen = reaper.GetUserFileNameForRead(guess, "Scegli l'SRT", "srt")
  if not ok then return end
  srt_path = chosen
end

local cues = parse_srt(read_all(srt_path) or "")
if #cues == 0 then reaper.MB("Nessun cue trovato in:\n" .. srt_path, "Import SRT", 0) return end

-- 2) se ci sono gia' marker, chiedo prima di sostituirli (cosi' si puo' rilanciare)
local existing = reaper.GetNumTakeMarkers(take)
reaper.Undo_BeginBlock()
if existing > 0 then
  local r = reaper.MB(existing .. " marker gia' presenti nel take.\nSostituirli?", "Import SRT", 3)
  if r == 2 then reaper.Undo_EndBlock("Import SRT (annullato)", -1) return end
  if r == 6 then
    for i = existing - 1, 0, -1 do reaper.DeleteTakeMarker(take, i) end
  end
end

-- 3) un marker per cue, nome = solo testo su una riga
for _, c in ipairs(cues) do
  local text = table.concat(c.text, " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  reaper.SetTakeMarker(take, -1, text, c.start)
end
reaper.Undo_EndBlock("Import SRT come take marker", -1)
reaper.UpdateArrange()

log(string.format("Importati %d cue da %s", #cues, srt_path:match("[^/\\]+$") or srt_path))
