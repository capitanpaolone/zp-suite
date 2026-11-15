-- Unione di più battute di testo nella prima (ZP_Testo_Copione.merge_text_items).
local M = dofile('ZP Studio Suite/ZP_Testo_Copione.lua')
local function eq(a, b, label) if a ~= b then error('FAIL ' .. (label or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

local items, deleted, undone, blocks
local function reset()
  deleted, undone, blocks = {}, 0, 0
  items = {
    [1] = { track = 'T', takes = 0, D_POSITION = 10, D_LENGTH = 1, P_NOTES = 'io', ['P_EXT:RythmoBand_HIGHLIGHT'] = 'io' },
    [2] = { track = 'T', takes = 0, D_POSITION = 12, D_LENGTH = 1.5, P_NOTES = ' vado\r\n', ['P_EXT:ZP_GOBBO_ANCHORS'] = M.serialize_anchors({ { guid = '{A}', offset = 2 } }),
            ['P_EXT:RythmoBand_HIGHLIGHT'] = 'vado\nio', ['P_EXT:ZP_GOBBO_TIMING'] = '1;2', ['P_EXT:ZP_GOBBO_TIMING_TEXT'] = ' vado' },
    [3] = { track = 'T', takes = 0, D_POSITION = 14, D_LENGTH = 2, P_NOTES = 'Via di qui.' },
    [4] = { track = 'T', takes = 0, D_POSITION = 20, D_LENGTH = 1, P_NOTES = '' },
    [5] = { track = 'ALTRA', takes = 0, D_POSITION = 30, D_LENGTH = 1, P_NOTES = 'x' },
    [6] = { track = 'T', takes = 1, D_POSITION = 40, D_LENGTH = 1, P_NOTES = 'audio' },
    [7] = { track = 'T', takes = 0, D_POSITION = 50, D_LENGTH = 1, P_NOTES = 'sync', ['P_EXT:ZP_SYNC_KEY'] = 'k' },
  }
end
local fail_write
local api = {
  ValidatePtr2 = function(_, id) return items[id] ~= nil end,
  GetSetMediaItemInfo_String = function(id, key, value, set)
    if set then if not (fail_write and key == 'P_NOTES') then items[id][key] = value end end
    return true, items[id][key] or ''
  end,
  GetMediaItemInfo_Value = function(id, key) return items[id][key] or 0 end,
  SetMediaItemInfo_Value = function(id, key, value) items[id][key] = value end,
  GetMediaItemNumTakes = function(id) return items[id].takes end,
  GetMediaItem_Track = function(id) return items[id].track end,
  DeleteTrackMediaItem = function(track, id) assert(items[id].track == track); items[id] = nil; deleted[#deleted + 1] = id; return true end,
  SetMediaItemSelected = function(id, v) items[id].selected = v end,
  UpdateItemInProject = function() end, UpdateArrange = function() end,
  Undo_BeginBlock = function() blocks = blocks + 1 end, Undo_EndBlock = function() end,
  Undo_DoUndo2 = function() undone = undone + 1 end,
}
local function name_item(id, text) items[id].P_NAME = text end

-- Tre pezzi di una battuta, dati in ordine sparso: resta il primo in timeline
reset()
local kept, info = M.merge_text_items(api, { 3, 1, 2 }, name_item)
eq(kept, 1); eq(info.count, 3)
eq(items[1].P_NOTES, 'io vado Via di qui.', 'testi in fila con uno spazio')
eq(items[1].D_LENGTH, 6, 'dura fino alla fine dell\'ultima')
eq(items[1].D_POSITION, 10); eq(items[1].P_NAME, 'io vado Via di qui.')
eq(items[2], nil); eq(items[3], nil); eq(#deleted, 2); eq(blocks, 1, 'un solo passo di Undo')
local anchors = M.parse_anchors(items[1]['P_EXT:ZP_GOBBO_ANCHORS'])
eq(#anchors, 1); eq(items[1].P_NOTES:sub(anchors[1].offset, anchors[1].offset + 3), 'vado', 'il promemoria resta sulla sua parola')
eq(items[1]['P_EXT:RythmoBand_HIGHLIGHT'], 'io\nvado', 'evidenziati uniti senza doppioni')
eq(items[1]['P_EXT:ZP_GOBBO_TIMING'], ''); eq(items[1].selected, true)

-- Una battuta vuota non aggiunge spazi ma allunga la durata
reset()
kept = M.merge_text_items(api, { 3, 4 }, name_item)
eq(kept, 3); eq(items[3].P_NOTES, 'Via di qui.'); eq(items[3].D_LENGTH, 7); eq(items[4], nil)

-- Rifiuti: nulla viene toccato
for _, case in ipairs({ { { 1 }, 'almeno due' }, { { 1, 5 }, 'stessa traccia' }, { { 1, 6 }, 'audio o video' }, { { 1, 7 }, 'seguono un audio' }, { { 1, 99 }, 'disponibile' } }) do
  reset()
  local none, err = M.merge_text_items(api, case[1], name_item)
  eq(none, nil); assert(err:find(case[2], 1, true), err)
  eq(#deleted, 0); eq(items[1].P_NOTES, 'io'); eq(blocks, 0)
end

-- Scrittura non riuscita: annulla e non toglie nulla
reset(); fail_write = true
local none, err = M.merge_text_items(api, { 1, 2 }, name_item)
eq(none, nil); assert(err:find('annullata', 1, true)); eq(undone, 1); eq(#deleted, 0)
fail_write = false

-- Nome dell'item
reset(); M.name_text_item(api, 1, 'riga uno\nriga  due'); eq(items[1].P_NAME, 'riga uno / riga due')

print('TUTTI OK')
