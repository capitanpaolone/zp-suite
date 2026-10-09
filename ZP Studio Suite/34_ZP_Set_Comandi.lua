-- @noindex

-- ZP Studio Suite for REAPER
-- 34 ZP Set Comandi: set di scorciatoie da tastiera da salvare e scegliere con un clic
-- (montaggio video, abitudini Pro Tools o Logic, set personali...).
--
-- I set sono file .ReaperKeyMap nella cartella REAPER/KeyMaps (quelli che ci sono gia' compaiono
-- da soli). Un set cambia SOLO le scorciatoie (righe KEY di reaper-kb.ini): gli script e le azioni
-- personalizzate registrate (SCR/ACT) restano tutti, cosi' toolbar e menu non perdono pulsanti.
--
-- Come si applica: reaper-kb.ini non si scrive mai con REAPER aperto (lo riscriverebbe lui).
-- "Attiva" prepara il set in KeyMaps/ZP_Set_in_attesa.txt e avvia un piccolo script di sistema
-- che aspetta la chiusura di REAPER, fa un backup di reaper-kb.ini, sostituisce le righe KEY e,
-- se richiesto, riapre REAPER. Prima di ogni cambio i tasti in uso vanno in "Backup automatico".

local M = {}

M.PENDING = "ZP_Set_in_attesa.txt"
M.BACKUP_NAME = "Backup automatico"
M.EXT = ".ReaperKeyMap"
M.STOCK = "REAPER di serie"

---------------------------------------------------------------------------
-- LOGICA PURA (collaudabile con lua fuori da REAPER)
---------------------------------------------------------------------------

