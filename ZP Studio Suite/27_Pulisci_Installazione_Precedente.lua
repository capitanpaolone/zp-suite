-- @noindex

--[[
ZP Studio Suite - Pulisci installazione precedente
27_Pulisci_Installazione_Precedente.lua

Serve a chi aveva la Suite installata con il vecchio installer (o con
RythmoBand) e adesso la riceve da ReaPack. Le due installazioni vivono in
cartelle diverse e non si sovrascrivono: senza pulizia si ritrovano due copie
di ogni script e la Action List doppia.

Dry-run prima, applica solo dopo conferma esplicita.
Non cancella nulla: sposta in una cartella di backup datata.
Non tocca l'installazione fatta da ReaPack.
Non rimuove toolbar o menu personalizzati.
]]

local function msg(s) reaper.ShowConsoleMsg(tostring(s) .. "\n") end

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

-- Righe della Action List da rimuovere.
-- Attenzione: la cartella installata da ReaPack contiene "ZP Studio Suite"
-- con gli SPAZI, quella del vecchio installer "ZP_Studio_Suite" con i
-- TRATTINI BASSI. E' questa differenza che tiene al sicuro l'installazione
-- nuova: nessuno di questi pattern la puo' intercettare.
local legacy_patterns = {
  "ZP_Studio_Suite",
  "Reaper_RythmoBand_Tools",
  "RythmoBandTools:",
  "ZP_RythmoBand",
}

local function is_legacy_line(line)
  for _, pat in ipairs(legacy_patterns) do
    if line:find(pat, 1, true) then return true end
  end
  return false
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

