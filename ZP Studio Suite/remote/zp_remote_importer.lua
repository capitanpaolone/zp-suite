-- @noindex
-- Importatore generale ZP Remote: solo aggiunte, ripetibile e non distruttivo.
-- Provenienza ZP:
--   Proprietà: ZP Remote / importatore.
--   Pacchetto d’origine: installazione locale inclusa nel ramo beta della Suite 2.6.6.
--   Copia locale REAPER acquisita il 2026-11-09; preparazione Suite 2.6.7.
--   Versione interna: non dichiarata separatamente; helper incluso nel pacchetto.

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("^(.*[/\\])") or ""
local json = dofile(script_dir .. "zp_remote_json.lua")
local logic = dofile(script_dir .. "zp_remote_import_logic.lua")
local r = reaper
local M = {}

local function die(msg) error(msg, 0) end
local function read_file(path)
  local f, err = io.open(path, "rb"); if not f then die("Lettura impossibile: " .. tostring(err)) end
  local d = f:read("*a"); f:close(); return d
end
local function read_json(path)
  local ok, obj = pcall(json.decode, read_file(path))
  if not ok or type(obj) ~= "table" then die("JSON non valido: " .. path .. " — " .. tostring(obj)) end
  return obj
end
local function write_copy(src, dst)
  local input, err = io.open(src, "rb"); if not input then die("WAV non leggibile: " .. src .. " (" .. tostring(err) .. ")") end
  local tmp = dst .. ".part-" .. tostring(os.time()) .. "-" .. tostring(math.random(1000,9999))
  local output, e = io.open(tmp, "wb"); if not output then input:close(); die("Non posso creare il WAV temporaneo: " .. tostring(e)) end
  while true do
    local block = input:read(1024*1024); if not block then break end
    local ok, we = output:write(block)
    if not ok then input:close(); output:close(); os.remove(tmp); die("Errore scrittura media: " .. tostring(we)) end
  end
  input:close()
  local closed, ce = output:close()
  if closed == nil then os.remove(tmp); die("Chiusura WAV temporaneo fallita: " .. tostring(ce)) end
  local ok, re = os.rename(tmp, dst); if not ok then os.remove(tmp); die("Non posso finalizzare il WAV copiato: " .. tostring(re)) end
end
local function shell_quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function digest(path)
  local p = io.popen("shasum -a 256 " .. shell_quote(path) .. " 2>/dev/null", "r")
  if not p then die("Non riesco ad avviare shasum per verificare gli hash.") end
  local line = p:read("*l"); local ok = p:close()
  local hex = line and line:match("^([0-9a-fA-F]+)")
  if not ok or not hex then die("shasum non disponibile o errore di lettura hash per: " .. path) end
  return hex:lower()
end
local function expect_hash(path, expected)
  if digest(path) ~= tostring(expected or ""):lower() then die("SHA-256 non coerente: " .. path) end
end
local function dirname(path) return path:match("^(.*)[/\\][^/\\]*$") or "." end
local function basename(path) return path:match("([^/\\]+)$") or path end
local function path_join(a,b) return a:gsub("[/\\]+$","") .. "/" .. b end
local function same(a,b,tol) return math.abs(tonumber(a or 0)-tonumber(b or 0)) <= (tol or 1/48000) end
local function setstr(fn, obj, key, value)
  local ok = fn(obj,key,value,true); if not ok then die("REAPER non accetta il campo " .. key) end
end
local function project_file()
  local _, file = r.EnumProjects(-1, "")
  if not file or file == "" then die("Salva il progetto REAPER prima di importare.") end
  return file
