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
    { done = n > 0 and srt == n,    info = M.summary(rows) },
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

-- Riga di stato della tappa 1, sugli item selezionati:
-- "5 selezionati: 3 da trascrivere, 2 gia' fatti" (+ ", 1 non WAV" se ce ne sono).
-- Gia' fatto = ha l'SRT accanto o i marker: non viene ritoccato (per rifarlo c'e' Ritrascrivi).
function M.summary(rows)
  local n, todo, done, other = #rows, 0, 0, 0
  for _, r in ipairs(rows) do
    if r.srt or r.markers > 0 then done = done + 1
    elseif r.wav then todo = todo + 1
    else other = other + 1 end
  end
  if n == 0 then return "nessun item selezionato" end
  local msg = string.format("%d selezionat%s: %d da trascrivere, %d gia' fatt%s",
    n, n == 1 and "o" or "i", todo, done, done == 1 and "o" or "i")
  if other > 0 then msg = msg .. string.format(", %d non WAV", other) end
  return msg
end

-- Nome breve di un modello di ZP Speech: "whisperkit:openai_whisper-large-v3-v20240930" -> "large-v3",
-- "parakeet-pro:nvidia_parakeet-v3_494MB" -> "parakeet-v3". Vuoto = predefinito del motore.
function M.model_label(model)
  if not model or model == "" then return "predefinito" end
  local m = model:match(":(.+)$") or model
  m = m:gsub("^openai_whisper%-", ""):gsub("^nvidia_", ""):gsub("%-v%d%d%d%d%d%d%d%d$", ""):gsub("_%d+MB$", "")
  return m
end

