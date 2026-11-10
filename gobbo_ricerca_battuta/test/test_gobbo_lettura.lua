local M=dofile('ZP Studio Suite/ZP_Testo_Copione.lua')
local n=0
local function eq(a,b,label) n=n+1;assert(a==b,'FAIL '..(label or tostring(n))..': '..tostring(a)..' ~= '..tostring(b)) end
local function near(a,b,label) n=n+1;assert(math.abs(a-b)<0.000001,'FAIL '..(label or tostring(n))) end
local text='A B\n\nC D'
local plan=M.reading_plan(text,{'A B','','C D'},4,8,120)
near(plan.total,8,'la durata include la pausa effettiva')
local s1,s2=M.reading_state(plan,3.1/8),M.reading_state(plan,4.9/8)
eq(s1.paused,true);eq(s2.paused,true);eq(s1.word,2);eq(s2.word,2)
near(s1.row,s2.row,'la camera resta ferma durante tutta la pausa')
near(s1.word_phase,s2.word_phase,'nessun anticipo della parola successiva')
eq(M.reading_state(plan,5/8).word,3,'ripresa esatta dopo la pausa')
eq(M.reading_state(plan,5/8).paused,false)
local no_pause=M.reading_plan('A B\nC D',nil,4,8,120)
for i=0,99 do eq(M.reading_state(no_pause,i/100).paused,false,'accapo singolo non è pausa') end
local edges=M.reading_plan('\nA\n\n',nil,4,8,120)
eq(M.reading_state(edges,0).word,0);eq(M.reading_state(edges,0).paused,true)
eq(M.reading_state(edges,0.8).paused,true,'pausa finale')
local calibrated=M.reading_plan('A\n\nB',nil,1,99.5,120)
eq(M.reading_state(calibrated,49.6/99.5).paused,true,'pausa da mezzo secondo con durata manuale')
eq(M.reading_state(calibrated,50.1/99.5).word,2)
local guid='{11111111-1111-1111-1111-111111111111}'
local anchors={{guid=guid,offset=6}}
local raw=M.serialize_anchors(anchors)
eq(M.parse_anchors(raw)[1].offset,6)
local moved=M.relocate_anchors('ciao parola','molto ciao parola',anchors)
eq(moved[1].offset,12,'inserimento prima del promemoria')
eq(M.relocate_anchors('ciao parola','ciao ',anchors)[1].offset,0,'parola eliminata: nessuna associazione arbitraria')
local reminders=M.reminder_markers(plan,anchors,{[guid]={pos=500,name='prima'}})
eq(reminders[1].pos,500,'il marker può stare fuori dall’item')
plan.reminders=reminders
local before=M.reading_state(plan,0.6)
plan.reminders=M.reminder_markers(plan,anchors,{[guid]={pos=9999,name='rinominato',id=99}})
local after=M.reading_state(plan,0.6)
eq(before.word,after.word);near(before.row,after.row,'muovere il promemoria non modifica la lettura')
eq(plan.reminders[1].name,'rinominato','GUID conserva il collegamento dopo rinomina/rinumerazione')
eq(#M.reminder_markers(plan,anchors,{}),0,'marker eliminato: nessun marker ricreato')
local drawn,current={},nil
local font=20
gfx={w=1000,h=700,mouse_x=-10,mouse_y=-10,mouse_cap=0,
 setfont=function(_,_,size) font=size or font end,
 measurestr=function(t) return assert(utf8.len(t))*8,font end,
 set=function() end,rect=function() end,roundrect=function() end,circle=function() end,line=function() end,
 drawstr=function(t) drawn[t]=current end}
local native,stored={},{}
reaper={GetExtState=function() return '1' end,SetExtState=function() end,GetOS=function() return 'OSX64' end,time_precise=function() return 1 end,
 CountProjectMarkers=function() return 1,#native,0 end,
 EnumProjectMarkers=function(index) local m=native[index+1];if not m then return 0 end;return index+1,false,m.pos,0,m.name,m.id end,
 GetSetProjectInfo_String=function(_,key) local index=tonumber(key:match(':(%d+)$'));local m=native[index+1];return m~=nil,m and m.guid or '' end,
 GetUserInputs=function() return true,'Promemoria' end,
 AddProjectMarker2=function(_,region,pos,ending,name,id,color) eq(region,false);native[#native+1]={guid=guid,pos=pos,name=name,id=42};return 42 end,
 DeleteProjectMarker=function() error('non deve eliminare marker esistenti') end,
 GetSetMediaItemInfo_String=function(_,key,value,set) if set then stored[key]=value end;return true,stored[key] or '' end,
 Undo_BeginBlock=function() end,Undo_EndBlock=function() end,UpdateArrange=function() end,UpdateItemInProject=function() end,
 SetEditCurPos=function() error('non deve spostare il cursore') end,OnStopButton=function() error('non deve fermare il trasporto') end,
 ShowMessageBox=function(msg) error('Messaggio inatteso: '..msg) end}
for _,name in ipairs({'02_Gobbo_Verticale.lua','03_Gobbo_Orizzontale.lua'}) do
 local path='ZP Studio Suite/'..name;local f=assert(io.open(path));local src=f:read('*a');f:close()
 src=src:gsub('\nLoad%w*Settings%(%)%s*\nInitGUI%(%)%s*\nDrawGUI%(%)%s*$',[[
return {follow=function() word_follow=true end}
]])
 local env=setmetatable({},{__index=_G});env._G=env
 local api=assert(load(src,'@'..path,'t',env))()
 env.UpdateItems=function() end
 local item={item=1,pos=0,len=8,notes=text,timed_scroll=true,reading_plan=plan,highlights={},anchors={},word_x={0,15,30,45},word_w={10,10,10,10},reading_prefix_words=0,prefix_w=0,lines={'A B','','C D'}}
 if name:sub(1,2)=='02' then
     api.follow();env.SetThemeColor=function(kind) current=kind end
     item.reading_state=s1;drawn={}
     env.DrawTextLine('A B',0,0,true,item,0,'text',1)
     env.DrawTextLine('C D',0,40,true,item,2,'text',1)
     eq(drawn.B,'word','ultima parola rimane evidenziata')
     eq(drawn.C,'text','la parola successiva non si accende durante la pausa')
     item.reading_state=M.reading_state(plan,5.1/8);drawn={}
     env.DrawTextLine('C D',0,40,true,item,2,'text',1);eq(drawn.C,'word','evidenziazione riparte dopo la pausa')
     env.AddGobboWordAnchor(item,6,500)
     eq(native[1].pos,500,'promemoria creato alla posizione scelta, liberamente')
     eq(M.parse_anchors(stored['P_EXT:ZP_GOBBO_ANCHORS'])[1].offset,6,'parola associata al promemoria')
 else
     local x1=env.GetWordModeX(item,3.1,1000,100)
     local x2=env.GetWordModeX(item,4.9,1000,100)
     near(x1,x2,'banda orizzontale ferma durante la pausa')
     eq(env.GetWordModeX(item,5.1,1000,100)~=x2,true,'banda riprende dopo la pausa')
     eq(env.GetWordModeX(item,-1,1000,100)~=100,true,'testo futuro non resta sul punto di lettura')
 end
end
print(n..' verifiche pause reali e promemoria OK')
print('TUTTI OK')
