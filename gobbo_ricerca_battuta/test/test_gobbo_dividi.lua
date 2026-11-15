local M=dofile('ZP Studio Suite/ZP_Testo_Copione.lua')
local n=0
local function eq(a,b,label) n=n+1;assert(a==b,'FAIL '..(label or tostring(n))..': '..tostring(a)..' ~= '..tostring(b)) end
local function near(a,b,label) n=n+1;assert(math.abs(a-b)<0.000001,'FAIL '..(label or tostring(n))..': '..a..' ~= '..b) end
local function normalized(s) return s:gsub('\r\n','\n'):gsub('\r','\n') end
local guid1='{11111111-1111-1111-1111-111111111111}'
local guid2='{22222222-2222-2222-2222-222222222222}'
-- All internal word boundaries, including empty rows, indentation, accents and short items.
for _,text in ipairs({'A B\n\nC D','È già qui. Ancóra sì!','prima\n  seconda\n\n\n terza','\n\nuno due\n\n','uno\t due   tre','A\nB\nC'}) do
 for _,duration in ipairs({2,8,99.5}) do
  local plan=M.reading_plan(text,nil,1,duration,120)
  for _,event in ipairs(plan.events) do
   if not event.pause and event.word>1 then
    local anchors={{guid=guid1,offset=1},{guid=guid2,offset=event.first}}
    local result=assert(M.split_reading_text(text,event.first,plan,duration,anchors))
    eq(result.left.text..result.boundary..result.right.text,text,'testo completo, nessuna parola persa/duplicata')
    eq(result.right.text:sub(1,event.last-event.first+1),text:sub(event.first,event.last),'il secondo item parte dalla parola')
    near(result.left.len+result.right.len,duration,'durata totale invariata')
    eq(result.right.anchors[1].offset,1,'promemoria della parola passa al secondo item')
    local lp=M.reading_plan(result.left.text,nil,1,result.left.len,120,result.left.timing)
    local rp=M.reading_plan(result.right.text,nil,1,result.right.len,120,result.right.timing)
    near(lp.total,result.left.len);near(rp.total,result.right.len)
    for j=0,18 do
     local t=duration*(j+0.273)/19
     local original=M.reading_state(plan,t/duration)
     local actual,left_words
     if t<result.left.len then actual=M.reading_state(lp,t/result.left.len);left_words=0
     else actual=M.reading_state(rp,(t-result.left.len)/result.right.len);left_words=lp.words end
     eq(actual.word+left_words,original.word,'parola allo stesso istante dopo il taglio')
     eq(actual.paused,original.paused,'pausa allo stesso istante dopo il taglio')
    end
   end
  end
 end
end
local small=M.reading_plan('uno due tre',nil,4,3,120)
local split=assert(M.split_reading_text('uno due tre',5,small,3,{}))
near(split.left.len,1,'nessun minimo di cinque secondi sul primo pezzo')
local rp=M.reading_plan(split.right.text,nil,4,split.right.len,120,split.right.timing)
local repeated=assert(M.split_reading_text(split.right.text,5,rp,split.right.len,{}))
near(repeated.left.len,1,'tagli ripetuti mantengono il passo')
near(repeated.right.len,1)
eq(M.split_reading_text('uno due tre',1,small,3,{}),nil,'niente item vuoto prima della prima parola')
local values=M.parse_reading_timing(M.serialize_reading_timing({0.2,0.7,1.1}))
near(values[2],0.7);eq(M.parse_reading_timing('v1|-1;2'),nil);eq(M.parse_reading_timing('v2|1;2'),nil)
local function clone(value)
 if type(value)~='table' then return value end
 local out={};for k,v in pairs(value) do out[k]=clone(v) end;return out
end
local items,before,after,menu_choice,now,writes,split_calls,fail_write,fail_split,undo_calls,setter_mode
local function reset(text)
 items={[1]={GUID=guid1,P_NOTES=text or 'A B\n\nC D',D_POSITION=10,D_LENGTH=8,takes=0,['P_EXT:ZP_TIMED_SCROLL']='1',['P_EXT:ZP_TIMED_SCROLL_WPM']='120',['P_EXT:ZP_TIMED_SCROLL_PAUSE_WEIGHT']='4',['P_EXT:ZP_GOBBO_ANCHORS']=M.serialize_anchors({{guid=guid1,offset=1},{guid=guid2,offset=6}}),['P_EXT:RythmoBand_HIGHLIGHT']='C'}}
 writes,split_calls,fail_write,fail_split,undo_calls,setter_mode=0,0,false,false,0,nil
