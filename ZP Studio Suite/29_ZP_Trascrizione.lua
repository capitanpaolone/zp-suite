-- @noindex

-- ZP Studio Suite for REAPER
-- 29 ZP Trascrizione: la strada dall'audio al Gobbo
--
-- Una finestra sola che mostra il flusso come una strada a quattro tappe, sugli item
-- audio selezionati. Ogni tappa dice a che punto sei e ha il suo pulsante; la tappa
-- da fare adesso e' evidenziata. "Percorri la strada" fa in ordine quello che manca.
--
--   1 Trascrivi       whisper (ZP Speech) crea l'SRT accanto al WAV, stesso nome
--   2 Abbina da...    sorgente a scelta -> take marker sull'item: SRT accanto al file o SRT
--                     esterno/tradotto (28_Collega_Marker.lua), marker di progetto (14);
--                     in piu' "cue del WAV -> marker in timeline" (azione nativa 40692)
--   3 Porta nel gobbo i marker diventano item testo magnetici su "Rythmo Band Testi <voce>"
--                     (ZP_sincronizza_aggancio.lua). Parte da sola dopo Abbina.
--   4 Segui i tagli   dopo 10 s senza modifiche al progetto i testi seguono l'audio
--
-- Un file gia' in timeline con i suoi marker salta direttamente alla tappa 3.
-- Ritrascrivi...: per un file che ha gia' marker o SRT ma va riletto da capo (es. dopo un
-- glue, o se i tempi sono cambiati): toglie i take marker degli item selezionati, mette da
-- parte l'SRT vecchio e lo tratta come un file nuovo (trascrivi, abbina, gobbo).
-- Gli script delle tappe non vengono riscritti: la finestra li lancia con dofile.

local M = {}

---------------------------------------------------------------------------
-- LOGICA PURA (collaudabile con lua5.4 fuori da REAPER)
---------------------------------------------------------------------------

-- rows: { {srt=bool, markers=n, texts=n, wav=bool}, ... } degli item selezionati
-- Restituisce le quattro tappe {done, info} e l'indice della prossima da fare.
function M.road(rows, follow)
  local n, srt, linked, shown = #rows, 0, 0, 0
  for _, r in ipairs(rows) do
    if r.srt or r.markers > 0 then srt = srt + 1 end
    if r.markers > 0 then linked = linked + 1 end
    if r.markers > 0 and r.texts > 0 then shown = shown + 1 end
  end
  local steps = {
    { done = n > 0 and srt == n,    info = string.format("%d di %d con SRT", srt, n) },
    { done = n > 0 and linked == n, info = string.format("%d di %d con marker", linked, n) },
    { done = linked > 0 and shown == linked, info = string.format("%d di %d con testi in timeline", shown, linked) },
    { done = follow, info = follow and "acceso: i testi seguono tagli e spostamenti" or "spento" },
  }
  local next_step
  if n > 0 then
    for i, s in ipairs(steps) do
      if not s.done then next_step = i; break end
    end
  end
  return steps, next_step
end

