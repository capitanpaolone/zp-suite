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
-- js_ReaScriptAPI, OSARA, interfaccia web di REAPER (SOLO Web).
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
function M.toolbar_state(menu_file, chains_ok, reaper_menu)
  if not menu_file or not chains_ok then return "manca" end
  if (reaper_menu or ""):find("ZP_tb_", 1, true) then return "ok" end
  return "importa"
end

function M.header_version(text)
  return (text or ""):match("@version%s+([%w%.%-]+)")
end

if not reaper then return M end

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

local TITLE = "ZP Studio Suite - Benvenuto"
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

-- I pezzi -----------------------------------------------------------------------
-- stato: "ok" pronto, "fare" da sistemare, "manca" facoltativo assente, "na" non serve qui
local function check_all()
  local out = {}
  local kb = read(P(resource, "reaper-kb.ini")) or ""

  -- 1 toolbar ed effetti
  local chains = exists(P(resource, "FXChains", "ZP Bus VoiceChain.RfxChain")) and exists(P(resource, "FXChains", "ZP MasterChain.RfxChain"))
  local tb = M.toolbar_state(exists(P(resource, "MenuSets", "ZP_StudioSuite.ReaperMenu")), chains, read(P(resource, "reaper-menu.ini")))
  out[#out + 1] = {
    title = "Toolbar ed effetti",
    state = tb == "ok" and "ok" or "fare",
    line = tb == "ok" and "Toolbar ZP importata; catene di effetti e preset al loro posto."
      or tb == "importa" and "File della toolbar pronto: va importata. Tasto destro su una toolbar > Customize toolbar > Import > ZP_StudioSuite.ReaperMenu."
      or "Da installare: pulsanti ZP, catene di effetti del SOLO Recorder e preset del Chain Builder.",
    buttons = {
      { "Installa", function() if run_script(P(here, "32_Installa_Toolbar_ZP.lua")) then speak("Toolbar ed effetti: installazione avviata.") end end },
      { "Come si fa", function() UI.open_help("tool-32") end },
    },
  }

  -- 2 Cue Navigator del Carver
  local hp = helper_path()
  if not hp then
    out[#out + 1] = { title = "Cue Navigator (Harmonic Space Carver)", state = "na",
      line = "Non serve: il Harmonic Space Carver non e' installato (pacchetto ZP Voce).", buttons = {} }
  else
    local running = reaper.GetExtState("ZP_HSC", "owner") ~= ""
    local su = read(P(resource, "Scripts", "__startup.lua"))
    local at_start = M.has_startup_block(su)
    local sws_path = M.kb_path(kb, M.sws_startup_action(read(P(resource, "S&M.ini"))))
    if sws_path and sws_path:find("Cue Navigator", 1, true) then at_start = true end
    out[#out + 1] = {
      title = "Cue Navigator (Harmonic Space Carver)",
      state = (running and at_start) and "ok" or "fare",
      line = (running and at_start) and "Acceso, e parte da solo a ogni apertura di REAPER."
        or at_start and "Parte a ogni apertura di REAPER, ma adesso e' spento: avvialo ora."
        or running and "Acceso adesso, ma alla prossima apertura di REAPER non ripartira': mettilo all'avvio."
        or "Collega i Carver a REAPER (cue, marker #HSC, routing). Deve partire a ogni apertura di REAPER.",
      buttons = {
        { "Avvia ora", function() if run_script(hp) then speak("Cue Navigator avviato.") end end, enabled = not running },
        { "A ogni apertura", function()
            local f = P(resource, "Scripts", "__startup.lua")
            if write(f, M.put_startup_block(read(f), M.startup_block(hp))) then
              speak("Il Cue Navigator partira' a ogni apertura di REAPER (Scripts/__startup.lua).")
            else speak("Non riesco a scrivere Scripts/__startup.lua.") end
          end, enabled = not at_start },
      },
    }
  end

  -- 3 ZP Speech
  if not IS_MAC then
    out[#out + 1] = { title = "ZP Speech (Trascrivi)", state = "na", line = "Solo su Mac. Altrove crea l'SRT con il tuo whisper e parti da Abbina.", buttons = {} }
  else
    local home = os.getenv("HOME") or ""
    local ready = exists(home .. "/Library/Application Support/ZP/runtimes/speech/bin/zp-speech")
    out[#out + 1] = {
      title = "ZP Speech (Trascrivi)",
      state = ready and "ok" or "manca",
      line = ready and "Installato: 29 Trascrivi crea l'SRT dal WAV con whisper."
        or "Facoltativo: serve solo a Trascrivi (29). Si installa a parte, con lo script install_macos.sh.",
      buttons = ready and {} or {
        { "Come si installa", function() UI.open_url("https://github.com/capitanpaolone/zp-suite/tree/master/speech-engine") end },
      },
    }
  end

  -- 4 SWS
  local sws = reaper.CF_GetSWSVersion and reaper.CF_GetSWSVersion() or nil
  out[#out + 1] = {
    title = "SWS",
    state = sws and "ok" or "manca",
    line = sws and ("Installata (" .. sws .. ").")
      or "Consigliata: copia-incolla nei pannelli, file che si aprono, secondi del pre-roll del SOLO.",
    buttons = sws and {} or { { "Sito SWS", function() UI.open_url("https://www.sws-extension.org") end } },
  }

  -- 5 js_ReaScriptAPI
  local js = reaper.JS_ReaScriptAPI_Version and reaper.JS_ReaScriptAPI_Version() or nil
  out[#out + 1] = {
    title = "js_ReaScriptAPI",
    state = js and "ok" or "manca",
    line = js and ("Installata (" .. tostring(js) .. ").")
      or "Consigliata: scelta cartelle di sistema, finestra del SOLO sempre sopra. Si installa da ReaPack.",
    buttons = js and {} or { { "Apri ReaPack", function()
        local id = reaper.NamedCommandLookup("_REAPACK_BROWSE")
        if id and id ~= 0 then reaper.Main_OnCommand(id, 0); speak("Cerca js_ReaScriptAPI e installalo.")
        else speak("Apri Extensions > ReaPack > Browse packages e cerca js_ReaScriptAPI.") end
      end } },
  }

  -- 6 OSARA
  local osara = reaper.osara_outputMessage ~= nil
  out[#out + 1] = {
    title = "OSARA",
    state = osara and "ok" or "manca",
    line = osara and "Installata: le battute si leggono con lo screen reader."
      or "Solo per chi usa uno screen reader: lettura delle battute (09-12).",
    buttons = osara and {} or { { "Sito OSARA", function() UI.open_url("https://osara.reaperaccessibility.com") end } },
  }

  -- 7 Interfaccia web
  local port = M.web_port(read(reaper.get_ini_file()))
  out[#out + 1] = {
    title = "Interfaccia web di REAPER",
    state = port and "ok" or "manca",
    line = port and ("Accesa sulla porta " .. port .. ": il globo del SOLO apre la versione web.")
      or "Serve solo al SOLO Web (browser, iPad). Preferences > Control/OSC/web > Add > Web browser interface.",
    buttons = port and {} or { { "Preferenze", function() reaper.Main_OnCommand(40016, 0) end } },
  }
  return out
end

-- Disegno ---------------------------------------------------------------------
local LED = { ok = {0.25, 0.85, 0.42}, fare = {0.95, 0.30, 0.22}, manca = {0.55, 0.60, 0.70}, na = {0.32, 0.34, 0.40} }
local WORD = { ok = "pronto", fare = "da fare", manca = "facoltativo", na = "non serve" }
local mouse_was_down = false

local function draw()
  UI.fill_background()
  local clicked = (gfx.mouse_cap & 1) == 0 and mouse_was_down
  local da_fare = 0
  for _, r in ipairs(rows) do if r.state == "fare" then da_fare = da_fare + 1 end end

  gfx.setfont(1, "Arial", 22, "b"); gfx.set(0.95, 0.95, 0.97, 1)
  gfx.x, gfx.y = 20, 16
  gfx.drawstr("Benvenuto nella ZP Studio Suite")
  gfx.setfont(1, "Arial", 14)
  if da_fare == 0 then gfx.set(0.45, 0.90, 0.55, 1) else gfx.set(1, 0.72, 0.40, 1) end
  gfx.x, gfx.y = 20, 46
  local ver = M.header_version(read(P(here, "00_Apri_Help_ZP_Studio_Suite.lua"))) or "?"
  gfx.drawstr((da_fare == 0 and "Tutto pronto." or (da_fare == 1 and "Una cosa da fare." or (da_fare .. " cose da fare."))) ..
    "  Versione " .. ver .. ". Lo stato si aggiorna da solo.")

  local y, bw = 76, 150
  for _, r in ipairs(rows) do
    local h = 70
    local panel = UI.draw_panel({ x = 12, y = y, w = gfx.w - 24, h = h }, nil)
    local c = LED[r.state]
    gfx.set(c[1], c[2], c[3], 1); gfx.circle(30, y + 22, 7, true, true)
    gfx.setfont(1, "Arial", 15, "b"); gfx.set(0.95, 0.95, 0.97, 1)
    gfx.x, gfx.y = 46, y + 13
    gfx.drawstr(r.title)
    local tw = gfx.measurestr(r.title)
    gfx.setfont(1, "Arial", 12, "b"); gfx.set(c[1], c[2], c[3], 1)
    gfx.x, gfx.y = 46 + tw + 10, y + 16
    gfx.drawstr(WORD[r.state])
    local text_w = gfx.w - 24 - 46 - (#r.buttons > 0 and (#r.buttons * (bw + 8)) or 0) - 10
    gfx.setfont(1, "Arial", 13); gfx.set(0.78, 0.80, 0.86, 1)
    for i, l in ipairs(UI.wrap_text(r.line, text_w)) do
      if i > 2 then break end
      gfx.x, gfx.y = 46, y + 34 + (i - 1) * 16
      gfx.drawstr(l)
    end
    local bx = gfx.w - 24 - #r.buttons * (bw + 8) + 4
    for _, b in ipairs(r.buttons) do
      if UI.draw_button({ x = bx, y = y + 20, w = bw, h = 30 }, b[1], false, b.enabled ~= false, clicked, b[1] == "Installa" and "save" or "tab") then
        b[2](); last_check = 0
      end
      bx = bx + bw + 8
    end
    y = y + h + 8
    local _ = panel
  end

  local by = gfx.h - 46
  if UI.draw_button({ x = 20, y = by, w = 130, h = 30 }, "Apri l'help", false, true, clicked, "tab") then UI.open_help("installazione") end
  if UI.draw_button({ x = gfx.w - 120, y = by, w = 100, h = 30 }, "Chiudi", false, true, clicked, "tab") then return false end
  gfx.setfont(1, "Arial", 13); gfx.set(0.70, 0.78, 0.92, 1)
  gfx.x, gfx.y = 164, by + 8
  gfx.drawstr(UI.fit_text(status ~= "" and status or "Riapri questo pannello quando vuoi: Action List > 33 Benvenuto.", gfx.w - 164 - 140))
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

gfx.init(TITLE, 820, 76 + 7 * 78 + 60, 0, 160, 120)
rows = check_all(); last_check = reaper.time_precise()
local fare = 0
for _, r in ipairs(rows) do if r.state == "fare" then fare = fare + 1 end end
speak(fare == 0 and "ZP Studio Suite: tutto pronto." or ("ZP Studio Suite: " .. fare .. " cose da fare. Ogni riga ha il suo pulsante."))
loop()
