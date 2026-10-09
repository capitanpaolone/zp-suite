-- @noindex
--[[
  ZP SOLO Web - motore (PROTOTIPO, uso locale)
  Autore: Paolo Balestri / ZP Studio Suite

  Script senza finestra che fa da ponte fra REAPER e la pagina zp_solo.html servita
  dall'interfaccia web di REAPER (Preferenze > Control/OSC/web > Web browser interface).

  Il canale e' quello di REAPER: le ExtState, che la pagina legge e scrive con
  /_/GET/EXTSTATE/... e /_/SET/EXTSTATE/...
    ZP_SOLO_WEB/state  (motore -> pagina)  JSON con trasporto, livelli, traccia, marker...
    ZP_SOLO_WEB/cmd    (pagina -> motore)  "id|comando|argomento"; il motore lo esegue una
                                           volta sola e scrive l'id in state.ack
  La pagina non registra niente da sola: i controlli (traccia armata, pre-roll in secondi,
  ingresso vero della scheda, marker numerati) stanno qui, come nel SOLO Recorder.

  Timeline (2026-10-08): ZP_SOLO_WEB/nav (motore -> pagina) con durata, regioni, marker e item della
  traccia armata; si riscrive solo quando il progetto cambia (state.navv dice la versione).
  Il comando "goto|secondi" porta li' il cursore (anche durante la riproduzione).

  Prototipo: trasporto (con pausa, anche del REC), pre-roll, livelli IN/RIT, marker, Save/Undo/Redo. La traccia e'
  quella armata nel progetto (come il Telecomando del SOLO). Si ferma rilanciandolo
  (REAPER chiede se terminarlo) o chiudendo REAPER.
]]

local SEC = "ZP_SOLO_WEB"
local SOLO_SEC = "ZP_SOLO_Recorder"                -- impostazioni condivise col SOLO (pre-roll)
local SOLO_PROJ = "ZP_SOLO_Recorder_Project"       -- contatori marker condivisi col SOLO
local PUBLISH_EVERY = 0.05                         -- 20 aggiornamenti al secondo
local PREROLL_MIN, PREROLL_MAX = 1, 5
local NEXT_GAP = 5.0

local ACTION = { play = 1007, pause = 1008, record = 1013, stop = 1016, save = 40026, undo = 40029, redo = 40030 }

local last_publish, last_cmd, ack, message = 0, nil, "", "Motore web acceso"

-- UTILITA' ------------------------------------------------------------------
local function json_str(s)
  s = tostring(s or "")
  s = s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
    return string.format("\\u%04x", c:byte())
  end)
  return '"' .. s .. '"'
end

local function json(v)
  local t = type(v)
  if t == "table" then
    local parts = {}
    if #v > 0 then
      for _, x in ipairs(v) do parts[#parts + 1] = json(x) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for k, x in pairs(v) do parts[#parts + 1] = json_str(k) .. ":" .. json(x) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    local n = string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", "")
    return n
  elseif t == "boolean" then return v and "true" or "false"
  elseif v == nil then return "null" end
  return json_str(v)
end

local function say(text) message = text end

local function track_name(tr)
  local _, n = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  if n == "" then n = "Traccia " .. math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) end
  return n
end

