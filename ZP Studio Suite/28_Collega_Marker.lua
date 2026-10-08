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

-- Cosa fare di un item, prima di aprire qualsiasi file.
-- existing: take marker gia' presenti; has_srt: l'SRT da usare esiste; quiet: lanciato dalla strada 29.
-- Dalla strada non si apre mai il Finder: un item con marker ma senza SRT accanto (tipico glue:
-- file nuovo, marker portati dietro) resta com'e'; uno senza ne' marker ne' SRT viene elencato.
local function decide(existing, has_srt, skip_existing, quiet)
  if existing > 0 and skip_existing then return "skip_linked" end
  if not has_srt then
    if not quiet then return "ask_file" end
    return existing > 0 and "skip_linked" or "missing"
  end
  return existing > 0 and "ask_replace" or "link"
end

-- "a.wav, b.wav e altri 3": ogni file una volta sola
local function name_list(names, max)
  local out, seen = {}, {}
  for _, n in ipairs(names) do
    if not seen[n] then seen[n] = true; out[#out + 1] = n end
  end
  local shown = {}
  for i = 1, math.min(#out, max or 3) do shown[i] = out[i] end
  local s = table.concat(shown, ", ")
  if #out > #shown then s = s .. string.format(" e altri %d", #out - #shown) end
  return s
end

local function main()
  local count = reaper.CountSelectedMediaItems(0)
  if count == 0 then show("Seleziona uno o più item audio.") return end
  local quiet = _G.ZP_COLLEGA_QUIET and true or false

  -- Prepara tutto prima di modificare il progetto: annullare una scelta non lascia
  -- metà importazione applicata.
  local plans, skipped = {}, 0
  local srt_cache = {}
  local missing, linked_no_srt, invalid = {}, {}, {}
  local already = 0          -- item gia' abbinati lasciati com'erano
  local to_replace = {}      -- dalla strada con SRT esterno: una domanda sola per tutti
  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = item and reaper.GetActiveTake(item)
    local source = take and reaper.GetMediaItemTake_Source(take)
    local source_path = source and reaper.GetMediaSourceFileName(source, "") or ""
    if not take or source_path == "" then
      skipped = skipped + 1
    else
      local file_name = source_path:match("[^/\\]+$") or source_path
      -- _G.ZP_COLLEGA_SRT_PATH (dalla strada, "SRT esterno o tradotto"): stesso SRT per tutti
      -- gli item selezionati, anche se accanto al file c'e' gia' l'SRT di whisper.
      local path = _G.ZP_COLLEGA_SRT_PATH or sidecar(source_path)
      local existing = reaper.GetNumTakeMarkers(take)
      local action = decide(existing, srt_cache[path] ~= nil or exists(path), _G.ZP_COLLEGA_SKIP_EXISTING, quiet)
      if action == "ask_file" then
        local ok, chosen = reaper.GetUserFileNameForRead(path, "Scegli l'SRT per " .. file_name, "srt")
        if not ok then return end
        path = chosen
        action = existing > 0 and "ask_replace" or "link"
      end
      local cached = srt_cache[path]
      if not cached and (action == "link" or action == "ask_replace") then
        local data = read_file(path)
        local cues = data and parse_srt(data) or {}
        if #cues == 0 then
          if not quiet then
            show("Non trovo cue SRT validi nel file:\n" .. path .. "\n\nNessuna modifica è stata applicata.")
            return
          end
          invalid[#invalid + 1] = file_name
          action = "invalid"
        else
          cached = { path = path, cues = cues }
          srt_cache[path] = cached
        end
      end
      local replace = false
      if action == "missing" then
        missing[#missing + 1] = file_name; skipped = skipped + 1
      elseif action == "invalid" then
        skipped = skipped + 1
      elseif action == "skip_linked" then
        if _G.ZP_COLLEGA_SKIP_EXISTING then already = already + 1
        else linked_no_srt[#linked_no_srt + 1] = file_name end
        skipped = skipped + 1   -- la strada non riapre item gia' collegati: per rifarli c'e' Ritrascrivi
      elseif action == "ask_replace" and quiet then
        to_replace[#to_replace + 1] = { take = take, cues = cached.cues, replace = true, path = path }
      elseif action == "ask_replace" then
        local answer = reaper.ShowMessageBox(
          string.format("L'item selezionato contiene già %d take marker.\n\nSì: sostituiscili con i cue SRT.\nNo: salta questo item.\nAnnulla: interrompi senza modifiche.", existing),
          "ZP Collega marker", 3)
        if answer == 2 then return end
        if answer == 6 then replace = true else skipped = skipped + 1 end
      end
      if action == "link" or replace then
        plans[#plans + 1] = { take = take, cues = cached.cues, replace = replace, path = path }
      end
    end
  end

  if #to_replace > 0 then
    local answer = reaper.ShowMessageBox(string.format(
      "%d item selezionati hanno già i loro marker.\n\nSì: sostituiscili tutti con l'SRT scelto.\nNo: lasciali com'erano.\nAnnulla: interrompi senza modifiche.",
      #to_replace), "ZP Collega marker", 3)
    if answer == 2 then return "Abbina annullato: nessuna modifica." end
    if answer == 6 then
      for _, plan in ipairs(to_replace) do plans[#plans + 1] = plan end
    else
      already = already + #to_replace; skipped = skipped + #to_replace
    end
  end

  -- Perche' qualcosa e' stato saltato: in una riga, la strada 29 mostra solo la prima.
  local why = {}
  if already > 0 then why[#why + 1] = string.format("%d gia' abbinati, lasciati com'erano (per rifarli: Ritrascrivi)", already) end
  if #missing > 0 then why[#why + 1] = "senza SRT accanto (Trascrivi): " .. name_list(missing) end
  if #linked_no_srt > 0 then
    why[#why + 1] = "gia' con marker ma senza SRT accanto, lasciati com'erano (glue? Ritrascrivi): " .. name_list(linked_no_srt)
  end
  if #invalid > 0 then why[#why + 1] = "SRT senza cue validi: " .. name_list(invalid) end
  local why_s = #why > 0 and (" - " .. table.concat(why, "; ")) or ""

  if #plans == 0 then return report("Nessun item pronto da collegare. Item saltati: " .. skipped .. why_s .. ".") end
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
  if quiet then
    return string.format("Abbinati %d item (%d cue), saltati %d%s.", applied, cue_count, skipped, why_s)
  end
  return report(string.format("Collegamento completato.\n\nItem aggiornati: %d\nCue importati: %d\nItem saltati: %d%s\n\nI marker sono riferiti al tempo sorgente e seguono l'audio quando sposti o tagli l'item.", applied, cue_count, skipped, why_s))
end

-- Espone il parser per prove Lua fuori da REAPER.
if not reaper then return { parse_time = parse_time, parse_srt = parse_srt, sidecar = sidecar, decide = decide, name_list = name_list } end
return main()
