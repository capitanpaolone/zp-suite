-- @noindex

-- ZP Studio Suite for REAPER
-- 31 SRT dall'audio: i take marker degli item selezionati diventano un SRT
-- accanto al file sorgente, con lo stesso nome.
--
-- Serve dopo il montaggio: le battute corrette in REAPER, o un file nato da un Glue
-- (che tiene solo i marker della parte usata), tornano a essere un SRT da consegnare
-- al fonico o da riusare. I tempi sono quelli del file (tempo sorgente), come
-- l'SRT di whisper: ricollegandolo con 29 "Abbina da..." torna identico.
--
-- Fine di ogni battuta = inizio della successiva; l'ultima dura al massimo 8 s
-- e non supera la fine del file.

local M = {}
local TITLE = "ZP SRT dall'audio"
local LAST_MAX = 8.0     -- secondi: durata massima dell'ultima battuta
local MIN_LEN = 0.3      -- secondi: durata minima di una battuta

---------------------------------------------------------------------------
-- LOGICA PURA (collaudabile con lua fuori da REAPER)
---------------------------------------------------------------------------

-- markers: { {src, text}, ... } anche da piu' item della stessa sorgente.
-- Tiene una sola battuta per punto (entro 1 ms): la prima trovata.
-- Marker di servizio (non sono testo): segnaposto "#...", azioni "!...", marker del SOLO
-- Recorder (SOLO_MARK_001, OK_001, BAD_001, ALT_001, NOISE_001, INSERT_001). Stessa regola del 14.
local SERVICE_PREFIXES = { "SOLO_MARK", "OK", "BAD", "ALT", "NOISE", "INSERT" }
function M.is_service(name)
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local c = name:sub(1, 1)
  if c == "#" or c == "!" then return true end
  for _, p in ipairs(SERVICE_PREFIXES) do
    if name:match("^" .. p .. "_%d+$") then return true end
  end
  return false
end

function M.cues(markers, source_len)
  local list = {}
  for _, m in ipairs(markers) do
    local text = (m.text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text ~= "" and not M.is_service(text) and m.src >= 0 then list[#list + 1] = { start = m.src, text = text } end
  end
  table.sort(list, function(a, b) return a.start < b.start end)
  local cues = {}
  for _, c in ipairs(list) do
    if not cues[#cues] or c.start - cues[#cues].start > 0.001 then cues[#cues + 1] = c end
  end
  for i, c in ipairs(cues) do
    local nxt = cues[i + 1] and cues[i + 1].start
    local stop = nxt or math.min(c.start + LAST_MAX, (source_len and source_len > c.start) and source_len or c.start + LAST_MAX)
    if stop - c.start < MIN_LEN then stop = c.start + MIN_LEN end
    c.stop = stop
  end
  return cues
end

function M.time(sec)
  local ms = math.floor(sec * 1000 + 0.5)
  return string.format("%02d:%02d:%02d,%03d", ms // 3600000, (ms // 60000) % 60, (ms // 1000) % 60, ms % 1000)
end

function M.srt(cues)
  local out = {}
  for i, c in ipairs(cues) do
    out[#out + 1] = string.format("%d\n%s --> %s\n%s\n", i, M.time(c.start), M.time(c.stop), c.text)
  end
  return table.concat(out, "\n")
end

if not reaper then return M end

---------------------------------------------------------------------------
-- PARTE REAPER
---------------------------------------------------------------------------

local function exists(p) local f = io.open(p, "rb"); if f then f:close() return true end return false end
local function base(p) return (p:gsub("%.[^./\\]+$", "")) end

local count = reaper.CountSelectedMediaItems(0)
if count == 0 then
  reaper.MB("Seleziona gli item audio con i marker delle battute.", TITLE, 0)
  return
end

-- marker raccolti per file sorgente (piu' pezzi dello stesso file = un solo SRT)
local by_source, order = {}, {}
for i = 0, count - 1 do
  local take = reaper.GetActiveTake(reaper.GetSelectedMediaItem(0, i))
  local src = take and reaper.GetMediaItemTake_Source(take)
  local path = src and reaper.GetMediaSourceFileName(src, "") or ""
  if path ~= "" and reaper.GetNumTakeMarkers(take) > 0 then
    local entry = by_source[path]
    if not entry then
      entry = { markers = {}, len = (reaper.GetMediaSourceLength(src)) }
      by_source[path] = entry
      order[#order + 1] = path
    end
    for j = 0, reaper.GetNumTakeMarkers(take) - 1 do
      local pos, name = reaper.GetTakeMarker(take, j)
      entry.markers[#entry.markers + 1] = { src = pos, text = name }
    end
  end
end
if #order == 0 then
  reaper.MB("Gli item selezionati non hanno marker sull'item.\n\nI marker si mettono con 29 ZP Trascrizione (Abbina da...) o con 14.", TITLE, 0)
  return
end

-- Tutte le domande prima di scrivere
local plan = {}
for _, path in ipairs(order) do
  local target = base(path) .. ".srt"
  local backup = false
  if exists(target) then
    local answer = reaper.MB(string.format(
      "Esiste gia' un SRT accanto a:\n%s\n\nSì: sostituiscilo (copia di sicurezza .srt.bak accanto).\nNo: salva un SRT nuovo \"(marker).srt\" accanto.\nAnnulla: esci senza scrivere niente.",
      path:match("[^/\\]+$") or path), TITLE, 3)
    if answer == 2 then return end
    if answer == 6 then backup = true else target = base(path) .. " (marker).srt" end
  end
  plan[#plan + 1] = { path = path, target = target, backup = backup }
end

local written, lines, failed = 0, 0, {}
for _, p in ipairs(plan) do
  local cues = M.cues(by_source[p.path].markers, by_source[p.path].len)
  if p.backup then
    os.remove(p.target .. ".bak")
    os.rename(p.target, p.target .. ".bak")
  end
  local f = io.open(p.target, "wb")
  if f then
    f:write(M.srt(cues))
    f:close()
    written, lines = written + 1, lines + #cues
  else
    failed[#failed + 1] = p.target
  end
end

local msg = string.format("SRT scritti: %d\nBattute: %d", written, lines)
if #failed > 0 then msg = msg .. "\n\nNon riesco a scrivere:\n" .. table.concat(failed, "\n") end
if written > 0 then msg = msg .. "\n\nAccanto ai file sorgente, con lo stesso nome." end
reaper.MB(msg, TITLE, 0)