local function armed_tracks()
  local out = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1 then out[#out + 1] = tr end
  end
  return out
end

local function input_short(tr)
  local v = math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_RECINPUT") or -1)
  if v < 0 then return "nessun ingresso" end
  if v & 4096 ~= 0 then return "MIDI" end
  local idx = v & 1023
  if idx >= 512 then return "ReaRoute " .. (idx - 512 + 1) end
  if v & 2048 ~= 0 then return "In " .. (idx + 1) .. "+ multi" end
  if v & 1024 ~= 0 then return "In " .. (idx + 1) .. "/" .. (idx + 2) end
  return "In " .. (idx + 1)
end

-- Livelli in dB. GetInputActivityLevel restituisce GIA' dB (-150 = silenzio);
-- Track_GetPeakInfo invece ampiezza.
local function amp_db(a)
  a = math.abs(tonumber(a) or 0)
  return a > 0 and 20 * math.log(a, 10) or -150
end

local function track_db(tr)
  if not tr then return nil end
  return amp_db(math.max(math.abs(reaper.Track_GetPeakInfo(tr, 0) or 0), math.abs(reaper.Track_GetPeakInfo(tr, 1) or 0)))
end

local function input_db(tr)
  if not tr then return nil end
  local v = math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_RECINPUT") or -1)
  if v >= 0 and v & 4096 == 0 and (v & 1023) < 512 and reaper.GetInputActivityLevel then
    local idx = v & 1023
    local db = tonumber(reaper.GetInputActivityLevel(idx)) or -150
    if v & 3072 ~= 0 then db = math.max(db, tonumber(reaper.GetInputActivityLevel(idx + 1)) or -150) end
    return db
  end
  return track_db(tr)
end

-- PRE-ROLL (lo stesso del SOLO: config di REAPER, secondi convertiti in misure) ------
local function preroll_api()
  return reaper.SNM_GetIntConfigVar and reaper.SNM_SetIntConfigVar and reaper.SNM_SetDoubleConfigVar
end

local function preroll_on()
  return preroll_api() and (math.floor(reaper.SNM_GetIntConfigVar("preroll", 0)) & 2) == 2 or false
end

local function preroll_s()
  local v = tonumber(reaper.GetExtState(SOLO_SEC, "preroll_s")) or 3
  return math.max(PREROLL_MIN, math.min(PREROLL_MAX, v))
end

local function apply_preroll()
  if not preroll_api() then return end
  local num, denom, bpm = reaper.TimeMap_GetTimeSigAtTime(0, reaper.GetCursorPosition())
  num, denom, bpm = tonumber(num) or 4, tonumber(denom) or 4, tonumber(bpm) or 120
  local meas = (num > 0 and denom > 0 and bpm > 0) and num * (4 / denom) * (60 / bpm) or 2
  reaper.SNM_SetDoubleConfigVar("prerollmeas", preroll_s() / meas)
end

-- MARKER (stessi nomi e contatori del SOLO) ---------------------------------------
local function add_marker(name)
  local pos = (reaper.GetPlayState() & 1 == 1) and reaper.GetPlayPosition() or reaper.GetCursorPosition()
  name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local custom = name ~= ""
  if not custom then
    local _, c = reaper.GetProjExtState(0, SOLO_PROJ, "SOLO_MARK_counter")
    local idx = tonumber(c) or 1
    name = string.format("SOLO_MARK_%03d", idx)
    reaper.SetProjExtState(0, SOLO_PROJ, "SOLO_MARK_counter", tostring(idx + 1))
  end
  reaper.AddProjectMarker2(0, false, pos, 0, name, -1, reaper.ColorToNative(100, 180, 230) | 0x1000000)
  reaper.UpdateArrange()
  say("Marker: " .. name)
end

-- COMANDI DALLA PAGINA --------------------------------------------------------
local COMANDI = {}

COMANDI.rec = function()
  if reaper.GetPlayState() & 4 == 4 then return say("REAPER sta gia' registrando.") end
  local armed = armed_tracks()
  if #armed == 0 then return say("REC bloccato: nessuna traccia armata nel progetto.") end
  if preroll_on() then apply_preroll() end
  reaper.Main_OnCommand(ACTION.record, 0)
  say("REC su " .. track_name(armed[1]) .. (#armed > 1 and (" + " .. (#armed - 1)) or ""))
end
COMANDI.stop = function() reaper.Main_OnCommand(ACTION.stop, 0); say("STOP") end
-- Pausa: la stessa azione mette in pausa e riprende, anche il REC (la registrazione resta aperta).
COMANDI.pause = function()
  local ps = reaper.GetPlayState()
  reaper.Main_OnCommand(ACTION.pause, 0)
  if ps & 4 == 4 then say(ps & 2 == 2 and "REC ripreso" or "REC in pausa: PLAY o PAUSA per riprendere, STOP per chiudere")
  else say(ps & 2 == 2 and "PLAY" or "PAUSA") end
end
-- PLAY durante il REC fa come REAPER: pausa / ripresa.
COMANDI.play = function()
  if reaper.GetPlayState() & 4 == 4 then return COMANDI.pause() end
  reaper.Main_OnCommand(ACTION.play, 0); say("PLAY")
end
COMANDI.back = function()
  reaper.SetEditCurPos(math.max(0, reaper.GetCursorPosition() - 5), true, false); say("Indietro 5 s")
end
COMANDI.fine = function()
  local last
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local it = reaper.GetMediaItem(0, i)
    local e = reaper.GetMediaItemInfo_Value(it, "D_POSITION") + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if not last or e > last then last = e end
  end
  reaper.SetEditCurPos(last and (last + NEXT_GAP) or 0, true, false)
  say(last and "Dopo l'ultimo item + 5 s" or "Nessun item: cursore a 0")
end
COMANDI.preroll = function()
  if not preroll_api() then return say("Il pre-roll in secondi richiede SWS.") end
  local v = math.floor(reaper.SNM_GetIntConfigVar("preroll", 0))
  local on = (v & 2) == 0
  if on then apply_preroll() end
  reaper.SNM_SetIntConfigVar("preroll", on and (v | 2) or (v & ~2))
  say(on and ("Pre-roll acceso, " .. preroll_s() .. " s") or "Pre-roll spento")
end
COMANDI.preroll_s = function(arg)
  local s = math.max(PREROLL_MIN, math.min(PREROLL_MAX, math.floor((tonumber(arg) or 3) + 0.5)))
  reaper.SetExtState(SOLO_SEC, "preroll_s", tostring(s), true)
  apply_preroll()
  say("Pre-roll: " .. s .. " s")
end
COMANDI.mark = function(arg) add_marker(arg) end
COMANDI["goto"] = function(arg)
  local p = tonumber(arg)
  if not p then return say("Posizione non valida") end
  reaper.SetEditCurPos(math.max(0, p), true, true)
  say("Vai a " .. reaper.format_timestr_pos(math.max(0, p), "", 5))
end
COMANDI.save = function() reaper.Main_OnCommand(ACTION.save, 0); say("Progetto salvato") end
COMANDI.undo = function() reaper.Main_OnCommand(ACTION.undo, 0); say("Undo") end
COMANDI.redo = function() reaper.Main_OnCommand(ACTION.redo, 0); say("Redo") end

local function read_command()
  local raw = reaper.GetExtState(SEC, "cmd")
  if raw == "" or raw == last_cmd then return end
  last_cmd = raw   -- REAPER ha gia' tolto la codifica URL (verificato con /_/SET/EXTSTATE)
  local id, verb, arg = raw:match("^([^|]*)|([^|]*)|?(.*)$")
  if not id or id == ack then return end
  ack = id
  local fn = COMANDI[verb]
  if fn then
    local ok, err = pcall(fn, arg)
    if not ok then say("Errore nel comando " .. verb .. ": " .. tostring(err)) end
  else
    say("Comando sconosciuto: " .. tostring(verb))
  end
end

-- STATO PER LA PAGINA ---------------------------------------------------------
local function region_at(pos)
  local _, nm, nr = reaper.CountProjectMarkers(0)
  for i = 0, nm + nr - 1 do
    local _, isrgn, s, e, name, idx = reaper.EnumProjectMarkers3(0, i)
    if isrgn and pos >= s and pos <= e then return name ~= "" and name or ("Regione " .. idx) end
  end
  return "Nessuna regione"
end

-- TIMELINE PER LA PAGINA ------------------------------------------------------
-- Regioni, marker e item della traccia armata (i take), con i colori di REAPER. Pochi dati,
-- riscritti solo quando cambia il progetto (GetProjectStateChangeCount), non 20 volte al secondo.
local MAX_MARKERS, MAX_ITEMS = 400, 600
local nav_count, nav_checked, nav_version = -1, -1000, 0

local function hex_color(native)
  if not native or native == 0 then return nil end
  local r, g, b = reaper.ColorFromNative(native & 0xFFFFFF)
  return string.format("#%02x%02x%02x", r, g, b)
end

local function build_nav()
  local nav = { len = reaper.GetProjectLength(0), regions = {}, markers = {}, items = {} }
  local _, nm, nr = reaper.CountProjectMarkers(0)
  for i = 0, nm + nr - 1 do
    local _, isrgn, s, e, name, idx, color = reaper.EnumProjectMarkers3(0, i)
    if isrgn then
      nav.regions[#nav.regions + 1] = { s = s, e = e, n = name ~= "" and name or ("Regione " .. idx), c = hex_color(color) }
    elseif #nav.markers < MAX_MARKERS then
      nav.markers[#nav.markers + 1] = { p = s, n = name, c = hex_color(color) }
    end
    if e > nav.len then nav.len = e end
  end
  local tr = armed_tracks()[1]
  if tr then
    nav.track = track_name(tr)
    for i = 0, math.min(reaper.CountTrackMediaItems(tr), MAX_ITEMS) - 1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      nav.items[#nav.items + 1] = { s = p, e = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH") }
    end
  end
  return nav
end

local function refresh_nav(now)
  if now - nav_checked < 0.5 then return end
  nav_checked = now
  local c = reaper.GetProjectStateChangeCount(0)
  if c == nav_count then return end
  nav_count = c
  nav_version = nav_version + 1
  reaper.SetExtState(SEC, "nav", json(build_nav()), false)
end

-- CONDIVIDI ----------------------------------------------------------------------
-- Indirizzi con cui altri dispositivi della stessa rete aprono la pagina: IP del computer in
-- rete locale + porta dell'interfaccia web di REAPER. Si ricalcolano ogni minuto (rete cambiata).
-- Per la versione online questo diventera' il link della sessione sul ponte remoto.
local share, last_share = {}, -1000

local function web_port()
  local f = io.open(reaper.get_ini_file(), "r")
  if not f then return nil end
  local ini = "\n" .. f:read("a"); f:close()
  local cnt = tonumber(ini:match("\ncsurf_cnt=(%d+)")) or 0
  for i = 0, cnt - 1 do
    local port = ini:match("\ncsurf_" .. i .. "=HTTP %-?%d+ (%d+)")
    if port then return port end
  end
  return nil
end

-- Indirizzi IPv4 di rete locale dal testo dei comandi di sistema (esclusi 127.x e 169.254.x).
local function lan_ips(text)
  local out, seen = {}, {}
  for ip in (text or ""):gmatch("(%d+%.%d+%.%d+%.%d+)") do
    if not ip:match("^127%.") and not ip:match("^169%.254%.") and not ip:match("^0%.") and not ip:match("%.255$")
      and not ip:match("^255%.") and not seen[ip] then
      seen[ip] = true; out[#out + 1] = ip
    end
  end
  return out
end

local function system_ips()
  local os_name = reaper.GetOS() or ""
  local cmd
  if os_name:match("Win") then cmd = 'ipconfig | findstr /R /C:"IPv4"'
  elseif os_name:match("OSX") or os_name:match("macOS") then
    cmd = "for i in 0 1 2 3 4 5 6 7 8; do ipconfig getifaddr en$i; done 2>/dev/null"
  else cmd = "hostname -I 2>/dev/null" end
  local p = io.popen(cmd)
  if not p then return {} end
  local txt = p:read("a") or ""; p:close()
  return lan_ips(txt)
end

local function refresh_share(now)
  if now - last_share < 60 then return end
  last_share = now
  local port = web_port()
  share = {}
  if not port then return end
  for _, ip in ipairs(system_ips()) do share[#share + 1] = "http://" .. ip .. ":" .. port .. "/zp_solo.html" end
end

local function publish()
  local ps = reaper.GetPlayState()
  local pos = (ps & 1 == 1) and reaper.GetPlayPosition() or reaper.GetCursorPosition()
  local armed = armed_tracks()
  local tr = armed[1]
  local st = {
    v = 1,
    t = reaper.time_precise(),
    ack = ack,
    msg = message,
    transport = (ps & 6 == 6) and "REC_PAUSE" or (ps & 4 == 4) and "REC" or (ps & 2 == 2) and "PAUSE" or (ps & 1 == 1) and "PLAY" or "STOP",
    pos = pos,
    tc = reaper.format_timestr_pos(pos, "", 5),
    track = tr and track_name(tr) or "",
    armed = #armed,
    input = tr and input_short(tr) or "",
    in_db = input_db(tr),
    rit_db = track_db(reaper.GetMasterTrack(0)),
    region = region_at(pos),
    preroll = preroll_on(),
    preroll_s = preroll_s(),
    sws = preroll_api() and true or false,
    dirty = reaper.IsProjectDirty(0) ~= 0,
    can_undo = reaper.Undo_CanUndo2(0) ~= nil,
    can_redo = reaper.Undo_CanRedo2(0) ~= nil,
    share = share,
    navv = nav_version,
    lang = (reaper.GetExtState("ZP_STUDIO_SUITE", "lingua") == "en") and "en" or "it",
  }
  reaper.SetExtState(SEC, "state", json(st), false)
end

local function loop()
  read_command()
  local now = reaper.time_precise()
  if now - last_publish >= PUBLISH_EVERY then
    last_publish = now
    refresh_share(now)
    refresh_nav(now)
    publish()
  end
  reaper.defer(loop)
end

local function on_exit()
  reaper.SetExtState(SEC, "state", json({ v = 1, t = 0, off = true, msg = "Motore web spento" }), false)
  if reaper.set_action_options then reaper.set_action_options(8) end
end

-- un comando rimasto da prima non va rieseguito
last_cmd = reaper.GetExtState(SEC, "cmd")
local rid = last_cmd:match("^([^|]*)|")
if rid then ack = rid end
if reaper.set_action_options then reaper.set_action_options(1 | 4) end   -- rilancio = termina; spia accesa
reaper.atexit(on_exit)
loop()
