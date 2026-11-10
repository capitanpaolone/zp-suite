-- @noindex
-- Copioni: trasformazioni pure UTF-8 e adattatori OS, senza dipendenze da REAPER.
local M = {}
local function trim(s) return s:match('^%s*(.-)%s*$') end
function M.normalize(s, collapse_pauses)
    s = tostring(s or ''):gsub('\r\n','\n'):gsub('\r','\n')
    for _, c in ipairs({'\194\160','\226\128\175','\226\128\128','\226\128\129','\226\128\130','\226\128\131','\226\128\132','\226\128\133','\226\128\134','\226\128\135','\226\128\136','\226\128\137','\226\128\138','\227\128\128'}) do s=s:gsub(c,' ') end
    for _, c in ipairs({'\226\128\139','\226\128\140','\226\128\141','\239\187\191','\194\173','\226\129\160'}) do s=s:gsub(c,'') end
    for _, c in ipairs({'“','”','„','«','»'}) do s=s:gsub(c,'"') end
    for _, c in ipairs({'‘','’','‚'}) do s=s:gsub(c,"'") end
    for _, c in ipairs({'–','—','−'}) do s=s:gsub(c,'-') end
    s=s:gsub('[%z\1-\8\11\12\14-\31\127]',''):gsub('[\t ]+',' '):gsub(' *\n *','\n')
    s=trim(s)
    if collapse_pauses then s=s:gsub('\n\n\n+','\n\n') end
    return s
