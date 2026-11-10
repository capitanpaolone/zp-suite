local n=0
local function eq(a,b,label) n=n+1; assert(a==b,'FAIL '..(label or tostring(n))..': '..tostring(a)..' ~= '..tostring(b)) end
local font=20
local draws={}
gfx={w=1000,h=700,mouse_x=-10,mouse_y=-10,mouse_cap=0,mouse_wheel=0,
 setfont=function(_,_,size) font=size or font end,
 measurestr=function(s) local len=utf8.len(s); assert(len,'UTF-8 non valido misurato');return len*font*0.5,font end,
 set=function() end,rect=function() end,roundrect=function() end,circle=function() end,line=function() end,
 drawstr=function(s) assert(utf8.len(s),'UTF-8 non valido disegnato');draws[#draws+1]={s=s,y=gfx.y} end,
 showmenu=function() return 0 end}
local writes,items={},{}
reaper={GetExtState=function() return '1' end,SetExtState=function() end,GetOS=function() return 'OSX64' end,
 time_precise=function() return 1 end,OnStopButton=function() end,
 GetSetMediaItemInfo_String=function(item,key,value,set)
   item=items[item]; if set then item[key]=value;writes[#writes+1]=key end;return true,item[key] or ''
 end,
 SetMediaItemInfo_Value=function(...)
   assert(select('#',...)==3,'API REAPER: attesi tre argomenti')
   local item,key,val=...;items[item][key]=val;writes[#writes+1]=key
 end,
 GetMediaItemInfo_Value=function(item,key) return items[item][key] or 0 end,
 UpdateItemInProject=function() end,Undo_BeginBlock=function() end,Undo_EndBlock=function() end,
 UpdateArrange=function() end,GetProjectStateChangeCount=function() return 0 end}
for _,name in ipairs({'02_Gobbo_Verticale.lua','03_Gobbo_Orizzontale.lua'}) do
 local path='ZP Studio Suite/'..name
 local f=assert(io.open(path));local src=f:read('*a');f:close()
 src=assert(src:gsub('\nLoad%w*Settings%(%)%s*\nInitGUI%(%)%s*\nDrawGUI%(%)%s*$',[[
return {get=function() return inline_edit end,set=function(e) inline_edit=e end,font=function() return master_font_size end}
]]))
 local env=setmetatable({},{__index=_G});env._G=env
 local api=assert(load(src,'@'..path,'t',env))()
 assert(api,'startup suffix non intercettato')
 env.UpdateItems=function() end;env.RecalculateDocumentLayout=function() end;env.RecalculateLayout=function() end
 env.RefreshCachedSubtitleItem=function() return true end
 items[1]={P_NOTES='È già qui.',D_LENGTH=99,['P_EXT:ZP_TIMED_SCROLL']='1',['P_EXT:ZP_TIMED_SCROLL_WPM']='120',['P_EXT:RythmoBand_HIGHLIGHT']='già'}
 writes={};env.StartInlineSubtitleEdit(1,20,20,600,200);env.InitInlineCopione()
 local e=api.get();eq(e.timed_existing,true,name..' timed')
 env.InlineSetSelection(1,#e.text+1);env.InlineInsertText(string.rep('È già qui.\n\n',100))
 draws={};env.DrawInlineSubtitleEditor();e=api.get()
 eq(e.viewport_bottom<gfx.h-90,true,'footer dentro finestra');eq(e.scroll>0,true,'cursore finale visibile')
 local before=e.scroll;e.wheel=120;env.DrawInlineSubtitleEditor();eq(e.scroll<before,true,'rotella indipendente')
 eq(#writes,0,'nessuna scrittura durante editing')
 -- Accent cursor positions never split UTF-8.
 e.text='È già qui.';e.cursor=1;e.lines=nil;e.layout_text=nil;env.DrawInlineSubtitleEditor()
 for dx=0,110,3 do env.InlineCursorFromPoint(e.text_x+dx,e.viewport_top+2);eq(utf8.len(e.text:sub(1,e.cursor-1))~=nil,true,'cursore UTF-8') end
 env.InlineSetSelection(1,3);env.InlineToggleHighlight();eq(#writes,0,'evidenziazione differita')
 env.InlineRestoreUndo();eq(env.InlineHighlightRaw(),'già','undo evidenziazione')
 env.ProcessInlineSubtitleEditKey(27);eq(api.get(),nil,'annulla');eq(items[1].P_NOTES,'È già qui.','timeline invariata')
 -- No-op Save preserves an item whose length was calibrated manually.
 env.StartInlineSubtitleEdit(1,20,20,600,200);env.SaveInlineSubtitleEdit();eq(items[1].D_LENGTH,99,'salvataggio senza cambiamenti')
 -- Explicit opt-out preserves length while saving changed text.
 env.StartInlineSubtitleEdit(1,20,20,600,200);env.InitInlineCopione();e=api.get();e.recalculate=false
 env.InlineSetSelection(1,#e.text+1);env.InlineInsertText('nuovo testo molto più lungo');env.SaveInlineSubtitleEdit()
 eq(items[1].D_LENGTH,99,'durata manuale preservata');eq(items[1].P_NOTES,'nuovo testo molto più lungo','testo salvato')
 env.StartInlineSubtitleEdit(1,20,20,600,200);env.InitInlineCopione();e=api.get()
 env.InlineSetSelection(1,#e.text+1);env.InlineInsertText('uno due');env.SaveInlineSubtitleEdit()
 eq(items[1].D_LENGTH<99,true,'durata ricalcolata')
 -- Small window and 100-line document: footer and viewport stay apart.
 gfx.w,gfx.h=420,320
 env.StartInlineSubtitleEdit(1,20,20,600,200);env.InitInlineCopione();e=api.get()
 e.text=string.rep('È già.\n',100);e.cursor=#e.text+1
 env.DrawInlineSubtitleEditor();eq(e.viewport_bottom<=gfx.h-102,true,'viewport piccolo')

 -- The click that opens the editor chooses the source insertion point.
 api.set(nil);gfx.w,gfx.h=1000,700
 items[1].P_NOTES='È già qui.\n\nAltra riga.'
 gfx.mouse_cap=1;gfx.mouse_x,gfx.mouse_y=28,24
 env.StartInlineSubtitleEdit(1,20,20,600,200,28,24)
 e=api.get();local clicked=e.cursor
 eq(clicked,1,'doppio clic: inizio parola cliccata')
 env.DrawInlineSubtitleEditor();eq(e.cursor,clicked,'il clic di apertura non riposiziona il cursore')
 gfx.mouse_cap=0;env.DrawInlineSubtitleEditor();eq(e.cursor,clicked,'rilascio apertura non riposiziona')
 env.ProcessInlineSubtitleEditKey(27)

 -- An item already scrolled to its middle opens at that line/word, not at either end.
 env.ProcessInlineSubtitleEditKey(27)
 local head={};for i=1,49 do head[#head+1]='riga '..i end
 local prefix=table.concat(head,'\n')..'\n'
 items[1].P_NOTES=prefix..'bersaglio È qui.\n'..string.rep('dopo\n',50)
 gfx.setfont(1,'Arial',api.font())
 local bx,by,cx,cy,width=20,20,28,300,200
 if name:sub(1,2)=='02' then
     by=300-49*api.font()*1.55-4
 else
     bx=28-12-gfx.measurestr(prefix:gsub('\n',' '));width=20000
 end
 gfx.mouse_cap=1;gfx.mouse_x,gfx.mouse_y=cx,cy
 env.StartInlineSubtitleEdit(1,bx,by,width,200,cx,cy);e=api.get()
 eq(e.cursor,#prefix+1,'doppio clic nel mezzo: byte della parola bersaglio')
 env.DrawInlineSubtitleEditor();eq(e.cursor,#prefix+1,'apertura mantiene parola bersaglio')
 eq(e.scroll>0,true,'editor aperto sulla riga centrale')
 gfx.mouse_cap=0;env.DrawInlineSubtitleEditor();env.ProcessInlineSubtitleEditKey(27)
 -- One Shift+Enter adds an empty row and extends the existing item, including short text.
 items[1].P_NOTES='È già qui.';items[1].D_LENGTH=99
 env.StartInlineSubtitleEdit(1,20,20,600,200);env.InitInlineCopione()
 e=api.get();env.InlineSetCursor(4);gfx.mouse_cap=8
 env.ProcessInlineSubtitleEditKey(13);gfx.mouse_cap=0
 eq(e.text,'È \n\ngià qui.','Shift+Invio inserisce una riga vuota')
 eq(env.InlineEstimatedDuration(e.text,e.timed_wpm)>99,true,'anteprima aggiunge tempo alla durata reale')
 env.SaveInlineSubtitleEdit()
 eq(items[1].D_LENGTH>99,true,'la pausa allunga lo stesso item')
 eq(items[1].P_NOTES,'È \n\ngià qui.','pausa salvata nel copione')
 local longer=items[1].D_LENGTH
 -- Undo in the editor restores the original pause and does not touch the timeline.
 env.StartInlineSubtitleEdit(1,20,20,600,200);env.InitInlineCopione()
 e=api.get();env.InlineSetCursor(#e.text+1);gfx.mouse_cap=8
 env.ProcessInlineSubtitleEditKey(13);gfx.mouse_cap=0
 eq(e.text:sub(-2),'\n\n','pausa finale conservata')
 env.InlineRestoreUndo();eq(e.text,items[1].P_NOTES,'Undo pausa')
 env.ProcessInlineSubtitleEditKey(27);eq(items[1].D_LENGTH,longer,'Annulla non allunga')
 -- End pauses survive saving and increase duration as well.
 env.StartInlineSubtitleEdit(1,20,20,600,200);env.InitInlineCopione()
 e=api.get();env.InlineSetCursor(#e.text+1);gfx.mouse_cap=8
 env.ProcessInlineSubtitleEditKey(13);gfx.mouse_cap=0;env.SaveInlineSubtitleEdit()
 eq(items[1].P_NOTES:sub(-2),'\n\n','Salva conserva pausa finale')
 eq(items[1].D_LENGTH>longer,true,'pausa finale aggiunge tempo')
 api.set(nil);gfx.w,gfx.h=1000,700
 if name:sub(1,2)=='03' then
     env.GetRythmoTrack=function() return 17 end
     reaper.GetCursorPosition=function() return 19.5 end
     reaper.AddMediaItemToTrack=function() items[2]={};return 2 end
     env.AddTimedGobboTextItem();env.InlineInsertText('uno\n\ndue')
     env.SaveInlineSubtitleEdit()
     eq(items[2].P_NOTES,'uno\n\ndue','nuovo testo conserva pausa')
     eq(items[2].D_LENGTH>5,true,'nuovo testo include il tempo della pausa')
     eq(items[2].D_POSITION,19.5,'nuovo testo mantiene posizione di inserimento')
 end
end
print(n..' verifiche editor con API REAPER simulate OK')
print('TUTTI OK')
