-- ZP leggi cue dal WAV (bozza, NON ancora nella Suite)
--
-- REAPER distingue due cose che a video sembrano uguali:
--   * take marker  -> stanno nel PROGETTO (.RPP); li legge GetTakeMarker
--   * cue del file -> stanno DENTRO il WAV (chunk "cue " + "LIST adtl"/"labl");
--                     REAPER li mostra, ma GetTakeMarker non li vede
-- Questo script legge i cue direttamente dal file, senza estensioni, e se vuoi
-- li copia come take marker, cosi' entrano nello stesso circuito di tutto il resto.
--
-- Il tempo di un cue e' in CAMPIONI dall'inizio del file: diviso per la frequenza
-- di campionamento da' i secondi sorgente, cioe' esattamente quello che vuole
-- SetTakeMarker. Come per l'SRT, nessuna compensazione di offset o playrate.

-- ============================ lettore (puro Lua) ============================
local function read_wav_cues(path)
  local f = io.open(path, "rb")
  if not f then return nil, "Impossibile aprire il file." end
  local hdr = f:read(12)
  if not hdr or #hdr < 12 or hdr:sub(1, 4) ~= "RIFF" or hdr:sub(9, 12) ~= "WAVE" then
    f:close()
    return nil, "Non e' un WAV (RIFF/WAVE)."
  end

  local rate, points, labels = nil, {}, {}
  while true do
    local h = f:read(8)
    if not h or #h < 8 then break end
    local id, size = string.unpack("<c4I4", h)
    local body_start = f:seek()

    if id == "fmt " then
      local d = f:read(size)
      rate = string.unpack("<I4", d, 5)            -- dopo formato(2) e canali(2)
    elseif id == "cue " then
      local d = f:read(size)
      local n = string.unpack("<I4", d, 1)
      for i = 0, n - 1 do
        local base = 5 + 24 * i                    -- ogni punto occupa 24 byte
        local cue_id = string.unpack("<I4", d, base)
        local sample = string.unpack("<I4", d, base + 20)
        points[#points + 1] = { id = cue_id, sample = sample }
      end
    elseif id == "LIST" then
      local d = f:read(size)
      if d:sub(1, 4) == "adtl" then                -- elenco delle etichette
        local j = 5
        while j + 8 <= #d + 1 do
          local cid = d:sub(j, j + 3)
          local s = string.unpack("<I4", d, j + 4)
          local body = d:sub(j + 8, j + 7 + s)
          if cid == "labl" or cid == "note" then
            local cue_id = string.unpack("<I4", body, 1)
            labels[cue_id] = body:sub(5):gsub("%z.*$", "")
          end
          j = j + 8 + s + (s & 1)                  -- i chunk sono allineati a 2 byte
        end
      end
    end
    -- salta al chunk successivo (anche 'data': non serve leggerlo)
    f:seek("set", body_start + size + (size & 1))
  end
  f:close()

  if not rate then return nil, "Chunk 'fmt ' non trovato." end
  local cues = {}
  for _, p in ipairs(points) do
    cues[#cues + 1] = { time = p.sample / rate, text = labels[p.id] or "" }
  end
  table.sort(cues, function(a, b) return a.time < b.time end)
  return cues
end
-- ========================= fine lettore (puro Lua) ==========================

if not reaper then return { read_wav_cues = read_wav_cues } end

local function log(s) reaper.ShowConsoleMsg(tostring(s) .. "\n") end

local item = reaper.GetSelectedMediaItem(0, 0)
if not item then reaper.MB("Seleziona un item audio.", "Cue dal WAV", 0) return end
local take = reaper.GetActiveTake(item)
if not take then reaper.MB("L'item non ha take.", "Cue dal WAV", 0) return end

local path = reaper.GetMediaSourceFileName(reaper.GetMediaItemTake_Source(take), "")
local cues, err = read_wav_cues(path)
if not cues then reaper.MB(err, "Cue dal WAV", 0) return end

log(string.format("%d cue in %s", #cues, path:match("[^/\\]+$") or path))
for i, c in ipairs(cues) do
  log(string.format("%2d  %9.3f s  (%d caratteri)  %s", i, c.time, #c.text, c.text:sub(1, 60)))
end
if #cues == 0 then return end

if reaper.GetNumTakeMarkers(take) > 0 then
  log("Il take ha gia' dei take marker: non copio niente.")
  return
end
if reaper.MB("Copiare i cue come take marker?", "Cue dal WAV", 4) == 6 then
  reaper.Undo_BeginBlock()
  for _, c in ipairs(cues) do
    reaper.SetTakeMarker(take, -1, (c.text:gsub("%s+", " ")), c.time)
  end
  reaper.Undo_EndBlock("Cue dal WAV come take marker", -1)
  reaper.UpdateArrange()
  log("Copiati " .. #cues .. " cue come take marker.")
end