end
reaper={GetExtState=function() return '1' end,SetExtState=function() end,GetOS=function() return 'OSX64' end,
 ValidatePtr2=function(_,id) return items[id]~=nil end,
 GetSetMediaItemInfo_String=function(id,key,value,set)
  if set then
   if fail_write and key=='P_NOTES' and id==2 then return false end
   if setter_mode=='silent_failure' and key=='P_NOTES' and id==2 then return true end
   items[id][key]=value;writes=writes+1
   if setter_mode=='false_empty' and value=='' or setter_mode=='false_all' then return false,value end
  end
  local saved=items[id][key] or ''
  if setter_mode=='crlf' and key=='P_NOTES' then saved=saved:gsub('\n','\r\n') end
  return saved~='',saved
 end,
 GetMediaItemInfo_Value=function(id,key) return items[id][key] or 0 end,
 GetMediaItemNumTakes=function(id) return items[id].takes end,
 SplitMediaItem=function(id,pos)
  split_calls=split_calls+1
  if fail_split then return nil end
  local old=items[id];items[2]=clone(old);items[2].GUID=guid2
  items[2].D_POSITION=pos;items[2].D_LENGTH=old.D_POSITION+old.D_LENGTH-pos;old.D_LENGTH=pos-old.D_POSITION
  return 2
 end,
 SetMediaItemSelected=function(id,selected) items[id].selected=selected end,
 Undo_BeginBlock=function() before=clone(items) end,
 Undo_EndBlock=function() after=clone(items) end,
 Undo_DoUndo2=function() undo_calls=undo_calls+1;items=clone(before) end,Undo_DoRedo2=function() items=clone(after) end,
 UpdateArrange=function() end,UpdateItemInProject=function() end,
 -- Il menu contestuale guarda anche le battute da unire: qui non ce ne sono.
 CountSelectedMediaItems=function() return 0 end,GetMediaItem_Track=function() return 'T' end,CountTrackMediaItems=function() return 0 end,
 SetEditCurPos=function() error('non deve spostare la timeline') end,OnStopButton=function() error('non deve fermare il trasporto') end,
 AddProjectMarker2=function() error('il taglio non deve creare o spostare marker') end,
 GetCursorPosition=function() return 500 end,time_precise=function() return now end,
 ShowMessageBox=function(msg) error('Messaggio inatteso: '..msg) end}
