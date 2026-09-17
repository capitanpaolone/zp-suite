-- @description ZP Stagekeeper - Crea Private Region SPACE dalla selezione temporale
-- @version 1.1
-- @noindex
local function load_private_regions()
  local path = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") .. "/ZP_Private_Regions.lua"
  local ok, module = pcall(dofile, path)
  if not ok or type(module) ~= "table" then
    local detail = ok and "il modulo non ha restituito una tabella valida" or tostring(module)
    reaper.MB(
      "ERRORE CRITICO: il modulo Private Regions non è disponibile o non è caricabile.\n\n" ..
      "Percorso atteso:\n" .. path .. "\n\n" ..
      "Dettaglio: " .. detail .. "\n\n" ..
      "Senza questo modulo una regione privata potrebbe essere trattata come pubblica.\n" ..
      "Lo script è stato interrotto per sicurezza.",
      "ZP Private Regions - modulo non disponibile",
      0
    )
    return nil
  end
  return module
end

local ZP_Private = load_private_regions()
if not ZP_Private then return end
local proj = reaper.EnumProjects(-1, "")
local first, last = reaper.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)
if last <= first then
  reaper.MB("Seleziona un intervallo temporale per la regione SPACE.", "ZP Stagekeeper", 0)
  return
end
reaper.Undo_BeginBlock2(proj)
local ok, err = pcall(ZP_Private.create, proj, "STAGEKEEPER", "SPACE", first, last,
  reaper.ColorToNative(235, 170, 60) | 0x1000000, 4, "SPACE")
reaper.Undo_EndBlock2(proj, "ZP Stagekeeper: Private Region SPACE", -1)
reaper.UpdateArrange()
if not ok then reaper.MB(tostring(err), "ZP Private Regions", 0) end
