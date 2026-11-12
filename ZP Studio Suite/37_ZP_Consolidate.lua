-- @description ZP Consolidate - copia in Media le sorgenti usate dal progetto e aggiorna i riferimenti
-- @author Paolo Balestri
-- @version 1.0
-- @about
--   Copia byte per byte in Media le sorgenti file di tutti i take, compresi i take inattivi,
--   e gli SRT/VTT registrati dal progetto. Non converte, ricampiona, taglia o sposta gli originali.

local r = reaper
local project_handle, rpp = r.EnumProjects(-1, "")
if not rpp or rpp == "" then
  r.MB("Prima salva il progetto: ZP Consolidate deve conoscere la cartella Media.", "ZP Consolidate", 0)
  return
end

local sep = package.config:sub(1, 1)
local project_dir = rpp:match("^(.*)[/\\][^/\\]+$")
if not project_dir then
  r.MB("Non riesco a determinare la cartella del progetto.", "ZP Consolidate", 0)
  return
end
local media_dir = project_dir .. sep .. "Media"
local function join(a, b) return a .. sep .. b end
local function basename(path) return path:match("[^/\\]+$") or path end
local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end
local function norm(path)
  path = tostring(path or ""):gsub("\\", "/"):gsub("/+$", "")
  if r.GetOS and r.GetOS():match("Win") then path = path:lower() end
  return path
end
local function resolve_path(path)
  path = tostring(path or "")
  if path:match("^[/\\]") or path:match("^%a:[/\\]") then return path end
  return join(project_dir, path)
