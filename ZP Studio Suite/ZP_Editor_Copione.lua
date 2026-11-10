-- @noindex
-- Editor gfx comune. Nessuna scrittura in timeline: Salva/Annulla restano al chiamante.
local M={}
function M.draw(e,c)
    local ui,T=c.ui,c.T
    local opening=e.opening_mouse_down
    local pressed,released=c.pressed and not opening,c.released and not opening
    if opening and (gfx.mouse_cap&1)==0 then e.opening_mouse_down=nil end
    local w=math.max(120,math.min(920,gfx.w-16)); local x=(gfx.w-w)/2
    local h=math.min(gfx.h-16,math.max(300,math.floor(gfx.h*0.80)))
    local y=math.max(8,(gfx.h-h)/2)
    local pad=12; local bw=math.max(65,math.min(145,(w-24)/3-4))
    local columns=math.max(1,math.floor((w-24)/(bw+4)))
    local actions={{'Incolla pulito','paste'},{'Carica file…','load'},{'Pulisci spazi','clean'},{'Unisci righe PDF','join'},{'Evidenzia','highlight'},{'Strumenti ▾','tools'}}
    local rows=math.ceil(#actions/columns)
    local top=y+32+rows*28; local footer=102
    local font=math.max(10,math.min(e.font_size or 22,28,math.floor((h-(top-y)-footer)/1.45))); local lh=font*1.45
    local visible=math.max(1,math.floor((h-(top-y)-footer)/lh))
    local bottom=top+visible*lh
    local tw=w-2*pad-14
    gfx.setfont(1,c.font,font)
    if e.layout_text~=e.text or e.layout_w~=tw or e.layout_font~=font then
        e.lines=c.lines(tw); e.layout_text=e.text; e.layout_w=tw; e.layout_font=font
    end
    local lines=e.lines; local ci=#lines
    for i,line in ipairs(lines) do if e.cursor>=line.start and e.cursor<=line.finish+1 then ci=i; break end end
    local maxscroll=math.max(0,#lines-visible)
    e.scroll=math.max(0,math.min(e.scroll or 0,maxscroll))
    if e.center_cursor then
        e.scroll=math.max(0,math.min(maxscroll,ci-1-math.floor(visible/2)))
        e.center_cursor=nil
        e.seen_cursor,e.seen_text=e.cursor,e.text
    elseif e.seen_cursor~=e.cursor or e.seen_text~=e.text then
        if ci<=e.scroll then e.scroll=ci-1 elseif ci>e.scroll+visible then e.scroll=ci-visible end
        e.seen_cursor,e.seen_text=e.cursor,e.text
    end
    if e.wheel and e.wheel~=0 then e.scroll=math.max(0,math.min(maxscroll,e.scroll+(e.wheel>0 and -3 or 3))); e.wheel=0 end
    e.text_x,e.text_y,e.text_w,e.line_h=x+pad,top-e.scroll*lh,tw,lh
    e.viewport_top,e.viewport_bottom=top,bottom
    gfx.set(0.07,0.07,0.09,0.99); ui.fill_round(x,y,w,h,7)
    gfx.setfont(3,'Arial',16,'b'); gfx.set(0.92,0.88,0.78,1); gfx.x,gfx.y=x+pad,y+8
    gfx.drawstr(T(e.title or 'Modifica battuta'),0,x+w-pad,y+29)
    local action
    local function button(bx,by,bw2,bh,label,key,active)
        if ui.draw_button({x=bx,y=by,w=bw2,h=bh},T(label),active,true,released,'neutral') then action=key end
    end
    for i,a in ipairs(actions) do button(x+pad+((i-1)%columns)*(bw+4),y+32+math.floor((i-1)/columns)*28,bw,24,a[1],a[2]) end
    gfx.setfont(1,c.font,font)
    local sa,sb=c.selection()
    for i=e.scroll+1,math.min(#lines,e.scroll+visible) do
        local line=lines[i]; local ly=top+(i-e.scroll-1)*lh
        if sa then
            local a,b=math.max(sa,line.start),math.min(sb,line.finish+1)
            if a<b then
                local before=gfx.measurestr(e.text:sub(line.start,a-1)); local sw=gfx.measurestr(e.text:sub(a,b-1))
                gfx.set(0.18,0.44,0.95,0.55); gfx.rect(x+pad+before,ly,math.min(sw,tw-before),lh,1)
            end
        end
        gfx.set(0.96,0.94,0.89,1); gfx.x,gfx.y=x+pad,ly
        gfx.drawstr(line.text,0,x+pad+tw,ly+lh)
    end
    local over=gfx.mouse_x>=x+pad and gfx.mouse_x<=x+pad+tw and gfx.mouse_y>=top and gfx.mouse_y<bottom
    if pressed and over then
        c.cursor_point(gfx.mouse_x,gfx.mouse_y)
        local now=c.time()
        if e.last_click_time and now-e.last_click_time<0.35 then c.select_word() else e.drag_anchor=e.cursor; e.dragging=true end
        e.last_click_time=now
    end
    if (gfx.mouse_cap&1)==1 and e.dragging then
        if gfx.mouse_y<top then e.scroll=math.max(0,e.scroll-1) elseif gfx.mouse_y>bottom then e.scroll=math.min(maxscroll,e.scroll+1) end
        e.text_y=top-e.scroll*lh
        local pos=c.cursor_at(gfx.mouse_x,math.max(top,math.min(bottom-1,gfx.mouse_y)))
        c.set_selection(e.drag_anchor,pos)
    elseif (gfx.mouse_cap&1)==0 then e.dragging=false end
    if ci>e.scroll and ci<=e.scroll+visible and math.floor(c.time()*2)%2==0 then
        local cw=gfx.measurestr(e.text:sub(lines[ci].start,e.cursor-1)); gfx.set(0.95,0.75,0.28,1)
        gfx.rect(x+pad+math.min(tw-2,cw),top+(ci-e.scroll-1)*lh,2,lh*0.9,1)
    end
    if maxscroll>0 then
        local sx=x+w-16; local sh=bottom-top; local th=math.max(16,sh*visible/#lines)
        gfx.set(0.18,0.18,0.23,1); gfx.rect(sx,top,6,sh,1)
        gfx.set(0.55,0.65,0.75,1); gfx.rect(sx,top+(sh-th)*e.scroll/maxscroll,6,th,1)
        if not opening and (gfx.mouse_cap&1)==1 and gfx.mouse_x>=sx-3 and gfx.mouse_x<=sx+9 and gfx.mouse_y>=top and gfx.mouse_y<=bottom then
            e.scroll=math.floor(math.max(0,math.min(1,(gfx.mouse_y-top-th/2)/math.max(1,sh-th)))*maxscroll)
        end
    end
    local fy=y+h-footer+4
    gfx.setfont(3,'Arial',13); gfx.set(0.85,0.86,0.90,1); gfx.x,gfx.y=x+pad,fy
    local words,pauses=c.stats(e.text)
    local label=string.format(T('Parole: %d · Pause: %d'),words,pauses)
    if c.duration then local secs=c.duration(e.text,e.timed_wpm or 120); label=label..string.format(T(' · Durata: %02d:%02d'),math.floor(secs/60),math.floor(secs%60)) end
    gfx.setfont(3,'Arial',13)
    gfx.drawstr(label,0,x+w-12,fy+18)
    if c.duration then
        button(x+pad,fy+21,28,23,'−','slower'); button(x+pad+32,fy+21,28,23,'+','faster')
        gfx.setfont(3,'Arial',13); gfx.set(0.85,0.86,0.90,1); gfx.x,gfx.y=x+pad+66,fy+25
        gfx.drawstr(tostring(e.timed_wpm or 120)..' '..T('parole/min'),0,x+w-12,fy+42)
    end
    if e.timed_existing then
        if ui.draw_toggle({x=x+pad,y=fy+47,w=w-24,h=22},T('Ricalcola durata item in timeline'),e.recalculate~=false,true,released) then e.recalculate=e.recalculate==false end
    elseif e.imported_highlights and #e.imported_highlights>0 then
        if ui.draw_toggle({x=x+pad,y=fy+47,w=w-24,h=22},T('Importa grassetto/evidenziato'),e.import_highlights,true,released) then e.import_highlights=not e.import_highlights end
    end
    button(x+w-182,y+h-28,80,23,'Annulla','cancel'); button(x+w-96,y+h-28,84,23,'Salva','save',true)
    gfx.setfont(3,'Arial',12); gfx.set(0.68,0.70,0.76,1)
    gfx.x,gfx.y=x+pad,y+h-23
    local hint=(e.mode=='note_new' or e.mode=='note_edit') and T('Shift+Invio: accapo') or T('Shift+Invio: pausa')
    gfx.drawstr(ui.fit_text(hint,math.max(0,w-210)),0,x+w-194,y+h-6)

    return action
end
return M
