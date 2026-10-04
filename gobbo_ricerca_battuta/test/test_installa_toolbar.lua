-- Test della logica pura di 32_Installa_Toolbar_ZP.lua. Lancio dalla radice del repo.
local M = dofile("ZP Studio Suite/32_Installa_Toolbar_ZP.lua")
local fails = 0
local function check(n, c) print((c and "ok   " or "FAIL ") .. n); if not c then fails = fails + 1 end end
local kb = table.concat({
  'SCR 4 0 RSaaa "Custom: 02_Gobbo_Verticale.lua" "ZP Suite/ZP Studio Suite/02_Gobbo_Verticale.lua"',
  'SCR 4 0 RSbbb "Custom: 02_Gobbo_Verticale.lua" "ZP Suite/ZP Studio Suite/02_Gobbo_Verticale.lua"',
  'SCR 4 32060 RSccc "Custom: 03_Gobbo_Orizzontale.lua" "ZP Suite/ZP Studio Suite/03_Gobbo_Orizzontale.lua"',
  'SCR 260 0 RSddd "Custom: x.lua" /Users/p/altro/x.lua',
  'KEY 1 65 _RSaaa 0',
}, "\n")
local ids = M.ids_from_kb(kb, "/Users/p/Library/Application Support/REAPER/Scripts")
check("relativo -> assoluto, primo vince", ids["/users/p/library/application support/reaper/scripts/zp suite/zp studio suite/02_gobbo_verticale.lua"] == "_RSaaa")
check("sezione diversa da 0 ignorata", ids["/users/p/library/application support/reaper/scripts/zp suite/zp studio suite/03_gobbo_orizzontale.lua"] == nil)
check("percorso assoluto senza virgolette", ids["/users/p/altro/x.lua"] == "_RSddd")
local layout = { { "a.lua", "A", "a.png" }, "-", "-", { "manca.lua", "M", "m.png" }, "-", { "b.lua", "B", "b.png" }, "-" }
local t = M.menu_text(layout, { ["a.lua"] = "_RS1", ["b.lua"] = "_RS2" })
check("pulsante mancante saltato, separatori non doppi, niente separatore finale",
  t == "[Floating toolbar 32]\nicon_0=a.png\nicon_2=b.png\nitem_0=_RS1 A\nitem_1=-1\nitem_2=_RS2 B\ntitle=ZP Studio Suite\n")
-- preset: unione per nome
local pkg = "[General]\nNbPresets=1\n\n[Preset0]\nData=AA\nLen=1\nName=Flat -19\n\n"
local m, added = M.merge_presets(nil, pkg)
check("preset: file utente assente -> file del pacchetto", m == pkg and added[1] == "Flat -19")
local user = "[General]\nNbPresets=2\n\n[Preset0]\nData=01\nLen=1\nName=Mio\n\n[Preset1]\nData=02\nLen=1\nName=Altro\n\n"
m, added = M.merge_presets(user, pkg)
local e = M.preset_entries(m)
check("preset: aggiunto in coda come Preset2, NbPresets=3, i miei intatti",
  #added == 1 and m:match("NbPresets=3") and #e == 3 and e[1].name == "Mio" and e[2].name == "Altro"
  and e[3].name == "Flat -19" and m:match("%[Preset2%]\nData=AA\nLen=1\nName=Flat %-19"))
local again, added2 = M.merge_presets(m, pkg)
check("preset: rilancio -> niente doppioni", again == m and #added2 == 0)
local mine = "[General]\nNbPresets=1\n\n[Preset0]\nData=FF\nLen=1\nName=Flat -19\n\n"
local kept, added3 = M.merge_presets(mine, pkg)
check("preset: stesso nome gia' mio -> non toccato", kept == mine and #added3 == 0)
local crlf = M.merge_presets("[General]\r\nNbPresets=0\r\n", pkg)
check("preset: CRLF e file senza preset", #M.preset_entries(crlf) == 1 and crlf:match("NbPresets=1"))
-- i file veri del pacchetto si leggono
for _, f in ipairs(M.PRESETS) do
  local h = io.open("ZP Studio Suite/presets/" .. f, "rb"); local t = h and h:read("a"); if h then h:close() end
  local en = M.preset_entries(t or "")
  check("pacchetto " .. f, #en == 1 and en[1].name ~= nil)
end
print(fails == 0 and "\nTUTTI OK" or ("\nFALLITI: " .. fails)); os.exit(fails == 0 and 0 or 1)
