-- Test della logica pura di 34_ZP_Set_Comandi.lua. Lancio dalla radice del repo.
local M = dofile("ZP Studio Suite/34_ZP_Set_Comandi.lua")
local fails = 0
local function check(n, c) print((c and "ok   " or "FAIL ") .. n); if not c then fails = fails + 1 end end
local kb = table.concat({
  'ACT 1 0 "abc123" "Custom: due azioni" _RSs1 40001',
  'SCR 4 0 RSs1 "Custom: uno.lua" "ZP/uno.lua"',
  'SCR 4 0 RSs2 "Custom: due.lua" "ZP/due.lua"',
  'SCR 4 0 RSs3 "Custom: tre.lua" "ZP/tre.lua"',
  'KEY 1 65 _RSs2 0\t\t # Main : A : Custom: due.lua',
  'KEY 9 32 0 0\t\t # Main : Cmd+Space : DISABLED DEFAULT',
  'KEY 1 66 _abc123 0',
  'KEY 5 66 _OSARA_CURSORPOS 0',
}, "\n") .. "\n"
local i = M.info(kb)
check("info: 3 scorciatoie vere (DISABLED DEFAULT non conta), OSARA visto", i.keys == 3 and i.lines == 4 and i.osara)
check("info: set vuoto", M.info("").keys == 0 and not M.info("").osara)
local set = M.extract_set(kb)
check("extract: tiene KEY, ACT e solo gli script richiamati (s2 dal tasto, s1 dall'azione)",
  set:find("KEY 1 65 _RSs2 0", 1, true) and set:find('ACT 1 0 "abc123"', 1, true) and set:find("RSs1", 1, true)
  and set:find("RSs2 ", 1, true) and not set:find("RSs3", 1, true))
check("stessi tasti in ordine diverso = stesso set", M.same_keys(M.info(set), i))
check("tasti diversi = set diverso", not M.same_keys(M.info("KEY 1 65 _RSs2 0\n"), i))
-- un set che arriva da fuori, con uno script che qui non c'e'
local other = table.concat({
  'SCR 4 0 RSs1 "Custom: uno.lua" "ZP/uno.lua"',
  'SCR 4 0 RSnew "Custom: nuovo.lua" "X/nuovo.lua"',
  'KEY 1 70 _RSnew 0',
  'KEY 1 71 40044 0',
}, "\n")
local pl = M.payload(kb, other)
check("payload: solo lo script nuovo + le righe KEY del set", pl == 'SCR 4 0 RSnew "Custom: nuovo.lua" "X/nuovo.lua"\nKEY 1 70 _RSnew 0\nKEY 1 71 40044 0\n')
local after = M.apply(kb, pl)
local ai = M.info(after)
check("dopo il cambio: tasti = quelli del set", M.same_keys(ai, M.info(other)))
check("dopo il cambio: tutti gli script e le azioni di prima restano",
  after:find("RSs1", 1, true) and after:find("RSs2", 1, true) and after:find("RSs3", 1, true) and after:find("abc123", 1, true))
check("REAPER di serie: nessuna riga KEY, script intatti", M.info(M.apply(kb, M.payload(kb, ""))).lines == 0
  and M.apply(kb, M.payload(kb, "")):find("RSs3", 1, true))
check("ritorno al backup = tasti di prima", M.same_keys(M.info(M.apply(after, M.payload(after, set))), i))
check("CRLF", M.info(kb:gsub("\n", "\r\n")).keys == 3)
check("nome sicuro", M.safe_name(' Pro/Tools: "mio" ') == "Pro Tools mio" and M.safe_name("   ") == "")
-- lo script di sistema vero (sh), su file finti, con un processo da aspettare che non esiste
local dir = os.tmpname(); os.remove(dir); os.execute("mkdir -p '" .. dir .. "'")
local kbp, newp = dir .. "/reaper-kb.ini", dir .. "/Mio set's.txt"
local f = io.open(kbp, "wb"); f:write(kb); f:close()
f = io.open(newp, "wb"); f:write(pl); f:close()
local sh = dir .. "/cambio.sh"
f = io.open(sh, "wb"); f:write(M.waiter_sh(kbp, newp, nil, false, { "ZP_nessun_processo_xyz" })); f:close()
local ok = os.execute("/bin/sh '" .. sh .. "'")
f = io.open(kbp, "rb"); local res = f and f:read("a"); if f then f:close() end
check("sh: reaper-kb.ini cambiato come M.apply", ok and res == M.apply(kb, pl))
check("sh: in attesa -> .applicato, backup fatto", io.open(newp, "rb") == nil and io.open(newp .. ".applicato", "rb") ~= nil
  and io.popen("ls '" .. dir .. "' | grep -c ZP_backup_"):read("l") == "1")
os.execute("/bin/sh '" .. sh .. "'")
f = io.open(kbp, "rb"); local res2 = f:read("a"); f:close()
check("sh: senza file in attesa (annullato) non fa niente", res2 == res)
check("ps1: generato con i percorsi", M.waiter_ps1("C:\\R\\reaper-kb.ini", "C:\\R\\K\\x.txt", "C:\\R\\reaper.exe", true):find("Wait-Process -Name reaper", 1, true) ~= nil)
os.execute("rm -r '" .. dir .. "'")
-- elenco leggibile
check("nome tasto: Cmd+Shift+K (mac), Ctrl+Shift+K (win)", M.key_name(13, 75, true) == "Cmd+Shift+K" and M.key_name(13, 75, false) == "Ctrl+Shift+K")
check("nome tasto: carattere senza bit virtuale, F2, Spazio, rotella", M.key_name(0, 34, true) == '"' and M.key_name(1, 113, true) == "F2"
  and M.key_name(1, 32, true) == "Spazio" and M.key_name(255, 248, true) == "Rotella")
local li = M.listing(kb, function(cmd) return cmd == "_abc123" and "Custom: due azioni" or nil end, true)
check("elenco: dal commento tasto e azione, spenti in fondo", li[1].key == "A" and li[1].action == "Custom: due.lua"
  and li[#li].off and li[#li].key == "Cmd+Space")
local found = false
for _, r in ipairs(li) do if r.key == "B" and r.action == "Custom: due azioni" then found = true end end
check("elenco: senza commento -> nome da REAPER", found)
local lt = M.listing_text(li)
check("testo per l'AI: righe 'tasto -> azione' + spenti in una riga", lt:find("A -> Custom: due.lua\n", 1, true)
  and lt:find("1 default keys disabled", 1, true) and not lt:find("Cmd+Space", 1, true))
print(fails == 0 and "\nTUTTI OK" or ("\nFALLITI: " .. fails)); os.exit(fails == 0 and 0 or 1)
