-- ZP Sincronizza: take marker -> traccia "Rythmo Band Testi" (bozza, NON ancora nella Suite)
--
-- Cosa fa, in ordine:
--   1. passa tutti gli item del progetto (tranne la traccia testi)
--   2. di ogni take tiene SOLO i marker dentro la parte sorgente usata
--      (dopo tagli/trim il take conserva tutta la lista: vedi collaudo)
--   3. converte sorgente -> timeline:  tempo = pos_item + (src - startoffs) / playrate
--   4. ricrea sulla traccia testi un item vuoto per battuta, testo nelle note
--      (e' il formato che il gobbo gia' legge: nessuna modifica al gobbo)
--
-- Si puo' rilanciare quando vuoi: cancella e rifa' SOLO gli item che ha creato
-- lui (marcati P_EXT:ZP_SYNC), quindi i testi scritti a mano restano intatti.

local TRACK_NAME = "Rythmo Band Testi"
local TAG        = "P_EXT:ZP_SYNC"
local MIN_LEN    = 0.1   -- secondi: durata minima di una battuta

local function find_track()
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if name == TRACK_NAME then return tr end
  end
end

local function get_or_create_track()
  local tr = find_track()
  if tr then return tr end
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", TRACK_NAME, true)
  return tr
end

-- Raccoglie le battute di un item: {pos, len, text}
local function item_lines(item, out)
  local take = reaper.GetActiveTake(item)
  if not take then return end
  local n = reaper.GetNumTakeMarkers(take)
  if n == 0 then return end

  local ipos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local ilen  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local s0    = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local rate  = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  if rate <= 0 then rate = 1 end
  local s1    = s0 + ilen * rate

  local list = {}
  for j = 0, n - 1 do
    local src, name = reaper.GetTakeMarker(take, j)
    if src >= s0 and src < s1 and name and name ~= "" then
      list[#list + 1] = { src = src, text = name }
    end
  end
  table.sort(list, function(a, b) return a.src < b.src end)

  for k, m in ipairs(list) do
    local nxt = list[k + 1] and list[k + 1].src or s1   -- la battuta dura fino alla successiva
    local pos = ipos + (m.src - s0) / rate
    local len = (nxt - m.src) / rate
    if len < MIN_LEN then len = MIN_LEN end
    out[#out + 1] = { pos = pos, len = len, text = m.text }
  end
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local rythmo = get_or_create_track()

-- 1) tolgo i vecchi item creati da questo script
for i = reaper.CountTrackMediaItems(rythmo) - 1, 0, -1 do
  local it = reaper.GetTrackMediaItem(rythmo, i)
  local _, tag = reaper.GetSetMediaItemInfo_String(it, TAG, "", false)
  if tag == "1" then reaper.DeleteTrackMediaItem(rythmo, it) end
end

-- 2) raccolgo le battute da tutti gli item (esclusi muted e la traccia testi)
local lines = {}
for t = 0, reaper.CountTracks(0) - 1 do
  local tr = reaper.GetTrack(0, t)
  if tr ~= rythmo then
    for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      if reaper.GetMediaItemInfo_Value(it, "B_MUTE") == 0 then item_lines(it, lines) end
    end
  end
end
table.sort(lines, function(a, b) return a.pos < b.pos end)

-- 3) creo gli item testo
for _, l in ipairs(lines) do
  local it = reaper.AddMediaItemToTrack(rythmo)
  reaper.SetMediaItemInfo_Value(it, "D_POSITION", l.pos)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH", l.len)
  reaper.GetSetMediaItemInfo_String(it, "P_NOTES", l.text, true)
  reaper.GetSetMediaItemInfo_String(it, TAG, "1", true)
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Sincronizza take marker nel gobbo", -1)

reaper.ShowConsoleMsg(string.format("Sincronizzate %d battute sulla traccia \"%s\".\n", #lines, TRACK_NAME))
