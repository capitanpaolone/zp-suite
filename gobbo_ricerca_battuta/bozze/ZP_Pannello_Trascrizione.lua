-- ZP Pannello Trascrizione (SCHELETRO di collaudo, non ancora nella Suite)
--
-- Una finestra sola che raccoglie i passi del flusso podcast:
--   Trascrivi      -> manda a ZP Speech i WAV degli item selezionati (salta chi ha gia' l'SRT)
--   Collega marker -> importa gli SRT come take marker (28_Collega_Marker.lua, invariato)
--   Sincronizza    -> ricostruisce/aggancia gli item testo del gobbo (ZP_sincronizza_aggancio.lua)
--   Autofollow     -> dopo 10 s senza modifiche al progetto lancia Sincronizza da solo
--
-- I tre script esistenti NON vengono riscritti: il pannello li lancia con dofile.
-- Per ora cerca i file nella cartella dello script e in "../ZP Studio Suite".

local sep = package.config:sub(1, 1)
local here = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or ".")

local function exists(p) local f = io.open(p, "rb"); if f then f:close() return true end return false end
local function read_file(p) local f = io.open(p, "rb"); if not f then return nil end local d = f:read("*a"); f:close(); return d end
local function find_file(name)
  for _, dir in ipairs({
    here,
    here .. sep .. ".." .. sep .. "ZP Studio Suite",
    here .. sep .. ".." .. sep .. ".." .. sep .. "ZP Studio Suite",
  }) do
    local p = dir .. sep .. name
    if exists(p) then return p end
  end
end
local function shell_quote(v) return "'" .. tostring(v):gsub("'", "'\\''") .. "'" end

local ui_path = find_file("ZP_UI.lua")
if not ui_path then
  reaper.ShowMessageBox("Non trovo ZP_UI.lua accanto allo script.", "ZP Pannello", 0)
  return
end
local UI = dofile(ui_path)

local EXT = "ZP_STUDIO_SUITE"
local autofollow = reaper.GetExtState(EXT, "PanelAutofollow") == "1"
local AUTO_DELAY = 10.0

local status = "Seleziona gli item audio da lavorare."
local rows, rows_t = {}, -1
local queue, running = {}, nil
local last_down = false
local pending, last_change, last_count = false, 0, reaper.GetProjectStateChangeCount(0)

---------------------------------------------------------------------------
-- Stato degli item selezionati (aggiornato ogni ~0.7 s, non a ogni frame)
---------------------------------------------------------------------------
local function sidecar(p) return (p:gsub("%.[^./\\]+$", "")) .. ".srt" end

local function refresh_rows()
  rows = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local take = it and reaper.GetActiveTake(it)
    local src = take and reaper.GetMediaItemTake_Source(take)
    local path = src and reaper.GetMediaSourceFileName(src, "") or ""
    if path ~= "" then
      rows[#rows + 1] = {
        name = path:match("[^/\\]+$") or path, path = path,
        srt = exists(sidecar(path)), markers = reaper.GetNumTakeMarkers(take),
      }
    end
  end
  rows_t = os.clock()
end

---------------------------------------------------------------------------
-- Lancio degli script esistenti
---------------------------------------------------------------------------
local function run_script(name, quiet)
  local p = find_file(name)
  if not p then status = "Non trovo " .. name; return nil end
  _G.ZP_SYNC_QUIET = quiet or nil
  local ok, res = pcall(dofile, p)
  _G.ZP_SYNC_QUIET = nil
  if not ok then status = "Errore in " .. name .. ": " .. tostring(res); return nil end
  return res
end

local function do_sync(quiet)
  local msg = run_script("ZP_sincronizza_aggancio.lua", quiet)
  if msg then status = "Sincronizza: " .. tostring(msg):gsub("\n", " ") end
  last_count = reaper.GetProjectStateChangeCount(0)   -- i cambi fatti dal sync non contano per l'autofollow
  pending = false
end

