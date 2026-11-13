-- @noindex
-- Provenienza ZP:
--   Proprietà: ZP Remote / recupero WAV senza manifest.
--   Origine: progetto ZP Remote (ZP_Solo_Recorder_WebRemote/reaper), copiato il 2026-11-13; preparazione Suite 2.6.7.
--   Versione interna: non dichiarata separatamente; incluso nel pacchetto.

-- ZP Remote — recupero WAV senza manifest. Solo aggiunte: nessun file esistente viene toccato o sovrascritto.
-- Per ogni WAV scelto: copia nella cartella Media del progetto, nuova traccia col nome del file, item al cursore di edit.
-- Un solo blocco di Undo. L'importatore normale (con consegna.json e verifica degli hash) resta separato e invariato.
local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("^(.*[/\\])") or ""
local logic = dofile(script_dir .. "zp_remote_recupero_logic.lua")
local r = reaper
local M = {}

local function die(msg) error(msg, 0) end
local function basename(path) return path:match("([^/\\]+)$") or path end
local function dirname(path) return path:match("^(.*)[/\\][^/\\]*$") or "." end
local function path_join(a, b) return a:gsub("[/\\]+$", "") .. "/" .. b end

local function project_file()
  local _, file = r.EnumProjects(-1, "")
  if not file or file == "" then die("Salva il progetto REAPER prima di importare.") end
  return file
end

local function copia(src, dst)
  local input, err = io.open(src, "rb"); if not input then die("WAV non leggibile: " .. src .. " (" .. tostring(err) .. ")") end
  local existing = io.open(dst, "rb")
  if existing then existing:close(); input:close(); die("Esiste già un file con questo nome, non lo sovrascrivo: " .. dst) end
  local tmp = dst .. ".part-" .. tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
  local output, e = io.open(tmp, "wb"); if not output then input:close(); die("Non posso creare il WAV temporaneo: " .. tostring(e)) end
  while true do
    local block = input:read(1024 * 1024); if not block then break end
    local ok, we = output:write(block)
    if not ok then input:close(); output:close(); os.remove(tmp); die("Errore di scrittura: " .. tostring(we)) end
  end
  input:close()
  local closed, ce = output:close()
  if closed == nil then os.remove(tmp); die("Chiusura del WAV temporaneo fallita: " .. tostring(ce)) end
  local ok, re = os.rename(tmp, dst); if not ok then os.remove(tmp); die("Non posso finalizzare il WAV copiato: " .. tostring(re)) end
end

