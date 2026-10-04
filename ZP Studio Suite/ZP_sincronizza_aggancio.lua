-- @noindex

-- ZP Sincronizza (ad aggancio): take marker -> tracce testo nascoste, una per traccia voce
-- (helper della Suite: lo usano la finestra ZP Trascrizione e i Gobbi per "Segui i tagli")
--
-- Differenza dalla prima bozza: NON cancella e riscrive tutto. Ogni item testo ricorda
-- da quale marker nasce (GUID del take + tempo sorgente) e a ogni lancio viene solo
-- RIPOSIZIONATO. Il testo che hai corretto a mano non viene toccato.
--
-- Cosa fa, in ordine:
--   1. per ogni item audio non muted tiene SOLO i marker nella parte sorgente usata
--   2. converte sorgente -> timeline:  tempo = pos_item + (src - startoffs) / playrate
--   3. confronta con gli item testo gia' esistenti (marcati ZP_SYNC_KEY) e decide:
--        - stesso marker  -> aggiorna posizione/durata (testo invariato)
--        - marker nuovo   -> crea l'item testo
--        - marker sparito -> item mai modificato = cancellato; modificato a mano = mute
--   4. una traccia testo per ogni traccia voce: "Rythmo Band Testi <nome voce>", nascosta
--
-- Il gobbo non cambia: riconosce il prefisso "Rythmo Band Testi" e cicla le tracce con < >.

local M = {}

---------------------------------------------------------------------------
-- LOGICA PURA (nessuna chiamata a reaper.*, collaudabile con lua5.4)
---------------------------------------------------------------------------

-- Chiave di un marker: GUID del take + tempo sorgente al millisecondo.
function M.make_key(take_guid, src)
  return string.format("%s|%.3f", take_guid, src)
end

-- Chiave "di ripiego": file sorgente + tempo. Serve a ritrovare l'item testo
-- se il take cambia GUID (es. dopo uno split) senza perdere il testo corretto.
function M.make_srckey(filename, src)
  return string.format("%s|%.3f", filename or "", src)
end

