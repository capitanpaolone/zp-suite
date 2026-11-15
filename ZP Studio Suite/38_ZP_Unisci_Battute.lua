-- @noindex

-- ZP Studio Suite: UNISCI BATTUTE
-- Unisce le battute di testo selezionate (stessa traccia) nella prima: i testi in fila,
-- la durata fino alla fine dell'ultima. Le altre vengono tolte. Un solo passo di Undo.

local SCRIPT_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "")
local ZP_TESTO = dofile(SCRIPT_DIR .. "ZP_Testo_Copione.lua")

local items = {}
for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
  items[#items + 1] = reaper.GetSelectedMediaItem(0, i)
end

local kept, info = ZP_TESTO.merge_text_items(reaper, items, function(item, text)
  ZP_TESTO.name_text_item(reaper, item, text)
end)
if not kept then
  reaper.ShowMessageBox(info .. "\n\nSeleziona in timeline le battute da unire e rilancia.", "ZP Studio Suite - Unisci battute", 0)
end
