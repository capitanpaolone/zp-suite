-- @noindex

--[[
  ZP SOLO Recorder - Proof of Concept
  Autore: Paolo Balestri / ZP Studio Suite

  Telecomando operativo per registrazione voiceover in REAPER.

  Funzioni principali:
  - modulo separato, non modifica gli altri script ZP;
  - Folder Mode e' il default;
  - registrazione esclusiva verificata sull'intero progetto;
  - regione Take automatica a ogni registrazione completata;
  - Lane Mode e' previsto come placeholder futuro;
  - always-on-top e Nascondi/Mostra REAPER sono best-effort: servono js_ReaScriptAPI;
  - REAPER non viene mai nascosto da solo, solo col pulsante, e torna su alla chiusura;
  - NEXT TAKE usa la fine reale del nuovo item -> gap 5s -> REC.

  Riferimenti consultati, non usati come librerie:
  - ZP_UI.lua per stile UI;
  - ZP Gobbo / Project Viewer per gfx, ExtState, marker/regioni;
  - Track Navigator mod per focus/finestra;
  - Dfk Custom Toolbar Utility per idea toolbar gfx;
  - ACendan Insert new track respect folders per attenzione a folder depth;
  - BSmith96 Recording per concetto arm dentro folder;
  - FTC Record takes without new splits per confermare che NEXT TAKE complesso e' fuori scope POC.
]]

local SCRIPT_TITLE = "ZP SOLO Recorder"
local SCRIPT_VERSION = "v0.2.0"
local EXT_SECTION = "ZP_SOLO_Recorder"
local PROJ_SECTION = "ZP_SOLO_Recorder_Project"

local FOLDER_NAME = "ZP SOLO SESSION"
local SESSION_VIEW_SECONDS = 120   -- zoom della timeline quando nasce la sessione SOLO
local TRACK_NAMES = {
  main = "VO_MAIN",
  inserts = "VO_INSERTS",
  retakes = "VO_RETAKES",
  alt = "VO_ALT",
  ref = "REF / VIDEO AUDIO"
}
local TRACK_ORDER = { "main", "inserts", "retakes", "alt", "ref" }
local RECORD_TRACK_KEYS = { "main", "inserts", "retakes", "alt" }

local MINI_W, MINI_H = 720, 236
local COMPACT_W, COMPACT_H = 740, 476
local EXPANDED_W, EXPANDED_H = 1000, 660
local TOOLBAR_H = 50   -- una fila: Save/Undo/Redo stanno in testata

local NEXT_TAKE_GAP_SECONDS = 5.0
local PREROLL_MIN, PREROLL_MAX = 1, 5   -- secondi del pre-roll di REAPER
local METER_FLOOR_DB = -60              -- scala dei meter IN e RIT: da -60 a 0 dB
local DEBOUNCE_SECONDS = 0.35
local STOP_REC_SETTLE_SECONDS = 0.45
local EPS = 0.000001

local ACTION = {
  play = 1007,
  pause = 1008,
  record = 1013,
  stop = 1016,
  save_project = 40026,
  undo = 40029,
  redo = 40030,
  toggle_metronome = 40364,
  show_mixer = 40078,
  show_routing = 40293,
  show_fx_chain = 40291,
  region_marker_manager = 40326,
  navigator = 40268,
  video_window = 50125
}

local function script_dir()
  local info = debug.getinfo(1, "S")
  local source = info and info.source or ""
  source = source:gsub("^@", "")
  return source:match("^(.*)[/\\][^/\\]+$") or "."
end

local sep = package.config:sub(1, 1)
local ok_ui, ZP_UI = pcall(dofile, script_dir() .. sep .. "ZP_UI.lua")
if not ok_ui and reaper.GetResourcePath then
  ok_ui, ZP_UI = pcall(dofile, reaper.GetResourcePath() .. sep .. "Scripts" .. sep .. "ZP_Studio_Suite" .. sep .. "ZP_UI.lua")
end
if not ok_ui then ZP_UI = nil end
-- La pulsantiera usa i controlli di ZP_UI (pomelli, interruttori, trasporto): senza, non parte.
if not (ZP_UI and ZP_UI.draw_knob) then
  reaper.MB("Manca ZP_UI.lua aggiornato accanto a questo script.\nReinstalla la ZP Studio Suite da ReaPack.", "ZP SOLO Recorder", 0)
  return
end

local state = {
  mode = "compact",
  pin = true,
  toolbar = false,
  preroll_s = 3,         -- secondi del pre-roll di REAPER (lo accende/spegne il pulsante sul REC)
  folder_mode = true,
  auto_regions = true,   -- crea la regione "Take NNN" a ogni REC
  nav = "regioni",       -- PREV/NEXT/START: "regioni" oppure "item"
  nav_zoom = 0,          -- navigatore: 0 = tutto il progetto, poi finestre sempre piu' corte
  nav_focus = "terzo",   -- testina a 1/3 da sinistra ("terzo") o al centro ("centro")
  fx_session = false,    -- sessione SOLO con le catene di effetti ZP (bus voci + master)
  rec_lock = false,      -- acceso: durante il REC la barra spaziatrice non ferma la registrazione
  active_track_key = "main",
  take_counter = 1,
  status = "Pronto",
  warning = "",
  last_click = {},
  mouse_was_down = false,
  pending = nil,
  mark_text = "",        -- nome del prossimo marker, scritto nella casella di Vai a e segna
  mark_focus = false,    -- la casella sta ricevendo i tasti
  meters = {},           -- meter: valore mostrato e picco trattenuto, per nome
  reaper_hidden = false,
  last_take = nil,
  hint = "",
  last_window_save = 0,
  last_pin_try = 0,
  toolbar_buttons = {},
  record_session = nil,
  ctrls = {},            -- comandi disegnati in questo giro (barra in basso e guida)
  zones = {},            -- zone disegnate in questo giro (guida)
  overlay = false,       -- guida rapida aperta
  overlay_pick = nil     -- comando scelto con un clic nella guida
}

local colors = {
  bg = {0.055, 0.058, 0.066, 1},
  panel = {0.10, 0.105, 0.125, 1},
  border = {0.28, 0.29, 0.34, 1},
  text = {0.92, 0.92, 0.94, 1},
  muted = {0.62, 0.64, 0.70, 1},
  green = {0.09, 0.46, 0.22, 1},
  blue = {0.12, 0.32, 0.54, 1},
  yellow = {0.88, 0.66, 0.20, 1},
  orange = {0.76, 0.32, 0.12, 1},
  red = {0.72, 0.06, 0.04, 1},
  rec = {0.95, 0.02, 0.02, 1},
  -- Telecomando: grigio antracite, cosi' si capisce a colpo d'occhio che non e' la sessione SOLO
  remote_bg = {0.20, 0.21, 0.22, 1},
  remote_panel = {0.27, 0.28, 0.295, 1}
}

local function set_color(c)
  gfx.set(c[1], c[2], c[3], c[4] or 1)
end

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function bool_from_state(value, fallback)
  if value == nil or value == "" then return fallback end
  return value == "1" or value == "true"
end

local function ext_get(key, fallback)
  local value = reaper.GetExtState(EXT_SECTION, key)
  if value == nil or value == "" then return fallback end
  return value
end

local function ext_set(key, value)
  reaper.SetExtState(EXT_SECTION, key, tostring(value or ""), true)
end

local function proj_get(key, fallback)
  local ok, value = reaper.GetProjExtState(0, PROJ_SECTION, key)
  if ok ~= 1 or value == "" then return fallback end
  return value
end

local function proj_set(key, value)
  reaper.SetProjExtState(0, PROJ_SECTION, key, tostring(value or ""))
end

local function load_state()
  state.mode = ext_get("mode", state.mode)
  state.pin = bool_from_state(ext_get("pin", ""), state.pin)
  state.toolbar = bool_from_state(ext_get("toolbar", ""), state.toolbar)
  state.preroll_s = math.max(PREROLL_MIN, math.min(PREROLL_MAX, tonumber(ext_get("preroll_s", "")) or state.preroll_s))
  state.folder_mode = bool_from_state(ext_get("folder_mode", ""), state.folder_mode)
  state.auto_regions = bool_from_state(ext_get("auto_regions", ""), state.auto_regions)
  state.nav = ext_get("nav", state.nav) == "item" and "item" or "regioni"
  state.nav_zoom = tonumber(ext_get("nav_zoom", "")) or state.nav_zoom
  state.nav_focus = ext_get("nav_focus", state.nav_focus) == "centro" and "centro" or "terzo"
  state.fx_session = bool_from_state(ext_get("fx_session", ""), state.fx_session)
  -- "rec_lock2": la chiave vecchia conteneva il default di prima (acceso), non una scelta
  state.rec_lock = bool_from_state(ext_get("rec_lock2", ""), state.rec_lock)
  state.active_track_key = proj_get("active_track_key", state.active_track_key)
  -- Destinazione: "solo" = sessione SOLO (crea le sue tracce); "progetto" = telecomando
  -- (registra sulle tracce che arma l'utente, non crea e non tocca niente).
  -- Prima volta in questo progetto: vuoto o gia' con la sessione SOLO -> solo; altrimenti telecomando.
  local saved_target = proj_get("target", "")
  if saved_target == "solo" or saved_target == "progetto" then
    state.target = saved_target
  else
    local has_solo = false   -- (find_track_exact e' definita piu' sotto: controllo qui)
    for i = 0, reaper.CountTracks(0) - 1 do
      local _, n = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, i), "P_NAME", "", false)
      if n == FOLDER_NAME then has_solo = true break end
    end
    state.target = (reaper.CountTracks(0) == 0 or has_solo) and "solo" or "progetto"
  end
  state.take_counter = tonumber(proj_get("take_counter", "")) or state.take_counter
end

local function save_state()
  ext_set("mode", state.mode)
  ext_set("pin", state.pin and "1" or "0")
  ext_set("toolbar", state.toolbar and "1" or "0")
  ext_set("preroll_s", state.preroll_s)
  ext_set("folder_mode", state.folder_mode and "1" or "0")
  ext_set("auto_regions", state.auto_regions and "1" or "0")
  ext_set("nav", state.nav)
  ext_set("nav_zoom", state.nav_zoom)
  ext_set("nav_focus", state.nav_focus)
  ext_set("fx_session", state.fx_session and "1" or "0")
  ext_set("rec_lock2", state.rec_lock and "1" or "0")
  proj_set("active_track_key", state.active_track_key)
  proj_set("take_counter", state.take_counter)
  proj_set("target", state.target or "solo")
end

local function save_window_state()
  if not gfx or not gfx.dock then return end
  local now = reaper.time_precise()
  if now - state.last_window_save < 0.8 then return end
  state.last_window_save = now
  local dock, x, y, w, h = gfx.dock(-1, 0, 0, 0, 0)
  ext_set("window_dock", dock or 0)
  ext_set("window_x", x or 120)
  ext_set("window_y", y or 120)
  ext_set("window_w", w or gfx.w)
  ext_set("window_h", h or gfx.h)
end

local function speak(text)
  text = tostring(text or "")
  state.status = text
  -- Solo OSARA, se c'e'. Niente console di ReaScript: il messaggio sta gia' nella riga
  -- di stato e la console aperta di continuo e' solo disturbo.
  if reaper.osara_outputMessage then reaper.osara_outputMessage(text) end
end

local function warn(text)
  state.warning = tostring(text or "")
  speak(text)
end

local function point_in_rect(px, py, x, y, w, h)
  if ZP_UI and ZP_UI.point_in_rect then return ZP_UI.point_in_rect(px, py, x, y, w, h) end
  return px >= x and px <= x + w and py >= y and py <= y + h
end

local function fit_text(text, max_w)
  text = tostring(text or "")
  if ZP_UI and ZP_UI.fit_text then return ZP_UI.fit_text(text, max_w) end
  if gfx.measurestr(text) <= max_w then return text end
  local suffix = "..."
  local out = ""
  for i = 1, #text do
    local candidate = text:sub(1, i)
    if gfx.measurestr(candidate) + gfx.measurestr(suffix) > max_w then break end
    out = candidate
  end
  return trim(out) .. suffix
end

local function mouse_clicked()
  return (gfx.mouse_cap & 1) == 0 and state.mouse_was_down
end

local function draw_fallback_button(rect, label, active, enabled, clicked, style)
  enabled = enabled ~= false
  local hover = enabled and point_in_rect(gfx.mouse_x, gfx.mouse_y, rect.x, rect.y, rect.w, rect.h)
  local fill = colors.panel
  if style == "danger" or style == "stop" or style == "rec" then fill = active and colors.rec or colors.red
  elseif style == "play" or style == "save" then fill = active and colors.green or colors.green
  elseif style == "tab" or active then fill = colors.blue
  elseif hover then fill = {0.18, 0.19, 0.23, 1} end
  if not enabled then fill = {0.09, 0.09, 0.10, 1} end
  set_color(fill)
  gfx.rect(rect.x, rect.y, rect.w, rect.h, true)
  set_color(colors.border)
  gfx.rect(rect.x, rect.y, rect.w, rect.h, false)
  gfx.setfont(1, "Arial", rect.h <= 26 and 13 or 15, "b")
  gfx.set(enabled and 0.96 or 0.45, enabled and 0.96 or 0.45, enabled and 0.97 or 0.45, 1)
  local label_out = fit_text(label, rect.w - 14)
  local tw, th = gfx.measurestr(label_out)
  gfx.x = rect.x + math.max(6, (rect.w - tw) * 0.5)
  gfx.y = rect.y + math.max(4, (rect.h - th) * 0.5)
  gfx.drawstr(label_out)
  return clicked and enabled and hover
end

local function draw_button(rect, label, active, enabled, clicked, style)
  if ZP_UI and ZP_UI.draw_button and style ~= "rec" then
    return ZP_UI.draw_button(rect, label, active, enabled, clicked, style)
  end
  return draw_fallback_button(rect, label, active, enabled, clicked, style)
end

