-- REAPER finto: verifica la logica delle note agganciate estraendo le funzioni dal Gobbo Verticale
local path = arg[1] or "ZP Studio Suite/02_Gobbo_Verticale.lua"
local src = io.open(path):read("a")
local a = src:find("function CollectAllTextItems()", 1, true)
local b = src:find("function CollectNotes()", 1, true)
local chunk = src:sub(a, b - 1)
local items, tracks, nextid = {}, {}, 0
local function new_item(track, pos, len, text)
  nextid = nextid + 1
  local it = {track=track, D_POSITION=pos, D_LENGTH=len, GUID="{G"..nextid.."}", P_NOTES=text or "", ext={}}
  table.insert(track.items, it); return it
end
local reaper = {}
function reaper.CountTrackMediaItems(t) return #t.items end
function reaper.GetTrackMediaItem(t,i) return t.items[i+1] end
function reaper.GetMediaItemInfo_Value(it,k) return it[k] end
function reaper.SetMediaItemInfo_Value(it,k,v) it[k]=v end
function reaper.GetSetMediaItemInfo_String(it,k,v,set)
  local e = k:match("^P_EXT:(.*)")
  if set then if e then it.ext[e]=v else it[k]=v end return true,v end
  if e then return true, it.ext[e] or "" end
  return true, it[k] or ""
end
function reaper.CountMediaItems() local n=0 for _,t in ipairs(tracks) do n=n+#t.items end return n end
function reaper.GetMediaItem(_,i) for _,t in ipairs(tracks) do if i<#t.items then return t.items[i+1] end i=i-#t.items end end
function reaper.ValidatePtr() return true end
function reaper.DeleteTrackMediaItem(t,it) for i,x in ipairs(t.items) do if x==it then table.remove(t.items,i) return end end end
function reaper.MarkProjectDirty() end
function reaper.UpdateArrange() end
local text_track, notes_track, other = {items={}}, {items={}}, {items={}}
tracks = {text_track, notes_track, other}
local env = setmetatable({reaper=reaper, NOTE_LINK_MAX_DISTANCE=10.0, NOTE_LINK_EPSILON=0.0005,
  notes_track_name="N", trim=function(s) return (tostring(s or ""):gsub("^%s+",""):gsub("%s+$","")) end,
  FindTrackByName=function() return notes_track end,
  CollectTextFlowTracks=function() return {{track=text_track}} end}, {__index=_G})
assert(load(chunk, "note", "t", env))()
local sync = env.SyncLinkedNotes
local function check(c, msg) if not c then error("FALLITO: "..msg, 2) end end
local A = new_item(text_track, 10, 4, "prima battuta")
local B = new_item(text_track, 20, 4, "seconda battuta")
local n1 = new_item(notes_track, 11, 1, "nota su A")
local n2 = new_item(notes_track, 26, 1, "nota vicino a B")
local n3 = new_item(notes_track, 100, 1, "nota lontana")
sync()
check(n1.ext.ZP_NOTE_LINK == A.GUID, "nota dentro la battuta: agganciata a quella")
check(n2.ext.ZP_NOTE_LINK == B.GUID, "nota a 2 s dalla fine: agganciata alla battuta vicina")
check((n3.ext.ZP_NOTE_LINK or "") == "", "nota lontana piu' di 10 s: resta libera")
A.D_POSITION = 50; sync()
check(math.abs(n1.D_POSITION - 51) < 1e-6, "battuta spostata: la nota la segue")
sync(); check(math.abs(n1.D_POSITION - 51) < 1e-6, "secondo controllo: niente altri spostamenti")
n1.D_POSITION = 21; sync()
check(n1.ext.ZP_NOTE_LINK == B.GUID, "nota spostata a mano su un'altra battuta: cambia aggancio")
B.D_POSITION = 30; sync()
check(math.abs(n1.D_POSITION - 31) < 1e-6 and math.abs(n2.D_POSITION - 36) < 1e-6, "entrambe le note seguono la seconda battuta")
-- divisione: B diventa 30-32, la parte destra e' un item nuovo 32-34
B.D_LENGTH = 2; local B2 = new_item(text_track, 32, 2, "seconda meta'")
n1.D_POSITION = 33; n1.ext.ZP_NOTE_LINK_OFF = "3.000000000"; sync()
check(n1.ext.ZP_NOTE_LINK == B2.GUID, "battuta divisa: la nota passa alla meta' che la contiene")
-- cancellazione
reaper.DeleteTrackMediaItem(text_track, B2); sync()
local still = false for _,x in ipairs(notes_track.items) do if x==n1 then still=true end end
check(not still, "battuta cancellata: la nota se ne va")
-- item ricreato nello stesso punto (unione, incolla): la nota resta e si riaggancia
reaper.DeleteTrackMediaItem(text_track, B); local B3 = new_item(text_track, 30, 8, "ricreata"); sync()
check(n2.ext.ZP_NOTE_LINK == B3.GUID, "battuta ricreata nello stesso punto: la nota si riaggancia")
-- battuta spostata su una traccia che non e' un flusso di testo: la nota resta
reaper.DeleteTrackMediaItem(text_track, B3); table.insert(other.items, B3); sync()
local kept = false for _,x in ipairs(notes_track.items) do if x==n2 then kept=true end end
check(kept, "battuta finita su un'altra traccia: la nota non viene cancellata")
print("TUTTI OK")