end
local media_prefix = norm(media_dir) .. "/"
local function in_media(path) return norm(path):sub(1, #media_prefix) == media_prefix end
local function unique_path(path, reserved)
  local name = basename(path)
  local ext = name:match("(%.[^.]+)$") or ""
  local stem = ext ~= "" and path:sub(1, #path - #ext) or path
  local n = 2
  repeat
    local candidate = stem .. " (" .. n .. ")" .. ext
    if not exists(candidate) and not reserved[norm(candidate)] then return candidate end
    n = n + 1
  until n > 10000
end

local helper_path = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or ".") .. sep .. "ZP_SRT_Progetto.lua"
local SRT
do
  local ok, module = pcall(dofile, helper_path)
  if ok and type(module) == "table" then SRT = module end
end

local media_by_path, media_plans, skipped, missing = {}, {}, {}, {}
local item_count = r.CountMediaItems(0)
for i = 0, item_count - 1 do
  local item = r.GetMediaItem(0, i)
  for t = 0, r.CountTakes(item) - 1 do
    local take = r.GetTake(item, t)
    local src = take and r.GetMediaItemTake_Source(take)
    if src then
      local path = r.GetMediaSourceFileName(src, "") or ""
      local kind = r.GetMediaSourceType and (r.GetMediaSourceType(src, "") or "") or ""
      if path == "" then
        if kind ~= "MIDI" then skipped[#skipped + 1] = "Take " .. (t + 1) .. ": sorgente senza file esterno (" .. (kind ~= "" and kind or "tipo sconosciuto") .. ")" end
      elseif r.GetMediaSourceParent and r.GetMediaSourceParent(src) then
        skipped[#skipped + 1] = basename(path) .. ": sorgente derivata/SECTION; lasciata collegata all'originale"
      elseif kind == "RPP_PROJECT" then
        skipped[#skipped + 1] = basename(path) .. ": subproject; le sue dipendenze vanno raccolte dal progetto annidato"
      elseif kind ~= "WAVE" and kind ~= "MIDI" and kind ~= "VIDEO" then
        skipped[#skipped + 1] = basename(path) .. ": tipo sorgente non gestito automaticamente (" .. (kind ~= "" and kind or "sconosciuto") .. ")"
      else
        path = resolve_path(path)
        local key = norm(path)
        if not media_by_path[key] then
          local record = { source = path, kind = kind, takes = {}, media = true }
          media_by_path[key], media_plans[#media_plans + 1] = record, record
        end
        media_by_path[key].takes[#media_by_path[key].takes + 1] = take
      end
    end
  end
end

local plans, reserved = {}, {}
local function add_file(source, label, media_record)
  if not exists(source) then
    missing[#missing + 1] = basename(source) .. " (" .. label .. ")"
    return
  end
  if in_media(source) then
    if media_record then media_record.destination = source; media_record.already_collected = true end
    return
  end
  local target = join(media_dir, basename(source))
  local key = norm(target)
  if reserved[key] then
    target = unique_path(target, reserved)
  elseif exists(target) then
    local answer = r.ShowMessageBox(
      "Esiste già un file con questo nome in Media:\n\n" .. basename(target) ..
      "\n\nSì = sovrascrivi la copia in Media\nNo = conserva entrambe rinominando la nuova copia\nAnnulla = interrompi ZP Consolidate",
      "Collisione in Media · ZP Consolidate", 3)
    if answer == 2 then error("annullato dall'utente") end
    if answer == 7 then target = unique_path(target, reserved) end
  end
  if not target then error("non trovo un nome libero per " .. basename(source)) end
  reserved[norm(target)] = true
  local plan = { source = source, target = target, media_record = media_record, label = label }
  plans[#plans + 1] = plan
  if media_record then media_record.destination = target; media_record.plan = plan end
end

if r.RecursiveCreateDirectory then
  r.RecursiveCreateDirectory(media_dir, 0)
else
  r.MB("Questa versione di REAPER non espone RecursiveCreateDirectory.", "ZP Consolidate", 0)
  return
end
local probe_path = join(media_dir, ".zp-consolidate-probe")
local probe = io.open(probe_path, "wb")
if not probe then
  r.MB("Non riesco a scrivere nella cartella Media:\n" .. media_dir, "ZP Consolidate", 0)
  return
end
probe:close(); os.remove(probe_path)

local ok_plan, plan_error = pcall(function()
  for _, record in ipairs(media_plans) do add_file(record.source, "media", record) end
  if SRT then
    for _, entry in ipairs(SRT.entries()) do
      if entry.path and entry.path ~= "" then
        add_file(entry.path, "SRT/VTT", { srt = entry })
      end
    end
  end
end)
if not ok_plan then
  if tostring(plan_error):find("annullato dall'utente", 1, true) then return end
  r.MB("Preparazione interrotta:\n" .. tostring(plan_error), "ZP Consolidate", 0)
  return
end

local file_index, active, copied, failed = 1, nil, {}, {}
local starting_state = r.GetProjectStateChangeCount(0)
local CHUNK, BUDGET = 1024 * 1024, 0.012
local function log(line) r.ShowConsoleMsg("[ZP Consolidate] " .. line .. "\n") end
local function temp_path(path)
  local base = path .. ".zp-part"
  if not exists(base) then return base end
  local n = 2
  repeat
    local candidate = base .. "." .. n
    if not exists(candidate) then return candidate end
    n = n + 1
  until n > 10000
end
local function begin_copy(plan)
  local input, err = io.open(plan.source, "rb")
  if not input then failed[#failed + 1] = basename(plan.source) .. ": lettura impossibile (" .. tostring(err) .. ")"; return nil end
  local temp = temp_path(plan.target)
  local output, werr = io.open(temp, "wb")
  if not output then input:close(); failed[#failed + 1] = basename(plan.target) .. ": scrittura impossibile (" .. tostring(werr) .. ")"; return nil end
  local size = input:seek("end") or 0
  input:seek("set", 0)
  return { plan = plan, input = input, output = output, temp = temp, size = size, bytes = 0 }
end
local function close_active(remove_temp)
  if not active then return end
  if active.input then active.input:close() end
  if active.output then active.output:close() end
  if remove_temp then os.remove(active.temp) end
  active = nil
end
local function install_temp(job)
  local target, temp = job.plan.target, job.temp
  local backup
  if exists(target) then
    local n = 1
    repeat
      backup = temp .. ".previous" .. (n > 1 and ("." .. n) or "")
      n = n + 1
    until not exists(backup)
    local moved, err = os.rename(target, backup)
    if not moved then os.remove(temp); failed[#failed + 1] = basename(target) .. ": backup collisione fallito (" .. tostring(err) .. ")"; return false end
  end
  local moved, err = os.rename(temp, target)
  if not moved then
    if backup then
      if not os.rename(backup, target) then failed[#failed + 1] = "RECUPERO MANUALE: versione precedente in " .. backup end
    end
    os.remove(temp)
    failed[#failed + 1] = basename(target) .. ": installazione copia fallita (" .. tostring(err) .. ")"
    return false
  end
  if backup and not os.remove(backup) then log("Versione precedente conservata in " .. backup) end
  copied[job.plan] = true
  return true
end

local function apply_copies_and_references()
  local current_handle, current_rpp = r.EnumProjects(-1, "")
  if current_handle ~= project_handle or current_rpp ~= rpp or r.GetProjectStateChangeCount(0) ~= starting_state then
    local message = "Le copie sono state create, ma il progetto è cambiato durante la raccolta. " ..
      "Per sicurezza non ho ricollegato i take né aggiornato il registro SRT. Rilancia ZP Consolidate sul progetto fermo."
    log(message)
    r.MB(message, "ZP Consolidate", 0)
    return
  end
  local relinks, source_map, srt_done = {}, {}, 0
  for _, record in ipairs(media_plans) do
    if record.destination and record.destination ~= record.source then
      if record.already_collected then
        -- Il percorso è già nella cartella Media.
      elseif copied[record.plan] then
        local pending, complete = {}, true
        for _, take in ipairs(record.takes) do
          local fresh = r.PCM_Source_CreateFromFile(record.destination)
          if fresh then pending[#pending + 1] = { take = take, source = fresh }
          else complete = false; failed[#failed + 1] = basename(record.source) .. ": REAPER non riesce a riaprire la copia" end
        end
        if complete then
          source_map[record.source] = record.destination
          for _, change in ipairs(pending) do relinks[#relinks + 1] = change end
        else
          for _, change in ipairs(pending) do
            if r.PCM_Source_Destroy then r.PCM_Source_Destroy(change.source) end
          end
        end
      end
    end
  end

  r.Undo_BeginBlock2(0)
  r.PreventUIRefresh(1)
  for _, change in ipairs(relinks) do r.SetMediaItemTake_Source(change.take, change.source) end
  for old_path, new_path in pairs(source_map) do
    if SRT and old_path ~= new_path then SRT.remap_source(old_path, new_path) end
  end
  if SRT then
    for _, plan in ipairs(plans) do
      if plan.label == "SRT/VTT" and copied[plan] and plan.media_record and plan.media_record.srt then
        local e = plan.media_record.srt
        local source_key = source_map[e.source] or e.source
        local ok, err = SRT.register(source_key, plan.target, e.lang, e.kind)
        if ok then srt_done = srt_done + 1 else failed[#failed + 1] = basename(plan.target) .. ": registro SRT fallito (" .. tostring(err) .. ")" end
      elseif plan.label == "SRT/VTT" and plan.media_record and plan.media_record.srt and plan.source == plan.target then
        local e = plan.media_record.srt
        SRT.register(e.source, plan.target, e.lang, e.kind)
        srt_done = srt_done + 1
      end
    end
  end
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  if #relinks > 0 or srt_done > 0 then
    r.MarkProjectDirty(0)
    r.Undo_EndBlock2(0, "ZP Consolidate: raccogli sorgenti e SRT", -1)
  else
    r.Undo_EndBlock2(0, "ZP Consolidate: nessuna sorgente aggiornata", -1)
  end

  local copied_count = 0
  for _ in pairs(copied) do copied_count = copied_count + 1 end
  local lines = { "ZP Consolidate terminato.", "", "File copiati: " .. tostring(copied_count), "Take ricollegati: " .. tostring(#relinks), "SRT/VTT registrati: " .. tostring(srt_done) }
  if #missing > 0 then lines[#lines + 1] = "\nFile mancanti: " .. #missing end
  if #skipped > 0 then lines[#lines + 1] = "Sorgenti particolari non raccolte: " .. #skipped end
  if #failed > 0 then lines[#lines + 1] = "Errori: " .. #failed end
  lines[#lines + 1] = "\nSalva il progetto per rendere permanenti i nuovi riferimenti."
  r.MB(table.concat(lines, "\n"), "ZP Consolidate", 0)
  for _, line in ipairs(missing) do log("MANCANTE: " .. line) end
  for _, line in ipairs(skipped) do log("DA VERIFICARE: " .. line) end
  for _, line in ipairs(failed) do log("ERRORE: " .. line) end
end

local function step()
  if not active then
    local plan = plans[file_index]
    if not plan then return apply_copies_and_references() end
    file_index = file_index + 1
    active = begin_copy(plan)
    if not active then return r.defer(step) end
  end
  local started = r.time_precise()
  repeat
    local chunk = active.input:read(CHUNK)
    if not chunk then
      local job = active
      local closed, err = job.output:close()
      job.output = nil
      job.input:close(); job.input = nil
      active = nil
      if not closed then
        os.remove(job.temp)
        failed[#failed + 1] = basename(job.plan.target) .. ": chiusura scrittura fallita (" .. tostring(err) .. ")"
      elseif job.bytes ~= job.size then
        os.remove(job.temp)
        failed[#failed + 1] = basename(job.plan.source) .. ": copia incompleta"
      else
        install_temp(job)
      end
      return r.defer(step)
    end
    local ok, err = active.output:write(chunk)
    if not ok then
      local name = basename(active.plan.target)
      close_active(true)
      failed[#failed + 1] = name .. ": scrittura fallita (" .. tostring(err) .. ")"
      return r.defer(step)
    end
    active.bytes = active.bytes + #chunk
  until r.time_precise() - started >= BUDGET
  r.defer(step)
end

if #plans == 0 then
  for _, line in ipairs(missing) do log("MANCANTE: " .. line) end
  for _, line in ipairs(skipped) do log("DA VERIFICARE: " .. line) end
  local message = "Non ci sono file esterni nuovi da copiare. I media già in Media e i MIDI incorporati restano come sono."
  if #missing > 0 then message = message .. "\n\nFile mancanti: " .. #missing .. " (dettagli in Console)." end
  if #skipped > 0 then message = message .. "\nSorgenti speciali da verificare: " .. #skipped .. " (dettagli in Console)." end
  if not SRT then message = message .. "\nIl modulo registro SRT non è disponibile in questa installazione." end
  r.MB(message, "ZP Consolidate", 0)
  return
end
log("Avvio: " .. #plans .. " file in coda, destinazione " .. media_dir)
r.defer(step)
