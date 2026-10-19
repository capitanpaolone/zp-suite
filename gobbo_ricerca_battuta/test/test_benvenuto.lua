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
check("langpack display: nil = originale", M.langpack_display_name(nil) == "Originale (inglese)")
check("langpack display: riga vuota = chiedi all'avvio (REAPER chiede la lingua)", M.langpack_display_name("") == "Chiedi all'avvio")
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

-- Lingua di REAPER: scelta applicata al riavvio (2.6.3). SNM_SetStringConfigVar("langpack") dava false.
check("langpack display: <> = inglese di serie (Load always su English)", M.langpack_display_name("<>") == "Originale (inglese)")
check("app da eseguibile: portatile rinominata", M.app_from_exe("/Volumes/D/Reaper26_test/REAPER test.app/Contents/MacOS/REAPER\n") == "/Volumes/D/Reaper26_test/REAPER test.app")
check("app da eseguibile: standard", M.app_from_exe("/Applications/REAPER.app/Contents/MacOS/REAPER") == "/Applications/REAPER.app")
check("app da eseguibile: non un app", M.app_from_exe("/usr/bin/sh") == nil and M.app_from_exe(nil) == nil)
local shpid = M.restart_sh("/A/REAPER test.app", nil, nil, 4242)
check("restart sh con pid: attende solo quel pid", shpid:find("kill -0 4242", 1, true) ~= nil and shpid:find("pgrep", 1, true) == nil)
-- l'helper scrive langpack= in reaper.ini: prova vera della shell generata su un ini finto (sezione [reaper] minuscola)
local function run_helper(ini_text, value)
  local dir = os.tmpname(); os.remove(dir); os.execute("mkdir -p '" .. dir .. "'")
  local ini = dir .. "/reaper.ini"
  local f = io.open(ini, "wb"); f:write(ini_text); f:close()
  local sh = M.restart_sh(nil, { "zz_nessun_processo" }, { ini = ini, langpack = value })
  local g = io.open(dir .. "/r.sh", "wb"); g:write(sh); g:close()
  os.execute("sh '" .. dir .. "/r.sh' >/dev/null 2>&1")
  local h = io.open(ini, "rb"); local out = h and h:read("a") or ""; if h then h:close() end
  os.execute("rm -rf '" .. dir .. "'")
  return out
end
local base = "[actions]\nwnd_h=1\n[reaper]\nfoo=1\nlangpack=<>\nbar=2\n[REAPER-fxadd]\nx=3\n"
local o1 = run_helper(base, "Italiano (ZP).ReaperLangPack")
check("helper ini: sostituisce la riga e non aggiunge sezioni", o1 == "[actions]\nwnd_h=1\n[reaper]\nlangpack=Italiano (ZP).ReaperLangPack\nfoo=1\nbar=2\n[REAPER-fxadd]\nx=3\n")
check("helper ini: nessuna sezione [REAPER] in piu' (REAPER ignorerebbe l'originale)", select(2, o1:lower():gsub("\n%[reaper%]", "")) == 1)
local o2 = run_helper("[reaper]\nfoo=1\n", "<>")
check("helper ini: riga assente = inserita dopo [reaper]", o2 == "[reaper]\nlangpack=<>\nfoo=1\n")
local o3 = run_helper("[REAPER]\nfoo=1\n", "<>")
check("helper ini: anche [REAPER] maiuscolo, una sola sezione", o3 == "[REAPER]\nlangpack=<>\nfoo=1\n")
local o4 = run_helper("[reaper]\r\nfoo=1\r\n", "<>")
check("helper ini: sezione con CRLF riconosciuta", o4:find("langpack=<>", 1, true) ~= nil and select(2, o4:lower():gsub("%[reaper%]", "")) == 1)
check("helper ini: lingua con parentesi, & e spazi", run_helper("[reaper]\n", "A (b) & c.ReaperLangPack") == "[reaper]\nlangpack=A (b) & c.ReaperLangPack\n")
check("langpack valid: #NAME", M.langpack_valid("#NAME:Italiano (ZP)\n; x") == true)
check("langpack valid: con BOM", M.langpack_valid("\239\187\191#NAME:Deutsch") == true)
check("langpack valid: file qualunque = no", M.langpack_valid("ciao") == false and M.langpack_valid(nil) == false)
check("langpack basename: unix e windows", M.langpack_basename("/a/b/Italiano (ZP).ReaperLangPack") == "Italiano (ZP).ReaperLangPack" and M.langpack_basename("C:\\x\\y.ReaperLangPack") == "y.ReaperLangPack")
local shp = M.restart_sh("/Applications/REAPER.app", nil, { ini = "/Users/x/Library/Application Support/REAPER/reaper.ini", langpack = "Italiano (ZP).ReaperLangPack" }, 777)
check("restart sh con lingua: scrive langpack dopo la chiusura e prima di open",
  shp:find("kill -0 777", 1, true) < shp:find("ZP_LP=", 1, true) and shp:find("ZP_LP=", 1, true) < shp:find("open '/Applications", 1, true)
  and shp:find("'Italiano (ZP).ReaperLangPack'", 1, true) ~= nil and shp:find("reaper.ini.zp_bak", 1, true) ~= nil)
check("restart sh senza lingua: nessun awk", M.restart_sh("/Applications/REAPER.app"):find("awk", 1, true) == nil)

if fails > 0 then print(fails .. " FALLITI") os.exit(1) end
print("TUTTI OK")
