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

check("toolbar: assente", M.toolbar_state(nil, true, false) == "manca")
check("toolbar: senza catene", M.toolbar_state(8, false, false) == "manca")
check("toolbar: scritta, da riavviare", M.toolbar_state(8, true, true) == "riavvia")
check("toolbar: pronta", M.toolbar_state(8, true, false) == "ok")
check("versione dall'intestazione", M.header_version("-- @description X\n-- @version 2.2.0\n") == "2.2.0")

local set = { ["/Library/Frameworks/Python.framework/Versions/3.12/bin/python3"] = true, ["/opt/homebrew/bin/python3.11"] = true }
check("python: il piu' recente trovato", M.find_python(function(p) return set[p] end) == "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3")
check("python: nessuno", M.find_python(function() return false end) == nil)
local menu = "[Main toolbar]\nitem_0=40001\n\n[Floating toolbar 2]\nicon_0=ZP_tb_x.png\nitem_0=_RS1 A\n\n[Floating toolbar 8]\nicon_0=ZP_tb_y.png\nitem_0=_RS2 B\ntitle=ZP Studio Suite\n\n[Floating toolbar 9]\nitem_0=1\n"
check("toolbar ZP: vince quella col nome ZP Studio Suite", M.toolbar_slot(menu) == 8)
check("toolbar ZP: senza nome, la prima con icone ZP", M.toolbar_slot("[Floating toolbar 5]\nicon_0=ZP_tb_a.png\n") == 5)
check("toolbar ZP: nella principale", M.toolbar_slot("[Main toolbar]\nicon_3=ZP_tb_a.png\n") == "main")
check("toolbar ZP: assente", M.toolbar_slot("[Floating toolbar 1]\nitem_0=1\n") == nil)
check("da riavviare: file ancora quello scritto", M.toolbar_pending("8|10", "0123456789") == true)
check("da riavviare: REAPER ha riscritto il file", M.toolbar_pending("8|10", "0123456789ab") == false)
check("da riavviare: nessuna scrittura", M.toolbar_pending("", "x") == false)
-- marker degli item (Mouse Modifiers, contesto Media item take marker)
local function G(t) return function(f) return t[f] end end
check("marker: comandi di serie", M.marker_state(G({ [0] = "1 m", [1] = "2 m" })) == "serie")
check("marker: protetti (No action letto come 0)", M.marker_state(G({ [0] = "0", [1] = "1 m" })) == "ok")
check("marker: impostazioni personali", M.marker_state(G({ [0] = "7 m", [1] = "2 m" })) == "altro")
check("marker: REAPER senza API", M.marker_state(nil) == "na")
local calls = {}
local function S(ctx, f, a) calls[#calls + 1] = ctx .. "|" .. tostring(f) .. "|" .. tostring(a) end
M.marker_protect(S)
check("marker: Proteggi", table.concat(calls, ";") == "MM_CTX_ITEMTAKEMARKER|0|0 m;MM_CTX_ITEMTAKEMARKER|1|1 m")
calls = {}; M.marker_reset(S)
check("marker: Ripristina standard = contesto di serie", table.concat(calls, ";") == "MM_CTX_ITEMTAKEMARKER|-1|-1")

-- Language pack di REAPER (nuove funzioni pure per 33 Benvenuto)
check("langpack clean: nome con estensione", M.langpack_clean_name("Italiano (ZP).ReaperLangPack") == "Italiano (ZP)")
check("langpack clean: maiuscole/minuscole", M.langpack_clean_name("Deutsch.reaperlangpack") == "Deutsch")
check("langpack clean: vuoto o nil", M.langpack_clean_name("") == nil and M.langpack_clean_name(nil) == nil)
check("langpack display: originale di default", M.langpack_display_name("") == "Originale (inglese)")
check("langpack display: con T_fn personalizzata", M.langpack_display_name(nil, function(s) return "Tradotto: " .. s end) == "Tradotto: Originale (inglese)")
check("langpack display: con nome pack", M.langpack_display_name("Italiano (ZP).ReaperLangPack") == "Italiano (ZP)")

local files = { "README.txt", "Italiano (ZP).ReaperLangPack", "deutsch.reaperlangpack", "note.doc" }
local filtered = M.filter_langpack_files(files)
check("filter langpack: solo estensioni giuste e ordine alfabetico", #filtered == 2 and filtered[1] == "deutsch.reaperlangpack" and filtered[2] == "Italiano (ZP).ReaperLangPack")

check("langpack state: invariato = ok", M.langpack_state("Italiano (ZP).ReaperLangPack", "Italiano (ZP).ReaperLangPack") == "ok")
check("langpack state: entrambi vuoti = ok", M.langpack_state("", "") == "ok")
check("langpack state: modificato = passo", M.langpack_state("Italiano (ZP).ReaperLangPack", "") == "passo")
check("langpack state: tornato a originale ma partito da pack = passo", M.langpack_state("", "Italiano (ZP).ReaperLangPack") == "passo")

local sh = M.restart_sh("/Applications/REAPER.app")
check("restart sh: pgrep e open inclusi", sh:find("pgrep -x 'REAPER'", 1, true) ~= nil and sh:find("open '/Applications/REAPER.app'", 1, true) ~= nil)
local ps1 = M.restart_ps1("C:\\REAPER\\reaper.exe")
check("restart ps1: Wait-Process e Start-Process inclusi", ps1:find("Wait-Process", 1, true) ~= nil and ps1:find("C:\\REAPER\\reaper.exe", 1, true) ~= nil)

if fails > 0 then print(fails .. " FALLITI") os.exit(1) end
print("TUTTI OK")