---------------------------------------------------------------------------
-- Trascrivi: coda sequenziale su ZP Speech (come 26_SRT_Tools.lua, ma per item selezionati)
---------------------------------------------------------------------------
local function speech_cli()
  local home = os.getenv("HOME") or ""
  return home .. "/Library/Application Support/ZP/runtimes/speech/bin/zp-speech", home
end

local function start_next()
  local job = table.remove(queue, 1)
  if not job then
    running = nil
    status = "Trascrizione finita. Ora puoi premere Collega marker."
    return
  end
  local cli, home = speech_cli()
  local tmp = os.tmpname(); os.remove(tmp)
  local st, lg = tmp .. ".status", tmp .. ".log"
  local out = sidecar(job)
  local task = shell_quote(cli) .. " request " .. shell_quote(job) .. " --format srt --output " .. shell_quote(out) ..
    " > " .. shell_quote(lg) .. " 2>&1; printf '%s\\n' \"$?\" > " .. shell_quote(st)
  os.execute("(" .. task .. ") </dev/null >/dev/null 2>&1 &")
  running = { job = job, out = out, st = st, lg = lg }
  status = string.format("Trascrivo %s (restano %d in coda)...", job:match("[^/\\]+$") or job, #queue)
end

local function poll_job()
  if not running then return end
  local code = read_file(running.st)
  if not code then return end
  os.remove(running.st)
  if tonumber(code:match("%d+")) ~= 0 then
    local detail = read_file(running.lg) or ""
    reaper.ShowConsoleMsg("[ZP Speech] errore su " .. running.job .. "\n" .. detail:sub(-1200) .. "\n")
    status = "Trascrizione NON riuscita: " .. (running.job:match("[^/\\]+$") or "") .. " (dettagli nella console)"
    queue = {}; running = nil
    return
  end
  os.remove(running.lg)
  start_next()
end

local function do_transcribe()
  if running then status = "Una trascrizione e' gia' in corso."; return end
  local osname = reaper.GetOS()
  if not (osname:match("OSX") or osname:match("macOS")) then
    reaper.ShowMessageBox("La trascrizione automatica e' configurata solo su macOS.\nSu Windows/Linux: crea l'SRT con il tuo whisper (stesso nome del WAV, accanto al file) e usa Collega marker.", "ZP Pannello", 0)
    return
  end
  local cli = speech_cli()
  if not exists(cli) then
    reaper.ShowMessageBox("ZP Speech non e' installato.\nAvvia prima install_speech_service.sh da ZP Tools, oppure crea l'SRT con il tuo whisper e usa Collega marker.", "ZP Pannello", 0)
    return
  end
  refresh_rows()
  local seen, skipped = {}, 0
  for _, r in ipairs(rows) do
    if not seen[r.path] then
      seen[r.path] = true
      if r.srt then skipped = skipped + 1
      elseif r.path:lower():match("%.wav$") then queue[#queue + 1] = r.path end
    end
  end
  if #queue == 0 then
    status = string.format("Niente da trascrivere (%d con SRT gia' presente, gli altri non sono WAV).", skipped)
    return
  end
  -- il servizio va avviato se non gira (come in 26_SRT_Tools.lua)
  local p = io.popen("/usr/bin/id -u 2>/dev/null", "r")
  local uid = p and p:read("*l"); if p then p:close() end
  if uid and uid:match("^%d+$") then
    local home = select(2, speech_cli())
    local plist = home .. "/Library/LaunchAgents/com.zp.speech-service.plist"
    os.execute("/bin/launchctl kickstart gui/" .. uid .. "/com.zp.speech-service >/dev/null 2>&1 || /bin/launchctl bootstrap 'gui/" ..
      uid .. "' " .. shell_quote(plist) .. " >/dev/null 2>&1")
  end
  status = string.format("In coda %d file (%d saltati: SRT gia' presente).", #queue, skipped)
  start_next()
end

---------------------------------------------------------------------------
-- Finestra
---------------------------------------------------------------------------
gfx.init("ZP Trascrizione", 600, 430, 0)

local function loop()
  if gfx.getchar() < 0 then gfx.quit() return end
  local now = os.clock()
  local down = (gfx.mouse_cap & 1) == 1
  local clicked = down and not last_down
  last_down = down

  if now - rows_t > 0.7 then refresh_rows() end
  poll_job()

  -- autofollow: aspetta 10 s di quiete, poi sincronizza (i propri cambi sono esclusi)
  if autofollow then
    local c = reaper.GetProjectStateChangeCount(0)
    if c ~= last_count then last_count = c; last_change = now; pending = true end
    if pending and now - last_change >= AUTO_DELAY then do_sync(true) end
  end

  UI.fill_background()
  UI.draw_header({ title = "Trascrizione e gobbo", credit = "ZP Studio Suite - scheletro di collaudo",
    description = "Trascrivi, collega gli SRT come marker, sincronizza il gobbo." })
  UI.draw_help_button({ x = gfx.w - 54, y = 16, w = 34, h = 28 }, clicked, nil)

  local pad, gap = 22, 10
  local bw = math.floor((gfx.w - pad * 2 - gap * 2) / 3)
  if UI.draw_button({ x = pad, y = 84, w = bw, h = 40 }, "1  Trascrivi", running ~= nil, running == nil, clicked, "play_now") then do_transcribe() end
  if UI.draw_button({ x = pad + bw + gap, y = 84, w = bw, h = 40 }, "2  Collega marker", false, true, clicked, "play_select") then
    run_script("28_Collega_Marker.lua"); refresh_rows()
  end
  if UI.draw_button({ x = pad + (bw + gap) * 2, y = 84, w = bw, h = 40 }, "3  Sincronizza", false, true, clicked, "save") then do_sync(false) end

  local af = autofollow and "Autofollow: ACCESO (10 s)" or "Autofollow: spento"
  if UI.draw_button({ x = pad, y = 134, w = bw + 40, h = 28 }, af, autofollow, true, clicked, "tab") then
    autofollow = not autofollow
    reaper.SetExtState(EXT, "PanelAutofollow", autofollow and "1" or "0", true)
    last_count = reaper.GetProjectStateChangeCount(0); pending = false
  end
  UI.draw_button({ x = pad + bw + 50, y = 134, w = bw - 40, h = 28 }, "Impostazioni", false, false, false, "tab")

  -- elenco item selezionati
  gfx.setfont(1, "Arial", 14)
  UI.set_color(UI.colors.muted)
  gfx.x, gfx.y = pad, 176
  gfx.drawstr(string.format("Item selezionati: %d", #rows))
  local y = 198
  for i, r in ipairs(rows) do
    if y > gfx.h - 70 then
      UI.set_color(UI.colors.muted); gfx.x, gfx.y = pad, y
      gfx.drawstr(string.format("... e altri %d", #rows - i + 1)); break
    end
    UI.set_color(UI.colors.text)
    gfx.x, gfx.y = pad, y
    gfx.drawstr(UI.fit_text(r.name, gfx.w - pad * 2 - 190))
    UI.set_color(r.srt and UI.colors.credit or UI.colors.disabled)
    gfx.x = gfx.w - pad - 180; gfx.drawstr(r.srt and "SRT presente" or "SRT mancante")
    UI.set_color(r.markers > 0 and UI.colors.credit or UI.colors.disabled)
    gfx.x = gfx.w - pad - 80; gfx.drawstr(string.format("marker %d", r.markers))
    y = y + 20
  end

  -- stato
  UI.set_color(UI.colors.title)
  gfx.setfont(1, "Arial", 14)
  gfx.x, gfx.y = pad, gfx.h - 40
  gfx.drawstr(UI.fit_text(status, gfx.w - pad * 2))

  gfx.update()
  reaper.defer(loop)
end

loop()
