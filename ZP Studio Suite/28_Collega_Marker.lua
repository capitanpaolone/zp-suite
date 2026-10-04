-- @noindex

-- ZP Collega marker: importa i cue SRT come take marker negli item selezionati.
-- Parte interna della strada 29 ZP Trascrizione (tappa 2, Abbina da...); si puo' ancora
-- lanciare da solo, ma non ha piu' un pulsante proprio.
-- I timestamp SRT sono riferiti all'intero file sorgente e restano tali nei take marker.

local function parse_time(value)
  if type(value) ~= "string" then return nil end
  local h, m, s, frac = value:match("^(%d+):(%d%d):(%d%d)[,.](%d+)$")
  if not h or #frac > 3 or tonumber(m) > 59 or tonumber(s) > 59 then return nil end
  local ms = tonumber(frac) / (10 ^ #frac)
  return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + ms
end

local function parse_srt(data)
  if type(data) ~= "string" then return {} end
  data = data:gsub("^\239\187\191", ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  local cues, start, lines = {}, nil, {}
  local function finish()
    if start and #lines > 0 then
      local text = table.concat(lines, " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
      if text ~= "" then cues[#cues + 1] = { start = start, text = text } end
    end
    start, lines = nil, {}
  end
  for line in (data .. "\n"):gmatch("(.-)\n") do
    local a, b = line:match("^%s*(%S+)%s+%-%->%s+(%S+)")
    if a and b then
      finish()
      start = parse_time(a)
    elseif line:match("^%s*$") then
      finish()
    elseif start then
      lines[#lines + 1] = line
    end
  end
  finish()
  table.sort(cues, function(a, b) return a.start < b.start end)
  return cues
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function exists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

local function sidecar(path)
  return (path:gsub("%.[^./\\]+$", "")) .. ".srt"
end

local function show(message, title)
  reaper.ShowMessageBox(message, title or "ZP Collega marker", 0)
end

-- Lanciato dalla finestra ZP Trascrizione (_G.ZP_COLLEGA_QUIET): niente messaggio
-- finale, il riepilogo viene restituito e la finestra lo mostra nella sua strada.
local function report(message)
  if _G.ZP_COLLEGA_QUIET then return message end
  show(message)
end

local function main()
  local count = reaper.CountSelectedMediaItems(0)
  if count == 0 then show("Seleziona uno o più item audio.") return end

  -- Prepara tutto prima di modificare il progetto: annullare una scelta non lascia
  -- metà importazione applicata.
  local plans, skipped = {}, 0
  local srt_cache = {}
  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = item and reaper.GetActiveTake(item)
    local source = take and reaper.GetMediaItemTake_Source(take)
    local source_path = source and reaper.GetMediaSourceFileName(source, "") or ""
    if not take or source_path == "" then
      skipped = skipped + 1
    else
      -- _G.ZP_COLLEGA_SRT_PATH (dalla strada, "SRT esterno o tradotto"): stesso SRT per tutti
      -- gli item selezionati, anche se accanto al file c'e' gia' l'SRT di whisper.
      local path = _G.ZP_COLLEGA_SRT_PATH or
        (srt_cache[source_path] and srt_cache[source_path].path or sidecar(source_path))
      if not exists(path) then
        local ok, chosen = reaper.GetUserFileNameForRead(path, "Scegli l'SRT per " .. (source_path:match("[^/\\]+$") or "item"), "srt")
        if not ok then return end
        path = chosen
      end
      local cached = srt_cache[path]
      if not cached then
        local data = read_file(path)
        local cues = data and parse_srt(data) or {}
        if #cues == 0 then
          show("Non trovo cue SRT validi nel file:\n" .. path .. "\n\nNessuna modifica è stata applicata.")
          return
        end
        cached = { path = path, cues = cues }
        srt_cache[path] = cached
      end
      local existing = reaper.GetNumTakeMarkers(take)
      local replace = false
      if existing > 0 and _G.ZP_COLLEGA_SKIP_EXISTING then
        skipped = skipped + 1   -- la strada intera non riapre item gia' collegati
      elseif existing > 0 then
        local answer = reaper.ShowMessageBox(
          string.format("L'item selezionato contiene già %d take marker.\n\nSì: sostituiscili con i cue SRT.\nNo: salta questo item.\nAnnulla: interrompi senza modifiche.", existing),
          "ZP Collega marker", 3)
        if answer == 2 then return end
        if answer == 6 then replace = true else skipped = skipped + 1 end
      end
      if existing == 0 or replace then
        plans[#plans + 1] = { take = take, cues = cached.cues, replace = replace, path = path }
      end
    end
  end

  if #plans == 0 then return report("Nessun item pronto da collegare. Item saltati: " .. skipped .. ".") end
  local applied, cue_count = 0, 0
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  for _, plan in ipairs(plans) do
    if plan.replace then
      for j = reaper.GetNumTakeMarkers(plan.take) - 1, 0, -1 do
        reaper.DeleteTakeMarker(plan.take, j)
      end
    end
    for _, cue in ipairs(plan.cues) do
      reaper.SetTakeMarker(plan.take, -1, cue.text, cue.start)
      cue_count = cue_count + 1
    end
    applied = applied + 1
  end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("ZP: collega cue SRT come take marker", -1)
  return report(string.format("Collegamento completato.\n\nItem aggiornati: %d\nCue importati: %d\nItem saltati: %d\n\nI marker sono riferiti al tempo sorgente e seguono l'audio quando sposti o tagli l'item.", applied, cue_count, skipped))
end

-- Espone il parser per prove Lua fuori da REAPER.
if not reaper then return { parse_time = parse_time, parse_srt = parse_srt, sidecar = sidecar } end
return main()