-- Item da mandare a whisper: WAV senza SRT e senza marker, un file una volta sola.
function M.to_transcribe(rows)
  local queue, seen = {}, {}
  for _, r in ipairs(rows) do
    if r.wav and not r.srt and r.markers == 0 and not seen[r.path] then
      seen[r.path] = true
      queue[#queue + 1] = r.path
    end
  end
  return queue
end

-- Item da RIleggere da capo: tutti i WAV selezionati, anche con SRT o marker, una volta sola.
-- Restituisce i percorsi e quanti hanno marker / SRT (per la domanda di conferma).
function M.to_retranscribe(rows)
  local queue, seen, with_markers, with_srt = {}, {}, 0, 0
  for _, r in ipairs(rows) do
    if r.wav then
      if r.markers > 0 then with_markers = with_markers + 1 end
      if not seen[r.path] then
        seen[r.path] = true
        queue[#queue + 1] = r.path
        if r.srt then with_srt = with_srt + 1 end
      end
    end
  end
  return queue, with_markers, with_srt
end

-- "m:ss" per i messaggi
function M.clock(sec)
  sec = math.max(0, math.floor(sec + 0.5))
  return string.format("%d:%02d", sec // 60, sec % 60)
end

-- Anti-ansia: la trascrizione non da' percentuali, quindi dico cosa so davvero:
-- che sto lavorando, da quanto, quanto e' lungo l'audio e una stima dalle volte precedenti.
-- ratio = secondi di lavoro per secondo di audio misurati in passato (nil se mai misurato)
function M.heartbeat(name, elapsed, audio_len, ratio, tick)
  local spin = ({ "|", "/", "-", "\\" })[(tick % 4) + 1]
  local msg = string.format("%s  Sto lavorando, non sono bloccato: %s, %s trascorsi", spin, name, M.clock(elapsed))
  if audio_len and audio_len > 0 then
    msg = msg .. ", audio " .. M.clock(audio_len)
    if ratio and ratio > 0 then
      local left = audio_len * ratio - elapsed
      msg = msg .. (left > 0 and (", mancano circa " .. M.clock(left)) or ", dovrei finire a momenti")
    end
  end
  return msg
end

if not reaper then return M end

---------------------------------------------------------------------------
-- PARTE REAPER
---------------------------------------------------------------------------

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
local function get_s(fn, obj, key) local _, v = fn(obj, key, "", false); return v or "" end

local ui_path = find_file("ZP_UI.lua")
if not ui_path then
  reaper.ShowMessageBox("Non trovo ZP_UI.lua accanto allo script.", "ZP Trascrizione", 0)
  return
end
local UI = dofile(ui_path)

local EXT = "ZP_STUDIO_SUITE"
local follow = reaper.GetExtState(EXT, "PanelAutofollow") == "1"
local FOLLOW_DELAY = 10.0

local status = "Seleziona gli item audio da lavorare."
local rows, rows_t = {}, -1
local text_names = {}          -- nomi delle tracce testo delle voci selezionate
local texts_visible = false
local queue, running = {}, nil
local audio_len = {}           -- percorso -> durata della sorgente, per la stima
local SPEED_KEY = "PanelSpeechRatio"
local chain = false            -- true mentre "Percorri la strada" e' in corso
local last_down = false
local pending, last_change, last_count = false, 0, reaper.GetProjectStateChangeCount(0)

---------------------------------------------------------------------------
-- Stato degli item selezionati e dei testi gia' in timeline
---------------------------------------------------------------------------
local function sidecar(p) return (p:gsub("%.[^./\\]+$", "")) .. ".srt" end

local function refresh_rows()
  -- testi esistenti: quanti item testo per take (chiave ZP_SYNC_KEY = GUID take|tempo)
  local per_take, text_track_of = {}, {}
  texts_visible = false
  for t = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, t)
    local voice = get_s(reaper.GetSetMediaTrackInfo_String, tr, "P_EXT:ZP_VOICE")
    if voice ~= "" then
      text_track_of[voice] = get_s(reaper.GetSetMediaTrackInfo_String, tr, "P_NAME")
      if reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP") == 1 then texts_visible = true end
      for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
        local key = get_s(reaper.GetSetMediaItemInfo_String, reaper.GetTrackMediaItem(tr, i), "P_EXT:ZP_SYNC_KEY")
        local tguid = key:match("^(.-)|")
        if tguid then per_take[tguid] = (per_take[tguid] or 0) + 1 end
      end
    end
  end

  rows, text_names = {}, {}
  local named = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local take = it and reaper.GetActiveTake(it)
    local src = take and reaper.GetMediaItemTake_Source(take)
    local path = src and reaper.GetMediaSourceFileName(src, "") or ""
    if path ~= "" then
      local tguid = get_s(reaper.GetSetMediaItemTakeInfo_String, take, "GUID")
      local vguid = reaper.GetTrackGUID(reaper.GetMediaItem_Track(it))
      rows[#rows + 1] = {
        name = path:match("[^/\\]+$") or path, path = path,
        wav = path:lower():match("%.wav$") ~= nil,
        srt = exists(sidecar(path)), markers = reaper.GetNumTakeMarkers(take),
        len = reaper.GetMediaSourceLength(src),
        texts = per_take[tguid] or 0,
      }
      audio_len[path] = rows[#rows].len
      local tn = text_track_of[vguid]
      if tn and not named[tn] then named[tn] = true; text_names[#text_names + 1] = tn end
    end
  end
  rows_t = os.clock()
end

---------------------------------------------------------------------------
-- Tappe
---------------------------------------------------------------------------
local function run_script(name, flags)
  local p = find_file(name)
  if not p then status = "Non trovo " .. name; return nil end
  for k, v in pairs(flags) do _G[k] = v end
  local ok, res = pcall(dofile, p)
  for k in pairs(flags) do _G[k] = nil end
  if not ok then status = "Errore in " .. name .. ": " .. tostring(res); return nil end
  return res
end

-- Tappa 3
local function do_bring(quiet)
  local msg = run_script("ZP_sincronizza_aggancio.lua", { ZP_SYNC_QUIET = true })
  if msg and not quiet then status = "Testi in timeline: " .. tostring(msg):gsub("\n", " ") end
  last_count = reaper.GetProjectStateChangeCount(0)   -- i cambi del sync non riaccendono il follow
  pending = false
  refresh_rows()
  return msg
end

local function set_follow(on)
  follow = on
  reaper.SetExtState(EXT, "PanelAutofollow", follow and "1" or "0", true)
  last_count = reaper.GetProjectStateChangeCount(0); pending = false
end

-- Tappa 2 (+3): abbina e porta subito i testi in timeline
local function do_link(skip_existing, srt_path)
  local msg = run_script("28_Collega_Marker.lua",
    { ZP_COLLEGA_QUIET = true, ZP_COLLEGA_SKIP_EXISTING = skip_existing or nil, ZP_COLLEGA_SRT_PATH = srt_path })
  local brought = do_bring(true)
  status = (msg and tostring(msg):match("^[^\n]*") or "Abbina: nessuna modifica.") ..
    (brought and ("  Testi: " .. tostring(brought):gsub("\n", " ")) or "")
end

-- Tappa 2 da marker di progetto: motore del 14 su tutti gli item selezionati,
-- poi subito nel gobbo. La domanda "cancello dalla timeline?" la fa il 14.
local function do_link_markers()
  local msg = run_script("14_Marker_da_Timeline_a_Item.lua", { ZP_14_ALL = true, ZP_14_QUIET = true })
  local brought = do_bring(true)
  status = (msg and (tostring(msg):gsub("\n", "  ")) or "Da marker di progetto: nessuna modifica.") ..
    (brought and ("  Testi: " .. tostring(brought):gsub("\n", " ")) or "")
end

-- Cue gia' scritti dentro il WAV -> marker di progetto in timeline (azione nativa 40692),
-- cosi' li gestisci in REAPER; quando renderizzi il file rilavorato escono i cue nuovi.
local function do_cues_to_timeline()
  local _, before = reaper.CountProjectMarkers(0)
  reaper.Main_OnCommand(40692, 0)   -- Item: Import item media cues as project markers
  local _, after = reaper.CountProjectMarkers(0)
  local n = after - before
  status = n > 0 and string.format(
    "Cue del WAV in timeline: %d marker di progetto. Sistemali in REAPER; per fissarli nell'item: Abbina da > marker di progetto.", n)
    or "Nessun cue trovato nei file degli item selezionati."
end

local function abbina_menu()
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local choice = gfx.showmenu(
    "SRT accanto al file (automatico)|SRT esterno o tradotto...|Marker di progetto in timeline (14)|Cue del WAV -> marker in timeline")
  if choice == 1 then
    do_link(false)
  elseif choice == 2 then
    local ok, path = reaper.GetUserFileNameForRead("", "SRT esterno o tradotto per gli item selezionati", "srt")
    if ok and path ~= "" then do_link(false, path) end
  elseif choice == 3 then
    do_link_markers()
  elseif choice == 4 then
    do_cues_to_timeline()
  end
end

local function finish_chain()
  chain = false
  do_link(true)
  if not follow then set_follow(true) end
  status = "Strada percorsa. " .. status
end

-- Tappa 1: coda sequenziale su ZP Speech
local function speech_cli()
  local home = os.getenv("HOME") or ""
  return home .. "/Library/Application Support/ZP/runtimes/speech/bin/zp-speech", home
end

local function start_next()
  local job = table.remove(queue, 1)
  if not job then
    running = nil
    refresh_rows()
    if chain then finish_chain() else status = "Trascrizione finita. Prossima tappa: Abbina." end
    return
  end
  local cli = speech_cli()
  local tmp = os.tmpname(); os.remove(tmp)
  local st, lg, pf = tmp .. ".status", tmp .. ".log", tmp .. ".pid"
  local task = shell_quote(cli) .. " request " .. shell_quote(job) .. " --format srt --output " ..
    shell_quote(sidecar(job)) .. " > " .. shell_quote(lg) .. " 2>&1; printf '%s\\n' \"$?\" > " .. shell_quote(st)
  os.execute("(" .. task .. ") </dev/null >/dev/null 2>&1 & echo $! > " .. shell_quote(pf))
  local now = reaper.time_precise()
  running = { job = job, st = st, lg = lg, pf = pf, t0 = now, checked = now, len = audio_len[job] }
  status = string.format("Trascrivo %s (ne restano %d)...", job:match("[^/\\]+$") or job, #queue)
end

local function speech_ratio()
  return tonumber(reaper.GetExtState(EXT, SPEED_KEY))
end

local function poll_job()
  if not running then return end
  local code = read_file(running.st)
  if not code then
    -- ogni 2 s controllo che il processo sia davvero vivo: se e' morto senza risposta lo dico
    local now = reaper.time_precise()
    if now - running.checked >= 2 then
      running.checked = now
      local pid = (read_file(running.pf) or ""):match("%d+")
      if pid and not os.execute("kill -0 " .. pid .. " 2>/dev/null") and not read_file(running.st) then
        status = "La trascrizione si e' fermata senza risposta: " .. (running.job:match("[^/\\]+$") or "") .. ". Riprova."
        os.remove(running.pf)
        queue, running, chain = {}, nil, false
      end
    end
    return
  end
  os.remove(running.st)
  os.remove(running.pf)
  if tonumber(code:match("%d+")) ~= 0 then
    local detail = read_file(running.lg) or ""
    reaper.ShowConsoleMsg("[ZP Speech] errore su " .. running.job .. "\n" .. detail:sub(-1200) .. "\n")
    status = "Trascrizione NON riuscita: " .. (running.job:match("[^/\\]+$") or "") .. " (dettagli nella console)"
    queue, running, chain = {}, nil, false
    return
  end
  os.remove(running.lg)
  -- impara la velocita' (media mobile) per stimare le prossime trascrizioni
  if running.len and running.len > 5 then
    local r = (reaper.time_precise() - running.t0) / running.len
    local old = speech_ratio()
    reaper.SetExtState(EXT, SPEED_KEY, string.format("%.4f", old and (old * 0.6 + r * 0.4) or r), true)
  end
  start_next()
end

local function speech_ready()
  local osname = reaper.GetOS()
  if not (osname:match("OSX") or osname:match("macOS")) then
    reaper.ShowMessageBox("La trascrizione automatica e' configurata solo su macOS.\nSu Windows/Linux: crea l'SRT con il tuo whisper (stesso nome del WAV, accanto al file) e parti dalla tappa Abbina.", "ZP Trascrizione", 0)
    return false
  end
  if not exists((speech_cli())) then
    reaper.ShowMessageBox("ZP Speech non e' installato.\nNel repo zp-suite lancia: bash speech-engine/install_macos.sh\n(serve Python 3.11+ e MacWhisper). Oppure crea l'SRT con il tuo whisper e parti dalla tappa Abbina.", "ZP Trascrizione", 0)
    return false
  end
  -- il servizio va avviato se non gira (come in 26_SRT_Tools.lua)
  local p = io.popen("/usr/bin/id -u 2>/dev/null", "r")
  local uid = p and p:read("*l"); if p then p:close() end
  if uid and uid:match("^%d+$") then
    local plist = select(2, speech_cli()) .. "/Library/LaunchAgents/com.zp.speech-service.plist"
    os.execute("/bin/launchctl kickstart gui/" .. uid .. "/com.zp.speech-service >/dev/null 2>&1 || /bin/launchctl bootstrap 'gui/" ..
      uid .. "' " .. shell_quote(plist) .. " >/dev/null 2>&1")
  end
  return true
end

-- Restituisce true se ha messo in coda qualcosa
local function do_transcribe()
  if running then status = "Una trascrizione e' gia' in corso."; return false end
  refresh_rows()
  local list = M.to_transcribe(rows)
  if #list == 0 then status = "Niente da trascrivere: gli item hanno gia' SRT o marker, o non sono WAV."; return false end
  if not speech_ready() then return false end
  queue = list
  start_next()
  return true
end

-- Ritrascrivi: il file ha gia' marker o SRT ma va riletto (glue, tempi cambiati).
-- Prima chiede; poi toglie i take marker degli item selezionati (Undo li rimette), rinomina
-- l'SRT accanto al file in .srt.bak-<data> (non lo cancella) e percorre la strada da capo.
local function do_retranscribe()
  if running then status = "Una trascrizione e' gia' in corso."; return end
  refresh_rows()
  local list, n_mark, n_srt = M.to_retranscribe(rows)
  if #list == 0 then status = "Niente da ritrascrivere: seleziona item WAV."; return end
  if not speech_ready() then return end
  local msg = string.format(
    "Ritrascrivo da capo %d file, come se fossero nuovi.\n\n" ..
    "Prima:\n- tolgo i take marker da %d item selezionati (solo da questi; Annulla li rimette)\n" ..
    "- l'SRT accanto al file (%d) lo rinomino in .srt.bak-<data>: non lo cancello\n\n" ..
    "Poi: trascrizione, Abbina e testi nel gobbo.\n" ..
    "I testi del gobbo legati ai vecchi marker: quelli mai toccati spariscono,\n" ..
    "quelli corretti a mano restano in mute.\n\nProcedo?", #list, n_mark, n_srt)
  if reaper.ShowMessageBox(msg, "ZP Trascrizione - Ritrascrivi", 4) ~= 6 then
    status = "Ritrascrivi annullato."
    return
  end
  local wanted = {}
  for _, p in ipairs(list) do wanted[p] = true end
  reaper.Undo_BeginBlock()
  local removed = 0
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local take = reaper.GetActiveTake(reaper.GetSelectedMediaItem(0, i))
    local src = take and reaper.GetMediaItemTake_Source(take)
    local path = src and reaper.GetMediaSourceFileName(src, "") or ""
    if wanted[path] then
      for m = reaper.GetNumTakeMarkers(take) - 1, 0, -1 do
        reaper.DeleteTakeMarker(take, m); removed = removed + 1
      end
    end
  end
  reaper.Undo_EndBlock("ZP Trascrizione: togli i take marker per ritrascrivere", -1)
  reaper.UpdateArrange()
  local stamp = os.date("%Y%m%d_%H%M%S")
  for _, p in ipairs(list) do
    local sc = sidecar(p)
    if exists(sc) then os.rename(sc, sc .. ".bak-" .. stamp) end
  end
  refresh_rows()
  chain = true
  queue = list
  start_next()
  status = string.format("Ritrascrivo: tolti %d marker. ", removed) .. status
end

local function walk_road()
  if #rows == 0 then status = "Seleziona prima gli item audio."; return end
  chain = true
  if not do_transcribe() and not running then finish_chain() end
end

local function toggle_texts_visible()
  local show = texts_visible and 0 or 1
  for t = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, t)
    if get_s(reaper.GetSetMediaTrackInfo_String, tr, "P_EXT:ZP_VOICE") ~= "" then
      reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", show)
    end
  end
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  refresh_rows()
end

---------------------------------------------------------------------------
-- Finestra
---------------------------------------------------------------------------
local TITLES = { "Trascrivi", "Abbina da...", "Porta nel gobbo", "Segui i tagli" }
local HINTS = {
  "whisper crea l'SRT accanto al file audio",
  "SRT, SRT tradotto, marker di progetto o cue -> marker sull'item",
  "i marker diventano testi magnetici per il gobbo",
  "dopo 10 s di quiete i testi seguono l'audio (interruttore anche nei Gobbi)",
}
local GREEN, BLUE, GRAY = { 0.20, 0.62, 0.34, 1 }, { 0.24, 0.52, 0.80, 1 }, { 0.36, 0.36, 0.42, 1 }

gfx.init("ZP Studio Suite - ZP Trascrizione", 660, 600, 0)

local function draw_step(i, s, is_next, y, clicked)
  local pad = 22
  local cx, cy, r = pad + 16, y + 22, 14
  -- tratto di strada verso la tappa successiva
  if i < 4 then
    UI.set_color(s.done and GREEN or GRAY)
    gfx.rect(cx - 1, cy + r, 3, 78 - 2 * r, true)
  end
  UI.set_color(s.done and GREEN or (is_next and BLUE or GRAY))
  gfx.circle(cx, cy, r, s.done or is_next, true)
  if is_next then gfx.circle(cx, cy, r + 4, false, true) end
  gfx.setfont(1, "Arial", 15, string.byte("b"))
  UI.set_color(UI.colors.text)
  local mark = s.done and "ok" or tostring(i)
  local mw = gfx.measurestr(mark)
  gfx.x, gfx.y = cx - mw / 2, cy - 8
  gfx.drawstr(mark)

  local tx = cx + r + 18
  gfx.setfont(1, "Arial", 17, string.byte("b"))
  UI.set_color(is_next and UI.colors.title or UI.colors.text)
  gfx.x, gfx.y = tx, y + 4
  gfx.drawstr(i .. "  " .. TITLES[i] .. (is_next and "   <- adesso" or ""))
  gfx.setfont(1, "Arial", 14)
  UI.set_color(UI.colors.muted)
  gfx.x, gfx.y = tx, y + 26
  gfx.drawstr(HINTS[i])
  UI.set_color(s.done and UI.colors.credit or UI.colors.disabled)
  gfx.x, gfx.y = tx, y + 44
  local info = s.info
  if i == 1 and running then
    info = M.heartbeat(running.job:match("[^/\\]+$") or running.job, reaper.time_precise() - running.t0,
      running.len, speech_ratio(), math.floor(reaper.time_precise() * 4))
    if #queue > 0 then info = info .. string.format(" (poi altri %d)", #queue) end
  end
  if i == 3 and #text_names > 0 then info = info .. "  -  " .. table.concat(text_names, ", ") end
  gfx.drawstr(UI.fit_text(info, gfx.w - tx - 190))

  -- pulsante della tappa
  local b = { x = gfx.w - pad - 160, y = y + 6, w = 160, h = 34 }
  local busy = running ~= nil or chain
  if i == 1 then
    -- tappa gia' fatta (SRT o marker): il pulsante diventa Ritrascrivi, per rileggere da capo
    local redo = s.done and not running
    local label = running and "Trascrivo..." or (redo and "Ritrascrivi..." or "Trascrivi")
    if UI.draw_button(b, label, running ~= nil, not busy and #rows > 0, clicked, redo and "play_select" or "play_now") then
      if redo then do_retranscribe() else do_transcribe() end
    end
  elseif i == 2 then
    if UI.draw_button(b, "Abbina da...", false, not busy and #rows > 0, clicked, "play_select") then abbina_menu() end
  elseif i == 3 then
    if UI.draw_button(b, "Aggiorna ora", false, not busy, clicked, "save") then do_bring(false) end
  else
    if UI.draw_button(b, follow and "Segui: ACCESO" or "Segui: spento", follow, true, clicked, "tab") then set_follow(not follow) end
  end
end

local function loop()
  if gfx.getchar() < 0 then gfx.quit() return end
  local now = os.clock()
  local down = (gfx.mouse_cap & 1) == 1
  local clicked = down and not last_down
  last_down = down

  if now - rows_t > 1.0 then refresh_rows() end
  poll_job()

  -- Segui i tagli: aspetta 10 s di quiete, poi riporta i testi sull'audio
  if follow and not running then
    local c = reaper.GetProjectStateChangeCount(0)
    if c ~= last_count then last_count = c; last_change = now; pending = true end
    if pending and now - last_change >= FOLLOW_DELAY then
      local msg = do_bring(true)
      if msg then status = "Seguito automatico: " .. tostring(msg):gsub("\n", " ") end
    end
  end

  UI.fill_background()
  UI.draw_header({ title = "Trascrizione -> Gobbo", credit = "ZP Studio Suite - 29",
    description = "Seleziona gli item audio e segui la strada. Ogni tappa si puo' fare anche a mano." })
  UI.draw_help_button({ x = gfx.w - 54, y = 16, w = 34, h = 28 }, clicked, "tool-29")

  local steps, next_step = M.road(rows, follow)
  local y = 96
  for i, s in ipairs(steps) do
    draw_step(i, s, i == next_step and not chain, y, clicked)
    y = y + 78
  end

  local pad = 22
  local bw = gfx.w - pad * 2 - 200
  local label = chain and "Sto percorrendo la strada..." or
    (next_step and ("Percorri la strada (da tappa " .. next_step .. ")") or "Strada completa")
  if UI.draw_button({ x = pad, y = y + 4, w = bw, h = 40 }, label, chain, not chain and next_step ~= nil, clicked, "play_now") then
    walk_road()
  end
  if UI.draw_button({ x = pad + bw + 10, y = y + 4, w = 190, h = 40 },
      texts_visible and "Nascondi tracce testo" or "Mostra tracce testo", texts_visible, true, clicked, "tab") then
    toggle_texts_visible()
  end

  -- item selezionati
  y = y + 58
  gfx.setfont(1, "Arial", 14)
  UI.set_color(UI.colors.muted)
  gfx.x, gfx.y = pad, y
  gfx.drawstr(#rows == 0 and "Nessun item audio selezionato." or string.format("Item selezionati: %d", #rows))
  y = y + 20
  for i, r in ipairs(rows) do
    if y > gfx.h - 54 then
      UI.set_color(UI.colors.muted); gfx.x, gfx.y = pad, y
      gfx.drawstr(string.format("... e altri %d", #rows - i + 1)); break
    end
    UI.set_color(UI.colors.text)
    gfx.x, gfx.y = pad, y
    gfx.drawstr(UI.fit_text(r.name, gfx.w - pad * 2 - 260))
    UI.set_color(UI.colors.muted)
    gfx.x = gfx.w - pad - 250
    gfx.drawstr(string.format("%s   marker %d   testi %d", r.srt and "SRT si" or "SRT no", r.markers, r.texts))
    y = y + 19
  end

  UI.set_color(UI.colors.title)
  gfx.setfont(1, "Arial", 14)
  gfx.x, gfx.y = pad, gfx.h - 32
  gfx.drawstr(UI.fit_text(status, gfx.w - pad * 2))

  gfx.update()
  reaper.defer(loop)
end

refresh_rows()
loop()
