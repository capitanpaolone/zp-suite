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
-- Preset: aggiunge in REAPER/presets i preset dei JSFX usati dal Chain Builder (BUS Chain
-- Voiceover_Body1..., Master Pro Flat -19). REAPER li lega al percorso del JSFX installato
-- da ReaPack. Si aggiungono solo i preset con un nome che non c'e' gia': i tuoi restano.

local M = {}

-- catene di effetti: file nel pacchetto -> nome in REAPER/FXChains
M.CHAINS = {
  { "fxchains/ZP_Bus_VoiceChain.RfxChain", "ZP Bus VoiceChain.RfxChain" },
  { "fxchains/ZP_MasterChain.RfxChain", "ZP MasterChain.RfxChain" },
}

-- preset dei JSFX: file nel pacchetto -> stesso nome in REAPER/presets (unione per nome)
M.PRESETS = {
  "js-ZP Suite_ZP Voce_ZP BUS Chain_jsfx.ini",
  "js-ZP Suite_ZP Master_ZP Master Pro_jsfx.ini",
}

-- La toolbar: la stessa che Paolo usa (Floating toolbar 8), con le icone di serie di REAPER
-- e due icone ZP nello stesso stile (Regioni_Item, Catena_FX, anche a 200% per Retina).
-- Voce: { script, testo, icona, icona di riserva } oppure { cmd = azione nativa, testo, icona }.
-- L'icona di riserva (ZP) si usa se l'icona scelta non c'e' in questo REAPER. "-" = separatore.
M.LAYOUT = {
  { "18_Project_Viewer.lua", "Project Viewer", "toolbar_item_arpeggiate.png", "ZP_tb_18_Project_Viewer.png" },
  { "17_Crea_Regioni_Export_da_Item_Nominati.lua", "Gestore Progetto", "ZP_tb_17_Regioni_Item.png" },
  { "19_Report_Minuti_Voce.lua", "Report minuti voce", "toolbar_misc_calculate_numeric.png", "ZP_tb_19_Report_Minuti.png" },
  "-",
  { "29_ZP_Trascrizione.lua", "ZP Trascrizione", "ZP_tb_29_Pannello_Trascrizione.png" },
  "-",
  { "02_Gobbo_Verticale.lua", "Gobbo verticale", "toolbar_item_selected_move_vertical_track.png", "ZP_tb_02_Gobbo_Verticale.png" },
  { "03_Gobbo_Orizzontale.lua", "Gobbo orizzontale", "toolbar_item_selected_move_horizontal_position_time.png", "ZP_tb_03_Gobbo_Orizzontale.png" },
  "-",
  { "20_Importa_Cartelle_Video_Mixdown.lua", "Importa cartelle", "toolbar_color_load_disk.png", "ZP_tb_20_Importa_Cartelle.png" },
  { "30_ZP_SRT.lua", "ZP SRT", "ZP_tb_30_ZP_SRT.png" },
  { "04_Crea_Marker_Item.lua", "Marker", "toolbar_marker_renum.png", "ZP_tb_04_Marker_Item.png" },
  "-",
  { "07_Note_Personaggio.lua", "Actor / Note", "toolbar_misc_mic.png", "ZP_tb_07_Actor_Note.png" },
  { "22_Pulisci_Code_Silenzi_e_Separa_Item.lua", "Voice Cleaner", "toolbar_misc_brush_broom_clean.png", "ZP_tb_22_Voice_Cleaner.png" },
  { "23_ZP_Chain_Builder.lua", "Chain Builder", "ZP_tb_23_Catena_FX.png" },
  { "25_ZP_SOLO_Recorder.lua", "SOLO Recorder", "ZP_tb_25_SOLO_Recorder.png" },
  "-",
  { cmd = 50125, "Video: Show/hide video window", "toolbar_video_screen.png" },
  { cmd = 42653, "Project tabs: Display video from background projects if active project lacks video", "ZP_tb_Importa_SRT_1_video.png" },
  { "24_ZP_Probe_Guard.lua", "Probe Guard", "toolbar_color_source_input_channel.png", "ZP_tb_24_Probe_Guard.png" },
  "-",
  { "00_Apri_Help_ZP_Studio_Suite.lua", "Help", "ZP_tb_00_Help.png" },
}