local function name_item(id,text) items[id].P_NAME=text end
reset()
local right,result=M.split_timed_item(reaper,1,6,items[1].P_NOTES,name_item)
eq(right,2);eq(items[1].P_NOTES,'A B\n');eq(items[2].P_NOTES,'C D')
near(items[1].D_LENGTH,5);near(items[2].D_LENGTH,3);near(items[2].D_POSITION,15)
eq(items[1]['P_EXT:RythmoBand_HIGHLIGHT'],'C');eq(items[2]['P_EXT:RythmoBand_HIGHLIGHT'],'C')
eq(#M.parse_anchors(items[1]['P_EXT:ZP_GOBBO_ANCHORS']),1)
eq(M.parse_anchors(items[2]['P_EXT:ZP_GOBBO_ANCHORS'])[1].offset,1)
eq(items[2]['P_EXT:ZP_GOBBO_TIMING_TEXT'],'C D')
local right_plan=M.reading_plan(items[2].P_NOTES,nil,4,3,120,M.parse_reading_timing(items[2]['P_EXT:ZP_GOBBO_TIMING']))
near(right_plan.events[1].stop,1.5,'tempo della parola conservato')
reaper.Undo_DoUndo2(0);eq(items[2],nil);eq(items[1].P_NOTES,'A B\n\nC D');near(items[1].D_LENGTH,8)
reaper.Undo_DoRedo2(0);eq(items[2].P_NOTES,'C D');near(items[2].D_POSITION,15)
for _,guard in ipairs({'audio','sync','untimed','stale','wrong_project','boundary','split_failure','write_failure'}) do
 reset()
 local expected=items[1].P_NOTES
 if guard=='audio' then items[1].takes=1
 elseif guard=='sync' then items[1]['P_EXT:ZP_SYNC_KEY']='source|123'
 elseif guard=='untimed' then items[1]['P_EXT:ZP_TIMED_SCROLL']=''
 elseif guard=='stale' then expected='testo vecchio'
 elseif guard=='wrong_project' then items={}
 elseif guard=='write_failure' then fail_write=true
 elseif guard=='split_failure' then fail_split=true end
 local id,err=M.split_timed_item(reaper,1,guard=='boundary' and 1 or 6,expected,name_item)
 eq(id,nil,guard);eq(type(err),'string',guard)
 if guard=='write_failure' then eq(items[2],nil,'rollback completo');eq(items[1].P_NOTES,expected)
 elseif guard=='split_failure' then eq(items[2],nil);eq(undo_calls,0,'taglio fallito non annulla azioni precedenti');near(items[1].D_LENGTH,8)
 else eq(split_calls,0,'nessun taglio prima di validare '..guard) end
end
-- Native REAPER returns false for empty P_EXT fields; it is not a write failure.
for _,mode in ipairs({'false_empty','false_all','crlf'}) do
 reset();setter_mode=mode
 items[1]['P_EXT:RythmoBand_HIGHLIGHT']=''
 items[1]['P_EXT:ZP_GOBBO_ANCHORS']=''
 items[1]['P_EXT:ZP_TIMED_SCROLL_PAUSE_WEIGHT']=''
 local id=assert(M.split_timed_item(reaper,1,6,items[1].P_NOTES,name_item))
 eq(id,2,'verifica contenuto anziché booleano: '..mode)
 eq(items[1].P_NOTES,'A B\n');eq(items[2].P_NOTES,'C D')
 eq(items[2]['P_EXT:ZP_GOBBO_ANCHORS'],'','promemoria vuoti validi')
 eq(undo_calls,0,'nessun rollback spurio')
end
reset();setter_mode='silent_failure'
local id,err=M.split_timed_item(reaper,1,6,items[1].P_NOTES,name_item)
eq(id,nil,'un true senza salvataggio non è successo')
eq(items[2],nil,'rollback su mancata persistenza')
eq(items[1].P_NOTES,'A B\n\nC D');eq(undo_calls,1)
-- Gesture integration in both windows: double click selects, right click explicitly edits/splits.
local font=20
gfx={w=1000,h=700,mouse_cap=1,mouse_x=0,mouse_y=0,
 setfont=function(_,_,size) font=size or font end,measurestr=function(text) return assert(utf8.len(text))*8,font end,
 set=function() end,rect=function() end,roundrect=function() end,line=function() end,circle=function() end,drawstr=function() end,
 showmenu=function() return menu_choice end}
for _,name in ipairs({'02_Gobbo_Verticale.lua','03_Gobbo_Orizzontale.lua'}) do
 reset();now=1
 local path='ZP Studio Suite/'..name;local file=assert(io.open(path));local src=file:read('*a');file:close()
 src=src:gsub('\nLoad%w*Settings%(%)%s*\nInitGUI%(%)%s*\nDrawGUI%(%)%s*$',[[
return {selection=function() return gobbo_word_selection end,editor=function() return inline_edit end,font=function() return master_font_size end}
]])
 local env=setmetatable({},{__index=_G});env._G=env
 local api=assert(load(src,'@'..path,'t',env))();env.UpdateItems=function() end
 env.UpdateSubtitleItemName(1,string.rep('È',78)..'città altra parola')
 eq(utf8.len(items[1].P_NAME)~=nil,true,'nome del pezzo non spezza lettere UTF-8')
 writes=0
 local text=items[1].P_NOTES
 local plan=M.reading_plan(text,{'A B','','C D'},4,8,120)
 local item={item=1,notes=text,timed_scroll=true,word_plan=plan,reading_plan=plan,lines={'A B','','C D'},anchors={},speaker_prefix='',prefix_w=0}
 gfx.mouse_cap=1;gfx.mouse_x=0;gfx.mouse_y=api.font()*1.55*2+1
 if name:sub(1,2)=='03' then gfx.mouse_x=32;gfx.mouse_y=1 end
 env.HandleSubtitleEditDoubleClick(item,0,0,1000,600);now=1.2;env.HandleSubtitleEditDoubleClick(item,0,0,1000,600)
 eq(api.editor(),nil,'doppio clic non apre l’editor')
 eq(api.selection().first,6,'doppio clic fissa la parola C')
 eq(writes,0,'la selezione non modifica il progetto')
 -- The text has moved under the pointer, but the chosen word is retained.
 gfx.mouse_x=0;gfx.mouse_y=1;gfx.mouse_cap=2;menu_choice=1
 env.HandleGobboWordAnchorMenu(item,0,0,1000,600)
 eq(api.editor().cursor,6,'Edita testo è esplicito e riapre al punto scelto')
 env.ProcessInlineSubtitleEditKey(27);eq(api.editor(),nil)
 -- Direct split of the chosen point through the command used by the menu.
 env.GobboSplitSelectedWord()
 eq(items[2].P_NOTES,'C D','divisione usa la parola scelta, non il punto ora sotto il mouse')
 eq(api.selection(),nil,'selezione invalidata dopo il taglio')
end
print(n..' verifiche divisione e gesti Gobbo OK')
print('TUTTI OK')
