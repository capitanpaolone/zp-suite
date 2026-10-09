-- @noindex

-- ZP Studio Suite for REAPER
-- 31 SRT dall'audio: i take marker degli item selezionati diventano un SRT,
-- con lo stesso nome del file sorgente, nella cartella che scegli (non tra i media).
--
-- Serve dopo il montaggio: le battute corrette in REAPER, o un file nato da un Glue
-- (che tiene solo i marker della parte usata), tornano a essere un SRT da consegnare
-- al fonico o da riusare. I tempi sono quelli del file (tempo sorgente), come
-- l'SRT di whisper: ricollegandolo con 29 "Abbina da > SRT esterno" torna identico.
-- Finestra (non messaggi bloccanti): mostra dal vivo gli item selezionati e quante
-- battute daranno, la cartella di destinazione (ricordata) e cosa fare se l'SRT c'e'
-- gia'. Scrivi SRT scrive; il risultato resta nella finestra. La chiudi tu.
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
local function file_base(p) return (base(p):match("[^/\\]+$") or base(p)) end
local sep = package.config:sub(1, 1)
local here = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or ".")
local EXT, DIR_KEY, MODE_KEY = "ZP_STUDIO_SUITE", "SRT31_dir", "SRT31_existing"

local ok_ui, UI = pcall(dofile, here .. sep .. "ZP_UI.lua")
if not ok_ui then
  reaper.ShowMessageBox("Non trovo ZP_UI.lua accanto allo script.", TITLE, 0)
  return
end

local function project_dir()
  local _, proj = reaper.EnumProjects(-1, "")
  local d = (proj or ""):match("^(.*)[/\\][^/\\]+$")
  return (d and d ~= "") and d or reaper.GetResourcePath()
end

-- Selettore di cartelle (js_ReaScriptAPI) o, senza, il dialogo "salva" (si tiene la cartella).
local function choose_dir(default)
  if reaper.JS_Dialog_BrowseForFolder then
    local rv, folder = reaper.JS_Dialog_BrowseForFolder("Dove salvo gli SRT?", default)
    if rv == 1 and folder and folder ~= "" then return folder end
    return nil
  end
  if reaper.GetUserFileNameForWrite then
    local ok, f = reaper.GetUserFileNameForWrite(default .. sep .. "SRT.srt", "Dove salvo gli SRT? (conta la cartella)", "srt")
    if ok and f ~= "" then return f:match("^(.*)[/\\][^/\\]+$") end
    return nil
  end
  local ok, f = reaper.GetUserFileNameForRead(default, "Scegli un file nella cartella dove salvare gli SRT", "")
  if ok and f ~= "" then return f:match("^(.*)[/\\][^/\\]+$") end
  return nil
end

local out_dir = reaper.GetExtState(EXT, DIR_KEY)
if out_dir == "" then out_dir = project_dir() end
local replace = reaper.GetExtState(EXT, MODE_KEY) ~= "new"   -- default: sostituisci (con .bak)
local result = nil       -- righe del risultato dell'ultima scrittura
local last_down = false

