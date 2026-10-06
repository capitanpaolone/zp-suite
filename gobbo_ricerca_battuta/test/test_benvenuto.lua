-- Test della logica pura di 33_Benvenuto_Controllo_Installazione.lua. Lancio dalla radice del repo.
local M = dofile("ZP Studio Suite/33_Benvenuto_Controllo_Installazione.lua")
local fails = 0
local function check(n, c) print((c and "ok   " or "FAIL ") .. n); if not c then fails = fails + 1 end end

check("porta web: HTTP in csurf_0", M.web_port("[REAPER]\ncsurf_0=HTTP 0 8080 '' 'index.html' 0 ''\ncsurf_1=MCU 0 9 0 0 1\ncsurf_cnt=2\n") == 8080)
check("porta web: oltre csurf_cnt non vale", M.web_port("csurf_0=MCU 0 9\ncsurf_3=HTTP 0 9000 ''\ncsurf_cnt=2\n") == nil)
check("porta web: niente HTTP", M.web_port("csurf_cnt=0\n") == nil)

check("azione di avvio SWS", M.sws_startup_action("[Misc]\nGlobalStartupAction=_RSabc\nX=1\n") == "_RSabc")
check("azione di avvio SWS vuota", M.sws_startup_action("[Misc]\nGlobalStartupAction=\n") == nil)
local kb = 'SCR 4 0 RSabc "Custom: ZP Harmonic Space Carver Cue Navigator.lua" "ZP Suite/ZP Harmonic Space Carver Cue Navigator.lua"\nSCR 4 0 RSdef "Custom: x.lua" /a/x.lua\n'
check("percorso da kb (tra virgolette)", M.kb_path(kb, "_RSabc") == "ZP Suite/ZP Harmonic Space Carver Cue Navigator.lua")
check("percorso da kb (senza virgolette)", M.kb_path(kb, "_RSdef") == "/a/x.lua")
check("percorso da kb: id sconosciuto", M.kb_path(kb, "_RSzzz") == nil)

local block = M.startup_block("/R/Scripts/ZP Suite/ZP Voce/ZP Harmonic Space Carver Cue Navigator.lua")
check("blocco di avvio compilabile", load(block) ~= nil)
local mine = "-- mio avvio\nreaper.ShowConsoleMsg('ciao')"
local t1 = M.put_startup_block(mine, block)
check("blocco aggiunto, il mio resta", t1:sub(1, #mine) == mine and M.has_startup_block(t1))
local t2 = M.put_startup_block(t1, M.startup_block("/altro.lua"))
local _, n = t2:gsub("ZP_BENVENUTO_HSC_INIZIO", "")
check("blocco rimpiazzato, non doppio", n == 1 and t2:find("/altro.lua", 1, true) and not t2:find("ZP Voce", 1, true))
check("file vuoto", M.put_startup_block(nil, block) == block .. "\n")

check("toolbar mai installata", M.toolbar_state(false, false, "") == "manca")
check("toolbar senza catene", M.toolbar_state(true, false, "") == "manca")
check("toolbar da importare", M.toolbar_state(true, true, "[Floating toolbar 1]\nitem_0=40001\n") == "importa")
check("toolbar importata", M.toolbar_state(true, true, "icon_0=ZP_tb_02_Gobbo.png\n") == "ok")
check("versione dall'intestazione", M.header_version("-- @description X\n-- @version 2.2.0\n") == "2.2.0")

if fails > 0 then print(fails .. " FALLITI") os.exit(1) end
print("TUTTI OK")