-- Marker di un item che cadono nella parte usata, con posizione/durata in timeline.
-- item = {pos, len, startoffs, rate}; markers = { {src=, text=}, ... }
-- Battuta in corso: se il pezzo comincia a meta' di una battuta (nessun marker proprio
-- all'inizio), la battuta iniziata prima viene ripetuta all'inizio del pezzo, con "… "
-- davanti e carry = true. Cosi' anche un pezzo tagliato senza marker ha il suo testo.
M.CARRY_PREFIX = "\226\128\166 "   -- "… "
function M.item_lines(item, markers)
  local rate = item.rate
  if not rate or rate <= 0 then rate = 1 end
  local s0 = item.startoffs
  local s1 = s0 + item.len * rate
  local min_len = item.min_len or 0.1
  local list, before = {}, nil
  for _, m in ipairs(markers) do
    if m.text and m.text ~= "" then
      if m.src >= s0 and m.src < s1 then
        list[#list + 1] = { src = m.src, text = m.text }
      elseif m.src < s0 and (not before or m.src > before.src) then
        before = m
      end
    end
  end
  table.sort(list, function(a, b) return a.src < b.src end)
  local out = {}
  if before and (not list[1] or list[1].src > s0 + 0.0005) then
    local nxt = list[1] and list[1].src or s1
    local len = (nxt - s0) / rate
    if len < min_len then len = min_len end
    out[1] = { src = before.src, text = M.CARRY_PREFIX .. before.text, pos = item.pos, len = len, carry = true }
  end
  for k, m in ipairs(list) do
    local nxt = list[k + 1] and list[k + 1].src or s1
    local len = (nxt - m.src) / rate
    if len < min_len then len = min_len end
    out[#out + 1] = { src = m.src, text = m.text, pos = item.pos + (m.src - s0) / rate, len = len }
  end
  return out
end

-- wanted:   { {key, srckey, track, pos, len, text}, ... }  cio' che i marker chiedono
-- existing: { {id, key, srckey, track, notes, orig, orphan}, ... } item testo gia' presenti
--           (notes = testo attuale, orig = testo scritto dallo script, orphan = gia' in mute da noi)
-- Ritorna { update={ {e=,w=,set_text=,unmute=,move=} }, create={w}, delete={e}, mute={e} }
function M.plan(wanted, existing)
  local plan = { update = {}, create = {}, delete = {}, mute = {} }

  -- 1) abbinamento esatto per chiave (il primo vince; un doppione resta "libero")
  local by_key, used = {}, {}
  for _, e in ipairs(existing) do
    if e.key and not by_key[e.key] then by_key[e.key] = e end
  end
  local pairs_, free_wanted = {}, {}
  for _, w in ipairs(wanted) do
    local e = by_key[w.key]
    if e and not used[e] then
      used[e] = true
      pairs_[#pairs_ + 1] = { e = e, w = w }
    else
      free_wanted[#free_wanted + 1] = w
    end
  end

  -- 2) item liberi, indicizzati per chiave di ripiego
  local free_by_src = {}
  for _, e in ipairs(existing) do
    if not used[e] and e.srckey then
      local lst = free_by_src[e.srckey]
      if not lst then lst = {}; free_by_src[e.srckey] = lst end
      lst[#lst + 1] = e
    end
  end

  -- 3) marker senza item: provo il ripiego (stesso file+tempo), altrimenti creo
  for _, w in ipairs(free_wanted) do
    local lst = free_by_src[w.srckey]
    local e
    while lst and #lst > 0 do
      local cand = table.remove(lst, 1)
      if not used[cand] then e = cand; break end
    end
    if e then
      used[e] = true
      pairs_[#pairs_ + 1] = { e = e, w = w, rebind = true }
    else
      plan.create[#plan.create + 1] = w
    end
  end

  -- 4) aggiornamenti per le coppie
  for _, p in ipairs(pairs_) do
    local e, w = p.e, p.w
    local untouched = (e.notes == e.orig)
    plan.update[#plan.update + 1] = {
      e = e, w = w,
      rebind   = p.rebind or false,
      set_text = untouched and w.text ~= e.orig,   -- testo mai toccato e marker cambiato: segue il marker
      unmute   = e.orphan and true or false,       -- il marker e' tornato valido
      move     = (e.track ~= w.track),
    }
  end

  -- 5) item senza piu' marker
  for _, e in ipairs(existing) do
    if not used[e] and e.key then
      if e.notes == e.orig then
        plan.delete[#plan.delete + 1] = e
      elseif not e.orphan then
        plan.mute[#plan.mute + 1] = e
      end
    end
  end
  return plan
end

if not reaper then return M end

---------------------------------------------------------------------------
-- PARTE REAPER
---------------------------------------------------------------------------

local TEXT_PREFIX = "Rythmo Band Testi"   -- quello che il gobbo riconosce (default_track_name)
local MIN_LEN     = 0.1                    -- secondi: durata minima di una battuta
local EPS         = 1e-6

local function get_s(obj_get, obj, key)
  local _, v = obj_get(obj, key, "", false)
  return v or ""
end
local function item_s(it, key) return get_s(reaper.GetSetMediaItemInfo_String, it, key) end
local function set_item_s(it, key, v) reaper.GetSetMediaItemInfo_String(it, key, v, true) end
local function track_s(tr, key) return get_s(reaper.GetSetMediaTrackInfo_String, tr, key) end

local function is_text_track(tr)
  if track_s(tr, "P_EXT:ZP_VOICE") ~= "" then return true end
  return track_s(tr, "P_NAME"):find(TEXT_PREFIX, 1, true) == 1
end

-- Traccia testo di una traccia voce (cercata per GUID della voce, quindi regge i rename)
local text_tracks = {}   -- voice_guid -> track
local tracks_changed = false   -- creata o rinominata una traccia testo
local function text_track_for(voice, create)
  local vguid = reaper.GetTrackGUID(voice)
  local want = TEXT_PREFIX .. " " .. track_s(voice, "P_NAME")
  local tr = text_tracks[vguid]
  if not tr then
    for i = 0, reaper.CountTracks(0) - 1 do
      local t = reaper.GetTrack(0, i)
      if track_s(t, "P_EXT:ZP_VOICE") == vguid then tr = t; break end
    end
  end
  if not tr and create then
    local idx = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(idx, true)
    tr = reaper.GetTrack(0, idx)
    tracks_changed = true
    reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ZP_VOICE", vguid, true)
    reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 0)      -- nascosta: la mostri tu dal gestore tracce
    reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 0)
  end
  if tr then
    if track_s(tr, "P_NAME") ~= want then reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", want, true); tracks_changed = true end
    text_tracks[vguid] = tr
  end
  return tr
end

local function take_markers(take)
  local out = {}
  for j = 0, reaper.GetNumTakeMarkers(take) - 1 do
    local src, name = reaper.GetTakeMarker(take, j)
    out[#out + 1] = { src = src, text = name }
  end
  return out
end

reaper.PreventUIRefresh(1)

-- A) cosa chiedono i marker (item audio non muted, fuori dalle tracce testo)
local wanted = {}
local voices_needed = {}
for t = 0, reaper.CountTracks(0) - 1 do
  local voice = reaper.GetTrack(0, t)
  if not is_text_track(voice) then
    for i = 0, reaper.CountTrackMediaItems(voice) - 1 do
      local it = reaper.GetTrackMediaItem(voice, i)
      local take = reaper.GetActiveTake(it)
      if take and reaper.GetMediaItemInfo_Value(it, "B_MUTE") == 0 and reaper.GetNumTakeMarkers(take) > 0 then
        local _, tguid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
        local src = reaper.GetMediaItemTake_Source(take)
        local fname = src and reaper.GetMediaSourceFileName(src, "") or ""
        local lines = M.item_lines({
          pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION"),
          len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH"),
          startoffs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"),
          rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"),
          min_len = MIN_LEN,
        }, take_markers(take))
        if #lines > 0 then
          local ttr = text_track_for(voice, true)
          for _, l in ipairs(lines) do
            wanted[#wanted + 1] = {
              -- la battuta in corso ha chiavi sue: se il pezzo si allarga e il marker
              -- rientra, l'item "…" sparisce e nasce quello normale
              key = M.make_key(tguid, l.src) .. (l.carry and "|c" or ""),
              srckey = M.make_srckey(fname, l.src) .. (l.carry and "|c" or ""),
              track = ttr, pos = l.pos, len = l.len, text = l.text,
            }
          end
        end
      end
    end
  end
end

-- B) item testo gia' presenti (solo quelli con la nostra chiave)
local existing = {}
for t = 0, reaper.CountTracks(0) - 1 do
  local tr = reaper.GetTrack(0, t)
  if track_s(tr, "P_EXT:ZP_VOICE") ~= "" then
    for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      local key = item_s(it, "P_EXT:ZP_SYNC_KEY")
      if key ~= "" then
        existing[#existing + 1] = {
          id = it, track = tr, key = key, srckey = item_s(it, "P_EXT:ZP_SYNC_SRCKEY"),
          notes = item_s(it, "P_NOTES"), orig = item_s(it, "P_EXT:ZP_SYNC_TEXT"),
          orphan = item_s(it, "P_EXT:ZP_SYNC_ORPH") == "1",
        }
      end
    end
  end
end

-- C) decido e applico
local plan = M.plan(wanted, existing)

-- Niente da allineare: esco senza punto di Undo. Segui i tagli gira da solo dopo ogni
-- modifica al progetto e non deve riempire la cronologia di Undo vuoti.
local function differs(u)
  if u.move or u.rebind or u.unmute or u.set_text then return true end
  return math.abs(reaper.GetMediaItemInfo_Value(u.e.id, "D_POSITION") - u.w.pos) > EPS
      or math.abs(reaper.GetMediaItemInfo_Value(u.e.id, "D_LENGTH") - u.w.len) > EPS
end
local dirty = tracks_changed or #plan.create > 0 or #plan.delete > 0 or #plan.mute > 0
for _, u in ipairs(plan.update) do
  if dirty then break end
  dirty = differs(u)
end
if not dirty then
  reaper.PreventUIRefresh(-1)
  local summary = string.format("gia' allineati, %d battute.", #wanted)
  if not _G.ZP_SYNC_QUIET then reaper.ShowConsoleMsg("Sincronizza: " .. summary .. "\n") end
  return summary
end

reaper.Undo_BeginBlock()
local n_upd, n_moved = 0, 0

for _, u in ipairs(plan.update) do
  local it = u.e.id
  if u.move then reaper.MoveMediaItemToTrack(it, u.w.track); n_moved = n_moved + 1 end
  local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  local changed = false
  if math.abs(pos - u.w.pos) > EPS then reaper.SetMediaItemInfo_Value(it, "D_POSITION", u.w.pos); changed = true end
  if math.abs(len - u.w.len) > EPS then reaper.SetMediaItemInfo_Value(it, "D_LENGTH", u.w.len); changed = true end
  if u.set_text then
    set_item_s(it, "P_NOTES", u.w.text); set_item_s(it, "P_EXT:ZP_SYNC_TEXT", u.w.text); changed = true
  end
  if u.rebind then
    set_item_s(it, "P_EXT:ZP_SYNC_KEY", u.w.key); set_item_s(it, "P_EXT:ZP_SYNC_SRCKEY", u.w.srckey); changed = true
  end
  if u.unmute then
    reaper.SetMediaItemInfo_Value(it, "B_MUTE", 0); set_item_s(it, "P_EXT:ZP_SYNC_ORPH", ""); changed = true
  end
  if changed then n_upd = n_upd + 1 end
end

for _, w in ipairs(plan.create) do
  local it = reaper.AddMediaItemToTrack(w.track)
  reaper.SetMediaItemInfo_Value(it, "D_POSITION", w.pos)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH", w.len)
  set_item_s(it, "P_NOTES", w.text)
  set_item_s(it, "P_EXT:ZP_SYNC_KEY", w.key)
  set_item_s(it, "P_EXT:ZP_SYNC_SRCKEY", w.srckey)
  set_item_s(it, "P_EXT:ZP_SYNC_TEXT", w.text)
end

for _, e in ipairs(plan.delete) do
  reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(e.id), e.id)
end
for _, e in ipairs(plan.mute) do
  reaper.SetMediaItemInfo_Value(e.id, "B_MUTE", 1)
  set_item_s(e.id, "P_EXT:ZP_SYNC_ORPH", "1")
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Sincronizza take marker nel gobbo (aggancio)", -1)

local summary = string.format(
  "%d creati, %d aggiornati (%d spostati di traccia), %d cancellati, %d in mute (modificati a mano), %d battute totali.",
  #plan.create, n_upd, n_moved, #plan.delete, #plan.mute, #wanted)
if not _G.ZP_SYNC_QUIET then
  reaper.ShowConsoleMsg("Sincronizza: " .. summary .. "\n")
end
return summary