-- Item selezionati raggruppati per file sorgente (piu' pezzi dello stesso file = un SRT)
local function collect()
  local by_source, order, no_markers = {}, {}, 0
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local take = reaper.GetActiveTake(reaper.GetSelectedMediaItem(0, i))
    local src = take and reaper.GetMediaItemTake_Source(take)
    local path = src and reaper.GetMediaSourceFileName(src, "") or ""
    if path ~= "" and reaper.GetNumTakeMarkers(take) > 0 then
      local entry = by_source[path]
      if not entry then
        entry = { path = path, markers = {}, len = (reaper.GetMediaSourceLength(src)) }
        by_source[path] = entry
        order[#order + 1] = entry
      end
      for j = 0, reaper.GetNumTakeMarkers(take) - 1 do
        local pos, name = reaper.GetTakeMarker(take, j)
        entry.markers[#entry.markers + 1] = { src = pos, text = name }
      end
    elseif path ~= "" then
      no_markers = no_markers + 1
    end
  end
  for _, e in ipairs(order) do e.cues = M.cues(e.markers, e.len) end
  return order, no_markers
end

local function write_all(order)
  reaper.RecursiveCreateDirectory(out_dir, 0)
  local written, lines, out = 0, 0, {}
  for _, e in ipairs(order) do
    local target = out_dir .. sep .. file_base(e.path) .. ".srt"
    local note = ""
    if exists(target) then
      if replace then
        os.remove(target .. ".bak")
        os.rename(target, target .. ".bak")
        note = "  (sostituito, il vecchio e' .bak)"
      else
        target = out_dir .. sep .. file_base(e.path) .. " (marker).srt"
        note = "  (nuovo file accanto)"
      end
    end
    local f = io.open(target, "wb")
    if f then
      f:write(M.srt(e.cues)); f:close()
      written, lines = written + 1, lines + #e.cues
      out[#out + 1] = "Scritto: " .. (target:match("[^/\\]+$") or target) .. note
    else
      out[#out + 1] = "NON scritto: " .. target
    end
  end
  table.insert(out, 1, string.format("SRT scritti: %d, battute: %d, in %s", written, lines, out_dir))
  if reaper.osara_outputMessage then reaper.osara_outputMessage(out[1]) end
  return out
end

local function text_line(s, x, y, size, color, bold, maxw)
  gfx.setfont(1, "Arial", size, bold and string.byte("b") or nil)
  UI.set_color(color)
  gfx.x, gfx.y = x, y
  gfx.drawstr(UI.fit_text(s, maxw or (gfx.w - x - 22)))
end

gfx.init("ZP Studio Suite - SRT dall'audio", 640, 540, 0)

local last_sig = ""
local function loop()
  local ch = gfx.getchar()
  if ch < 0 or ch == 27 then gfx.quit() return end
  local down = (gfx.mouse_cap & 1) == 1
  local clicked = down and not last_down
  last_down = down

  local order, no_markers = collect()
  -- se cambia la selezione, il risultato vecchio non vale piu'
  local sig = tostring(#order) .. ":" .. tostring(no_markers) .. ":" .. (order[1] and order[1].path or "")
  if sig ~= last_sig then
    if last_sig ~= "" then result = nil end
    last_sig = sig
    if reaper.osara_outputMessage then
      reaper.osara_outputMessage(#order > 0 and string.format("%d file con battute pronti per l'SRT.", #order)
        or "Seleziona gli item audio con i marker delle battute.")
    end
  end

  UI.fill_background()
  UI.draw_header({ title = "SRT dall'audio", description = "I marker delle battute degli item selezionati diventano un SRT." })
  UI.draw_help_button({ x = gfx.w - 54, y = 16, w = 34, h = 28 }, clicked, "tool-31")

  local x, y = 22, 92
  text_line("Item selezionati", x, y, 15, UI.colors.title, true)
  y = y + 26
  if #order == 0 then
    text_line("Nessun item audio con marker delle battute.", x, y, 15, UI.colors.text)
    y = y + 22
    text_line("Seleziona in timeline gli item audio: i marker li mette 29 ZP Trascrizione (Abbina da...).", x, y, 14, UI.colors.muted)
    y = y + 22
  else
    for k, e in ipairs(order) do
      if k > 6 then text_line(string.format("... e altri %d file", #order - 6), x, y, 14, UI.colors.muted); y = y + 22; break end
      text_line(string.format("%s  -  %d battute", file_base(e.path), #e.cues), x, y, 15, UI.colors.text)
      y = y + 22
    end
  end
  if no_markers > 0 then
    text_line(string.format("%d item selezionati senza marker: saltati.", no_markers), x, y, 14, UI.colors.muted)
    y = y + 22
  end

  y = math.max(y + 14, 270)
  text_line("Cartella", x, y, 15, UI.colors.title, true)
  if UI.draw_button({ x = gfx.w - 22 - 180, y = y - 4, w = 180, h = 30 }, "Cambia cartella...", false, true, clicked, "play_select") then
    local picked = choose_dir(out_dir)
    if picked then out_dir = picked; reaper.SetExtState(EXT, DIR_KEY, out_dir, true); result = nil end
  end
  y = y + 26
  text_line(out_dir, x, y, 14, UI.colors.text, false, gfx.w - 44)

  y = y + 36
  text_line("Se l'SRT c'e' gia'", x, y, 15, UI.colors.title, true)
  local bx = x + 170
  if UI.draw_button({ x = bx, y = y - 4, w = 170, h = 30 }, "Sostituisci (.bak)", replace, true, clicked, "tab") then
    replace = true; reaper.SetExtState(EXT, MODE_KEY, "replace", true)
  end
  if UI.draw_button({ x = bx + 176, y = y - 4, w = 170, h = 30 }, "Nuovo file (marker)", not replace, true, clicked, "tab") then
    replace = false; reaper.SetExtState(EXT, MODE_KEY, "new", true)
  end

  y = y + 44
  if result then
    for k, l in ipairs(result) do
      text_line(l, x, y, k == 1 and 15 or 14, k == 1 and UI.colors.credit or UI.colors.text, k == 1, gfx.w - 44)
      y = y + 22
    end
  end

  local by = gfx.h - 22 - 36
  if UI.draw_button({ x = gfx.w - 22 - 110, y = by, w = 110, h = 36 }, "Chiudi", false, true, clicked, "tab") then
    gfx.quit()
    return
  end
  if UI.draw_button({ x = gfx.w - 22 - 110 - 12 - 160, y = by, w = 160, h = 36 }, "Scrivi SRT", false, #order > 0, clicked, "save") then
    result = write_all(order)
  end

  gfx.update()
  reaper.defer(loop)
end

loop()