end
function M.join_lines(s)
    s=M.normalize(s)
    local out={}
    for line in (s..'\n'):gmatch('(.-)\n') do
        local prev=out[#out]
        if prev and prev~='' and line~='' and not prev:match('[%.!%?:;]$') and not line:match('^[-•]') and not line:match('^%d+[.)]') then
            out[#out]=prev..' '..line
        else out[#out+1]=line end
    end
    return table.concat(out,'\n')
end
function M.breathe(s) return (s:gsub('([%.!%?]) +','%1\n')) end
local lower,upper={},{}
local a,b={'À','È','É','Ì','Ò','Ù','Á','Í','Ó','Ú','Ä','Ë','Ï','Ö','Ü','Ç','Ñ'},{'à','è','é','ì','ò','ù','á','í','ó','ú','ä','ë','ï','ö','ü','ç','ñ'}
for i,c in ipairs(a) do lower[c]=b[i]; upper[b[i]]=c end
function M.lower(s) s=s:lower(); for c,v in pairs(lower) do s=s:gsub(c,v) end; return s end
function M.upper(s) s=s:upper(); for c,v in pairs(upper) do s=s:gsub(c,v) end; return s end
function M.sentence_case(s)
    s=M.lower(s); local start=true; local out={}
    for _,c in utf8.codes(s) do
        local ch=utf8.char(c)
        if start and (ch:match('%a') or upper[ch]) then ch=M.upper(ch); start=false end
        out[#out+1]=ch
        if ch:match('[%.!%?\n]') then start=true end
    end
    return table.concat(out)
end
function M.stats(s)
    local words,pauses=0,0
    local raw=tostring(s or ''):gsub('\r\n','\n'):gsub('\r','\n')
    for _ in M.normalize(raw):gmatch('%S+') do words=words+1 end
    if raw:match('%S') then
        for line in (raw..'\n'):gmatch('([^\n]*)\n') do
            if not line:match('%S') then pauses=pauses+1 end
        end
    end
    return words,pauses
end
-- Posizione sorgente dal testo disegnato con spazi compressi, sempre su confini UTF-8.
function M.cursor_in_words(text, first, last, px, measure)
    local x,best=0,first
    local space=measure(' ')
    for offset,word in text:sub(first,last):gmatch('()(%S+)') do
        local a=first+offset-1
        local width=measure(word)
        if px<=x+width then
            best=a
            local previous=0
            for byte in utf8.codes(word) do
                local right=measure(word:sub(1,byte-1))
                if px-x<(previous+right)/2 then return best end
                best=a+byte-1; previous=right
            end
            if px-x<(previous+width)/2 then return best end
            return a+#word
        end
        best=a+#word
        if px<x+width+space/2 then return best end
        x=x+width+space
    end
    return best
end
function M.same_words(a,b)
    local function fold(s) return trim(tostring(s):gsub('%s+',' ')) end
    return fold(a)==fold(b)
end
local function entity(s)
    s=s:gsub('&#x(%x+);',function(n) local v=tonumber(n,16); return v and v<=0x10ffff and utf8.char(v) or '' end)
    s=s:gsub('&#(%d+);',function(n) local v=tonumber(n); return v and v<=0x10ffff and utf8.char(v) or '' end)
    local named={lt='<',gt='>',amp='&',quot='"',apos="'"}
    return (s:gsub('&(%a+);',named))
end
local function attr(tag,name) return tag:match(name..'=["\'](.-)["\']') end
function M.docx(xml)
    xml=xml:gsub('<w:p%s*/>','<w:p></w:p>'):gsub('<w:p(%s[^>]-)/>','<w:p%1></w:p>')
    xml=xml:gsub('<w:del[%s>].-</w:del>',''):gsub('<w:instrText[%s>].-</w:instrText>','')
    local paragraphs,highlights={},{}
    for p in xml:gmatch('<w:p[%s>](.-)</w:p>') do
        local chunks={}
        for run in p:gmatch('<w:r[%s>](.-)</w:r>') do
            local out={}
            for token in run:gmatch('<[^>]+>[^<]*') do
                if token:match('^<w:t[%s>]') then out[#out+1]=entity(token:gsub('^<[^>]+>',''))
                elseif token:match('^<w:br[%s/>]') or token:match('^<w:cr[%s/>]') then out[#out+1]='\n'
                elseif token:match('^<w:tab[%s/>]') then out[#out+1]=' ' end
            end
            local text=table.concat(out); chunks[#chunks+1]=text
            local bold=run:match('<w:b[%s/>][^>]*>')
            local hl=run:match('<w:highlight%s[^>]*>')
            if (bold and not bold:match('w:val=["\'](0)["\']') and not bold:match('w:val=["\']false["\']')) or (hl and attr(hl,'w:val')=='yellow') then
                if trim(text)~='' then highlights[#highlights+1]=trim(text) end
            end
        end
        paragraphs[#paragraphs+1]=table.concat(chunks)
    end
    return M.normalize(table.concat(paragraphs,'\n')),highlights
end
function M.odt(xml,styles_xml)
    local styles={}
    for _,source in ipairs({styles_xml or '',xml}) do
        for tag,body in source:gmatch('(<style:style%s[^>]*>)(.-)</style:style>') do
            local name=attr(tag,'style:name')
            if name then styles[name]={parent=attr(tag,'style:parent%-style%-name'), marked=body:find('fo:font%-weight=["\']bold["\']') or body:lower():find('fo:background%-color=["\']#ffff00["\']')} end
        end
    end
    local function marked(name,seen)
        seen=seen or {}; if not name or seen[name] or not styles[name] then return false end
        seen[name]=true; return styles[name].marked or marked(styles[name].parent,seen)
    end
    local paragraphs,highlights={},{}
    xml=xml:gsub('<text:h([%s>])','<text:p%1'):gsub('</text:h>','</text:p>'):gsub('<text:p%s*/>','<text:p></text:p>'):gsub('<text:p(%s[^>]-)/>','<text:p%1></text:p>')
    for tag,body in xml:gmatch('(<text:p[^>]*>)(.-)</text:p>') do
        local out,stack={}, {marked(attr(tag,'text:style%-name'))}
        for token in (body..'<end/>'):gmatch('([^<]*<[^>]+>)') do
            local text,t=token:match('^(.-)(<[^>]+>)$')
            text=entity(text or '')
            out[#out+1]=text
            if stack[#stack] and trim(text)~='' then highlights[#highlights+1]=trim(text) end
            if t:match('^<text:span[%s>]') then stack[#stack+1]=stack[#stack] or marked(attr(t,'text:style%-name'))
            elseif t:match('^</text:span') then if #stack>1 then table.remove(stack) end
            elseif t:match('^<text:line%-break[%s/>]') then out[#out+1]='\n'
            elseif t:match('^<text:tab[%s/>]') then out[#out+1]=' '
            elseif t:match('^<text:s[%s/>]') then out[#out+1]=string.rep(' ',math.min(10000,tonumber(attr(t,'text:c')) or 1)) end
        end
        paragraphs[#paragraphs+1]=table.concat(out)
    end
    return M.normalize(table.concat(paragraphs,'\n')),highlights
end
-- RTF: gruppi/destinazioni, escape, Unicode signed e fallback \ucN.
function M.rtf(s)
    local out,stack={},{}; local state={skip=false,uc=1}; local i,fallback=1,0
    local ignored={fonttbl=true,colortbl=true,stylesheet=true,info=true,pict=true,object=true,header=true,footer=true,fldinst=true}
    local cp1252={[128]=8364,[130]=8218,[131]=402,[132]=8222,[133]=8230,[145]=8216,[146]=8217,[147]=8220,[148]=8221,[150]=8211,[151]=8212}
    local pending
    local function emit(c)
        if fallback>0 then fallback=fallback-1 elseif not state.skip then out[#out+1]=c end
    end
    while i<=#s do
        local c=s:sub(i,i)
        if c=='{' then stack[#stack+1]=state; state={skip=state.skip,uc=state.uc}; i=i+1
        elseif c=='}' then state=table.remove(stack) or state; i=i+1
        elseif c=='\\' then
            local rest=s:sub(i+1); local hex=rest:match("^'(%x%x)")
            if hex then local n=tonumber(hex,16); emit(utf8.char(cp1252[n] or n)); i=i+4
            else
                local word,num,space=rest:match('^(%a+)(%-?%d*)( ?)')
                if word then
                    i=i+1+#word+#num+#space; local n=tonumber(num)
                    if word=='bin' and n then i=i+math.max(0,n)
                    elseif ignored[word] then state.skip=true
                    elseif word=='uc' then state.uc=math.max(0,n or 1)
                    elseif word=='u' and n then
                        n=n<0 and n+65536 or n
                        if n>=0xd800 and n<=0xdbff then pending=n
                        elseif n>=0xdc00 and n<=0xdfff and pending then if not state.skip then out[#out+1]=utf8.char(0x10000+(pending-0xd800)*1024+n-0xdc00) end; pending=nil
                        elseif not state.skip then out[#out+1]=utf8.char(n); pending=nil end
                        fallback=state.uc
                    elseif word=='par' or word=='line' then emit('\n')
                    elseif word=='tab' then emit(' ')
                    elseif word=='emdash' or word=='endash' then emit('-') end
                else
                    local sym=rest:sub(1,1); i=i+2
                    if sym=='*' then state.skip=true elseif sym=='~' then emit(' ') elseif sym=='\\' or sym=='{' or sym=='}' then emit(sym) end
                end
            end
        elseif c=='\n' or c=='\r' then i=i+1
        else local n=c:byte(); emit(n>=128 and utf8.char(cp1252[n] or n) or c); i=i+1 end
    end
    return M.normalize(table.concat(out))
end
local function quote(s) return "'"..s:gsub("'","'\\''").."'" end
local function psquote(s) return "'"..s:gsub("'","''").."'" end
local function capture(command,runner)
    if runner then return runner(command) end
    local p=io.popen(command,'r'); if not p then return nil,'Impossibile avviare il convertitore.' end
    local data=p:read('*a'); local ok=p:close()
    if not ok then return nil,'Comando non disponibile o documento non leggibile.' end
    return data
end
local function powershell(script)
    -- EncodedCommand evita cmd.exe expansion (% ! & e virgolette nei percorsi).
    local bytes={}
    for _,n in utf8.codes(script) do
        if n>65535 then n=n-65536; local hi,lo=0xd800+(n>>10),0xdc00+(n&1023); bytes[#bytes+1]=string.char(hi&255,hi>>8,lo&255,lo>>8)
        else bytes[#bytes+1]=string.char(n&255,n>>8) end
    end
    local s=table.concat(bytes); local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local out={}
    for j=1,#s,3 do local a,b,c=s:byte(j,j+2); local v=(a<<16)|((b or 0)<<8)|(c or 0)
        out[#out+1]=alphabet:sub((v>>18)+1,(v>>18)+1)..alphabet:sub(((v>>12)&63)+1,((v>>12)&63)+1)..(b and alphabet:sub(((v>>6)&63)+1,((v>>6)&63)+1) or '=')..(c and alphabet:sub((v&63)+1,(v&63)+1) or '=') end
    return 'powershell.exe -NoProfile -NonInteractive -EncodedCommand '..table.concat(out)
end
function M.clipboard(api,osname,runner)
    if api and api.CF_GetClipboard then local ok,s=pcall(api.CF_GetClipboard,''); if ok and type(s)=='string' then return M.normalize(s) end end
    local cmd=osname:match('Win') and powershell('[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new(); Get-Clipboard -Raw') or (osname:match('OSX') and 'pbpaste' or 'sh -c "wl-paste --no-newline 2>/dev/null || xclip -selection clipboard -o 2>/dev/null || xsel --clipboard --output"')
    local s,err=capture(cmd,runner); if not s then return nil,err end
    return M.normalize(s)
end
function M.read_file(path,osname,runner)
    local ext=path:match('%.([^%.]+)$'); ext=ext and ext:lower()
    if ext=='txt' or ext=='rtf' then
        local f,err=io.open(path,'rb'); if not f then return nil,err end
        local s=f:read('*a'); f:close()
        if ext=='rtf' then return M.rtf(s),{} end
        if not utf8.len(s) then return nil,'Il file TXT deve essere UTF-8.' end
        return M.normalize(s),{}
    end
    if ext~='docx' and ext~='odt' then return nil,'Formato supportato: .docx, .odt, .rtf, .txt.' end
    local function member(name)
        local cmd
        if osname:match('Win') then
            cmd=powershell("$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.IO.Compression.FileSystem; [Console]::OutputEncoding=[System.Text.UTF8Encoding]::new(); $z=[IO.Compression.ZipFile]::OpenRead("..psquote(path).."); try { $e=$z.GetEntry("..psquote(name).."); if (!$e) { exit 2 }; $r=[IO.StreamReader]::new($e.Open()); try { [Console]::Write($r.ReadToEnd()) } finally { $r.Dispose() } } finally { $z.Dispose() }")
        else cmd='unzip -p '..quote(path)..' '..quote(name)..' 2>/dev/null' end
        return capture(cmd,runner)
    end
    local xml,err=member(ext=='docx' and 'word/document.xml' or 'content.xml')
    if not xml or xml=='' then return nil,err or 'XML del documento mancante.' end
    if ext=='docx' then return M.docx(xml) end
    local styles=member('styles.xml'); return M.odt(xml,styles)
end
-- Segmenti di lettura: le righe vuote consumano tempo senza avanzare la parola.
function M.reading_plan(text, lines, pause_weight, duration, wpm, timing)
    text=tostring(text or ''):gsub('\r\n','\n'):gsub('\r','\n')
    pause_weight=math.max(0.01,tonumber(pause_weight) or 4)
    local word_weight=1
    if duration and duration>0 then
        local words,pauses=0,0
        for line in (text..'\n'):gmatch('(.-)\n') do
            if not line:match('%S') then pauses=pauses+1 else for _ in line:gmatch('%S+') do words=words+1 end end
        end
        local seconds=pause_weight*60/math.max(40,math.min(240,wpm or 120))
        if words>0 and duration>pauses*seconds then
            word_weight=(duration-pauses*seconds)/words
            pause_weight=seconds
        end
    end

    local plan={events={},rows={},total=0,words=0}
    local source=1
    for line in (text..'\n'):gmatch('(.-)\n') do
        if not line:match('%S') then
            plan.events[#plan.events+1]={pause=true,first=source,last=source+#line,word=plan.words,start=plan.total,stop=plan.total+pause_weight}
            plan.total=plan.total+pause_weight
        else
            for pos,word in line:gmatch('()(%S+)') do
                plan.words=plan.words+1
                plan.events[#plan.events+1]={first=source+pos-1,last=source+pos+#word-2,word=plan.words,start=plan.total,stop=plan.total+word_weight}
                plan.total=plan.total+word_weight
            end
        end
        source=source+#line+1
    end
    if timing and #timing==#plan.events then
        local total=0;local valid=true
        for _,value in ipairs(timing) do
            if type(value)~='number' or value<0 or value~=value or value==math.huge then valid=false;break end
            total=total+value
        end
        if valid and total>0 and total<math.huge then
            local cursor=0
            for i,event in ipairs(plan.events) do event.start=cursor;cursor=cursor+timing[i];event.stop=cursor end
            plan.total=total
        end
    end
    -- La geometria può cambiare con il font; i tempi e gli offset sorgente restano comuni.
    if not lines then lines={};for line in (text..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end end
    local event_index=1
    for row,line in ipairs(lines) do
        local count=0;for _ in line:gmatch('%S+') do count=count+1 end
        local info={first=nil,last=nil,start=nil,stop=nil}
        for col=1,math.max(1,count) do
            local event=plan.events[event_index]
            if not event then break end
            event.row=row-1+(count>0 and (col-1)/count or 0)
            event.row_end=event.pause and event.row or row-1+col/count
            info.first=info.first or event.first;info.last=event.last
            info.start=info.start or event.start;info.stop=event.stop
            event_index=event_index+1
        end
        plan.rows[row]=info
    end
    return plan
end
function M.reading_state(plan, progress)
    if not plan or #plan.events==0 then return {word=0,word_phase=0,row=0,paused=false} end
    local u=math.max(0,math.min(1,progress or 0))*plan.total
    local lo,hi=1,#plan.events
    while lo<hi do local mid=math.floor((lo+hi)/2);if u<plan.events[mid].stop then hi=mid else lo=mid+1 end end
    local e=plan.events[lo]
    local f=math.max(0,math.min(1,(u-e.start)/math.max(0.000001,e.stop-e.start)))
    return {word=e.word,word_phase=e.pause and e.word or e.word-1+f,
        row=(e.row or 0)+((e.row_end or e.row or 0)-(e.row or 0))*f,
        paused=e.pause or false,event=e,fraction=f}
end
function M.progress_for_cursor(plan,cursor)
    for _,e in ipairs(plan.events) do
        if cursor<=e.last then
            local f=e.pause and 0 or math.max(0,math.min(1,(cursor-e.first)/math.max(1,e.last-e.first+1)))
            return (e.start+(e.stop-e.start)*f)/math.max(0.000001,plan.total)
        end
    end
    return 1
end
function M.progress_for_row(plan,row)
    local index=math.max(1,math.min(#plan.rows,math.floor(row)+1))
    local r=plan.rows[index]
    if not r or not r.start then return 0 end
    local f=math.max(0,math.min(1,row-(index-1)))
    return (r.start+(r.stop-r.start)*f)/math.max(0.000001,plan.total)
end

-- Identità per GUID: rinumerare o rinominare i marker non cambia il collegamento.
function M.parse_anchors(raw)
    local anchors={}
    for guid,offset in tostring(raw or ''):gmatch('([^%s]+)[\t ]+(%d+)') do
        if guid:match('^%{[%x%-]+%}$') then anchors[#anchors+1]={guid=guid,offset=tonumber(offset)} end
    end
    return anchors
end
function M.serialize_anchors(anchors)
    local out={}
    for _,a in ipairs(anchors or {}) do out[#out+1]=a.guid..'\t'..tostring(math.max(0,math.floor(a.offset))) end
    return table.concat(out,'\n')
end
function M.relocate_anchors(old,new,anchors)
    local prefix=0
    while prefix<math.min(#old,#new) and old:byte(prefix+1)==new:byte(prefix+1) do prefix=prefix+1 end
    while prefix>0 and old:byte(prefix+1) and old:byte(prefix+1)>=128 and old:byte(prefix+1)<192 do prefix=prefix-1 end
    local suffix=0
    while suffix<math.min(#old-prefix,#new-prefix) and old:byte(#old-suffix)==new:byte(#new-suffix) do suffix=suffix+1 end
    local old_end=#old-suffix+1
    local out={}
    for _,a in ipairs(anchors or {}) do
        local offset=a.offset
        if offset>prefix and offset>0 then
            if offset>=old_end then offset=offset+#new-#old else offset=0 end
        end
        out[#out+1]={guid=a.guid,offset=offset}
    end
    return out
end
function M.timeline_markers(api)
    local out={}
    if not api.CountProjectMarkers or not api.GetSetProjectInfo_String then return out end
    local _,nm,nr=api.CountProjectMarkers(0)
    for i=0,nm+nr-1 do
        local ok,isregion,pos,ending,name,id=api.EnumProjectMarkers( i )
        if ok and not isregion then
            local success,guid=api.GetSetProjectInfo_String(0,'MARKER_GUID:'..i,'',false)
            if success and guid~='' then out[guid]={guid=guid,pos=pos,name=name,id=id} end
        end
    end
    return out
end
-- Promemoria: la posizione del marker non modifica mai i tempi del lettore.
function M.reminder_markers(plan,anchors,markers)
    local out={}
    for _,a in ipairs(anchors or {}) do
        local marker=markers[a.guid]
        if marker and a.offset>0 then
            out[#out+1]={offset=a.offset,guid=a.guid,name=marker.name,pos=marker.pos}
        end
    end
    return out
end
function M.parse_reading_timing(raw)
    raw=tostring(raw or '')
    if raw:sub(1,3)~='v1|' then return nil end
    local out={}
    for token in raw:sub(4):gmatch('[^;]+') do
        local value=tonumber(token)
        if not value or value<0 or value~=value or value==math.huge then return nil end
        out[#out+1]=value
    end
    return #out>0 and out or nil
end
function M.serialize_reading_timing(values)
    local out={}
    for _,value in ipairs(values or {}) do out[#out+1]=(string.format('%.17g',value):gsub(',','.')) end
    return 'v1|'..table.concat(out,';')
end
function M.word_event(plan,offset)
    for _,event in ipairs(plan.events) do
        if not event.pause and offset>=event.first and offset<=event.last+1 then return event end
    end
end
function M.split_reading_text(text,offset,plan,duration,anchors)
    local event=M.word_event(plan,offset)
    if not event then return nil,'Seleziona una parola del copione.' end
    local cut=event.first
    local left,right=text:sub(1,cut-1),text:sub(cut)
    if not left:match('%S') or not right:match('%S') then return nil,'Il taglio deve lasciare testo in entrambi gli item.' end
    -- Il confine tra item sostituisce l’ultimo accapo: non deve diventare una pausa in più.
    local boundary=left:match('\n[ \t]*$') or ''
    if boundary~='' then left=left:sub(1,#left-#boundary) end
    local a,b={},{}
    local scale=duration/math.max(0.000001,plan.total)
    for _,e in ipairs(plan.events) do
        local values=e.first<cut and a or b
        values[#values+1]=(e.stop-e.start)*scale
    end
    local lp,rp=M.reading_plan(left),M.reading_plan(right)
    if #lp.events~=#a or #rp.events~=#b then return nil,'Impossibile conservare le pause in questo punto di taglio.' end
    local left_len=duration*event.start/plan.total
    local right_len=duration-left_len
    if left_len<=0.000001 or right_len<=0.000001 then return nil,'Il punto di taglio è troppo vicino al bordo dell’item.' end
    local la,ra={},{}
    for _,anchor in ipairs(anchors or {}) do
        if anchor.offset>0 and anchor.offset>=cut then
            ra[#ra+1]={guid=anchor.guid,offset=anchor.offset-cut+1}
        else la[#la+1]={guid=anchor.guid,offset=anchor.offset} end
    end
    return {left={text=left,timing=a,anchors=la,len=left_len},right={text=right,timing=b,anchors=ra,len=right_len},cut=cut,boundary=boundary}
end
-- Operazione esplicita: soltanto item testo autonomi, mai audio o testi gestiti da ZP_SYNC.
function M.split_timed_item(api,item,offset,expected_text,name_item)
    if not api.ValidatePtr2(0,item,'MediaItem*') then return nil,'L’item selezionato non è più disponibile.' end
    local function get(key) local _,value=api.GetSetMediaItemInfo_String(item,key,'',false);return value or '' end
    if get('P_EXT:ZP_TIMED_SCROLL')~='1' or get('P_EXT:ZP_SYNC_KEY')~='' or api.GetMediaItemNumTakes(item)>0 then
        return nil,'La divisione dal copione è disponibile solo per testi temporizzati autonomi.'
    end
    local text=get('P_NOTES'):gsub('\r\n','\n'):gsub('\r','\n')
    if text~=expected_text then return nil,'Il testo è cambiato: seleziona di nuovo la parola.' end
    local pace_raw=get('P_EXT:ZP_TIMED_SCROLL_WPM')
    local pause_raw=get('P_EXT:ZP_TIMED_SCROLL_PAUSE_WEIGHT')
    local highlights=get('P_EXT:RythmoBand_HIGHLIGHT')
    local pos=api.GetMediaItemInfo_Value(item,'D_POSITION')
    local len=api.GetMediaItemInfo_Value(item,'D_LENGTH')
    local wpm=tonumber(get('P_EXT:ZP_TIMED_SCROLL_WPM')) or 120
    local pause=tonumber(get('P_EXT:ZP_TIMED_SCROLL_PAUSE_WEIGHT')) or 4
    local timing=get('P_EXT:ZP_GOBBO_TIMING_TEXT')==text and M.parse_reading_timing(get('P_EXT:ZP_GOBBO_TIMING')) or nil
    local plan=M.reading_plan(text,nil,pause,len,wpm,timing)
    local result,err=M.split_reading_text(text,offset,plan,len,M.parse_anchors(get('P_EXT:ZP_GOBBO_ANCHORS')))
    if not result then return nil,err end
    api.Undo_BeginBlock()
    local right=api.SplitMediaItem(item,pos+result.left.len)
    if not right then api.Undo_EndBlock('ZP Gobbo: divisione non eseguita',-1);return nil,'REAPER non ha diviso l’item.' end
    local ok,failure=pcall(function()
        for _,part in ipairs({{id=item,data=result.left},{id=right,data=result.right}}) do
            local function set(key,value)
                -- La risposta del setter non certifica il valore persistito (specialmente P_EXT vuoti).
                api.GetSetMediaItemInfo_String(part.id,key,value,true)
                local _,saved=api.GetSetMediaItemInfo_String(part.id,key,'',false)
                saved=saved or ''
                if key=='P_NOTES' then saved=saved:gsub('\r\n','\n'):gsub('\r','\n') end
                if saved~=value then error('Verifica scrittura: '..key,0) end
            end
            set('P_NOTES',part.data.text)
            set('P_EXT:ZP_TIMED_SCROLL','1')
            set('P_EXT:ZP_TIMED_SCROLL_WPM',pace_raw)
            set('P_EXT:ZP_TIMED_SCROLL_PAUSE_WEIGHT',pause_raw)
            set('P_EXT:RythmoBand_HIGHLIGHT',highlights)
            set('P_EXT:ZP_GOBBO_ANCHORS',M.serialize_anchors(part.data.anchors))
            set('P_EXT:ZP_GOBBO_TIMING',M.serialize_reading_timing(part.data.timing))
            set('P_EXT:ZP_GOBBO_TIMING_TEXT',part.data.text)
            name_item(part.id,part.data.text)
            api.UpdateItemInProject(part.id)
        end
        api.SetMediaItemSelected(item,false);api.SetMediaItemSelected(right,true)
    end)
    api.Undo_EndBlock('ZP Gobbo: dividi prima della parola',-1)
    if not ok then
        api.Undo_DoUndo2(0)
        return nil,'Divisione annullata: impossibile salvare il contenuto dei due item.'
    end
    api.UpdateArrange()
    return right,result
end

return M
