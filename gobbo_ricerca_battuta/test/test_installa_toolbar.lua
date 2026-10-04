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
print(fails == 0 and "\nTUTTI OK" or ("\nFALLITI: " .. fails)); os.exit(fails == 0 and 0 or 1)
