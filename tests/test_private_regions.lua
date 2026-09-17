-- @noindex
-- Run from repository root: lua tests/test_private_regions.lua
local lanes, objects, ext, bounds, next_id = {}, {}, {}, 3, 0
local function reset()
  lanes, objects, ext, bounds, next_id = {"{A}", "{B}", "{C}"}, {}, {}, 3, 0
end
reaper = {
  EnumProjExtState = function(_, _, i)
    local keys = {}; for k in pairs(ext) do keys[#keys+1] = k end; table.sort(keys)
    local k = keys[i+1]; return k ~= nil, k, k and ext[k]
  end,
  SetProjExtState = function(_, _, key, value) ext[key] = value; return 1 end,
  GetSetProjectInfo_String = function(_, key, value, set)
    local n = tonumber(key:match('RULER_LANE_GUID:(%d+)$'))
    if n then return lanes[n+1] ~= nil, lanes[n+1] or '' end
    return true, value
  end,
  GetSetProjectInfo = function(_, key, value, set)
    if key == 'RULER_LANE_COUNT' then
      if set then for i = #lanes+1,value do lanes[i] = '{NEW'..i..'}' end end
      return #lanes
    end
    if key == 'RENDER_BOUNDSFLAG' then if set then bounds = value end; return bounds end
  end,
  GetNumRegionsOrMarkers = function() return #objects end,
  GetRegionOrMarker = function(_, i, guid)
    if i >= 0 then return objects[i+1] end
    for _, o in ipairs(objects) do if o.GUID == guid then return o end end
  end,
  GetRegionOrMarkerInfo_Value = function(_, o, key)
    if key == 'I_INDEX' then for i,v in ipairs(objects) do if v==o then return i-1 end end end
    return o[key] or 0
  end,
  SetRegionOrMarkerInfo_Value = function(_, o, key, value) o[key] = value; return value end,
  GetSetRegionOrMarkerInfo_String = function(_, o, key, value, set)
    if set then o[key] = value end; return true, o[key]
  end,
  AddRegionOrMarker = function(_, region, first, last, name, _, color)
    next_id = next_id + 1
    local o = {B_ISREGION=region and 1 or 0, D_STARTPOS=first, D_ENDPOS=last,
      P_NAME=name, I_CUSTOMCOLOR=color, I_NUMBER=next_id, GUID='{REG'..next_id..'}', I_LANENUMBER=0}
    objects[#objects+1]=o; return o
  end,
  DeleteProjectMarker = function(_, number)
    for i,o in ipairs(objects) do if o.I_NUMBER==number then table.remove(objects,i); return true end end
    return false
  end,
  CountProjectMarkers = function()
    local regions=0; for _,o in ipairs(objects) do regions=regions+o.B_ISREGION end
    return #objects,#objects-regions,regions
  end,
  EnumProjectMarkers3 = function(_, i)
    local o=objects[i+1]; if not o then return 0 end
    return i+1,o.B_ISREGION==1,o.D_STARTPOS,o.D_ENDPOS,o.P_NAME,o.I_NUMBER,o.I_CUSTOMCOLOR
  end,
  atexit=function() end
}
local P=dofile('ZP Studio Suite/ZP_Private_Regions.lua')
local passed=0
local function test(name, fn) reset(); fn(); passed=passed+1; print('OK '..name) end
local function editorial(name)
 return reaper.AddRegionOrMarker(0,true,0,10,name or 'SPACE',-1,123)
end
local function private(owner, kind)
 return P.create(0,owner or 'STAGEKEEPER',kind or 'SPACE',1,3,123,4)
end

test('ordinary name and color do not identify ownership', function()
 editorial(); assert(not P.is_private(0,0)); private(); assert(not P.is_private(0,0)); assert(P.is_private(0,1))
end)
test('initial lane 4, reuse by GUID after reorder', function()
 local o=private(); local guid=lanes[4]; lanes[1],lanes[4]=lanes[4],lanes[1]; o.I_LANENUMBER=0
 local second=private(); assert(second.I_LANENUMBER==0 and lanes[1]==guid and #lanes==4)
end)
test('existing fourth lane is never appropriated', function()
 lanes[4]='{EDITORIAL4}'; local o=private(); assert(o.I_LANENUMBER==4 and not ext['lane:{EDITORIAL4}'])
end)
test('future owner and unknown type remain private', function()
 private(); private('WHISPER','FUTURE_TYPE'); assert(P.is_private(0,1)); assert(P.owner_at_index(0,1)=='WHISPER')
end)
test('foreign read update delete rejected', function()
 local o=private('WHISPER','TEXT')
 assert(not pcall(P.read,0,'STAGEKEEPER',o.GUID))
 assert(not pcall(P.update,0,'STAGEKEEPER',o.GUID,'IGNORE',2,4))
 assert(not pcall(P.delete,0,'STAGEKEEPER',o.GUID)); assert(#objects==1 and o.P_NAME=='TEXT')
end)
test('owner CRUD uses region GUID', function()
 local o=private(); P.update(0,'STAGEKEEPER',o.GUID,'IGNORE',2,4)
 local data=P.read(0,'STAGEKEEPER',o.GUID); assert(data.type=='IGNORE' and data.end_pos==4)
 assert(P.delete(0,'STAGEKEEPER',o.GUID)); assert(#objects==0)
end)
test('deleted lane cannot capture another lane', function()
 private(); lanes[4]='{REPLACEMENT}'; assert(not pcall(private)); assert(#objects==1)
end)
test('invalid range creates nothing', function()
 assert(not pcall(P.create,0,'STAGEKEEPER','SPACE',3,1,0,4)); assert(#lanes==3 and #objects==0)
end)
test('occupied lane registration rejected', function()
 editorial(); assert(not pcall(P.register_lane,0,'WHISPER',0))
end)
test('render selection excludes every private owner', function()
 local e=editorial(); local a=private(); local b=private('WHISPER','TEXT')
 assert(P.select_render_regions(0,{[e.I_NUMBER]=true,[a.I_NUMBER]=true,[b.I_NUMBER]=true})==1)
 assert(bounds==5 and e.B_UISEL==1 and a.B_UISEL==0 and b.B_UISEL==0)
end)
test('fail closed with registered lanes but missing APIs', function()
 private(); local saved=reaper.GetRegionOrMarker; reaper.GetRegionOrMarker=nil
 assert(P.is_private(0,0)); reaper.GetRegionOrMarker=saved
end)
test('viewer actual collection excludes private content and counts', function()
 editorial('Editorial'); private(); private('WHISPER','TEXT')
 local f=assert(io.open('ZP Studio Suite/18_Project_Viewer.lua')); local src=f:read('*a'); f:close()
 src=src:match('^(.-)local function build_rows%(%)')..'return collect_project_marks'
 local collect=assert(load(src,'@ZP Studio Suite/18_Project_Viewer.lua'))()
 local markers,regions=collect(); assert(#markers==0 and #regions==1 and regions[1].name=='Editorial')
end)
test('queue snapshot preserves private GUIDs and restores selection', function()
 local e=editorial(); local a=private(); local b=private('WHISPER','TEXT'); a.B_UISEL=1
 local f=assert(io.open('ZP Studio Suite/17_Crea_Regioni_Export_da_Item_Nominati.lua')); local src=f:read('*a'); f:close()
 local body=src:match('(local function queue_with_only_regions.-)local function save_render_settings_snapshot')
 local factory=assert(load('local ZP_Private=...; '..body..' return queue_with_only_regions'))
 local queue=factory(P)
 local ok,err=queue({{idx=e.I_NUMBER}},function(mode)
   assert(mode==5 and bounds==5 and e.B_UISEL==1 and a.B_UISEL==0 and b.B_UISEL==0)
   assert(#objects==3)
 end)
 assert(ok,err); assert(bounds==3 and a.B_UISEL==1 and #objects==3)
 local bad=queue({{idx=e.I_NUMBER}},function() error('simulated queue failure') end)
 assert(not bad and bounds==3 and a.B_UISEL==1 and #objects==3)
end)
local function stage(role)
 return P.create(0,'STAGEKEEPER',role,1,3,123,4,role)
end

test('alternating roles persist exactly two distinct lanes', function()
 local a=stage('SPACE'); local b=stage('IGNORE')
 for i=1,20 do
  assert(stage('SPACE').I_LANENUMBER==a.I_LANENUMBER)
  assert(stage('IGNORE').I_LANENUMBER==b.I_LANENUMBER)
 end
 assert(#lanes==5 and a.I_LANENUMBER~=b.I_LANENUMBER)
 assert(ext['role:'..lanes[4]]=='SPACE' and ext['role:'..lanes[5]]=='IGNORE')
end)
test('IGNORE can initialize first', function()
 local b=stage('IGNORE'); local a=stage('SPACE')
 assert(b.I_LANENUMBER==3 and a.I_LANENUMBER==4 and #lanes==5)
end)
test('both role GUIDs survive reorder rename and helper reload', function()
 local a=stage('SPACE'); local b=stage('IGNORE')
 lanes[1],lanes[4]=lanes[4],lanes[1]; a.I_LANENUMBER=0
 lanes[2],lanes[5]=lanes[5],lanes[2]; b.I_LANENUMBER=1
 reaper.GetSetProjectInfo_String(0,'RULER_LANE_NAME:0','arbitrary',true)
 local reload=dofile('ZP Studio Suite/ZP_Private_Regions.lua')
 assert(reload.create(0,'STAGEKEEPER','SPACE',4,5,0,4,'SPACE').I_LANENUMBER==0)
 assert(reload.create(0,'STAGEKEEPER','IGNORE',4,5,0,4,'IGNORE').I_LANENUMBER==1)
 assert(#lanes==5)
end)
test('deleted role fails without mutation and restored GUID resumes', function()
 for _,role in ipairs({'SPACE','IGNORE'}) do
  reset(); stage('SPACE'); stage('IGNORE')
  local index=role=='SPACE' and 4 or 5; local guid=lanes[index]
  lanes[index]='{REPLACEMENT}'
  local before={}; for k,v in pairs(ext) do before[k]=v end
  for i=1,3 do
   local ok,err=pcall(stage,role); assert(not ok and err:match('Undo'))
  end
  assert(#lanes==5 and #objects==2)
  for k,v in pairs(ext) do assert(before[k]==v) end
  for k,v in pairs(before) do assert(ext[k]==v) end
  lanes[index]=guid -- model Undo restoring the original lane identity
  assert(stage(role).I_LANENUMBER==index-1 and #lanes==5)
 end
end)
test('role semantics ignore region name and reject cross-role update', function()
 local a=stage('SPACE'); a.P_NAME='IGNORE'
 assert(P.read(0,'STAGEKEEPER',a.GUID).type=='SPACE')
 assert(not pcall(P.update,0,'STAGEKEEPER',a.GUID,'IGNORE',8,9))
 assert(a.D_STARTPOS==1 and a.D_ENDPOS==3)
end)
test('legacy ownership cannot be guessed from region name', function()
 private(); local ok,err=pcall(stage,'SPACE')
 assert(not ok and err:match('legacy') and #lanes==4 and #objects==1)
 assert(not pcall(stage,'IGNORE') and #lanes==4)
end)
test('duplicate role registry fails without creating anything', function()
 stage('SPACE'); lanes[5]='{DUP}'
 ext['lane:{DUP}']='STAGEKEEPER'; ext['role:{DUP}']='SPACE'
 assert(not pcall(stage,'SPACE') and #lanes==5 and #objects==1)
end)
test('registered role cannot be reassigned', function()
 stage('SPACE')
 assert(not pcall(P.register_lane,0,'STAGEKEEPER',3,'IGNORE'))
 assert(ext['role:'..lanes[4]]=='SPACE')
end)
test('actual actions create only their own persistent roles', function()
 local messages={}; local depth=0
 reaper.EnumProjects=function() return 0 end
 reaper.GetSet_LoopTimeRange2=function() return 1,3 end
 reaper.ColorToNative=function() return 123 end
 reaper.Undo_BeginBlock2=function() depth=depth+1 end
 reaper.Undo_EndBlock2=function() depth=depth-1 end
 reaper.UpdateArrange=function() end
 reaper.MB=function(message) messages[#messages+1]=message end
 for i=1,5 do
  dofile('ZP Studio Suite/28_Stagekeeper_Private_SPACE.lua')
  dofile('ZP Studio Suite/29_Stagekeeper_Private_IGNORE.lua')
 end
 assert(#lanes==5 and #objects==10 and depth==0 and #messages==0)
 for i,o in ipairs(objects) do assert(o.I_LANENUMBER==(i%2==1 and 3 or 4)) end
 lanes[4]='{DELETED}'
 dofile('ZP Studio Suite/28_Stagekeeper_Private_SPACE.lua')
 assert(#messages==1 and messages[1]:match('Undo') and #objects==10 and depth==0)
end)
test('safe loader aborts every dependent script when the module cannot load', function()
 local real_dofile = dofile
 local messages = {}
 reaper.EnumProjects=function() return 0 end
 reaper.GetSet_LoopTimeRange2=function() return 1,3 end
 reaper.ColorToNative=function() return 123 end
 reaper.Undo_BeginBlock2=function() error('nessun blocco Undo deve essere aperto') end
 reaper.Undo_EndBlock2=function() error('nessun blocco Undo deve essere chiuso') end
 reaper.UpdateArrange=function() end
 reaper.MB=function(message) messages[#messages+1]=message end
 local dependents={'04_worker_Crea_Marker_Item','05_Aggiorna_SRT_Video','05_worker_Gestione_SRT',
  '08_Esporta_SRT','17_Crea_Regioni_Export_da_Item_Nominati','18_Project_Viewer',
  '19_Report_Minuti_Voce','20_Importa_Cartelle_Video_Mixdown',
  '22_Pulisci_Code_Silenzi_e_Separa_Item','25_ZP_SOLO_Recorder',
  '28_Stagekeeper_Private_SPACE','29_Stagekeeper_Private_IGNORE'}
 assert(#dependents==12)
 for _,name in ipairs(dependents) do
  local path='ZP Studio Suite/'..name..'.lua'
  dofile=function(target)
   if target:match('ZP_Private_Regions%.lua$') then error('modulo simulato non caricabile',0) end
   return real_dofile(target)
  end
  local before=#messages
  local ok,err=pcall(real_dofile,path)
  dofile=real_dofile
  assert(ok,path..': stack trace non gestito invece di abort controllato -> '..tostring(err))
  assert(#messages==before+1,path..': attesa esattamente una MB di abort')
  local m=messages[#messages]
  assert(m:match('caricabile'),path..': il messaggio non dice che il modulo non e caricabile')
  assert(m:match('modulo simulato non caricabile'),path..': il messaggio non riporta il dettaglio di dofile')
  assert(#objects==0 and #lanes==3,path..': lo script ha toccato il progetto prima di abortire')
 end
end)
print(passed..' tests passed')
