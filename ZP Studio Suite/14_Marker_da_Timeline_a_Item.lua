-- @noindex

-- ZP Studio Suite for REAPER
-- 14 Marker da timeline a item
--
-- Copia i marker di progetto che cadono dentro l'item selezionato come take
-- marker dell'item. Tiene nome, posizione e colore.
--
-- Con piu' item selezionati chiede se lavorare su tutti o solo sul primo.
-- Non duplica: un marker gia' presente nell'item (stesso punto, stesso nome)
-- viene saltato, quindi lo script si puo' rilanciare senza danni.
-- Alla fine propone di cancellare dalla timeline i marker di progetto ormai
-- fissati negli item; se rispondi No restano dove sono, come prima.
--
-- Il tempo dei take marker e' quello della sorgente, non della timeline:
-- la conversione tiene conto di start offset e playrate del take.

local M = {}
local TITLE = "Project Markers -> Take Markers"
local SAME_POS = 0.001   -- secondi: entro 1 ms e' lo stesso punto della sorgente

---------------------------------------------------------------------------
-- LOGICA PURA (collaudabile con lua fuori da REAPER)
---------------------------------------------------------------------------

-- items:   { {pos, len, startoffs, rate, existing = { {src, name}, ... }}, ... }
-- markers: { {pos, name, id, color}, ... }  marker di progetto (non regioni)
-- Restituisce per ogni item i marker da aggiungere e quanti sono gia' presenti,
-- e l'elenco degli id dei marker di progetto fissati in almeno un item.
function M.plan(items, markers)
  local result, fixed, fixed_seen = {}, {}, {}
  for i, it in ipairs(items) do
    local rate = (it.rate and it.rate > 0) and it.rate or 1
    local add, already = {}, 0
    local present = {}
    for _, e in ipairs(it.existing or {}) do present[#present + 1] = e end
    for _, m in ipairs(markers) do
      -- [inizio, fine): un marker sul bordo appartiene all'item che comincia li'
      if m.pos >= it.pos and m.pos < it.pos + it.len then
        local src = it.startoffs + (m.pos - it.pos) * rate
        local name = m.name or ""
        local dup = false
        for _, e in ipairs(present) do
          if math.abs(e.src - src) <= SAME_POS and (e.name or "") == name then dup = true; break end
        end
        if dup then
          already = already + 1
        else
          add[#add + 1] = { src = src, name = name, color = m.color }
          present[#present + 1] = { src = src, name = name }
        end
        if not fixed_seen[m.id] then fixed_seen[m.id] = true; fixed[#fixed + 1] = m.id end
      end
    end
    result[i] = { add = add, already = already }
  end
  return result, fixed
end

if not reaper then return M end

---------------------------------------------------------------------------
-- PARTE REAPER
---------------------------------------------------------------------------

local count = reaper.CountSelectedMediaItems(0)
if count == 0 then
  reaper.MB("Seleziona un item e rilancia lo script.", TITLE, 0)
  return
end

local use = 1
if count > 1 then
  local answer = reaper.MB(string.format(
    "Ci sono %d item selezionati.\n\nSì: fissa i marker in tutti.\nNo: solo nel primo.\nAnnulla: esci senza modifiche.", count),
    TITLE, 3)
  if answer == 2 then return end
  use = answer == 6 and count or 1
end

-- item e take da lavorare, con i take marker che hanno gia'
local items, takes, no_take = {}, {}, 0
for i = 0, use - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  local take = item and reaper.GetActiveTake(item)
  if take then
    local existing = {}
    for j = 0, reaper.GetNumTakeMarkers(take) - 1 do
      local src, name = reaper.GetTakeMarker(take, j)
      existing[#existing + 1] = { src = src, name = name }
    end
    items[#items + 1] = {
      pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION"),
      len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
      startoffs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"),
      rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"),
      existing = existing,
    }
    takes[#takes + 1] = take
  else
    no_take = no_take + 1
  end
end
if #items == 0 then
  reaper.MB("L'item selezionato non ha un take attivo.", TITLE, 0)
  return
end

local markers = {}
local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
for i = 0, num_markers + num_regions - 1 do
  local retval, is_region, pos, _, name, id, color = reaper.EnumProjectMarkers3(0, i)
  if retval > 0 and not is_region then
    markers[#markers + 1] = { pos = pos, name = name, id = id, color = color }
  end
end

local plan, fixed = M.plan(items, markers)
local to_add, already = 0, 0
for _, p in ipairs(plan) do to_add = to_add + #p.add; already = already + p.already end

if #fixed == 0 then
  reaper.MB("Nessun marker di progetto dentro " .. (#items > 1 and "gli item selezionati." or "l'item selezionato."), TITLE, 0)
  return
end

-- Tutte le domande prima di modificare: un Annulla non lascia lavori a meta'.
local remove = reaper.MB(string.format(
  "Marker da fissare negli item: %d\nGia' presenti negli item (saltati): %d\n\nCancellare dalla timeline i %d marker di progetto fissati negli item?\n\nSì: cancella dalla timeline.\nNo: lasciali anche in timeline.\nAnnulla: esci senza modifiche.",
  to_add, already, #fixed), TITLE, 3)
if remove == 2 then return end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

for i, p in ipairs(plan) do
  for _, m in ipairs(p.add) do
    reaper.SetTakeMarker(takes[i], -1, m.name, m.src, m.color)
  end
end

local removed = 0
if remove == 6 then
  for _, id in ipairs(fixed) do
    if reaper.DeleteProjectMarker(0, id, false) then removed = removed + 1 end
  end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Copia Project Markers come Take Markers", -1)

reaper.MB(string.format(
  "Item lavorati: %d%s\nMarker fissati: %d\nGia' presenti, saltati: %d\nCancellati dalla timeline: %d",
  #items, no_take > 0 and string.format(" (%d senza take, saltati)", no_take) or "",
  to_add, already, removed), TITLE, 0)
