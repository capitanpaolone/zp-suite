-- @noindex

-- ZP Studio Suite for REAPER
-- 30 ZP SRT: tutto quello che si fa con gli SRT, in una finestra, nell'ordine
-- in cui si lavora: porta dentro, controlla, porta fuori.
--
-- Non rifa' il lavoro degli script: apre lo strumento giusto come azione a se' (dall'Action
-- List), cosi' questa finestra RESTA APERTA e la chiudi tu. Solo se lo script non si trova
-- tra le azioni si chiude e lo apre direttamente. Gli script restano utilizzabili da soli.

local sep = package.config:sub(1, 1)
local here = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or ".")
local function path_of(name) return here .. sep .. name end
local function exists(p) local f = io.open(p, "rb"); if f then f:close() return true end return false end

if not exists(path_of("ZP_UI.lua")) then
  reaper.ShowMessageBox("Non trovo ZP_UI.lua accanto allo script.", "ZP SRT", 0)
  return
end
local UI = dofile(path_of("ZP_UI.lua"))

-- Colonne e strumenti. op = operazione preselezionata nel 05 (ExtState SRT_OP).
local COLUMNS = {
  { title = "1  Porta dentro", items = {
    { label = "Video + SRT", script = "01_Importa_Video_SRT.lua",
      hint = "nuovo lavoro video",
      help = "Importa un video e il suo SRT: crea la traccia video e la traccia testi. Tempi della timeline." },
    { label = "Sostituisci testi", script = "05_Aggiorna_SRT_Video.lua",
      hint = "su video, regione o tutti",
      help = "Cambia i sottotitoli di video gia' in progetto: video selezionati, regione sotto la playhead o tutti gli omonimi. Gli item vecchi vanno su una traccia BKP." },
    { label = "Aggiungi lingua", script = "05_Aggiorna_SRT_Video.lua", op = 2,
      hint = "reference, non sostituisce",
      help = "Aggiunge un secondo flusso (es. ENG o ORIG) al video selezionato, senza toccare il testo principale. Si legge nel Gobbo con < >." },
    { label = "Collega a un audio", script = "29_ZP_Trascrizione.lua",
      hint = "29: il testo segue i tagli",
      help = "Apre la strada 29: trascrivi o abbina un SRT (anche tradotto) a un item audio. Tempi del file: il testo segue tagli e spostamenti." },
    { label = "Da testo o traduzione", script = "26_SRT_Tools.lua",
      hint = "crea l'SRT, poi qui sopra",
      help = "Apre SRT Tools: testo con timecode (es. traduzione da Excel/Word) -> SRT. Poi usalo con Sostituisci, Aggiungi lingua o Collega a un audio." },
  } },
  { title = "2  Controlla", items = {
    { label = "Info item SRT", script = "13_Info_Item_SRT.lua",
      hint = "origine e testo, solo lettura",
      help = "Mostra da quale SRT e da quale cue viene l'item di testo selezionato. Non modifica niente." },
    { label = "Traccia gobbo vuota", script = "05_Aggiorna_SRT_Video.lua", op = 5,
      hint = "per scrivere a mano",
      help = "Crea (o riusa) la traccia Rythmo Band Testi e mette un item TESTO alla playhead, pronto da scrivere." },
    { label = "Leggi nel Gobbo", script = "02_Gobbo_Verticale.lua",
      hint = "Leggi tutto, ricerca",
      help = "Apre il Gobbo verticale. In Flusso testi, 'Tutti' legge insieme tutte le tracce di testo; la ricerca trova parole ovunque." },
  } },
  { title = "3  Porta fuori", items = {
    { label = "Esporta SRT", script = "08_Esporta_SRT.lua",
      hint = "video, regioni o tutto",
      help = "Scrive gli SRT finali dai testi in timeline: per video selezionati, regione al cursore, tutte le regioni o tutti i video." },
    { label = "SRT dall'audio", script = "31_SRT_da_Marker_Audio.lua",
      hint = "marker -> SRT, scegli la cartella",
      help = "Dai marker degli item audio selezionati scrive l'SRT nella cartella che scegli (anche dopo tagli o Glue). Da consegnare al fonico o da riusare." },
  } },
}

local last_down = false
local hover_help = nil

-- Identificativo d'azione dello script: dal file delle azioni (reaper-kb.ini) o, se non
-- c'e', registrandolo adesso nell'Action List (come fa la 32). 0 = non disponibile.
local function norm(p) return (tostring(p):gsub("\\", "/"):gsub("/+", "/"):lower()) end
local function command_for(path)
  local f = io.open(reaper.GetResourcePath() .. sep .. "reaper-kb.ini", "rb")
  local kb = f and f:read("*a") or ""
  if f then f:close() end
  local want, scripts = norm(path), reaper.GetResourcePath() .. "/Scripts/"
  for line in kb:gmatch("[^\n]+") do
    local section, id, rest = line:match('^SCR%s+%d+%s+(%d+)%s+(RS%x+)%s+"[^"]*"%s+(.-)%s*$')
    if section == "0" and rest then
      local p = rest:match('^"(.*)"$') or rest
      if not p:match("^/") and not p:match("^%a:[/\\]") then p = scripts .. p end
      if norm(p) == want then
        local cmd = reaper.NamedCommandLookup("_" .. id)
        if cmd and cmd > 0 then return cmd end
      end
    end
  end
  local cmd = reaper.AddRemoveReaScript(true, 0, path, true)
  return cmd or 0
