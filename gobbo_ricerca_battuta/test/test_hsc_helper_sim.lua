-- Simulazione del giro completo dell'helper Cue Navigator con un REAPER finto e un Carver finto.
-- Lancio dalla radice del repo. Copre: progetto vecchio -> marker, spostamento, ADD, marker cancellato
-- o aggiunto a mano, cue rosso quando la voce si sposta, clic sull'avviso (comando 8), Riallinea da tasto.
HSC_SYNC_SIM = true
local gm, ext, pext, markers, nextnum, state = {}, {}, {}, {}, 1, 0
local FN = "/progetti/prova.rpp"
local carT = {nchan=4, num=1, recv={}, items={}, mute=0}
local voc  = {nchan=2, num=2, recv={}, items={}, mute=0}
carT.recv = {{src=voc, srcchan=0, dst=2}}
local tracks = {carT, voc}
voc.items = { {pos=0, len=100, take={offs=0, rate=1, file="voce.wav"}, mute=0} }
local CYAN = 36 + 184*256 + 212*65536 | 0x1000000
local function bump() state = state + 1 end
local function resort() table.sort(markers, function(a, b) return a.pos < b.pos end) end
local LAST_TIP
local base_reaper = {
  gmem_attach=function() end, gmem_read=function(i) return gm[i] or 0 end, gmem_write=function(i,v) gm[i]=v end,
  time_precise=function() return CLOCK end, defer=function() end, GetPlayState=function() return 0 end,
  GetMasterTrack=function() return {nchan=2, recv={}, items={}} end,
  CountTracks=function() return #tracks end, GetTrack=function(_,i) return tracks[i+1] end,
  TrackFX_GetCount=function(t) return t==carT and 1 or 0 end, TrackFX_GetFXName=function() return true, "JS: ZP Harmonic Space Carver" end,
  TrackFX_GetNumParams=function() return 1 end, TrackFX_GetParamName=function() return true, "SC 1 On (3/4)" end,
  TrackFX_GetParam=function() return 1 end, TrackFX_SetParam=function() return true end,
  TrackFX_GetPinMappings=function(_,_,_,pin) return ({[0]=1,[1]=2,[2]=4,[3]=8})[pin] or 0, 0 end,
  GetTrackNumSends=function(t) return #t.recv end,
  GetTrackSendInfo_Value=function(t,_,r,k) local x=t.recv[r+1]
    if k=="I_SRCCHAN" then return x.srcchan elseif k=="I_DSTCHAN" then return x.dst elseif k=="B_MUTE" then return 0 elseif k=="P_SRCTRACK" then return x.src end end,
  GetParentTrack=function() return nil end,
  GetMediaTrackInfo_Value=function(t,k) if k=="I_NCHAN" then return t.nchan elseif k=="B_MUTE" then return t.mute elseif k=="IP_TRACKNUMBER" then return t.num else return 0 end end,
  CountTrackMediaItems=function(t) return #t.items end, GetTrackMediaItem=function(t,i) return t.items[i+1] end,
  GetActiveTake=function(it) return it.take end, TakeIsMIDI=function() return false end,
  GetMediaItemInfo_Value=function(it,k) if k=="B_MUTE" then return it.mute elseif k=="D_POSITION" then return it.pos elseif k=="D_LENGTH" then return it.len end end,
  GetMediaItemTakeInfo_Value=function(tk,k) if k=="D_STARTOFFS" then return tk.offs else return tk.rate end end,
  GetMediaItemTake_Source=function(tk) return tk end, GetMediaSourceFileName=function(src) return src.file end, GetMediaSourceParent=function() return nil end,
  ColorToNative=function(r,g,b) return r + g*256 + b*65536 end,
  EnumProjects=function(i) if i == -1 or i == 0 then return "PROJ", FN end end,
  GetProjectStateChangeCount=function() return state end,
  EnumProjectMarkers3=function(_,i) local m=markers[i+1]; if not m then return 0 end; return 1, false, m.pos, 0, m.name, m.num, m.color end,
  CountProjectMarkers=function() return #markers end,
  DeleteProjectMarker=function(_,num) for i,m in ipairs(markers) do if m.num==num then table.remove(markers,i); bump(); return true end end return false end,
  AddProjectMarker2=function(_,_,pos,_,name,_,color) markers[#markers+1]={pos=pos,name=name,num=nextnum,color=color,lane=0}; nextnum=nextnum+1; resort(); bump(); return nextnum-1 end,
  SetProjectMarker3=function(_,num,_,pos,_,name,color) for _,m in ipairs(markers) do if m.num==num then m.pos=pos; m.color=color end end; resort(); bump(); return true end,
  GetRegionOrMarker=function(_,idx) return markers[idx+1] end,
  GetRegionOrMarkerInfo_Value=function(_,m) return m.lane end, SetRegionOrMarkerInfo_Value=function(_,m,_,v) m.lane=v end,
  SetProjExtState=function(_,s,k,v) pext[s..k]=v end, GetProjExtState=function(_,s,k) return 1, pext[s..k] or "" end,
  GetExtState=function(s,k) return ext[s..k] or "" end, SetExtState=function(s,k,v) ext[s..k]=v end, DeleteExtState=function(s,k) ext[s..k]=nil end,
  HasExtState=function(s,k) return ext[s..k] ~= nil end,
  GetMousePosition=function() return 0, 0 end, TrackCtl_SetToolTip=function(m) if m ~= "" then LAST_TIP = m end end,
  Undo_BeginBlock2=function() end, Undo_EndBlock2=function() end, PreventUIRefresh=function() end, UpdateTimeline=function() end,
  GetResourcePath=function() return "/tmp" end, file_exists=function() return false end,
}
-- funzioni non previste dal finto: restituiscono nil senza errori (l'helper le usa solo per extra)
reaper = setmetatable(base_reaper, { __index = function() return function() return nil end end })
CLOCK = 0
local nav = dofile("ZP Voce/ZP Harmonic Space Carver Cue Navigator.lua")
-- Carver finto, come quick_service del JSFX (senza numero unico: indirizzo da traccia e posizione)
local base = 4096 + (0 + 2) * 4096
local cues, seen = {}, 0
gm[base+69] = 905243
local function carver()
  local seq = gm[3803] or 0
  if seq ~= seen then seen = seq
    if gm[3800] == base and gm[3801] == 5 then cues = {} for i = 1, gm[3810] do cues[i] = gm[3810+i] end gm[3804] = seq end
  end
  table.sort(cues); gm[base+4] = #cues; for i = 0, 63 do gm[base+5+i] = cues[i+1] or -1 end
end
local function step(n) for _ = 1, (n or 4) do carver(); CLOCK = CLOCK + 0.3; bump(); nav.run_once(); carver() end end
local fails = 0
local function ml() local t = {} for _, m in ipairs(markers) do t[#t+1] = string.format("%g%s", m.pos, m.color == CYAN and "" or "R") end return table.concat(t, ",") end
local function cl() local t = {} for _, c in ipairs(cues) do t[#t+1] = string.format("%g", c) end return table.concat(t, ",") end
local function check(name, got, want) if got ~= want then fails = fails + 1; print("FAIL " .. name .. " got [" .. got .. "] want [" .. want .. "]") end end

nav.rescan()
cues = {12, 3}; step()
check("progetto vecchio: marker dai cue", ml(), "3,12")
check("progetto vecchio: Carver intatto", cl(), "3,12")
markers[2].pos = 9; resort(); step()
check("marker spostato: il Carver segue", cl(), "3,9")
cues[#cues+1] = 20; step()
check("ADD nel Carver: marker", ml(), "3,9,20")
table.remove(markers, 2); step()
check("marker cancellato a mano: torna", ml(), "3,9,20")
markers[#markers+1] = {pos=15, name="#HSC", num=99, color=CYAN, lane=0}; resort(); step()
check("marker aggiunto a mano: tolto", ml(), "3,9,20")
cues = {50}; step()
check("CLEAR + nuovo cue", ml(), "50")
voc.items[1].pos = 3; step()
check("voce spostata: cue rosso", ml(), "50R")
-- clic sull'avviso CUE FUORI POSTO nel Carver (comando 8 sul canale GUI -> helper)
gm[base] = 8; gm[base+1] = (gm[base+1] or 0) + 1; step()
check("clic sull'avviso: riallineato", ml() .. " / " .. tostring(LAST_TIP), "53 / 1 cue riallineato")
check("clic sull'avviso: Carver aggiornato", cl(), "53")
check("clic sull'avviso: ack all'helper", tostring(gm[base+3] == gm[base+1]), "true")
-- tasto Riallinea (richiesta in ExtState)
voc.items[1].pos = 10; step()
ext["ZP_HSCreq"] = "realign_all|7"; step()
check("tasto Riallinea", ml() .. " / " .. tostring(ext["ZP_HSCrep"]), "60 / 7|1")
print(fails == 0 and "TUTTI OK" or (fails .. " FALLITI"))