-- Icone di serie di REAPER (stanno dentro l'applicazione, non nella cartella dell'utente).
M.STOCK = {
  ["toolbar_item_arpeggiate.png"] = true, ["toolbar_misc_calculate_numeric.png"] = true,
  ["toolbar_item_selected_move_vertical_track.png"] = true,
  ["toolbar_item_selected_move_horizontal_position_time.png"] = true,
  ["toolbar_color_load_disk.png"] = true, ["toolbar_marker_renum.png"] = true, ["toolbar_misc_mic.png"] = true,
  ["toolbar_misc_brush_broom_clean.png"] = true, ["toolbar_video_screen.png"] = true,
  ["toolbar_color_source_input_channel.png"] = true,
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
-- Icona del pulsante: quella scelta, o la riserva ZP se has_icon dice che qui non c'e'.
function M.pick_icon(e, has_icon)
  if e[4] and has_icon and not has_icon(e[3]) then return e[4] end
  return e[3]
end

function M.menu_text(layout, ids, title, has_icon)
  local icons, items, n = {}, {}, 0
  for _, e in ipairs(layout) do
    if e == "-" then
      if n > 0 and items[#items] ~= "-1" then items[#items + 1] = "-1"; n = n + 1 end
    else
      local id = e.cmd and tostring(e.cmd) or ids[e[1]]
      local text = e.cmd and e[1] or e[2]
      local icon = e.cmd and e[2] or M.pick_icon(e, has_icon)
      if id then
        icons[#icons + 1] = string.format("icon_%d=%s", n, icon)
        items[#items + 1] = string.format("%s %s", id, text)
        n = n + 1
      end
    end
  end
  if items[#items] == "-1" then items[#items] = nil end
  local out = { "[Floating toolbar 32]" }
  for _, l in ipairs(icons) do out[#out + 1] = l end
  for i, l in ipairs(items) do out[#out + 1] = string.format("item_%d=%s", i - 1, l) end
  out[#out + 1] = "title=" .. (title or "ZP Studio Suite")
  return table.concat(out, "\n") .. "\n"
end

-- Preset di un file .ini di REAPER: elenco di { name, body } (body = righe sotto [PresetN]).
function M.preset_entries(text)
  local out, cur = {}, nil
  for line in (tostring(text or ""):gsub("\r", "") .. "\n"):gmatch("([^\n]*)\n") do
    if line:match("^%[Preset%d+%]$") then
      cur = { name = nil, body = {} }
      out[#out + 1] = cur
    elseif line:match("^%[") then
      cur = nil
    elseif cur and line ~= "" then
      cur.body[#cur.body + 1] = line
      local n = line:match("^Name=(.*)$")
      if n then cur.name = n end
    end
  end
  return out
end

-- Unisce i preset del pacchetto a quelli dell'utente: aggiunge solo i nomi che mancano,
-- in coda, e aggiorna NbPresets. Restituisce il testo nuovo e i nomi aggiunti.
function M.merge_presets(user, pkg)
  user = user and tostring(user):gsub("\r", "") or ""
  local pkg_entries = M.preset_entries(pkg)
  if not user:match("%S") then
    local names = {}
    for _, e in ipairs(pkg_entries) do names[#names + 1] = e.name end
    return pkg, names
  end
  local have = {}
  local user_entries = M.preset_entries(user)
  for _, e in ipairs(user_entries) do if e.name then have[e.name] = true end end
  local n = tonumber(user:match("NbPresets=(%d+)")) or #user_entries
  local add, names = {}, {}
  for _, e in ipairs(pkg_entries) do
    if e.name and not have[e.name] then
      add[#add + 1] = "[Preset" .. n .. "]\n" .. table.concat(e.body, "\n") .. "\n"
      names[#names + 1] = e.name
      n = n + 1
    end
  end
  if #add == 0 then return user, names end
  if user:match("NbPresets=%d+") then
    user = user:gsub("NbPresets=%d+", "NbPresets=" .. n, 1)
  else
    user = user:gsub("%[General%]\n", "[General]\nNbPresets=" .. n .. "\n", 1)
  end
  if not user:match("\n\n$") then user = user:gsub("\n*$", "") .. "\n\n" end
  return user .. table.concat(add, "\n") .. "\n", names
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
  if e ~= "-" and not e.cmd then
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
local function has_icon(name)
  return M.STOCK[name] or exists(resource .. sep .. "Data" .. sep .. "toolbar_icons" .. sep .. name)
end
f:write(M.menu_text(M.LAYOUT, ids, nil, has_icon))
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

-- preset dei JSFX in REAPER/presets
local preset_dir = resource .. sep .. "presets"
reaper.RecursiveCreateDirectory(preset_dir, 0)
local preset_lines = {}
for _, name in ipairs(M.PRESETS) do
  local pkg = read(here .. sep .. "presets" .. sep .. name)
  local dest = preset_dir .. sep .. name
  if not pkg then
    preset_lines[#preset_lines + 1] = name .. ": non trovato nel pacchetto"
  else
    local user = read(dest)
    local merged, added = M.merge_presets(user, pkg)
    if #added == 0 then
      preset_lines[#preset_lines + 1] = "gia' presenti: " .. table.concat((function()
        local t = {} for _, e in ipairs(M.preset_entries(pkg)) do t[#t + 1] = e.name end return t end)(), ", ")
    else
      if user then
        local b = io.open(dest .. ".ZPSS_backup_" .. os.date("%Y%m%d_%H%M%S"), "wb")
        if b then b:write(user); b:close() end
      end
      local out = io.open(dest, "wb")
      if out then out:write(merged); out:close(); preset_lines[#preset_lines + 1] = "aggiunti: " .. table.concat(added, ", ")
      else preset_lines[#preset_lines + 1] = name .. ": non riesco a scriverlo" end
    end
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
msg = msg .. "\n\nPreset per il Chain Builder (REAPER/presets):\n" .. table.concat(preset_lines, "\n")
reaper.MB(msg, "ZP Installa toolbar ed effetti", 0)