end

-- true = questa finestra si e' chiusa (ripiego)
local function launch(entry)
  local p = path_of(entry.script)
  if not exists(p) then
    reaper.ShowMessageBox("Non trovo " .. entry.script .. " accanto a questo script.", "ZP SRT", 0)
    return false
  end
  if entry.op then reaper.SetExtState("ZP_STUDIO_SUITE", "SRT_OP", tostring(entry.op), false)
  else reaper.DeleteExtState("ZP_STUDIO_SUITE", "SRT_OP", false) end
  local cmd = command_for(p)
  if cmd > 0 then
    reaper.Main_OnCommand(cmd, 0)
    return false
  end
  gfx.quit()
  _G.ZP_SRT_OP = entry.op
  local ok, err = pcall(dofile, p)
  if not ok then reaper.ShowMessageBox("Errore in " .. entry.script .. ":\n\n" .. tostring(err), "ZP SRT", 0) end
  return true
end

-- toolbar: icona accesa finche' la finestra e' aperta; un altro clic sull'icona la chiude (REAPER 7.03+)
if reaper.set_action_options then reaper.set_action_options(1 | 4); reaper.atexit(function() reaper.set_action_options(8) end) end
gfx.init("ZP Studio Suite - ZP SRT", 780, 530, 0)

local function loop()
  if gfx.getchar() < 0 then gfx.quit() return end
  local down = (gfx.mouse_cap & 1) == 1
  local clicked = down and not last_down
  last_down = down
  hover_help = nil

  UI.fill_background()
  UI.draw_header({ title = "ZP SRT", description = "Scegli cosa vuoi fare con gli SRT: apre lo strumento giusto e resta aperta, la chiudi tu." })
  UI.draw_help_button({ x = gfx.w - 54, y = 16, w = 34, h = 28 }, clicked, "tool-30")

  local pad, gap = 22, 18
  local cw = math.floor((gfx.w - pad * 2 - gap * 2) / 3)
  for c, col in ipairs(COLUMNS) do
    local x = pad + (c - 1) * (cw + gap)
    local y = 92
    gfx.setfont(1, "Arial", 16, string.byte("b"))
    UI.set_color(UI.colors.title)
    gfx.x, gfx.y = x, y
    gfx.drawstr(col.title)
    y = y + 28
    for _, entry in ipairs(col.items) do
      local rect = { x = x, y = y, w = cw, h = 34 }
      if UI.point_in_rect(gfx.mouse_x, gfx.mouse_y, rect.x, rect.y, rect.w, rect.h + 18) then hover_help = entry.help end
      if UI.draw_button(rect, entry.label, false, true, clicked, "play_select") then
        if launch(entry) then return end
      end
      gfx.setfont(1, "Arial", 13)
      UI.set_color(UI.colors.muted)
      gfx.x, gfx.y = x + 4, y + 37
      gfx.drawstr(UI.fit_text(entry.hint, cw - 8))
      y = y + 58
    end
  end

  -- spiegazione: quella del pulsante sotto il mouse, altrimenti i due mondi
  local box_y = gfx.h - 78
  UI.set_color(UI.colors.panel_border)
  gfx.line(pad, box_y - 10, gfx.w - pad, box_y - 10)
  gfx.setfont(1, "Arial", 14)
  UI.set_color(hover_help and UI.colors.text or UI.colors.muted)
  local text = hover_help or
    "Video (colonne 1-3): tempi della timeline, per sottotitoli e consegna.  Audio (Collega a un audio, SRT dall'audio): tempi del file, il testo segue i tagli."
  -- a capo semplice su due righe
  local words, line, lines = {}, "", {}
  for w in text:gmatch("%S+") do words[#words + 1] = w end
  for _, w in ipairs(words) do
    local try = line == "" and w or (line .. " " .. w)
    if gfx.measurestr(try) > gfx.w - pad * 2 and line ~= "" then lines[#lines + 1] = line; line = w else line = try end
  end
  if line ~= "" then lines[#lines + 1] = line end
  for i = 1, math.min(3, #lines) do
    gfx.x, gfx.y = pad, box_y + (i - 1) * 20
    gfx.drawstr(lines[i])
  end

  gfx.update()
  reaper.defer(loop)
end

loop()
