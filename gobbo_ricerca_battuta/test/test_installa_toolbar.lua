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
-- toolbar 8 di Paolo: azioni native, icone di serie, riserva ZP
local lay = { { "a.lua", "A", "stock.png", "zp_a.png" }, { "b.lua", "B", "tomtjes.png", "zp_b.png" }, "-",
  { cmd = 50125, "Video", "toolbar_video_screen.png" } }
local has = function(n) return n == "stock.png" end
local t8 = M.menu_text(lay, { ["a.lua"] = "_RS1", ["b.lua"] = "_RS2" }, nil, has)
check("icona di serie tenuta, mancante -> riserva ZP, azione nativa col suo numero",
  t8:find("icon_0=stock.png", 1, true) and t8:find("icon_1=zp_b.png", 1, true)
  and t8:find("item_3=50125 Video", 1, true) and t8:find("icon_3=toolbar_video_screen.png", 1, true))
local full = M.menu_text(M.LAYOUT, setmetatable({}, { __index = function() return "_RSx" end }), nil, function(n) return M.STOCK[n] end)
local nitems = select(2, full:gsub("\nitem_", ""))
check("layout completo = toolbar 8 (23 voci con 6 separatori)", nitems == 23 and full:find("item_18=50125", 1, true)
  and full:find("item_19=42653", 1, true) and full:find("icon_1=ZP_tb_17_Regioni_Item.png", 1, true) and full:find("ZP_tb_23_Catena_FX.png", 1, true))
-- scrittura diretta in reaper-menu.ini
local ini = "[Main toolbar]\nitem_0=40001\n\n[Floating toolbar 1]\nitem_0=1 A\n\n[Floating toolbar 3]\nitem_0=2 B\ntitle=Mia\n\n[MIDI piano roll]\nitem_0=5\n"
check("slot: primo libero fra 1 e 16", M.pick_slot(ini) == 2)
check("slot: quella gia' chiamata ZP Studio Suite", M.pick_slot(ini .. "\n[Floating toolbar 9]\nicon_0=x.png\nitem_0=3 C\ntitle=ZP Studio Suite\n") == 9)
check("slot: file vuoto", M.pick_slot(nil) == 1)
-- icone B (2026-10-08): se ci sono si usano, altrimenti restano quelle di prima (anche per le azioni native)
local withB = M.menu_text(M.LAYOUT, setmetatable({}, { __index = function() return "_RSx" end }), nil, function() return true end)
check("icone B quando sono installate", withB:find("icon_0=ZP_tbB_18_Project_Viewer.png", 1, true)
  and withB:find("icon_18=ZP_tbB_Video.png", 1, true) and withB:find("icon_22=ZP_tbB_00_Help.png", 1, true)
  and withB:find("ZP_tb_25_SOLO_Recorder.png", 1, true))
check("senza icone B: azione nativa usa la sua riserva", full:find("icon_18=toolbar_video_screen.png", 1, true) ~= nil
  and full:find("icon_19=ZP_tb_Importa_SRT_1_video.png", 1, true) ~= nil)
local sec = "[Floating toolbar 2]\nitem_0=_RS1 X\ntitle=ZP Studio Suite\n"
local w1 = M.put_section(ini, sec)
check("sezione nuova in coda, il resto intatto", w1:sub(1, #ini) == ini and w1:find("[Floating toolbar 2]", 1, true))
local w2 = M.put_section(w1, "[Floating toolbar 2]\nitem_0=_RS9 Y\ntitle=ZP Studio Suite\n")
local _, k = w2:gsub("%[Floating toolbar 2%]", "")
check("sezione rimpiazzata, non doppia, le altre intatte", k == 1 and w2:find("_RS9 Y", 1, true) and not w2:find("_RS1 X", 1, true)
  and w2:find("[Floating toolbar 3]\nitem_0=2 B\ntitle=Mia", 1, true) and w2:find("[MIDI piano roll]\nitem_0=5", 1, true))
local mid = M.put_section(ini, "[Floating toolbar 1]\nitem_0=_RSz Z\n")
check("sezione in mezzo rimpiazzata, la successiva resta", mid:find("[Floating toolbar 1]\nitem_0=_RSz Z\n\n[Floating toolbar 3]", 1, true) ~= nil)
check("menu_text con numero di toolbar", M.menu_text({ { "a.lua", "A", "a.png" } }, { ["a.lua"] = "_RS1" }, nil, nil, 7):match("^%[Floating toolbar 7%]") ~= nil)
print(fails == 0 and "\nTUTTI OK" or ("\nFALLITI: " .. fails)); os.exit(fails == 0 and 0 or 1)