local function scan_kb(text)
  local keep, hits = {}, {}
  for _, line in ipairs(split_lines_preserve(text)) do
    if is_legacy_line(line) then hits[#hits + 1] = line else keep[#keep + 1] = line end
  end
  return keep, hits
end

local sep = package.config:sub(1, 1)
local resource = reaper.GetResourcePath()
local scripts = resource .. sep .. "Scripts"
local kb = resource .. sep .. "reaper-kb.ini"
local stamp = os.date("%Y%m%d_%H%M%S")
local backup_root = scripts .. sep .. "ZP_StudioSuite_backup_" .. stamp
local kb_backup = kb .. ".ZPSS_backup_" .. stamp
local log_path = resource .. sep .. "ZP_StudioSuite_Pulizia_" .. stamp .. ".log"

-- Cartelle delle installazioni precedenti. Nessuna di queste e' quella di
-- ReaPack, che sta sotto una cartella col nome del repository.
local legacy_dirs = {
  { nome = "vecchio installer",  path = scripts .. sep .. "ZP_Studio_Suite" },
  { nome = "RythmoBand",         path = scripts .. sep .. "ZP Paolo Balestri_lua" .. sep .. "Reaper_RythmoBand_Tools" },
}

reaper.ClearConsole()
msg("ZP Studio Suite - Pulisci installazione precedente")
msg("DRY RUN: non viene modificato niente senza la tua conferma.")
msg("Resource Path: " .. resource)
msg("")

local kb_txt = read_all(kb) or ""
local keep, hits = scan_kb(kb_txt)

local trovate = {}
for _, d in ipairs(legacy_dirs) do
  if exists(d.path) then trovate[#trovate + 1] = d end
end

msg("Vecchie voci nella Action List: " .. tostring(#hits))
for _, line in ipairs(hits) do msg("  " .. line) end
msg("")
msg("Cartelle di installazioni precedenti trovate: " .. tostring(#trovate))
for _, d in ipairs(trovate) do
  msg("  [" .. d.nome .. "] " .. d.path)
end
msg("")
msg("L'installazione fatta da ReaPack non viene toccata.")
msg("Toolbar e menu personalizzati non vengono rimossi: quelli li sistemi a mano.")

if #hits == 0 and #trovate == 0 then
  reaper.ShowMessageBox(
    "Non ho trovato installazioni precedenti.\n\n" ..
    "Hai solo la versione ReaPack: non c'e' niente da pulire.",
    "ZP Studio Suite - Pulizia", 0)
  write_all(log_path, "Dry-run " .. stamp .. "\nNessun residuo rilevato.\n")
  return
end

local riepilogo =
  "Ho trovato una installazione precedente della Suite.\n\n" ..
  "Voci vecchie nella Action List: " .. tostring(#hits) .. "\n" ..
  "Cartelle da mettere da parte: " .. tostring(#trovate) .. "\n\n" ..
  "Niente viene cancellato: le cartelle vengono spostate in\n" ..
  backup_root .. "\n" ..
  "e di reaper-kb.ini viene fatta una copia prima di toccarlo.\n\n" ..
  "La versione installata da ReaPack non viene toccata.\n\n" ..
  "Procedo?"

if reaper.ShowMessageBox(riepilogo, "ZP Studio Suite - Pulizia", 4) ~= 6 then
  msg("")
  msg("Dry-run completato. Non ho modificato niente.")
  write_all(log_path, "Dry-run " .. stamp .. "\nVoci: " .. tostring(#hits) ..
                      "\nCartelle: " .. tostring(#trovate) .. "\n")
  return
end

local log = {}
log[#log + 1] = "Pulizia installazione precedente - APPLICATA " .. stamp
log[#log + 1] = "Resource Path: " .. resource

if #hits > 0 then
  if not write_all(kb_backup, kb_txt) then
    reaper.ShowMessageBox("ERRORE: non riesco a creare la copia di reaper-kb.ini.\nMi fermo senza toccare niente.",
      "ZP Studio Suite", 0)
    return
  end
  local nuovo = table.concat(keep, "\n")
  if kb_txt:match("[\r\n]$") then nuovo = nuovo .. "\n" end
  if not write_all(kb, nuovo) then
    reaper.ShowMessageBox("ERRORE: copia creata ma non riesco a riscrivere reaper-kb.ini.\nIl file originale e' salvo in:\n" .. kb_backup,
      "ZP Studio Suite", 0)
    return
  end
  log[#log + 1] = "Copia di reaper-kb.ini: " .. kb_backup
  log[#log + 1] = "Voci rimosse:"
  for _, line in ipairs(hits) do log[#log + 1] = "  " .. line end
  msg("")
  msg("Copia di reaper-kb.ini creata: " .. kb_backup)
end

if #trovate > 0 then
  if sep == "\\" then
    os.execute('mkdir "' .. backup_root .. '" >NUL 2>NUL')
  else
    os.execute('mkdir -p "' .. backup_root:gsub('"', '\\"') .. '"')
  end
  for _, d in ipairs(trovate) do
    local dest = backup_root .. sep .. d.path:match("[^/\\]+$")
    local ok, err = os.rename(d.path, dest)
    if ok then
      log[#log + 1] = "Spostata [" .. d.nome .. "] in: " .. dest
      msg("Spostata [" .. d.nome .. "] in: " .. dest)
    else
      log[#log + 1] = "ERRORE spostando [" .. d.nome .. "]: " .. tostring(err)
      msg("ERRORE spostando [" .. d.nome .. "]: " .. tostring(err))
    end
  end
end

log[#log + 1] = "Toolbar e menu personalizzati non rimossi."
write_all(log_path, table.concat(log, "\n") .. "\n")
msg("")
msg("Log: " .. log_path)

reaper.ShowMessageBox(
  "Pulizia completata.\n\n" ..
  "1. Riavvia REAPER: la Action List si aggiorna al riavvio.\n" ..
  "2. La tua vecchia toolbar punta ancora agli script rimossi. " ..
  "Reimportala dal pacchetto: Options > Customize toolbars > Import, " ..
  "e scegli il file toolbar/ZP_StudioSuite.ReaperMenu della Suite.\n\n" ..
  "Niente e' stato cancellato: trovi tutto in\n" .. backup_root,
  "ZP Studio Suite - Pulizia", 0)