local function lines(text)
  local t = {}
  for l in (tostring(text or ""):gsub("\r", "") .. "\n"):gmatch("([^\n]*)\n") do
    if l ~= "" then t[#t + 1] = l end
  end
  return t
end

-- Riga KEY -> chiave "modificatori tasto comando sezione" (senza il commento finale)
function M.key_sig(line)
  local a, b, c, d = line:match("^KEY%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
  return a and (a .. " " .. b .. " " .. c .. " " .. d) or nil
end

-- Identificativo di una riga SCR/ACT (quello che le righe KEY richiamano con "_" davanti)
function M.def_id(line)
  local id = line:match("^SCR%s+%S+%s+%S+%s+(%S+)")
  if id then return id end
  return line:match('^ACT%s+%S+%s+%S+%s+"([^"]+)"')
end

-- Riassunto di un set: scorciatoie vere (comando ~= 0), tasti OSARA, insieme delle chiavi.
function M.info(text)
  local n, osara, sigs, count = 0, false, {}, 0
  for _, l in ipairs(lines(text)) do
    local sig = M.key_sig(l)
    if sig then
      sigs[sig] = true
      count = count + 1
      local cmd = sig:match("^%S+ %S+ (%S+)")
      if cmd ~= "0" then n = n + 1 end
      if cmd:upper():find("OSARA", 1, true) then osara = true end
    end
  end
  return { keys = n, osara = osara, sigs = sigs, lines = count }
end

-- Due set hanno le stesse scorciatoie (l'ordine non conta)?
function M.same_keys(a, b)
  for k in pairs(a.sigs) do if not b.sigs[k] then return false end end
  for k in pairs(b.sigs) do if not a.sigs[k] then return false end end
  return true
end

-- Da reaper-kb.ini al file del set: le righe KEY, le azioni personalizzate (ACT) e gli script
-- (SCR) che i tasti o le azioni richiamano. Gli altri script non servono al set.
function M.extract_set(kb_text)
  local all = lines(kb_text)
  local wanted, keys, acts = {}, {}, {}
  for _, l in ipairs(all) do
    if l:match("^KEY%s") then
      keys[#keys + 1] = l
      local cmd = (M.key_sig(l) or ""):match("^%S+ %S+ (%S+)")
      if cmd and cmd:sub(1, 1) == "_" then wanted[cmd:sub(2)] = true end
    elseif l:match("^ACT%s") then
      acts[#acts + 1] = l
      for ref in l:gmatch("_(RS[%w_]+)") do wanted[ref] = true end
    end
  end
  local out = {}
  for _, l in ipairs(acts) do out[#out + 1] = l end
  for _, l in ipairs(all) do
    if l:match("^SCR%s") and wanted[M.def_id(l) or ""] then out[#out + 1] = l end
  end
  for _, l in ipairs(keys) do out[#out + 1] = l end
  return table.concat(out, "\n") .. (#out > 0 and "\n" or "")
end

-- Righe da aggiungere a reaper-kb.ini (dopo aver tolto le sue righe KEY): le azioni e gli script
-- del set che qui non ci sono ancora (per identificativo), poi tutte le righe KEY del set.
function M.payload(kb_text, set_text)
  local have = {}
  for _, l in ipairs(lines(kb_text)) do
    local id = (l:match("^SCR%s") or l:match("^ACT%s")) and M.def_id(l)
    if id then have[id] = true end
  end
  local defs, keys = {}, {}
  for _, l in ipairs(lines(set_text)) do
    if l:match("^KEY%s") then keys[#keys + 1] = l
    elseif l:match("^SCR%s") or l:match("^ACT%s") then
      local id = M.def_id(l)
      if id and not have[id] then defs[#defs + 1] = l; have[id] = true end
    end
  end
  local out = {}
  for _, l in ipairs(defs) do out[#out + 1] = l end
  for _, l in ipairs(keys) do out[#out + 1] = l end
  return table.concat(out, "\n") .. (#out > 0 and "\n" or "")
end

-- Quello che fa lo script di sistema a REAPER chiuso (qui per collaudarlo):
-- reaper-kb.ini senza righe KEY + payload.
function M.apply(kb_text, payload)
  local out = {}
  for _, l in ipairs(lines(kb_text)) do if not l:match("^KEY ") then out[#out + 1] = l end end
  for _, l in ipairs(lines(payload)) do out[#out + 1] = l end
  return table.concat(out, "\n") .. "\n"
end

-- Nome di file accettabile per un set scritto dall'utente
function M.safe_name(name)
  name = tostring(name or ""):gsub("[/\\:%*%?\"<>|%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #name > 60 then name = name:sub(1, 60):gsub("%s+$", "") end
  return name
end

-- Script di sistema (macOS / Linux): aspetta che REAPER sia chiuso, poi applica.
local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
-- proc: nomi del processo da aspettare (di serie REAPER e reaper; i test ne passano uno inesistente)
function M.waiter_sh(kb, pending, app, reopen, proc)
  local wait = {}
  for _, p in ipairs(proc or { "REAPER", "reaper" }) do wait[#wait + 1] = "pgrep -x " .. shq(p) .. " >/dev/null 2>&1" end
  return table.concat({
    "#!/bin/sh",
    "# ZP Set Comandi: aspetta la chiusura di REAPER, poi cambia le scorciatoie in reaper-kb.ini.",
    "KB=" .. shq(kb),
    "NEW=" .. shq(pending),
    "while " .. table.concat(wait, " || ") .. "; do sleep 1; done",
    "sleep 1",
    "[ -f \"$NEW\" ] || exit 0",
    "cp \"$KB\" \"$KB.ZP_backup_$(date +%Y%m%d_%H%M%S)\" || exit 1",
    "{ grep -v '^KEY ' \"$KB\"; cat \"$NEW\"; } > \"$KB.zp_nuovo\" && mv \"$KB.zp_nuovo\" \"$KB\" && mv \"$NEW\" \"$NEW.applicato\"",
    reopen and app and ("open " .. shq(app)) or "",
    "",
  }, "\n")
end

-- Script di sistema (Windows, PowerShell): stessa cosa.
function M.waiter_ps1(kb, pending, exe, reopen)
  local function psq(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end
  return table.concat({
    "# ZP Set Comandi: aspetta la chiusura di REAPER, poi cambia le scorciatoie in reaper-kb.ini.",
    "$kb = " .. psq(kb),
    "$new = " .. psq(pending),
    "Wait-Process -Name reaper -ErrorAction SilentlyContinue",
    "Start-Sleep -Seconds 1",
    "if (-not (Test-Path -LiteralPath $new)) { exit 0 }",
    "Copy-Item -LiteralPath $kb -Destination ($kb + '.ZP_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))",
    "$keep = [IO.File]::ReadAllLines($kb) | Where-Object { $_ -notmatch '^KEY ' }",
    "$add = [IO.File]::ReadAllLines($new)",
    "[IO.File]::WriteAllLines($kb, [string[]]($keep + $add), (New-Object Text.UTF8Encoding($false)))",
    "Move-Item -LiteralPath $new -Destination ($new + '.applicato') -Force",
    reopen and exe and ("Start-Process " .. psq(exe)) or "",
    "",
  }, "\r\n")
end

-- Nome leggibile del tasto di una riga KEY senza commento (i file esportati da REAPER lo hanno
-- gia' nel commento "# Main : Cmd+K : ..."). mods: 1 = tasto virtuale, 4 Shift, 8 Cmd/Ctrl,
-- 16 Opt/Alt, 32 Control/Win; 255 = rotella e gesti; senza bit 1 il codice e' un carattere.
local VK = { [8] = "Backspace", [9] = "Tab", [13] = "Invio", [27] = "Esc", [32] = "Spazio",
  [33] = "Pagina su", [34] = "Pagina giu'", [35] = "Fine", [36] = "Inizio", [37] = "Freccia sinistra",
  [38] = "Freccia su", [39] = "Freccia destra", [40] = "Freccia giu'", [45] = "Ins", [46] = "Canc",
  [186] = ";", [187] = "=", [188] = ",", [189] = "-", [190] = ".", [191] = "/", [192] = "`",
  [219] = "[", [220] = "\\", [221] = "]", [222] = "'" }
local WHEEL = { [248] = "Rotella", [249] = "Rotella", [218] = "Rotella orizzontale", [250] = "Rotella" }
function M.key_name(mods, code, mac)
  mods, code = tonumber(mods) or 0, tonumber(code) or 0
  local name
  if mods == 255 then
    name = WHEEL[code & 0xFF] or ("Gesto " .. code)
  elseif mods & 1 == 0 then
    name = (code >= 32 and code < 127) and string.char(code) or ("Tasto " .. code)
  elseif code >= 65 and code <= 90 or code >= 48 and code <= 57 then name = string.char(code)
  elseif code >= 112 and code <= 135 then name = "F" .. (code - 111)
  elseif code >= 96 and code <= 105 then name = "Tastierino " .. (code - 96)
  else name = VK[code] or ("Tasto " .. code) end
  local pre = {}
  if mods ~= 255 then
    if mods & 8 ~= 0 then pre[#pre + 1] = mac and "Cmd" or "Ctrl" end
    if mods & 16 ~= 0 then pre[#pre + 1] = mac and "Opt" or "Alt" end
    if mods & 32 ~= 0 then pre[#pre + 1] = mac and "Control" or "Win" end
    if mods & 4 ~= 0 then pre[#pre + 1] = "Shift" end
  end
  pre[#pre + 1] = name
  return table.concat(pre, "+")
end

local SECTIONS = { ["0"] = "", ["32060"] = "MIDI: ", ["32061"] = "Lista eventi MIDI: ",
  ["32062"] = "MIDI in linea: ", ["32063"] = "Media Explorer: " }

-- Elenco leggibile di un set: { key, action, off } per riga KEY. action_name(cmd, section) da
-- REAPER (puo' mancare): serve per le righe senza commento. off = tasto di serie spento.
function M.listing(text, action_name, mac)
  local out = {}
  for _, l in ipairs(lines(text)) do
    local mods, code, cmd, sec = l:match("^KEY%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
    if mods then
      local comment = l:match("#%s*(.-)%s*$")
      local parts = {}
      if comment then for p in (comment .. " : "):gmatch("(.-)%s+:%s+") do parts[#parts + 1] = p end end
      local key = parts[2] or M.key_name(mods, code, mac)
      local off = cmd == "0"
      local act = off and "tasto di serie spento" or (#parts >= 3 and parts[#parts] or nil)
      if not act or act == "" then act = action_name and action_name(cmd, tonumber(sec) or 0) or nil end
      if not act or act == "" then act = "azione " .. cmd end
      out[#out + 1] = { key = (SECTIONS[sec] or "") .. key, action = act, off = off }
    end
  end
  local on, offs = {}, {}  -- prima le scorciatoie vere, poi i tasti spenti (ordine del file)
  for _, r in ipairs(out) do if r.off then offs[#offs + 1] = r else on[#on + 1] = r end end
  for _, r in ipairs(offs) do on[#on + 1] = r end
  return on
end

-- Testo per l'AI: una riga "tasto -> azione" per scorciatoia; i tasti di serie spenti in una riga sola.
function M.listing_text(list)
  local t, off = {}, 0
  for _, r in ipairs(list) do
    if r.off then off = off + 1 else t[#t + 1] = r.key .. " -> " .. r.action end
  end
  if off > 0 then t[#t + 1] = off .. " default keys disabled (no action)" end
  return table.concat(t, "\n") .. "\n"
end

if not reaper then return M end

---------------------------------------------------------------------------
-- PARTE REAPER
---------------------------------------------------------------------------

local sep = package.config:sub(1, 1)
local here = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or ".")
local UI = dofile(here .. sep .. "ZP_UI.lua")
local A = dofile(here .. sep .. "ZP_Agenti.lua")
local T = UI.T or function(s) return s end
local resource = reaper.GetResourcePath()
local KB = resource .. sep .. "reaper-kb.ini"
local DIR = resource .. sep .. "KeyMaps"
local PENDING = DIR .. sep .. M.PENDING
local IS_WIN = reaper.GetOS():match("Win") ~= nil
local SECTION = "ZP_SET_COMANDI"

reaper.RecursiveCreateDirectory(DIR, 0)

local function read(p) local f = io.open(p, "rb"); if not f then return nil end local d = f:read("*a"); f:close(); return d end
local function write(p, d) local f = io.open(p, "wb"); if not f then return false end f:write(d); f:close(); return true end
local function say(msg) if reaper.osara_outputMessage then reaper.osara_outputMessage(msg) end end

local S = { sets = {}, status = "", status_ok = true, scroll = 0, last_cap = 0 }

-- Data di salvataggio dei set fatti qui (ExtState: nome -> data)
local function saved_date(name) return reaper.GetExtState(SECTION, "data_" .. name) end

local function load_sets()
  local current = M.info(read(KB) or "")
  local pending_text = read(PENDING)
  local pending_info = pending_text and M.info(pending_text) or nil
  S.current = current
  S.pending_name = pending_text and reaper.GetExtState(SECTION, "in_attesa") or nil
  if S.pending_name == "" then S.pending_name = "set scelto" end
  local sets, i = {}, 0
  while true do
    local f = reaper.EnumerateFiles(DIR, i)
    if not f then break end
    if f:sub(-#M.EXT):lower() == M.EXT:lower() then
      local name = f:sub(1, -#M.EXT - 1)
      local text = read(DIR .. sep .. f) or ""
      local info = M.info(text)
      sets[#sets + 1] = { name = name, file = DIR .. sep .. f, info = info, text = text,
        in_use = M.same_keys(info, current), pending = pending_info and M.same_keys(info, pending_info) or false }
    end
    i = i + 1
  end
  table.sort(sets, function(a, b)
    if (a.name == M.BACKUP_NAME) ~= (b.name == M.BACKUP_NAME) then return b.name == M.BACKUP_NAME end
    return a.name:lower() < b.name:lower()
  end)
  local stock = M.info("")
  sets[#sets + 1] = { name = M.STOCK, stock = true, info = stock, text = "",
    in_use = M.same_keys(stock, current), pending = pending_info and M.same_keys(stock, pending_info) or false }
  S.sets = sets
  if S.view then -- la pagina aperta segue il set ricaricato (stato IN USO / AL RIAVVIO)
    local found
    for _, x in ipairs(sets) do if x.name == S.view.name then found = x end end
    S.view = found
  end
end

local function set_status(msg, ok) S.status, S.status_ok = msg, ok ~= false; say(msg) end

local function detail(s)
  if s.stock then return T("Nessuna scorciatoia personale: i tasti originali di REAPER") end
  local parts = { s.info.keys .. (s.info.keys == 1 and T(" scorciatoia") or T(" scorciatoie")) }
  local d = saved_date(s.name)
  if s.name == M.BACKUP_NAME then parts[#parts + 1] = T("i tasti di prima dell'ultimo cambio")
  elseif d ~= "" then parts[#parts + 1] = T("salvato il ") .. d end
  if s.info.osara then parts[#parts + 1] = T("con i tasti OSARA") end
  return table.concat(parts, "  ·  ")
end

local function app_path()
  local exe = reaper.GetExePath() or ""
  local app = exe:match("^(.-%.app)")
  if app then return app end
  local f = io.open(exe .. "/REAPER.app/Contents/Info.plist", "rb")
  if f then f:close(); return exe .. "/REAPER.app" end
  return "/Applications/REAPER.app"
end

local function start_waiter(reopen)
  if IS_WIN then
    local ps = resource .. sep .. "ZP_Set_Comandi_cambio.ps1"
    if not write(ps, M.waiter_ps1(KB, PENDING, reaper.GetExePath() .. sep .. "reaper.exe", reopen)) then return false end
    os.execute('start "" /B powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' .. ps .. '"')
  else
    local sh = resource .. sep .. "ZP_Set_Comandi_cambio.sh"
    if not write(sh, M.waiter_sh(KB, PENDING, app_path(), reopen)) then return false end
    os.execute("nohup /bin/sh " .. shq(sh) .. " >/dev/null 2>&1 &")
  end
  return true
end

local function cancel_pending()
  if os.rename(PENDING, PENDING .. ".annullato") then
    reaper.SetExtState(SECTION, "in_attesa", "", true)
    set_status(T("Cambio annullato: al riavvio restano i tasti di adesso."))
  end
  load_sets()
end

local function activate(s)
  if s.in_use then
    if S.pending_name then return cancel_pending() end -- tornare a quello in uso = annullare il cambio
    return set_status(string.format(T("\"%s\" e' gia' in uso."), s.name))
  end
  local warn_osara = S.current.osara and not s.info.osara and not s.stock
  local msg = T("Attivare il set \"") .. s.name ..
    T("\"?\n\nLe scorciatoie cambiano quando REAPER si riapre. Script, azioni e toolbar restano come sono.\nPrima del cambio i tasti di adesso vanno nel set \"") ..
    T(M.BACKUP_NAME) .. T("\".\n\n") ..
    (warn_osara and T("ATTENZIONE: questo set non ha i tasti di OSARA, che adesso usi.\n\n") or "") ..
    T("Si' = chiudi e riapri REAPER adesso (salva prima il progetto)\nNo = piu' tardi: vale dal prossimo riavvio\nAnnulla = non cambiare niente")
  local r = reaper.MB(msg, T("ZP Set Comandi"), 3)
  if r ~= 6 and r ~= 7 then return end
  local kb = read(KB)
  if not kb then return set_status(T("Non riesco a leggere reaper-kb.ini"), false) end
  if not write(DIR .. sep .. M.BACKUP_NAME .. M.EXT, M.extract_set(kb)) then
    return set_status(T("Non riesco a scrivere il backup in KeyMaps: niente cambiato"), false)
  end
  reaper.SetExtState(SECTION, "data_" .. M.BACKUP_NAME, os.date("%d/%m/%Y %H:%M"), true)
  if not write(PENDING, M.payload(kb, s.text)) then return set_status(T("Non riesco a preparare il set"), false) end
  reaper.SetExtState(SECTION, "in_attesa", s.name, true)
  if not start_waiter(r == 6) then
    os.rename(PENDING, PENDING .. ".annullato")
    return set_status(T("Non riesco ad avviare il cambio: niente cambiato"), false)
  end
  if r == 6 then
    say(T("Chiudo REAPER per attivare ") .. s.name)
    reaper.Main_OnCommand(40004, 0) -- File: Quit REAPER (chiede di salvare i progetti)
  end
  set_status("\"" .. s.name .. T("\" sara' attivo dal prossimo riavvio di REAPER."))
  load_sets()
end

local function save_current()
  local ok, name = reaper.GetUserInputs(T("ZP Set Comandi: salva i tasti attuali"), 1,
    T("Nome del set (es. Video, Doppiaggio):,extrawidth=220"), "")
  if not ok then return end
  name = M.safe_name(name)
  if name == "" or name == M.STOCK or name == M.BACKUP_NAME then return set_status(T("Scegli un altro nome."), false) end
  local path = DIR .. sep .. name .. M.EXT
  if read(path) and reaper.MB(T("Esiste gia' un set \"") .. name .. T("\". Lo sostituisco con i tasti attuali?"), T("ZP Set Comandi"), 4) ~= 6 then return end
  local kb = read(KB)
  if not kb or not write(path, M.extract_set(kb)) then return set_status(T("Non riesco a salvare il set"), false) end
  reaper.SetExtState(SECTION, "data_" .. name, os.date("%d/%m/%Y"), true)
  set_status(string.format(T("Salvato \"%s\" con %d scorciatoie."), name, M.info(kb).keys))
  load_sets()
end

local function import_file()
  local ok, src = reaper.GetUserFileNameForRead("", T("ZP Set Comandi: scegli un file di scorciatoie"), "ReaperKeyMap")
  if not ok or src == "" then return end
  local text = read(src)
  if not text or M.info(text).lines == 0 then return set_status(T("Il file non contiene scorciatoie di REAPER."), false) end
  local name = M.safe_name((src:match("([^/\\]+)$") or "Importato"):gsub("%.[^.]+$", ""))
  local dest = DIR .. sep .. name .. M.EXT
  if read(dest) then name = name .. " " .. os.date("%H%M%S"); dest = DIR .. sep .. name .. M.EXT end
  if not write(dest, text) then return set_status(T("Non riesco a copiarlo in KeyMaps"), false) end
  reaper.SetExtState(SECTION, "data_" .. name, "importato " .. os.date("%d/%m/%Y"), true)
  set_status(T("Importato \"") .. name .. T("\": ora e' nell'elenco."))
  load_sets()
end

local function open_folder()
  if IS_WIN then os.execute('explorer "' .. DIR .. '"')
  else os.execute("open " .. shq(DIR)) end
end

-- Spiegazione di un set: file di testo accanto al set (resta anche se il set cambia nome o va in archivio)
local function expl_path(name) return DIR .. sep .. name .. ".spiegazione.txt" end
local function explanation(s) return not s.stock and read(expl_path(s.name)) or nil end

local function move_set(s, new_dir, new_name)
  local dest = new_dir .. sep .. new_name .. M.EXT
  if read(dest) then return false end
  if not os.rename(s.file, dest) then return false end
  os.rename(expl_path(s.name), new_dir .. sep .. new_name .. ".spiegazione.txt")
  local d = saved_date(s.name)
  if d ~= "" then reaper.SetExtState(SECTION, "data_" .. new_name, d, true) end
  return true
end

local function rename_set(s)
  if s.stock then return end
  local ok, name = reaper.GetUserInputs(T("ZP Set Comandi: rinomina"), 1, T("Nuovo nome:,extrawidth=240"), s.name)
  if not ok then return end
  name = M.safe_name(name)
  if name == "" or name == s.name or name == M.STOCK then return end
  if not move_set(s, DIR, name) then return set_status(T("Non riesco: c'e' gia' un set \"") .. name .. T("\"?"), false) end
  reaper.DeleteExtState(SECTION, "data_" .. s.name, true)
  set_status(T("Ora si chiama \"") .. name .. T("\"."))
  load_sets()
  for _, x in ipairs(S.sets) do if x.name == name then S.view = x end end
end

-- Archivia: il set va in KeyMaps/Archivio (niente si cancella; si riprende con Apri cartella).
local function archive_set(s)
  if s.stock then return end
  local msg = string.format(
    T("Metto \"%s\" in archivio?\n\nNon si cancella: va nella cartella KeyMaps/Archivio e sparisce da questo elenco. Per riaverlo, rimettilo in KeyMaps (Apri cartella)."),
    s.name
  )
  if reaper.MB(msg, T("ZP Set Comandi"), 4) ~= 6 then return end
  local arch = DIR .. sep .. "Archivio"
  reaper.RecursiveCreateDirectory(arch, 0)
  local name = s.name
  if read(arch .. sep .. name .. M.EXT) then name = name .. " " .. os.date("%Y%m%d_%H%M%S") end
  if not move_set(s, arch, name) then return set_status(T("Non riesco a spostarlo in Archivio"), false) end
  S.view = nil
  set_status("\"" .. s.name .. T("\" e' in KeyMaps/Archivio."))
  load_sets()
end

-- Spiega con l'AI (facoltativo, a richiesta): ZP Speech explain-keys in background.
local MAC = not IS_WIN
local function agents()
  if not S.agents then S.agents = A.load() end
  return S.agents
end
local JOBS = resource .. sep .. "ZP_jobs"
local function action_name(cmd, section)
  local n = tonumber(cmd) or reaper.NamedCommandLookup(cmd)
  if not n or n == 0 then return nil end
  if reaper.CF_GetCommandText then -- SWS: sezione per numero
    local ok, t = pcall(reaper.CF_GetCommandText, section, n)
    if ok and t and t ~= "" then return t end
  end
  if reaper.kbd_getTextFromCmd then -- senza SWS: la sezione va passata come puntatore
    local sec = reaper.SectionFromUniqueID and reaper.SectionFromUniqueID(section) or nil
    local ok, t = pcall(reaper.kbd_getTextFromCmd, n, sec)
    if ok and t and t ~= "" then return t end
  end
  return nil
end

local function explain_ai(s)
  if S.ai then return set_status(T("Aspetta: l'AI sta gia' scrivendo una spiegazione."), false) end
  local cli = A.cli()
  if IS_WIN or not read(cli) then
    return set_status(T("Spiega con l'AI usa ZP Speech (macOS): non e' installato qui."), false)
  end
  local engine = A.resolve(agents(), A.get())
  if not engine then return set_status(T("Nessun agente AI trovato su questo Mac (Codex, Claude, Qwen, OpenCode, Ollama)."), false) end
  local list = M.listing(s.text, action_name, MAC)
  local n = 0
  for _, r in ipairs(list) do if not r.off then n = n + 1 end end
  if n == 0 then return set_status(T("Questo set non ha scorciatoie da spiegare."), false) end
  local agent_label = (A.NAMES[engine] or engine) .. ". " .. A.where(engine)
  local msg = string.format(
    T("Chiedo all'AI una spiegazione breve di \"%s\".\n\nMando SOLO l'elenco delle %d scorciatoie (tasto e nome dell'azione), niente altro.\nAgente: %s\n\nLa spiegazione resta salvata accanto al set. Procedo?"),
    s.name, n, agent_label
  )
  if reaper.MB(msg, T("ZP Set Comandi - Spiega con l'AI"), 4) ~= 6 then return end
  reaper.RecursiveCreateDirectory(JOBS, 0)
  local base = JOBS .. sep .. "setcomandi_" .. os.date("%Y%m%d_%H%M%S")
  write(base .. "_elenco.txt", M.listing_text(list))
  os.remove(base .. "_fine")
  os.execute("( " .. shq(cli) .. " explain-keys " .. shq(base .. "_elenco.txt") .. " --engine " .. shq(engine) .. " --output " .. shq(base .. "_spiegazione.txt") ..
    " 2> " .. shq(base .. "_errori.txt") .. "; echo $? > " .. shq(base .. "_fine") .. " ) >/dev/null 2>&1 &")
  S.ai = { base = base, name = s.name, t0 = reaper.time_precise() }
  set_status(T("L'AI sta scrivendo la spiegazione di \"") .. s.name .. T("\"…"))
end

local function poll_ai()
  if not S.ai or reaper.time_precise() - (S.ai.last or 0) < 0.5 then return end
  S.ai.last = reaper.time_precise()
  local code = read(S.ai.base .. "_fine")
  if not code then return end
  local answer = read(S.ai.base .. "_spiegazione.txt")
  if tonumber(code) == 0 and answer and answer:match("%S") then
    write(expl_path(S.ai.name), answer)
    set_status(T("Spiegazione pronta per \"") .. S.ai.name .. T("\"."))
  else
    local err = (read(S.ai.base .. "_errori.txt") or ""):gsub("%s+$", ""):match("([^\n]*)$") or ""
    set_status(T("L'AI non ha risposto: ") .. (err ~= "" and err or T("errore sconosciuto")), false)
  end
  S.ai = nil
end

---------------------------------------------------------------------------
-- FINESTRA
---------------------------------------------------------------------------

local W, H = 660, 780
local TEAL = { 0.10, 0.74, 0.60, 1 }
local YELLOW = { 1.0, 0.82, 0.30, 1 }
local SOFT = { 0.82, 0.82, 0.88, 1 }

local function text(s, x, y, size, col, bold)
  gfx.setfont(1, "Arial", size, bold and "b" or nil)
  UI.set_color(col or UI.colors.text)
  gfx.x, gfx.y = x, y
  gfx.drawstr(s)
end

local function header(clicked)
  UI.draw_header({ title = T("ZP Set Comandi"), title_size = 22, credit_size = 13,
    fallback_icon = function(x, y, s)
      UI.set_color({ 0.20, 0.22, 0.26, 1 }); UI.fill_round(x, y, s, s, 6)
      UI.set_color(UI.colors.text)
      for r = 0, 2 do for c = 0, 3 do gfx.rect(x + 5 + c * 7, y + 8 + r * 7, 5, 5, true) end end
    end })
  UI.draw_help_button({ x = gfx.w - 56, y = 18, w = 38, h = 32, font = 17 }, clicked, "tool-34")
end

local function status_line(x, w)
  if S.status ~= "" then text(UI.fit_text(S.status, w), x, gfx.h - 92, 15, S.status_ok and TEAL or { 1, 0.45, 0.40, 1 }) end
end

local function scrollbar(top, bottom, total, max_scroll, scroll)
  if max_scroll <= 0 then return end
  local track_h = bottom - top
  local thumb = math.max(30, track_h * track_h / total)
  local ty = top + (track_h - thumb) * (scroll / max_scroll)
  UI.set_color({ 0.20, 0.20, 0.26, 1 }); gfx.rect(gfx.w - 14, top, 6, track_h, true)
  UI.set_color({ 0.60, 0.62, 0.72, 1 }); gfx.rect(gfx.w - 14, ty, 6, thumb, true)
end

local function wheel(max_scroll, key)
  if gfx.mouse_wheel ~= 0 then S[key] = (S[key] or 0) - gfx.mouse_wheel / 4; gfx.mouse_wheel = 0 end
  S[key] = math.max(0, math.min(max_scroll, S[key] or 0))
  return S[key]
end

-- Pagina di un set: spiegazione, tutte le scorciatoie, Attiva / Rinomina / Archivia.
local function draw_detail(clicked)
  local s = S.view
  local x, y, w = 22, 70, gfx.w - 44
  if UI.draw_button({ x = x, y = y, w = 130, h = 34, font = 16 }, T("← Elenco"), false, true, clicked) then S.view = nil; return end
  text(UI.fit_text(s.name, w - 150), x + 146, y + 6, 20, s.in_use and TEAL or UI.colors.text, true)
  y = y + 46
  text(UI.fit_text((s.in_use and T("IN USO  ·  ") or "") .. (s.stock and T("I tasti originali di REAPER") or detail(s)), w), x, y, 16, SOFT)
  y = y + 28
  -- spiegazione
  local ex = explanation(s)
  local busy = S.ai and S.ai.name == s.name
  gfx.setfont(1, "Arial", 16)
  local ex_lines = ex and UI.wrap_text((ex:gsub("%s+$", "")), w - 24) or nil
  local box_h = ex_lines and math.min(#ex_lines, 10) * 21 + 20 or 56
  UI.set_color(UI.colors.panel); UI.fill_round(x, y, w, box_h, 6)
  if ex_lines then
    for i = 1, math.min(#ex_lines, 10) do text(ex_lines[i], x + 12, y + 10 + (i - 1) * 21, 16, UI.colors.text) end
  elseif s.stock then
    text(T("Nessuna scorciatoia personale: valgono i tasti di serie di REAPER."), x + 12, y + 18, 16, SOFT)
  else
    text(busy and T("L'AI sta scrivendo…") or T("Nessuna spiegazione."), x + 12, y + 18, 16, busy and YELLOW or SOFT)
  end
  y = y + box_h + 10
  if not s.stock and not busy then
    if UI.draw_button({ x = x + w - 190, y = y, w = 190, h = 32, font = 15 },
      ex and T("Rifai con l'AI") or T("Spiega con l'AI"), false, true, clicked) then explain_ai(s) end
    local lab = T("Agente: ") .. (S.agents and A.label(S.agents, A.get()) or A.NAMES[A.get()] or A.get())
    if UI.draw_button({ x = x + w - 190 - 8 - 200, y = y, w = 200, h = 32, font = 15 }, lab, false, true, clicked) then
      local pick = A.menu(agents(), A.get())
      if pick then A.set(pick); set_status(T("Agente AI: ") .. A.label(agents(), pick) .. ".") end
    end
    y = y + 42
  end
  -- scorciatoie
  local list = S.view_list
  if not list then list = M.listing(s.text, action_name, MAC); S.view_list = list end
  local n_on = 0
  for _, r in ipairs(list) do if not r.off then n_on = n_on + 1 end end
  text(n_on .. T(" scorciatoie") .. (#list > n_on and (T("  ·  ") .. (#list - n_on) .. T(" tasti di serie spenti")) or ""), x, y, 16, UI.colors.title, true)
  y = y + 26
  local top, bottom, row_h = y, gfx.h - 118, 24
  local total = #list * row_h
  local sc = wheel(math.max(0, total - (bottom - top)), "detail_scroll")
  local key_w = math.floor(w * 0.36)
  for i, r in ipairs(list) do
    local ry = top + (i - 1) * row_h - sc
    if ry >= top - 1 and ry + row_h <= bottom + 1 then
      if i % 2 == 0 then UI.set_color({ 0.09, 0.09, 0.12, 1 }); gfx.rect(x, ry, w - 14, row_h, true) end
      text(UI.fit_text(r.key, key_w - 10), x + 8, ry + 3, 16, r.off and UI.colors.muted or YELLOW, true)
      text(UI.fit_text(r.action, w - key_w - 26), x + key_w, ry + 3, 16, r.off and UI.colors.muted or UI.colors.text)
    end
  end
  scrollbar(top, bottom, total, math.max(0, total - (bottom - top)), sc)
  status_line(x, w)
  local bw = math.floor((w - 16) / 3)
  local row = gfx.h - 66
  if s.in_use and not S.pending_name then
    text(T("IN USO"), x + 30, row + 10, 17, TEAL, true)
  elseif s.pending then
    text(T("AL RIAVVIO"), x + 14, row + 10, 17, YELLOW, true)
  elseif UI.draw_button({ x = x, y = row, w = bw, h = 40, font = 16 }, T("Attiva"), false, true, clicked, "play") then
    activate(s)
  end
  if not s.stock then
    if UI.draw_button({ x = x + bw + 8, y = row, w = bw, h = 40, font = 16 }, T("Rinomina…"), false, true, clicked) then rename_set(s) end
    if UI.draw_button({ x = x + 2 * (bw + 8), y = row, w = bw, h = 40, font = 16 }, T("Archivia…"), false, true, clicked) then archive_set(s) end
  end
end

local function open_view(s)
  S.view, S.view_list, S.detail_scroll = s, nil, 0
end

-- Parte alta dell'elenco (spiegazione, "Adesso in uso", cambio in attesa). Si disegna due volte:
-- prima per sapere dove comincia l'elenco, poi sopra i riquadri che scorrendo escono in alto.
local function draw_top(clicked)
  local x, y, w = 22, 70, gfx.w - 44
  gfx.setfont(1, "Arial", 16)
  UI.set_color(UI.colors.muted)
  for _, l in ipairs(UI.wrap_text(T("Scegli il set di scorciatoie che ti serve. Clic sul nome di un set per vedere cosa fa. Cambia solo i tasti: script e toolbar restano."), w)) do
    gfx.x, gfx.y = x, y; gfx.drawstr(l); y = y + 21
  end
  y = y + 6
  -- cosa c'e' adesso
  local in_use
  for _, s in ipairs(S.sets) do if s.in_use then in_use = s end end
  UI.set_color(UI.colors.panel); UI.fill_round(x, y, w, 52, 6)
  if in_use then
    text(T("Adesso in uso: ") .. UI.fit_text(in_use.name, w - 170), x + 12, y + 7, 17, TEAL, true)
    text(S.current.keys .. T(" scorciatoie") .. (S.current.osara and T("  ·  con i tasti OSARA") or ""), x + 12, y + 29, 15, SOFT)
  else
    text(T("Adesso: ") .. S.current.keys .. T(" scorciatoie che non sono in nessun set"), x + 12, y + 7, 17, UI.colors.text, true)
    text(UI.fit_text(T("Per poterci tornare, salvale con \"Salva tasti attuali\" qui sotto."), w - 24), x + 12, y + 29, 15, YELLOW)
  end
  y = y + 62
  if S.pending_name then
    UI.set_color({ 0.20, 0.17, 0.06, 1 }); UI.fill_round(x, y, w, 40, 6)
    text(T("Al prossimo riavvio: ") .. UI.fit_text(S.pending_name, w - 200), x + 12, y + 11, 16, YELLOW, true)
    if UI.draw_button({ x = x + w - 120, y = y + 5, w = 110, h = 30, font = 15 }, T("Annulla"), false, true, clicked) then cancel_pending() end
    y = y + 50
  end
  return y
end

local function draw_list(clicked)
  local x, w = 22, gfx.w - 44
  -- elenco dei set
  local list_top, list_bottom = draw_top(false), gfx.h - 118
  local card_h, gap = 68, 8
  local total = #S.sets * (card_h + gap)
  local max_scroll = math.max(0, total - (list_bottom - list_top))
  local sc = wheel(max_scroll, "scroll")
  for i, s in ipairs(S.sets) do
    local cy = list_top + (i - 1) * (card_h + gap) - sc
    if cy + card_h > list_top and cy < list_bottom then -- quello che esce in alto lo copre la testata, ridisegnata dopo
      local vis = cy >= list_top - 1 and cy + card_h <= list_bottom + 1
      local hover = UI.point_in_rect(gfx.mouse_x, gfx.mouse_y, x, cy, w - 150, card_h)
        and gfx.mouse_y >= list_top and gfx.mouse_y <= list_bottom
      UI.set_color(s.in_use and { 0.07, 0.17, 0.15, 1 } or (hover and { 0.14, 0.14, 0.20, 1 } or UI.colors.panel))
      UI.fill_round(x, cy, w, card_h, 7)
      UI.set_color(s.in_use and TEAL or (s.pending and YELLOW or UI.colors.panel_border))
      if gfx.roundrect then gfx.roundrect(x, cy, w - 1, card_h - 1, 7, true) end
      if s.in_use then gfx.roundrect(x + 1, cy + 1, w - 3, card_h - 3, 6, true) end
      local name = (s.in_use and "✓ " or "") .. s.name
      text(UI.fit_text(name, w - 170), x + 14, cy + 10, 18, UI.colors.text, true)
      text(UI.fit_text(detail(s), w - 170), x + 14, cy + 38, 16, SOFT)
      local bx = { x = x + w - 132, y = cy + 17, w = 118, h = 34, font = 16 }
      if s.in_use and not S.pending_name then
        text(T("IN USO"), bx.x + 26, bx.y + 8, 16, TEAL, true)
      elseif s.pending then
        text(T("AL RIAVVIO"), bx.x + 6, bx.y + 8, 16, YELLOW, true)
      elseif vis and UI.draw_button(bx, T("Attiva"), false, true, clicked, "play") then
        activate(s)
        clicked = false
      end
      if hover and clicked then open_view(s) end
    end
  end
  -- copre cio' che esce dall'elenco, sotto e sopra (in alto si ridisegna la testata)
  UI.set_color(UI.colors.bg)
  gfx.rect(0, list_bottom, gfx.w, gfx.h - list_bottom, true)
  gfx.rect(0, 0, gfx.w, list_top, true)
  draw_top(clicked)
  header(clicked)
  scrollbar(list_top, list_bottom, total, max_scroll, sc)
  if max_scroll > 0 and sc < max_scroll then text(T("altri set: scorri con la rotella"), x, list_bottom + 2, 14, UI.colors.muted) end

  status_line(x, w)
  local bw = math.floor((w - 16) / 3)
  local row = gfx.h - 66
  if UI.draw_button({ x = x, y = row, w = bw, h = 40, font = 16 }, T("Salva tasti attuali…"), false, true, clicked, "save") then save_current() end
  if UI.draw_button({ x = x + bw + 8, y = row, w = bw, h = 40, font = 16 }, T("Importa file…"), false, true, clicked) then import_file() end
  if UI.draw_button({ x = x + 2 * (bw + 8), y = row, w = bw, h = 40, font = 16 }, T("Apri cartella"), false, true, clicked) then open_folder() end
end

local function draw()
  UI.fill_background()
  local clicked = gfx.mouse_cap & 1 == 1 and S.last_cap & 1 == 0
  S.last_cap = gfx.mouse_cap
  poll_ai()
  if S.view then header(clicked); draw_detail(clicked) else draw_list(clicked) end
end

local function loop()
  local c = gfx.getchar()
  if c < 0 or (c == 27 and not S.view) then
    reaper.SetExtState(SECTION, "finestra", table.concat({ gfx.dock(-1, 0, 0, 0, 0) }, ","), true)
    gfx.quit()
    return
  end
  if c == 27 then S.view = nil end -- Esc nella pagina di un set: torna all'elenco
  draw()
  gfx.update()
  reaper.defer(loop)
end

if reaper.set_action_options then reaper.set_action_options(1 | 4); reaper.atexit(function() reaper.set_action_options(8) end) end
load_sets()
local d, px, py, pw, ph = (reaper.GetExtState(SECTION, "finestra") .. ","):match("([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)")
gfx.init(T("ZP Set Comandi"), math.max(560, tonumber(pw) or W), math.max(H, tonumber(ph) or H), tonumber(d) or 0, tonumber(px) or 200, tonumber(py) or 120)
loop()
