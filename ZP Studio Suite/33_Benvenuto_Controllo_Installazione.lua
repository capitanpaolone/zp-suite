-- @noindex

-- ZP Studio Suite for REAPER
-- 33 Benvenuto: controllo installazione. Un pannello che dice quali pezzi della suite sono
-- pronti e quali no, e per ognuno ha il pulsante che lo mette a posto.
--
-- Compare da solo una volta, la prima volta che si usa uno strumento ZP dopo l'installazione
-- (ZP_UI lo lancia: ReaPack non puo' eseguire niente subito dopo aver installato). Poi si
-- riapre dall'Action List ("33 Benvenuto") o dall'help.
--
-- Pezzi controllati: toolbar ed effetti (32), Cue Navigator del Harmonic Space Carver
-- (deve partire a ogni apertura di REAPER), ZP Speech (Trascrivi, solo Mac), SWS,
-- js_ReaScriptAPI, OSARA, marker degli item protetti (Mouse Modifiers), interfaccia web di REAPER (SOLO Web).
-- Lo stato si ricontrolla da solo ogni secondo: fai una cosa e la spia cambia.

local M = {}

-- Parte pura (testata da gobbo_ricerca_battuta/test/test_benvenuto.lua) ----------------

-- Porta dell'interfaccia web: in reaper.ini, csurf_N=HTTP flag porta ... con N < csurf_cnt.
function M.web_port(ini)
  ini = "\n" .. (ini or "")
  local cnt = tonumber(ini:match("\ncsurf_cnt=(%d+)")) or 0
  for i = 0, cnt - 1 do
    local port = ini:match("\ncsurf_" .. i .. "=HTTP %-?%d+ (%d+)")
    if port then return tonumber(port) end
  end
  return nil
end

-- Azione di avvio di SWS (S&M.ini, [Misc] GlobalStartupAction=...).
function M.sws_startup_action(sm)
  local v = ("\n" .. (sm or "")):match("\nGlobalStartupAction=([^\r\n]+)")
  return v and v ~= "" and v or nil
end

-- Percorso dello script registrato con quell'identificativo (_RSxxx) in reaper-kb.ini.
function M.kb_path(kb, id)
  if not id then return nil end
  id = id:gsub("^_", "")
  for line in ((kb or "") .. "\n"):gmatch("([^\n]*)\n") do
    local rid, rest = line:match("^SCR %d+ %d+ (%S+) (.*)$")
    if rid == id then
      local path = rest:match('^".-" "(.-)"%s*$') or rest:match('^".-" (%S+)%s*$')
      return path
    end
  end
  return nil
end

M.START_BEGIN = "-- ZP_BENVENUTO_HSC_INIZIO"
M.START_END = "-- ZP_BENVENUTO_HSC_FINE"

-- Blocco di __startup.lua che avvia il Cue Navigator all'apertura di REAPER (senza SWS).
function M.startup_block(helper_path)
  return table.concat({
    M.START_BEGIN .. " (ZP Studio Suite, 33 Benvenuto: avvia il Cue Navigator del Harmonic Space Carver)",
    "do",
    "  local p = " .. string.format("%q", helper_path),
    "  local f = io.open(p, \"r\")",
    "  if f then",
    "    f:close()",
    "    local id = reaper.AddRemoveReaScript(true, 0, p, true)",
    "    if id and id ~= 0 then reaper.Main_OnCommand(id, 0) end",
    "  end",
    "end",
    M.START_END,
  }, "\n")
end

function M.has_startup_block(text)
  return (text or ""):find(M.START_BEGIN, 1, true) ~= nil
end

-- Mette (o rimpiazza) il blocco ZP in __startup.lua, lasciando intatto il resto.
function M.put_startup_block(text, block)
  text = text or ""
  local a = text:find(M.START_BEGIN, 1, true)
  if a then
    local _, b = text:find(M.START_END, a, true)
    if b then return text:sub(1, a - 1) .. block .. text:sub(b + 1) end
  end
  if text ~= "" and not text:match("\n$") then text = text .. "\n" end
  return text .. block .. "\n"
end

-- Toolbar: "ok" importata, "importa" file pronto ma non importata, "manca" mai installata.
-- Toolbar: "manca" (da installare), "riavvia" (scritta dal 32 in reaper-menu.ini, REAPER deve
-- ripartire per caricarla), "ok". slot = toolbar_slot; pending = scritta in questa sessione.
-- La toolbar scritta dal 32 aspetta un riavvio solo se reaper-menu.ini e' ancora quello scritto
-- (flag "slot|lunghezza"): se REAPER l'ha riscritto, la toolbar e' gia' caricata.
function M.toolbar_pending(flag, menu_ini)
  local len = tonumber((flag or ""):match("|(%d+)$"))
  return len ~= nil and len == #(menu_ini or "")
end

function M.toolbar_state(slot, chains_ok, pending)
  if not slot or not chains_ok then return "manca" end
  if pending then return "riavvia" end
  return "ok"
end

-- reaper-menu.ini sezione per sezione, riga per riga: { name = "Floating toolbar 8", lines = {...} }.
-- (Un pattern su tutto il testo saltava una sezione si' e una no: la riga vuota fra due sezioni.)
function M.menu_sections(menu)
  local out, cur = {}, nil
  for line in tostring(menu or ""):gsub("\r", ""):gmatch("[^\n]+") do
    local name = line:match("^%[(.-)%]%s*$")
    if name then cur = { name = name, lines = {} }; out[#out + 1] = cur
    elseif cur then cur.lines[#cur.lines + 1] = line end
  end
  return out
end

-- In quale toolbar sta una toolbar ZP (reaper-menu.ini): numero della Floating toolbar, "main" per la
-- toolbar principale, nil se non c'e'. Vince quella che ha il titolo; senza titolo (di serie
-- "ZP Studio Suite") vale la prima che usa icone ZP (ZP_tb_, ZP_tbB_), mai quella dei colori.
function M.toolbar_slot(menu, title)
  title = title or "ZP Studio Suite"
  local best
  for _, sec in ipairs(M.menu_sections(menu)) do
    local slot = tonumber(sec.name:match("^Floating toolbar (%d+)$")) or (sec.name == "Main toolbar" and "main") or nil
    if slot then
      local zp, colori = false, false
      for _, l in ipairs(sec.lines) do
        if l == "title=" .. title then return slot end
        if l:match("^icon_%d+=ZP_tb[B_]") then zp = true end
        if l == "title=ZP Colori" then colori = true end
      end
      if zp and not colori and title == "ZP Studio Suite" then best = best or slot end
    end
  end
  return best
end

function M.header_version(text)
  return (text or ""):match("@version%s+([%w%.%-]+)")
end

-- Python 3.11+ fra i posti dove lo mettono python.org e Homebrew (exists e' passato da fuori).
function M.find_python(exists)
  for _, v in ipairs({ "3.14", "3.13", "3.12", "3.11" }) do
    for _, p in ipairs({ "/Library/Frameworks/Python.framework/Versions/" .. v .. "/bin/python3",
                         "/opt/homebrew/bin/python" .. v, "/usr/local/bin/python" .. v,
                         "/opt/homebrew/opt/python@" .. v .. "/bin/python" .. v }) do
      if exists(p) then return p end
    end
  end
end

-- Language pack di REAPER (pura)
function M.langpack_clean_name(filename)
  if not filename or filename == "" then return nil end
  return (filename:gsub("%.[Rr][Ee][Aa][Pp][Ee][Rr][Ll][Aa][Nn][Gg][Pp][Aa][Cc][Kk]$", ""))
end

function M.langpack_display_name(filename, T_fn)
  local T = T_fn or function(s) return s end
  local clean = M.langpack_clean_name(filename)
  if not clean or clean == "" then return T("Originale (inglese)") end
  return clean
end

function M.filter_langpack_files(files)
  local out = {}
  for _, f in ipairs(files or {}) do
    if f:match("%.[Rr][Ee][Aa][Pp][Ee][Rr][Ll][Aa][Nn][Gg][Pp][Aa][Cc][Kk]$") then
      out[#out + 1] = f
    end
  end
  table.sort(out, function(a, b) return a:lower() < b:lower() end)
  return out
end

function M.langpack_state(current_pack, initial_pack)
  local c = (current_pack or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local i = (initial_pack or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if c == i then return "ok" else return "passo" end
end

local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
function M.restart_sh(app, proc)
  local wait = {}
  for _, p in ipairs(proc or { "REAPER", "reaper" }) do wait[#wait + 1] = "pgrep -x " .. shq(p) .. " >/dev/null 2>&1" end
  return table.concat({
    "#!/bin/sh",
    "# ZP Studio Suite: aspetta la chiusura di REAPER e poi lo riapre.",
    "while " .. table.concat(wait, " || ") .. "; do sleep 1; done",
    "sleep 1",
    app and ("open " .. shq(app)) or "",
    "",
  }, "\n")
end

function M.restart_ps1(exe)
  local function psq(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end
  return table.concat({
    "# ZP Studio Suite: aspetta la chiusura di REAPER e poi lo riapre.",
    "Wait-Process -Name reaper -ErrorAction SilentlyContinue",
    "Start-Sleep -Seconds 1",
    exe and ("Start-Process " .. psq(exe)) or "",
    "",
  }, "\r\n")
end


-- Marker degli item (take marker): con i comandi di serie di REAPER trascinare sopra un marker lo
-- sposta, e chi voleva spostare o selezionare l'item si ritrova a muovere il marker. Protetti
-- (scelta di Paolo, 2026-10-07): trascinare senza tasti non fa niente sul marker (l'item resta
-- prendibile), Shift+trascina sposta il marker. Contesto "Media item take marker", left drag.
-- Codici di REAPER 7.82: "0 m" = No action, "1 m" = Move take marker, "2 m" = Move take marker
-- ignoring snap (Shift di serie). GetMouseModifier restituisce "0" per No action.
M.MARKER_CTX = "MM_CTX_ITEMTAKEMARKER"
M.MARKER_PROTECT = { { 0, "0 m" }, { 1, "1 m" } }     -- { tasti (0 nessuno, 1 Shift), azione }
local function mm_norm(v)
  v = tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if v:match("^%-?%d+$") then v = v .. " m" end
  return v
end
-- Stato dai valori attuali (get(tasti) -> stringa di REAPER): "ok" protetti, "serie" comandi di
-- serie di REAPER, "altro" impostazioni personali, "na" REAPER senza GetMouseModifier.
function M.marker_state(get)
  if not get then return "na" end
  local d, sh = mm_norm(get(0)), mm_norm(get(1))
  if d == "0 m" and sh == "1 m" then return "ok" end
  if d == "1 m" and sh == "2 m" then return "serie" end
  return "altro"
end
-- Proteggi e Ripristina standard (set = reaper.SetMouseModifier).
function M.marker_protect(set)
  for _, e in ipairs(M.MARKER_PROTECT) do set(M.MARKER_CTX, e[1], e[2]) end
end
function M.marker_reset(set)
  set(M.MARKER_CTX, -1, -1)                 -- tutto il contesto torna come lo da' REAPER
end

if not reaper or ZP_BENVENUTO_LIB then return M end

---------------------------------------------------------------------------
-- PARTE REAPER
---------------------------------------------------------------------------

local sep = package.config:sub(1, 1)
local here = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or ".")
local resource = reaper.GetResourcePath()
-- il primo avvio e' fatto: va segnato PRIMA di caricare ZP_UI, che altrimenti lancerebbe
-- un secondo Benvenuto
reaper.SetExtState("ZP_STUDIO_SUITE", "benvenuto_visto", "1", true)
local ok_ui, UI = pcall(dofile, here .. sep .. "ZP_UI.lua")
if not ok_ui or not UI then reaper.MB("Manca ZP_UI.lua accanto a questo script: reinstalla la ZP Studio Suite da ReaPack.", "ZP Benvenuto", 0) return end

local T = UI.T or function(s) return s end
local TITLE = "ZP Studio Suite - " .. T("Benvenuto")
local HELPER_NAME = "ZP Harmonic Space Carver Cue Navigator.lua"
local IS_MAC = (reaper.GetOS() or ""):match("OSX") or (reaper.GetOS() or ""):match("macOS")

local function read(p) local f = io.open(p, "rb"); if not f then return nil end local d = f:read("a"); f:close(); return d end
local function exists(p) local f = io.open(p, "rb"); if f then f:close() return true end return false end
local function write(p, d) local f = io.open(p, "wb"); if not f then return false end f:write(d); f:close(); return true end
local function P(...) return table.concat({ ... }, sep) end

local status, last_check, rows = "", 0, {}

local function run_script(path)
  if not exists(path) then return false end
  local id = reaper.AddRemoveReaScript(true, 0, path, true)
  if not id or id == 0 then return false end
  reaper.Main_OnCommand(id, 0)
  return true
end

local function helper_path()
  for _, p in ipairs({ P(resource, "Scripts", "ZP Suite", "ZP Voce", HELPER_NAME), P(resource, "Scripts", "ZP Suite", HELPER_NAME) }) do
    if exists(p) then return p end
  end
  return nil
end

local function speak(t)
  status = t
  if reaper.osara_outputMessage then reaper.osara_outputMessage(t) end
end

-- ZP Speech: il Terminale scarica da GitHub solo speech-engine e lancia install_macos.sh.
local function install_speech()
  local cmd = os.tmpname() .. "_zp_speech.command"
  local body = table.concat({
    "#!/bin/bash",
    "echo 'ZP Speech: scarico l installatore da GitHub (capitanpaolone/zp-suite)...'",
    "T=$(mktemp -d)",
    "curl -fsSL https://codeload.github.com/capitanpaolone/zp-suite/tar.gz/refs/heads/master | tar -xz -C \"$T\" --strip-components=1 zp-suite-master/speech-engine || { echo 'Download non riuscito: controlla la connessione.'; read -n 1 -s -r -p 'Premi un tasto per chiudere.'; exit 1; }",
    "bash \"$T/speech-engine/install_macos.sh\" && echo 'ZP Speech pronto: torna in REAPER, la spia del Benvenuto diventa verde.' || echo 'Installazione non riuscita: leggi i messaggi qui sopra.'",
    "rm -rf \"$T\"",
    "echo",
    "read -n 1 -s -r -p 'Fatto. Premi un tasto per chiudere questa finestra.'",
  }, "\n") .. "\n"
  if not write(cmd, body) then speak("Non riesco a preparare l'installazione di ZP Speech."); return false end
  os.execute("chmod +x " .. string.format("%q", cmd) .. " && open " .. string.format("%q", cmd))
  return true
end

if _G.ZP_INITIAL_LANGPACK == nil then
  local ok_lp, cur = reaper.get_config_var_string("langpack")
  _G.ZP_INITIAL_LANGPACK = (ok_lp and cur) or ""
end

local function app_path()
  local exe = reaper.GetExePath() or ""
  local app = exe:match("^(.-%.app)")
  if app then return app end
  local f = io.open(exe .. "/REAPER.app/Contents/Info.plist", "rb")
  if f then f:close(); return exe .. "/REAPER.app" end
  return "/Applications/REAPER.app"
end

local function restart_reaper()
  local is_win = (reaper.GetOS() or ""):match("Win")
  if is_win then
    local ps = resource .. sep .. "ZP_Restart.ps1"
    write(ps, M.restart_ps1(reaper.GetExePath() .. sep .. "reaper.exe"))
    os.execute('start "" /B powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' .. ps .. '"')
  else
    local sh = resource .. sep .. "ZP_Restart.sh"
    write(sh, M.restart_sh(app_path()))
    os.execute("nohup /bin/sh " .. string.format("%q", sh) .. " >/dev/null 2>&1 &")
  end
  speak(T("Chiudo REAPER per applicare la nuova lingua..."))
  reaper.Main_OnCommand(40004, 0)
end

-- I pezzi -----------------------------------------------------------------------
-- stato: "ok" pronto, "fare" da sistemare, "manca" facoltativo assente, "na" non serve qui
local function check_all()
  local out = {}
  local kb = read(P(resource, "reaper-kb.ini")) or ""

  -- 0a Lingua della Suite: due pulsanti a vista Italiano | English
  local cur_suite_lang = UI.get_lingua()
  out[#out + 1] = {
    title = T("Lingua della Suite"),
    state = "ok",
    line = T("Finestre, messaggi e guide della ZP Studio Suite. Vale subito per le finestre che si aprono dopo."),
    buttons = {
      { "Italiano", function() UI.set_lingua("it"); rows = check_all() end, w = 84, active = (cur_suite_lang == "it") },
      { "English", function() UI.set_lingua("en"); rows = check_all() end, w = 84, active = (cur_suite_lang == "en") },
    },
  }

  -- 0b Lingua di REAPER: menu language pack
  local ok_cur, cur_pack = reaper.get_config_var_string("langpack")
  cur_pack = (ok_cur and cur_pack) or ""
  local has_sws = reaper.SNM_SetStringConfigVar ~= nil
  local lp_state = M.langpack_state(cur_pack, _G.ZP_INITIAL_LANGPACK)
  local display_lp = M.langpack_display_name(cur_pack, T)

  local r_buttons = {}
  if not has_sws then
    r_buttons[#r_buttons + 1] = { T("Preferenze"), function() reaper.Main_OnCommand(40016, 0) end, w = 110 }
  else
    local menu_btn_label = display_lp .. " ▾"
    r_buttons[#r_buttons + 1] = {
      menu_btn_label,
      function()
        local pack_dir = P(resource, "LangPack")
        local raw_files = {}
        local idx = 0
        while true do
          local f = reaper.EnumerateFiles(pack_dir, idx)
          if not f then break end
          raw_files[#raw_files + 1] = f
          idx = idx + 1
        end
        local packs = M.filter_langpack_files(raw_files)
        local menu_entries = {}
        local is_orig = (cur_pack == "")
        menu_entries[#menu_entries + 1] = (is_orig and "!" or "") .. T("Originale (inglese)")
        for _, p in ipairs(packs) do
          local is_sel = (cur_pack == p)
          menu_entries[#menu_entries + 1] = (is_sel and "!" or "") .. M.langpack_clean_name(p)
        end
        local sel = gfx.showmenu(table.concat(menu_entries, "|"))
        if sel == 1 then
          reaper.SNM_SetStringConfigVar("langpack", "")
          rows = check_all()
        elseif sel > 1 and packs[sel - 1] then
          reaper.SNM_SetStringConfigVar("langpack", packs[sel - 1])
          rows = check_all()
        end
      end,
      w = math.max(140, gfx.measurestr(menu_btn_label) + 24),
    }
    if lp_state == "passo" then
      r_buttons[#r_buttons + 1] = { T("Riavvia ora"), restart_reaper, w = 110 }
    end
  end

  out[#out + 1] = {
    title = T("Lingua di REAPER"),
    state = lp_state,
    line = not has_sws and T("Scegli il language pack in Preferences > General > Language pack.")
      or lp_state == "passo" and string.format(T("REAPER passa a %s al riavvio."), display_lp)
      or T("Menu e finestre di REAPER. Originale = inglese, come le guide ufficiali."),
    buttons = r_buttons,
  }

  -- 1 toolbar ed effetti: il 32 scrive la toolbar "ZP Studio Suite" in reaper-menu.ini; REAPER la

  -- carica al riavvio. La spia "toolbar_da_riavviare" e' non persistente: sparisce riavviando.
  local chains = exists(P(resource, "FXChains", "ZP Bus VoiceChain.RfxChain")) and exists(P(resource, "FXChains", "ZP MasterChain.RfxChain"))
  local menu_ini = read(P(resource, "reaper-menu.ini"))
  local slot = M.toolbar_slot(menu_ini)
  local pending = M.toolbar_pending(reaper.GetExtState("ZP_STUDIO_SUITE", "toolbar_da_riavviare"), menu_ini)
  local tb = M.toolbar_state(slot, chains, pending)
  local dove = type(slot) == "number" and ("Floating toolbar " .. slot) or slot == "main" and T("toolbar principale") or ""
  local reinstalla = { T("Reinstalla"), function() if run_script(P(here, "32_Installa_Toolbar_ZP.lua")) then speak(T("Toolbar ed effetti: installazione avviata.")) end end }
  out[#out + 1] = {
    title = T("Toolbar ed effetti"),
    state = tb == "ok" and "ok" or tb == "riavvia" and "passo" or "fare",
    line = tb == "ok" and string.format(T("Toolbar \"ZP Studio Suite\" nella %s (Switch toolbar o View > Toolbars); catene di effetti e preset al loro posto."), dove)
      or tb == "riavvia" and string.format(T("Scritta nella %s. Ultimo passo: chiudi e riapri REAPER. Fino ad allora non aprire Customize toolbars (la scrittura andrebbe persa)."), dove)
      or T("Da installare: toolbar \"ZP Studio Suite\" (pronta dopo un riavvio di REAPER), catene di effetti del SOLO Recorder e preset del Chain Builder."),
    buttons = tb == "ok" and {
      { T("Apri la toolbar"), function()
          if type(slot) == "number" and slot <= 16 then
            reaper.Main_OnCommand(41678 + slot, 0)   -- Toolbar: Open/close toolbar N (41679 = 1)
            speak(string.format(T("Toolbar ZP: Floating toolbar %s, aperta o chiusa."), tostring(slot)))
          elseif type(slot) == "number" then speak(string.format(T("La toolbar ZP e' la Floating toolbar %s: View > Toolbars."), tostring(slot)))
          else speak(T("La toolbar ZP e' nella toolbar principale.")) end
        end },
      reinstalla,
    } or tb == "riavvia" and { reinstalla } or {
      { T("Installa"), function() if run_script(P(here, "32_Installa_Toolbar_ZP.lua")) then speak(T("Toolbar ed effetti: installazione avviata.")) end end },
      { T("Come si fa"), function() UI.open_help("tool-32") end },
    },
  }

  -- 1b toolbar ZP Colori (facoltativa): senza, i colori stanno nella finestrella 35 (tavolozza)
  local cslot = M.toolbar_slot(menu_ini, "ZP Colori")
  local cwant = reaper.GetExtState("ZP_STUDIO_SUITE", "toolbar_colori") == "1"
  out[#out + 1] = {
    title = T("Toolbar ZP Colori (facoltativa)"),
    state = cslot and (pending and "passo" or "ok") or "manca",
    line = cslot and string.format(T("Nella Floating toolbar %s: modo Item/Traccia/Tutto, 20 colori, Togli."), tostring(cslot))
      or cwant and T("Chiesta: lancia Installa (32) e riavvia REAPER.")
      or T("Non serve per forza: i colori ci sono gia' nella finestrella ZP Colori (tavolozza nella toolbar ZP). Installala se vuoi i colori sempre a vista, per esempio accanto al trasporto."),
    buttons = cslot and {
      { T("Apri la toolbar"), function()
          if type(cslot) == "number" and cslot <= 16 then reaper.Main_OnCommand(41678 + cslot, 0) end
        end, enabled = type(cslot) == "number" and cslot <= 16 },
    } or {
      { T("Installa"), function()
          reaper.SetExtState("ZP_STUDIO_SUITE", "toolbar_colori", "1", true)
          if run_script(P(here, "32_Installa_Toolbar_ZP.lua")) then speak(T("Toolbar ZP Colori: installazione avviata.")) end
        end },
      { T("Come si usa"), function() UI.open_help("colori", "toolbar.html") end },
    },
  }

  -- 2 Cue Navigator del Carver
  local hp = helper_path()
  if not hp then
    out[#out + 1] = { title = T("Cue Navigator (Harmonic Space Carver)"), state = "na",
      line = T("Non serve: il Harmonic Space Carver non e' installato (pacchetto ZP Voce)."), buttons = {} }
  else
    local running = reaper.GetExtState("ZP_HSC", "owner") ~= ""
    local su = read(P(resource, "Scripts", "__startup.lua"))
    local at_start = M.has_startup_block(su)
    local sws_path = M.kb_path(kb, M.sws_startup_action(read(P(resource, "S&M.ini"))))
    if sws_path and sws_path:find("Cue Navigator", 1, true) then at_start = true end
    out[#out + 1] = {
      title = T("Cue Navigator (Harmonic Space Carver)"),
      state = (running and at_start) and "ok" or "fare",
      line = (running and at_start) and T("Acceso, e parte da solo a ogni apertura di REAPER.")
        or at_start and T("Parte a ogni apertura di REAPER, ma adesso e' spento: avvialo ora.")
        or running and T("Acceso adesso, ma alla prossima apertura di REAPER non ripartira': mettilo all'avvio.")
        or T("Serve all'Harmonic Space Carver per sincronizzare i cue con i marker e muovere la testina. 'Installa' lo aggiunge all'avvio di REAPER (Scripts/__startup.lua)."),
      buttons = {
        { T("Avvia ora"), function() if run_script(hp) then speak(T("Cue Navigator avviato.")) end end, enabled = not running },
        { T("A ogni apertura"), function()
            local f = P(resource, "Scripts", "__startup.lua")
            if write(f, M.put_startup_block(read(f), M.startup_block(hp))) then
              speak(T("Il Cue Navigator partira' a ogni apertura di REAPER (Scripts/__startup.lua)."))
            else speak(T("Non riesco a scrivere Scripts/__startup.lua.")) end
          end, enabled = not at_start },
      },
    }
  end

  -- 3 ZP Speech: un clic su Installa apre il Terminale, scarica da GitHub solo la cartella
  -- speech-engine e lancia il suo installatore (si vede tutto quello che fa).
  if not IS_MAC then
    out[#out + 1] = { title = T("ZP Speech (Trascrivi)"), state = "na", line = T("Solo su Mac. Altrove crea l'SRT con il tuo whisper e parti da Abbina."), buttons = {} }
  else
    local home = os.getenv("HOME") or ""
    local ready = exists(home .. "/Library/Application Support/ZP/runtimes/speech/bin/zp-speech")
    local mw = exists("/Applications/MacWhisper.app")
    local py = M.find_python(exists)
    local mancano = {}
    if not py then mancano[#mancano + 1] = "Python 3.11 o piu' recente (python.org)" end
    if not mw then mancano[#mancano + 1] = "MacWhisper (in Applicazioni)" end
    out[#out + 1] = {
      title = T("ZP Speech (Trascrivi)"),
      state = (ready and mw) and "ok" or "manca",
      line = (ready and mw) and T("Installato: 29 Trascrivi crea l'SRT dal WAV con whisper (MacWhisper).")
        or ready and T("Installato, ma per trascrivere serve MacWhisper in Applicazioni (aprilo una volta).")
        or (#mancano > 0 and string.format(T("Facoltativo, serve a Trascrivi (29). Prima di installarlo serve: %s."), table.concat(mancano, ", "))
          or T("Facoltativo, serve a Trascrivi (29). Installa: il Terminale scarica e installa tutto da solo.")),
      buttons = {
        { ready and T("Aggiorna") or T("Installa"), function() if install_speech() then speak(T("Si apre il Terminale: segui li' l'installazione di ZP Speech.")) end end,
          enabled = py ~= nil },
        { "Python", function() UI.open_url("https://www.python.org/downloads/macos/") end, hidden = py ~= nil },
        { "MacWhisper", function() UI.open_url("https://goodsnooze.gumroad.com/l/macwhisper") end, hidden = mw },
      },
    }
  end

  -- 4 SWS
  local sws = reaper.CF_GetSWSVersion and reaper.CF_GetSWSVersion() or nil
  out[#out + 1] = {
    title = "SWS",
    state = sws and "ok" or "manca",
    line = sws and string.format(T("Installata (%s)."), sws)
      or T("Consigliata: copia-incolla nei pannelli, file che si aprono, secondi del pre-roll del SOLO."),
    buttons = sws and {} or { { T("Sito SWS"), function() UI.open_url("https://www.sws-extension.org") end } },
  }

  -- 5 js_ReaScriptAPI
  local js = reaper.JS_ReaScriptAPI_Version and reaper.JS_ReaScriptAPI_Version() or nil
  out[#out + 1] = {
    title = "js_ReaScriptAPI",
    state = js and "ok" or "manca",
    line = js and string.format(T("Installata (%s)."), tostring(js))
      or T("Consigliata: scelta cartelle di sistema, finestra del SOLO sempre sopra. Si installa da ReaPack."),
    buttons = js and {} or { { T("Installa js_ReaScriptAPI"), function()
        local id = reaper.NamedCommandLookup("_REAPACK_BROWSE")
        if id and id ~= 0 then reaper.Main_OnCommand(id, 0); speak(T("Cerca js_ReaScriptAPI e installalo."))
        else speak(T("Apri Extensions > ReaPack > Browse packages e cerca js_ReaScriptAPI.")) end
      end } },
  }

  -- 6 OSARA
  local osara = reaper.osara_outputMessage ~= nil
  out[#out + 1] = {
    title = "OSARA",
    state = osara and "ok" or "manca",
    line = osara and T("Installata: le battute si leggono con lo screen reader.")
      or T("Solo per chi usa uno screen reader: lettura delle battute (09-12)."),
    buttons = osara and {} or { { T("Sito OSARA"), function() UI.open_url("https://osara.reaperaccessibility.com") end } },
  }

  -- 7 Marker degli item: non si spostano per sbaglio
  local get = reaper.GetMouseModifier and function(f) return reaper.GetMouseModifier(M.MARKER_CTX, f) end or nil
  local ms = M.marker_state(get)
  local protect = { T("Proteggi"), function()
      M.marker_protect(reaper.SetMouseModifier)
      speak(T("Marker degli item protetti: trascini l'item, Shift+trascina sposta il marker."))
    end }
  local reset = { T("Ripristina standard"), function()
      M.marker_reset(reaper.SetMouseModifier)
      speak(T("Marker degli item: comandi di serie di REAPER (trascinare sposta il marker)."))
    end }
  out[#out + 1] = {
    title = T("Marker degli item"),
    state = ms == "ok" and "ok" or ms == "na" and "na" or "passo",
    line = ms == "ok" and T("Protetti: trascinando sopra un marker prendi l'item; Shift+trascina sposta il marker, doppio clic lo modifica.")
      or ms == "serie" and T("Comandi di serie di REAPER: trascinare sopra un marker lo sposta invece dell'item. Proteggi: il marker si sposta solo con Shift+trascina.")
      or ms == "na" and T("Questa versione di REAPER non permette di cambiarlo da uno script (Preferences > Mouse Modifiers).")
      or T("Impostazioni tue in Mouse Modifiers > Media item take marker: non le tocco. Proteggi le sostituisce (marker solo con Shift+trascina)."),
    buttons = ms == "na" and {} or ms == "ok" and { reset } or ms == "serie" and { protect } or { protect, reset },
  }

  -- 8 Interfaccia web
  local port = M.web_port(read(reaper.get_ini_file()))
  out[#out + 1] = {
    title = T("Interfaccia web di REAPER"),
    state = port and "ok" or "manca",
    line = port and (T("Accesa sulla porta ") .. port .. T(": il globo del SOLO apre la versione web."))
      or T("Serve solo al SOLO Web (browser, iPad). Preferences > Control/OSC/web > Add > Web browser interface."),
    buttons = port and {} or { { T("Preferenze"), function() reaper.Main_OnCommand(40016, 0) end } },
  }
  return out
end

-- Disegno ---------------------------------------------------------------------
local LED = { ok = {0.25, 0.85, 0.42}, fare = {0.95, 0.30, 0.22}, passo = {0.98, 0.72, 0.20}, manca = {0.55, 0.60, 0.70}, na = {0.32, 0.34, 0.40} }
local WORD = { ok = "pronto", fare = "da fare", passo = "manca un passo", manca = "facoltativo", na = "non serve" }
local mouse_was_down = false
local scroll = 0          -- righe che scorrono quando la finestra e' bassa

local function draw()
  UI.fill_background()
  local clicked = (gfx.mouse_cap & 1) == 0 and mouse_was_down
  local da_fare = 0
  for _, r in ipairs(rows) do if r.state == "fare" or r.state == "passo" then da_fare = da_fare + 1 end end

  -- elenco delle righe: scorre fra top e bottom (rotella), il resto resta fermo
  local top, bottom = 76, gfx.h - 56
  local in_list = gfx.mouse_y >= top and gfx.mouse_y <= bottom
  if gfx.mouse_wheel ~= 0 then scroll = scroll - gfx.mouse_wheel / 4; gfx.mouse_wheel = 0 end
  local y, bw = top - scroll, 136
  local list_clicked = clicked and in_list
  for _, r in ipairs(rows) do
    local shown = {}
    for _, b in ipairs(r.buttons) do if not b.hidden then shown[#shown + 1] = b end end
    local total_btn_w = 0
    for _, b in ipairs(shown) do total_btn_w = total_btn_w + (b.w or bw) + 8 end
    local text_w = gfx.w - 24 - 46 - total_btn_w - 10
    gfx.setfont(1, "Arial", 13)
    local lines = UI.wrap_text(r.line, text_w)
    local h = math.max(70, 40 + math.min(3, #lines) * 16)
    local panel = UI.draw_panel({ x = 12, y = y, w = gfx.w - 24, h = h }, nil)
    local c = LED[r.state]
    gfx.set(c[1], c[2], c[3], 1); gfx.circle(30, y + 22, 7, true, true)
    gfx.setfont(1, "Arial", 15, "b"); gfx.set(0.95, 0.95, 0.97, 1)
    gfx.x, gfx.y = 46, y + 13
    gfx.drawstr(r.title)
    local tw = gfx.measurestr(r.title)
    gfx.setfont(1, "Arial", 12, "b"); gfx.set(c[1], c[2], c[3], 1)
    gfx.x, gfx.y = 46 + tw + 10, y + 16
    gfx.drawstr(T(WORD[r.state]))
    gfx.setfont(1, "Arial", 13); gfx.set(0.78, 0.80, 0.86, 1)
    for i, l in ipairs(lines) do
      if i > 3 then break end
      gfx.x, gfx.y = 46, y + 34 + (i - 1) * 16
      gfx.drawstr(l)
    end
    local bx = gfx.w - 24 - total_btn_w + 8
    for _, b in ipairs(shown) do
      local w_btn = b.w or bw
      local btn_style = (b[1] == T("Installa") and b.enabled ~= false) and "save"
        or (b[1] == T("Riavvia ora") and b.enabled ~= false) and "save"
        or "tab"
      if UI.draw_button({ x = bx, y = y + 20, w = w_btn, h = 30 }, b[1], b.active or false, b.enabled ~= false, list_clicked, btn_style) then
        b[2](); last_check = 0
      end
      bx = bx + w_btn + 8
    end
    y = y + h + 8
    local _ = panel
  end
  local total = y + scroll - top
  local max_scroll = math.max(0, total - (bottom - top))
  scroll = math.max(0, math.min(max_scroll, scroll))
  -- copre sopra e sotto quello che esce dall'elenco, poi titolo e barra in basso
  UI.set_color(UI.colors.bg)
  gfx.rect(0, 0, gfx.w, top - 4, true)
  gfx.rect(0, bottom, gfx.w, gfx.h - bottom, true)
  if max_scroll > 0 then
    local track = bottom - top
    local thumb = math.max(30, track * track / total)
    gfx.set(0.20, 0.20, 0.26, 1); gfx.rect(gfx.w - 9, top, 5, track, true)
    gfx.set(0.60, 0.62, 0.72, 1); gfx.rect(gfx.w - 9, top + (track - thumb) * scroll / max_scroll, 5, thumb, true)
  end
  gfx.setfont(1, "Arial", 22, "b"); gfx.set(0.95, 0.95, 0.97, 1)
  gfx.x, gfx.y = 20, 16
  gfx.drawstr(T("Benvenuto nella ZP Studio Suite"))
  -- firma in alto a destra: marchio + "Sviluppata su un'idea di Paolo Balestri · Lato Cardioide" (clic: sito)
  do
    local idea, lc = T("Sviluppata su un'idea di Paolo Balestri") .. " · ", "Lato Cardioide"
    gfx.setfont(1, "Arial", 13)
    local w = 21 + gfx.measurestr(idea .. lc)
    local cx, cy = gfx.w - 20 - w, 22
    gfx.setfont(1, "Arial", 22, "b")
    if cx > 20 + gfx.measurestr(T("Benvenuto nella ZP Studio Suite")) + 16 then
      UI.draw_logo(cx, cy - 1, 16)
      gfx.setfont(1, "Arial", 13)
      gfx.set(0.80, 0.82, 0.88, 1); gfx.x, gfx.y = cx + 21, cy; gfx.drawstr(idea)
      UI.set_color(UI.colors.gold); gfx.drawstr(lc)
      if clicked and UI.point_in_rect(gfx.mouse_x, gfx.mouse_y, cx, cy - 4, w, 22) then
        UI.open_url("https://latocardioide.it/strumenti/")
      end
    end
  end
  gfx.setfont(1, "Arial", 14)
  if da_fare == 0 then gfx.set(0.45, 0.90, 0.55, 1) else gfx.set(1, 0.72, 0.40, 1) end
  gfx.x, gfx.y = 20, 46
  local ver = M.header_version(read(P(here, "00_Apri_Help_ZP_Studio_Suite.lua"))) or "?"
  gfx.drawstr((da_fare == 0 and T("Tutto pronto.") or (da_fare == 1 and T("Una cosa da fare.") or (da_fare .. T(" cose da fare.")))) ..
    T("  Versione ") .. ver .. T(". Lo stato si aggiorna da solo.") .. (max_scroll > 0 and T("  Altre righe: rotella.") or ""))

  local by = gfx.h - 46
  if UI.draw_button({ x = 20, y = by, w = 130, h = 30 }, T("Apri l'help"), false, true, clicked, "tab") then UI.open_help("installazione") end

  if UI.draw_button({ x = gfx.w - 120, y = by, w = 100, h = 30 }, T("Chiudi"), false, true, clicked, "tab") then return false end
  gfx.setfont(1, "Arial", 13); gfx.set(0.70, 0.78, 0.92, 1)
  gfx.x, gfx.y = 164, by + 8
  gfx.drawstr(UI.fit_text(status ~= "" and status or T("Riapri questo pannello quando vuoi: Action List > 33 Benvenuto."), gfx.w - 120 - 164 - 20))
  mouse_was_down = (gfx.mouse_cap & 1) == 1
  gfx.update()
  return true
end

local function loop()
  local ch = gfx.getchar()
  if ch < 0 or ch == 27 then gfx.quit() return end
  if reaper.time_precise() - last_check > 1.0 then rows = check_all(); last_check = reaper.time_precise() end
  if not draw() then gfx.quit() return end
  reaper.defer(loop)
end

gfx.init(TITLE, 820, 76 + 11 * 78 + 60 + 34, 0, 160, 120)
rows = check_all(); last_check = reaper.time_precise()
local fare = 0
for _, r in ipairs(rows) do if r.state == "fare" or r.state == "passo" then fare = fare + 1 end end
speak(fare == 0 and T("ZP Studio Suite: tutto pronto.") or (T("ZP Studio Suite: ") .. fare .. T(" cose da fare. Ogni riga ha il suo pulsante.")))
loop()

