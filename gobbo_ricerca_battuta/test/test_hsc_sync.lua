-- Test della sincronizzazione cue <-> marker #HSC (helper Cue Navigator 1.4). Lancio dalla radice del repo.
HSC_SYNC_TEST = true
local HSC = dofile("ZP Voce/ZP Harmonic Space Carver Cue Navigator.lua")
local fails = 0
local function eq(a, b) return HSC.same(HSC.sorted(a or {}), HSC.sorted(b or {})) end
local function check(name, cond) if not cond then fails = fails + 1; print("FAIL " .. name) end end

-- nomi dei marker
check("nome esatto", HSC.is_cue_marker("#HSC", false))
check("nome con spazi", HSC.is_cue_marker("  #HSC ", false))
check("nome con suffisso", HSC.is_cue_marker("#HSC voce", false))
check("regione esclusa", not HSC.is_cue_marker("#HSC", true))
check("altro segnaposto", not HSC.is_cue_marker("#HSCX", false))
check("testo", not HSC.is_cue_marker("HSC", false))

local function M(...) local l = {} for i, v in ipairs({...}) do l[i] = { num = v[1], pos = v[2] } end return l end
local function nums(l) table.sort(l) return table.concat(l, ",") end
local function pos_of(l) local o = {} for _, c in ipairs(l) do o[#o + 1] = type(c) == "table" and c.pos or c end table.sort(o) local t = {} for i, v in ipairs(o) do t[i] = string.format("%g", v) end return table.concat(t, ",") end

-- primo giro: comanda il Carver, mai cancellare cue
local f = HSC.first_sync({}, {12.0, 3.5})
check("primo giro: cue senza marker -> creati", pos_of(f.create) == "3.5,12" and #f.delete == 0)
f = HSC.first_sync(M({1, 5.0}, {2, 9.0}), {9.002, 5.0})
check("primo giro: gia' allineati", #f.create == 0 and #f.delete == 0)
f = HSC.first_sync(M({1, 5.0}, {2, 9.0}), {5.0})
check("primo giro: marker senza cue -> tolto", nums(f.delete) == "2" and #f.create == 0)
f = HSC.first_sync({}, {})
check("primo giro: vuoto", #f.create == 0 and #f.delete == 0)

local synced = { [1] = 10.0, [2] = 20.0, [3] = 30.0 }
-- spostamenti accettati
local ms = HSC.marker_side(synced, M({1, 10.0}, {2, 17.0}, {3, 27.0}))
check("marker spostati: niente da fare", #ms.restore == 0 and #ms.delete == 0 and next(ms.rekey) == nil)
-- cancellato a mano: torna
ms = HSC.marker_side(synced, M({1, 10.0}, {3, 30.0}))
check("marker cancellato: rimesso", #ms.restore == 1 and ms.restore[1].pos == 20.0 and ms.restore[1].from == 2)
-- tutti cancellati: tornano tutti
ms = HSC.marker_side(synced, {})
check("tutti cancellati: rimessi", #ms.restore == 3)
-- aggiunto a mano: tolto
ms = HSC.marker_side(synced, M({1, 10.0}, {2, 20.0}, {3, 30.0}, {9, 15.0}))
check("marker aggiunto a mano: tolto", nums(ms.delete) == "9" and #ms.restore == 0)
-- rinumerati: stessa posizione, numero nuovo
ms = HSC.marker_side(synced, M({11, 10.0}, {12, 20.0}, {13, 30.0}))
check("rinumerati: chiavi nuove, niente rimesso", ms.rekey[1] == 11 and ms.rekey[2] == 12 and ms.rekey[3] == 13 and #ms.restore == 0 and #ms.delete == 0)

local mk = M({1, 10.0}, {2, 20.0}, {3, 30.0})
-- lato Carver
local cs = HSC.carver_side({10, 20, 30}, {10, 15, 20, 30}, mk)
check("Carver: cue aggiunto -> marker", pos_of(cs.create) == "15" and #cs.delete == 0)
cs = HSC.carver_side({10, 20, 30}, {10, 30}, mk)
check("Carver: cue tolto -> marker tolto", nums(cs.delete) == "2" and #cs.create == 0)
cs = HSC.carver_side({10, 20, 30}, {}, mk)
check("Carver: CLEAR ALL -> marker tolti", nums(cs.delete) == "1,2,3")
cs = HSC.carver_side({10, 20, 30}, {10.001, 20, 29.997}, mk)
check("Carver: sotto tolleranza niente", #cs.create == 0 and #cs.delete == 0)
cs = HSC.carver_side({}, {1.000, 1.004}, {})
check("Carver: cue a 4 ms -> due marker", #cs.create == 2)

-- elenco al Carver: posizioni ordinate, massimo 64
local many = {}
for i = 70, 1, -1 do many[#many + 1] = { num = i, pos = i * 1.0 } end
local list = HSC.positions(many)
check("posizioni: 64 e ordinate", #list == 64 and list[1] == 1.0 and list[64] == 64.0)

-- ===== tracce voce dal routing sidechain (progetto come "I Guardiani dell'Abbazia") =====
do
  local tracks, byname = {}, {}
  local function T(name, parent, opt)
    local t = {name=name, parent=parent, mute=0, mainsend=1, offs=0, nch=0, nchan=2, recv={}}
    for k, v in pairs(opt or {}) do t[k] = v end
    tracks[#tracks+1] = t; t.num = #tracks; byname[name] = t; return t
  end
  local mic = T("1_microfoni"); T("edit", mic); T("L1", mic); T("Esterni", mic)
  local col = T("Colonna sonora", nil, {nchan=4}); T("Musica", col); T("EFX", col)
  local voci = T("Voci"); T("Argan", voci); T("GianLUCA", voci, {mute=1}); T("Beker", voci)
  local child_voice = T("Voce figlia", col, {offs=2, nch=2})        -- figlia del Carver su 3/4
  col.recv = {{src=mic, srcchan=0, dst=2}, {src=voci, srcchan=0, dst=2}}
  local pins, sc2 = {[0]=1, [1]=2, [2]=4, [3]=8}, 0
  reaper = {
    GetMediaTrackInfo_Value=function(t,k)
      if k=="I_NCHAN" then return t.nchan elseif k=="B_MUTE" then return t.mute elseif k=="B_MAINSEND" then return t.mainsend
      elseif k=="C_MAINSEND_OFFS" then return t.offs elseif k=="C_MAINSEND_NCH" then return t.nch elseif k=="IP_TRACKNUMBER" then return t.num end end,
    TrackFX_GetNumParams=function() return 3 end,
    TrackFX_GetParamName=function(_,_,p) return true, ({"SC 1 On (3/4)","SC 2 On (5/6)","SC 3 On (7/8)"})[p+1] end,
    TrackFX_GetParam=function(_,_,p) return p==0 and 1 or (p==1 and sc2 or 0) end,
    TrackFX_GetPinMappings=function(_,_,_,pin) return pins[pin] or 0, 0 end,
    CountTracks=function() return #tracks end, GetTrack=function(_,i) return tracks[i+1] end,
    GetParentTrack=function(t) return t.parent end,
    GetTrackNumSends=function(t) return #t.recv end,
    GetTrackSendInfo_Value=function(t,_,r,k) local x=t.recv[r+1]
      if k=="I_SRCCHAN" then return x.srcchan elseif k=="I_DSTCHAN" then return x.dst elseif k=="B_MUTE" then return 0 elseif k=="P_SRCTRACK" then return x.src end end,
  }
  local function names(l) local o={} for _,t in ipairs(l) do o[#o+1]=t.name end return table.concat(o,",") end
  check("voci: invii e figlie, mute escluse", names(HSC.voice_tracks(col, 0)) == "1_microfoni,edit,L1,Esterni,Voci,Argan,Beker,Voce figlia")
  pins[2], pins[3] = 1, 2
  check("voci: pin SC su 1/2 = la musica", names(HSC.voice_tracks(col, 0)) == "Musica,EFX")
  pins[2], pins[3] = 4, 8; col.recv[1].dst = 0
  check("voci: invio su 1/2 non e' voce", names(HSC.voice_tracks(col, 0)) == "Voci,Argan,Beker,Voce figlia")
  pins[2], pins[3] = 0, 0
  check("voci: SC1 scollegata = nessuna", #HSC.voice_tracks(col, 0) == 0)
  reaper = nil
end

-- ===== ancore dei cue all'audio della voce =====
do
  local v1 = { file = "voce.wav", pos = 100, len = 10, offs = 20, rate = 1, track = 3 }   -- file 20..30 in timeline 100..110
  local v2 = { file = "ospite.wav", pos = 105, len = 10, offs = 0, rate = 1, track = 5 }
  local a = HSC.make_anchor(104, { v1, v2 })
  check("ancora: voce sotto il cue", a.file == "voce.wav" and math.abs(a.src - 24) < 1e-9)
  a = HSC.make_anchor(112, { v1 })
  check("ancora: voce finita da poco", a.file == "voce.wav" and math.abs(a.src - 32) < 1e-9)
  a = HSC.make_anchor(99, { v1 })
  check("ancora: voce che parte subito", a.file == "voce.wav" and math.abs(a.src - 19) < 1e-9)
  check("ancora: nessuna voce = libero", HSC.make_anchor(150, { v1 }).file == "")
  a = { file = "voce.wav", src = 24 }
  check("atteso: al suo posto", math.abs(HSC.expected(a, { v1 }, 104) - 104) < 1e-9)
  local moved = { file = "voce.wav", pos = 97, len = 10, offs = 20, rate = 1, track = 3 }     -- ripple: -3 s
  check("atteso: segue l'item", math.abs(HSC.expected(a, { moved }, 104) - 101) < 1e-9)
  local trimmed = { file = "voce.wav", pos = 102, len = 8, offs = 22, rate = 1, track = 3 } -- tagliato l'inizio
  check("atteso: taglio a sinistra non sposta", math.abs(HSC.expected(a, { trimmed }, 104) - 104) < 1e-9)
  local left = { file = "voce.wav", pos = 100, len = 3, offs = 20, rate = 1, track = 3 }
  local right = { file = "voce.wav", pos = 103, len = 7, offs = 23, rate = 1, track = 3 }
  check("atteso: item diviso", math.abs(HSC.expected(a, { left, right }, 104) - 104) < 1e-9)
  local twice = { file = "voce.wav", pos = 300, len = 10, offs = 20, rate = 1, track = 3 }
  check("atteso: file usato due volte, vale il piu' vicino", math.abs(HSC.expected(a, { twice, v1 }, 104) - 104) < 1e-9)
  check("atteso: audio sparito", HSC.expected(a, { v2 }, 104) == nil)
  check("giudizio: ok", HSC.judge(a, 104, 104.01, 104, 104) == "ok")
  check("giudizio: audio spostato = rosso", HSC.judge(a, 104, 101, 104, 104) == "lost")
  check("giudizio: marker trascinato = nuova ancora", HSC.judge(a, 108, 104, 104, 104) == "reanchor")
  check("giudizio: spostati insieme (ripple tutte) = ok", HSC.judge(a, 101, 101, 104, 104) == "ok")
  check("giudizio: audio sparito = rosso", HSC.judge(a, 104, nil, 104, 104) == "lost")
  check("giudizio: libero", HSC.judge({ file = "", src = 0 }, 104, nil, 100, nil) == "free")
  check("giudizio: alla riapertura fuori posto = rosso", HSC.judge(a, 104, 101, nil, nil) == "lost")
  local back = HSC.deserialize(HSC.serialize({ [3] = { file = "C:\\voci\\a b.wav", src = 12.5 }, [7] = { file = "", src = 0 } }))
  check("salvataggio ancore", back[3].file == "C:\\voci\\a b.wav" and math.abs(back[3].src - 12.5) < 1e-6 and back[7].file == "")
  local m1, m2 = HSC.masks({ true, false, true })
  check("maschere 1", m1 == 5 and m2 == 0)
  local l = {} for i = 1, 40 do l[i] = (i == 33) end
  m1, m2 = HSC.masks(l)
  check("maschere 2", m1 == 0 and m2 == 1)
end

print(fails == 0 and "TUTTI OK" or (fails .. " FALLITI"))
