-- @noindex

--[[
ZP Studio Suite - Pulisci installazione precedente
27_Pulisci_Installazione_Precedente.lua

v2 - riscritto per riconoscere QUALSIASI pacchetto o script ZP storico
presente nell'installazione di REAPER (dentro Scripts ed Effects), non solo
le due cartelle note del vecchio installer.

Il riconoscimento si basa PRIMA di tutto sulla firma/autore reale trovata
nei file (vedi STRONG_MARKERS piu' sotto, ricavati da file veri, non
inventati). Quando non c'e' firma esplicita ma solo un indizio nel nome o
nell'intestazione ("ZP ..."), il file finisce sempre tra i "dubbi": non
viene mai archiviato in automatico.

Regola guida, sempre: in caso di dubbio, NON archiviare. Meglio lasciare un
residuo che spostare o cancellare un file sbagliato.

Fasi (in quest'ordine, mai invertito):
  1. Scansione di Scripts ed Effects (ricorsiva), senza toccare nulla.
  2. Esclusione dell'installazione corrente di ReaPack: quando l'API di
     ReaPack e' disponibile (reaper.ReaPack_GetOwner) si chiede direttamente
     a ReaPack "questo file e' tuo?" - e' la verifica piu' affidabile che
     esista, perche' non dipende da come si chiama la cartella. Se l'API
     non e' disponibile si ricade su un elenco esplicito dei percorsi
     correnti noti (ricavati dal repository reale: la cartella di ogni
     categoria dell'index ReaPack), e qualunque cosa assomigli a
     un'installazione corrente ma non sia in quell'elenco finisce tra i
     dubbi, mai archiviata.
  3. Costruzione del report (dry-run): pacchetti interi, singoli script,
     singoli JSFX, cosa viene escluso e perche', cosa e' dubbio.
  4. Conferma esplicita tua.
  5. Verifica che sul sistema ci sia davvero un modo di creare uno ZIP
     (comandi "zip"/"unzip" su macOS/Linux, "tar" su Windows). Se non c'e',
     ci si ferma subito: nessuna modifica.
  6. Creazione dello ZIP in "ZP Studio Suite Archives/" sotto la Resource
     Path, mantenendo dentro la struttura Scripts/... ed Effects/... cosi'
     com'era, cosi' si vede sempre da dove veniva ogni cosa.
  7. Verifica che lo ZIP esista, sia integro e contenga davvero ogni
     elemento archiviato. Se qualcosa non torna: ci si ferma, non si
     cancella niente.
  8. Solo a questo punto: rimozione degli originali gia' archiviati (con
     controlli di sicurezza sul percorso prima di ogni cancellazione).
  9. Pulizia mirata di reaper-kb.ini: si tolgono solo le righe che puntano
     a script davvero archiviati in questo passaggio (mai per sottostringa
     generica). Le voci in stile "RythmoBandTools:" (namespace di azioni
     custom senza un file dietro) vengono solo segnalate, non rimosse: non
     sono ricavabili con certezza dal nuovo criterio.
  10. Log completo su file, e avviso finale sulle toolbar (mai toccate).

Non tocca MAI:
  - l'installazione corrente installata da ReaPack;
  - questo stesso script;
  - qualunque cosa dentro "ZP Studio Suite Archives/";
  - cartelle/file di terze parti (nessuna firma o indizio ZP = mai
    candidato, a prescindere da dove si trovano);
  - file con un @author/autore esplicito che non e' Paolo Balestri/Zio
    Paolo (es. script di altri autori lasciati in giro nella cartella
    Scripts, anche se il nome del file sembra personale).
]]

-- Ogni riga stampata in console finisce anche qui, cosi' il report completo
-- si puo' sempre rileggere dal file di log invece che dalla finestra della
-- console di REAPER (che ha una scrollback scomoda da copiare per intero).
local console_log = {}
local function msg(s)
  s = tostring(s)
  reaper.ShowConsoleMsg(s .. "\n")
  console_log[#console_log + 1] = s
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function read_all(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function write_all(path, text)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(text)
  f:close()
  return true
end

local function split_lines_preserve(text)
  if text == "" then return {} end
  local lines, pos = {}, 1
  while pos <= #text do
    local s, e = text:find("\r?\n", pos)
    if s then
      lines[#lines + 1] = text:sub(pos, s - 1)
      pos = e + 1
    else
      lines[#lines + 1] = text:sub(pos)
      pos = #text + 1
    end
  end
  return lines
end

local sep = package.config:sub(1, 1)
local is_win = sep == "\\"
local resource = reaper.GetResourcePath()
local scripts_root = resource .. sep .. "Scripts"
local effects_root = resource .. sep .. "Effects"
local kb = resource .. sep .. "reaper-kb.ini"
local stamp_full = os.date("%Y%m%d_%H%M%S")
local stamp = os.date("%Y%m%d_%H%M")
local archives_dir = resource .. sep .. "ZP Studio Suite Archives"
local zip_path = archives_dir .. sep .. "ZP_Precedenti_" .. stamp .. ".zip"
local kb_backup = kb .. ".ZPSS_backup_" .. stamp_full
local log_path = resource .. sep .. "ZP_StudioSuite_Pulizia_" .. stamp_full .. ".log"

-- Scrive nel file di log tutto cio' che e' stato stampato in console fino a
-- questo momento, seguito da una riga finale con l'esito. Usata in OGNI
-- punto in cui lo script si ferma (con o senza modifiche), cosi' il report
-- completo si legge sempre dal file, senza dipendere dalla finestra della
-- console di REAPER.
local function write_full_log(esito)
  write_all(log_path, table.concat(console_log, "\n") .. "\n\n" .. esito .. "\n")
end

-- Percorso di questo stesso script: non e' mai un candidato.
local _, self_path_raw = reaper.get_action_context()
local self_path = self_path_raw or ""

local function join(a, b) return a .. sep .. b end

-- ---------------------------------------------------------------------
-- Elenco file/cartelle (API di REAPER, non os.execute: funziona uguale
-- su macOS e Windows senza dipendere da comandi di shell esterni).
-- ---------------------------------------------------------------------

local function list_files_recursive(dir, out)
  out = out or {}
  local i = 0
  while true do
    local fn = reaper.EnumerateFiles(dir, i)
    if not fn then break end
    if fn ~= ".DS_Store" then out[#out + 1] = join(dir, fn) end
    i = i + 1
  end
  i = 0
  while true do
    local sub = reaper.EnumerateSubdirectories(dir, i)
    if not sub then break end
    list_files_recursive(join(dir, sub), out)
    i = i + 1
  end
  return out
end

local function list_subdirs(dir)
  local out = {}
  local i = 0
  while true do
    local sub = reaper.EnumerateSubdirectories(dir, i)
    if not sub then break end
    out[#out + 1] = sub
    i = i + 1
  end
  return out
end

-- ---------------------------------------------------------------------
-- Riconoscimento firma. Le stringhe qui sotto sono quelle trovate per
-- davvero nei file storici durante la ricognizione (Fase 1): non sono
-- inventate.
-- ---------------------------------------------------------------------

local STRONG_MARKERS = { "paolo balestri", "zio paolo", "paolobalestri.com" }

local function has_strong_signature(text)
  local low = text:lower()
  for _, m in ipairs(STRONG_MARKERS) do
    if low:find(m, 1, true) then return true end
  end
  return false
end

local AUTHOR_PATTERNS = {
  "@author%s+([^\r\n]+)",
  "[Aa]utore:%s*([^\r\n]+)",
  "[Aa]uthor:%s*([^\r\n]+)",
}

local function declared_author(text)
  for _, pat in ipairs(AUTHOR_PATTERNS) do
    local m = text:match(pat)
    if m then return (m:match("^%s*(.-)%s*$")) end
  end
  return nil
end

local function is_third_party_author(name)
  if not name then return false end
  local low = name:lower()
  if low:find("paolo", 1, true) or low:find("zp", 1, true) then return false end
  return true
end

local function has_zp_name_hint(basename, text)
  if basename:match("^[Zz][Pp][ _]") then return true end
  local head = text:sub(1, 400):lower()
  if head:find("zp studio suite", 1, true) or head:find("zp suite", 1, true) then return true end
  return false
end

local CODE_EXT = { lua = true, eel = true, py = true, jsfx = true }
local SAFE_EXTRA_EXT = {
  txt = true, md = true, html = true, pdf = true, png = true, jpg = true,
  rtracktemplate = true, reapermenu = true, dll = true,
}

local function ext_of(path)
  local e = path:match("%.([%w]+)$")
  return e and e:lower() or ""
end

local function is_safe_extra(path)
  return SAFE_EXTRA_EXT[ext_of(path)] == true
end

-- Classifica un file: "strong" (firma certa), "third_party" (autore
-- dichiarato che non e' Paolo/ZP), "hint" (solo indizio dal nome),
-- "none" (nessun indizio), "skip_ext" (estensione non di codice, non
-- valutata come firma - puo' comunque essere un'estensione "sicura").
local function classify_file(path)
  local e = ext_of(path)
  if not CODE_EXT[e] then return { path = path, kind = "skip_ext" } end
  local text = read_all(path) or ""
  local author = declared_author(text)
  if author and is_third_party_author(author) and not has_strong_signature(text) then
    return { path = path, kind = "third_party", author = author }
  end
  if has_strong_signature(text) then
    return { path = path, kind = "strong" }
  end
  local basename = path:match("[^/\\]+$") or path
  if has_zp_name_hint(basename, text) then
    return { path = path, kind = "hint" }
  end
  return { path = path, kind = "none" }
end

-- ---------------------------------------------------------------------
-- Protezione dell'installazione corrente di ReaPack.
-- ---------------------------------------------------------------------

local reapack_api_ok = reaper.APIExists("ReaPack_GetOwner")
  and reaper.APIExists("ReaPack_GetEntryInfo")
  and reaper.APIExists("ReaPack_FreeEntry")

-- Percorsi correnti noti. Confermati DAVVERO da un'esecuzione reale (le voci
-- di reaper-kb.ini della tua installazione vera stanno sotto
-- "Scripts/ZP Suite/ZP Studio Suite/", percorso annidato sotto il nome del
-- repository ReaPack "ZP Suite" - NON quello piatto che avevo dedotto solo
-- guardando la struttura del repository GitHub). Tengo comunque anche la
-- forma piatta come possibilita', per sicurezza, nel caso cambi ancora.
local KNOWN_CURRENT_RELATIVE = {
  join("Scripts", join("ZP Suite", "ZP Studio Suite")),
  join("Scripts", "ZP Studio Suite"),
  join("Effects", join("ZP Suite", "ZP Master")),
  join("Effects", join("ZP Suite", "ZP Misura")),
  join("Effects", join("ZP Suite", "ZP Voce")),
  join("Effects", "ZP Master"),
  join("Effects", "ZP Misura"),
  join("Effects", "ZP Voce"),
}

local function is_known_current_path(path)
  for _, rp in ipairs(KNOWN_CURRENT_RELATIVE) do
    local full = join(resource, rp)
    if path == full or path:sub(1, #full + 1) == full .. sep then return true end
  end
  return false
end

local function looks_like_current_name(path)
  for _, rp in ipairs(KNOWN_CURRENT_RELATIVE) do
    local name = rp:match("[^/\\]+$")
    if path:find(sep .. name .. sep, 1, true) or path:sub(-(#name)) == name then
      return true
    end
  end
  return false
end

-- Chiede a ReaPack se possiede questo file. Protetto con pcall: se l'API
-- si comporta in modo inatteso anche una sola volta, si disattiva per il
-- resto dell'esecuzione e si passa al ripiego per percorso (mai il
-- contrario: un errore non deve MAI tradursi in "quindi non e' protetto").
local function reapack_owns(path)
  if not reapack_api_ok then return nil end
  local ok, entry = pcall(reaper.ReaPack_GetOwner, path)
  if not ok then
    reapack_api_ok = false
    return nil
  end
  if not entry or entry == false then return false end
  pcall(reaper.ReaPack_FreeEntry, entry)
  return true
end

-- Ritorna: "protetto_reapack" | "protetto_percorso_noto" | "dubbio_simile" | nil
--
-- IMPORTANTE: una risposta "no" di ReaPack (il file non risulta suo) non
-- basta MAI da sola per dire "quindi non e' protetto". L'ho verificato con
-- un'esecuzione reale: ReaPack puo' rispondere "non mio" anche per file che
-- fanno parte dell'installazione corrente (per come tiene il registro dei
-- pacchetti multi-file), e se quella risposta avesse bypassato il controllo
-- per percorso l'installazione vera sarebbe finita tra i candidati. Quindi:
-- l'API puo' solo AGGIUNGERE protezione (risposta "si'"), mai toglierla. Il
-- controllo per percorso viene sempre fatto, qualunque cosa dica l'API.
local function protection_status(path)
  if reapack_owns(path) == true then return "protetto_reapack" end
  if is_known_current_path(path) then return "protetto_percorso_noto" end
  if looks_like_current_name(path) then return "dubbio_simile" end
  return nil
end

-- ---------------------------------------------------------------------
-- Valutazione di una cartella come "pacchetto intero".
-- ---------------------------------------------------------------------

-- Una cartella e' un pacchetto intero solo se contiene almeno un file con
-- firma forte, nessun file con autore di terzi, e nessun file di codice
-- privo di qualunque indizio ZP. Con require_name_hint=true (usato per
-- Effects, piu' prudente) serve in piu' che il NOME della cartella stessa
-- richiami ZP/Paolo, non solo il contenuto.
local function evaluate_dir_as_package(dir_abs, require_name_hint)
  if require_name_hint then
    local name = (dir_abs:match("[^/\\]+$") or ""):lower()
    if not (name:find("paolo balestri", 1, true) or name:find("zio paolo", 1, true)
        or name:match("^zp[ _]")) then
      return false, {}
    end
  end
  local files = list_files_recursive(dir_abs, {})
  local has_strong = false
  for _, f in ipairs(files) do
    local cls = classify_file(f)
    if cls.kind == "third_party" then
      return false, files
    elseif cls.kind == "strong" then
      has_strong = true
    elseif cls.kind == "none" and not is_safe_extra(f) then
      return false, files
    end
  end
  return has_strong, files
end

-- ---------------------------------------------------------------------
-- Scansione di un'area (Scripts oppure Effects).
-- ---------------------------------------------------------------------

local function scan_area(area_root, require_name_hint_for_folders)
  local result = {
    packages = {},
    single_strong = {},
    dubious = {},
    excluded_third_party = {},
    excluded_current = {},
  }
  if not exists(area_root) then return result end

  local handled_dirs = {}
  for _, name in ipairs(list_subdirs(area_root)) do
    local dir_abs = join(area_root, name)
    if dir_abs ~= archives_dir then
      local has_strong, files = evaluate_dir_as_package(dir_abs, require_name_hint_for_folders)
      local protect_kind, dubious_kind = nil, nil
      for _, f in ipairs(files) do
        local st = protection_status(f)
        if st == "protetto_reapack" or st == "protetto_percorso_noto" then protect_kind = st end
        if st == "dubbio_simile" then dubious_kind = st end
      end
      if protect_kind then
        result.excluded_current[#result.excluded_current + 1] = { path = dir_abs, motivo = protect_kind }
        handled_dirs[name] = true
      elseif dubious_kind then
        result.dubious[#result.dubious + 1] =
          { path = dir_abs, motivo = "cartella simile all'installazione corrente, non verificabile con certezza" }
        handled_dirs[name] = true
      elseif has_strong then
        result.packages[#result.packages + 1] = { path = dir_abs, files = files }
        handled_dirs[name] = true
      end
    end
  end

  local all_files = list_files_recursive(area_root, {})
  for _, f in ipairs(all_files) do
    if f ~= self_path then
      local rest = f:sub(#area_root + 2)
      local first_seg = rest:match("^([^/\\]+)")
      local inside_handled = first_seg and handled_dirs[first_seg]
      if not inside_handled then
        local cls = classify_file(f)
        if cls.kind == "third_party" then
          result.excluded_third_party[#result.excluded_third_party + 1] = { path = f, autore = cls.author }
        elseif cls.kind == "strong" then
          local st = protection_status(f)
          if st == "protetto_reapack" or st == "protetto_percorso_noto" then
            result.excluded_current[#result.excluded_current + 1] = { path = f, motivo = st }
          elseif st == "dubbio_simile" then
            result.dubious[#result.dubious + 1] =
              { path = f, motivo = "file simile all'installazione corrente, non verificabile con certezza" }
          else
            result.single_strong[#result.single_strong + 1] = { path = f }
          end
        elseif cls.kind == "hint" then
          result.dubious[#result.dubious + 1] =
            { path = f, motivo = "nessuna firma esplicita, solo indizio dal nome/intestazione" }
        end
      end
    end
  end

  return result
end

-- ---------------------------------------------------------------------
-- Esecuzione della scansione (Fase 1 di questo run: sola diagnosi).
-- ---------------------------------------------------------------------

reaper.ClearConsole()
msg("ZP Studio Suite - Pulisci installazione precedente (v2)")
msg("DRY RUN: non viene modificato niente senza la tua conferma.")
msg("Resource Path: " .. resource)
msg("Verifica ownership ReaPack via API: " .. (reapack_api_ok and "disponibile" or "non disponibile (uso il ripiego per percorso)"))
msg("")

local scripts_res = scan_area(scripts_root, false)
local effects_res = scan_area(effects_root, true)

local function count(t) return #t end

local total_packages = count(scripts_res.packages) + count(effects_res.packages)
local total_singles = count(scripts_res.single_strong) + count(effects_res.single_strong)
local total_dubious = count(scripts_res.dubious) + count(effects_res.dubious)
local total_excl_tp = count(scripts_res.excluded_third_party) + count(effects_res.excluded_third_party)
local total_excl_cur = count(scripts_res.excluded_current) + count(effects_res.excluded_current)

local function print_section(title, area_label, items, fmt)
  if #items == 0 then return end
  msg(title .. " [" .. area_label .. "]: " .. tostring(#items))
  for _, it in ipairs(items) do msg("  " .. fmt(it)) end
end

msg("=== Pacchetti interi (cartelle) ===")
print_section("Scripts", "pacchetti", scripts_res.packages, function(p) return p.path .. "  (" .. #p.files .. " file)" end)
print_section("Effects", "pacchetti", effects_res.packages, function(p) return p.path .. "  (" .. #p.files .. " file)" end)
msg("")
msg("=== Singoli file con firma forte ===")
print_section("Scripts", "singoli", scripts_res.single_strong, function(p) return p.path end)
print_section("Effects", "singoli", effects_res.single_strong, function(p) return p.path end)
msg("")
msg("=== Esclusi: installazione corrente ReaPack ===")
print_section("Scripts", "esclusi", scripts_res.excluded_current, function(p) return p.path .. "  [" .. p.motivo .. "]" end)
print_section("Effects", "esclusi", effects_res.excluded_current, function(p) return p.path .. "  [" .. p.motivo .. "]" end)
msg("")
msg("=== Esclusi: autore di terzi dichiarato nel file ===")
print_section("Scripts", "esclusi", scripts_res.excluded_third_party, function(p) return p.path .. "  [@author " .. tostring(p.autore) .. "]" end)
print_section("Effects", "esclusi", effects_res.excluded_third_party, function(p) return p.path .. "  [@author " .. tostring(p.autore) .. "]" end)
msg("")
msg("=== Dubbi: lasciati intatti, verificali a mano ===")
print_section("Scripts", "dubbi", scripts_res.dubious, function(p) return p.path .. "  (" .. p.motivo .. ")" end)
print_section("Effects", "dubbi", effects_res.dubious, function(p) return p.path .. "  (" .. p.motivo .. ")" end)
msg("")
msg("L'installazione fatta da ReaPack non viene toccata.")
msg("Toolbar e menu personalizzati non vengono rimossi: quelli li sistemi a mano.")
msg("")

if total_packages == 0 and total_singles == 0 then
  local extra = ""
  if total_dubious > 0 then
    extra = "\n\nCi sono pero' " .. tostring(total_dubious) ..
      " elementi dubbi (nessuna firma esplicita, o simili all'installazione corrente): " ..
      "li trovi elencati nella console, li ho lasciati intatti."
  end
  reaper.ShowMessageBox(
    "Non ho trovato residui archiviabili con certezza." .. extra,
    "ZP Studio Suite - Pulizia", 0)
  write_full_log("Nessun candidato archiviabile. Dubbi: " .. tostring(total_dubious) .. ". Nessuna modifica effettuata.")
  return
end

-- ---------------------------------------------------------------------
-- Riepilogo kb.ini: quali righe verrebbero rimosse (solo per candidati
-- Scripts davvero trovati in questa scansione).
-- ---------------------------------------------------------------------

local function scripts_relpath(abs_path)
  local prefix = scripts_root .. sep
  if abs_path:sub(1, #prefix) == prefix then
    local r = abs_path:sub(#prefix + 1)
    if sep == "\\" then r = r:gsub("\\", "/") end
    return r
  end
  return nil
end

local removal_relpaths = {}
for _, p in ipairs(scripts_res.packages) do
  for _, f in ipairs(p.files) do
    local r = scripts_relpath(f)
    if r then removal_relpaths[#removal_relpaths + 1] = r end
  end
end
for _, p in ipairs(scripts_res.single_strong) do
  local r = scripts_relpath(p.path)
  if r then removal_relpaths[#removal_relpaths + 1] = r end
end

local function line_matches_relpath(line, relpath)
  if line:find(relpath .. '"', 1, true) then return true end
  if line:sub(-#relpath) == relpath then return true end
  return false
end

local kb_txt = read_all(kb) or ""
local kb_lines = split_lines_preserve(kb_txt)
local kb_keep, kb_hits = {}, {}
for _, line in ipairs(kb_lines) do
  local matched = false
  for _, r in ipairs(removal_relpaths) do
    if line_matches_relpath(line, r) then matched = true; break end
  end
  if matched then kb_hits[#kb_hits + 1] = line else kb_keep[#kb_keep + 1] = line end
end

-- Solo informativo: vecchi indizi testuali non ricollegabili con certezza
-- a un candidato di questa scansione (es. "RythmoBandTools:", un namespace
-- di azioni custom senza percorso file dietro). Mai rimossi in automatico.
local OLD_TEXT_HINTS = { "RythmoBandTools:" }
local kb_old_hint_lines = {}
for _, line in ipairs(kb_lines) do
  for _, pat in ipairs(OLD_TEXT_HINTS) do
    if line:find(pat, 1, true) then
      local already = false
      for _, h in ipairs(kb_hits) do if h == line then already = true end end
      if not already then kb_old_hint_lines[#kb_old_hint_lines + 1] = line end
    end
  end
end

msg("=== reaper-kb.ini: voci che verrebbero rimosse (" .. tostring(#kb_hits) .. ") ===")
for _, line in ipairs(kb_hits) do msg("  " .. line) end
if #kb_old_hint_lines > 0 then
  msg("")
  msg("=== reaper-kb.ini: indizi vecchio stile trovati ma NON rimossi (verificali a mano) ===")
  for _, line in ipairs(kb_old_hint_lines) do msg("  " .. line) end
end
msg("")

-- ---------------------------------------------------------------------
-- Conferma esplicita.
-- ---------------------------------------------------------------------

local riepilogo =
  "Ho trovato residui di installazioni precedenti della Suite.\n\n" ..
  "Pacchetti interi da archiviare: " .. tostring(total_packages) .. "\n" ..
  "Singoli file da archiviare: " .. tostring(total_singles) .. "\n" ..
  "Voci di reaper-kb.ini da rimuovere: " .. tostring(#kb_hits) .. "\n" ..
  "Elementi dubbi lasciati intatti: " .. tostring(total_dubious) .. "\n\n" ..
  "Niente viene cancellato prima di aver creato e verificato uno ZIP in\n" ..
  archives_dir .. sep .. "ZP_Precedenti_" .. stamp .. ".zip\n\n" ..
  "L'installazione fatta da ReaPack non viene toccata.\n\n" ..
  "Procedo?"

if reaper.ShowMessageBox(riepilogo, "ZP Studio Suite - Pulizia", 4) ~= 6 then
  msg("")
  msg("Dry-run completato. Non ho modificato niente.")
  write_full_log("Dry-run completato. Non ho modificato niente. Pacchetti: " .. tostring(total_packages) ..
    " | Singoli: " .. tostring(total_singles) ..
    " | Voci kb.ini: " .. tostring(#kb_hits) ..
    " | Dubbi: " .. tostring(total_dubious))
  return
end

-- ---------------------------------------------------------------------
-- Utility di shell (usate solo per creare/verificare lo ZIP: nessuna
-- cancellazione passa da qui).
-- ---------------------------------------------------------------------

local function shell_quote(s)
  if is_win then
    return '"' .. s:gsub('"', '""') .. '"'
  else
    return "'" .. s:gsub("'", "'\\''") .. "'"
  end
end

local function run_capture(cmd)
  local h = io.popen(cmd .. " 2>&1")
  if not h then return false, "" end
  local out = h:read("*a") or ""
  local a = h:close()
  return a == true, out
end

local function tool_available(check_cmd)
  local ok, out = run_capture(check_cmd)
  return out:match("%S") ~= nil
end

local function find_zip_tool()
  if is_win then
    if tool_available("where tar") then return "tar" end
    return nil
  else
    if tool_available("command -v zip") and tool_available("command -v unzip") then return "zip" end
    return nil
  end
end

local zip_tool = find_zip_tool()
if not zip_tool then
  reaper.ShowMessageBox(
    "Non ho trovato uno strumento per creare lo ZIP su questo sistema " ..
    "(cerco 'zip'/'unzip' su macOS, 'tar' su Windows).\n\n" ..
    "Mi fermo qui: NON ho spostato o cancellato niente.",
    "ZP Studio Suite - Pulizia", 0)
  write_full_log("Fermato: nessuno strumento zip disponibile. Nessuna modifica effettuata.")
  return
end

-- ---------------------------------------------------------------------
-- Creazione dell'archivio.
-- ---------------------------------------------------------------------

if not exists(archives_dir) then
  if is_win then os.execute('mkdir ' .. shell_quote(archives_dir))
  else os.execute('mkdir -p ' .. shell_quote(archives_dir)) end
end

local function resource_relpath(abs_path)
  local prefix = resource .. sep
  if abs_path:sub(1, #prefix) == prefix then return abs_path:sub(#prefix + 1) end
  return abs_path
end

local all_candidates = {}
for _, p in ipairs(scripts_res.packages) do all_candidates[#all_candidates + 1] = { path = p.path, is_dir = true } end
for _, p in ipairs(scripts_res.single_strong) do all_candidates[#all_candidates + 1] = { path = p.path, is_dir = false } end
for _, p in ipairs(effects_res.packages) do all_candidates[#all_candidates + 1] = { path = p.path, is_dir = true } end
for _, p in ipairs(effects_res.single_strong) do all_candidates[#all_candidates + 1] = { path = p.path, is_dir = false } end

local rel_args = {}
for _, c in ipairs(all_candidates) do rel_args[#rel_args + 1] = shell_quote(resource_relpath(c.path)) end

local create_ok, create_out
if is_win then
  -- ATTENZIONE: percorso Windows scritto per completezza ma non testato
  -- dal vivo in questa sessione. bsdtar (tar.exe di Windows 10+) sa creare
  -- zip con -a in base all'estensione del file di destinazione.
  local cmd = string.format('tar -a -c -f %s -C %s %s',
    shell_quote(zip_path), shell_quote(resource), table.concat(rel_args, " "))
  create_ok, create_out = run_capture(cmd)
else
  local cmd = string.format('cd %s && zip -r -X %s %s',
    shell_quote(resource), shell_quote(zip_path), table.concat(rel_args, " "))
  create_ok, create_out = run_capture(cmd)
end

local function abort_no_changes(reason)
  reaper.ShowMessageBox(
    "Qualcosa non ha funzionato durante la creazione/verifica dello ZIP:\n\n" ..
    reason .. "\n\nMi fermo qui: NON ho spostato o cancellato niente.",
    "ZP Studio Suite - Pulizia", 0)
  write_full_log("Fermato: " .. reason .. " Nessuna modifica effettuata.")
end

if not exists(zip_path) then
  abort_no_changes("lo ZIP non risulta creato in " .. zip_path .. "\nOutput comando: " .. create_out)
  return
end

-- Verifica integrita' + presenza di ogni candidato nell'archivio.
local integrity_ok = false
local listing = ""
if is_win then
  local ok_list, out_list = run_capture(string.format("tar -tf %s", shell_quote(zip_path)))
  listing = out_list
  integrity_ok = ok_list and out_list:match("%S") ~= nil
else
  local ok_test, out_test = run_capture(string.format("zip -T %s", shell_quote(zip_path)))
  integrity_ok = ok_test
  local ok_list, out_list = run_capture(string.format("unzip -l %s", shell_quote(zip_path)))
  listing = out_list
end

if not integrity_ok then
  abort_no_changes("il test di integrita' dello ZIP non e' andato a buon fine.")
  return
end

local all_present = true
local missing_list = {}
for _, c in ipairs(all_candidates) do
  local rp = resource_relpath(c.path)
  if not listing:find(rp, 1, true) then
    all_present = false
    missing_list[#missing_list + 1] = rp
  end
end

if not all_present then
  abort_no_changes("questi elementi non risultano nello ZIP: " .. table.concat(missing_list, "; "))
  return
end

msg("ZIP creato e verificato: " .. zip_path)
msg("")

-- ---------------------------------------------------------------------
-- Solo ora: rimozione degli originali gia' archiviati e verificati.
-- ---------------------------------------------------------------------

local function safe_remove_tree(path)
  assert(path and path ~= "", "percorso vuoto")
  assert(path ~= resource and path ~= scripts_root and path ~= effects_root,
    "non cancello la Resource Path o le radici Scripts/Effects")
  assert(path:sub(1, #scripts_root + 1) == scripts_root .. sep
      or path:sub(1, #effects_root + 1) == effects_root .. sep,
      "il percorso non e' dentro Scripts o Effects: mi fermo")
  if is_win then os.execute('rmdir /s /q ' .. shell_quote(path))
  else os.execute('rm -rf ' .. shell_quote(path)) end
end

local function safe_remove_file(path)
  assert(path and path ~= "", "percorso vuoto")
  assert(path:sub(1, #scripts_root + 1) == scripts_root .. sep
      or path:sub(1, #effects_root + 1) == effects_root .. sep,
      "il percorso non e' dentro Scripts o Effects: mi fermo")
  os.remove(path)
end

local removed_log = {}
for _, c in ipairs(all_candidates) do
  local ok, err = pcall(function()
    if c.is_dir then safe_remove_tree(c.path) else safe_remove_file(c.path) end
  end)
  if ok then
    removed_log[#removed_log + 1] = "Archiviato e rimosso: " .. c.path
    msg("Rimosso: " .. c.path)
  else
    removed_log[#removed_log + 1] = "ERRORE rimuovendo " .. c.path .. ": " .. tostring(err)
    msg("ERRORE rimuovendo " .. c.path .. ": " .. tostring(err))
  end
end
msg("")

-- ---------------------------------------------------------------------
-- reaper-kb.ini: rimozione mirata delle sole voci individuate sopra.
-- ---------------------------------------------------------------------

local kb_backup_ok = true
if #kb_hits > 0 then
  if not write_all(kb_backup, kb_txt) then
    kb_backup_ok = false
    msg("ERRORE: non riesco a creare la copia di reaper-kb.ini, non lo tocco.")
  else
    local nuovo = table.concat(kb_keep, "\n")
    if kb_txt:match("[\r\n]$") then nuovo = nuovo .. "\n" end
    if write_all(kb, nuovo) then
      msg("Copia di reaper-kb.ini creata: " .. kb_backup)
      msg("Voci rimosse dalla Action List: " .. tostring(#kb_hits))
    else
      msg("ERRORE: copia creata ma non riesco a riscrivere reaper-kb.ini. Originale salvo in: " .. kb_backup)
    end
  end
end

-- ---------------------------------------------------------------------
-- Log completo.
-- ---------------------------------------------------------------------

local log = {}
local function L(s) log[#log + 1] = s end
L("Pulizia installazione precedente (v2) - APPLICATA " .. stamp_full)
L("Resource Path: " .. resource)
L("Verifica ownership ReaPack via API: " .. (reapack_api_ok and "usata" or "non disponibile, ripiego per percorso"))
L("Firme riconosciute: " .. table.concat(STRONG_MARKERS, " | "))
L("")
L("Pacchetti interi archiviati: " .. tostring(count(scripts_res.packages) + count(effects_res.packages)))
for _, p in ipairs(scripts_res.packages) do L("  [Scripts] " .. p.path) end
for _, p in ipairs(effects_res.packages) do L("  [Effects] " .. p.path) end
L("Singoli file archiviati: " .. tostring(count(scripts_res.single_strong) + count(effects_res.single_strong)))
for _, p in ipairs(scripts_res.single_strong) do L("  [Scripts] " .. p.path) end
for _, p in ipairs(effects_res.single_strong) do L("  [Effects] " .. p.path) end
L("")
L("Esclusi (installazione corrente ReaPack): " .. tostring(total_excl_cur))
for _, p in ipairs(scripts_res.excluded_current) do L("  [Scripts] " .. p.path .. " [" .. p.motivo .. "]") end
for _, p in ipairs(effects_res.excluded_current) do L("  [Effects] " .. p.path .. " [" .. p.motivo .. "]") end
L("Esclusi (autore di terzi): " .. tostring(total_excl_tp))
for _, p in ipairs(scripts_res.excluded_third_party) do L("  [Scripts] " .. p.path .. " [@author " .. tostring(p.autore) .. "]") end
for _, p in ipairs(effects_res.excluded_third_party) do L("  [Effects] " .. p.path .. " [@author " .. tostring(p.autore) .. "]") end
L("Dubbi, lasciati intatti: " .. tostring(total_dubious))
for _, p in ipairs(scripts_res.dubious) do L("  [Scripts] " .. p.path .. " (" .. p.motivo .. ")") end
for _, p in ipairs(effects_res.dubious) do L("  [Effects] " .. p.path .. " (" .. p.motivo .. ")") end
L("")
L("ZIP creato: " .. zip_path)
L("ZIP verificato: integrita' OK, tutti i candidati presenti.")
L("")
for _, l in ipairs(removed_log) do L(l) end
L("")
if #kb_hits > 0 then
  L("Copia di reaper-kb.ini: " .. (kb_backup_ok and kb_backup or "NON CREATA (errore)"))
  L("Voci rimosse da reaper-kb.ini:")
  for _, line in ipairs(kb_hits) do L("  " .. line) end
else
  L("Nessuna voce di reaper-kb.ini da rimuovere.")
end
if #kb_old_hint_lines > 0 then
  L("")
  L("Indizi vecchio stile trovati in reaper-kb.ini ma NON rimossi (verificali a mano):")
  for _, line in ipairs(kb_old_hint_lines) do L("  " .. line) end
end
L("")
L("Toolbar e menu personalizzati non rimossi.")

write_all(log_path, table.concat(log, "\n") .. "\n")
msg("Log: " .. log_path)

reaper.ShowMessageBox(
  "Pulizia completata.\n\n" ..
  "1. Riavvia REAPER: la Action List si aggiorna al riavvio.\n" ..
  "2. Le tue vecchie toolbar puntano ancora agli script rimossi. " ..
  "Reimportale dal pacchetto: Options > Customize toolbars > Import, " ..
  "e scegli il file toolbar/ZP_StudioSuite.ReaperMenu della Suite.\n\n" ..
  "Niente e' stato cancellato senza prima uno ZIP verificato: lo trovi in\n" .. zip_path,
  "ZP Studio Suite - Pulizia", 0)
