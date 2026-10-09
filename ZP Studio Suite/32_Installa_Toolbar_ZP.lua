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
-- Poi scrive la toolbar "ZP Studio Suite" in reaper-menu.ini (backup accanto): nella toolbar che
-- si chiama gia' cosi', altrimenti nella prima Floating toolbar libera fra 1 e 16; le altre
-- toolbar e i menu restano com'erano. REAPER la carica al riavvio. Ne lascia anche una copia
-- in MenuSets/ZP_StudioSuite.ReaperMenu, da importare a mano se serve.
-- Catene: se in FXChains c'e' gia' una catena con lo stesso nome non viene sovrascritta
-- (puo' essere la tua, personalizzata).
-- Marker degli item: se valgono i comandi di serie di REAPER li protegge (trascinare prende l'item,
-- Shift+trascina sposta il marker); logica nel 33 Benvenuto.
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

-- La toolbar: la stessa che Paolo usa (Floating toolbar 8). Icone ZP in stile B (2026-10-08):
-- riquadro scuro, disegno chiaro, verde acqua quando lo strumento e' aperto; anche a 200% per Retina.
-- Si rifanno con gobbo_ricerca_battuta/strumenti/genera_icone_toolbar_B.py. SOLO Recorder ha la sua.
-- Voce: { script, testo, icona, icona di riserva } oppure { cmd = azione nativa, testo, icona, riserva }.
-- L'icona di riserva si usa se l'icona scelta non c'e' in questo REAPER (es. ReaPack non ancora
-- aggiornato: restano le icone di prima). "-" = separatore.
M.LAYOUT = {
  { "18_Project_Viewer.lua", "Project Viewer", "ZP_tbB_18_Project_Viewer.png", "toolbar_item_arpeggiate.png" },
  { "17_Crea_Regioni_Export_da_Item_Nominati.lua", "Gestore Progetto", "ZP_tbB_17_Gestore_Progetto.png", "ZP_tb_17_Regioni_Item.png" },
  { "19_Report_Minuti_Voce.lua", "Report minuti voce", "ZP_tbB_19_Report_Minuti.png", "toolbar_misc_calculate_numeric.png" },
  "-",
  { "29_ZP_Trascrizione.lua", "ZP Trascrizione", "ZP_tbB_29_Trascrizione.png", "ZP_tb_29_Pannello_Trascrizione.png" },
  "-",
  { "02_Gobbo_Verticale.lua", "Gobbo verticale", "ZP_tbB_02_Gobbo_Verticale.png", "toolbar_item_selected_move_vertical_track.png" },
  { "03_Gobbo_Orizzontale.lua", "Gobbo orizzontale", "ZP_tbB_03_Gobbo_Orizzontale.png", "toolbar_item_selected_move_horizontal_position_time.png" },
  "-",
  { "20_Importa_Cartelle_Video_Mixdown.lua", "Importa cartelle", "ZP_tbB_20_Importa_Cartelle.png", "toolbar_color_load_disk.png" },
  { "30_ZP_SRT.lua", "ZP SRT", "ZP_tbB_30_ZP_SRT.png", "ZP_tb_30_ZP_SRT.png" },
  { "04_Crea_Marker_Item.lua", "Marker", "ZP_tbB_04_Marker.png", "toolbar_marker_renum.png" },
  "-",
  { "07_Note_Personaggio.lua", "Actor / Note", "ZP_tbB_07_Actor_Note.png", "toolbar_misc_mic.png" },
  { "22_Pulisci_Code_Silenzi_e_Separa_Item.lua", "Voice Cleaner", "ZP_tbB_22_Voice_Cleaner.png", "toolbar_misc_brush_broom_clean.png" },
  { "23_ZP_Chain_Builder.lua", "Chain Builder", "ZP_tbB_23_Chain_Builder.png", "ZP_tb_23_Catena_FX.png" },
  { "25_ZP_SOLO_Recorder.lua", "SOLO Recorder", "ZP_tb_25_SOLO_Recorder.png" },
  "-",
  { cmd = 50125, "Video: Show/hide video window", "ZP_tbB_Video.png", "toolbar_video_screen.png" },
  { cmd = 42653, "Project tabs: Display video from background projects if active project lacks video", "ZP_tbB_Video_Sfondo.png", "ZP_tb_Importa_SRT_1_video.png" },
  { "24_ZP_Probe_Guard.lua", "Probe Guard", "ZP_tbB_24_Probe_Guard.png", "toolbar_color_source_input_channel.png" },
  "-",
  { "35_ZP_Colori.lua", "ZP Colori", "ZP_tbB_35_Colori.png", "toolbar_color_random_question.png" },
  { "34_ZP_Set_Comandi.lua", "Set Comandi", "ZP_tbB_34_Set_Comandi.png" },
  { "00_Apri_Help_ZP_Studio_Suite.lua", "Help", "ZP_tbB_00_Help.png", "ZP_tb_00_Help.png" },
}

-- Toolbar "ZP Colori" (clicca e colora, 2026-10-09), FACOLTATIVA: si scrive solo se chiesta dal 33
-- Benvenuto (ExtState persistente ZP_STUDIO_SUITE/toolbar_colori = 1) o se c'e' gia' (si aggiorna).
-- Senza toolbar si usa la finestrella 35 ZP Colori, dal pulsante tavolozza della toolbar ZP.
-- Pulsanti: tre interruttori di modo (Item, Traccia, Tutto),
-- i 20 colori della palette e Togli colore. Logica in ZP_Colori.lua, pulsanti in colori/.
-- Icone: gobbo_ricerca_battuta/strumenti/genera_icone_colori.py
M.TITLE_COLORI = "ZP Colori"
M.LAYOUT_COLORI = {
  { "colori/ZP_Colori_Modo_Item.lua", "ZP Colori: modo Item (colora gli item selezionati)", "ZP_tbC_Item.png" },
  { "colori/ZP_Colori_Modo_Traccia.lua", "ZP Colori: modo Traccia (colora le tracce, non gli item)", "ZP_tbC_Traccia.png" },
  { "colori/ZP_Colori_Modo_Tutto.lua", "ZP Colori: modo Tutto (tracce e item dentro)", "ZP_tbC_Tutto.png" },
  "-",
}
do
  local ok, C = pcall(dofile, (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or ".") .. "/ZP_Colori.lua")
  if ok and C then
    for i, p in ipairs(C.PALETTE) do
      M.LAYOUT_COLORI[#M.LAYOUT_COLORI + 1] = { "colori/" .. C.color_file(i), "ZP Colori: " .. p[1], string.format("ZP_tbC_%02d.png", i) }
    end
  end
  M.LAYOUT_COLORI[#M.LAYOUT_COLORI + 1] = "-"
  M.LAYOUT_COLORI[#M.LAYOUT_COLORI + 1] = { "colori/ZP_Colori_Togli.lua", "ZP Colori: togli colore", "ZP_tbC_Togli.png" }
end

-- Icone di serie di REAPER (stanno dentro l'applicazione, non nella cartella dell'utente).
M.STOCK = {
  ["toolbar_item_arpeggiate.png"] = true, ["toolbar_misc_calculate_numeric.png"] = true,
  ["toolbar_item_selected_move_vertical_track.png"] = true,
  ["toolbar_item_selected_move_horizontal_position_time.png"] = true,
  ["toolbar_color_load_disk.png"] = true, ["toolbar_marker_renum.png"] = true, ["toolbar_misc_mic.png"] = true,
  ["toolbar_misc_brush_broom_clean.png"] = true, ["toolbar_video_screen.png"] = true,
  ["toolbar_color_source_input_channel.png"] = true, ["toolbar_color_random_question.png"] = true,
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
  -- script: { script, testo, icona, riserva }; azione nativa: { cmd = ..., testo, icona, riserva }
  local icon, spare = e[3], e[4]
  if e.cmd then icon, spare = e[2], e[3] end
  if spare and has_icon and not has_icon(icon) then return spare end
  return icon
end

function M.menu_text(layout, ids, title, has_icon, slot)
  local icons, items, n = {}, {}, 0
  for _, e in ipairs(layout) do
    if e == "-" then
      if n > 0 and items[#items] ~= "-1" then items[#items + 1] = "-1"; n = n + 1 end
    else
      local id = e.cmd and tostring(e.cmd) or ids[e[1]]
      local text = e.cmd and e[1] or e[2]
      local icon = M.pick_icon(e, has_icon)
      if id then
        icons[#icons + 1] = string.format("icon_%d=%s", n, icon)
        items[#items + 1] = string.format("%s %s", id, text)
        n = n + 1
      end
    end
  end
  if items[#items] == "-1" then items[#items] = nil end
  local out = { "[Floating toolbar " .. (slot or 32) .. "]" }
  for _, l in ipairs(icons) do out[#out + 1] = l end
  for i, l in ipairs(items) do out[#out + 1] = string.format("item_%d=%s", i - 1, l) end
  out[#out + 1] = "title=" .. (title or "ZP Studio Suite")
  return table.concat(out, "\n") .. "\n"
end

-- reaper-menu.ini: in quale Floating toolbar scrivere una toolbar ZP. Quella che si chiama gia'
-- cosi' (title, di serie "ZP Studio Suite": si aggiorna), altrimenti la prima libera fra 1 e 16
-- (stanno in View > Toolbars), poi fra 17 e 32. Libera = sezione assente o senza pulsanti.
function M.pick_slot(ini, title)
  title = title or "ZP Studio Suite"
  -- riga per riga: con un pattern su tutto il testo la riga vuota fra due sezioni veniva
  -- consumata e una toolbar si' e una no restava fuori (sembrava libera)
  local used, cur = {}, nil
  for line in tostring(ini or ""):gsub("\r", ""):gmatch("[^\n]+") do
    local sec = line:match("^%[(.-)%]%s*$")
    if sec then
      cur = tonumber(sec:match("^Floating toolbar (%d+)$"))
    elseif cur then
      if line == "title=" .. title then return cur end
      if line:match("^item_%d+=") then used[cur] = true end
    end
  end
  for n = 1, 32 do if not used[n] then return n end end
  return nil
end

-- Mette (o rimpiazza) la sezione [nome] in reaper-menu.ini; il resto del file resta com'e'.
function M.put_section(ini, section_text)
  ini = ini or ""
  local name = section_text:match("^%[([^%]]+)%]")
  local body = (section_text:gsub("\n+$", ""))
  local out, skipping, done = {}, false, false
  for line in (ini .. ((ini == "" or ini:match("\n$")) and "" or "\n")):gmatch("([^\n]*)\n") do
    local sec = line:match("^%[(.+)%]%s*$")
    if sec then
      skipping = (sec == name)
      if skipping and not done then out[#out + 1] = body; out[#out + 1] = ""; done = true end
    end
    if not skipping then out[#out + 1] = line end
  end
  if not done then
    if #out > 0 and out[#out] ~= "" then out[#out + 1] = "" end
    out[#out + 1] = body
  end
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
local all_buttons = {}
for _, e in ipairs(M.LAYOUT) do all_buttons[#all_buttons + 1] = e end
for _, e in ipairs(M.LAYOUT_COLORI) do all_buttons[#all_buttons + 1] = e end
for _, e in ipairs(all_buttons) do
  if e ~= "-" and not e.cmd then
    local path = here .. sep .. e[1]:gsub("/", sep)
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

-- La toolbar va anche in reaper-menu.ini, col nome "ZP Studio Suite": dopo un riavvio di REAPER
-- si sceglie con Switch toolbar (l'Import di REAPER non porta il nome e chiede passi a mano).
-- REAPER riscrive reaper-menu.ini solo quando si modificano menu o toolbar: finche' non si
-- riavvia non va aperto Customize toolbars, altrimenti la sezione scritta qui si perde.
local menu_ini_path = resource .. sep .. "reaper-menu.ini"
local menu_ini = read(menu_ini_path) or ""
local slot = M.pick_slot(menu_ini)
local slot_msg
if slot then
  if menu_ini ~= "" then
    local bk = io.open(menu_ini_path .. ".ZP_backup_" .. os.date("%Y%m%d_%H%M%S"), "wb")
    if bk then bk:write(menu_ini); bk:close() end
  end
  local w = io.open(menu_ini_path, "wb")
  if w then
    local new_ini = M.put_section(menu_ini, M.menu_text(M.LAYOUT, ids, nil, has_icon, slot))
    w:write(new_ini)
    w:close()
    -- "da riavviare" vale finche' il file e' quello scritto qui: se REAPER lo riscrive (Customize
    -- toolbars, Import) la toolbar e' gia' nella sua memoria. Non persistente: sparisce al riavvio.
    reaper.SetExtState("ZP_STUDIO_SUITE", "toolbar_da_riavviare", slot .. "|" .. #new_ini, false)
    slot_msg = "Toolbar \"ZP Studio Suite\" scritta nella Floating toolbar " .. slot .. ".\n" ..
      "RIAVVIA REAPER: dopo la trovi con Switch toolbar (o View > Toolbars).\n" ..
      "Prima del riavvio non aprire Customize toolbars, altrimenti va rifatto."
  end
end
if not slot_msg then
  slot_msg = "Non ho potuto scriverla in reaper-menu.ini: importala a mano da Options > Customize\n" ..
    "menus/toolbars > Import, file " .. target
end

-- Toolbar "ZP Colori": stessa strada, in un'altra Floating toolbar (quella che si chiama gia' cosi',
-- o la prima libera dopo aver scritto la ZP Studio Suite).
local colori_msg
local want_colori = reaper.GetExtState("ZP_STUDIO_SUITE", "toolbar_colori") == "1"
  or (function()
    for line in (read(menu_ini_path) or ""):gmatch("[^\r\n]+") do if line == "title=" .. M.TITLE_COLORI then return true end end
  end)()
if want_colori then
  local colori_text = M.menu_text(M.LAYOUT_COLORI, ids, M.TITLE_COLORI, has_icon)
  local cf = io.open(menu_dir .. sep .. "ZP_Colori.ReaperMenu", "wb")
  if cf then cf:write(colori_text); cf:close() end
  local ini_now = read(menu_ini_path) or ""
  local cslot = M.pick_slot(ini_now, M.TITLE_COLORI)
  local w = cslot and io.open(menu_ini_path, "wb")
  if w then
    local new_ini = M.put_section(ini_now, M.menu_text(M.LAYOUT_COLORI, ids, M.TITLE_COLORI, has_icon, cslot))
    w:write(new_ini)
    w:close()
    if slot then reaper.SetExtState("ZP_STUDIO_SUITE", "toolbar_da_riavviare", slot .. "|" .. #new_ini, false) end
    colori_msg = "Toolbar \"ZP Colori\" (clicca e colora) scritta nella Floating toolbar " .. cslot .. "."
  else
    colori_msg = "Toolbar \"ZP Colori\": importala a mano dal file " .. menu_dir .. sep .. "ZP_Colori.ReaperMenu"
  end
  -- i tre pulsanti dei modi: il loro identificativo serve a ZP_Colori per accendere quello giusto
  for _, mode in ipairs({ "Item", "Traccia", "Tutto" }) do
    local id = ids["colori/ZP_Colori_Modo_" .. mode .. ".lua"]
    if id then reaper.SetExtState("ZP_COLORI", "cmd_" .. mode:lower(), id, true) end
  end
else
  colori_msg = "Colori: pulsante tavolozza nella toolbar (finestrella 35 ZP Colori). La toolbar ZP Colori, facoltativa, si installa dal 33 Benvenuto."
end

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

-- marker degli item: protetti se valgono ancora i comandi di serie di REAPER (le impostazioni
-- personali non si toccano); si torna indietro dal Benvenuto (33) con Ripristina standard
local marker_msg
do
  ZP_BENVENUTO_LIB = true
  local okb, B = pcall(dofile, here .. sep .. "33_Benvenuto_Controllo_Installazione.lua")
  ZP_BENVENUTO_LIB = nil
  if okb and B and reaper.GetMouseModifier and reaper.SetMouseModifier then
    local st = B.marker_state(function(f) return reaper.GetMouseModifier(B.MARKER_CTX, f) end)
    if st == "serie" then
      B.marker_protect(reaper.SetMouseModifier)
      marker_msg = "protetti: trascinando sopra un marker prendi l'item, Shift+trascina sposta il marker\n(33 Benvenuto > Ripristina standard per tornare ai comandi di REAPER)"
    elseif st == "ok" then marker_msg = "gia' protetti (Shift+trascina sposta il marker)"
    else marker_msg = "impostazioni tue in Mouse Modifiers, non toccate (33 Benvenuto > Proteggi)" end
  end
end

local buttons = 0
for _, e in ipairs(M.LAYOUT) do if type(e) == "table" and (e.cmd or ids[e[1]]) then buttons = buttons + 1 end end
local msg = string.format(
  "Toolbar con %d pulsanti, con gli identificativi di questo REAPER.\n\n%s\n\n(Copia da importare a mano, se serve: %s)",
  buttons, slot_msg, target)
msg = msg .. "\n\n" .. colori_msg
if #registered > 0 then msg = msg .. "\n\nRegistrati ora nell'Action List: " .. table.concat(registered, ", ") end
if #missing > 0 then msg = msg .. "\n\nNON trovati (pulsante saltato): " .. table.concat(missing, ", ") end
msg = msg .. "\n\nCatene di effetti per il SOLO Recorder (REAPER/FXChains):\n" .. table.concat(chain_lines, "\n")
msg = msg .. "\n\nPreset per il Chain Builder (REAPER/presets):\n" .. table.concat(preset_lines, "\n")
if marker_msg then msg = msg .. "\n\nMarker degli item: " .. marker_msg end
reaper.MB(msg, "ZP Installa toolbar ed effetti", 0)
