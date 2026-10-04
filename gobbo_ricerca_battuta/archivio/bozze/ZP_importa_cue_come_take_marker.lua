-- ZP importa cue dei file come take marker (bozza, NON ancora nella Suite)
--
-- Per ogni item selezionato:
--   1. 40692  -> i cue del file diventano marker di PROGETTO
--   2. il tuo script (project -> take marker) li copia nell'item
--   3. cancella i marker di progetto creati al punto 1, cosi' non restano doppioni
-- I take marker seguono poi tagli, spostamenti e Glue come tutti gli altri.
--
-- Salta gli item che hanno gia' dei take marker: rilanciarlo non crea doppioni.
-- NOTA: assume che l'ID sotto sia lo script project -> take marker che copia i
-- marker di progetto nell'item selezionato (come il 14 della Suite).

local CUES_TO_PROJECT_MARKERS = 40692
local PROJECT_TO_TAKE_MARKERS = "_RSec76c1a2359012fb969d191afa2c67a8c9cd6b67"

-- Elenco dei numeri dei marker di progetto (le regioni non contano).
local function marker_numbers()
  local set = {}
  local _, n_markers, n_regions = reaper.CountProjectMarkers(0)
  for i = 0, n_markers + n_regions - 1 do
    local ok, is_region, _, _, _, number = reaper.EnumProjectMarkers(i)
    if ok and not is_region then set[number] = true end
  end
  return set
end

local cmd = reaper.NamedCommandLookup(PROJECT_TO_TAKE_MARKERS)
if cmd == 0 then
  reaper.MB("Non trovo lo script project -> take marker.\nControlla l'ID in cima al file.",
            "Cue come take marker", 0)
  return
end

-- Memorizzo la selezione: 40692 e lo script lavorano sugli item selezionati,
-- quindi li seleziono uno alla volta e alla fine rimetto tutto com'era.
local selected = {}
for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
  selected[#selected + 1] = reaper.GetSelectedMediaItem(0, i)
end
if #selected == 0 then reaper.MB("Seleziona almeno un item.", "Cue come take marker", 0) return end

local done, skipped = 0, 0
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

for _, item in ipairs(selected) do
  local take = reaper.GetActiveTake(item)
  if take and reaper.GetNumTakeMarkers(take) == 0 then
    reaper.SelectAllMediaItems(0, false)
    reaper.SetMediaItemSelected(item, true)

    local before = marker_numbers()
    reaper.Main_OnCommand(CUES_TO_PROJECT_MARKERS, 0)
    reaper.Main_OnCommand(cmd, 0)

    -- tolgo solo i marker di progetto nati da 40692
    for number in pairs(marker_numbers()) do
      if not before[number] then reaper.DeleteProjectMarker(0, number, false) end
    end
    done = done + 1
  else
    skipped = skipped + 1
  end
end

reaper.SelectAllMediaItems(0, false)
for _, item in ipairs(selected) do reaper.SetMediaItemSelected(item, true) end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Importa cue come take marker", -1)

reaper.ShowConsoleMsg(string.format("Cue importati su %d item, saltati %d (avevano gia' take marker).\n", done, skipped))