-- Modelli installati dalla risposta JSON di /api/v1/capabilities.
function M.parse_models(json)
  local list = {}
  local block = tostring(json or ""):match('"models"%s*:%s*%[(.-)%]')
  for m in (block or ""):gmatch('"([^"]+)"') do list[#list + 1] = m end
  return list
end

-- Lingue in tendina (codici ISO 639-1, come li vuole MacWhisper); "Altra..." accetta qualsiasi codice.
M.LANGS = {
  { code = "it", label = "Italiano" }, { code = "en", label = "Inglese" }, { code = "fr", label = "Francese" },
  { code = "de", label = "Tedesco" }, { code = "es", label = "Spagnolo" }, { code = "pt", label = "Portoghese" },
  { code = "zh", label = "Cinese" }, { code = "ja", label = "Giapponese" }, { code = "ko", label = "Coreano" },
  { code = "ru", label = "Russo" }, { code = "auto", label = "Automatica" },
}
function M.lang_label(code)
  for _, l in ipairs(M.LANGS) do if l.code == code then return l.label end end
  if not code or code == "" then return "Italiano" end
  return code:upper()
end

-- Codice scritto a mano in "Altra...": 2 o 3 lettere (it, fr, yue...), oppure nil.
function M.clean_lang_code(text)
  local c = tostring(text or ""):lower():gsub("%s", "")
  if c:match("^%a%a%a?$") or c == "auto" then return c end
  return nil
end

-- Parakeet v3 conosce solo 25 lingue europee: con le altre avviso (Whisper ne conosce circa 99).
local PARAKEET_LANGS = {}
for c in ("bg hr cs da nl en et fi fr de el hu it lv lt mt pl pt ro sk sl es sv ru uk auto"):gmatch("%S+") do PARAKEET_LANGS[c] = true end
function M.lang_warning(model, code)
  if tostring(model or ""):lower():find("parakeet", 1, true) and not PARAKEET_LANGS[code or ""] then
    return "Parakeet non conosce " .. M.lang_label(code) .. ": usa large-v3 o small (Whisper)."
  end
  return nil
end

-- Traduzione (a richiesta): Episodio01.srt -> Episodio01.it.srt, accanto all'originale.
-- Un tag di lingua gia' presente nel nome viene sostituito (come fa zp-speech translate).
function M.translated_name(srt, code)
  local base = tostring(srt):gsub("%.[Ss][Rr][Tt]$", "")
  local stem_tag = base:match("^(.*)%.%a%a%a?$")
  if stem_tag and not stem_tag:match("[/\\]$") then base = stem_tag end
  return base .. "." .. code .. ".srt"
end

-- Motori di traduzione dalla risposta di `zp-speech translators`:
-- { {engine="codex", available=true, models={...}}, ... }
function M.parse_engines(json)
  local list = {}
  for obj in tostring(json or ""):gmatch('{"engine"%s*:.-%]}') do
    local e = { engine = obj:match('"engine"%s*:%s*"([^"]+)"'),
                available = obj:match('"available"%s*:%s*true') ~= nil, models = {} }
    for m in (obj:match('"models"%s*:%s*%[(.-)%]') or ""):gmatch('"([^"]+)"') do e.models[#e.models + 1] = m end
    if e.engine then list[#list + 1] = e end
  end
  return list
end

-- Ultimo "progress n/tot" scritto dal motore durante la traduzione.
function M.progress_from_log(text)
  local done, total
  for d, t in tostring(text or ""):gmatch("progress (%d+)/(%d+)") do done, total = tonumber(d), tonumber(t) end
  return done, total
end

-- Coda in background: uno script bash fa i lavori uno dopo l'altro, indipendente dalla finestra
-- (chiuderla non ferma niente). Nella cartella del lavoro scrive:
--   cur  = "i<TAB>secondi_epoch<TAB>percorso" del lavoro in corso
--   done = una riga "i<TAB>codice<TAB>secondi<TAB>percorso" per ogni lavoro finito
--   log_i = uscita del lavoro i;  end = scritto alla fine
-- e alla fine manda una notifica di macOS. items: { {path=..., cmd=...}, ... } (cmd gia' quotato).
local function sq(v) return "'" .. tostring(v):gsub("'", "'\\''") .. "'" end
function M.batch_script(dir, items, title, what)
  local out = { "#!/bin/bash", "D=" .. sq(dir), "ok=0; ko=0" }
  for i, it in ipairs(items) do
    local p = tostring(it.path):gsub("[\t\n]", " ")
    out[#out + 1] = string.format('t0=$(date +%%s); printf "%%s\\t%%s\\t%%s\\n" %d "$t0" %s > "$D/cur"', i, sq(p))
    out[#out + 1] = string.format('{ %s ; } > "$D/log_%d" 2>&1; c=$?', it.cmd, i)
    out[#out + 1] = 'if [ "$c" = 0 ]; then ok=$((ok+1)); else ko=$((ko+1)); fi'
    out[#out + 1] = string.format('printf "%%s\\t%%s\\t%%s\\t%%s\\n" %d "$c" "$(( $(date +%%s) - t0 ))" %s >> "$D/done"', i, sq(p))
  end
  out[#out + 1] = string.format('msg="%s finita: $ok di %d file"; [ "$ko" != 0 ] && msg="$msg, $ko non riusciti"', what, #items)
  out[#out + 1] = 'echo "$ok $ko" > "$D/end"'
  out[#out + 1] = "/usr/bin/osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title (item 2 of argv)' -e 'end run' \"$msg\" " .. sq(title) .. " >/dev/null 2>&1"
  return table.concat(out, "\n") .. "\n"
end

-- Righe di "done": { {i=, code=, secs=, path=}, ... }
function M.parse_done(text)
  local list = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local i, code, secs, path = line:match("^(%d+)\t(%d+)\t(%d+)\t(.*)$")
    if i then list[#list + 1] = { i = tonumber(i), code = tonumber(code), secs = tonumber(secs), path = path } end
  end
  return list
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

-- Modello e lingua di whisper (tendine in alto): valgono per Trascrivi e Ritrascrivi.
-- Ogni file trascritto si ricorda con cosa e' stato fatto (ExtState del progetto ZP_SPEECH_MODEL).
local MODEL_KEY, LANG_KEY, MADE_SECTION = "PanelSpeechModel", "PanelSpeechLang", "ZP_SPEECH_MODEL"
local speech_model = reaper.GetExtState(EXT, MODEL_KEY)          -- "" = predefinito del motore
local speech_lang = reaper.GetExtState(EXT, LANG_KEY)
if speech_lang == "" then speech_lang = "it" end
local speech_models = nil                                         -- nil = non ancora chiesti

-- Traduzione degli SRT (a richiesta): motore, modello e lingua d'arrivo ricordati.
local TR_ENGINE_KEY, TR_MODEL_KEY, TR_LANG_KEY = "PanelTranslateEngine", "PanelTranslateModel", "PanelTranslateLang"
local tr_engine = reaper.GetExtState(EXT, TR_ENGINE_KEY); if tr_engine == "" then tr_engine = "codex" end
local tr_model = reaper.GetExtState(EXT, TR_MODEL_KEY)            -- "" = quello scelto in Codex
local tr_lang = reaper.GetExtState(EXT, TR_LANG_KEY); if tr_lang == "" then tr_lang = "it" end
local tr_engines = nil                                            -- nil = non ancora chiesti
local tr_queue, tr_running, tr_report = {}, nil, nil

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
        -- le battute tradotte (chiave "...|it" o "...|it|c") non contano: sono la stessa battuta
        local translated = key:match("|%a%a%a?$") and not key:match("|c$") or key:match("|%a%a%a?|c$")
        if tguid and not translated then per_take[tguid] = (per_take[tguid] or 0) + 1 end
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
        made = select(2, reaper.GetProjExtState(0, MADE_SECTION, path)),
      }
      local tr = {}
      for _, l in ipairs(M.LANGS) do
        if l.code ~= "auto" and exists(M.translated_name(sidecar(path), l.code)) then tr[#tr + 1] = l.code end
      end
      rows[#rows].translations = tr
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
    do_link(true)   -- gli item gia' abbinati restano com'erano: per rifarli c'e' Ritrascrivi
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

---------------------------------------------------------------------------
-- Coda in background (trascrivi / traduci): vedi M.batch_script. La finestra legge la cartella
-- del lavoro; se la riapri a lavoro in corso o finito, riprende da li' (anche il seguito di
-- "Percorri la strada", segnato nel file chain).
---------------------------------------------------------------------------
local JOBS = reaper.GetResourcePath() .. sep .. "ZP_jobs"
local batches = {}                 -- kind -> { total, seen, plan, chain }

local function job_dir(kind) return JOBS .. sep .. kind end

local function write_file(p, text)
  local f = io.open(p, "wb"); if not f then return false end
  f:write(text); f:close(); return true
end

local function clear_dir(dir)
  os.execute("/bin/rm -rf " .. shell_quote(dir) .. " 2>/dev/null")
end

-- items: { {path=, cmd=, made=, len=}, ... }
local function start_batch(kind, items, with_chain, title, what)
  local dir = job_dir(kind)
  clear_dir(dir)
  os.execute("/bin/mkdir -p " .. shell_quote(dir))
  local plan = {}
  for i, it in ipairs(items) do plan[#plan + 1] = string.format("%d\t%s\t%s\t%s", i, it.made or "", tostring(it.len or 0), it.path) end
  write_file(dir .. sep .. "plan", table.concat(plan, "\n") .. "\n")
  if with_chain then write_file(dir .. sep .. "chain", "1\n") end
  write_file(dir .. sep .. "run.sh", M.batch_script(dir, items, title, what))
  os.execute("/usr/bin/nohup /bin/bash " .. shell_quote(dir .. sep .. "run.sh") ..
    " </dev/null >/dev/null 2>&1 & echo $! > " .. shell_quote(dir .. sep .. "pid"))
  batches[kind] = nil
end

-- Legge lo stato del lavoro. on_item(entry, plan_row) per ogni lavoro appena finito;
-- on_end(ok, ko, chain) una volta sola alla fine. Restituisce la tabella "running" o nil.
local function poll_batch(kind, on_item, on_end)
  local dir = job_dir(kind)
  local planf = read_file(dir .. sep .. "plan")
  if not planf then batches[kind] = nil; return nil end
  local b = batches[kind]
  if not b then
    b = { plan = {}, seen = tonumber(read_file(dir .. sep .. "seen") or "") or 0,
          chain = exists(dir .. sep .. "chain"), checked = 0 }
    for line in planf:gmatch("[^\n]+") do
      local i, made, len, path = line:match("^(%d+)\t([^\t]*)\t([^\t]*)\t(.*)$")
      if i then b.plan[tonumber(i)] = { made = made, len = tonumber(len), path = path } end
    end
    b.total = #b.plan
    batches[kind] = b
  end
  for _, e in ipairs(M.parse_done(read_file(dir .. sep .. "done"))) do
    if e.i > b.seen then
      b.seen = e.i
      write_file(dir .. sep .. "seen", tostring(b.seen))
      on_item(e, b.plan[e.i] or {}, dir)
    end
  end
  local fin = read_file(dir .. sep .. "end")
  if fin then
    local ok, ko = fin:match("(%d+)%s+(%d+)")
    local chain_flag = b.chain
    clear_dir(dir)
    batches[kind] = nil
    on_end(tonumber(ok) or 0, tonumber(ko) or 0, chain_flag)
    return nil
  end
  -- processo morto senza "end" (per esempio Mac riavviato): lo dico e chiudo il lavoro
  local now = reaper.time_precise()
  if now - b.checked >= 2 then
    b.checked = now
    local pid = (read_file(dir .. sep .. "pid") or ""):match("%d+")
    if pid and not os.execute("kill -0 " .. pid .. " 2>/dev/null") and not read_file(dir .. sep .. "end") then
      clear_dir(dir)
      batches[kind] = nil
      status = "Il lavoro in background si e' interrotto (" .. b.seen .. " di " .. b.total .. " fatti). Riprova: riparte da quelli che mancano."
      return nil
    end
  end
  local cur = read_file(dir .. sep .. "cur") or ""
  local ci, epoch, cpath = cur:match("^(%d+)\t(%d+)\t([^\n]*)")
  ci = tonumber(ci) or (b.seen + 1)
  local row = b.plan[ci] or {}
  return { job = cpath or row.path or "", t0 = now - math.max(0, os.time() - (tonumber(epoch) or os.time())),
           len = row.len, left = math.max(0, b.total - ci), index = ci, total = b.total,
           log = dir .. sep .. "log_" .. ci, chain = b.chain }
end

-- Tappa 1: coda sequenziale su ZP Speech
local function speech_cli()
  local home = os.getenv("HOME") or ""
  return home .. "/Library/Application Support/ZP/runtimes/speech/bin/zp-speech", home
end

local function start_next()
  -- tutta la coda parte in background: chiudere la finestra non la ferma
  local cli = speech_cli()
  local opts = " --language " .. shell_quote(speech_lang)
  if speech_model ~= "" then opts = opts .. " --model " .. shell_quote(speech_model) end
  local items = {}
  for _, job in ipairs(queue) do
    items[#items + 1] = { path = job, len = audio_len[job], made = M.model_label(speech_model) .. " " .. speech_lang,
      cmd = shell_quote(cli) .. " request " .. shell_quote(job) .. opts .. " --format srt --output " .. shell_quote(sidecar(job)) }
  end
  queue = {}
  if #items == 0 then return end
  start_batch("trascrivi", items, chain, "ZP Trascrizione", "Trascrizione")
  status = string.format("Trascrivo %d file in background: puoi chiudere la finestra, alla fine arriva una notifica.", #items)
end

local function speech_ratio()
  return tonumber(reaper.GetExtState(EXT, SPEED_KEY))
end

local function poll_job()
  running = poll_batch("trascrivi", function(e, row, dir)
    if e.code == 0 then
      reaper.SetProjExtState(0, MADE_SECTION, e.path, row.made or "")   -- con che modello e lingua
      -- impara la velocita' (media mobile) per stimare le prossime trascrizioni
      if row.len and row.len > 5 and e.secs > 0 then
        local r = e.secs / row.len
        local old = speech_ratio()
        reaper.SetExtState(EXT, SPEED_KEY, string.format("%.4f", old and (old * 0.6 + r * 0.4) or r), true)
      end
    else
      reaper.ShowConsoleMsg("[ZP Speech] errore su " .. e.path .. "\n" .. (read_file(dir .. sep .. "log_" .. e.i) or ""):sub(-1200) .. "\n")
    end
  end, function(ok, ko, chain_flag)
    refresh_rows()
    if ko > 0 then
      chain = false
      status = string.format("Trascrizione finita: %d file, %d NON riusciti (dettagli nella console).", ok, ko)
    elseif chain_flag then
      chain = true
      finish_chain()
    else
      chain = false
      status = string.format("Trascrizione finita: %d file. Prossima tappa: Abbina.", ok)
    end
  end)
  if running and running.chain then chain = true end
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

-- Modelli installati, chiesti una volta al servizio ZP Speech (curl, max 2 s).
local function load_models()
  speech_models = {}
  local url = (os.getenv("ZP_SPEECH_URL") or "http://127.0.0.1:8770"):gsub("/+$", "") .. "/api/v1/capabilities"
  local p = io.popen("/usr/bin/curl -s --max-time 2 " .. shell_quote(url) .. " 2>/dev/null", "r")
  if p then speech_models = M.parse_models(p:read("*a")); p:close() end
end

local function model_menu()
  if not speech_models or #speech_models == 0 then
    speech_ready()          -- se il servizio non gira lo avvia, poi riprovo
    load_models()
  end
  local items, parts = { "" }, { (speech_model == "" and "!" or "") .. "Predefinito del motore" }
  for _, m in ipairs(speech_models or {}) do
    items[#items + 1] = m
    parts[#parts + 1] = (m == speech_model and "!" or "") .. M.model_label(m)
  end
  if #items == 1 then parts[#parts + 1] = "#(ZP Speech non risponde: nessun elenco)" end
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local choice = gfx.showmenu(table.concat(parts, "|"))
  if choice > 0 and items[choice] then
    speech_model = items[choice]
    reaper.SetExtState(EXT, MODEL_KEY, speech_model, true)
    status = "Modello per le prossime trascrizioni: " .. M.model_label(speech_model) .. "."
  end
end

local function lang_menu()
  local parts, known = {}, false
  for i, l in ipairs(M.LANGS) do
    parts[i] = (l.code == speech_lang and "!" or "") .. l.label
    if l.code == speech_lang then known = true end
  end
  parts[#parts + 1] = (known and "" or "!") .. "Altra..." .. (known and "" or (" (" .. speech_lang .. ")"))
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local choice = gfx.showmenu(table.concat(parts, "|"))
  local code
  if choice > 0 and M.LANGS[choice] then
    code = M.LANGS[choice].code
  elseif choice == #M.LANGS + 1 then
    local ok, text = reaper.GetUserInputs("ZP Trascrizione - lingua", 1,
      "Codice della lingua (es. nl, ar, hi, yue):,extrawidth=60", known and "" or speech_lang)
    if ok then
      code = M.clean_lang_code(text)
      if not code then status = "Codice lingua non valido: servono 2 o 3 lettere (it, fr, yue...)." end
    end
  end
  if code then
    speech_lang = code
    reaper.SetExtState(EXT, LANG_KEY, speech_lang, true)
    status = "Lingua per le prossime trascrizioni: " .. M.lang_label(speech_lang) .. "."
  end
end

local function speech_choice_text()
  return M.model_label(speech_model) .. ", lingua " .. M.lang_label(speech_lang):lower()
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
  local skipped = 0
  for _, r in ipairs(rows) do if r.srt or r.markers > 0 then skipped = skipped + 1 end end
  status = status .. string.format("  [%s]%s", speech_choice_text(),
    skipped > 0 and string.format("  %d gia' fatti, lasciati come sono.", skipped) or "")
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
  -- l'SRT vecchio esiste solo se rileggi un file gia' trascritto (un file glued ha un nome
  -- nuovo e non ce l'ha): solo allora lo metto da parte e lo dico
  local msg = string.format(
    "Ritrascrivo da capo %d file, come se fossero nuovi.\n\n" ..
    "Prima tolgo i take marker da %d item selezionati (solo da questi; Annulla li rimette).%s\n\n" ..
    "Poi: trascrizione con " .. speech_choice_text() .. " (si cambiano dalle tendine in alto),\nAbbina e testi nel gobbo.\n" ..
    "I testi del gobbo legati ai vecchi marker: quelli mai toccati spariscono,\n" ..
    "quelli corretti a mano restano in mute.\n\nProcedo?", #list, n_mark,
    n_srt > 0 and string.format("\nL'SRT gia' accanto a %d file lo rinomino in .srt.bak-<data>, non lo cancello.", n_srt) or "")
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

---------------------------------------------------------------------------
-- Traduci (facoltativo): l'SRT accanto al file -> Nome.<lingua>.srt con un agente AI
-- (Codex con il tuo login). Coda in background come la trascrizione.
---------------------------------------------------------------------------
local function load_engines()
  tr_engines = {}
  local p = io.popen(shell_quote((speech_cli())) .. " translators 2>/dev/null", "r")
  if p then tr_engines = M.parse_engines(p:read("*a")); p:close() end
end

local function tr_choice_text()
  return M.lang_label(tr_lang) .. " · " .. tr_engine .. (tr_model ~= "" and (" " .. tr_model) or "")
end

local function tr_start_next()
  local items = {}
  local opts = " --to " .. shell_quote(tr_lang) .. " --engine " .. shell_quote(tr_engine)
  if tr_model ~= "" then opts = opts .. " --model " .. shell_quote(tr_model) end
  for _, job in ipairs(tr_queue) do
    items[#items + 1] = { path = job, cmd = shell_quote((speech_cli())) .. " translate " .. shell_quote(job) .. opts }
  end
  tr_queue = {}
  if #items == 0 then return end
  write_file(JOBS .. sep .. "traduci_report", string.format("%s %d %d", tr_lang, tr_report.skipped, tr_report.nosrt))
  start_batch("traduci", items, false, "ZP Traduci", "Traduzione")
  status = string.format("Traduco %d SRT in background: puoi chiudere la finestra, alla fine arriva una notifica.", #items)
end

local function tr_poll()
  tr_running = poll_batch("traduci", function(e, row, dir)
    if e.code ~= 0 then
      reaper.ShowConsoleMsg("[ZP Traduci] errore su " .. e.path .. "\n" .. (read_file(dir .. sep .. "log_" .. e.i) or ""):sub(-1200) .. "\n")
    end
  end, function(ok, ko)
    refresh_rows()
    local lang, skipped, nosrt = (read_file(JOBS .. sep .. "traduci_report") or ""):match("(%S+)%s+(%d+)%s+(%d+)")
    skipped, nosrt = tonumber(skipped) or 0, tonumber(nosrt) or 0
    status = string.format("Traduzione in %s finita: %d file tradotti", M.lang_label(lang or tr_lang):lower(), ok) ..
      (skipped > 0 and string.format(", %d gia' tradotti", skipped) or "") ..
      (nosrt > 0 and string.format(", %d senza SRT", nosrt) or "") ..
      (ko > 0 and string.format(", %d NON riusciti (dettagli nella console)", ko) or "") .. "."
  end)
end

local function do_translate()
  if running or tr_running then status = "Aspetta: c'e' gia' un lavoro in corso."; return end
  refresh_rows()
  local list, seen = {}, {}
  tr_report = { ok = 0, skipped = 0, nosrt = 0, failed = 0 }
  for _, r in ipairs(rows) do
    if not seen[r.path] then
      seen[r.path] = true
      local srt = sidecar(r.path)
      if not exists(srt) then tr_report.nosrt = tr_report.nosrt + 1
      elseif exists(M.translated_name(srt, tr_lang)) then tr_report.skipped = tr_report.skipped + 1
      else list[#list + 1] = srt end
    end
  end
  if #list == 0 then
    status = "Niente da tradurre in " .. M.lang_label(tr_lang):lower() .. ": " ..
      string.format("%d gia' tradotti, %d senza SRT.", tr_report.skipped, tr_report.nosrt)
    return
  end
  local where = tr_engine == "codex" and "Il testo delle battute va a OpenAI con il tuo account ChatGPT.\n" or ""
  local msg = string.format("Traduco %d SRT in %s con %s.\n\n%sGli originali non vengono toccati: " ..
    "accanto nasce Nome.%s.srt, con gli stessi tempi.\n\nProcedo?", #list, M.lang_label(tr_lang):lower(),
    tr_engine .. (tr_model ~= "" and (" (" .. tr_model .. ")") or ""), where, tr_lang)
  if reaper.ShowMessageBox(msg, "ZP Trascrizione - Traduci", 4) ~= 6 then status = "Traduzione annullata."; return end
  tr_queue = list
  tr_start_next()
end

-- Menu di Traduci: lingua d'arrivo (avvia), oppure motore / modello (solo scelta).
local function translate_menu()
  if not tr_engines then load_engines() end
  local parts, actions = { "#Traduci gli SRT degli item selezionati in:" }, { false }
  for _, l in ipairs(M.LANGS) do
    if l.code ~= "auto" then
      parts[#parts + 1] = (l.code == tr_lang and "!" or "") .. l.label
      actions[#actions + 1] = { lang = l.code }
    end
  end
  parts[#parts + 1] = ""; actions[#actions + 1] = false
  parts[#parts + 1] = ">Motore"; actions[#actions + 1] = false
  local engines = tr_engines or {}
  for i, e in ipairs(engines) do
    local label = e.engine .. (e.available and "" or " (non installato)")
    parts[#parts + 1] = (i == #engines and "<" or "") .. (e.available and "" or "#") ..
      (e.engine == tr_engine and "!" or "") .. label
    actions[#actions + 1] = { engine = e.engine }
  end
  if #engines == 0 then parts[#parts + 1] = "<#(nessun motore trovato)"; actions[#actions + 1] = false end
  local current = nil
  for _, e in ipairs(engines) do if e.engine == tr_engine then current = e end end
  parts[#parts + 1] = ">Modello"; actions[#actions + 1] = false
  parts[#parts + 1] = (tr_model == "" and "!" or "") .. "Quello scelto in " .. tr_engine
  actions[#actions + 1] = { model = "" }
  local models = current and current.models or {}
  for _, m in ipairs(models) do
    parts[#parts + 1] = (m == tr_model and "!" or "") .. m
    actions[#actions + 1] = { model = m }
  end
  parts[#parts] = "<" .. parts[#parts]
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  -- in showmenu le voci ">..." e "<" non contano come scelte: rimappo l'indice sulle voci vere
  local choice = gfx.showmenu(table.concat(parts, "|"))
  if choice <= 0 then return end
  local n = 0
  for i, part in ipairs(parts) do
    local p = part:gsub("^<", "")
    if p ~= "" and not p:match("^>") then
      n = n + 1
      if n == choice then
        local a = actions[i]
        if a and a.lang then
          tr_lang = a.lang; reaper.SetExtState(EXT, TR_LANG_KEY, tr_lang, true)
          do_translate()
        elseif a and a.engine then
          tr_engine = a.engine; reaper.SetExtState(EXT, TR_ENGINE_KEY, tr_engine, true)
          tr_model = ""; reaper.SetExtState(EXT, TR_MODEL_KEY, "", true)
          status = "Motore di traduzione: " .. tr_engine .. "."
        elseif a and a.model then
          tr_model = a.model; reaper.SetExtState(EXT, TR_MODEL_KEY, tr_model, true)
          status = "Modello di traduzione: " .. (tr_model ~= "" and tr_model or ("quello scelto in " .. tr_engine)) .. "."
        end
        return
      end
    end
  end
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

-- toolbar: icona accesa finche' la finestra e' aperta; un altro clic sull'icona la chiude (REAPER 7.03+)
if reaper.set_action_options then reaper.set_action_options(1 | 4); reaper.atexit(function() reaper.set_action_options(8) end) end
gfx.init("ZP Studio Suite - ZP Trascrizione", 720, 780, 0)

local STEP_H = 88   -- altezza di una tappa (testi piu' grandi, 2026-10-08)

local function draw_step(i, s, is_next, y, clicked)
  local pad = 22
  local cx, cy, r = pad + 16, y + 22, 14
  -- tratto di strada verso la tappa successiva
  if i < 4 then
    UI.set_color(s.done and GREEN or GRAY)
    gfx.rect(cx - 1, cy + r, 3, STEP_H - 2 * r, true)
  end
  UI.set_color(s.done and GREEN or (is_next and BLUE or GRAY))
  gfx.circle(cx, cy, r, s.done or is_next, true)
  if is_next then gfx.circle(cx, cy, r + 4, false, true) end
  gfx.setfont(1, "Arial", 17, string.byte("b"))
  UI.set_color(UI.colors.text)
  local mark = s.done and "ok" or tostring(i)
  local mw = gfx.measurestr(mark)
  gfx.x, gfx.y = cx - mw / 2, cy - 9
  gfx.drawstr(mark)

  local tx = cx + r + 18
  gfx.setfont(1, "Arial", 19, string.byte("b"))
  UI.set_color(is_next and UI.colors.title or UI.colors.text)
  gfx.x, gfx.y = tx, y + 4
  gfx.drawstr(i .. "  " .. TITLES[i] .. (is_next and "   <- adesso" or ""))
  gfx.setfont(1, "Arial", 16)
  UI.set_color(UI.colors.muted)
  gfx.x, gfx.y = tx, y + 29
  gfx.drawstr(HINTS[i])
  UI.set_color(s.done and UI.colors.credit or UI.colors.disabled)
  gfx.x, gfx.y = tx, y + 51
  local info = s.info
  if i == 1 and running then
    info = M.heartbeat(running.job:match("[^/\\]+$") or running.job, reaper.time_precise() - running.t0,
      running.len, speech_ratio(), math.floor(reaper.time_precise() * 4))
    if running.left and running.left > 0 then info = info .. string.format(" (%d di %d, poi altri %d)", running.index, running.total, running.left) end
  end
  if i == 3 and #text_names > 0 then info = info .. "  -  " .. table.concat(text_names, ", ") end
  gfx.drawstr(UI.fit_text(info, gfx.w - tx - pad))

  -- pulsante della tappa
  local b = { x = gfx.w - pad - 180, y = y + 4, w = 180, h = 38, font = 17 }
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

-- Titolo con l'avanzamento: si vede anche con la finestra agganciata o coperta.
-- gfx.init(nome) a finestra aperta cambia solo il titolo.
local BASE_TITLE, shown_title = "ZP Studio Suite - ZP Trascrizione", nil
local function update_title()
  local t = BASE_TITLE
  if running and running.total then t = string.format("ZP Trascrizione - trascrivo %d di %d", running.index, running.total)
  elseif tr_running and tr_running.total then t = string.format("ZP Trascrizione - traduco %d di %d", tr_running.index, tr_running.total) end
  if t ~= shown_title then shown_title = t; gfx.init(t) end
end

local function loop()
  if gfx.getchar() < 0 then gfx.quit() return end
  local now = os.clock()
  local down = (gfx.mouse_cap & 1) == 1
  local clicked = down and not last_down
  last_down = down

  if now - rows_t > 1.0 then refresh_rows() end
  poll_job()
  tr_poll()
  update_title()

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
    description = "Seleziona gli item audio e segui la strada. Ogni tappa si puo' fare anche a mano.", description_size = 16 })
  UI.draw_help_button({ x = gfx.w - 54, y = 16, w = 34, h = 28 }, clicked, "tool-29")

  -- modello e lingua di whisper
  do
    local pad, busy = 22, running ~= nil or chain
    gfx.setfont(1, "Arial", 16)
    UI.set_color(UI.colors.muted)
    gfx.x, gfx.y = pad, 103
    gfx.drawstr("Modello")
    if UI.draw_button({ x = pad + 72, y = 96, w = 220, h = 30, font = 16 }, M.model_label(speech_model) .. "  ▾", false, not busy, clicked, "tab") then
      model_menu()
    end
    UI.set_color(UI.colors.muted)
    gfx.x, gfx.y = pad + 316, 103
    gfx.drawstr("Lingua")
    local warn = M.lang_warning(speech_model ~= "" and speech_model or (speech_models and speech_models[1]), speech_lang)
    if UI.draw_button({ x = pad + 378, y = 96, w = 170, h = 30, font = 16 }, (warn and "! " or "") .. M.lang_label(speech_lang) .. "  ▾", false, not busy, clicked, "tab") then
      lang_menu()
    end
    if warn then
      gfx.setfont(1, "Arial", 15)
      gfx.set(1.0, 0.72, 0.30, 1)
      gfx.x, gfx.y = pad, 130
      gfx.drawstr(UI.fit_text(warn, gfx.w - pad * 2))
    end
  end

  local steps, next_step = M.road(rows, follow)
  local y = 152
  for i, s in ipairs(steps) do
    draw_step(i, s, i == next_step and not chain, y, clicked)
    y = y + STEP_H
  end

  local pad = 22
  local bw = gfx.w - pad * 2 - 200
  local label = chain and "Sto percorrendo la strada..." or
    (next_step and ("Percorri la strada (da tappa " .. next_step .. ")") or "Strada completa")
  if UI.draw_button({ x = pad, y = y + 4, w = bw, h = 40, font = 17 }, label, chain, not chain and next_step ~= nil, clicked, "play_now") then
    walk_road()
  end
  if UI.draw_button({ x = pad + bw + 10, y = y + 4, w = 190, h = 40, font = 16 },
      texts_visible and "Nascondi tracce testo" or "Mostra tracce testo", texts_visible, true, clicked, "tab") then
    toggle_texts_visible()
  end

  -- Traduci (facoltativo)
  y = y + 50
  do
    local tr_label
    if tr_running then
      local done, total = M.progress_from_log(read_file(tr_running.log))
      tr_label = string.format("Traduco %s%s, %s...", tr_running.job:match("[^/\\]+$") or "",
        done and string.format(" (%d/%d battute)", done, total) or "",
        M.clock(reaper.time_precise() - tr_running.t0)) .. (tr_running.left > 0 and string.format(" poi altri %d", tr_running.left) or "")
    else
      tr_label = "Traduci...   (" .. tr_choice_text() .. ")"
    end
    if UI.draw_button({ x = pad, y = y + 4, w = gfx.w - pad * 2, h = 38, font = 17 }, tr_label, tr_running ~= nil,
        not (running or chain or tr_running) and #rows > 0, clicked, "play_select") then
      translate_menu()
    end
  end

  -- item selezionati
  y = y + 54
  gfx.setfont(1, "Arial", 16)
  UI.set_color(UI.colors.muted)
  gfx.x, gfx.y = pad, y
  gfx.drawstr(#rows == 0 and "Nessun item audio selezionato." or string.format("Item selezionati: %d", #rows))
  y = y + 24
  for i, r in ipairs(rows) do
    if y > gfx.h - 60 then
      UI.set_color(UI.colors.muted); gfx.x, gfx.y = pad, y
      gfx.drawstr(string.format("... e altri %d", #rows - i + 1)); break
    end
    UI.set_color(UI.colors.text)
    gfx.x, gfx.y = pad, y
    gfx.drawstr(UI.fit_text(r.name, gfx.w - pad * 2 - 360))
    UI.set_color(UI.colors.muted)
    gfx.x = gfx.w - pad - 350
    local made = (r.made and r.made ~= "") and (" (" .. r.made .. ")") or ""
    local trs = (r.translations and #r.translations > 0) and (" +" .. table.concat(r.translations, ",")) or ""
    gfx.drawstr(string.format("%s%s%s   marker %d   testi %d", r.srt and "SRT si" or "SRT no", made, trs, r.markers, r.texts))
    y = y + 22
  end

  UI.set_color(UI.colors.title)
  gfx.setfont(1, "Arial", 16)
  gfx.x, gfx.y = pad, gfx.h - 34
  gfx.drawstr(UI.fit_text(status, gfx.w - pad * 2))

  gfx.update()
  reaper.defer(loop)
end

refresh_rows()
loop()
