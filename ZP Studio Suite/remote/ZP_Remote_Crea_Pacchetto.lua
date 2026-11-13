-- @description ZP Remote: controlla il progetto REAPER e crea il pacchetto da condividere
-- @version 1.0
-- @author ZP
-- @about
--   Interfaccia guidata per l'esportatore ZP Remote. Richiede accanto a questo file
--   zp_remote_esporta.py e zp_remote_json.lua.

-- Provenienza ZP:
--   Proprietà: ZP Remote / esportazione pacchetti.
--   Pacchetto d’origine: ZP Studio Suite 2.6.6 (installazione locale con aggiornamenti beta).
--   Copia locale REAPER acquisita il 2026-11-09; preparazione Suite 2.6.7.
--   Versione interna: 1.0, campo @version ReaPack.

local r = reaper
local TITLE, SECTION = "ZP Remote · Pacchetto", "ZP_REMOTE_EXPORT"
local HELP = [[Da REAPER a dubbertools.com

1. Scegli la regione da esportare e la cartella di destinazione. Se il progetto è nuovo, genera un ID. Se hai già condiviso un pacchetto, recupera il suo ID per collegare le consegne allo stesso progetto.

2. Premi «Controlla», poi «Crea pacchetto». Lo ZIP contiene il materiale della regione: video, guida audio, battute e anelli. Per creare lo ZIP servono Python 3 e ffmpeg.

3. Usa «Apri cartella» per trovare lo ZIP. Mettilo su uno spazio che fornisce un link HTTPS scaricabile. Accedi al tuo spazio su dubbertools.com, apri il progetto e incolla quel link nella parte che vuoi assegnare.

4. Quando ricevi le registrazioni, apri «Importa» nello stesso progetto REAPER. Scegli lo ZIP di ritorno oppure la cartella estratta con consegna.json. Se l’ID coincide, i tempi BWF collocano le take nel progetto senza ZIP di partenza; per riallineare una copia diversa, scegli anche il pacchetto originale. Premi «Controlla consegna» e verifica la regione e il riepilogo prima di importare.]]
local src = debug.getinfo(1, "S").source:sub(2)
local script_dir = src:match("^(.*)[/\\][^/\\]+$") or "."
local function join(a, b) return a:gsub("[/\\]+$", "") .. package.config:sub(1,1) .. b end
local exporter = join(script_dir, "zp_remote_esporta.py")
local json_path = join(script_dir, "zp_remote_json.lua")
local json_ok, json = pcall(dofile, json_path)

local function quote(s)
  s = tostring(s)
  if r.GetOS():match("^Win") then return '"' .. s:gsub('"', '\\"') .. '"' end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end
local function find_python()
  local osname = r.GetOS()
  if osname:match("^Win") then return "py -3" end
  local candidates = osname:match("OSX")
    and {"/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"}
    or {"/usr/local/bin/python3", "/usr/bin/python3", "/usr/bin/python3.11", "/usr/bin/python3.10"}
  for _, path in ipairs(candidates) do
    local f = io.open(path, "rb")
    if f then f:close(); return quote(path) end
  end
  return nil
end
local python = find_python()
local function command(args)
  if not python then return nil end
  return python .. " " .. table.concat(args, " ")
