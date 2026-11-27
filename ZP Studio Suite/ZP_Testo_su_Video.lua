-- @noindex
-- ZP Studio Suite: TESTO SU VIDEO (modulo; lo usano 40_Testo_su_Video e i due Gobbo) (copione Excel senza timecode)
-- Legge un .xlsx a blocchi (colonna "File name" + una colonna di testo per lingua, senza tempi) e crea
-- UN item di testo per ogni video/audio gia' in timeline: stessa posizione e stessa durata del media,
-- sulla traccia "Rythmo Band Testi" del Gobbo. Il testo e' una battuta per riga.
-- Abbinamento: nome del blocco = nome dell'item (senza estensione, senza distinzione di maiuscole).
-- Nessun abbinamento "per somiglianza": un nome che e' prefisso di un altro (es. "Clip01" e "Clip01_alt") resta una cosa distinta.
-- Se ci sono item selezionati lavora solo su quelli, altrimenti su tutti. Rilanciandolo, gli item di testo
-- creati prima dallo stesso nome vengono sostituiti (niente doppioni). Un solo passo di Undo.

local M = {}
local SCRIPT_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "")
local XLSX = dofile(SCRIPT_DIR .. "ZP_Xlsx_Copione.lua")
local TESTO = dofile(SCRIPT_DIR .. "ZP_Testo_Copione.lua")

local TITLE = "ZP Studio Suite - Testo su video"
local TRACK_NAME = "Rythmo Band Testi"
local KEY = "P_EXT:ZP_TESTO_VIDEO"

local function msg(text) reaper.ShowMessageBox(text, TITLE, 0) end
local function reader(path) return function(n) return TESTO.zip_member(path, n, reaper.GetOS()) end end

-- true se l'xlsx e' un copione a blocchi (colonna File name + testo) utilizzabile da run().
function M.can_run(path)
  if not path:lower():match("%.xlsx$") then return false end
  local g = XLSX.read_groups(reader(path), { choose = function() return 1 end })
  return g ~= nil
end

local function item_names(item)
  local names = {}
  local take = reaper.GetActiveTake(item)
  if not take then return names end
  local _, tn = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  if tn ~= "" then names[#names + 1] = tn end
  local _, iname = reaper.GetSetMediaItemInfo_String(item, "P_NAME", "", false)
  if iname ~= "" then names[#names + 1] = iname end
  local src = reaper.GetMediaItemTake_Source(take)
  local path = src and reaper.GetMediaSourceFileName(src, "") or ""
  if path ~= "" then names[#names + 1] = path:match("([^/\\]+)$") or path end
  return names
end

local function find_track(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, n = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if n == name then return tr end
  end
end

function M.run(path)
  local groups, sheet, column = XLSX.read_groups(reader(path), { choose = XLSX.menu })
  if not groups then if sheet then msg("Copione non importato.\n\n" .. sheet) end return false end

  -- media candidati
  local items = {}
  local selected = reaper.CountSelectedMediaItems(0)
  if selected > 0 then
    for i = 0, selected - 1 do items[#items + 1] = reaper.GetSelectedMediaItem(0, i) end
  else
    for i = 0, reaper.CountMediaItems(0) - 1 do items[#items + 1] = reaper.GetMediaItem(0, i) end
  end
  local by_name = {}
  for _, item in ipairs(items) do
    if reaper.GetActiveTake(item) then
      for _, n in ipairs(item_names(item)) do
        local k = XLSX.match_key(n)
        by_name[k] = by_name[k] or item
      end
    end
  end

  local plan, missing, used = {}, {}, {}
  for _, g in ipairs(groups) do
    local item = by_name[XLSX.match_key(g.name)]
    if item then plan[#plan + 1] = { group = g, item = item }; used[item] = true
    else missing[#missing + 1] = g.name end
  end
  if #plan == 0 then
    msg("Nessun blocco del copione corrisponde a un item in timeline" ..
      (selected > 0 and " (fra quelli selezionati)" or "") .. ".\n\nI nomi devono coincidere con i nomi dei media, senza estensione.\nPrimo blocco del file: " .. groups[1].name)
    return false
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local track = find_track(TRACK_NAME)
  if not track then
    reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
    track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", TRACK_NAME, true)
  end

  -- Sostituzione: via i testi creati in precedenza da questo script con lo stesso nome blocco.
  local replaced = 0
  local wanted = {}
  for _, p in ipairs(plan) do wanted[p.group.name] = true end
  for i = reaper.CountTrackMediaItems(track) - 1, 0, -1 do
    local it = reaper.GetTrackMediaItem(track, i)
    local _, k = reaper.GetSetMediaItemInfo_String(it, KEY, "", false)
    if k ~= "" and wanted[k] then reaper.DeleteTrackMediaItem(track, it); replaced = replaced + 1 end
  end

  for _, p in ipairs(plan) do
    local pos = reaper.GetMediaItemInfo_Value(p.item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(p.item, "D_LENGTH")
    local t = reaper.AddMediaItemToTrack(track)
    reaper.SetMediaItemInfo_Value(t, "D_POSITION", pos)
    reaper.SetMediaItemInfo_Value(t, "D_LENGTH", len)
    reaper.GetSetMediaItemInfo_String(t, "P_NOTES", p.group.text, true)
    reaper.GetSetMediaItemInfo_String(t, KEY, p.group.name, true)
    TESTO.name_text_item(reaper, t, p.group.text)
  end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("ZP: testo su video da copione Excel", -1)

  local unused = 0
  for _, item in ipairs(items) do
    if reaper.GetActiveTake(item) and not used[item] then unused = unused + 1 end
  end
  local report = string.format("Creati %d item di testo (colonna «%s», foglio «%s») sulla traccia «%s».", #plan, column or "?", sheet or "?", TRACK_NAME)
  if replaced > 0 then report = report .. string.format("\nSostituiti %d testi creati in precedenza.", replaced) end
  if #missing > 0 then report = report .. "\n\nBlocchi del copione senza media in timeline:\n- " .. table.concat(missing, "\n- ") end
  if unused > 0 then report = report .. string.format("\n\n%d media in timeline senza blocco nel copione.", unused) end
  msg(report)

  return true
end

return M
