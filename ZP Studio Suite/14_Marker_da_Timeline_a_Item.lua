-- @noindex

-- ZP Studio Suite for REAPER
-- 14 Marker da timeline a item
--
-- Copia i marker di progetto che cadono dentro l'item selezionato come take
-- marker dell'item. Tiene nome, posizione e colore.
--
-- NON cancella i marker di progetto: li duplica dentro l'item, cosi' il testo
-- viaggia insieme al file quando l'item viene spostato o consegnato.
--
-- Il tempo dei take marker e' quello della sorgente, non della timeline:
-- la conversione tiene conto di start offset e playrate del take.

local item = reaper.GetSelectedMediaItem(0, 0)

if not item then
    reaper.MB(
        "Seleziona un item e rilancia lo script.",
        "Project Markers -> Take Markers",
        0
    )
    return
end

local take = reaper.GetActiveTake(item)

if not take then
    reaper.MB(
        "L'item selezionato non ha un take attivo.",
        "Project Markers -> Take Markers",
        0
    )
    return
end

local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
local item_end = item_pos + item_len

-- Parametri necessari per convertire
-- tempo progetto -> tempo sorgente del take
local start_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
local playrate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")

local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
local total = num_markers + num_regions

local copied = 0

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

for i = 0, total - 1 do
    local retval,
          is_region,
          marker_pos,
          region_end,
          name,
          marker_id,
          color =
        reaper.EnumProjectMarkers3(0, i)

    if retval > 0
       and not is_region
       and marker_pos >= item_pos
       and marker_pos <= item_end then

        -- SetTakeMarker usa il tempo della sorgente del take,
        -- non la posizione assoluta nel progetto.
        local source_pos =
            start_offset + ((marker_pos - item_pos) * playrate)

        reaper.SetTakeMarker(
            take,
            -1,             -- -1 = crea nuovo Take Marker
            name or "",
            source_pos,
            color
        )

        copied = copied + 1
    end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()

reaper.Undo_EndBlock(
    "Copia Project Markers come Take Markers",
    -1
)

reaper.MB(
    tostring(copied) .. " marker copiati nell'item.",
    "Project Markers -> Take Markers",
    0
)