end
local function read_json(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close()
  if not json_ok then return nil, "Lettore JSON non disponibile: zp_remote_json.lua deve stare accanto allo script." end
  local ok, value = pcall(json.decode, s)
  if not ok then return nil end
  return value
end
local function trim_output(s)
  if not s then return "" end
  -- ExecProcess antepone il codice di uscita alla risposta del comando.
  local first = s:find("\n", 1, true)
  if first then s = s:sub(first + 1) end
  return s:match("^%s*(.-)%s*$") or ""
end

local _, rpp = r.EnumProjects(-1, "")
if not rpp then rpp = "" end
local project_name = rpp:match("([^/\\]+)%.RPP$") or rpp:match("([^/\\]+)$")
if not project_name and r.GetProjectName then project_name = r.GetProjectName(0, "") end
project_name = project_name ~= "" and project_name or "Progetto REAPER non salvato"
local project_dir = rpp:match("^(.*)[/\\][^/\\]+$") or ""
local folder = r.GetExtState(SECTION, "cartella")
if folder == "" then folder = project_dir end
local summary, summary_error
local status_text, status_kind = rpp == "" and "Salva il progetto per iniziare il percorso ZP Remote." or "Controlla il progetto per iniziare il percorso ZP Remote.", "info"
local busy, status_file, started_at, export_running = false, nil, nil, false
local started_precise
local completed_zip
local poster_jpg = ""
local pending_save_action, recovery_mode, recovery_value, input_focus = nil, false, "", false
local view = "export"
local export_regions, export_region_index = {}, 1
local import_delivery = r.GetExtState(SECTION, "import_consegna")
local import_zip = r.GetExtState(SECTION, "import_zip")
local import_regions, import_region_index, import_region_manual = {}, 1, false
local import_sync_project = ""
local import_last_reaper_cursor, import_last_ui_selected_idx
local import_last_loop_start, import_last_loop_end
local import_busy, import_status_file, import_started_at = false, nil, nil
local import_plan_path, import_plan, import_status_text, import_status_kind = nil, nil, "Scegli la cartella oppure lo ZIP di ritorno.", "info"
local C, rect, label, wrapped_label, buttons
local start_import_preflight
local refresh_export_regions
local function is_identity_error(text)
  return text and (
    text:find("identità ZP Remote", 1, true) or
    text:find("ID ZP Remote assente", 1, true)
  )
end
local function project_identity()
  local found, id = r.GetProjExtState(0, "ZP_REMOTE", "PROJECT_ID")
  if found > 0 and id and id ~= "" then return id end
  return nil
end
local function refresh_project_info()
  local _, path = r.EnumProjects(-1, "")
  rpp = path or ""
  if rpp ~= "" then
    project_name = rpp:match("([^/\\]+)%.RPP$") or rpp:match("([^/\\]+)$") or project_name
    project_dir = rpp:match("^(.*)[/\\][^/\\]+$") or project_dir
    if folder == "" and project_dir ~= "" then folder = project_dir end
  elseif r.GetProjectName then
    local name = r.GetProjectName(0, "")
    if name and name ~= "" then project_name = name end
  end
end

local function preflight()
  if rpp == "" then
    summary, summary_error = nil, "Salva prima il progetto REAPER."
    status_text, status_kind = summary_error, "error"
    return false
  end
  if not r.file_exists(exporter) then
    summary, summary_error = nil, "Non trovo zp_remote_esporta.py accanto a questa azione. Tieni insieme i file della cartella reaper/."
    status_text, status_kind = summary_error, "error"
    return false
  end
  if not json_ok then
    summary, summary_error = nil, "Non trovo zp_remote_json.lua accanto a questa azione. Tieni insieme i file della cartella reaper/."
    status_text, status_kind = summary_error, "error"
    return false
  end
  if not project_identity() then
    summary, summary_error = nil, "Prima assegna un'identità a questo progetto."
    status_text = "Passaggio 1: genera un ID oppure recupera quello del pacchetto già inviato."
    status_kind = "info"
    return false
  end
  if not python then
    summary, summary_error = nil, "Non trovo Python 3 in una posizione di sistema. Installa Python 3 e riapri REAPER."
    status_text, status_kind = summary_error, "error"
    return false
  end
  refresh_export_regions()
  local region = export_regions[export_region_index]
  if not region then
    summary, summary_error = nil, "Il progetto non contiene regioni REAPER da esportare. Crea una regione, salvala e riprova."
    status_text, status_kind = summary_error, "error"
    return false
  end
  local region_flag = region.guid and "--region-guid" or "--region-name"
  local region_value = region.guid or region.name
  local cmd = command({quote(exporter), quote(rpp), "--controlla", region_flag, quote(region_value),
    "--region-start", quote(string.format("%.9f", region.start)), "--region-end", quote(string.format("%.9f", region.ending))})
  local output = r.ExecProcess(cmd, 0)
  local payload = trim_output(output)
  local report_error
  if json_ok then
    for line in payload:gmatch("[^\r\n]+") do
      local candidate = line:match("^%s*(%{.*%})%s*$")
      if candidate then
        local ok, data = pcall(json.decode, candidate)
        if ok and data and data.ok then
          summary, summary_error = data, nil
          status_text = "Regione pronta. Rivedi il riepilogo, poi crea il pacchetto."
          status_kind = "ok"
          return true
        elseif ok and data and data.errore then
          report_error = data.errore
        end
      end
    end
  end
  if report_error then
    summary, summary_error = nil, report_error
    if is_identity_error(report_error) then
      status_text = "Passaggio 1: genera un ID oppure recupera quello del pacchetto già inviato."
      status_kind = "info"
    else
      status_text, status_kind = report_error:gsub("\n", " "), "error"
    end
    return false
  end
  if payload == "-999" or payload:match("^-?%d+$") then
    payload = "REAPER non è riuscito ad avviare Python 3. Chiudi e riapri REAPER dopo aver installato Python."
  end
  summary, summary_error = nil, payload ~= "" and payload or "Non riesco a leggere il progetto. Controlla Python 3 e i file ZP Remote."
  status_text = summary_error:gsub("\n", " ")
  status_kind = "error"
  return false
end

local function choose_folder()
  local ok, selected = r.GetUserFileName(3, "Dove salvo il pacchetto ZP Remote?", folder, "")
  if ok and selected and selected ~= "" then
    folder = selected:gsub("[/\\]+$", "")
    r.SetExtState(SECTION, "cartella", folder, true)
    summary = nil
    status_text, status_kind = "Cartella scelta. Controlla il progetto prima di esportare.", "info"
  end
end

local function choose_poster_jpg()
  local ok, selected = r.GetUserFileNameForRead(poster_jpg, "Scegli il JPG per poster.jpg", "jpg")
  if ok and selected and selected ~= "" then
    poster_jpg = selected
    status_text, status_kind = "Userò il JPG scelto, adattato a 640×360.", "ok"
  end
end

local function request_save(action)
  refresh_project_info()
  if rpp == "" or r.IsProjectDirty(0) > 0 then
    pending_save_action = action
    status_text = "Salva il progetto per continuare con il passaggio selezionato."
    status_kind = "info"
    if action == "import_check" then
      import_plan=nil
      import_status_text,import_status_kind="Salva il progetto per controllare la consegna.","info"
    end
    return false
  end
  return true
end

local function normalize_identity(value)
  local id = tostring(value or ""):match("^%s*(.-)%s*$")
  if id:sub(1,1) == "{" and id:sub(-1) == "}" then id = id:sub(2,-2) end
  id = id:gsub("-", "")
  if #id ~= 32 or not id:match("^%x+$") then return nil end
  return "{" .. id:upper() .. "}"
end

local function save_identity(id)
  if project_identity() then
    status_text, status_kind = "Questo progetto ha già un ID. Lo mantengo invariato.", "info"
    recovery_mode, input_focus = false, false
    return
  end
  r.SetProjExtState(0, "ZP_REMOTE", "PROJECT_ID", id)
  r.MarkProjectDirty(0)
  r.Main_SaveProject(0, false)
  refresh_project_info()
  local saved, check = r.GetProjExtState(0, "ZP_REMOTE", "PROJECT_ID")
  if saved <= 0 or check ~= id or rpp == "" or r.IsProjectDirty(0) > 0 then
    status_text, status_kind = "ID assegnato ma non ancora salvato su disco. Usa Salva progetto prima di continuare.", "error"
    return
  end
  recovery_mode, input_focus, summary_error = false, false, nil
  status_text, status_kind = "ID creato e salvato nel progetto. Passo successivo: controlla il progetto.", "ok"
  preflight()
end

local function generate_identity()
  if project_identity() then
    status_text, status_kind = "L'ID è già presente: resta associato a questo progetto.", "ok"
    return
  end
  if not request_save("generate") then return end
  save_identity(r.genGuid(""):upper())
end

local function recover_identity()
  local id = normalize_identity(recovery_value)
  if not id then
    status_text, status_kind = "ID non valido. Incolla il valore project.guid dal manifest.json del pacchetto esistente.", "error"
    return
  end
  if project_identity() then
    status_text, status_kind = "Questo progetto ha già un ID. Non lo sostituisco.", "error"
    return
  end
  if not request_save("recover") then return end
  save_identity(id)
end

local function check_project()
  if not project_identity() then
    summary, summary_error = nil, "Prima genera un ID per un nuovo progetto oppure recupera quello del pacchetto già inviato."
    status_text, status_kind = summary_error, "info"
    return
  end
  if not request_save("check") then return end
  refresh_project_info()
  preflight()
end

local character_ids = dofile(join(script_dir, "zp_remote_character_ids.lua"))

local function persist_character_ids(summary)
  local found, raw = r.GetProjExtState(0, "ZP_REMOTE", "CHARACTER_IDS")
  local registry = {version=1, by_marker={}, by_name={}}
  if found > 0 and raw ~= "" then
    local ok, value = pcall(json.decode, raw)
    if not ok or type(value) ~= "table" then
      status_text, status_kind = "Mappa CHARACTER_IDS non leggibile nel progetto. Nessun export avviato.", "error"
      return false
    end
    registry = value
  end
  local updated, changed, err = character_ids.reconcile(summary.personaggi_marker or {}, registry, function() return r.genGuid("") end)
  if not updated then status_text, status_kind = err, "error"; return false end
  if changed then
    r.SetProjExtState(0, "ZP_REMOTE", "CHARACTER_IDS", character_ids.encode(updated))
    r.MarkProjectDirty(0)
    pending_save_action = "export"
    status_text, status_kind = "Ho riallineato la mappa degli ID al nome attuale dei marker. Salva il progetto, poi riprendo l’esportazione.", "info"
    return false
  end
  return true
end

local function start_export_now()
  refresh_project_info()
  if not project_identity() then
    summary, summary_error = nil, "Prima genera un ID per questo progetto."
    status_text, status_kind = summary_error, "info"
    return
  end
  if not preflight() then return end
  if not persist_character_ids(summary) then return end
  local region = export_regions[export_region_index]
  if folder == "" then
    status_text, status_kind = "Scegli la cartella in cui creare il pacchetto.", "info"
    return
  end
  local safe_name = (summary.progetto or project_name):gsub("[^A-Za-z0-9]+", "-"):gsub("^-+", ""):gsub("-+$", "")
  if safe_name == "" then safe_name = "progetto" end
  local region_slug = (region.name or "regione"):gsub("[^A-Za-z0-9]+", "-"):gsub("^-+", ""):gsub("-+$", "")
  if region_slug == "" then region_slug = "regione" end
  safe_name = safe_name .. "-" .. region_slug .. "-" .. tostring(region.marker_index)
  local package_name = safe_name
  local package_path = folder .. package.config:sub(1,1) .. package_name .. ".zip"
  local overwrite_existing = false
  if r.file_exists(package_path) then
    local suffix = 2
    repeat
      package_name = safe_name .. "-" .. tostring(suffix)
      package_path = folder .. package.config:sub(1,1) .. package_name .. ".zip"
      suffix = suffix + 1
    until not r.file_exists(package_path)
    local answer = r.ShowMessageBox(
      "Esiste già:\n" .. safe_name .. ".zip\n\n" ..
      "Sì: sovrascrivi il file esistente.\n" ..
      "No: conserva il file e crea " .. package_name .. ".zip.\n" ..
      "Annulla: interrompi senza modifiche.",
      "Pacchetto già esistente", 3)
    if answer == 6 then
      overwrite_existing = true
      package_name = safe_name
    elseif answer ~= 7 then
      status_text, status_kind = "Esportazione annullata; lo ZIP esistente è rimasto intatto.", "info"
      return
    end
  end
  status_file = folder .. package.config:sub(1,1) .. ".zp_remote_stato_" .. r.genGuid(""):gsub("[^%x]", "") .. ".json"
  os.remove(status_file)
  local region_flag = region.guid and "--region-guid" or "--region-name"
  if poster_jpg ~= "" and not r.file_exists(poster_jpg) then
    status_text, status_kind = "Il JPG scelto per il poster non è più disponibile. Scegline un altro o usa il fotogramma video.", "error"
    return
  end
  local args = {quote(exporter), quote(rpp), "--uscita", quote(folder), "--stato-file", quote(status_file),
    "--nome-pacchetto", quote(package_name), region_flag, quote(region.guid or region.name),
    "--region-start", quote(string.format("%.9f", region.start)), "--region-end", quote(string.format("%.9f", region.ending))}
  if overwrite_existing then args[#args+1] = "--sovrascrivi" end
  if poster_jpg ~= "" then
    args[#args+1] = "--poster-jpg"; args[#args+1] = quote(poster_jpg)
  else
    local cursor_s = r.GetCursorPosition()
    args[#args+1] = "--poster-project-s"; args[#args+1] = quote(string.format("%.9f", cursor_s))
  end
  r.ExecProcess(command(args), -1)
  busy, started_at, export_running = true, os.time(), false
  started_precise = r.time_precise and r.time_precise() or started_at
  status_text, status_kind = "Avvio dell'esportazione…", "working"
end

local function start_export()
  if busy then return end
  if not project_identity() then
    status_text, status_kind = "Completa prima il passaggio Identità progetto.", "info"
    return
  end
  if not request_save("export") then return end
  start_export_now()
end

local function save_and_continue()
  local action = pending_save_action
  if not action then return end
  r.Main_SaveProject(0, false)
  refresh_project_info()
  if rpp == "" or r.IsProjectDirty(0) > 0 then
    pending_save_action = nil
    status_text, status_kind = "Il progetto non risulta salvato.", "error"
    if action=="import_check" then import_status_text,import_status_kind=status_text,status_kind end
    return
  end
  pending_save_action = nil
  if action == "generate" then
    save_identity(r.genGuid(""):upper())
  elseif action == "recover" then
    local id = normalize_identity(recovery_value)
    if id then save_identity(id) else status_text, status_kind = "ID non valido. Incolla un project.guid valido.", "error" end
  elseif action == "check" then
    preflight()
  elseif action == "export" then
    start_export_now()
  elseif action == "import_check" then
    start_import_preflight()
  end
end

local function poll_export()
  if not busy or not status_file then return end
  local result = read_json(status_file)
  if result and result.stato == "in_corso" then
    export_running = true
  elseif result and result.stato == "completato" then
    busy, completed_zip = false, result.zip
    status_text = "Pacchetto della regione " .. tostring(result.regione or "") .. " creato · " .. tostring(result.durata_s or "") .. " s · " .. tostring(result.anelli) .. " anelli · " .. tostring(result.mb) .. " MB"
    status_kind = "ok"
    os.remove(status_file)
  elseif result and result.stato == "errore" then
    busy = false
    status_text = tostring(result.messaggio or "Esportazione non riuscita."):gsub("\n", " ")
    status_kind = "error"
    os.remove(status_file)
  elseif not export_running and os.time() - (started_at or os.time()) > 15 then
    busy = false
    status_text = "L'esportazione non è partita. Controlla Python 3 e ffmpeg, poi riprova."
    status_kind = "error"
    os.remove(status_file)
  end
end

local function refresh_import_regions()
  local previous=import_regions[import_region_index]
  local previous_manual=import_region_manual
  if import_sync_project ~= rpp then
    import_sync_project = rpp
    import_last_reaper_cursor, import_last_ui_selected_idx = nil, nil
    import_last_loop_start, import_last_loop_end = nil, nil
    previous, previous_manual = nil, false
  end
  import_regions = {}
  local _, marker_count, region_count = r.CountProjectMarkers(0)
  local count=(marker_count or 0)+(region_count or 0)
  local cursor = r.GetCursorPosition()
  for i=0,(count or 0)-1 do
    local retval,is_region,pos,ending,name,idx = r.EnumProjectMarkers3(0,i)
    if retval and retval > 0 and is_region then
      import_regions[#import_regions+1] = {name=name or ("Regione "..tostring(idx)), start=pos, ending=ending, marker_index=idx}
    end
  end
  table.sort(import_regions,function(a,b) return a.start < b.start end)
  if rpp ~= "" then
    local f=io.open(rpp,"rb")
    if f then
      for line in f:lines() do
        if line:match("^%s*MARKER%s") then
          local id,pos=line:match("^%s*MARKER%s+(%d+)%s+([^%s]+)")
          local guid=line:match("({[%x%-]+})")
          if id and pos and guid then
            for _,region in ipairs(import_regions) do
              if tonumber(id)==tonumber(region.marker_index) and math.abs((tonumber(pos) or -1)-region.start)<0.000001 then region.guid=guid; break end
            end
          end
        end
      end
      f:close()
    end
  end
  if #import_regions > 0 then
    local selected_start,selected_end
    if r.GetSet_LoopTimeRange2 then
      selected_start,selected_end=r.GetSet_LoopTimeRange2(0,false,false,0,0,false)
    end
    local found
    if previous then
      for i,region in ipairs(import_regions) do
        local same_guid=previous.guid and region.guid and previous.guid:upper()==region.guid:upper()
        local same_legacy=not previous.guid and not region.guid and previous.marker_index==region.marker_index and math.abs(previous.start-region.start)<=1/48000
        if same_guid or same_legacy then import_region_index=i; import_region_manual=previous_manual; found=true; break end
      end
    end
    if not found and selected_start and selected_end and selected_end>selected_start then
      for i,region in ipairs(import_regions) do
        if math.abs(region.start-selected_start)<=1/48000 and math.abs(region.ending-selected_end)<=1/48000 then
          import_region_index=i; import_region_manual=false; found=true; break
        end
      end
    end
    if not found then
      for i,region in ipairs(import_regions) do
        if cursor >= region.start and cursor <= region.ending then import_region_index=i; import_region_manual=false; found=true; break end
      end
    end
    if not found then import_region_index=math.min(import_region_index,#import_regions); import_region_manual=false end
  else import_region_index=1; import_region_manual=false end
end

refresh_export_regions = function()
  local previous = export_regions[export_region_index]
  local saved_guid = r.GetExtState(SECTION, "export_region_guid")
  local saved_name = r.GetExtState(SECTION, "export_region_name")
  local saved_start = tonumber(r.GetExtState(SECTION, "export_region_start"))
  export_regions = {}
  local _, marker_count, region_count = r.CountProjectMarkers(0)
  local count = (marker_count or 0) + (region_count or 0)
  for i = 0, count - 1 do
    local retval, is_region, pos, ending, name, idx, region_color = r.EnumProjectMarkers3(0, i)
    if retval and retval > 0 and is_region then
      export_regions[#export_regions + 1] = {name=name or ("Regione " .. tostring(idx)), start=pos, ending=ending, marker_index=idx, color=region_color or 0}
    end
  end
  table.sort(export_regions, function(a,b) return a.start < b.start end)
  if rpp ~= "" then
    local f = io.open(rpp, "rb")
    if f then
      for line in f:lines() do
        if line:match("^%s*MARKER%s") then
          local id, pos = line:match("^%s*MARKER%s+(%d+)%s+([^%s]+)")
          local guid = line:match("({[%x%-]+})")
          if id and pos and guid then
            for _, region in ipairs(export_regions) do
              if tonumber(id) == tonumber(region.marker_index) and math.abs((tonumber(pos) or -1) - region.start) < 0.000001 then
                region.guid = guid
                break
              end
            end
          end
        end
      end
      f:close()
    end
  end
  local chosen
  if previous then
    for i, region in ipairs(export_regions) do
      if (previous.guid and region.guid == previous.guid)
          or (not previous.guid and region.marker_index == previous.marker_index and math.abs(region.start-previous.start)<0.000001) then
        chosen = i
        break
      end
    end
  end
  if not chosen and saved_guid ~= "" then
    for i, region in ipairs(export_regions) do
      if region.guid == saved_guid then chosen = i; break end
    end
  end
  if not chosen and saved_name ~= "" and saved_start then
    for i, region in ipairs(export_regions) do
      if region.name == saved_name and math.abs(region.start-saved_start)<0.000001 then chosen = i; break end
    end
  end
  if not chosen then
    local cursor = r.GetCursorPosition()
    for i, region in ipairs(export_regions) do
      if cursor >= region.start and cursor <= region.ending then chosen = i; break end
    end
  end
  export_region_index = chosen or math.min(export_region_index, math.max(1, #export_regions))
end

local last_reaper_cursor, last_ui_selected_idx
local last_loop_start, last_loop_end
local function selected_region_from_reaper_ui()
  if not (r.GetNumRegionsOrMarkers and r.GetRegionOrMarker and r.GetRegionOrMarkerInfo_Value) then return nil end
  local found
  local count = r.GetNumRegionsOrMarkers(0) or 0
  for i = 0, count - 1 do
    local marker = r.GetRegionOrMarker(0, i, "")
    if marker and (r.GetRegionOrMarkerInfo_Value(0, marker, "B_ISREGION") or 0) > 0.5
        and (r.GetRegionOrMarkerInfo_Value(0, marker, "B_UISEL") or 0) > 0.5 then
      local idx = r.GetRegionOrMarkerInfo_Value(0, marker, "I_NUMBER")
      idx = idx and math.floor(idx + 0.5) or nil
      if idx then
        if found then return nil end -- Se ne sono selezionate più di una, usa time selection/cursore come criterio.
        found = idx
      end
    end
  end
  return found
end

local function sync_export_region_to_reaper()
  if #export_regions == 0 then return end
  local target
  local ui_selected_idx = selected_region_from_reaper_ui()
  local ui_changed = ui_selected_idx ~= last_ui_selected_idx
  last_ui_selected_idx = ui_selected_idx
  local loop_start, loop_end
  if r.GetSet_LoopTimeRange2 then
    local ok, a, b = pcall(r.GetSet_LoopTimeRange2, 0, false, false, 0, 0, false)
    if ok then loop_start, loop_end = a, b end
  elseif r.GetSet_LoopTimeRange then
    local ok, a, b = pcall(r.GetSet_LoopTimeRange, false, false, 0, 0, false)
    if ok then loop_start, loop_end = a, b end
  end
  if loop_start and loop_end and (last_loop_start == nil or math.abs(loop_start-last_loop_start)>0.00001 or math.abs(loop_end-last_loop_end)>0.00001) then
    last_loop_start, last_loop_end = loop_start, loop_end
    for i, region in ipairs(export_regions) do
      if math.abs(loop_start-region.start)<0.00001 and math.abs(loop_end-region.ending)<0.00001 then target=i; break end
    end
  end
  local cursor = r.GetCursorPosition()
  if last_reaper_cursor == nil or math.abs(cursor-last_reaper_cursor) > 0.00001 then
    last_reaper_cursor = cursor
    if r.GetLastMarkerAndCurRegion then
      local ok, _, region_idx = pcall(r.GetLastMarkerAndCurRegion, 0, cursor)
      if ok and region_idx and region_idx >= 0 then
        for i, region in ipairs(export_regions) do
          if region.marker_index == region_idx then target=i; break end
        end
      end
    end
  end
  if ui_changed and ui_selected_idx then
    for i, region in ipairs(export_regions) do
      if region.marker_index == ui_selected_idx then target=i; break end
    end
  end
  if target and target ~= export_region_index then
    export_region_index = target
    local selected = export_regions[target]
    summary, summary_error, completed_zip = nil, nil, nil
    r.SetExtState(SECTION,"export_region_guid",selected.guid or "",true)
    r.SetExtState(SECTION,"export_region_name",selected.name or "",true)
    r.SetExtState(SECTION,"export_region_start",tostring(selected.start),true)
    status_text = "Regione selezionata in REAPER: " .. selected.name
    status_kind = "info"
  end
end

local function sync_import_region_to_reaper()
  if #import_regions == 0 then return end
  local target
  local ui_selected_idx = selected_region_from_reaper_ui()
  local ui_changed = ui_selected_idx ~= import_last_ui_selected_idx
  import_last_ui_selected_idx = ui_selected_idx
  local loop_start, loop_end
  if r.GetSet_LoopTimeRange2 then
    local ok, a, b = pcall(r.GetSet_LoopTimeRange2, 0, false, false, 0, 0, false)
    if ok then loop_start, loop_end = a, b end
  elseif r.GetSet_LoopTimeRange then
    local ok, a, b = pcall(r.GetSet_LoopTimeRange, false, false, 0, 0, false)
    if ok then loop_start, loop_end = a, b end
  end
  if loop_start and loop_end and (import_last_loop_start == nil or math.abs(loop_start-import_last_loop_start)>0.00001 or math.abs(loop_end-import_last_loop_end)>0.00001) then
    import_last_loop_start, import_last_loop_end = loop_start, loop_end
    for i, region in ipairs(import_regions) do
      if math.abs(loop_start-region.start)<0.00001 and math.abs(loop_end-region.ending)<0.00001 then target=i; break end
    end
  end
  local cursor = r.GetCursorPosition()
  if import_last_reaper_cursor == nil or math.abs(cursor-import_last_reaper_cursor)>0.00001 then
    import_last_reaper_cursor = cursor
    if r.GetLastMarkerAndCurRegion then
      local ok, _, region_idx = pcall(r.GetLastMarkerAndCurRegion, 0, cursor)
      if ok and region_idx and region_idx >= 0 then
        for i, region in ipairs(import_regions) do
          if region.marker_index == region_idx then target=i; break end
        end
      end
    end
  end
  if ui_changed and ui_selected_idx then
    for i, region in ipairs(import_regions) do
      if region.marker_index == ui_selected_idx then target=i; break end
    end
  end
  if target and target ~= import_region_index then
    import_region_index = target
    import_region_manual = false
    import_plan = nil
    local selected = import_regions[target]
    import_status_text = "Regione selezionata in REAPER: " .. selected.name .. ". Ricontrolla la consegna."
    import_status_kind = "info"
  end
end

local function choose_import_delivery()
  -- Il menu si apre a gfx.x/gfx.y: lo si mette subito sotto il pulsante «Scegli consegna…».
  for _, b in ipairs(buttons) do
    if b.id=="delivery" then gfx.x,gfx.y=math.floor(b.x),math.floor(b.y+b.h+2) end
  end
  local choice=gfx.showmenu("ZIP di ritorno|Cartella con consegna.json")
  if choice==0 then return end
  local ok,selected
  if choice==1 then
    ok,selected=r.GetUserFileName(1,"Scegli lo ZIP di ritorno","", "ZIP di ritorno|*.zip")
  elseif choice==2 then
    ok,selected=r.GetUserFileName(3,"Scegli la cartella che contiene consegna.json",import_delivery,"")
  end
  if not ok then return end
  if not selected or selected=="" then
    import_status_text,import_status_kind="Selezione annullata.","info"
    return
  end
  selected=selected:gsub("[/\\]+$","")
  if selected:lower():match("%.zip$") then
    if not r.file_exists(selected) then
      import_status_text,import_status_kind="Lo ZIP selezionato non esiste o non è leggibile.","error"
      return
    end
  elseif r.file_exists(join(selected,"manifest.json")) and not r.file_exists(join(selected,"consegna.json")) then
    import_status_text,import_status_kind="Questa è la cartella del pacchetto di partenza. Scegli lo ZIP di ritorno oppure la cartella con consegna.json.","error"
    return
  elseif not r.file_exists(join(selected,"consegna.json")) then
    import_status_text,import_status_kind="Scegli uno ZIP di ritorno oppure una cartella che contenga consegna.json e i WAV.","error"
    return
  end
  import_delivery=selected
  r.SetExtState(SECTION,"import_consegna",import_delivery,true)
  import_plan=nil
  local kind=selected:lower():match("%.zip$") and "ZIP di ritorno" or "Cartella consegna"
  import_status_text,import_status_kind=kind.." selezionata. Premi Controlla consegna.","info"
end

local function choose_import_zip()
  local ok,selected = r.GetUserFileNameForRead(import_zip,"Scegli il pacchetto di partenza inviato al doppiatore","zip")
  if ok and selected and selected ~= "" then
    import_zip=selected
    r.SetExtState(SECTION,"import_zip",import_zip,true)
    import_plan=nil
    import_status_text,import_status_kind="Pacchetto di partenza selezionato.","info"
  end
end

start_import_preflight = function()
  import_plan=nil
  refresh_project_info()
  refresh_import_regions()
  if rpp == "" then import_status_text,import_status_kind="Salva prima il progetto REAPER.","error"; return end
  if not python then import_status_text,import_status_kind="Non trovo Python 3.","error"; return end
  local preflight_script=join(script_dir,"zp_remote_preflight.py")
  if not r.file_exists(preflight_script) then import_status_text,import_status_kind="Non trovo zp_remote_preflight.py accanto all’azione.","error"; return end
  if import_delivery == "" then import_status_text,import_status_kind="Scegli lo ZIP di ritorno o la cartella estratta.","error"; return end
  local region=import_regions[import_region_index]
  local resource=r.GetResourcePath()
  local preflight_dir=join(resource,"ZP Remote/Preflight")
  r.RecursiveCreateDirectory(preflight_dir,0)
  local nonce=r.genGuid(""):gsub("[^%x]","")
  import_plan_path=join(preflight_dir,"piano_"..nonce..".json")
  import_status_file=join(preflight_dir,"stato_"..nonce..".json")
  os.remove(import_plan_path); os.remove(import_status_file)
  local args={quote(preflight_script),"--consegna",quote(import_delivery),"--progetto",quote(rpp),"--output",quote(import_plan_path),"--status-file",quote(import_status_file),"--allow-unanchored"}
  if import_zip ~= "" then
    args[#args+1]="--pacchetto"
    args[#args+1]=quote(import_zip)
  end
  if region then
    args[#args+1]=region.guid and "--region-guid" or "--region-name"
    args[#args+1]=quote(region.guid or region.name)
  end
  local selected=r.GetSelectedMediaItem(0,0)
  if selected then
    local take=r.GetActiveTake(selected)
    local source=take and r.GetMediaItemTake_Source(take)
    local kind=source and r.GetMediaSourceType(source,"") or ""
    args[#args+1]="--selected-item-type"
    args[#args+1]=quote(kind)
    if kind=="VIDEO" then
      local media=r.GetMediaSourceFileName(source,"")
      args[#args+1]="--selected-item-start"
      args[#args+1]=tostring(r.GetMediaItemInfo_Value(selected,"D_POSITION"))
      args[#args+1]="--selected-item-file"
      args[#args+1]=quote(media)
    end
  end
  r.ExecProcess(command(args),-1)
  import_plan=nil
  import_busy=true
  import_started_at=os.time()
  import_status_text="Controllo consegna, ZIP, WAV e regione in corso…"
  import_status_kind="working"
end

local function poll_import_preflight()
  if not import_busy or not import_status_file then return end
  local result=read_json(import_status_file)
  if result and result.stato == "in_corso" then return end
  if result and result.stato == "completato" then
    import_busy=false
    import_plan=read_json(import_plan_path)
    if import_plan then
      local c=import_plan.counts or {}
      import_status_text=("Controllo completato · %s WAV · %s item · %s personaggi · regione %s"):format(c.files or 0,c.items or 0,(function() local n=0; for _ in pairs(c.characters or {}) do n=n+1 end; return n end)(),import_plan.region and import_plan.region.name or "")
      import_status_kind="ok"
      local placement=import_plan.placement
      if placement and placement.mode=="cursor" then
        import_status_text="Prima take al cursore, su nuove tracce. "..placement.reason.."."
      end
      if result.warnings and #result.warnings>0 then import_status_text=import_status_text..(" · %d avvisi"):format(#result.warnings) end
    else import_status_text,import_status_kind="Il preflight non ha prodotto il piano d’importazione.","error" end
    os.remove(import_status_file)
  elseif result and result.stato == "errore" then
    import_busy=false
    import_status_text=tostring(result.messaggio or "Controllo non riuscito."):gsub("\n"," ")
    import_status_kind="error"
    os.remove(import_status_file)
  elseif os.time()-(import_started_at or os.time()) > 120 then
    import_busy=false
    import_status_text="Il controllo non ha risposto. Verifica Python e riprova."
    import_status_kind="error"
    os.remove(import_status_file)
  end
end

local function run_import()
  if import_busy or not import_plan then return end
  refresh_project_info()
  if rpp == "" or r.IsProjectDirty(0)>0 then
    import_status_text="Salva il progetto e rifai il controllo prima di importare."
    import_status_kind="info"
    import_plan=nil
    return
  end
  local importer_path=join(script_dir,"zp_remote_importer.lua")
  local imported,importer=pcall(dofile,importer_path)
  if not imported or type(importer)~="table" or type(importer.run)~="function" then
    import_status_text="Non riesco a caricare il modulo d’importazione: "..tostring(importer)
    import_status_kind="error"
    return
  end
  import_busy=true
  import_status_kind="working"
  local ok,result=importer.run({
    plan_path=import_plan_path,
    confirm=function(message)
      local placement=import_plan.placement
      return not placement or placement.mode~="cursor" or r.MB(message,"ZP Remote — importa al cursore",1)==1
    end,
    onProgress=function(message)
      import_status_text=tostring(message):gsub("\n"," · ")
      buttons={}
      gfx.set(0,0,0,1); gfx.rect(0,0,gfx.w,gfx.h,1); rect(0,0,gfx.w,gfx.h,C.bg)
      rect(0,0,gfx.w,74,C.panel); label(28,12,"ZP REMOTE",C.accent,"Arial",15); label(28,35,"Importa consegna",C.text,"Arial",25)
      rect(20,204,720,284,C.panel,7)
      label(38,228,"IMPORTAZIONE IN CORSO",C.sub,"Arial",14)
      wrapped_label(38,270,import_status_text,C.text,"Arial",17,670,7)
      gfx.update()
    end
  })
  import_busy=false
  if not ok then
    import_status_text=tostring(result):gsub("\n"," · ")
    import_status_kind="error"
    import_plan=nil
  elseif result then
    import_status_text=tostring(result.message or "Importazione completata."):gsub("\n"," · ")
    import_status_kind="ok"
    import_plan=nil
  else
    import_status_text="Importazione annullata. Il progetto non è stato modificato."
    import_status_kind="info"
  end
end

local function focus_revealed_folder(directory, deadline)
  local folder_name = directory:match("([^/\\]+)$")
  if folder_name and r.JS_Window_FindTop and r.JS_Window_SetForeground then
    local hwnd = r.JS_Window_FindTop(folder_name, false)
    if hwnd then
      pcall(r.JS_Window_SetForeground, hwnd)
      return
    end
  end
  if r.time_precise and r.time_precise() < deadline then
    r.defer(function() focus_revealed_folder(directory, deadline) end)
  end
end

local function reveal_package(path)
  local osname = r.GetOS()
  local directory = path:match("^(.*)[/\\][^/\\]+$") or path
  local cmd
  if osname:match("^Win") then
    cmd = "explorer " .. quote(directory)
  elseif osname:find("OSX", 1, true) then
    -- open -R mostra la cartella che contiene lo ZIP; JS_ReaScriptAPI porta Finder davanti a REAPER.
    cmd = "/usr/bin/open -R " .. quote(path)
  else
    cmd = "xdg-open " .. quote(directory)
  end
  local result = r.ExecProcess(cmd, 3000)
  local exit_code = result and tonumber(result:match("^%s*(-?%d+)"))
  if exit_code and exit_code ~= 0 then
    status_text, status_kind = "Non riesco ad aprire la cartella del pacchetto: " .. directory, "error"
  else
    if osname:find("OSX", 1, true) and r.JS_Window_FindTop and r.JS_Window_SetForeground and r.time_precise then
      r.defer(function() focus_revealed_folder(directory, r.time_precise() + 2) end)
    end
    status_text, status_kind = "Cartella del pacchetto mostrata in Finder.", "ok"
  end
end

-- Palette ZP Remote ad alto contrasto. La scala aumenta insieme finestra, testi e controlli.
local UI_SCALE = 1.25
 C = {bg={23,24,29}, panel={34,36,45}, line={74,106,138}, text={245,246,250}, sub={193,199,211}, accent={155,76,49}, green={88,205,139}, red={255,145,135}, error_panel={67,34,37}, button={48,51,61}, button_border={116,126,145}, shadow={12,13,17}, accent_border={230,151,111}}
local function scaled(v) return v * UI_SCALE end
local function color(c) gfx.set(c[1]/255, c[2]/255, c[3]/255, 1) end
rect = function(x,y,w,h,c,round)
  x,y,w,h=scaled(x),scaled(y),scaled(w),scaled(h)
  color(c); if round and gfx.roundrect then gfx.roundrect(x,y,w,h,scaled(round),1) else gfx.rect(x,y,w,h,1) end
end
label = function(x,y,s,c,font,size)
  color(c); gfx.setfont(1, font or "Arial", scaled(size or 16)); gfx.x,gfx.y=scaled(x),scaled(y); gfx.drawstr(tostring(s or ""))
end
wrapped_label = function(x,y,s,c,font,size,width,max_lines)
  color(c); gfx.setfont(1, font or "Arial", scaled(size or 14))
  local lines, line = {}, ""
  for word in tostring(s or ""):gmatch("%S+") do
    local candidate = line == "" and word or (line .. " " .. word)
    if line ~= "" and gfx.measurestr(candidate) > scaled(width) then lines[#lines+1]=line; line=word else line=candidate end
  end
  if line ~= "" then lines[#lines+1]=line end
  for i=1, math.min(#lines, max_lines or #lines) do
    gfx.x,gfx.y=scaled(x),scaled(y+(i-1)*21); gfx.drawstr(lines[i])
  end
end
local function folder_label(path)
  local max_width = scaled(550)
  gfx.setfont(1, "Arial", scaled(18))
  if gfx.measurestr(path) <= max_width then return path end
  local tail = path:match("([^/\\]+)$") or path
  return "…/" .. tail
end
buttons = {}
local mouse_was_down = false
local function button(id, text, x,y,w,h, primary, disabled)
  local fill = primary and C.accent or C.button
  local edge = primary and C.accent_border or C.button_border
  if disabled then fill,edge = {55,56,62},{83,86,94} end
  rect(x,y+2,w,h,C.shadow,7)
  rect(x,y,w,h,fill,7)
  color(edge); gfx.roundrect(scaled(x),scaled(y),scaled(w),scaled(h),scaled(7),0)
  label(x+16,y+8,text,disabled and C.sub or C.text,"Arial",19)
  buttons[#buttons+1] = {id=id,x=scaled(x),y=scaled(y),w=scaled(w),h=scaled(h),disabled=disabled}
end
local function click(id)
  if gfx.mouse_cap & 1 == 0 or mouse_was_down then return false end
  for _, b in ipairs(buttons) do
    if b.id == id and not b.disabled and gfx.mouse_x >= b.x and gfx.mouse_x <= b.x+b.w and gfx.mouse_y >= b.y and gfx.mouse_y <= b.y+b.h then return true end
  end
  return false
end

refresh_export_regions()
gfx.init(TITLE, math.floor(760*UI_SCALE), math.floor(600*UI_SCALE), 0)
local header_icon = gfx.loadimg(0, join(join(script_dir, "assets"), "zp_remote_pacchetto.png"))
local header_icon_width, header_icon_height = 0, 0
if header_icon >= 0 then
  header_icon_width, header_icon_height = gfx.getimgdim(header_icon)
end
local has_header_icon = header_icon_width > 0 and header_icon_height > 0
gfx.setfont(1, "Arial", scaled(16))
local function frame()
  poll_export()
  poll_import_preflight()
  if not busy and not pending_save_action then
    if view == "export" then sync_export_region_to_reaper()
    elseif not import_busy then sync_import_region_to_reaper() end
  end
  if busy then
    local now = r.time_precise and r.time_precise() or os.time()
    local elapsed = math.max(0, math.floor(now - (started_precise or started_at or now)))
    local hours = math.floor(elapsed / 3600)
    local minutes = math.floor((elapsed % 3600) / 60)
    local seconds = elapsed % 60
    local timer = hours > 0 and ("%d:%02d:%02d"):format(hours, minutes, seconds) or ("%02d:%02d"):format(minutes, seconds)
    local dots = string.rep("·", math.floor(now * 2) % 4)
    local activity = export_running and "Sto preparando video, audio guida e ZIP" or "Avvio dell'esportatore"
    status_text = activity .. dots .. " · tempo trascorso " .. timer .. ". L'attesa varia con durata e peso del video."
    status_kind = "working"
  end
  buttons = {}
  gfx.set(0,0,0,1); gfx.rect(0,0,gfx.w,gfx.h,1)
  rect(0,0,gfx.w,gfx.h,C.bg)
  rect(0,0,gfx.w,74,C.panel)
  local title_x = 28
  if has_header_icon then
    gfx.blit(header_icon, 1, 0, 0, 0, header_icon_width, header_icon_height,
      scaled(24), scaled(15), scaled(44), scaled(44))
    title_x = 76
  end
  label(title_x,12,"ZP REMOTE",C.accent,"Arial",15)
  label(title_x,35,view == "export" and "Esporta progetto" or "Importa consegna",C.text,"Arial",25)
  button("tab_export","Esporta",330,18,112,40,view == "export",busy or import_busy)
  button("tab_import","Importa",450,18,112,40,view == "import",busy or import_busy)
  button("help","?",596,15,44,44,false,busy or import_busy)
  label(24,92,project_name,C.text,"Arial",21)
  label(24,122,view == "export" and "Video, battute e anelli per il doppiaggio remoto" or "Controlla una consegna e importa le registrazioni",C.sub,"Arial",17)
  local id = project_identity()
  if id then
    label(24,153,"ID ZP Remote: " .. id,C.text,"Arial",16)
    label(24,177,"Passaggio 1 completato · identifica il progetto e abbina le consegne.",C.sub,"Arial",14)
  else
    label(24,153,"ID ZP Remote: da assegnare",C.text,"Arial",16)
    label(24,177,"Generalo dal passaggio 1; l'ID resterà nel progetto e nei pacchetti.",C.sub,"Arial",14)
  end
  if view == "import" then
    rect(20,204,720,94,C.panel,7)
    label(38,216,"CONSEGNA DI RITORNO",C.sub,"Arial",13)
    local delivery_label="Scegli uno ZIP di ritorno oppure la cartella con consegna.json"
    if import_delivery~="" then
      local kind=import_delivery:lower():match("%.zip$") and "ZIP di ritorno" or "Cartella consegna"
      delivery_label=kind.." · "..folder_label(import_delivery)
    end
    wrapped_label(38,241,delivery_label,C.text,"Arial",15,478,1)
    wrapped_label(38,273,"ZIP di partenza (serve per riallineare un’altra copia) · "..(import_zip~="" and folder_label(import_zip) or "non selezionato"),C.text,"Arial",15,478,1)
    button("delivery","Scegli consegna…",546,225,176,36,false,import_busy)
    button("package_zip","ZIP di partenza…",546,264,176,34,false,import_busy)
    rect(20,316,720,172,C.panel,7)
    label(38,332,"REGIONE E ANTEPRIMA",C.sub,"Arial",13)
    local selected=import_regions[import_region_index]
    button("region_prev","‹",38,360,48,42,false,import_busy or #import_regions<2)
    local region_text=selected and (selected.name..(" · %.2f–%.2f s"):format(selected.start,selected.ending)) or "Nessuna regione nel progetto"
    wrapped_label(98,369,region_text,C.text,"Arial",18,500,1)
    button("region_next","›",654,360,48,42,false,import_busy or #import_regions<2)
    if import_plan then
      local c=import_plan.counts or {}
      label(38,420,("Piano: %s WAV · %s item · %s fuori traccia"):format(c.files or 0,c.items or 0,c.fuori_traccia or 0),C.text,"Arial",17)
      local chars={}; for name,n in pairs(c.characters or {}) do chars[#chars+1]=tostring(name).." ("..tostring(n)..")" end; table.sort(chars)
      wrapped_label(38,451,"Personaggi: "..(#chars>0 and table.concat(chars,", ") or "nessuno"),C.sub,"Arial",15,680,2)
    elseif import_status_kind == "error" and import_status_text ~= "" then
      rect(30,414,700,70,C.error_panel,6)
      wrapped_label(42,422,import_status_text,C.red,"Arial",17,660,3)
    else
      label(38,421,"La consegna può essere una cartella o uno ZIP di ritorno.",C.sub,"Arial",16)
      label(38,451,"Nello stesso progetto i tempi BWF agganciano le take alla regione.",C.sub,"Arial",15)
    end
    local stat_color=import_status_kind=="error" and C.red or (import_status_kind=="ok" and C.green or C.sub)
    wrapped_label(24,501,import_status_text,stat_color,"Arial",15,710,2)
    if pending_save_action=="import_check" then
      button("save_continue","Salva progetto e controlla",24,544,290,44,true,import_busy)
      button("cancel_save","Annulla",322,544,120,44,false,import_busy)
    else
      button("import_check",import_busy and "Controllo in corso…" or "Controlla consegna",24,544,250,44,false,import_busy or import_delivery=="")
    end
    local placement=import_plan and import_plan.placement
    local import_label=placement and placement.mode=="cursor" and "Importa al cursore" or "Importa nel progetto"
    button("import_run",import_label,486,544,236,44,true,import_busy or not import_plan)
  else
  rect(20,204,720,64,C.panel,7)
  label(38,213,"CARTELLA DI DESTINAZIONE",C.sub,"Arial",13)
  label(38,236,folder_label(folder),C.text,"Arial",17)
  button("browse","Scegli…",624,214,98,42,false,busy)
  rect(20,278,720,72,C.panel,7)
  label(38,287,"POSTER DEL PACCHETTO",C.sub,"Arial",13)
  local poster_label = poster_jpg ~= "" and folder_label(poster_jpg) or "Fotogramma del video dentro la regione"
  wrapped_label(38,310,poster_label,C.text,"Arial",14,420,1)
  button("poster_video","Video",496,294,100,40,false,busy)
  button("poster_jpg","Scegli JPG…",606,294,116,40,false,busy)
  local selected_region = export_regions[export_region_index]
  if selected_region and selected_region.color and selected_region.color ~= 0 and r.ColorFromNative then
    local cr,cg,cb = r.ColorFromNative(selected_region.color)
    rect(20,360,720,128,{cr,cg,cb},7)
    rect(23,363,714,122,C.panel,6)
  else
    rect(20,360,720,128,C.panel,7)
  end
  if recovery_mode then
    label(38,371,"PASSAGGIO 1 · RECUPERA L'ID DEL PROGETTO",C.sub,"Arial",13)
    label(38,393,"Incolla project.guid dal vecchio pacchetto (⌘V / Ctrl+V):",C.text,"Arial",15)
    rect(38,412,680,34,input_focus and C.line or C.bg,5)
    label(52,420,recovery_value ~= "" and recovery_value or "{ID del progetto}",recovery_value ~= "" and C.text or C.sub,"Arial",16)
    button("save_id","Salva ID",38,451,160,34,true,busy or pending_save_action ~= nil)
    button("cancel_recovery","Indietro",214,451,150,34,false,busy)
  elseif not id then
    label(38,371,"PASSAGGIO 1 · IDENTITÀ PROGETTO",C.sub,"Arial",13)
    label(38,396,"ID non trovato. Se è un progetto nuovo, genera l'ID qui.",C.text,"Arial",16)
    wrapped_label(38,421,"Se hai già inviato un pacchetto, recupera il suo ID invece di crearne uno nuovo.",C.sub,"Arial",14,680,2)
    button("generate_id","Genera ID",38,451,190,34,true,busy or pending_save_action ~= nil)
    button("recover_mode","Ho già un ID",246,451,190,34,false,busy or pending_save_action ~= nil)
  elseif summary then
    label(38,371,"REGIONE DA ESPORTARE · CONTROLLO COMPLETATO",C.green,"Arial",13)
    local selected=export_regions[export_region_index]
    button("export_region_prev","‹",38,389,42,34,false,busy or #export_regions<2)
    wrapped_label(92,396,selected and (selected.name..(" · %.2f–%.2f s"):format(selected.start,selected.ending)) or "Nessuna regione REAPER",C.text,"Arial",17,520,1)
    button("export_region_next","›",678,389,42,34,false,busy or #export_regions<2)
    label(38,431,"Video: " .. summary.video .. " · " .. summary.durata_s .. " secondi",C.text,"Arial",16)
    wrapped_label(38,452,"Personaggi: " .. table.concat(summary.personaggi or {}, ", "),C.text,"Arial",15,680,1)
    label(38,474,"Anelli: " .. summary.anelli_marker .. " · Battute: " .. summary.battute .. " · Note: " .. summary.note,C.text,"Arial",14)
  else
    label(38,371,"PASSAGGIO 2 · SCEGLI LA REGIONE E CONTROLLA",C.sub,"Arial",13)
    local selected=export_regions[export_region_index]
    button("export_region_prev","‹",38,389,42,34,false,busy or #export_regions<2)
    wrapped_label(92,396,selected and (selected.name..(" · %.2f–%.2f s"):format(selected.start,selected.ending)) or "Nessuna regione REAPER",C.text,"Arial",17,520,1)
    button("export_region_next","›",678,389,42,34,false,busy or #export_regions<2)
    if summary_error then
      rect(30,427,700,61,C.error_panel,6)
      wrapped_label(42,430,summary_error,C.red,"Arial",16,660,3)
    else
      label(38,433,"L'esportazione usa solo il video e i contenuti dentro la regione.",C.sub,"Arial",16)
    end
  end
  local stat_color = status_kind == "error" and C.red or (status_kind == "ok" and C.green or C.sub)
  if status_kind == "error" then rect(20,493,720,46,C.error_panel,6) end
  wrapped_label(24,501,status_text,stat_color,"Arial",17,710,2)
  if pending_save_action then
    local save_label = pending_save_action == "generate" and "Salva progetto e genera ID"
      or pending_save_action == "recover" and "Salva progetto e collega ID"
      or pending_save_action == "export" and "Salva progetto e crea pacchetto"
      or "Salva progetto e continua"
    button("save_continue",save_label,24,544,420,44,true,busy)
    button("cancel_save","Annulla",458,544,130,44,false,busy)
  else
    button("check","2. Controlla",24,544,170,44,false,busy or not id)
    if completed_zip then
      button("open","4. Apri cartella",486,544,236,44,true,busy)
    else
      button("create",busy and "Preparazione in corso…" or "3. Crea pacchetto",486,544,236,44,true,busy or not summary or not id)
    end
  end
  end
  button("close","Chiudi",650,15,96,44,false,busy or import_busy)
  gfx.update()

  local mouse_pressed = (gfx.mouse_cap & 1) ~= 0 and not mouse_was_down
  if recovery_mode and mouse_pressed and gfx.mouse_x >= scaled(38) and gfx.mouse_x <= scaled(718) and gfx.mouse_y >= scaled(412) and gfx.mouse_y <= scaled(446) then
    input_focus = true
  elseif mouse_pressed then
    input_focus = false
  end
  if click("tab_export") then view="export" end
  if click("tab_import") then view="import"; refresh_import_regions() end
  if click("help") then r.ShowMessageBox(HELP, "ZP Remote · Aiuto", 0) end
  if click("browse") then choose_folder() end
  if click("poster_jpg") then choose_poster_jpg() end
  if click("poster_video") then
    poster_jpg = ""
    status_text, status_kind = "Userò il fotogramma video nella regione, vicino al cursore REAPER, ritagliato a 640×360.", "info"
  end
  if click("delivery") then choose_import_delivery() end
  if click("package_zip") then choose_import_zip() end
  if click("region_prev") then import_region_index=math.max(1,import_region_index-1); import_region_manual=true; import_plan=nil; import_status_text="Regione cambiata: ricontrolla la consegna."; import_status_kind="info" end
  if click("region_next") then import_region_index=math.min(#import_regions,import_region_index+1); import_region_manual=true; import_plan=nil; import_status_text="Regione cambiata: ricontrolla la consegna."; import_status_kind="info" end
  if click("export_region_prev") then
    export_region_index=math.max(1,export_region_index-1); summary=nil; summary_error=nil; completed_zip=nil
    local selected=export_regions[export_region_index]
    if selected then r.SetExtState(SECTION,"export_region_guid",selected.guid or "",true); r.SetExtState(SECTION,"export_region_name",selected.name or "",true); r.SetExtState(SECTION,"export_region_start",tostring(selected.start),true) end
    status_text="Regione cambiata. Controlla di nuovo prima di creare il pacchetto."; status_kind="info"
  end
  if click("export_region_next") then
    export_region_index=math.min(#export_regions,export_region_index+1); summary=nil; summary_error=nil; completed_zip=nil
    local selected=export_regions[export_region_index]
    if selected then r.SetExtState(SECTION,"export_region_guid",selected.guid or "",true); r.SetExtState(SECTION,"export_region_name",selected.name or "",true); r.SetExtState(SECTION,"export_region_start",tostring(selected.start),true) end
    status_text="Regione cambiata. Controlla di nuovo prima di creare il pacchetto."; status_kind="info"
  end
  if click("import_check") then if not import_busy then if request_save("import_check") then start_import_preflight() end end end
  if click("import_run") then run_import() end
  if click("generate_id") then generate_identity() end
  if click("recover_mode") then recovery_mode, recovery_value, input_focus = true, "", true end
  if click("save_id") then recover_identity() end
  if click("cancel_recovery") then recovery_mode, recovery_value, input_focus = false, "", false end
  if click("check") then check_project() end
  if click("create") then start_export() end
  if click("open") and completed_zip then reveal_package(completed_zip) end
  if click("save_continue") then save_and_continue() end
  if click("cancel_save") then
    pending_save_action = nil
    status_text, status_kind = "Salvataggio annullato.", "info"
    if view=="import" then import_status_text,import_status_kind=status_text,status_kind end
  end
  if click("close") then gfx.quit(); return end
  local ch = gfx.getchar()
  if recovery_mode and input_focus and ch > 0 then
    if ch == 8 or ch == 127 then
      recovery_value = recovery_value:sub(1, -2)
    elseif ch == 13 then
      recover_identity()
    elseif ch == 22 and r.CF_GetClipboard then
      local _, clip = r.CF_GetClipboard("")
      if clip then recovery_value = tostring(clip):gsub("[%c%s\"]", "") end
    elseif ch >= 32 and ch <= 126 and #recovery_value < 40 then
      local char = string.char(ch)
      if char:match("[%x{}%-]") then recovery_value = recovery_value .. char end
    end
  elseif ch == 27 or ch == -1 then
    gfx.quit(); return
  end
  mouse_was_down = (gfx.mouse_cap & 1) ~= 0
  r.defer(frame)
end
r.defer(frame)
