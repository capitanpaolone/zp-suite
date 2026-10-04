-- @noindex

-- ZP Studio Suite for REAPER
-- 32 Installa toolbar ed effetti ZP: da lanciare dopo la prima installazione o un
-- aggiornamento. Scrive la toolbar della suite con gli identificativi delle azioni di
-- QUESTO REAPER e mette in REAPER/FXChains le catene di effetti usate dal SOLO Recorder
-- (Effetti ON): ZP Bus VoiceChain (bus voci) e ZP MasterChain (master).
--
-- Perche': ogni pulsante richiama uno script con un identificativo che REAPER assegna
-- quando registra lo script, e che cambia da un Mac all'altro. Un file toolbar fisso
-- avrebbe pulsanti vuoti per gli script nuovi. Questo script li cerca qui:
--   1. nel file delle azioni (reaper-kb.ini), se lo script e' gia' registrato;
--   2. altrimenti lo registra adesso nell'Action List.
-- Poi scrive MenuSets/ZP_StudioSuite.ReaperMenu (con copia del file precedente) e
-- spiega come importarlo. Non tocca le toolbar che stai usando.
-- Catene: se in FXChains c'e' gia' una catena con lo stesso nome non viene sovrascritta
-- (puo' essere la tua, personalizzata).

local M = {}

-- catene di effetti: file nel pacchetto -> nome in REAPER/FXChains
M.CHAINS = {
  { "fxchains/ZP_Bus_VoiceChain.RfxChain", "ZP Bus VoiceChain.RfxChain" },
  { "fxchains/ZP_MasterChain.RfxChain", "ZP MasterChain.RfxChain" },
}

-- La toolbar: script, testo del pulsante, icona. "-" = separatore.
M.LAYOUT = {
  { "18_Project_Viewer.lua", "Project Viewer", "ZP_tb_18_Project_Viewer.png" },
  { "17_Crea_Regioni_Export_da_Item_Nominati.lua", "Gestore Progetto", "ZP_tb_17_Gestore_Progetto.png" },
  { "19_Report_Minuti_Voce.lua", "Report minuti voce", "ZP_tb_19_Report_Minuti.png" },
  "-",
  { "29_ZP_Trascrizione.lua", "ZP Trascrizione", "ZP_tb_29_Pannello_Trascrizione.png" },
  "-",
  { "02_Gobbo_Verticale.lua", "Gobbo verticale", "ZP_tb_02_Gobbo_Verticale.png" },
  { "03_Gobbo_Orizzontale.lua", "Gobbo orizzontale", "ZP_tb_03_Gobbo_Orizzontale.png" },
  "-",
  { "20_Importa_Cartelle_Video_Mixdown.lua", "Importa cartelle", "ZP_tb_20_Importa_Cartelle.png" },
  { "30_ZP_SRT.lua", "ZP SRT", "ZP_tb_30_ZP_SRT.png" },
  { "04_Crea_Marker_Item.lua", "Marker", "ZP_tb_04_Marker_Item.png" },
  "-",
  { "07_Note_Personaggio.lua", "Actor / Note", "ZP_tb_07_Actor_Note.png" },
  { "22_Pulisci_Code_Silenzi_e_Separa_Item.lua", "Voice Cleaner", "ZP_tb_22_Voice_Cleaner.png" },
  { "23_ZP_Chain_Builder.lua", "Chain Builder", "ZP_tb_23_Chain_Builder.png" },
  { "24_ZP_Probe_Guard.lua", "Probe Guard", "ZP_tb_24_Probe_Guard.png" },
  { "25_ZP_SOLO_Recorder.lua", "SOLO Recorder", "ZP_tb_25_SOLO_Recorder.png" },
  "-",
  { "00_Apri_Help_ZP_Studio_Suite.lua", "Help", "ZP_tb_00_Help.png" },
}

---------------------------------------------------------------------------
-- LOGICA PURA (collaudabile con lua fuori da REAPER)
---------------------------------------------------------------------------

local function norm(p)
  return (tostring(p):gsub("\\", "/"):gsub("/+", "/"):lower())
end

-- Dal testo di reaper-kb.ini: percorso normalizzato -> identificativo "_RS...",
-- solo azioni della sezione principale (0). Il primo trovato vince.
-- I percorsi relativi sono relativi alla cartella Scripts.
function M.ids_from_kb(kb_text, scripts_dir)
  local ids = {}
  for line in (kb_text .. "\n"):gmatch("([^\n]*)\n") do
    local section, id, rest = line:match('^SCR%s+%d+%s+(%d+)%s+(RS%x+)%s+"[^"]*"%s+(.-)%s*$')
    if section == "0" and rest and rest ~= "" then
      local path = rest:match('^"(.*)"$') or rest
      if not path:match("^/") and not path:match("^%a:[/\\]") then path = scripts_dir .. "/" .. path end
      local key = norm(path)
      if not ids[key] then ids[key] = "_" .. id end
    end
  end
  return ids
end

-- Testo del file .ReaperMenu. ids: nome script -> "_RS..." (mancante = pulsante saltato)
function M.menu_text(layout, ids, title)
  local icons, items, n = {}, {}, 0
  for _, e in ipairs(layout) do
    if e == "-" then
      if n > 0 and items[#items] ~= "-1" then items[#items + 1] = "-1"; n = n + 1 end
    elseif ids[e[1]] then
      icons[#icons + 1] = string.format("icon_%d=%s", n, e[3])
      items[#items + 1] = string.format("%s %s", ids[e[1]], e[2])
      n = n + 1
    end
  end
  if items[#items] == "-1" then items[#items] = nil end
  local out = { "[Floating toolbar 32]" }
  for _, l in ipairs(icons) do out[#out + 1] = l end
  for i, l in ipairs(items) do out[#out + 1] = string.format("item_%d=%s", i - 1, l) end
  out[#out + 1] = "title=" .. (title or "ZP Studio Suite")
  return table.concat(out, "\n") .. "\n"
end

if not reaper then return M end

---------------------------------------------------------------------------
-- PARTE REAPER
---------------------------------------------------------------------------

local sep = package.config:sub(1, 1)
local here = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or ".")
local resource = reaper.GetResourcePath()
local function read(p) local f = io.open(p, "rb"); if not f then return nil end local d = f:read("*a"); f:close(); return d end
local function exists(p) local f = io.open(p, "rb"); if f then f:close() return true end return false end

local kb_ids = M.ids_from_kb(read(resource .. sep .. "reaper-kb.ini") or "", resource .. "/Scripts")
local ids, registered, missing = {}, {}, {}
local to_register = {}
for _, e in ipairs(M.LAYOUT) do
  if e ~= "-" then
    local path = here .. sep .. e[1]
    if not exists(path) then
      missing[#missing + 1] = e[1]
    else
      local id = kb_ids[norm(path)]
      if id then ids[e[1]] = id else to_register[#to_register + 1] = { name = e[1], path = path } end
    end
  end
end
for i, r in ipairs(to_register) do
  local cmd = reaper.AddRemoveReaScript(true, 0, r.path, i == #to_register)
  local named = cmd and cmd > 0 and reaper.ReverseNamedCommandLookup(cmd)
  if named and named ~= "" then
    ids[r.name] = "_" .. named:gsub("^_", "")
    registered[#registered + 1] = r.name
  else
    missing[#missing + 1] = r.name
  end
end

local menu_dir = resource .. sep .. "MenuSets"
reaper.RecursiveCreateDirectory(menu_dir, 0)
local target = menu_dir .. sep .. "ZP_StudioSuite.ReaperMenu"
local old = read(target)
if old then
  local f = io.open(target .. ".ZPSS_backup_" .. os.date("%Y%m%d_%H%M%S"), "wb")
  if f then f:write(old); f:close() end
end
local f = io.open(target, "wb")
if not f then
  reaper.MB("Non riesco a scrivere:\n" .. target, "ZP Installa toolbar", 0)
  return
end
f:write(M.menu_text(M.LAYOUT, ids))
f:close()

-- catene di effetti in REAPER/FXChains
local chain_dir = resource .. sep .. "FXChains"
reaper.RecursiveCreateDirectory(chain_dir, 0)
local chain_lines = {}
for _, c in ipairs(M.CHAINS) do
  local data = read(here .. sep .. c[1]:gsub("/", sep))
  local dest = chain_dir .. sep .. c[2]
  local existing = read(dest)
  if not data then
    chain_lines[#chain_lines + 1] = c[2] .. ": non trovata nel pacchetto"
  elseif existing == data then
    chain_lines[#chain_lines + 1] = c[2] .. ": gia' aggiornata"
  elseif existing then
    chain_lines[#chain_lines + 1] = c[2] .. ": ce n'e' gia' una con questo nome, non toccata"
  else
    local out = io.open(dest, "wb")
    if out then out:write(data); out:close(); chain_lines[#chain_lines + 1] = c[2] .. ": installata"
    else chain_lines[#chain_lines + 1] = c[2] .. ": non riesco a scriverla" end
  end
end

local buttons = 0
for _ in pairs(ids) do buttons = buttons + 1 end
local msg = string.format(
  "Toolbar scritta con %d pulsanti, con gli identificativi di questo REAPER.\n\n%s\n\nPer metterla in REAPER:\nOptions > Customize menus/toolbars, scegli una toolbar libera (es. Floating toolbar 32),\npoi Import/Export > Import e scegli questo file.",
  buttons, target)
if #registered > 0 then msg = msg .. "\n\nRegistrati ora nell'Action List: " .. table.concat(registered, ", ") end
if #missing > 0 then msg = msg .. "\n\nNON trovati (pulsante saltato): " .. table.concat(missing, ", ") end
msg = msg .. "\n\nCatene di effetti per il SOLO Recorder (REAPER/FXChains):\n" .. table.concat(chain_lines, "\n")
reaper.MB(msg, "ZP Installa toolbar ed effetti", 0)
