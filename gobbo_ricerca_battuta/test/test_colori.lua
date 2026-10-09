-- Test della logica pura di ZP_Colori.lua (toolbar ZP Colori). Lancio dalla radice del repo.
local M = dofile("ZP Studio Suite/ZP_Colori.lua")
local fails = 0
local function check(n, c) print((c and "ok   " or "FAIL ") .. n); if not c then fails = fails + 1 end end
check("20 colori (16 + bianco, nero, grigio, rosso)", #M.PALETTE == 20 and M.color_file(18) == "ZP_Colori_18_Nero.lua")
check("nome file colore", M.color_file(7) == "ZP_Colori_07_Blu.lua" and M.color_file(1) == "ZP_Colori_01_Verde_lime.lua")
check("nome file fuori palette", M.color_file(21) == nil)
local k, a = M.parse_button("/x/Scripts/ZP Suite/ZP Studio Suite/colori/ZP_Colori_07_Blu.lua")
check("pulsante colore", k == "colore" and a == 7)
k, a = M.parse_button("C:\\R\\colori\\ZP_Colori_Modo_Traccia.lua")
check("pulsante modo (percorso Windows)", k == "modo" and a == "traccia")
check("pulsante togli", M.parse_button("colori/ZP_Colori_Togli.lua") == "togli")
check("nomi sconosciuti", M.parse_button("colori/ZP_Colori_99_X.lua") == nil and M.parse_button("colori/ZP_Colori_Modo_Boh.lua") == nil
  and M.parse_button("altro.lua") == nil)
check("modo di serie = item", M.valid_mode("") == "item" and M.valid_mode("tutto") == "tutto")
-- ogni script della cartella colori/ corrisponde a un pulsante, e ogni pulsante ha il suo script
local n = 0
for i = 1, #M.PALETTE do
  local f = io.open("ZP Studio Suite/colori/" .. M.color_file(i), "rb"); if f then f:close(); n = n + 1 end
end
for _, file in pairs(M.MODE_FILES) do
  local f = io.open("ZP Studio Suite/colori/" .. file, "rb"); if f then f:close(); n = n + 1 end
end
local f = io.open("ZP Studio Suite/colori/ZP_Colori_Togli.lua", "rb"); if f then f:close(); n = n + 1 end
check("24 script dei pulsanti presenti", n == 24)
local kb = table.concat({
  'SCR 4 0 RSa1 "Custom: ZP_Colori_Modo_Item.lua" "ZP Suite/ZP Studio Suite/colori/ZP_Colori_Modo_Item.lua"',
  'SCR 4 32060 RSb2 "Custom: ZP_Colori_Modo_Tutto.lua" "ZP Suite/ZP Studio Suite/colori/ZP_Colori_Modo_Tutto.lua"',
  'SCR 4 0 RSc3 "Custom: ZP_Colori_Modo_Tutto.lua" /abs/colori/ZP_Colori_Modo_Tutto.lua',
  'SCR 4 0 RSd4 "Custom: X_ZP_Colori_Modo_Traccia.lua" "a/X_ZP_Colori_Modo_Traccia.lua"',
}, "\n")
local ids = M.mode_ids_from_kb(kb)
check("id dei modi da reaper-kb.ini (solo sezione principale, nome esatto)",
  ids.item == "_RSa1" and ids.tutto == "_RSc3" and ids.traccia == nil)
-- toolbar nel 32
local T = dofile("ZP Studio Suite/32_Installa_Toolbar_ZP.lua")
local txt = T.menu_text(T.LAYOUT_COLORI, setmetatable({}, { __index = function() return "_RSx" end }), T.TITLE_COLORI, nil, 5)
local items = select(2, txt:gsub("\nitem_", ""))
check("toolbar ZP Colori: 3 modi + 20 colori + togli + 2 separatori", items == 26
  and txt:find("icon_0=ZP_tbC_Item.png", 1, true) and txt:find("icon_4=ZP_tbC_01.png", 1, true)
  and txt:find("icon_25=ZP_tbC_Togli.png", 1, true) and txt:match("title=ZP Colori\n$"))
for _, e in ipairs(T.LAYOUT_COLORI) do
  if e ~= "-" then
    local h = io.open("ZP Studio Suite/" .. e[1], "rb"); local ic = io.open("ZP Studio Suite/icons/" .. e[3], "rb")
    if not (h and ic) then check("file e icona di " .. e[1], false) end
    if h then h:close() end if ic then ic:close() end
  end
end
print(fails == 0 and "\nTUTTI OK" or ("\nFALLITI: " .. fails)); os.exit(fails == 0 and 0 or 1)