-- Spiegazioni dei comandi, per chiave stabile (non per etichetta, che cambia).
-- AIUTI: una riga, nella barra in basso quando passi col mouse.
-- DETTAGLI: la spiegazione lunga dell'overlay della guida (?). Se manca, vale AIUTI.
local AIUTI = {
  ["Mini"] = "Vista Mini: trasporto, ingresso e ascolto.",
  ["Compact"] = "Vista Compact: anche tracce, spostamenti, marker e sessione.",
  ["Expanded"] = "Vista Expanded: anche take, etichette e navigatore.",
  ["REAPER"] = "Nasconde o rimette su la finestra di REAPER, senza cercarla nel Dock.",
  ["?"] = "Guida rapida: numera le zone e spiega ogni comando. Clic di nuovo per chiuderla.",
  ["REC"] = "Registra sulla traccia scelta, dopo aver verificato che sia l'unica armata.",
  ["Lock"] = "Lucchetto del REC: acceso, la barra spaziatrice non ferma la registrazione. Clic: cambia.",
  ["STOP"] = "Ferma la registrazione o la riproduzione e numera il take appena inciso.",
  ["PLAY"] = "Riproduce dalla posizione del cursore.",
  ["-5s"] = "Sposta il cursore indietro di cinque secondi.",
  ["fine +5s"] = "Porta il cursore cinque secondi dopo la fine dell'ultimo item. Non cancella niente.",
  ["Ingresso"] = "Da quale ingresso della scheda pesca la traccia. Clic: cambia ingresso.",
  ["Monitor"] = "Ascolto dell'ingresso sulla traccia attiva. Clic: acceso / spento.",
  ["Ritorno"] = "Volume della traccia selezionata in REAPER (reference o video). Trascina o rotella.",
  ["Pre-roll"] = "Pre-roll di REAPER sul REC: riparte qualche secondo prima e registra dal cursore. Clic: acceso / spento.",
  ["Secondi pre-roll"] = "Secondi del pre-roll, da 1 a 5: - e +, oppure la rotella. La spia gialla dice che e' acceso.",
  ["IN"] = "Livello dell'ingresso della scheda da cui registri, in dB. La riga chiara e' il picco.",
  ["RIT"] = "Livello del master, cioe' quello che senti, in dB.",
  ["MAIN"] = "Registra sulla traccia principale VO_MAIN.",
  ["INSERTS"] = "Registra sulla traccia degli inserti.",
  ["RETAKES"] = "Registra sulla traccia dei rifacimenti.",
  ["ALT"] = "Registra sulla traccia delle versioni alternative.",
  ["Telecomando"] = "Telecomando: registra sulle tracce del tuo progetto, non crea le tracce SOLO.",
  ["Sessione"] = "Sessione SOLO: la cartella ZP SOLO SESSION con le sue tracce voce.",
  ["Tracce"] = "Tracce del progetto con il loro ingresso: un clic arma o disarma.",
  ["Regioni"] = "Precedente / inizio / successivo si muovono tra le regioni.",
  ["Item"] = "Precedente / inizio / successivo si muovono tra gli item della traccia di destinazione.",
  ["Precedente"] = "Cursore alla regione (o all'item) precedente.",
  ["Inizio"] = "Cursore all'inizio della regione (o dell'item) in cui ti trovi.",
  ["Successivo"] = "Cursore alla regione (o all'item) successiva.",
  ["Mark"] = "Mette un marker qui: col nome scritto nella casella accanto, se c'e', altrimenti numerato.",
  ["Nome marker"] = "Scrivi il nome del marker e premi Invio (o il pulsante marker). Esc lascia perdere.",
  ["Nome / nota"] = "Rinomina l'ultima regione take, per annotarci com'e' andata.",
  ["Next take"] = "Chiude il take, lascia cinque secondi di stacco e riparte a registrare.",
  ["Togli take"] = "Toglie dalla timeline il take appena registrato. Il file resta nella cartella Media.",
  ["Retake"] = "Rifa' la regione corrente sulla traccia dei retake.",
  ["Insert"] = "Registra un inserto senza toccare quello che c'e' gia'.",
  ["Alt take"] = "Registra una versione alternativa sulla traccia ALT.",
  ["OK"] = "Marker OK: questo punto e' buono.",
  ["BAD"] = "Marker BAD: questo punto e' da rifare.",
  ["ALT marker"] = "Marker ALT: qui c'e' una versione alternativa.",
  ["NOISE"] = "Marker NOISE: c'e' un rumore da sistemare.",
  ["Regioni take"] = "A ogni REC crea la regione Take NNN sul nuovo audio. Clic: acceso / spento.",
  ["Effetti"] = "Sessione SOLO con le catene ZP sul bus voci e sul master. Clic: acceso / spento.",
  ["Pin"] = "Pin: tiene questa finestra sempre sopra le altre. Clic: acceso / spento.",
  ["Toolbar"] = "Mostra o nasconde la fila di comandi REAPER in fondo al pannello (non in Mini).",
  ["Video"] = "Apre e chiude la finestra video di REAPER.",
  ["Zoom"] = "Quanto tempo mostra il navigatore: da tutto il progetto a 10 secondi.",
  ["1/3"] = "Testina a un terzo da sinistra: vedi di piu' di quello che arriva.",
  ["centro"] = "Testina al centro della striscia.",
  ["Navigatore"] = "Clic o trascina per spostare il cursore (fermo durante il REC).",
  ["Guida completa"] = "Apre la pagina di help del SOLO Recorder nel browser.",
  ["Save"] = "Salva il progetto.",
  ["Undo"] = "Annulla l'ultima operazione di REAPER.",
  ["Redo"] = "Ripete l'operazione annullata.",
  ["Metro"] = "Accende o spegne il metronomo.",
  ["Mixer"] = "Apre il mixer di REAPER.",
  ["Routing"] = "Apre il routing della traccia selezionata.",
  ["FX Chain"] = "Apre la catena effetti della traccia selezionata.",
  ["Notes"] = "Apre le note del progetto (finestra Notes di SWS; senza SWS, Project settings).",
  ["Markers"] = "Apre il gestore di marker e regioni.",
  ["Navigator"] = "Apre il Navigator di REAPER.",
}

local DETTAGLI = {
  ["REC"] = "Registra sulla traccia di destinazione (zona 4). Prima controlla che sia l'unica armata. Con il pre-roll acceso (PRE sul bordo del REC) REAPER riparte qualche secondo prima e registra dal cursore. In Telecomando, se non c'e' nessuna traccia armata, ti chiede quale armare.",
  ["Lock"] = "Il lucchetto sul REC protegge la registrazione. Parte spento. Acceso (giallo, chiuso): durante il REC la barra spaziatrice non ferma niente, solo il pulsante STOP. Spento (grigio, aperto): la barra ferma anche il REC, come in REAPER. Vale quando la finestra del SOLO e' in primo piano.",
  ["STOP"] = "Ferma la registrazione o la riproduzione. Dopo un REC numera il take e, se Regioni take e' acceso, crea la sua regione.",
  ["Ritorno"] = "Volume della traccia selezionata in REAPER: di solito la reference o l'audio del video. Trascina in su o in giu' (con Shift e' piu' fine), oppure usa la rotella; doppio clic = 0 dB. E' un cambio di mix vero: resta nel progetto.",
  ["Pre-roll"] = "Il pre-roll e' quello di REAPER (Options > Metronome/pre-roll, 'Pre-roll before recording'): premuto REC, la riproduzione parte qualche secondo prima del cursore, cosi' senti l'attacco, e la registrazione comincia dal cursore. PRE sul bordo sinistro del REC lo accende (giallo) e lo spegne. I secondi, da 1 a 5, si regolano in Sessione e finestra. REAPER lo misura in battute: il SOLO converte i secondi al tempo del progetto a ogni REC. Serve SWS. E' un'impostazione di REAPER: vale anche fuori dal SOLO.",
  ["IN"] = "Il livello vero dell'ingresso della scheda audio da cui registra la traccia, prima di effetti, fader e monitor: e' quello che finisce nel file. Scala in dB da -60 a 0, tacche a -18 e -6: verde fino a -18, giallo fino a -6, poi arancio e rosso sopra -1. La riga chiara e' il picco, che resta fermo un secondo e mezzo; a destra il suo valore. Per MIDI o ReaRoute mostra il meter della traccia.",
  ["Nome marker"] = "Clic nella casella e scrivi il nome: mentre scrivi i tasti vanno li' (anche la barra spaziatrice). Invio, o il pulsante marker, mette il marker nel punto in cui sei con quel nome; Esc lascia perdere. Casella vuota: il marker e' di servizio e numerato (SOLO_MARK_001...). Un marker col nome tuo e' un marker normale: se vuoi che resti di servizio, comincialo con #.",
  ["Ingresso"] = "L'ingresso della scheda audio da cui registra la traccia di destinazione: In 1, In 1/2 per lo stereo, e cosi' via. Clic: scegli da un elenco.",
  ["Monitor"] = "Ascolto in cuffia dell'ingresso sulla traccia attiva. Auto vuol dire che REAPER lo accende da solo quando la traccia e' armata.",
  ["Sessione"] = "Sessione SOLO: il SOLO lavora nella sua cartella ZP SOLO SESSION, con le tracce MAIN, INSERTS, RETAKES e ALT; arma solo quella scelta. La spia accesa dice in che modalita' sei; clic sull'altra per cambiare.",
  ["Telecomando"] = "Telecomando: il SOLO registra sulle tracce del tuo progetto, quelle che armi tu. Non crea la cartella SOLO e non cambia l'armamento. Retake, Insert, Alt take ed Effetti qui sono spenti, perche' usano le tracce della sessione SOLO.",
  ["Next take"] = "Chiude il take in corso, lascia cinque secondi di stacco dopo la fine reale dell'audio e riparte subito a registrare.",
  ["Togli take"] = "Toglie dalla timeline il take appena registrato (e la sua regione) e riporta il cursore dov'era. Il file audio resta nella cartella Media: se serve, lo ritrovi.",
  ["Regioni take"] = "Acceso: a ogni REC crea la regione Take NNN sopra il nuovo audio, utile per rinominare e ritrovare i take. Spento: registra senza regioni; Togli take funziona lo stesso.",
  ["Effetti"] = "Acceso: quando nasce la sessione SOLO inserisce ZP Bus VoiceChain sul bus delle voci e ZP MasterChain sul master. Le catene le installa il comando 32. Non le duplica se ci sono gia'. Spegnendo, quelle gia' inserite restano.",
  ["Zoom"] = "Quanto tempo mostra il navigatore: tutto il progetto, poi 10, 5, 2, 1 minuto, 30 e 10 secondi. Con lo zoom la striscia segue la testina. Trascina o rotella; doppio clic = tutto.",
  ["Navigatore"] = "Tutto il progetto (o la finestra di zoom) in una striscia: in alto, tenui, gli item di tutte le tracce; in verde quelli della traccia di destinazione. Regioni in blu, marker in giallo, il riquadro e' la parte visibile della timeline. Clic o trascina per spostare il cursore; durante il REC non si muove.",
  ["Pin"] = "Tiene la finestra del SOLO sempre sopra le altre (serve js_ReaScriptAPI). Sta in testata, cosi' c'e' anche in Mini.",
}

-- Le zone, come le numera la guida.
local ZONE_AIUTO = {
  testata = "Stato del trasporto, timecode, traccia, regione, take e pre-roll. A sinistra Save, Undo, Redo, Pin e Toolbar; a destra le tre viste, REAPER e questa guida. C'e' in ogni vista.",
  trasporto = "I comandi di ogni secondo. REC e' il piu' grande; sul suo bordo PRE accende il pre-roll di REAPER e il lucchetto decide se la barra spaziatrice puo' fermarlo.",
  ingresso = "Cosa entra e cosa senti: meter dell'ingresso e del ritorno, da dove pesca la traccia, monitor. Il pomello regola il ritorno.",
  traccia = "Dove registri. A destra il selettore Sessione / Telecomando: la meta' accesa e' la modalita' in uso.",
  vai = "Muoversi tra regioni o item, e mettere marker: il pulsante col simbolo marker, e accanto la casella per dargli un nome.",
  take = "In alto i comandi che registrano (pallino rosso): Next take, Retake, Insert, Alt take. Sotto quelli che gestiscono il take appena fatto: Nome / nota e Togli take.",
  etichette = "Marker di giudizio nel punto in cui sei: OK, BAD, ALT, NOISE.",
  navigatore = "Il progetto in una striscia. Lo zoom e la posizione della testina sono in alto a destra.",
  sessione = "Interruttori della sessione e della finestra (la spia verde vuol dire acceso) e i secondi del pre-roll.",
}

local function aiuto_per(key)
  return AIUTI[key]
end

local function sotto_il_mouse(rect)
  local mx, my = gfx.mouse_x, gfx.mouse_y
  return mx >= rect.x and mx <= rect.x + rect.w and my >= rect.y and my <= rect.y + rect.h
end

-- Ogni comando disegnato si annota qui: la barra in basso e la guida sanno cosa c'e' sotto il mouse.
local function note(rect, key, text)
  state.ctrls[#state.ctrls + 1] = { rect = rect, key = key, text = text }
  if sotto_il_mouse(rect) then
    local testo = text or aiuto_per(key)
    if testo then state.hint = testo end
  end
end

local function btn(rect, label, active, enabled, clicked, style, key, text)
  note(rect, key or label, text)
  return draw_button(rect, label, active, enabled, clicked, style)
end

local function transport_state()
  local ps = reaper.GetPlayState()
  local recording = (ps & 4) == 4
  local paused = (ps & 2) == 2
  local playing = (ps & 1) == 1
  if recording then return "REC", ps end
  if paused then return "PAUSE", ps end
  if playing then return "PLAY", ps end
  return "STOP", ps
end

local function current_position()
  local label, ps = transport_state()
  if label == "PLAY" or label == "REC" then return reaper.GetPlayPosition() end
  return reaper.GetCursorPosition()
end

local function format_time(pos)
  if reaper.format_timestr_pos then return reaper.format_timestr_pos(pos or 0, "", 5) end
  local s = math.max(0, pos or 0)
  local h = math.floor(s / 3600)
  local m = math.floor((s - h * 3600) / 60)
  local sec = s - h * 3600 - m * 60
  return string.format("%02d:%02d:%06.3f", h, m, sec)
end

local function track_name(track)
  if not track then return "" end
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  return name or ""
end

local function find_track_exact(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    if track_name(track) == name then return track, i end
  end
  return nil, nil
end

local function track_index(track)
  if not track then return nil end
  local ptr = tostring(track)
  for i = 0, reaper.CountTracks(0) - 1 do
    local current = reaper.GetTrack(0, i)
    if tostring(current) == ptr then return i end
  end
  return nil
end

local function set_track_name(track, name)
  if track then reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true) end
end

local function native_color(r, g, b)
  return reaper.ColorToNative(r, g, b) | 0x1000000
end

local function set_track_color(track, r, g, b)
  if track then reaper.SetTrackColor(track, native_color(r, g, b)) end
end

local function find_folder_end(folder)
  local start_idx = track_index(folder)
  if not start_idx then return nil end
  local depth = 1
  for i = start_idx + 1, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    depth = depth + math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0)
    if depth <= 0 then return i end
  end
  return reaper.CountTracks(0) - 1
end

local function insert_named_track(index, name, color)
  reaper.InsertTrackAtIndex(index, true)
  local track = reaper.GetTrack(0, index)
  set_track_name(track, name)
  if color then set_track_color(track, color[1], color[2], color[3]) end
  return track
end

local function solo_tracks()
  local out = {}
  for _, key in ipairs(TRACK_ORDER) do
    local tr = find_track_exact(TRACK_NAMES[key])
    if tr then out[key] = tr end
  end
  return out
end

local function normalize_solo_folder_depths(tracks)
  local folder = find_track_exact(FOLDER_NAME)
  if not folder then return end
  reaper.SetMediaTrackInfo_Value(folder, "I_FOLDERDEPTH", 1)
  local last_key = nil
  for _, key in ipairs(TRACK_ORDER) do
    if tracks[key] then last_key = key end
  end
  for _, key in ipairs(TRACK_ORDER) do
    if tracks[key] then
      reaper.SetMediaTrackInfo_Value(tracks[key], "I_FOLDERDEPTH", key == last_key and -1 or 0)
    end
  end
end

-- Sessione con effetti: due catene salvate in REAPER/FXChains. La cartella ZP SOLO SESSION
-- fa da bus delle voci; la seconda va sul master.
local FX_CHAIN_BUS = "ZP Bus VoiceChain.RfxChain"
local FX_CHAIN_MASTER = "ZP MasterChain.RfxChain"