end
local function project_region(plan)
  local _, markers, regions = r.CountProjectMarkers(0)
  local found, wanted = {}, tostring(plan.region.guid or ""):upper()
  for i=0,markers+regions-1 do
    local ok,isrgn,pos,fin,name,idx,color,guid = r.EnumProjectMarkers3(0,i)
    if ok and ok > 0 and isrgn then
      if not guid and r.GetRegionOrMarker and r.GetSetRegionOrMarkerInfo_String then
        local marker = r.GetRegionOrMarker(0,i,"")
        if marker then
          local _, value = r.GetSetRegionOrMarkerInfo_String(0,marker,"GUID","",false)
          guid = value
        end
      elseif not guid and r.GetSetProjectInfo_String then
        local _, value = r.GetSetProjectInfo_String(0,"MARKER_GUID:"..i,"",false)
        guid = value
      end
      if wanted ~= "" and tostring(guid or ""):upper() == wanted then
        found[#found+1] = {start=pos,finish=fin,name=name,guid=guid}
      elseif wanted == "" and name == plan.region.name then
        found[#found+1] = {start=pos,finish=fin,name=name,guid=guid}
      end
    end
  end
  if #found ~= 1 then die("La regione del piano non corrisponde a una regione unica nel progetto aperto.") end
  local x = found[1]
  if not same(x.start,plan.region.start_s) or not same(x.finish,plan.region.end_s) then die("I limiti della regione sono diversi dal piano oltre un campione.") end
  if plan.region.name and x.name ~= plan.region.name then die("La regione con quel GUID ha un nome diverso da quello del piano.") end
  return x
end
local function get_track_ext(track,key)
  local _, value = r.GetSetMediaTrackInfo_String(track,key,"",false); return value or ""
end
local function get_item_ext(item,key)
  local _, value = r.GetSetMediaItemInfo_String(item,key,"",false); return value or ""
end
local function hex(s)
  return (tostring(s or ""):gsub(".",function(c) return ("%02X"):format(c:byte()) end))
end
local function unhex(s)
  if #s%2 ~= 0 or s:find("[^%x]") then return nil end
  return (s:gsub("..",function(pair) return string.char(tonumber(pair,16)) end))
end
local function parse_item_tag(value)
  local key, hash, filename = value:match("^ZPR2|([%x]+)|([%x]+)|([%x]*)$")
  if key then return {key=unhex(key),hash=hash:lower(),file=unhex(filename),legacy_key=value} end
  local old_hash = value:match("^[^/]+/([%x]+)/%d+$") or value:match("^[^:]+:([%x]+):%d+$")
  return {legacy_key=value,hash=old_hash and old_hash:lower() or nil}
end
local function item_tag(key,hash,filename)
  return "ZPR2|" .. hex(key) .. "|" .. tostring(hash):lower() .. "|" .. hex(filename)
end
local function collect_state(plan, batch_prefix)
  local state = {items={},characters={},p_lane_counts={}}
  local name_candidates = {}
  for ti=0,r.CountTracks(0)-1 do
    local track = r.GetTrack(0,ti)
    local _, name = r.GetSetMediaTrackInfo_String(track,"P_NAME","",false)
    local raw_id = get_track_ext(track,"P_EXT:ZP_REMOTE_CHARACTER")
    local id = raw_id ~= "" and logic.canonico(raw_id,"pers") or ""
    if not batch_prefix and raw_id ~= "" and not id then die("character_id REAPER non valido o di tipo diverso sulla traccia "..tostring(name)) end
    local batch_track = false
    if batch_prefix then
      local tag = get_track_ext(track,"P_EXT:ZP_REMOTE_IMPORT")
      batch_track = tag:sub(1,#batch_prefix) == batch_prefix
      if batch_track then
        local key = tag:sub(#batch_prefix+1)
        if state.characters[key] then die("Più tracce appartengono allo stesso personaggio di questo lotto.") end
        state.characters[key] = track
      end
    elseif id ~= "" then
      local ck="id:"..id
      if state.characters[ck] then die("Il progetto contiene più tracce per lo stesso character_id; import bloccato.") end
      state.characters[ck]=track
    end
    local normalized=logic.normalize_name(name)
    if not batch_prefix and normalized~="" and id=="" then
      name_candidates[normalized]=name_candidates[normalized] or {}
      name_candidates[normalized][#name_candidates[normalized]+1]={track=track,id=id}
    end
    local lane_count = r.GetMediaTrackInfo_Value(track,"I_NUMFIXEDLANES") or 0
    local p_count=tonumber(get_track_ext(track,"P_EXT:ZP_REMOTE_P_LANES")) or 2
    if not batch_prefix then
      if id~="" then state.p_lane_counts["id:"..id]=p_count end
      if normalized~="" then state.p_lane_counts["name:"..normalized]=p_count end
    end
    for ii=0,r.CountTrackMediaItems(track)-1 do
      local item = r.GetTrackMediaItem(track,ii)
      local raw = get_item_ext(item,"P_EXT:ZP_REMOTE_IMPORT")
      if raw ~= "" and (not batch_prefix or batch_track) then
        local parsed = parse_item_tag(raw)
        parsed.character_key = id~="" and ("id:"..id) or ("name:"..normalized)
        parsed.lane = math.max(0,math.floor(r.GetMediaItemInfo_Value(item,"I_FIXEDLANE") or 0))
        parsed.file = parsed.file or ""
        parsed.position = r.GetMediaItemInfo_Value(item,"D_POSITION")
        parsed.length = r.GetMediaItemInfo_Value(item,"D_LENGTH")
        parsed.project_lane_count = lane_count
        parsed.role=get_item_ext(item,"P_EXT:ZP_REMOTE_ROLE")
        if parsed.role=="" then parsed.role=parsed.lane<p_count and "P" or "A" end
        parsed.ring_id=get_item_ext(item,"P_EXT:ZP_REMOTE_RING_ID")
        parsed.take_version=get_item_ext(item,"P_EXT:ZP_REMOTE_TAKE_VERSION")
        if parsed.ring_id=="" and parsed.key then
          local ring,version=parsed.key:match("^[^|]+|[^|]+|([^|]+)|([^|]+)|")
          if ring and ring~="legacy" then parsed.ring_id=ring; parsed.take_version=version end
        end
        parsed.recorded_at=get_item_ext(item,"P_EXT:ZP_REMOTE_RECORDED_AT")
        state.items[#state.items+1] = parsed
      end
    end
  end
  if batch_prefix then return state end
  local needed={}
  for _,f in ipairs(plan.files or {}) do if f.role=="P" or f.role=="A" then
    local normalized=logic.normalize_name(f.character)
    if normalized~="" then needed[normalized]=true end
  end end
  for normalized in pairs(needed) do
    local candidates=name_candidates[normalized] or {}
    if #candidates>1 then die("Più tracce hanno il nome normalizzato ‘"..normalized.."’. Aggiungi character_id alle tracce o risolvi il duplicato prima di importare.") end
    if #candidates==1 then state.characters["name:"..normalized]=candidates[1].track end
  end
  return state
end
local function verify_copy_set(plan, source_dir, media_dir, on_progress)
  local valid, err = logic.validate(plan); if not valid then die(err) end
  local seen, total = {}, 0
  for file_index, f in ipairs(plan.files) do
    if on_progress then on_progress(("Verifico WAV %d/%d: %s"):format(file_index,#plan.files,tostring(f.file))) end
    if type(f.file) ~= "string" or f.file == "" or f.file == "." or f.file == ".." or f.file:find("[/\\]") or f.file:find("[%c]") then
      die("Nome WAV non sicuro nel piano: " .. tostring(f.file))
    end
    if seen[f.file] then die("Nome WAV duplicato nel piano: " .. f.file) end
    seen[f.file] = true
    local src = path_join(source_dir,f.file)
    if not r.file_exists(src) then die("WAV mancante; nessuna modifica eseguita: " .. src) end
    expect_hash(src,f.sha256)
    local dst = path_join(media_dir,f.file)
    f.media_file=f.file
    if r.file_exists(dst) then
      if digest(dst)~=tostring(f.sha256):lower() then
        local stem,ext=f.file:match("^(.*)(%.[^.]*)$")
        if not stem then stem,ext=f.file,"" end
        f.media_file=stem.."__"..tostring(f.sha256):lower()..ext
        local alternate=path_join(media_dir,f.media_file)
        if r.file_exists(alternate) then expect_hash(alternate,f.sha256) end
      end
    end
    if f.role == "P" or f.role == "A" then
      for _, it in ipairs(f.items or {}) do
        total = total + 1
        if not it.idempotency_key or it.idempotency_key == "" then die("Piano privo di chiave stabile: " .. f.file) end
      end
    end
  end
  if total ~= plan.counts.items then die("Conteggio item incoerente nel piano.") end
end
local function ensure_copied(plan, source_dir, media_dir, on_progress)
  local ok = r.RecursiveCreateDirectory(media_dir,0)
  if not ok or ok <= 0 then
    if not r.EnumerateFiles(media_dir,0) and not r.EnumerateSubdirectories(media_dir,0) then die("Creazione cartella fallita: " .. media_dir) end
  end
  for file_index, f in ipairs(plan.files) do
    if on_progress then on_progress(("Copio WAV %d/%d: %s"):format(file_index,#plan.files,tostring(f.file))) end
    local src, dst = path_join(source_dir,f.file), path_join(media_dir,f.media_file or f.file)
    if r.file_exists(dst) then expect_hash(dst,f.sha256)
    else write_copy(src,dst); expect_hash(dst,f.sha256) end
  end
end
local lane_names = {"P1","P2","A1","A2","A3"}
local function ensure_lanes(track,count,muted,new_track,p_count)
  count = math.max(5,math.floor(count or 0))
  local current = math.floor(r.GetMediaTrackInfo_Value(track,"I_NUMFIXEDLANES") or 0)
  if current < count or r.GetMediaTrackInfo_Value(track,"I_FREEMODE") ~= 2 then
    r.SetMediaTrackInfo_Value(track,"I_FREEMODE",2); r.UpdateTimeline()
    r.SetMediaTrackInfo_Value(track,"I_NUMFIXEDLANES",count); r.UpdateTimeline()
    local ok, chunk = r.GetTrackStateChunk(track,"",false)
    if not ok then die("Non riesco a leggere il chunk della traccia per le lane.") end
    local names = {}
    p_count=math.max(2,math.floor(p_count or 2))
    for i=1,count do names[i] = i<=p_count and ("P"..i) or ("A"..(i-p_count)) end
    local zeros = {}; for _=1,count-1 do zeros[#zeros+1]="0" end
    local fixed = "FIXEDLANES "..count.." "..table.concat(zeros," ")
    local replaced,n = chunk:gsub("FIXEDLANES [^\r\n]*",function() return fixed end,1)
    if n == 0 then die("REAPER non ha serializzato il blocco FIXEDLANES.") end
    replaced = replaced:gsub("LANENAME [^\r\n]*\n","")
    replaced = replaced:gsub("(FIXEDLANES "..count.." [^\r\n]*\n)","%1    LANENAME "..table.concat(names," ").."\n",1)
    if not r.SetTrackStateChunk(track,replaced,false) then die("Impostazione delle fixed lane non riuscita.") end
    if new_track then
      r.SetMediaTrackInfo_Value(track,"C_BEATATTACHMODE",0)
      for lane=0,count-1 do r.SetMediaTrackInfo_Value(track,"C_LANEPLAYS:"..lane,muted and 0 or (lane < p_count and 2 or 0)) end
    end
    r.UpdateTimeline()
  end
  local actual = math.floor(r.GetMediaTrackInfo_Value(track,"I_NUMFIXEDLANES") or 0)
  if r.GetMediaTrackInfo_Value(track,"I_FREEMODE") ~= 2 or actual < count then die("REAPER non conferma il numero richiesto di fixed lane.") end
end
local function json_escape(s)
  return '"' .. tostring(s):gsub('[%z\1-\31\\"]',function(c)
    local map={['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
    return map[c] or ("\\u%04x"):format(c:byte())
  end) .. '"'
end
local function json_encode(value)
  local kind=type(value)
  if value==nil then return "null" elseif kind=="boolean" then return value and "true" or "false"
  elseif kind=="number" then return tostring(value) elseif kind=="string" then return json_escape(value)
  elseif kind~="table" then return json_escape(tostring(value)) end
  local n,max=0,0; for k in pairs(value) do n=n+1; if type(k)=="number" and k>max then max=k end end
  local array=(n==0 or (max==n))
  local out={}
  if array then for i=1,max do out[#out+1]=json_encode(value[i]) end; return "["..table.concat(out,",").."]" end
  for k,v in pairs(value) do out[#out+1]=json_escape(k)..":"..json_encode(v) end
  return "{"..table.concat(out,",").."}"
end
local function write_json_atomic(path,value)
  local tmp=path..".tmp-"..tostring(os.time()).."-"..tostring(math.random(1000,9999))
  local f,err=io.open(tmp,"wb"); if not f then die("Non posso creare import-log.json: "..tostring(err)) end
  local ok,we=f:write(json_encode(value),"\n"); if not ok then f:close(); os.remove(tmp); die("Scrittura import-log.json fallita: "..tostring(we)) end
  local closed,ce=f:close(); if closed==nil then os.remove(tmp); die("Chiusura import-log.json fallita: "..tostring(ce)) end
  local renamed,re=os.rename(tmp,path); if not renamed then os.remove(tmp); die("Salvataggio import-log.json fallito: "..tostring(re)) end
end
local function make_cues(plan)
  if type(plan.cues)=="table" then return plan.cues end
  local cues={}
  for _,f in ipairs(plan.files or {}) do
    if f.role=="P" or f.role=="A" then for _,item in ipairs(f.items or {}) do cues[#cues+1]={file=f,item=item,legacy_key=item.idempotency_key} end end
  end
  return cues
end
local function add_log_rows(target,actions,kind)
  for _,a in ipairs(actions) do if a.kind==kind then target[#target+1]={key=a.key,file=a.file,hash=a.hash,character_key=a.character_key,lane=a.lane,role=a.role} end end
end
local function delivery_identity(value, allow_browser)
  local project_id = logic.canonico(value,"prj")
  if project_id or not allow_browser or type(value)~="string" then return project_id end
  local prefix,suffix = value:lower():match("^(%a+)%-(.+)$")
  if (prefix=="sess" or prefix=="demo") and logic.canonico(suffix,"prj")=="prj-"..suffix then
    return value:lower()
  end
end
local function main(opts)
  opts=opts or {}
  local ui_refresh_locked=false
  local function progress(message)
    if not opts.onProgress then return end
    if ui_refresh_locked then r.PreventUIRefresh(-1) end
    local ok,err=pcall(opts.onProgress,message)
    if ui_refresh_locked then r.PreventUIRefresh(1) end
    if not ok then error(err,0) end
  end
  local ok,plan_path
  if opts.plan_path and opts.plan_path~="" then ok,plan_path=true,opts.plan_path
  else ok,plan_path=r.GetUserFileNameForRead("","Scegli il piano JSON ZP Remote","json") end
  if not ok then return nil end
  local plan=read_json(plan_path)
  if plan.schema~="zp_remote_reaper_import_plan_v1" or (plan.session_type~="ordinary" and plan.session_type~="retake") then die("Schema piano o tipo sessione non supportato.") end
  local placement = plan.placement
  local at_cursor = placement and placement.mode == "cursor"
  local at_video = placement and placement.mode == "video"
  local separate_tracks = placement and placement.separate_tracks
  if at_cursor and not separate_tracks then die("L’importazione al cursore richiede tracce separate.") end
  local allow_browser = at_cursor and separate_tracks and plan.session_type=="ordinary"
  local project_id=logic.canonico(plan.project_guid,"prj")
  local delivery_id=delivery_identity(plan.delivery_guid,allow_browser)
  if not project_id or not delivery_id then die("ID progetto del piano non valido o di tipo diverso.") end
  if plan.project_id and logic.canonico(plan.project_id,"prj")~=project_id then die("project.id del piano non corrisponde a project_guid.") end
  if plan.delivery_project_id and logic.canonico(plan.delivery_project_id,"prj")~=delivery_id then die("ID canonico della consegna non coerente.") end
  local region_alias = plan.region_alias ~= json.null and plan.region_alias or nil
  if not plan.region or not plan.region.guid then die("Il piano deve identificare la regione tramite region.guid.") end
  if plan.session_type=="retake" and (not plan.retake_session_id or not plan.base_project_id or not plan.base_region_id or region_alias) then die("Contratto retake incompleto o con alias legacy non consentito.") end
  local package_path=type(plan.inputs.package)=="string" and plan.inputs.package or nil
  local direct_bwf_anchor=placement and placement.mode=="region" and placement.anchor=="same-project-bwf-v1"
  if package_path then
    expect_hash(package_path,plan.input_hashes.package)
  elseif direct_bwf_anchor or at_video then
    if project_id~=delivery_id or plan.session_type~="ordinary" then die("L’ancora video/BWF senza ZIP è valida solo per la stessa sessione/progetto.") end
  elseif not at_cursor then
    die("Per importare nella regione serve lo ZIP di partenza verificato.")
  end
  local active_file=project_file()
  expect_hash(active_file,plan.input_hashes.project)
  local active_id_ok,active_id=r.GetProjExtState(0,"ZP_REMOTE","PROJECT_ID")
  active_id=(active_id_ok>0 and active_id~="") and active_id or nil
  if not separate_tracks and (not at_video or project_id==delivery_id) then
    local identity_action,identity_error=logic.project_identity(plan.delivery_guid,active_id)
    if not identity_action then die(identity_error) end
  end
  local source_dir=plan.inputs.delivery_dir
  local media_dir=path_join(path_join(dirname(active_file),"Media/ZP Remote"),plan.delivery_id)
  verify_copy_set(plan,source_dir,media_dir,progress)
  local region
  if at_video then
    local selected=r.GetSelectedMediaItem(0,0)
    local take=selected and r.GetActiveTake(selected)
    local source=take and r.GetMediaItemTake_Source(take)
    if not source or r.GetMediaSourceType(source,"")~="VIDEO" then die("L'item VIDEO usato nel controllo non è più selezionato.") end
    local media=r.GetMediaSourceFileName(source,"")
    if not same(r.GetMediaItemInfo_Value(selected,"D_POSITION"),placement.video_start_s)
       or media~=placement.video_file then die("L'item VIDEO selezionato è cambiato dopo il controllo.") end
    region={start=plan.region.start_s,finish=plan.region.end_s,name=plan.region.name,guid=plan.region.guid}
  else
    region=at_cursor and plan.region or project_region(plan)
  end
  if not at_cursor and not at_video and plan.session_type=="retake" and (logic.canonico(plan.project_guid,"prj")~=logic.canonico(plan.base_project_id,"prj") or plan.region.guid~=plan.base_region_id) then die("Identità base della retake diversa dal progetto/regione del piano.") end
  if region_alias and (logic.canonico(region_alias.delivery_guid,"prj")~=logic.canonico(plan.delivery_guid,"prj") or logic.canonico(region_alias.rpp_guid,"prj")~=logic.canonico(plan.project_guid,"prj") or region_alias.region_guid~=plan.region.guid) then die("Alias legacy del piano non coerente.") end
  if not placement and #(plan.rpp_missing_media or {})>0 then die("Il preflight segnala media della sessione mancanti; import bloccato.") end
  local delivery_path=path_join(source_dir,"consegna.json")
  local delivery=read_json(delivery_path)
  expect_hash(delivery_path,plan.input_hashes.delivery_json)
  if delivery.zp_remote~=2 or delivery_identity(delivery.progetto,allow_browser)~=delivery_id or #delivery.files~=#plan.files then die("La consegna è cambiata dopo il preflight.") end
  for i,f in ipairs(plan.files) do
    local source=delivery.files[i]
    if not source or source.file~=f.file or source.sha256~=f.sha256 then die("Ordine/contenuto della consegna cambiato: "..f.file) end
  end
  plan.cues=make_cues(plan)
  local valid,validation_error=logic.validate(plan); if not valid then die(validation_error) end
  local batch_prefix=separate_tracks and ("batch-character:"..plan.delivery_id..":"..plan.region.guid..":") or nil
  local state=collect_state(plan,batch_prefix)
  local decision,decision_error=logic.decide(plan,state); if not decision then die(decision_error) end
  local delivery_project_id=logic.canonico(plan.delivery_guid,"prj")
  local id_to_write=not separate_tracks and project_id==delivery_project_id and not active_id and delivery_project_id and ("{"..delivery_project_id:sub(5):upper().."}") or nil
  local lines={}
  for key,c in pairs(plan.counts.characters or {}) do lines[#lines+1]=tostring(key).." "..tostring(c) end
  table.sort(lines)
  local preview=("Anteprima import\n\n%s WAV · P %s · A %s · %s fuori traccia · %s personaggi\n\n%s\n\nConsegna: %s\nRegione: %s\nProgetto aperto: %s\n\nDa aggiungere: %s · invariati: %s · take diversi: %s · archiviati dal master: %s"):format(
    plan.counts.files,plan.counts.P,plan.counts.A or 0,plan.counts.fuori_traccia,#lines,table.concat(lines," · "),plan.delivery_id,region.name,basename(active_file),decision.added,decision.unchanged,decision.replaced,#decision.archived)
  local cursor = at_cursor and r.GetCursorPosition() or 0
  if at_cursor then
    preview=preview..("\n\nRiferimenti originali assenti o non verificabili. Prima take al cursore (%.3f s), su nuove tracce.\n%s."):format(cursor,placement.reason)
  end
  if id_to_write then preview=preview.."\n\nIl progetto non ha ancora un ID: verrà assegnato l'ID della consegna." end
  preview=preview.."\n\nNessun item verrà sovrascritto o cancellato."
  if opts.confirm then
    if not opts.confirm(preview) then return nil end
  elseif r.MB(preview,"ZP Remote — conferma import",1)~=1 then
    return nil
  end
  if id_to_write then
    local valid_id=id_to_write:match("^%{[%x%-]+%}$")
    if not valid_id then die("ID progetto della consegna non valido.") end
  end

  -- All sources and destinations were checked before this first filesystem/project write.
  ensure_copied(plan,source_dir,media_dir,progress)
  local track_by_key={}
  for key,tr in pairs(state.characters) do track_by_key[key]=tr end
  for key,upgrade in pairs(decision.upgraded_characters or {}) do track_by_key[key]=upgrade.track end
  local new_char_list, new_track_key = {}, {}
  local adding_characters={}
  for _,action in ipairs(decision.actions) do
    if action.kind~="unchanged" then adding_characters[action.character_key]=true end
  end
  for key,row in pairs(decision.new_characters) do
    if adding_characters[key] then new_char_list[#new_char_list+1]=row end
  end
  table.sort(new_char_list,function(a,b) return tostring(a.name)<tostring(b.name) end)
  local max_lane={}
  for _,action in ipairs(decision.actions) do max_lane[action.character_key]=math.max(max_lane[action.character_key] or 0,(action.lane or 0)+1) end
  local insertions_by_key={}
  for _,entry in ipairs(decision.lane_insertions or {}) do
    local list=insertions_by_key[entry.character_key] or {}
    list[#list+1]=entry
    insertions_by_key[entry.character_key]=list
  end
  local log={date=os.date("!%Y-%m-%dT%H:%M:%SZ"),project_id=plan.delivery_guid,region_guid=plan.region.guid,delivery_id=plan.delivery_id,
    placement=placement and placement.mode, cursor_s=at_cursor and cursor or nil,
    files_by_role={P=plan.counts.P or 0,A=plan.counts.A or 0,fuori_traccia=plan.counts.fuori_traccia or 0},
    added={},unchanged={},replaced={},archived=decision.archived,errors={},legacy_character_fallbacks=decision.legacy_fallbacks}
  add_log_rows(log.added,decision.actions,"add")
  add_log_rows(log.unchanged,decision.actions,"unchanged")
  add_log_rows(log.replaced,decision.actions,"replace")

  local has_upgrades=next(decision.upgraded_characters or {})~=nil
  local changed=(#new_char_list>0 or #log.added>0 or #log.replaced>0 or has_upgrades or id_to_write~=nil or #(decision.lane_insertions or {})>0)
  local log_path=dirname(plan_path).."/import-log.json"
  local previous_log
  local old_log=io.open(log_path,"rb")
  if old_log then previous_log=old_log:read("*a"); old_log:close() end
  if changed then
    r.PreventUIRefresh(1)
    ui_refresh_locked=true
    r.Undo_BeginBlock2(0)
    local success,err=xpcall(function()
      for key,upgrade in pairs(decision.upgraded_characters or {}) do
        setstr(r.GetSetMediaTrackInfo_String,upgrade.track,"P_EXT:ZP_REMOTE_CHARACTER",upgrade.character_id)
        setstr(r.GetSetMediaTrackInfo_String,upgrade.track,"P_EXT:ZP_REMOTE_IMPORT","character:"..key)
      end
      if id_to_write then
        r.SetProjExtState(0,"ZP_REMOTE","PROJECT_ID",id_to_write)
        r.MarkProjectDirty(0)
        local saved,check=r.GetProjExtState(0,"ZP_REMOTE","PROJECT_ID")
        if saved<=0 or check~=id_to_write then die("Non riesco a impostare l'ID progetto richiesto.") end
      end
      local start=r.CountTracks(0)
      local add_folder=#new_char_list>0 and not separate_tracks
      if add_folder then
        r.InsertTrackAtIndex(start,true)
        local folder=r.GetTrack(0,start)
        r.GetSetMediaTrackInfo_String(folder,"P_NAME","ZP Remote · "..region.name,true)
        r.SetMediaTrackInfo_Value(folder,"I_FOLDERDEPTH",1)
        setstr(r.GetSetMediaTrackInfo_String,folder,"P_EXT:ZP_REMOTE_IMPORT","batch:"..plan.delivery_id..":"..plan.region.guid)
      end
      local inserted=0
      local source_cache={}
      for _,character in ipairs(new_char_list) do
        local index=start+inserted+(add_folder and 1 or 0)
        r.InsertTrackAtIndex(index,true)
        local track=r.GetTrack(0,index); if not track then die("Creazione traccia personaggio fallita.") end
        local label=tostring(character.name or "Personaggio")
        r.GetSetMediaTrackInfo_String(track,"P_NAME",label,true)
        if not separate_tracks and type(character.character_id)=="string" and character.character_id~="" then setstr(r.GetSetMediaTrackInfo_String,track,"P_EXT:ZP_REMOTE_CHARACTER",character.character_id) end
        local key=character.key
        setstr(r.GetSetMediaTrackInfo_String,track,"P_EXT:ZP_REMOTE_IMPORT",(batch_prefix or "character:")..key)
        track_by_key[key]=track; new_track_key[key]=true; inserted=inserted+1
      end
      if add_folder then r.SetMediaTrackInfo_Value(r.GetTrack(0,start+inserted),"I_FOLDERDEPTH",-1) end
      for key,entries in pairs(insertions_by_key) do
        local track=track_by_key[key]
        if not track then die("Traccia retake non trovata: "..key) end
        local original=math.max(5,math.floor(r.GetMediaTrackInfo_Value(track,"I_NUMFIXEDLANES") or 0))
        local old_plays={}
        for lane=0,original-1 do old_plays[lane]=r.GetMediaTrackInfo_Value(track,"C_LANEPLAYS:"..lane) end
        local needed=math.max(original+#entries,max_lane[key] or 0)
        local p_count=(decision.p_lane_counts or {})[key] or 2
        ensure_lanes(track,needed,plan.session_type=="retake",new_track_key[key]==true,p_count)
        for _,entry in ipairs(entries) do
          for ii=0,r.CountTrackMediaItems(track)-1 do
            local old=r.GetTrackMediaItem(track,ii)
            local lane=math.floor(r.GetMediaItemInfo_Value(old,"I_FIXEDLANE") or 0)
            if lane>=entry.at then r.SetMediaItemInfo_Value(old,"I_FIXEDLANE",lane+1) end
          end
          for lane=needed-1,entry.at+1,-1 do old_plays[lane]=old_plays[lane-1] end
          old_plays[entry.at]=entry.role=="P" and 2 or 0
        end
        for lane=0,needed-1 do
          if old_plays[lane]~=nil then r.SetMediaTrackInfo_Value(track,"C_LANEPLAYS:"..lane,old_plays[lane]) end
        end
        setstr(r.GetSetMediaTrackInfo_String,track,"P_EXT:ZP_REMOTE_P_LANES",tostring(p_count))
      end
      for action_index,action in ipairs(decision.actions) do
        if action.kind=="add" or action.kind=="replace" then
          progress(("Inserisco item %d/%d: %s"):format(action_index,#decision.actions,tostring(action.file)))
          local track=track_by_key[action.character_key]
          if not track then die("Nessuna traccia per il personaggio "..tostring(action.character_key)) end
          local file
          for _,f in ipairs(plan.files) do if f.file==action.file then file=f; break end end
          if not file then die("File del piano non trovato: "..tostring(action.file)) end
          local item_plan
          for _,it in ipairs(file.items or {}) do if it.idempotency_key==action.key or (it.item_index==tonumber(action.key:match("|(%d+)$"))) then item_plan=it; break end end
          if not item_plan then die("Item del piano non trovato per "..action.file) end
          local needed=math.max(max_lane[action.character_key] or 5,math.floor(r.GetMediaTrackInfo_Value(track,"I_NUMFIXEDLANES") or 0))
          ensure_lanes(track,needed,plan.session_type=="retake",new_track_key[action.character_key] == true,
            (decision.p_lane_counts or {})[action.character_key] or 2)
          local media=path_join(media_dir,file.media_file or file.file)
          local source=source_cache[file.file]
          if not source then
            source=r.PCM_Source_CreateFromFile(media)
            if not source then die("REAPER non apre il media copiato: "..media) end
            source_cache[file.file]=source
          end
          local source_len=r.GetMediaSourceLength(source)
          if item_plan.source_offset_s+item_plan.length_s>source_len+1/48000 then die("Taglio oltre la sorgente: "..file.file) end
          local item=r.AddMediaItemToTrack(track); if not item then die("Creazione item fallita: "..file.file) end
          local take=r.AddTakeToMediaItem(item); if not take then die("Creazione take fallita: "..file.file) end
          r.SetMediaItemTake_Source(take,source)
          r.GetSetMediaItemTakeInfo_String(take,"P_NAME",file.file,true)
          r.SetMediaItemInfo_Value(item,"D_POSITION",item_plan.position_s+cursor)
          r.SetMediaItemInfo_Value(item,"D_LENGTH",item_plan.length_s)
          r.SetMediaItemTakeInfo_Value(take,"D_STARTOFFS",item_plan.source_offset_s)
          r.SetMediaItemInfo_Value(item,"D_FADEINLEN",item_plan.fade_in_ms/1000)
          r.SetMediaItemInfo_Value(item,"D_FADEOUTLEN",item_plan.fade_out_ms/1000)
          r.SetMediaItemInfo_Value(item,"D_FADEINLEN_AUTO",-1)
          r.SetMediaItemInfo_Value(item,"D_FADEOUTLEN_AUTO",-1)
          r.SetMediaItemInfo_Value(item,"I_FIXEDLANE",action.lane or 0)
          r.SetMediaItemInfo_Value(item,"C_BEATATTACHMODE",0)
          if item_plan.note and item_plan.note~="" then r.GetSetMediaItemInfo_String(item,"P_NOTES",item_plan.note,true) end
          setstr(r.GetSetMediaItemInfo_String,item,"P_EXT:ZP_REMOTE_IMPORT",item_tag(action.key,file.sha256,file.file))
          setstr(r.GetSetMediaItemInfo_String,item,"P_EXT:ZP_REMOTE_ROLE",file.role)
          if item_plan.ring_id~=nil and item_plan.ring_id~=json.null then setstr(r.GetSetMediaItemInfo_String,item,"P_EXT:ZP_REMOTE_RING_ID",tostring(item_plan.ring_id)) end
          if item_plan.take_version~=nil and item_plan.take_version~=json.null then setstr(r.GetSetMediaItemInfo_String,item,"P_EXT:ZP_REMOTE_TAKE_VERSION",tostring(item_plan.take_version)) end
          if type(file.recorded_at)=="string" and file.recorded_at~="" then setstr(r.GetSetMediaItemInfo_String,item,"P_EXT:ZP_REMOTE_RECORDED_AT",file.recorded_at) end
          if type(plan.session_date)=="string" and plan.session_date~="" then setstr(r.GetSetMediaItemInfo_String,item,"P_EXT:ZP_REMOTE_SESSION_DATE",plan.session_date) end
          setstr(r.GetSetMediaItemInfo_String,item,"P_EXT:ZP_REMOTE_BWF_REFERENCE",tostring(file.time_reference))
        end
      end
      if not separate_tracks then
        r.SetProjExtState(0,"ZP_REMOTE_IMPORT","delivery_id",plan.delivery_id)
        r.SetProjExtState(0,"ZP_REMOTE_IMPORT","region_guid",plan.region.guid)
      end
      r.UpdateArrange()
      write_json_atomic(log_path,log)
    end,debug.traceback)
    r.PreventUIRefresh(-1)
    ui_refresh_locked=false
    r.Undo_EndBlock2(0,success and "ZP Remote: importa consegna" or "ZP Remote: import annullato",-1)
    if not success then
      r.Undo_DoUndo2(0)
      die("Import annullato con Undo. Nessun item è stato sovrascritto o cancellato.\n"..tostring(err))
    end
    if not separate_tracks then r.Main_OnCommand(40026,0) end
    if not separate_tracks and r.IsProjectDirty(0)>0 then
      r.Undo_DoUndo2(0)
      if previous_log then
        local restore=io.open(log_path,"wb")
        if restore then restore:write(previous_log); restore:close() end
      else
        os.remove(log_path)
      end
      die("Salvataggio progetto non confermato; annullato l'ultimo blocco Undo.")
    end
  else
    write_json_atomic(log_path,log)
  end
  local msg=("Import concluso.\n\nFile: P %s · A %s · fuori traccia %s.\nAggiunti: %s · invariati: %s · nuovi take: %s · battute assenti dal master, lasciate intatte: %s.\nPersonaggi senza character_id: %s (riconosciuti dal nome normalizzato).\n\nRapporto: import-log.json"):format(
    plan.counts.P or 0,plan.counts.A or 0,plan.counts.fuori_traccia or 0,
    decision.added,decision.unchanged,decision.replaced,#decision.archived,decision.legacy_fallbacks)
  progress(msg)
  return {message=msg,log=log,decision=decision,region=region}
end

function M.run(opts)
  local ok,result=xpcall(function() return main(opts or {}) end,debug.traceback)
  if not ok then return false,result end
  return true,result
end

return M