-- Scelta dei file: se c'è js_ReaScriptAPI si scelgono più file insieme, altrimenti uno alla volta.
local function scegli_file()
  local paths = {}
  if r.JS_Dialog_BrowseForOpenFiles then
    local ok, list = r.JS_Dialog_BrowseForOpenFiles("Scegli i WAV da inserire (senza manifest)", "", "", "WAV (*.wav)\0*.wav\0\0", true)
    if ok ~= 1 and ok ~= true then return paths end
    -- elenco: cartella\0file1\0file2... oppure, con un solo file, il percorso intero
    return logic.percorsi_da_selezione(list)
  end
  while true do
    local ok, path = r.GetUserFileNameForRead("", "Scegli un WAV da inserire (senza manifest)", "wav")
    if not ok then break end
    paths[#paths + 1] = path
    if r.MB("Aggiungere un altro WAV?", "ZP Remote — recupero WAV", 4) ~= 6 then break end
  end
  return paths
end

local function descrivi(path)
  local f = io.open(path, "rb"); if not f then return { path = path, name = basename(path), head = "", size = 0 } end
  local head = f:read(65536) or ""
  local size = f:seek("end") or #head
  f:close()
  -- per i blocchi lunghi prima di 'data' (JUNK, bext, iXML): rilegge il file a finestre, aprendolo solo quando serve
  local function leggi(offset, n)
    local g = io.open(path, "rb"); if not g then return nil end
    local ok = g:seek("set", offset)
    local s = ok and g:read(n) or nil
    g:close()
    return s
  end
  -- REAPER è l'ultimo giudice: se non legge audio (durata 0) il file non viene importato
  local reaper_len
  local src = r.PCM_Source_CreateFromFile(path)
  if src then
    reaper_len = r.GetMediaSourceLength(src) or 0
    if r.PCM_Source_Destroy then r.PCM_Source_Destroy(src) end
  else
    reaper_len = 0
  end
  return { path = path, name = basename(path), head = head, size = size, leggi = leggi, reaper_len = reaper_len }
end

-- Riserva una cartella nuova per il lotto: RecursiveCreateDirectory dà >0 solo se l'ha creata ora.
local function riserva_cartella(base_dir)
  for n = 1, 100 do
    local candidata = (n == 1) and base_dir or (base_dir .. "_" .. n)
    if r.RecursiveCreateDirectory(candidata, 0) > 0 then return candidata end
  end
  die("Non riesco a creare una cartella nuova in Media/ZP Remote.")
end

local function main(opts)
  opts = opts or {}
  local project = project_file()
  local paths = opts.paths or scegli_file()
  if #paths == 0 then return nil end
  local files = {}
  for _, p in ipairs(paths) do files[#files + 1] = descrivi(p) end
  local cursore = r.GetCursorPosition()
  local stamp = os.date("%Y%m%d-%H%M%S")
  local base_dir = path_join(path_join(dirname(project), "Media/ZP Remote"), "recupero_" .. stamp)
  local piano = logic.piano(files, cursore, {})
  if #piano.voci == 0 then return { message = logic.messaggio(piano), piano = piano } end
  if opts.confirm and not opts.confirm(("Inserisco %d file in nuove tracce al cursore (%.3f s).\nI file non sono verificati (manca il manifest).\nProcedo?"):format(#piano.voci, cursore)) then return nil end
  local media_dir = riserva_cartella(base_dir)   -- dopo la conferma: se annulli, nessuna cartella vuota
  -- 1) copio tutto prima di toccare il progetto; se fallisce, tolgo solo ciò che ho creato io
  local copiati = {}
  local ok_copia, err_copia = pcall(function()
    for _, v in ipairs(piano.voci) do
      if opts.onProgress then opts.onProgress("Copio " .. v.name) end
      local dst = path_join(media_dir, v.media_name)
      copia(v.path, dst)
      copiati[#copiati + 1] = dst
    end
  end)
  if not ok_copia then
    for _, f in ipairs(copiati) do os.remove(f) end
    os.remove(media_dir)   -- riesce solo se vuota: non tocca nulla che non sia nostro
    die(tostring(err_copia))
  end
  -- 2) un solo blocco di Undo per tracce e item
  r.PreventUIRefresh(1)
  r.Undo_BeginBlock2(0)
  local ok, err = xpcall(function()
    for _, v in ipairs(piano.voci) do
      local index = r.CountTracks(0)
      r.InsertTrackAtIndex(index, true)
      local track = r.GetTrack(0, index); if not track then die("Creazione traccia fallita: " .. v.name) end
      r.GetSetMediaTrackInfo_String(track, "P_NAME", v.track_name, true)
      r.GetSetMediaTrackInfo_String(track, "P_EXT:ZP_REMOTE_IMPORT", "recupero:" .. stamp, true)
      local media = path_join(media_dir, v.media_name)
      local source = r.PCM_Source_CreateFromFile(media); if not source then die("REAPER non apre il WAV copiato: " .. media) end
      local len = r.GetMediaSourceLength(source)
      local item = r.AddMediaItemToTrack(track); if not item then die("Creazione item fallita: " .. v.name) end
      local take = r.AddTakeToMediaItem(item); if not take then die("Creazione take fallita: " .. v.name) end
      r.SetMediaItemTake_Source(take, source)
      r.GetSetMediaItemTakeInfo_String(take, "P_NAME", v.name, true)
      r.SetMediaItemInfo_Value(item, "D_POSITION", v.position_s)
      r.SetMediaItemInfo_Value(item, "D_LENGTH", len)
      r.SetMediaItemInfo_Value(item, "C_BEATATTACHMODE", 0)
      r.GetSetMediaItemInfo_String(item, "P_NOTES", "Recuperato senza manifest — da verificare", true)
      r.GetSetMediaItemInfo_String(item, "P_EXT:ZP_REMOTE_IMPORT", "recupero:" .. stamp, true)
    end
    r.UpdateArrange()
  end, debug.traceback)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock2(0, ok and "ZP Remote: recupero WAV senza manifest" or "ZP Remote: recupero annullato", -1)
  if not ok then
    r.Undo_DoUndo2(0)
    die("Recupero annullato con Undo. I WAV originali non sono stati toccati.\n" .. tostring(err))
  end
  return { message = logic.messaggio(piano), piano = piano }
end

function M.run(opts)
  local ok, result = xpcall(function() return main(opts or {}) end, debug.traceback)
  if not ok then return false, result end
  return true, result
end

return M