local function read_fx_chain(name)
  local path = reaper.GetResourcePath() .. "/FXChains/" .. name
  local f = io.open(path, "rb")
  if not f then return nil, "manca " .. name .. " (lancia 32 Installa toolbar ed effetti)" end
  local text = f:read("*a"); f:close()
  local out = {}
  -- via gli FXID: REAPER ne assegna di nuovi, cosi' non ci sono doppioni
  for line in (text:gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do
    if not line:match("^%s*FXID ") then out[#out + 1] = line end
  end
  return table.concat(out, "\n")
end

local function track_has_fx(track, needle)
  for i = 0, reaper.TrackFX_GetCount(track) - 1 do
    local _, name = reaper.TrackFX_GetFXName(track, i, "")
    if (name or ""):lower():find(needle:lower(), 1, true) then return true end
  end
  return false
end

-- L'API non carica i file .RfxChain: la catena passa da una traccia temporanea
-- (blocco FXCHAIN nel suo stato) e gli effetti si spostano, con i loro parametri,
-- sulla traccia di destinazione (anche il master). Poi la temporanea sparisce.
local function load_fx_chain(dest, name)
  local chain, err = read_fx_chain(name)
  if not chain then return nil, err end
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, false)
  local tmp = reaper.GetTrack(0, idx)
  local _, chunk = reaper.GetTrackStateChunk(tmp, "", false)
  chunk = chunk:gsub(">%s*$", "<FXCHAIN\nSHOW 0\nLASTSEL 0\nDOCKED 0\n" .. chain .. "\n>\n>\n")
  reaper.SetTrackStateChunk(tmp, chunk, false)
  local n = reaper.TrackFX_GetCount(tmp)
  for _ = 1, n do
    reaper.TrackFX_CopyToTrack(tmp, 0, dest, reaper.TrackFX_GetCount(dest), true)
  end
  reaper.DeleteTrack(tmp)
  return n
end

local function apply_fx_session()
  local folder = find_track_exact(FOLDER_NAME)
  if not folder then return false end
  local parts = {}
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  if track_has_fx(folder, "ZP BUS Chain") then
    parts[#parts + 1] = "bus voci gia' pronto"
  else
    local n, err = load_fx_chain(folder, FX_CHAIN_BUS)
    parts[#parts + 1] = n and ("bus voci: " .. n .. " effetti") or ("bus voci: " .. err)
  end
  local master = reaper.GetMasterTrack(0)
  if track_has_fx(master, "ZP Master Pro") then
    parts[#parts + 1] = "master gia' pronto"
  else
    local n, err = load_fx_chain(master, FX_CHAIN_MASTER)
    parts[#parts + 1] = n and ("master: " .. n .. " effetti") or ("master: " .. err)
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ZP SOLO: effetti della sessione (bus voci + master)", -1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  state.status = "Effetti: " .. table.concat(parts, " - ")
  return true
end

local function ensure_solo_structure()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local folder, folder_idx = find_track_exact(FOLDER_NAME)
  local created = not folder
  if not folder then
    local idx = reaper.CountTracks(0)
    folder = insert_named_track(idx, FOLDER_NAME, {50, 145, 170})
    folder_idx = idx
    for offset, key in ipairs(TRACK_ORDER) do
      local tr = insert_named_track(folder_idx + offset, TRACK_NAMES[key], ({ 
        main = {80, 185, 110}, inserts = {240, 170, 60}, retakes = {215, 95, 70}, alt = {145, 115, 210}, ref = {92, 155, 215}
      })[key])
      reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 1)
      reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 1)
    end
  else
    local tracks = solo_tracks()
    local insert_at = (find_folder_end(folder) or folder_idx) + 1
    for _, key in ipairs(TRACK_ORDER) do
      if not tracks[key] then
        tracks[key] = insert_named_track(insert_at, TRACK_NAMES[key], nil)
        insert_at = insert_at + 1
      end
    end
  end

  normalize_solo_folder_depths(solo_tracks())
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ZP SOLO Recorder: crea/trova struttura SOLO", -1)
  if created then
    -- Solo vista: alla nascita della sessione la timeline mostra circa 2 minuti dal cursore
    -- (su un REAPER vuoto lo zoom di partenza e' troppo largo). Non cambia nient'altro.
    local start = math.max(0, reaper.GetCursorPosition() - 5)
    reaper.GetSet_ArrangeView2(0, true, 0, 0, start, start + SESSION_VIEW_SECONDS)
    if state.fx_session then apply_fx_session() end
  end
  reaper.UpdateArrange()
  return solo_tracks()
end

local function remote_mode()
  return state.target == "progetto"
end

-- Telecomando: tracce armate dall'utente nel progetto, nell'ordine delle tracce.
local function armed_tracks()
  local out = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1 then out[#out + 1] = tr end
  end
  return out
end

local function active_track()
  if remote_mode() then
    local armed = armed_tracks()
    if not armed[1] then return nil, "nessuna traccia armata" end
    local name = track_name(armed[1])
    if #armed > 1 then name = name .. " + " .. tostring(#armed - 1) end
    return armed[1], name
  end
  local tracks = solo_tracks()
  return tracks[state.active_track_key], TRACK_NAMES[state.active_track_key]
end

-- Telecomando: arma la traccia selezionata in REAPER. Non disarma le altre: l'armamento
-- del progetto resta dell'utente.
local function arm_selected_track()
  local tr = reaper.GetSelectedTrack(0, 0)
  if not tr then return nil end
  reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", 1)
  if reaper.GetMediaTrackInfo_Value(tr, "I_RECINPUT") < 0 then
    reaper.SetMediaTrackInfo_Value(tr, "I_RECINPUT", 0)
  end
  return tr
end

-- Ingresso di registrazione (I_RECINPUT): -1 nessuno; &4096 MIDI; &1024 stereo;
-- &2048 multicanale; indice & 1023 (da 512 in su = ReaRoute).
local function input_short(track)
  if not track then return "-" end
  local v = math.floor(reaper.GetMediaTrackInfo_Value(track, "I_RECINPUT") or -1)
  if v < 0 then return "nessun ingresso" end
  if v & 4096 ~= 0 then return "MIDI" end
  local idx = v & 1023
  if idx >= 512 then return "ReaRoute " .. tostring(idx - 512 + 1) end
  if v & 2048 ~= 0 then return "In " .. tostring(idx + 1) .. "+ multi" end
  if v & 1024 ~= 0 then return "In " .. tostring(idx + 1) .. "/" .. tostring(idx + 2) end
  return "In " .. tostring(idx + 1)
end

local function input_long(track)
  local short = input_short(track)
  if not track then return short end
  local v = math.floor(reaper.GetMediaTrackInfo_Value(track, "I_RECINPUT") or -1)
  if v >= 0 and v & 4096 == 0 and (v & 1023) < 512 and reaper.GetInputChannelName then
    local name = reaper.GetInputChannelName(v & 1023)
    if name and name ~= "" and name ~= short then return short .. " (" .. name .. ")" end
  end
  return short
end

local function menu_safe(text)
  return (tostring(text):gsub("[|#!<>]", " "))
end

-- Menu degli ingressi della scheda audio per la traccia: mono, poi coppie stereo.
local function choose_input(track)
  if not track then warn("Nessuna traccia di destinazione."); return end
  local n = reaper.GetNumAudioInputs and reaper.GetNumAudioInputs() or 0
  local current = math.floor(reaper.GetMediaTrackInfo_Value(track, "I_RECINPUT") or -1)
  local entries, values = {}, {}
  local function add(label, value)
    entries[#entries + 1] = (value == current and "!" or "") .. menu_safe(label)
    values[#values + 1] = value
  end
  for i = 0, n - 1 do
    local name = reaper.GetInputChannelName and reaper.GetInputChannelName(i) or ""
    add("In " .. (i + 1) .. ((name ~= "" and name ~= ("In " .. (i + 1))) and ("   " .. name) or ""), i)
  end
  for i = 0, n - 2, 2 do add("Stereo In " .. (i + 1) .. "/" .. (i + 2), 1024 + i) end
  add("Nessun ingresso", -1)
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local choice = gfx.showmenu(table.concat(entries, "|"))
  local v = values[choice or 0]
  if v ~= nil then
    reaper.SetMediaTrackInfo_Value(track, "I_RECINPUT", v)
    state.status = "Ingresso di " .. track_name(track) .. ": " .. input_long(track)
  end
end

-- Telecomando: elenco delle tracce del progetto, armate spuntate, con l'ingresso.
-- Un clic arma o disarma quella traccia (le altre restano come sono).
local function choose_tracks_menu()
  local n = reaper.CountTracks(0)
  if n == 0 then warn("Il progetto non ha tracce."); return end
  local selected = reaper.GetSelectedTrack(0, 0)
  local entries, tracks = {}, {}
  for i = 0, n - 1 do
    local tr = reaper.GetTrack(0, i)
    local name = track_name(tr); if name == "" then name = "(senza nome)" end
    local armed = reaper.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1
    entries[#entries + 1] = (armed and "!" or "") .. menu_safe(string.format("%d   %s   ·   %s%s",
      i + 1, name, input_short(tr), tr == selected and "   (selezionata)" or ""))
    tracks[#tracks + 1] = tr
  end
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local tr = tracks[gfx.showmenu(table.concat(entries, "|")) or 0]
  if not tr then return end
  local arm = reaper.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1 and 0 or 1
  reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", arm)
  if arm == 1 and reaper.GetMediaTrackInfo_Value(tr, "I_RECINPUT") < 0 then
    reaper.SetMediaTrackInfo_Value(tr, "I_RECINPUT", 0)
  end
  state.warning = ""
  state.status = (arm == 1 and "Armata: " or "Disarmata: ") .. track_name(tr) .. " · " .. input_long(tr)
end

-- Telecomando, REC senza tracce armate: chiede su quale registrare invece di indovinare.
-- Menu con le tracce del progetto, la selezionata gia' spuntata; niente scelta = niente REC.
local function choose_track_to_arm()
  local n = reaper.CountTracks(0)
  if n == 0 then
    warn("Telecomando: il progetto non ha tracce su cui registrare.")
    return nil
  end
  local selected = reaper.GetSelectedTrack(0, 0)
  local entries, tracks = { "#Nessuna traccia armata: su quale registro?" }, {}
  for i = 0, n - 1 do
    local tr = reaper.GetTrack(0, i)
    local name = track_name(tr)
    if name == "" then name = "(senza nome)" end
    name = name:gsub("[|#!<>]", " ")
    entries[#entries + 1] = (tr == selected and "!" or "") .. menu_safe(string.format("%d   %s   ·   %s", i + 1, name, input_short(tr)))
    tracks[#tracks + 1] = tr
  end
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local choice = gfx.showmenu(table.concat(entries, "|"))
  local tr = tracks[(choice or 0) - 1]   -- la prima voce e' il titolo
  if not tr then
    warn("REC annullato: nessuna traccia scelta.")
    return nil
  end
  reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", 1)
  if reaper.GetMediaTrackInfo_Value(tr, "I_RECINPUT") < 0 then
    reaper.SetMediaTrackInfo_Value(tr, "I_RECINPUT", 0)
  end
  reaper.SetOnlyTrackSelected(tr)
  return tr
end

local function target_name()
  local _, name = active_track()
  return name or "?"
end

local function set_target(mode)
  state.target = mode
  proj_set("target", mode)
  state.warning = ""
  state.status = mode == "progetto"
    and "Telecomando: registra sulle tracce che armi tu nel progetto. Non crea tracce."
    or "Sessione SOLO: al primo REC crea la cartella ZP SOLO SESSION con le sue tracce."
end

local function set_active_track_key(key)
  if not TRACK_NAMES[key] then return false end
  state.active_track_key = key
  proj_set("active_track_key", key)
  return true
end

local function arm_only_solo_target(key)
  if remote_mode() then
    local armed = armed_tracks()
    if not armed[1] then
      if not choose_track_to_arm() then return nil end
      armed = armed_tracks()
    end
    state.status = "REC READY — " .. target_name()
    return armed[1]
  end
  local tracks = ensure_solo_structure()
  local target = tracks[key]
  if not target then warn("Traccia SOLO non trovata: " .. tostring(TRACK_NAMES[key] or key)); return nil end
  -- L'esclusivita' riguarda l'intero progetto, non soltanto le tracce SOLO.
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", tr == target and 1 or 0)
  end
  reaper.SetMediaTrackInfo_Value(target, "I_RECMON", 1)
  if reaper.GetMediaTrackInfo_Value(target, "I_RECINPUT") < 0 then
    reaper.SetMediaTrackInfo_Value(target, "I_RECINPUT", 0)
  end
  reaper.SetOnlyTrackSelected(target)
  set_active_track_key(key)
  local armed_count, armed_target = 0, false
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1 then
      armed_count = armed_count + 1
      armed_target = armed_target or tr == target
    end
  end
  if armed_count ~= 1 or not armed_target then
    warn("REC BLOCCATO: impossibile garantire la registrazione esclusiva.")
    return nil
  end
  state.status = "REC READY — " .. TRACK_NAMES[key]
  return target
end

local function item_guid(item)
  if not item then return nil end
  local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  return guid
end

local function snapshot_items()
  local seen = {}
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local guid = item_guid(reaper.GetMediaItem(0, i))
    if guid then seen[guid] = true end
  end
  return seen
end

local function last_item_end()
  local last_end = nil
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local item = reaper.GetMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_end = pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if not last_end or item_end > last_end then last_end = item_end end
  end
  return last_end
end

local function can_click(id)
  local now = reaper.time_precise()
  local last = state.last_click[id] or 0
  if now - last < DEBOUNCE_SECONDS then return false end
  state.last_click[id] = now
  return true
end

-- Pre-roll: e' quello di REAPER (Opzioni > Metronome/pre-roll), non un conto alla rovescia.
-- Nel config "preroll" il bit 2 lo accende sul REC; "prerollmeas" e' la durata in MISURE.
-- Il SOLO ragiona in secondi e li converte al tempo del punto in cui registri (a ogni REC,
-- perche' il tempo del progetto puo' cambiare). Leggere e scrivere il config richiede SWS.
local function preroll_api()
  return reaper.SNM_GetIntConfigVar and reaper.SNM_SetIntConfigVar and reaper.SNM_SetDoubleConfigVar
end

local function preroll_on()
  if not preroll_api() then return false end
  return (math.floor(reaper.SNM_GetIntConfigVar("preroll", 0)) & 2) == 2
end

local function measure_seconds(pos)
  local num, denom, bpm = reaper.TimeMap_GetTimeSigAtTime(0, pos)
  num, denom, bpm = tonumber(num) or 4, tonumber(denom) or 4, tonumber(bpm) or 120
  if num <= 0 or denom <= 0 or bpm <= 0 then return 2.0 end
  return num * (4 / denom) * (60 / bpm)
end

local function apply_preroll_seconds()
  if not preroll_api() then return false end
  reaper.SNM_SetDoubleConfigVar("prerollmeas", state.preroll_s / measure_seconds(current_position()))
  return true
end

local function preroll_label()
  if not preroll_api() then return "Pre-roll: serve SWS" end
  return preroll_on() and ("Pre-roll " .. state.preroll_s .. " s") or "Pre-roll off"
end

local function toggle_preroll()
  if not preroll_api() then
    warn("Il pre-roll si regola con SWS: installalo da ReaPack, oppure Opzioni > Metronome/pre-roll di REAPER.")
    return
  end
  local v = math.floor(reaper.SNM_GetIntConfigVar("preroll", 0))
  local on = (v & 2) == 0
  if on then apply_preroll_seconds() end
  reaper.SNM_SetIntConfigVar("preroll", on and (v | 2) or (v & ~2))
  speak(on and ("Pre-roll acceso: il REC riparte " .. state.preroll_s .. " secondi prima, e registra dal cursore.")
    or "Pre-roll spento: il REC parte dal cursore.")
end

local function set_preroll_seconds(sec)
  sec = math.max(PREROLL_MIN, math.min(PREROLL_MAX, math.floor(sec + 0.5)))
  if sec == state.preroll_s then return end
  state.preroll_s = sec
  save_state()
  apply_preroll_seconds()
  state.status = "Pre-roll: " .. sec .. " s" .. (preroll_on() and "" or " (spento: accendilo dal pulsante sul REC)")
end

local function do_record_now()
  if (reaper.GetPlayState() & 4) == 4 then
    speak("REC gia' attivo.")
    return
  end
  local target = arm_only_solo_target(state.active_track_key)
  if not target then return end
  state.record_session = {
    before = snapshot_items(),
    track = target,
    track_key = state.active_track_key,
    started_at = reaper.GetCursorPosition()
  }
  if preroll_on() then apply_preroll_seconds() end
  reaper.Main_OnCommand(ACTION.record, 0)
  if (reaper.GetPlayState() & 4) ~= 4 then
    state.record_session = nil
    warn("REC BLOCCATO: REAPER non ha avviato la registrazione.")
    return
  end
  state.status = "● REC — " .. target_name()
end

local function record_on_track(key, label)
  if not can_click("record_" .. key) then return end
  if (reaper.GetPlayState() & 4) == 4 then
    speak("REAPER sta gia' registrando.")
    return
  end
  if not arm_only_solo_target(key) then return end
  do_record_now()
end

local function stop_transport()
  if not can_click("stop") then return end
  local was_recording = (reaper.GetPlayState() & 4) == 4
  reaper.Main_OnCommand(ACTION.stop, 0)
  if was_recording and state.record_session then
    state.pending = { kind = "finalize_recording", due = reaper.time_precise() + STOP_REC_SETTLE_SECONDS,
      session = state.record_session }
    state.record_session = nil
    state.status = "STOP — preparo indice take"
  else
    state.status = "STOP"
  end
end

local function play_transport()
  if not can_click("play") then return end
  if (reaper.GetPlayState() & 4) == 4 then
    warn("STOP prima del PLAY: registrazione in corso.")
    return
  end
  reaper.Main_OnCommand(ACTION.play, 0)
  state.status = "PLAY"
end

local function pause_transport()
  if not can_click("pause") then return end
  reaper.Main_OnCommand(ACTION.pause, 0)
  state.status = "PAUSE"
end

local function move_cursor(delta)
  if not can_click("move_" .. tostring(delta)) then return end
  local pos = math.max(0, current_position() + delta)
  reaper.SetEditCurPos(pos, true, false)
  state.status = delta < 0 and "Back 5s" or "Forward 5s"
end

local function goto_after_last_item()
  if not can_click("after_last_item") then return end
  local item_end = last_item_end()
  if not item_end then
    reaper.SetEditCurPos(0, true, false)
    warn("Nessun item presente: cursore a 0:00.")
    return
  end
  reaper.SetEditCurPos(item_end + NEXT_TAKE_GAP_SECONDS, true, false)
  state.status = "Dopo ultimo item +" .. tostring(NEXT_TAKE_GAP_SECONDS) .. "s"
end

-- custom: il nome scritto nella casella di Vai a e segna. Senza, il marker e' di
-- servizio e numerato (SOLO_MARK_001...), come vuole la regola dei marker del SOLO.
local function add_marker_named(prefix, custom)
  local pos = current_position()
  local idx = tonumber(proj_get(prefix .. "_counter", "")) or 1
  local name = string.format("%s_%03d", prefix, idx)
  custom = trim(custom or "")
  if custom ~= "" then name = custom end
  local color_map = {
    SOLO_MARK = native_color(100, 180, 230),
    BAD = native_color(230, 60, 50),
    OK = native_color(80, 200, 110),
    ALT = native_color(160, 115, 220),
    NOISE = native_color(235, 170, 60),
    INSERT = native_color(245, 145, 50)
  }
  reaper.AddProjectMarker2(0, false, pos, 0, name, -1, color_map[prefix] or 0)
  if custom == "" then proj_set(prefix .. "_counter", idx + 1) end
  reaper.UpdateArrange()
  state.status = "Marker: " .. name
end

local function collect_regions()
  local regions = {}
  local _, marker_count, region_count = reaper.CountProjectMarkers(0)
  local total = marker_count + region_count
  for i = 0, total - 1 do
    local ok, is_region, pos, rgn_end, name, idx, color = reaper.EnumProjectMarkers3(0, i)
    if ok and is_region then
      regions[#regions + 1] = { pos = pos, end_pos = rgn_end, name = trim(name or ""), idx = idx, color = color or 0 }
    end
  end
  table.sort(regions, function(a, b) return a.pos < b.pos end)
  return regions
end

local function current_region()
  local pos = current_position()
  for _, r in ipairs(collect_regions()) do
    if pos >= r.pos - EPS and pos <= r.end_pos + EPS then return r end
  end
  return nil
end

local function region_label()
  local r = current_region()
  if not r then return "Nessuna regione" end
  return r.name ~= "" and r.name or ("Regione " .. tostring(r.idx or "?"))
end

local function goto_region(delta)
  if not can_click("region_" .. tostring(delta)) then return end
  local regions = collect_regions()
  if #regions == 0 then warn("Nessuna regione nel progetto."); return end
  local pos = current_position()
  local target = nil
  if delta < 0 then
    for i = #regions, 1, -1 do
      if regions[i].pos < pos - 0.05 then target = regions[i]; break end
    end
    target = target or regions[1]
  else
    for _, r in ipairs(regions) do
      if r.pos > pos + 0.05 then target = r; break end
    end
    target = target or regions[#regions]
  end
  reaper.SetEditCurPos(target.pos, true, false)
  state.status = "Regione: " .. (target.name ~= "" and target.name or tostring(target.idx))
end

local function goto_region_start()
  local r = current_region()
  if not r then warn("Il cursore non e' dentro una regione."); return end
  reaper.SetEditCurPos(r.pos, true, false)
  state.status = "Inizio regione"
end

-- Navigazione per item: quelli della traccia di destinazione; se non ce ne sono, tutti.
local function item_starts()
  local target = active_track()
  local starts, all = {}, {}
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local it = reaper.GetMediaItem(0, i)
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local l = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    all[#all + 1] = { pos = p, len = l }
    if target and reaper.GetMediaItemTrack(it) == target then starts[#starts + 1] = { pos = p, len = l } end
  end
  local list = #starts > 0 and starts or all
  table.sort(list, function(a, b) return a.pos < b.pos end)
  return list
end

local function goto_item(delta)
  if not can_click("item_" .. tostring(delta)) then return end
  local items = item_starts()
  if #items == 0 then warn("Nessun item nel progetto."); return end
  local pos = current_position()
  local target = nil
  if delta < 0 then
    for i = #items, 1, -1 do
      if items[i].pos < pos - 0.05 then target = items[i]; break end
    end
    target = target or items[1]
  else
    for _, it in ipairs(items) do
      if it.pos > pos + 0.05 then target = it; break end
    end
    target = target or items[#items]
  end
  reaper.SetEditCurPos(target.pos, true, false)
  state.status = "Item a " .. format_time(target.pos)
end

local function goto_item_start()
  local pos = current_position()
  for _, it in ipairs(item_starts()) do
    if pos >= it.pos and pos < it.pos + it.len then
      reaper.SetEditCurPos(it.pos, true, false)
      state.status = "Inizio item"
      return
    end
  end
  warn("Il cursore non e' dentro un item.")
end

local function rec_region(key)
  local r = current_region()
  if not r then warn("Il cursore non e' dentro una regione."); return end
  reaper.SetEditCurPos(r.pos, true, false)
  record_on_track(key, key == "retakes" and "RETAKE" or "REC REGION")
end

local function insert_record()
  add_marker_named("INSERT", false)
  record_on_track("inserts", "INSERT")
end

local function alt_take()
  add_marker_named("ALT", false)
  record_on_track("alt", "ALT TAKE")
end

local function next_take()
  if not can_click("next_take") then return end
  if (reaper.GetPlayState() & 4) ~= 4 then
    warn("NEXT TAKE disponibile solo durante REC nella POC.")
    return
  end
  local key = state.active_track_key
  reaper.Main_OnCommand(ACTION.stop, 0)
  state.pending = {
    kind = "finalize_and_next_take",
    due = reaper.time_precise() + STOP_REC_SETTLE_SECONDS,
    track_key = key,
    session = state.record_session
  }
  state.record_session = nil
  state.status = "NEXT TAKE: stop e preparo nuovo take"
end

-- Toglie dalla timeline il take appena registrato e riporta il cursore
-- dov'era partito, pronto a rifarlo. Il file audio NON viene cancellato:
-- resta nella cartella del progetto. Tutto dentro un blocco di undo, quindi
-- un Ctrl+Z lo rimette esattamente com'era.
local function undo_last_take()
  local lt = state.last_take
  if not lt or not lt.guids or #lt.guids == 0 then
    warn("Nessun take di questa sessione da togliere. Per quelli di prima usa l'Undo di REAPER.")
    return
  end
  local risposta = reaper.ShowMessageBox(
    "Tolgo " .. (lt.region or "l'ultimo take") .. " dalla timeline e riporto il cursore" ..
    " al punto di partenza.\n\nIl file audio NON viene cancellato: resta nella cartella" ..
    " Media del progetto. E un Ctrl+Z rimette tutto com'era.",
    "ZP SOLO Recorder - togli il take", 1)
  if risposta ~= 1 then
    state.status = "Non ho toccato niente."
    return
  end
  reaper.Undo_BeginBlock()
  local cercati = {}
  for _, g in ipairs(lt.guids) do cercati[g] = true end
  local tolti = 0
  for i = reaper.CountMediaItems(0) - 1, 0, -1 do
    local item = reaper.GetMediaItem(0, i)
    local guid = item and item_guid(item)
    if guid and cercati[guid] then
      local tr = reaper.GetMediaItemTrack(item)
      if tr and reaper.DeleteTrackMediaItem(tr, item) then tolti = tolti + 1 end
    end
  end
  if lt.region then
    local i = 0
    while true do
      local retval, isrgn, _, _, nome, idx = reaper.EnumProjectMarkers(i)
      if retval == 0 then break end
      if isrgn and nome == lt.region then
        reaper.DeleteProjectMarker(0, idx, true)
        break
      end
      i = i + 1
    end
  end
  if state.take_counter > 1 then
    state.take_counter = state.take_counter - 1
    proj_set("take_counter", state.take_counter)
  end
  if lt.start then reaper.SetEditCurPos(lt.start, true, false) end
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("ZP SOLO: tolto " .. (lt.region or "l'ultimo take") .. " dalla timeline", -1)
  state.last_take = nil
  if tolti == 0 then
    warn("Non ho trovato gli item di quel take: forse li hai gia' spostati o tolti a mano.")
    return
  end
  state.status = (lt.region or "Ultimo take") ..
    " tolto dalla timeline, cursore all'inizio. Il file resta nella cartella del progetto; Ctrl+Z lo rimette."
end

local function finalize_recording(session)
  if not session then return nil end
  local first_pos, final_end = nil, nil
  local nuovi = {}
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local item = reaper.GetMediaItem(0, i)
    local guid = item_guid(item)
    local belongs_to_target = reaper.GetMediaItemTrack(item) == session.track
    if guid and not session.before[guid] and belongs_to_target then
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_end = pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      first_pos = not first_pos and pos or math.min(first_pos, pos)
      final_end = not final_end and item_end or math.max(final_end, item_end)
      nuovi[#nuovi + 1] = guid
    end
  end
  if not first_pos or not final_end or final_end <= first_pos + EPS then
    warn("STOP: nessun nuovo item registrato identificato.")
    return nil
  end
  local take_number = state.take_counter
  local name = string.format("Take %03d", take_number)
  local region_name = nil
  if state.auto_regions then
    reaper.AddProjectMarker2(0, true, first_pos, final_end, name, -1, native_color(70, 155, 220))
    region_name = name
  end
  state.take_counter = take_number + 1
  proj_set("take_counter", state.take_counter)
  -- Mi segno cos'e' appena entrato in timeline: serve a TOGLI TAKE.
  state.last_take = { guids = nuovi, start = first_pos, region = region_name,
                      track_key = session.track_key }
  reaper.UpdateArrange()
  state.status = name .. (region_name and " indicizzato — " or " registrato (senza regione) — ") .. track_name(session.track)
  return final_end, name
end

local function rename_last_take_region()
  local regions = collect_regions()
  if #regions == 0 then warn("Nessuna regione da rinominare."); return end
  local r = regions[#regions]
  local current_name = r.name ~= "" and r.name or "Take"
  local ok, value = reaper.GetUserInputs("Nome / nota ultima registrazione", 1,
    "Nome o nota,extrawidth=520", current_name)
  if not ok then return end
  value = trim(value)
  if value == "" then return end
  reaper.SetProjectMarker3(0, r.idx, true, r.pos, r.end_pos, value, r.color)
  reaper.UpdateArrange()
  state.status = "Ultima regione: " .. value
end

local function process_pending()
  if not state.pending then return end
  if reaper.time_precise() < state.pending.due then return end
  local pending = state.pending
  state.pending = nil
  if pending.kind == "finalize_recording" then
    finalize_recording(pending.session)
  elseif pending.kind == "finalize_and_next_take" then
    local recorded_end = finalize_recording(pending.session)
    local base = recorded_end or last_item_end()
    if not base then
      warn("NEXT TAKE: nessun item da cui proseguire.")
      return
    end
    reaper.SetEditCurPos(base + NEXT_TAKE_GAP_SECONDS, true, false)
    if not arm_only_solo_target(pending.track_key) then
      warn("NEXT TAKE: impossibile riarmare la traccia SOLO.")
      return
    end
    do_record_now()
  end
end

-- METER ------------------------------------------------------------------
-- IN legge l'ingresso VERO della scheda audio da cui registra la traccia
-- (GetInputActivityLevel), prima di effetti, fader e monitor: e' il livello che
-- finisce nel file. Solo se non si puo' (MIDI, ReaRoute, REAPER vecchio) ripiega
-- sul meter della traccia. RIT e' il master: quello che senti.
-- I valori sono in dB (scala da -60 a 0): in lineare una voce a -30 dB riempiva
-- il 3% della barra e sembrava sempre LOW.
local function amp_db(a)
  a = math.abs(tonumber(a) or 0)
  if a <= 0 then return -150 end
  return 20 * math.log(a, 10)
end

local function track_peak(track)
  if not track or not reaper.Track_GetPeakInfo then return nil end
  local l = math.abs(reaper.Track_GetPeakInfo(track, 0) or 0)
  local r = math.abs(reaper.Track_GetPeakInfo(track, 1) or l)
  return math.max(l, r)
end

local function input_peak(track)
  if not track then return nil, nil end
  local v = math.floor(reaper.GetMediaTrackInfo_Value(track, "I_RECINPUT") or -1)
  if v >= 0 and v & 4096 == 0 and (v & 1023) < 512 and reaper.GetInputActivityLevel then
    local idx = v & 1023
    local peak = reaper.GetInputActivityLevel(idx) or 0
    if v & 3072 ~= 0 then peak = math.max(peak, reaper.GetInputActivityLevel(idx + 1) or 0) end
    return math.abs(peak), "scheda"
  end
  return track_peak(track), "traccia"
end

-- Balistica: sale subito, scende di 24 dB al secondo; il picco resta fermo 1,5 s.
local function meter_update(name, peak)
  local now = reaper.time_precise()
  local m = state.meters[name]
  if not m then m = { db = -150, hold = -150, hold_t = 0, t = now }; state.meters[name] = m end
  local db = peak and amp_db(peak) or -150
  local dt = math.min(0.25, now - m.t)
  m.t = now
  m.db = math.max(db, m.db - 24 * dt)
  if db >= m.hold then m.hold, m.hold_t = db, now
  elseif now - m.hold_t > 1.5 then m.hold = m.db end
  m.none = peak == nil
  return m
end

local function meter_word(db)
  if db > -1 then return "CLIP" end
  if db > -6 then return "HOT" end
  if db > -30 then return "OK" end
  return "LOW"
end

-- 50125 e' gia' un'azione a interruttore: prima la usavamo solo per aprire,
-- e la finestra restava li' finche' non la cercavi a mano.
local function show_video_window()
  local prima = reaper.GetToggleCommandState(ACTION.video_window)
  reaper.Main_OnCommand(ACTION.video_window, 0)
  state.status = (prima == 1) and "Finestra video chiusa" or "Finestra video aperta"
end

local function video_aperta()
  return reaper.GetToggleCommandState(ACTION.video_window) == 1
end

local function show_navigator()
  local ok = pcall(reaper.Main_OnCommand, ACTION.navigator, 0)
  if ok then state.status = "Navigator" else warn("Navigator non disponibile.") end
end

local function run_action(action_id, label)
  if not action_id then return end
  reaper.Main_OnCommand(action_id, 0)
  state.status = label or ("Action " .. tostring(action_id))
end

-- Note del progetto. REAPER non ha un'azione che le apra da sole (stanno nella scheda
-- Notes di File > Project settings; 40850 sono le note degli ITEM). Con SWS c'e' la
-- finestra Notes sulle note del progetto: si apre anche se sono vuote e ci si scrive.
local function open_project_notes()
  local cmd = reaper.NamedCommandLookup and reaper.NamedCommandLookup("_S&M_SHOWNOTESHELP") or 0
  if cmd and cmd > 0 then
    reaper.Main_OnCommand(cmd, 0)
    state.status = "Note del progetto (finestra Notes di SWS): apri/chiudi"
  else
    reaper.Main_OnCommand(40021, 0)   -- File: Project settings...
    state.status = "Senza SWS: le note del progetto sono nella scheda Notes di Project settings."
  end
end

local function try_pin_window()
  if not state.pin then return end
  if reaper.time_precise() - state.last_pin_try < 1.0 then return end
  state.last_pin_try = reaper.time_precise()
  if not (reaper.JS_Window_Find and reaper.JS_Window_SetZOrder) then return end
  local hwnd = reaper.JS_Window_Find(SCRIPT_TITLE, true)
  if hwnd then pcall(reaper.JS_Window_SetZOrder, hwnd, "TOPMOST") end
end

local function try_unpin_window()
  if not (reaper.JS_Window_Find and reaper.JS_Window_SetZOrder) then return end
  local hwnd = reaper.JS_Window_Find(SCRIPT_TITLE, true)
  if hwnd then pcall(reaper.JS_Window_SetZOrder, hwnd, "NOTOPMOST") end
end

-- Nascondi / mostra la finestra di REAPER. E' un interruttore, e non viene
-- mai premuto da solo: all'avvio REAPER resta dov'e'.
local function toggle_reaper_window()
  if not (reaper.GetMainHwnd and reaper.JS_Window_Show) then
    state.warning = "Serve js_ReaScriptAPI per nascondere e rimettere su REAPER."
    return
  end
  local hwnd = reaper.GetMainHwnd()
  if not hwnd then
    state.warning = "Finestra di REAPER non trovata."
    return
  end
  if state.reaper_hidden then
    local ok = pcall(reaper.JS_Window_Show, hwnd, "RESTORE")
    if not ok then
      state.warning = "Non sono riuscito a rimettere su REAPER: usa il Dock."
      return
    end
    if reaper.JS_Window_SetForeground then
      pcall(reaper.JS_Window_SetForeground, hwnd)
    end
    state.reaper_hidden = false
    state.warning = ""
    state.status = "REAPER di nuovo visibile"
  else
    local ok = pcall(reaper.JS_Window_Show, hwnd, "MINIMIZE")
    if not ok then
      state.warning = "Minimize non disponibile su questo sistema."
      return
    end
    state.reaper_hidden = true
    state.warning = ""
    state.status = "REAPER nascosto: premi Mostra REAPER per riportarlo su"
  end
end

-- Monitoring d'ingresso della traccia attiva. REAPER tende ad accenderlo
-- da solo quando armi: qui si spegne e si riaccende senza aprire la finestra
-- principale. I_RECMON: 0 spento, 1 acceso, 2 automatico.
local function monitoring_label()
  local tr = active_track()
  if not tr then return "Monitor -", false end
  local mon = reaper.GetMediaTrackInfo_Value(tr, "I_RECMON")
  if mon == 2 then return "Monitor auto", true end
  if mon == 1 then return "Monitor ON", true end
  return "Monitor OFF", false
end

local function toggle_monitoring()
  local tr, nome = active_track()
  if not tr then
    warn("Traccia non trovata: scegline un'altra o costruisci la catena.")
    return
  end
  local mon = reaper.GetMediaTrackInfo_Value(tr, "I_RECMON")
  local nuovo = (mon == 0) and 1 or 0
  reaper.SetMediaTrackInfo_Value(tr, "I_RECMON", nuovo)
  state.status = (nuovo == 1 and "Monitoring acceso su " or "Monitoring spento su ") .. (nome or "?")
end

-- Volume di ritorno: agisce sulla TRACCIA SELEZIONATA in REAPER, che in
-- similsync e' la reference o l'audio del video. E' un cambio di mix vero,
-- quindi resta nel progetto: per questo mostro sempre il valore e dico
-- su quale traccia sto agendo.
local function selected_track()
  return reaper.GetSelectedTrack(0, 0)
end

local function track_db(tr)
  local v = reaper.GetMediaTrackInfo_Value(tr, "D_VOL")
  if v <= 0 then return -150 end
  return 20 * math.log(v, 10)
end

local function return_db_label()
  local tr = selected_track()
  if not tr then return "--" end
  return string.format("%+.1f dB", track_db(tr))
end

local function set_return_db(db)
  local tr = selected_track()
  if not tr then
    warn("Seleziona in REAPER la traccia che vuoi alzare o abbassare (la reference, o il video).")
    return
  end
  db = math.max(-60, math.min(12, db))
  reaper.SetMediaTrackInfo_Value(tr, "D_VOL", 10 ^ (db / 20))
  local _, nome = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  if nome == nil or nome == "" then nome = "traccia selezionata" end
  reaper.UpdateArrange()
  state.status = string.format("Ritorno: %s a %+.1f dB (e' un cambio di mix, resta nel progetto)", nome, db)
end

-- Help dedicato al SOLO: sta accanto agli altri, nella cartella help/.
local function apri_help_solo()
  local sep = package.config:sub(1, 1)
  local percorso = script_dir() .. sep .. "help" .. sep .. "solo_recorder.html"
  local f = io.open(percorso, "r")
  if not f then
    warn("Help del SOLO non trovato: " .. percorso)
    return
  end
  f:close()
  if reaper.CF_ShellExecute then
    reaper.CF_ShellExecute(percorso)
  else
    local osname = reaper.GetOS()
    local quoted = string.format("%q", percorso)
    if osname:match("OSX") or osname:match("macOS") then os.execute("open " .. quoted .. " &")
    elseif osname:match("Win") then os.execute('start "" ' .. quoted)
    else os.execute("xdg-open " .. quoted .. " >/dev/null 2>&1 &") end
  end
  state.status = "Help del SOLO aperto nel browser"
end

-- Se chiudi il telecomando mentre REAPER e' nascosto, non lo lascio sparito.
local function restore_reaper_on_exit()
  if not state.reaper_hidden then return end
  if not (reaper.GetMainHwnd and reaper.JS_Window_Show) then return end
  local hwnd = reaper.GetMainHwnd()
  if hwnd then pcall(reaper.JS_Window_Show, hwnd, "RESTORE") end
  state.reaper_hidden = false
end

local function mode_size(mode)
  if mode == "mini" then return MINI_W, MINI_H end
  if mode == "expanded" then return EXPANDED_W, EXPANDED_H end
  return COMPACT_W, COMPACT_H
end

local function set_mode(mode)
  if mode ~= "mini" and mode ~= "compact" and mode ~= "expanded" then return end
  state.mode = mode
  state.mark_focus = false
  local w, h = mode_size(mode)
  if mode ~= "mini" and state.toolbar then h = h + TOOLBAR_H end
  local dock, x, y = gfx.dock(-1, 0, 0, 0, 0)
  -- Su una finestra gia' aperta, gfx.init non sempre la ridimensiona: percio'
  -- la chiudo e la riapro alla misura giusta, tenendo posizione e dock.
  gfx.quit()
  gfx.init(SCRIPT_TITLE, w, h, dock or 0, x or 140, y or 120)
  gfx.setfont(1, "Arial", 15)
  state.last_pin_try = 0
  save_state()
end

-- Altezza della testata. I pulsanti di modalita' stanno qui e non si spostano
-- mai: cambiando vista, il mouse li ritrova dov'erano.
local function head_h()
  return state.mode == "mini" and 76 or 102
end

local function toggle_overlay()
  state.overlay = not state.overlay
  state.overlay_pick = nil
  if state.overlay then
    speak("Guida rapida: passa con il mouse su un comando per sapere cosa fa; clic per fissarlo. Esc o ? per chiudere.")
  else
    state.status = "Guida chiusa"
  end
end

local function toggle_rec_lock()
  state.rec_lock = not state.rec_lock
  save_state()
  speak(state.rec_lock and "Lock REC acceso: durante il REC la barra spaziatrice non ferma la registrazione."
    or "Lock REC spento: la barra spaziatrice ferma anche il REC, come in REAPER.")
end

-- Icone della testata (gfx non ha font di icone): salva, annulla, ripeti, pin, toolbar.
-- Negli archi di gfx 0 e' in alto e -pi/2 a sinistra.
local function draw_header_icon(kind, cx, cy, s)
  if kind == "save" then
    local h = math.floor(s * 0.62)
    local x0, y0 = math.floor(cx - h / 2), math.floor(cy - h / 2)
    gfx.rect(x0, y0, h, h, true)
    gfx.set(0.06, 0.10, 0.07, 1)
    gfx.rect(x0 + h * 0.22, y0 + 1, h * 0.50, h * 0.30, true)
    gfx.rect(x0 + h * 0.16, y0 + h * 0.56, h * 0.68, h * 0.34, true)
  elseif kind == "undo" or kind == "redo" then
    local r, d = s * 0.30, (kind == "undo") and -1 or 1
    local ay = cy + s * 0.06
    -- arco sopra il centro; la punta sta dal lato verso cui si torna (undo a sinistra)
    local a1, a2 = -math.pi / 2, math.pi * 0.6
    if d > 0 then a1, a2 = -math.pi * 0.6, math.pi / 2 end
    for t = 0, 1 do
      if gfx.arc then gfx.arc(cx, ay, r - t, a1, a2, true) end
    end
    local tipx = cx + d * r
    gfx.triangle(tipx - s * 0.13, ay, tipx + s * 0.13, ay, tipx, ay + s * 0.17)
  elseif kind == "pin" then
    gfx.rect(cx - s * 0.13, cy - s * 0.38, s * 0.26, s * 0.24, true)
    gfx.rect(cx - s * 0.26, cy - s * 0.15, s * 0.52, math.max(2, s * 0.09), true)
    gfx.rect(cx - 1, cy - s * 0.08, 2, s * 0.46, true)
  elseif kind == "toolbar" then
    local w, h = math.floor(s * 0.72), math.floor(s * 0.56)
    local x0, y0 = math.floor(cx - w / 2), math.floor(cy - h / 2)
    gfx.rect(x0, y0, w, h, false)
    local cw = math.floor((w - 8) / 3)
    for i = 0, 2 do gfx.rect(x0 + 2 + i * (cw + 2), y0 + h - 7, cw, 5, true) end
  end
end

-- Pulsantino della testata con icona: nella barra in basso e nella guida c'e' la spiegazione.
local function hbtn(rect, icon, key, active, enabled, clicked, style)
  local hit = btn(rect, "", active, enabled, clicked, style or "tab", key)
  local v = enabled == false and 0.42 or 0.95
  if icon == "save" and enabled ~= false then gfx.set(0.55, 1.0, 0.65, 1) else gfx.set(v, v, v + 0.02, 1) end
  draw_header_icon(icon, rect.x + rect.w / 2, rect.y + rect.h / 2, rect.h)
  return hit
end

-- Sinistra della testata: Save, Undo, Redo, poi Pin e Toolbar. Si vedono in ogni vista,
-- anche in Mini (dove la toolbar non c'e' e il suo pulsante e' spento).
local function draw_header_tools(clicked)
  local y, bh, bw = 8, 24, 30
  local x = 14
  if hbtn({x=x, y=y, w=bw, h=bh}, "save", "Save", false, true, clicked, "save") then run_action(ACTION.save_project, "Progetto salvato") end
  x = x + bw + 4
  if hbtn({x=x, y=y, w=bw, h=bh}, "undo", "Undo", false, true, clicked) then run_action(ACTION.undo, "Undo") end
  x = x + bw + 4
  if hbtn({x=x, y=y, w=bw, h=bh}, "redo", "Redo", false, true, clicked) then run_action(ACTION.redo, "Redo") end
  x = x + bw + 14
  if hbtn({x=x, y=y, w=bw, h=bh}, "pin", "Pin", state.pin, true, clicked) then
    state.pin = not state.pin; if not state.pin then try_unpin_window() end; save_state()
    state.status = state.pin and "Pin: finestra sempre sopra" or "Pin spento"
  end
  x = x + bw + 4
  if hbtn({x=x, y=y, w=bw, h=bh}, "toolbar", "Toolbar", state.toolbar and state.mode ~= "mini", state.mode ~= "mini", clicked) then
    state.toolbar = not state.toolbar; save_state(); set_mode(state.mode)
  end
end

-- Testata: viste, REAPER, guida. Stanno sempre allo stesso posto, in ogni vista.
local function draw_header_buttons(clicked)
  draw_header_tools(clicked)
  local y, bh = 8, 24
  local w1, w2, w3, wr, wq = 62, 84, 88, 72, 28
  local tot = w1 + w2 + w3 + 12 + wr + 4 + wq
  local x = gfx.w - tot - 14
  if btn({x=x, y=y, w=w1, h=bh}, "Mini", state.mode == "mini", true, clicked, "tab") then set_mode("mini") end
  x = x + w1 + 4
  if btn({x=x, y=y, w=w2, h=bh}, "Compact", state.mode == "compact", true, clicked, "tab") then set_mode("compact") end
  x = x + w2 + 4
  if btn({x=x, y=y, w=w3, h=bh}, "Expanded", state.mode == "expanded", true, clicked, "tab") then set_mode("expanded") end
  x = x + w3 + 12
  if btn({x=x, y=y, w=wr, h=bh}, "REAPER", state.reaper_hidden, true, clicked, "tab") then toggle_reaper_window() end
  x = x + wr + 4
  state.help_rect = {x=x, y=y, w=wq, h=bh}
  if btn(state.help_rect, "?", state.overlay, true, clicked, "tab") then toggle_overlay() end
end

local function draw_status_header(clicked)
  local label = transport_state()
  local rec = label == "REC"
  local H = head_h()
  set_color(rec and colors.rec or (state.target == "progetto" and colors.remote_panel or colors.panel))
  gfx.rect(0, 0, gfx.w, H, true)
  set_color(colors.border)
  gfx.rect(0, H - 1, gfx.w, 1, true)
  draw_header_buttons(clicked)
  gfx.setfont(1, "Arial", rec and 26 or 22, "b")
  gfx.set(1, 1, 1, 1)
  gfx.x, gfx.y = 14, 40
  local active_name = target_name()
  gfx.drawstr(rec and ("\u{25CF} REC \u{2014} " .. active_name) or label)
  gfx.setfont(2, "Arial", state.mode == "mini" and 24 or 28, "b")
  local tc = format_time(current_position())
  local tw = gfx.measurestr(tc)
  gfx.x, gfx.y = gfx.w - tw - 16, 38
  gfx.drawstr(tc)
  if state.mode ~= "mini" then
    gfx.setfont(3, "Arial", 13)
    gfx.set(0.82, 0.84, 0.88, 1)
    gfx.x, gfx.y = 16, 78
    local tr = (remote_mode() and "Telecomando · " or "") .. target_name()
    gfx.drawstr(fit_text("Track: " .. tr .. "   Region: " .. region_label() ..
      "   Take: " .. tostring(state.take_counter) ..
      "   " .. preroll_label(), gfx.w - 32))
  end
end

local function meter_x(db, x, w)
  local f = (db - METER_FLOOR_DB) / -METER_FLOOR_DB
  return x + w * math.max(0, math.min(1, f))
end

local function draw_meter(x, y, w, h, m)
  set_color({0.055, 0.055, 0.065, 1})
  gfx.rect(x, y, w, h, true)
  local ix, iw, iy, ih = x + 2, w - 4, y + 2, h - 4
  -- la barra cambia colore per zone: verde fino a -18, giallo fino a -6, arancio, rosso sopra -1
  local zone = { {-18, colors.green}, {-6, {0.62, 0.58, 0.12, 1}}, {-1, colors.orange}, {0, colors.rec} }
  local from = METER_FLOOR_DB
  for _, z in ipairs(zone) do
    local top = math.min(m.db, z[1])
    if top > from then
      local x1, x2 = meter_x(from, ix, iw), meter_x(top, ix, iw)
      set_color(z[2]); gfx.rect(x1, iy, math.max(1, x2 - x1), ih, true)
    end
    from = z[1]
  end
  -- tacche a -48 -36 -24 -18 -12 -6 -3
  for _, t in ipairs({-48, -36, -24, -18, -12, -6, -3}) do
    gfx.set(1, 1, 1, (t == -18 or t == -6) and 0.30 or 0.14)
    gfx.rect(math.floor(meter_x(t, ix, iw)), iy, 1, ih, true)
  end
  if m.hold > METER_FLOOR_DB then
    if m.hold > -1 then gfx.set(1, 0.25, 0.2, 1) else gfx.set(0.95, 0.95, 0.97, 0.9) end
    gfx.rect(math.floor(meter_x(m.hold, ix, iw)) - 1, iy, 2, ih, true)
  end
  set_color(colors.border)
  gfx.rect(x, y, w, h, false)
  gfx.setfont(1, "Arial", 12, "b")
  gfx.set(1, 1, 1, 1)
  local word = m.none and "N/A" or meter_word(m.hold)
  gfx.x, gfx.y = x + 8, y + 5
  gfx.drawstr(word)
  local val = m.none and "" or (m.hold <= -100 and "-inf" or string.format("%.1f dB", m.hold))
  local vw = gfx.measurestr(val)
  if w > 120 then gfx.x = x + w - vw - 8; gfx.drawstr(val) end
end

-- Navigatore dentro la finestra (vista Expanded): tutto il progetto in una striscia.
-- In alto, tenui, gli item di tutte le tracce; in basso, in verde, quelli della traccia
-- di destinazione. Regioni in blu, marker in giallo, riquadro = parte visibile della
-- timeline, cursore bianco, riproduzione verde (rossa in REC). Clic o trascina: sposta
-- il cursore; durante il REC non si muove niente.
local function nav_time_label(t)
  t = math.floor(t + 0.5)
  if t >= 3600 then return string.format("%d:%02d:%02d", t // 3600, (t // 60) % 60, t % 60) end
  return string.format("%d:%02d", t // 60, t % 60)
end

local NAV_ZOOM_SECONDS = { 600, 300, 120, 60, 30, 10 }   -- livelli dopo "tutto"

local function nav_zoom_label()
  local z = NAV_ZOOM_SECONDS[state.nav_zoom]
  if not z then return "tutto" end
  return z >= 60 and (tostring(z // 60) .. " min") or (tostring(z) .. " s")
end

local function draw_navigator(x, y, w, h)
  if w < 120 or h < 44 then return end
  local proj_len = reaper.GetProjectLength(0)
  local view_start, view_end = reaper.GetSet_ArrangeView2(0, false, 0, 0, 0, 0)
  local ps = reaper.GetPlayState()
  -- finestra: tutto il progetto, oppure una durata fissa che segue la testina
  local t0, total = 0, math.max(proj_len + 10, view_end or 0, 60)
  local zoom_len = NAV_ZOOM_SECONDS[state.nav_zoom]
  if zoom_len then
    local head = (ps & 1 == 1) and reaper.GetPlayPosition() or reaper.GetCursorPosition()
    total = zoom_len
    t0 = math.max(0, head - zoom_len * (state.nav_focus == "centro" and 0.5 or 1 / 3))
  end
  local band_h = h - 14
  local function tx(t) return x + ((t - t0) / total) * w end
  local function visible(a, b) return b >= t0 and a <= t0 + total end

  gfx.set(0.10, 0.105, 0.12, 1); gfx.rect(x, y, w, band_h, true)
  set_color(colors.border); gfx.rect(x, y, w, band_h, false)

  gfx.setfont(1, "Arial", 11)
  for _, r in ipairs(collect_regions()) do
    if not visible(r.pos, r.end_pos) then goto next_region end
    local rx = math.max(x, tx(r.pos))
    local rw = math.max(1, math.min(x + w, tx(r.end_pos)) - rx)
    gfx.set(0.25, 0.45, 0.70, 0.30); gfx.rect(rx, y + 1, rw, band_h - 2, true)
    if rw > 40 and r.name ~= "" then
      gfx.set(0.78, 0.86, 0.96, 0.9); gfx.x, gfx.y = rx + 3, y + 2
      gfx.drawstr(fit_text(r.name, rw - 6))
    end
    ::next_region::
  end

  local target = active_track()
  local lane = math.floor((band_h - 16) / 3)
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local it = reaper.GetMediaItem(0, i)
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local l = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if not visible(p, p + l) then goto next_item end
    local ix = math.max(x, tx(p))
    local iw = math.max(1, math.min(x + w, tx(p + l)) - ix)
    if target and reaper.GetMediaItemTrack(it) == target then
      gfx.set(0.35, 0.80, 0.50, 0.85); gfx.rect(ix, y + 14 + lane, iw, lane * 2 - 2, true)
    else
      gfx.set(0.60, 0.62, 0.68, 0.40); gfx.rect(ix, y + 14, iw, lane - 3, true)
    end
    ::next_item::
  end

  local _, nm, nr = reaper.CountProjectMarkers(0)
  for i = 0, nm + nr - 1 do
    local ok, isrgn, pos = reaper.EnumProjectMarkers3(0, i)
    if ok and not isrgn and visible(pos, pos) then gfx.set(0.95, 0.80, 0.30, 0.9); gfx.line(tx(pos), y + 1, tx(pos), y + band_h - 2) end
  end

  if view_end and view_end > view_start and visible(view_start, view_end) then
    gfx.set(1, 1, 1, 0.55)
    local vx = math.max(x, tx(view_start))
    gfx.rect(vx, y, math.max(2, math.min(x + w, tx(view_end)) - vx), band_h, false)
  end
  local ec = reaper.GetCursorPosition()
  if visible(ec, ec) then gfx.set(1, 1, 1, 1); gfx.line(tx(ec), y, tx(ec), y + band_h) end
  if ps & 1 == 1 then
    if ps & 4 == 4 then gfx.set(1, 0.25, 0.2, 1) else gfx.set(0.4, 0.9, 0.5, 1) end
    local pp = reaper.GetPlayPosition()
    gfx.line(tx(pp), y, tx(pp), y + band_h)
  end

  gfx.set(0.60, 0.62, 0.68, 1)
  local step = total > 3600 and 600 or total > 1800 and 300 or total > 600 and 60 or total > 120 and 30
    or total > 40 and 10 or total > 15 and 5 or 1
  local t = math.ceil(t0 / step) * step
  while t <= t0 + total do
    gfx.x, gfx.y = tx(t) + 2, y + band_h + 1
    gfx.drawstr(nav_time_label(t))
    t = t + step
  end

  if state.overlay then return end
  local down = (gfx.mouse_cap & 1) == 1
  local inside = point_in_rect(gfx.mouse_x, gfx.mouse_y, x, y, w, band_h)
  if down and inside and not state.mouse_was_down then state.nav_drag = true end
  if state.nav_drag then
    if down then
      if ps & 4 ~= 4 then
        local tt = math.max(0, t0 + math.max(0, math.min(1, (gfx.mouse_x - x) / w)) * total)
        reaper.SetEditCurPos(tt, true, false)
        state.nav_t = tt
      end
    else
      state.nav_drag = false
      if ps & 1 == 1 and ps & 4 ~= 4 and state.nav_t then reaper.SetEditCurPos(state.nav_t, true, true) end
      state.nav_t = nil
    end
  end
end

---------------------------------------------------------------------------
-- PULSANTIERA A ZONE
-- Ogni zona e' un pannello col suo titolo. Le zone si mettono in fila da sole e
-- vanno a capo se la finestra e' stretta: niente coordinate fisse, niente pulsanti
-- uno sopra l'altro. La guida (?) numera le zone e spiega ogni comando.
---------------------------------------------------------------------------

local GAP, MARGIN, STATUS_H = 10, 12, 28

-- Il tasto del mouse e' appena sceso (serve ai pomelli). Con la guida aperta no.
local function pressed_now()
  return not state.overlay and (gfx.mouse_cap & 1) == 1 and not state.mouse_was_down
end

-- Pulsante con un simbolo disegnato al posto della scritta.
local function sbtn(rect, key, symbol, active, enabled, clicked)
  local hit = btn(rect, "", active, enabled, clicked, nil, key)
  local v = enabled == false and 0.45 or 0.95
  gfx.set(v, v, v + 0.02, 1)
  ZP_UI.draw_symbol(symbol, rect.x + rect.w / 2, rect.y + rect.h / 2, rect.h * 0.9)
  return hit
end

local function tgl(rect, label, on, enabled, clicked, key)
  note(rect, key or label)
  return ZP_UI.draw_toggle(rect, label, on, enabled, clicked)
end

local function knob(rect, k, key, text)
  note(rect, key, text)
  k.pressed = pressed_now()
  k.readonly = state.overlay
  return ZP_UI.draw_knob(rect, k)
end

-- Pulsanti in fila che vanno a capo: posizioni e altezza totale.
local function flow(x, y, w, items, row_h, gap)
  local px, py, pos = x, y, {}
  for i, it in ipairs(items) do
    local iw = math.min(it.w, w)
    if px > x and px + iw > x + w then px = x; py = py + row_h + gap end
    pos[i] = {x=px, y=py, w=iw, h=row_h}
    px = px + iw + gap
  end
  return pos, (py - y) + row_h
end

local Z = {}

-- 2 TRASPORTO -------------------------------------------------------------
Z.trasporto = { id = "trasporto", n = 2, title = "Trasporto", min_w = 300, weight = 1,
  h = function() return 104 end }
function Z.trasporto.draw(c, clicked)
  local ts = transport_state()
  local tasti = {
    {"prev", 40, "-5s", "-5s"}, {"rec", 58, "REC", "REC"}, {"stop", 50, "STOP", "STOP"},
    {"play", 50, "PLAY", "PLAY"}, {"next", 40, "fine +5s", "fine +5s"}
  }
  local total = 238
  local g = math.max(6, math.min(28, math.floor((c.w - total) / 4)))
  local x = c.x + math.floor((c.w - total - g * 4) / 2)
  local cy, cap_y = c.y + 30, c.y + 62
  -- il lucchetto sta sul bordo del REC: se il mouse e' li', il clic non fa partire il REC
  local rec_cx = x + 40 + g + 29
  local lx, ly, lr = rec_cx + 22, cy - 22, 11
  local on_lock = (gfx.mouse_x - lx) ^ 2 + (gfx.mouse_y - ly) ^ 2 <= (lr + 1) ^ 2
  -- il pre-roll sta sull'altro bordo del REC, simmetrico al lucchetto
  local px = rec_cx - 22
  local on_pre = (gfx.mouse_x - px) ^ 2 + (gfx.mouse_y - ly) ^ 2 <= (lr + 1) ^ 2
  for _, t in ipairs(tasti) do
    local kind, d = t[1], t[2]
    local r = {x=x, y=cy - d // 2, w=d, h=d}
    note(r, t[4])
    local active = (kind == "rec" and ts == "REC") or (kind == "play" and ts == "PLAY")
    if ZP_UI.draw_round_button(r, kind, active, true, clicked and not on_lock and not on_pre) then
      if kind == "rec" then record_on_track(state.active_track_key, "REC")
      elseif kind == "stop" then stop_transport()
      elseif kind == "play" then play_transport()
      elseif kind == "prev" then move_cursor(-5)
      else goto_after_last_item() end
    end
    gfx.setfont(1, "Arial", 11, "b")
    gfx.set(0.70, 0.73, 0.80, 1)
    local tw = gfx.measurestr(t[3])
    gfx.x, gfx.y = x + d / 2 - tw / 2, cap_y
    gfx.drawstr(t[3])
    x = x + d + g
  end
  note({x=lx - lr, y=ly - lr, w=lr * 2, h=lr * 2}, "Lock")
  if state.rec_lock then gfx.set(0.98, on_lock and 0.88 or 0.76, 0.24, 1)
  else gfx.set(on_lock and 0.42 or 0.28, on_lock and 0.44 or 0.30, on_lock and 0.50 or 0.36, 1) end
  gfx.circle(lx, ly, lr, true, true)
  gfx.set(0.05, 0.05, 0.06, 1); gfx.circle(lx, ly, lr, false, true)
  if state.rec_lock then gfx.set(0.14, 0.09, 0.02, 1) else gfx.set(0.86, 0.88, 0.93, 1) end
  ZP_UI.draw_lock(lx, ly, lr * 1.3, state.rec_lock)
  if clicked and on_lock then toggle_rec_lock() end

  local pre = preroll_on()
  note({x=px - lr, y=ly - lr, w=lr * 2, h=lr * 2}, "Pre-roll", preroll_label() .. ". Clic: acceso / spento; i secondi in Sessione e finestra.")
  if pre then gfx.set(0.98, on_pre and 0.88 or 0.76, 0.24, 1)
  else gfx.set(on_pre and 0.42 or 0.28, on_pre and 0.44 or 0.30, on_pre and 0.50 or 0.36, 1) end
  gfx.circle(px, ly, lr, true, true)
  gfx.set(0.05, 0.05, 0.06, 1); gfx.circle(px, ly, lr, false, true)
  if pre then gfx.set(0.14, 0.09, 0.02, 1) else gfx.set(0.86, 0.88, 0.93, 1) end
  gfx.setfont(1, "Arial", 9, "b")
  local tw, th = gfx.measurestr("PRE")
  gfx.x, gfx.y = px - tw / 2, ly - th / 2
  gfx.drawstr("PRE")
  if clicked and on_pre then toggle_preroll() end
end

-- 3 INGRESSO E ASCOLTO ----------------------------------------------------
Z.ingresso = { id = "ingresso", n = 3, title = "Ingresso e ascolto", min_w = 380, weight = 2,
  h = function() return 104 end }
function Z.ingresso.draw(c, clicked)
  local tr = active_track()
  local kw = 64
  local lw = c.w - kw - 6
  local bw = math.min(130, math.max(92, math.floor(lw * 0.42)))
  local mw = math.max(40, lw - 28 - bw - 8)
  local in_peak, in_src = input_peak(tr)
  local m_in = meter_update("in", in_peak)
  local m_rit = meter_update("rit", track_peak(reaper.GetMasterTrack(0)))

  gfx.setfont(1, "Arial", 12, "b")
  gfx.set(0.80, 0.82, 0.88, 1)
  gfx.x, gfx.y = c.x, c.y + 7
  gfx.drawstr("IN")
  local in_rect = {x=c.x + 28, y=c.y + 2, w=mw, h=24}
  draw_meter(in_rect.x, in_rect.y, mw, 24, m_in)
  note(in_rect, "IN", in_src == "scheda" and "IN: ingresso della scheda audio (prima di effetti e fader), in dB. La riga chiara e' il picco." or
    "IN: meter della traccia di destinazione (questo ingresso non si legge direttamente), in dB.")
  local r1 = {x=c.x + 28 + mw + 8, y=c.y, w=bw, h=28}
  if btn(r1, (tr and input_short(tr) or "nessuna traccia") .. " \u{25BE}", false, tr ~= nil, clicked, "tab", "Ingresso",
      tr and ("Ingresso: " .. input_long(tr) .. ". Clic: cambia ingresso.") or nil) then
    choose_input(tr)
  end

  local y2 = c.y + 40
  gfx.setfont(1, "Arial", 12, "b")
  gfx.set(0.80, 0.82, 0.88, 1)
  gfx.x, gfx.y = c.x, y2 + 7
  gfx.drawstr("RIT")
  draw_meter(c.x + 28, y2 + 2, mw, 24, m_rit)
  note({x=c.x + 28, y=y2 + 2, w=mw, h=24}, "RIT")
  local mon_label, mon_on = monitoring_label()
  if btn({x=r1.x, y=y2, w=bw, h=28}, mon_label, mon_on, true, clicked, "tab", "Monitor") then toggle_monitoring() end

  local kx = c.x + lw + 6
  local sel = selected_track()
  local db = sel and math.max(-60, track_db(sel)) or 0
  local sel_nome = ""
  if sel then local _; _, sel_nome = reaper.GetSetMediaTrackInfo_String(sel, "P_NAME", "", false) end
  local v, changed = knob({x=kx, y=c.y, w=kw, h=c.h}, {
    id = "ritorno", value = db, min = -60, max = 12, default = 0, step = 0.5,
    label = "Ritorno", text = sel and string.format("%+.1f dB", db) or "--", enabled = sel ~= nil,
  }, "Ritorno", sel and ("Ritorno: volume di " .. ((sel_nome ~= "" and sel_nome) or "traccia selezionata") ..
    ". Trascina o rotella, doppio clic = 0 dB.") or "Ritorno: seleziona in REAPER la traccia da regolare (reference o video).")
  if changed then set_return_db(v) end
end

-- 4 TRACCIA ---------------------------------------------------------------
Z.traccia = { id = "traccia", n = 4, title = "Traccia di destinazione", min_w = 500, weight = 2,
  h = function() return 62 end }
function Z.traccia.draw(c, clicked)
  -- Selettore doppio, come Regioni / Item: la meta' accesa e' la modalita' in uso.
  local remote = remote_mode()
  local sw1, sw2 = 82, 104
  local sx = c.x + c.w - sw1 - sw2 - 2
  if btn({x=sx, y=c.y, w=sw1, h=32}, "Sessione", not remote, true, clicked, "tab") and remote then
    set_target("solo")
    return
  end
  if btn({x=sx + sw1 + 2, y=c.y, w=sw2, h=32}, "Telecomando", remote, true, clicked, "tab") and not remote then
    set_target("progetto")
    return
  end
  local avail = sx - 12 - c.x
  if remote then
    local armed = armed_tracks()
    local arm_w = 110
    gfx.setfont(1, "Arial", 13, "b")
    gfx.set(0.86, 0.90, 0.96, 1)
    gfx.x, gfx.y = c.x, c.y + 8
    gfx.drawstr(fit_text(#armed > 0 and ("Registra su " .. target_name())
      or "Nessuna traccia armata", avail - arm_w - 10))
    if btn({x=sx - 12 - arm_w, y=c.y, w=arm_w, h=32}, "Tracce \u{25BE}", false, true, clicked, "tab", "Tracce") then
      choose_tracks_menu()
    end
    return
  end
  -- tracce della sessione: nome sopra, ingresso sotto in piccolo
  local n = #RECORD_TRACK_KEYS
  local bw = math.floor((avail - 6 * (n - 1)) / n)
  for i, key in ipairs(RECORD_TRACK_KEYS) do
    local x = c.x + (i - 1) * (bw + 6)
    local corto = TRACK_NAMES[key]:gsub("^VO_", "")
    local solo_tr = find_track_exact(TRACK_NAMES[key])
    local r = {x=x, y=c.y, w=bw, h=32}
    if btn(r, "", state.active_track_key == key, true, clicked, "tab", corto,
        solo_tr and (AIUTI[corto] .. " Ingresso: " .. input_long(solo_tr) .. ".") or nil) then
      if arm_only_solo_target(key) then state.warning = "" end
    end
    gfx.setfont(1, "Arial", 12, "b")
    gfx.set(0.96, 0.96, 0.98, 1)
    local t = fit_text(corto, bw - 8)
    local tw = gfx.measurestr(t)
    gfx.x, gfx.y = x + (bw - tw) / 2, c.y + (solo_tr and 3 or 9)
    gfx.drawstr(t)
    if solo_tr then
      gfx.setfont(1, "Arial", 10)
      gfx.set(0.70, 0.76, 0.86, 1)
      t = fit_text(input_short(solo_tr), bw - 8)
      tw = gfx.measurestr(t)
      gfx.x, gfx.y = x + (bw - tw) / 2, c.y + 18
      gfx.drawstr(t)
    end
  end
end

-- 5 VAI A E SEGNA ---------------------------------------------------------
-- Simbolo marker: asta con bandierina, come i marker della timeline.
local function draw_marker_symbol(cx, cy, s)
  local h = s * 0.62
  local x0, y0 = math.floor(cx - s * 0.18), math.floor(cy - h / 2)
  gfx.rect(x0, y0, 2, h, true)
  gfx.triangle(x0 + 2, y0, x0 + 2, y0 + h * 0.5, x0 + 2 + s * 0.42, y0 + h * 0.25)
end

-- Marker nel punto in cui sei: con il nome della casella, se c'e', altrimenti numerato.
local function mark_here()
  local nome = trim(state.mark_text)
  add_marker_named("SOLO_MARK", nome)
  state.mark_text = ""
  state.mark_focus = false
end

-- Casella del nome: clic per scrivere, Invio mette il marker, Esc lascia perdere.
-- Mentre scrivi i tasti vanno qui (anche la barra spaziatrice): vedi main_loop.
local function draw_mark_field(r, clicked)
  local hover = sotto_il_mouse(r)
  note(r, "Nome marker")
  if clicked and not state.overlay then state.mark_focus = hover end
  set_color(state.mark_focus and {0.05, 0.06, 0.08, 1} or {0.09, 0.095, 0.115, 1})
  ZP_UI.fill_round(r.x, r.y, r.w, r.h, 5)
  if state.mark_focus then gfx.set(0.30, 0.68, 1.0, 1)
  elseif hover then gfx.set(0.48, 0.52, 0.62, 1) else gfx.set(0.32, 0.34, 0.42, 1) end
  if gfx.roundrect then gfx.roundrect(r.x, r.y, r.w - 1, r.h - 1, 5, true) else gfx.rect(r.x, r.y, r.w, r.h, false) end
  gfx.setfont(1, "Arial", 13)
  local t = state.mark_text
  local tx = r.x + 9
  if t == "" and not state.mark_focus then
    gfx.set(0.55, 0.57, 0.63, 1)
    t = fit_text("Nome marker\u{2026}", r.w - 18)
  else
    gfx.set(0.95, 0.95, 0.97, 1)
    -- se il testo e' piu' lungo della casella, si vede la parte finale (dove scrivi)
    while #t > 0 and gfx.measurestr(t) > r.w - 22 do t = t:gsub("^[%z\1-\127\194-\244][\128-\191]*", "") end
  end
  local tw, th = gfx.measurestr(t)
  gfx.x, gfx.y = tx, r.y + (r.h - th) / 2
  gfx.drawstr(t)
  if state.mark_focus and (reaper.time_precise() % 1) < 0.55 then
    gfx.set(0.30, 0.68, 1.0, 1)
    gfx.rect(tx + tw + 1, r.y + 7, 2, r.h - 14, true)
  end
end

-- Tasti per la casella del marker. Restituisce true se il tasto e' stato usato qui.
local function mark_field_key(char)
  if not state.mark_focus then return false end
  if char == 13 then mark_here()
  elseif char == 27 then state.mark_focus = false; state.mark_text = ""; state.status = "Marker lasciato perdere"
  elseif char == 8 then state.mark_text = state.mark_text:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
  elseif char >= 32 and char < 127 then state.mark_text = state.mark_text .. string.char(char)
  elseif char >= 0x75000000 and char < 0x76000000 then
    state.mark_text = state.mark_text .. utf8.char(char - 0x75000000)
  elseif char >= 160 and char < 256 then state.mark_text = state.mark_text .. utf8.char(char)
  end
  return true
end

Z.vai = { id = "vai", n = 5, title = "Vai a e segna", min_w = 420, weight = 1,
  h = function() return 62 end }
function Z.vai.draw(c, clicked)
  local by_item = state.nav == "item"
  local x, h = c.x, 32
  if btn({x=x, y=c.y, w=66, h=h}, "Regioni", not by_item, true, clicked, "tab") then
    state.nav = "regioni"; save_state(); state.status = "Spostamenti tra le regioni"
  end
  x = x + 68
  if btn({x=x, y=c.y, w=54, h=h}, "Item", by_item, true, clicked, "tab") then
    state.nav = "item"; save_state(); state.status = "Spostamenti tra gli item della traccia di destinazione"
  end
  x = x + 54 + 12
  if sbtn({x=x, y=c.y, w=34, h=h}, "Precedente", "left", false, true, clicked) then
    if by_item then goto_item(-1) else goto_region(-1) end
  end
  x = x + 38
  if sbtn({x=x, y=c.y, w=34, h=h}, "Inizio", "start", false, true, clicked) then
    if by_item then goto_item_start() else goto_region_start() end
  end
  x = x + 38
  if sbtn({x=x, y=c.y, w=34, h=h}, "Successivo", "right", false, true, clicked) then
    if by_item then goto_item(1) else goto_region(1) end
  end
  x = x + 34 + 12
  local rest = c.x + c.w - x
  local w1 = math.max(36, math.floor((rest - 6) * 0.42 / 3))
  local mr = {x=x, y=c.y, w=w1, h=h}
  local hit = btn(mr, "", false, true, clicked, nil, "Mark")
  gfx.set(0.42, 0.74, 0.92, 1)
  draw_marker_symbol(mr.x + mr.w / 2, mr.y + mr.h / 2, h * 0.8)
  if hit then mark_here() end
  draw_mark_field({x=x + w1 + 6, y=c.y, w=rest - w1 - 6, h=h}, clicked)
end

-- 6 TAKE ------------------------------------------------------------------
Z.take = { id = "take", n = 6, title = "Take", min_w = 400, weight = 2,
  h = function() return 96 end }

-- Pulsante che REGISTRA: pallino rosso a sinistra, cosi' non si confonde con i comandi
-- che spostano o segnano. Spento (pallino grigio) quando non si puo' usare.
local function recbtn(rect, label, enabled, clicked)
  note(rect, label)
  local hit = ZP_UI.draw_button(rect, "", false, enabled, clicked, nil)
  local cy = rect.y + rect.h / 2
  if enabled then gfx.set(0.95, 0.16, 0.12, 1) else gfx.set(0.38, 0.38, 0.40, 1) end
  gfx.circle(rect.x + 13, cy, 5, true, true)
  gfx.setfont(1, "Arial", 13, "b")
  local v = enabled and 0.95 or 0.48
  gfx.set(v, v, v + 0.02, 1)
  local t = fit_text(label, rect.w - 30)
  local _, th = gfx.measurestr(t)
  gfx.x, gfx.y = rect.x + 24, cy - th / 2
  gfx.drawstr(t)
  return hit
end

function Z.take.draw(c, clicked)
  -- riga 1: registrano (true = usa le tracce della sessione SOLO -> spento in Telecomando)
  local registra = {
    {"Next take", next_take},
    {"Retake", function() rec_region("retakes") end, true},
    {"Insert", insert_record, true},
    {"Alt take", alt_take, true},
  }
  local bw = math.floor((c.w - 18) / 4)
  for i, v in ipairs(registra) do
    if recbtn({x=c.x + (i - 1) * (bw + 6), y=c.y, w=bw, h=30}, v[1], not (v[3] and remote_mode()), clicked) then
      v[2]()
    end
  end
  -- riga 2: gestiscono il take appena fatto
  local hw = math.floor((c.w - 6) / 2)
  if btn({x=c.x, y=c.y + 36, w=hw, h=30}, "Nome / nota", false, true, clicked) then rename_last_take_region() end
  if btn({x=c.x + hw + 6, y=c.y + 36, w=c.w - hw - 6, h=30}, "Togli take", false, true, clicked, "danger") then undo_last_take() end
end

-- 7 ETICHETTE -------------------------------------------------------------
local ETICHETTE = { {"OK", "save", "OK"}, {"BAD", "danger", "BAD"}, {"ALT", nil, "ALT marker"}, {"NOISE", "play_select", "NOISE"} }
Z.etichette = { id = "etichette", n = 7, title = "Etichette", min_w = 150, weight = 1,
  h = function(w) return (w - 20 >= 4 * 56 + 18) and 62 or 96 end }
function Z.etichette.draw(c, clicked)
  local cols = (c.w >= 4 * 56 + 18) and 4 or 2
  local bw = math.floor((c.w - 6 * (cols - 1)) / cols)
  for i, e in ipairs(ETICHETTE) do
    local col, row = (i - 1) % cols, (i - 1) // cols
    if btn({x=c.x + col * (bw + 6), y=c.y + row * 36, w=bw, h=30}, e[1], false, true, clicked, e[2], e[3]) then
      add_marker_named(e[1], false)
    end
  end
end

-- 9 SESSIONE E FINESTRA ---------------------------------------------------
local function sessione_voci()
  return {
    {w = 124, kind = "tgl", label = "Regioni take", on = state.auto_regions, act = function()
      state.auto_regions = not state.auto_regions; save_state()
      state.status = state.auto_regions and "A ogni REC crea la regione Take NNN." or "REC senza regione: il take resta, la regione no."
    end},
    {w = 92, kind = "tgl", label = "Effetti", on = state.fx_session, enabled = not remote_mode(), act = function()
      state.fx_session = not state.fx_session; save_state()
      if state.fx_session then
        if not apply_fx_session() then state.status = "Effetti ON: li inserisco quando nasce la sessione SOLO." end
      else
        state.status = "Effetti OFF: non inserisco piu' le catene; quelli gia' inseriti restano."
      end
    end},
    {w = 80, kind = "tgl", label = "Video", on = video_aperta(), act = show_video_window},
    {w = 156, kind = "step", label = "Pre-roll"},
  }
end

Z.sessione = { id = "sessione", n = 9, title = "Sessione e finestra", min_w = 300, weight = 2 }
function Z.sessione.h(w)
  local _, h = flow(0, 0, w - 20, sessione_voci(), 28, 6)
  return h + 30
end
-- Secondi del pre-roll: [-] valore [+], anche con la rotella. La spia dice se e' acceso.
local function draw_preroll_stepper(r, clicked)
  note(r, "Secondi pre-roll")
  local bw = 28
  local on = preroll_on()
  if btn({x=r.x, y=r.y, w=bw, h=r.h}, "\u{2212}", false, state.preroll_s > PREROLL_MIN, clicked, nil, "Secondi pre-roll") then
    set_preroll_seconds(state.preroll_s - 1)
  end
  if btn({x=r.x + r.w - bw, y=r.y, w=bw, h=r.h}, "+", false, state.preroll_s < PREROLL_MAX, clicked, nil, "Secondi pre-roll") then
    set_preroll_seconds(state.preroll_s + 1)
  end
  local mx, mw = r.x + bw + 4, r.w - 2 * bw - 8
  set_color({0.13, 0.13, 0.17, 1})
  ZP_UI.fill_round(mx, r.y, mw, r.h, 5)
  if on then gfx.set(0.98, 0.76, 0.24, 1) else gfx.set(0.22, 0.24, 0.28, 1) end
  gfx.circle(mx + 11, r.y + r.h / 2, 4, true, true)
  gfx.setfont(1, "Arial", 13, "b")
  gfx.set(0.95, 0.95, 0.97, 1)
  local t = fit_text("Pre-roll " .. state.preroll_s .. " s", mw - 24)
  local tw, th = gfx.measurestr(t)
  gfx.x, gfx.y = mx + 20 + (mw - 24 - tw) / 2, r.y + (r.h - th) / 2
  gfx.drawstr(t)
  if gfx.mouse_wheel ~= 0 and not state.overlay and sotto_il_mouse(r) then
    set_preroll_seconds(state.preroll_s + (gfx.mouse_wheel > 0 and 1 or -1))
    gfx.mouse_wheel = 0
  end
end

function Z.sessione.draw(c, clicked)
  local voci = sessione_voci()
  local pos = flow(c.x, c.y, c.w, voci, 28, 6)
  for i, v in ipairs(voci) do
    local hit
    if v.kind == "tgl" then hit = tgl(pos[i], v.label, v.on, v.enabled, clicked)
    elseif v.kind == "step" then draw_preroll_stepper(pos[i], clicked)
    else hit = btn(pos[i], v.label, false, true, clicked) end
    if hit then v.act() end
  end
end

-- 8 NAVIGATORE (prende l'altezza che resta) ------------------------------
Z.navigatore = { id = "navigatore", n = 8, title = "Navigatore", min_w = 300, weight = 1 }
function Z.navigatore.draw(c, clicked)
  local v, changed = knob({x=c.x, y=c.y, w=120, h=30}, {
    id = "zoom", value = state.nav_zoom, min = 0, max = #NAV_ZOOM_SECONDS, default = 0, step = 1,
    label = "Zoom", text = nav_zoom_label(), inline = true,
  }, "Zoom")
  if changed then
    state.nav_zoom = math.floor(v + 0.5); save_state()
    state.status = "Navigatore: " .. nav_zoom_label()
  end
  local zoomed = state.nav_zoom > 0
  local x = c.x + c.w - 48 - 4 - 70
  if btn({x=x, y=c.y + 2, w=48, h=26}, "1/3", state.nav_focus ~= "centro", zoomed, clicked, "tab") then
    state.nav_focus = "terzo"; save_state()
  end
  if btn({x=x + 52, y=c.y + 2, w=70, h=26}, "centro", state.nav_focus == "centro", zoomed, clicked, "tab") then
    state.nav_focus = "centro"; save_state()
  end
  local band = {x=c.x, y=c.y + 38, w=c.w, h=c.h - 38}
  note(band, "Navigatore", "Navigatore (" .. nav_zoom_label() .. "): clic o trascina per spostare il cursore (fermo durante il REC).")
  draw_navigator(band.x, band.y, band.w, band.h)
end

-- Le viste sono un sottoinsieme delle zone, nell'ordine in cui si leggono.
local VISTE = {
  mini = { Z.trasporto, Z.ingresso },
  compact = { Z.trasporto, Z.ingresso, Z.traccia, Z.vai, Z.sessione },
  -- Expanded: "Vai a e segna" a sinistra e "Traccia" a destra, sulla stessa riga
  expanded = { Z.trasporto, Z.ingresso, Z.vai, Z.traccia, Z.take, Z.etichette, Z.sessione },
}

-- Impagina le zone in righe: ne mette in una riga finche' ci stanno (larghezza minima),
-- poi divide lo spazio avanzato secondo il peso. Righe alte quanto la zona piu' alta.
local function layout_zones(zones, x, y, w)
  local rows, row, used = {}, {}, 0
  for _, z in ipairs(zones) do
    local need = math.min(z.min_w, w) + (#row > 0 and GAP or 0)
    if #row > 0 and used + need > w then
      rows[#rows + 1] = row
      row, used, need = {}, 0, math.min(z.min_w, w)
    end
    row[#row + 1] = z
    used = used + need
  end
  if #row > 0 then rows[#rows + 1] = row end
  local placed = {}
  for _, r in ipairs(rows) do
    local mins, weights = GAP * (#r - 1), 0
    for _, z in ipairs(r) do mins = mins + math.min(z.min_w, w); weights = weights + (z.weight or 1) end
    local extra = math.max(0, w - mins)
    local widths, rh, xx = {}, 0, x
    for i, z in ipairs(r) do
      local zw = math.min(z.min_w, w) + math.floor(extra * (z.weight or 1) / weights)
      if i == #r then zw = x + w - xx end
      widths[i] = zw
      rh = math.max(rh, z.h(zw))
      xx = xx + zw + GAP
    end
    xx = x
    for i, z in ipairs(r) do
      placed[#placed + 1] = { zone = z, rect = {x=xx, y=y, w=widths[i], h=rh} }
      xx = xx + widths[i] + GAP
    end
    y = y + rh + GAP
  end
  return placed, y
end

local function content_bottom()
  return gfx.h - ((state.toolbar and state.mode ~= "mini") and TOOLBAR_H or 0) - STATUS_H
end

local function draw_zones(clicked)
  local zones = VISTE[state.mode] or VISTE.compact
  local placed, y = layout_zones(zones, MARGIN, head_h() + GAP, gfx.w - 2 * MARGIN)
  if state.mode == "expanded" and content_bottom() - y >= 90 then
    placed[#placed + 1] = { zone = Z.navigatore, rect = {x=MARGIN, y=y, w=gfx.w - 2 * MARGIN, h=content_bottom() - y} }
  end
  state.zones = { { id = "testata", n = 1, title = "Testata", rect = {x=0, y=0, w=gfx.w, h=head_h()} } }
  local remote = state.target == "progetto"
  local opts = remote and { fill = {0.235, 0.245, 0.26, 1}, border = {0.36, 0.37, 0.40, 1} } or nil
  for _, p in ipairs(placed) do
    local c = ZP_UI.draw_panel(p.rect, p.zone.title, opts)
    p.zone.draw(c, clicked)
    state.zones[#state.zones + 1] = { id = p.zone.id, n = p.zone.n, title = p.zone.title, rect = p.rect }
  end
end

-- GUIDA RAPIDA (overlay) --------------------------------------------------
-- Scurisce la finestra, numera le zone e spiega il comando sotto il mouse.
-- Un clic su un comando non lo esegue: fissa la sua spiegazione (e la legge OSARA).
local function draw_overlay(clicked)
  gfx.set(0, 0, 0, 0.66)
  gfx.rect(0, 0, gfx.w, gfx.h, true)
  local hit
  for i = #state.ctrls, 1, -1 do
    local c = state.ctrls[i]
    if c.key ~= "?" and sotto_il_mouse(c.rect) then hit = c; break end
  end
  local zone_hit
  for _, z in ipairs(state.zones) do
    local r = z.rect
    gfx.set(0.30, 0.68, 1.0, 0.75)
    gfx.rect(r.x + 1, r.y + 1, r.w - 2, r.h - 2, false)
    gfx.setfont(1, "Arial", 12, "b")
    local tw = gfx.measurestr(z.title)
    gfx.set(0.04, 0.07, 0.12, 1)
    gfx.rect(r.x + 2, r.y + 2, tw + 36, 19, true)
    gfx.set(0.30, 0.68, 1.0, 1)
    gfx.circle(r.x + 13, r.y + 11, 8, true, true)
    gfx.setfont(1, "Arial", 11, "b")
    gfx.set(0.02, 0.08, 0.16, 1)
    local s = tostring(z.n)
    local sw = gfx.measurestr(s)
    gfx.x, gfx.y = r.x + 13 - sw / 2, r.y + 5
    gfx.drawstr(s)
    gfx.setfont(1, "Arial", 12, "b")
    gfx.set(0.86, 0.93, 1, 1)
    gfx.x, gfx.y = r.x + 26, r.y + 5
    gfx.drawstr(z.title)
    if sotto_il_mouse(r) then zone_hit = z end
  end
  if hit then
    gfx.set(1, 0.85, 0.30, 1)
    gfx.rect(hit.rect.x - 2, hit.rect.y - 2, hit.rect.w + 4, hit.rect.h + 4, false)
    gfx.rect(hit.rect.x - 3, hit.rect.y - 3, hit.rect.w + 6, hit.rect.h + 6, false)
    if clicked then
      state.overlay_pick = { key = hit.key, text = DETTAGLI[hit.key] or hit.text or aiuto_per(hit.key) or "" }
      speak(hit.key .. ": " .. state.overlay_pick.text)
    end
  end

  -- riquadro della spiegazione: comando sotto il mouse, oppure quello fissato, oppure la zona
  local title, text
  if hit then
    title, text = hit.key, DETTAGLI[hit.key] or hit.text or aiuto_per(hit.key) or ""
  elseif state.overlay_pick then
    title, text = state.overlay_pick.key, state.overlay_pick.text
  elseif zone_hit then
    title, text = zone_hit.n .. "  " .. zone_hit.title, ZONE_AIUTO[zone_hit.id] or ""
  else
    title = "Guida rapida"
    text = "Passa con il mouse su un comando per sapere cosa fa; clic per fissare la spiegazione (OSARA la legge). Le zone sono numerate. Esc o ? per chiudere; Guida completa apre l'help nel browser."
  end
  local bw = math.min(gfx.w - 32, 640)
  gfx.setfont(1, "Arial", 14)
  local lines = ZP_UI.wrap_text(text, bw - 28)
  local bh = 40 + #lines * 18 + 10
  local bx = math.floor((gfx.w - bw) / 2)
  local by = (gfx.mouse_y > gfx.h / 2) and (head_h() + 8) or (gfx.h - bh - 12)
  gfx.set(0.10, 0.11, 0.145, 0.98)
  ZP_UI.fill_round(bx, by, bw, bh, 8)
  gfx.set(0.30, 0.68, 1.0, 1)
  if gfx.roundrect then gfx.roundrect(bx, by, bw - 1, bh - 1, 8, true) else gfx.rect(bx, by, bw, bh, false) end
  gfx.setfont(1, "Arial", 15, "b")
  gfx.set(1, 0.88, 0.45, 1)
  gfx.x, gfx.y = bx + 14, by + 12
  gfx.drawstr(fit_text(title, bw - 28))
  gfx.setfont(1, "Arial", 14)
  gfx.set(0.92, 0.93, 0.96, 1)
  for i, l in ipairs(lines) do
    gfx.x, gfx.y = bx + 14, by + 36 + (i - 1) * 18
    gfx.drawstr(l)
  end

  -- comandi della guida, sopra lo scuro: "?" chiude, accanto la guida completa
  local hr = state.help_rect
  if hr then
    if ZP_UI.draw_button(hr, "?", true, true, clicked, "tab") then toggle_overlay() end
    local gr = {x=hr.x - 136, y=hr.y, w=130, h=hr.h}
    if ZP_UI.draw_button(gr, "Guida completa", false, true, clicked, "play_select") then apri_help_solo() end
  end
end

local function draw_toolbar(clicked)
  if not state.toolbar or state.mode == "mini" then return end
  local y = gfx.h - TOOLBAR_H + 8
  set_color({0.075, 0.078, 0.090, 1})
  gfx.rect(0, gfx.h - TOOLBAR_H, gfx.w, TOOLBAR_H, true)
  set_color(colors.border)
  gfx.rect(0, gfx.h - TOOLBAR_H, gfx.w, 1, true)
  local buttons = {
    {"Metro", ACTION.toggle_metronome},
    {"Mixer", ACTION.show_mixer},
    {"Routing", ACTION.show_routing},
    {"FX Chain", ACTION.show_fx_chain},
    {"Notes", open_project_notes},
    {"Markers", ACTION.region_marker_manager},
    {"Navigator", ACTION.navigator},
    {"Video", ACTION.video_window}
  }
  local x, bw, bh, gap = 14, 78, 30, 8
  for _, b in ipairs(buttons) do
    if x + bw > gfx.w - 10 then x = 14; y = y + 38 end
    if btn({x=x, y=y, w=bw, h=bh}, b[1], false, true, clicked, b[3]) then
      if type(b[2]) == "function" then b[2]() else run_action(b[2], b[1]) end
    end
    x = x + bw + gap
  end
end

local function draw_gui()
  -- Il suggerimento vale un giro solo: lo ricalcolano i pulsanti disegnati adesso.
  state.hint = ""
  set_color(state.target == "progetto" and colors.remote_bg or colors.bg)
  gfx.rect(0, 0, gfx.w, gfx.h, true)
  state.ctrls = {}
  -- con la guida aperta i comandi si vedono ma non si azionano
  local real_click = mouse_clicked()
  local clicked = real_click and not state.overlay
  draw_status_header(clicked)
  draw_zones(clicked)
  draw_toolbar(clicked)

  -- Riga in basso: se il mouse e' su un pulsante spiega quel pulsante,
  -- altrimenti dice come e' andata l'ultima cosa che hai premuto.
  local yr = gfx.h - (state.toolbar and state.mode ~= "mini" and TOOLBAR_H or 0) - 22
  gfx.setfont(1, "Arial", 13)
  if state.hint ~= "" then
    gfx.set(0.62, 0.78, 0.92, 1)
  else
    gfx.set(0.74, 0.76, 0.82, 1)
  end
  gfx.x, gfx.y = 16, yr
  gfx.drawstr(fit_text(state.hint ~= "" and state.hint or
    (state.warning ~= "" and state.warning or state.status), gfx.w - 32))
  if state.overlay then draw_overlay(real_click) end
  -- la rotella vale solo sopra un pomello: quello che nessuno ha usato si butta
  gfx.mouse_wheel = 0
  if (gfx.mouse_cap & 1) == 0 then ZP_UI._knob.drag = nil end
  gfx.update()
end

local function init_gui()
  load_state()
  local w, h = mode_size(state.mode)
  if state.mode ~= "mini" and state.toolbar then h = h + TOOLBAR_H end
  local x = tonumber(ext_get("window_x", "")) or 140
  local y = tonumber(ext_get("window_y", "")) or 120
  local dock = tonumber(ext_get("window_dock", "")) or 0
  gfx.init(SCRIPT_TITLE, w, h, dock, x, y)
  gfx.setfont(1, "Arial", 15)
end

local function main_loop()
  local char = gfx.getchar()
  if char < 0 then
    save_window_state()
    save_state()
    restore_reaper_on_exit()
    return
  end
  -- Casella del marker attiva: i tasti (barra e ? compresi) sono testo. Leggo tutta la coda,
  -- cosi' chi scrive veloce non perde lettere.
  while char > 0 and state.mark_focus and not state.overlay do
    mark_field_key(char)
    char = gfx.getchar()
  end
  if char <= 0 then
  elseif char == 27 and state.overlay then
    toggle_overlay()
  elseif char == 63 then
    toggle_overlay()
  elseif char == 27 then
    -- Esc non chiude: evita chiusure accidentali durante sessione.
    state.status = "Esc ignorato: chiudi dalla X finestra se necessario."
  elseif char == 32 then
    -- Barra: come in REAPER (avvia / ferma). Durante il REC, con Lock REC acceso, non ferma.
    local ps = reaper.GetPlayState()
    if ps & 4 == 4 then
      if state.rec_lock then
        state.status = "REC protetto (Lock REC): per fermare premi STOP."
      else
        stop_transport()
      end
    elseif ps & 1 == 1 then
      stop_transport()
    else
      play_transport()
    end
  end

  process_pending()
  try_pin_window()
  draw_gui()
  save_window_state()
  state.mouse_was_down = (gfx.mouse_cap & 1) == 1
  reaper.defer(main_loop)
end

-- Rete di sicurezza: se lo script viene fermato in un altro modo
-- (Action List, ReaScript ricaricato), REAPER torna comunque su.
reaper.atexit(restore_reaper_on_exit)

init_gui()
main_loop()
