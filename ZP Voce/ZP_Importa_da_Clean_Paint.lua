-- @noindex
-- @description ZP Clean & Paint — Importa in REAPER l'ultimo file inviato dalla Web App
-- @version 1.0.0
-- @author Paolo Balestri / Antigravity
-- Legge reaper_import_path.txt scritto da ZP Clean & Paint (e compatibile con ZP Catalogo).

local script_source = debug.getinfo(1, "S").source or ""
if script_source:sub(1, 1) == "@" then
  script_source = script_source:sub(2)
end
local script_dir = script_source:match("^(.*)[/\\][^/\\]+$") or "."
local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""
local appdata = os.getenv("APPDATA") or ""

local handoff_candidates = {}
if appdata ~= "" then
  handoff_candidates[#handoff_candidates + 1] = appdata .. "/ZP_Clean_Paint/reaper_import_path.txt"
  handoff_candidates[#handoff_candidates + 1] = appdata .. "/ZP_Catalogo_1_0/reaper_import_path.txt"
end
if home ~= "" then
  handoff_candidates[#handoff_candidates + 1] = home .. "/Library/Application Support/ZP_Clean_Paint/reaper_import_path.txt"
  handoff_candidates[#handoff_candidates + 1] = home .. "/Library/Application Support/ZP_Catalogo_1_0/reaper_import_path.txt"
end
handoff_candidates[#handoff_candidates + 1] = script_dir .. "/reaper_import_path.txt"

local default_track_name = "ZP Clean & Paint Out"
local build_missing_peaks_command = 40047 -- Peaks: Build any missing peaks

local function notify(message)
  if reaper.GetMousePosition and reaper.TrackCtl_SetToolTip then
    local x, y = reaper.GetMousePosition()
    reaper.TrackCtl_SetToolTip("ZP Clean & Paint: " .. message, x + 12, y + 12, true)
  end
end

local function basename(path)
  return (path and path:match("[^/\\]+$")) or path or ""
end

local function read_first_available(paths)
  for i = 1, #paths do
    local f = io.open(paths[i], "r")
    if f then
      local text = f:read("*a")
      f:close()
      text = text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
      if text ~= "" then
        return text, paths[i]
      end
    end
  end
  return nil, nil
end

local media_path = read_first_available(handoff_candidates)
if not media_path then
  reaper.ShowMessageBox(
    "Nessun file pronto da ZP Clean & Paint.\nPremi prima 'Invia Risultato a REAPER' nella pagina web (http://127.0.0.1:8789).",
    "ZP Clean & Paint",
    0
  )
  return
end

local f = io.open(media_path, "rb")
if not f then
  reaper.ShowMessageBox("File non trovato:\n" .. media_path, "ZP Clean & Paint", 0)
  return
end
f:close()

local function get_target_track()
  -- Se c'è una traccia selezionata dall'utente, usa quella; altrimenti cerca o crea "ZP Clean & Paint Out"
  local sel_track = reaper.GetSelectedTrack(0, 0)
  if sel_track then
    return sel_track
  end
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, tr_name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if tr_name == default_track_name then
      return tr
    end
  end
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", default_track_name, true)
  return tr
end

local function insert_media_on_track(track, path)
  local source = reaper.PCM_Source_CreateFromFile(path)
  if not source then
    return false, "REAPER non riesce a leggere il file:\n" .. path
  end

  local length = reaper.GetMediaSourceLength(source)
  if not length or length <= 0 then length = 1 end

  local item = reaper.AddMediaItemToTrack(track)
  if not item then
    reaper.PCM_Source_Destroy(source)
    return false, "Impossibile creare l'item sulla traccia."
  end

  local play_state = reaper.GetPlayState()
  local position = (play_state % 2 == 1) and reaper.GetPlayPosition() or reaper.GetCursorPosition()
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", position)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", length)
  local take = reaper.AddTakeToMediaItem(item)
  reaper.SetMediaItemTake_Source(take, source)
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", basename(path), true)
  reaper.SetMediaItemSelected(item, true)
  reaper.SetOnlyTrackSelected(track)
  reaper.UpdateItemInProject(item)
  reaper.SetEditCurPos(position, true, false)
  return true
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
local target_track = get_target_track()
local ok, err = insert_media_on_track(target_track, media_path)
reaper.TrackList_AdjustWindows(false)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
if ok then
  reaper.Main_OnCommand(build_missing_peaks_command, 0)
end
reaper.Undo_EndBlock("Importa file da ZP Clean & Paint", -1)

if not ok then
  reaper.ShowMessageBox(err or "Importazione non riuscita.", "ZP Clean & Paint", 0)
else
  notify("Importato: " .. basename(media_path))
end
