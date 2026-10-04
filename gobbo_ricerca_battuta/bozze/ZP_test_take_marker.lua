-- ZP test take marker (script di prova, NON fa parte della Suite)
-- Modo "crea": scrive N take marker sull'item selezionato.
-- Modo "conta": per ogni item selezionato riporta quanti marker ha
--               e se i nomi lunghi sono arrivati interi.

local LONG = string.rep("Battuta lunga di prova, serve a vedere se il nome del marker viene troncato. ", 10) -- circa 780 caratteri, come 120 parole

local function log(s) reaper.ShowConsoleMsg(tostring(s) .. "\n") end

local ok, vals = reaper.GetUserInputs("Test take marker", 3,
  "Modo (crea/conta):,Quanti marker (crea):,Intervallo in secondi (crea):",
  "crea,600,2")
if not ok then return end
local mode, n, step = vals:match("^([^,]*),([^,]*),([^,]*)$")
n, step = tonumber(n) or 600, tonumber(step) or 2

local count = reaper.CountSelectedMediaItems(0)
if count == 0 then reaper.MB("Seleziona almeno un item audio.", "Test", 0) return end

if mode == "crea" then
  local item = reaper.GetSelectedMediaItem(0, 0)
  local take = reaper.GetActiveTake(item)
  if not take then reaper.MB("L'item non ha take.", "Test", 0) return end
  -- SetTakeMarker lavora in tempo SORGENTE, non di timeline:
  -- parto dall'offset del take e avanzo di 'step' secondi per volta.
  local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local t0 = reaper.time_precise()
  reaper.Undo_BeginBlock()
  for i = 1, n do
    local name = (i % 10 == 0) and string.format("TEST %04d %s", i, LONG)
                                 or string.format("TEST %04d", i)
    reaper.SetTakeMarker(take, -1, name, offs + (i - 1) * step)
  end
  reaper.Undo_EndBlock("Test take marker", -1)
  log(string.format("Creati %d marker in %.3f s. Ora ne risultano %d.",
      n, reaper.time_precise() - t0, reaper.GetNumTakeMarkers(take)))
else
  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = reaper.GetActiveTake(item)
    if take then
      local m = reaper.GetNumTakeMarkers(take)
      local intatti, lunghi, dentro = 0, 0, 0
      -- parte di sorgente che l'item usa ancora dopo tagli e trim (in secondi sorgente)
      local s0 = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
      local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
      local s1 = s0 + reaper.GetMediaItemInfo_Value(item, "D_LENGTH") * rate
      for j = 0, m - 1 do
        local srcpos, name = reaper.GetTakeMarker(take, j)
        if srcpos >= s0 and srcpos < s1 then dentro = dentro + 1 end
        if name and name:find("TEST %d%d%d%d Battuta lunga") then
          lunghi = lunghi + 1
          if #name >= #LONG then intatti = intatti + 1 end
        end
      end
      local src = reaper.GetMediaItemTake_Source(take)
      local fname = reaper.GetMediaSourceFileName(src, "")
      log(string.format("Item %d: %d marker nel take, %d dentro la parte usata, nomi lunghi intatti %d/%d  [%s]",
          i + 1, m, dentro, intatti, lunghi, fname:match("[^/\\]+$") or fname))
    end
  end
end
