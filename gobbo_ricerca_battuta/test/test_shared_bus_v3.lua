-- Test unitario per ZP Shared Bus v3 (Cue Navigator TeleDir + Open-FX + integrita' JSFX)
-- Eseguibile con: lua gobbo_ricerca_battuta/test/test_shared_bus_v3.lua

local info = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
local root_dir = (info or "./") .. "../../"

-- 1. Test modulo puro TeleDir
_G.HSC_SYNC_TEST = true
local HSC = dofile(root_dir .. "ZP Voce/ZP Harmonic Space Carver Cue Navigator.lua")
local TeleDir = HSC.TeleDir
assert(TeleDir, "TeleDir non esposto in HSC")

assert(TeleDir.sanitize_name("Voce Paolo èéàù") == "Voce Paolo eeau", "Sanitizzazione accenti errata")
assert(TeleDir.sanitize_name("") == "", "Stringa vuota non preservata")
assert(#TeleDir.sanitize_name("12345678901234567890XYZ") == 20, "Troncamento a 20 caratteri fallito")
assert(TeleDir.sanitize_name("A😀B") == "AB", "Caratteri non ASCII non filtrati")

local samples = { "", "Paolo", "Ospite è 1", "VO BUS (Stereo)", "12345678901234567890extra" }
for _, raw in ipairs(samples) do
  local expected = TeleDir.sanitize_name(raw)
  local len, p0, p1, p2, p3, p4 = TeleDir.pack_name(raw)
  assert(len == #expected, "Lunghezza packed errata per " .. raw)
  for _, p in ipairs({ p0, p1, p2, p3, p4 }) do
    assert(p >= 0 and p < 2147483648, "Packed float fuori range int31: " .. tostring(p))
  end
  local unpacked = TeleDir.unpack_name(len, p0, p1, p2, p3, p4)
  assert(unpacked == expected, string.format("Roundtrip fallito: got '%s' want '%s'", unpacked, expected))
end

-- 2. Simulazione serve_telemetry_dir() e serve_telemetry_cmd()
_G.HSC_SYNC_TEST = nil
_G.HSC_SYNC_SIM = true

local gmem = {}
local ext = {}
local shown_fx = {}
local clock = 50.0

local vo_bus = { name = "VO BUS", role = "VO_BUS", mute = 0, solo = 0, fdep = 1, parent = nil, fx_cnt = 2 }
local tr_paolo = { name = "Paolo à", role = "", mute = 0, solo = 1, fdep = 0, parent = vo_bus, fx_cnt = 3 }
local tr_ospite = { name = "Ospite", role = "", mute = 1, solo = 0, fdep = 0, parent = vo_bus, fx_cnt = 2 }
local music_bus = { name = "Music BUS", role = "MUSIC_BUS", mute = 0, solo = 0, fdep = 0, parent = nil, fx_cnt = 1 }
local master_tr = { name = "MASTER", fx_cnt = 1 }
local tracks = { vo_bus, tr_paolo, tr_ospite, music_bus }

_G.reaper = {
  gmem_attach = function() end,
  gmem_read = function(idx) return gmem[idx] or 0 end,
  gmem_write = function(idx, val) gmem[idx] = val end,
  time_precise = function() return clock end,
  defer = function() end,
  GetExtState = function(s, k) return ext[s .. ":" .. k] or "" end,
  SetExtState = function(s, k, v) ext[s .. ":" .. k] = v end,
  DeleteExtState = function(s, k) ext[s .. ":" .. k] = nil end,
  GetProjExtState = function() return 0, "" end,
  SetProjExtState = function() end,
  GetProjectStateChangeCount = function() return 1 end,
  EnumProjects = function(i) if i == -1 or i == 0 then return "P1", "/tmp/p1.rpp" end end,
  CountTracks = function() return #tracks end,
  GetTrack = function(_, i) return tracks[i + 1] end,
  GetMasterTrack = function() return master_tr end,
  GetParentTrack = function(t) return t.parent end,
  GetSetMediaTrackInfo_String = function(t, k)
    if k == "P_NAME" then return true, t.name end
    if k == "P_EXT:ZP_CHAIN_ROLE" then return true, t.role end
    return false, ""
  end,
  GetMediaTrackInfo_Value = function(t, k)
    if k == "B_MUTE" then return t.mute or 0 end
    if k == "I_SOLO" then return t.solo or 0 end
    if k == "I_FOLDERDEPTH" then return t.fdep or 0 end
    if k == "I_NCHAN" then return 2 end
    return 0
  end,
  TrackFX_GetCount = function(t) return t.fx_cnt or 0 end,
  TrackFX_GetFXName = function() return false, "" end,
  TrackFX_GetNumParams = function() return 0 end,
  TrackFX_Show = function(t, fx, flag)
    shown_fx[#shown_fx + 1] = { track = t, fx = fx, flag = flag }
  end,
  CountProjectMarkers = function() return 0 end,
  EnumProjectMarkers3 = function() return 0 end,
  CountTrackMediaItems = function() return 0 end,
  GetPlayState = function() return 0 end,
  ColorToNative = function() return 0 end,
  TrackCtl_SetToolTip = function() end,
  GetResourcePath = function() return root_dir end,
  GetOS = function() return "OSX64" end,
}

local sim = dofile(root_dir .. "ZP Voce/ZP Harmonic Space Carver Cue Navigator.lua")
assert(sim and sim.serve_telemetry_dir and sim.serve_telemetry_cmd, "Funzioni TeleDir non esposte in HSC_SYNC_SIM")

sim.serve_telemetry_dir()
assert(gmem[1004] == 1, "dir_heartbeat deve essere 1")
assert(gmem[1005] == 50.0, "dir_time deve essere 50.0")
assert(gmem[1006] == 4, "dir_track_count deve essere 4")

-- Traccia 0 = VO BUS (exists + folder + VO_BUS = 1 + 8 + 16 = 25)
local d0 = 3072 + 0 * 8
assert(gmem[d0 + 0] == 25, "Flags VO BUS errati: " .. tostring(gmem[d0 + 0]))
assert(gmem[d0 + 1] == -1, "Parent VO BUS deve essere -1")
assert(TeleDir.unpack_name(gmem[d0 + 2], gmem[d0 + 3], gmem[d0 + 4], gmem[d0 + 5], gmem[d0 + 6], gmem[d0 + 7]) == "VO BUS")

-- Traccia 1 = Paolo à (exists + solo = 1 + 4 = 5, parent = 0)
local d1 = 3072 + 1 * 8
assert(gmem[d1 + 0] == 5, "Flags Paolo errati: " .. tostring(gmem[d1 + 0]))
assert(gmem[d1 + 1] == 0, "Parent Paolo deve essere 0")
assert(TeleDir.unpack_name(gmem[d1 + 2], gmem[d1 + 3], gmem[d1 + 4], gmem[d1 + 5], gmem[d1 + 6], gmem[d1 + 7]) == "Paolo a")

-- Traccia 2 = Ospite (exists + mute = 1 + 2 = 3, parent = 0)
local d2 = 3072 + 2 * 8
assert(gmem[d2 + 0] == 3, "Flags Ospite errati: " .. tostring(gmem[d2 + 0]))

-- Traccia 3 = Music BUS (exists + MUSIC_BUS = 1 + 32 = 33)
local d3 = 3072 + 3 * 8
assert(gmem[d3 + 0] == 33, "Flags Music BUS errati: " .. tostring(gmem[d3 + 0]))

-- Rimozione tracce -> pulizia slot vecchi
tracks = { vo_bus, tr_paolo }
clock = 51.0
sim.serve_telemetry_dir()
assert(gmem[1004] == 2, "dir_heartbeat deve avanzare a 2")
assert(gmem[1006] == 2, "dir_track_count deve scendere a 2")
assert(gmem[d2 + 0] == 0 and gmem[d3 + 0] == 0, "Slot tracce rimosse devono essere azzerati")

-- Test Open-FX mailbox
gmem[1008] = 1
gmem[1009] = 2
gmem[1010] = 1
sim.serve_telemetry_cmd()
assert(gmem[1011] == 1 and gmem[1012] == 1, "Open-FX traccia valida fallito")
assert(#shown_fx == 1 and shown_fx[1].track == tr_paolo and shown_fx[1].fx == 2 and shown_fx[1].flag == 3)

-- Stessa seq -> nessuna nuova apertura
sim.serve_telemetry_cmd()
assert(#shown_fx == 1, "Open-FX non deve ripetere comando con seq gia' evasa")

-- Master track (tr_idx = -1)
gmem[1008] = -1
gmem[1009] = 0
gmem[1010] = 2
sim.serve_telemetry_cmd()
assert(gmem[1011] == 2 and gmem[1012] == 1, "Open-FX Master fallito")
assert(#shown_fx == 2 and shown_fx[2].track == master_tr and shown_fx[2].fx == 0)

-- FX inesistente
gmem[1008] = 0
gmem[1009] = 99
gmem[1010] = 3
sim.serve_telemetry_cmd()
assert(gmem[1011] == 3 and gmem[1012] == 2, "Open-FX target invalido deve restituire status 2")
assert(#shown_fx == 2, "Non deve chiamare TrackFX_Show per FX inesistente")

-- 3. Verifica statica integrita' protocollo nei 10 JSFX
local producers = {
  { path = "ZP Voce/ZP BUS Chain.jsfx", ptypes = { 1 } },
  { path = "ZP Voce/ZP Voiceover Unified Chain.jsfx", ptypes = { 2 } },
  { path = "ZP Voce/ZP Magic Voice LAB.jsfx", ptypes = { 3 } },
  { path = "ZP Voce/ZP Spoken Finish.jsfx", ptypes = { 4 } },
  { path = "ZP Voce/ZP Stagekeeper Dialogue Director.jsfx", ptypes = { 5 } },
  { path = "ZP Lab/ZP Click & Attack Softener.jsfx", ptypes = { 6 } },
  { path = "ZP Lab/ZP BrownSlope Dynamic Guard.jsfx", ptypes = { 7 } },
  { path = "ZP Voce/ZP Harmonic Space Carver.jsfx", ptypes = { 8 } },
  { path = "ZP Misura/ZP Voice-Music Probe.jsfx", ptypes = { 9, 10 } },
  { path = "ZP Misura/ZP BrownSlope Prism.jsfx", ptypes = { 11 } },
  { path = "ZP Misura/ZP Loudness Meter Multichannel.jsfx", ptypes = { 12 } },
}
local seen_pt = {}
for _, pr in ipairs(producers) do
  local f = assert(io.open(root_dir .. pr.path, "r"), "Impossibile aprire " .. pr.path)
  local txt = f:read("*a"); f:close()
  assert(txt:find("function zp3_boot()", 1, true), "Manca zp3_boot in " .. pr.path)
  assert(txt:find("function zp3_claim(", 1, true), "Manca zp3_claim in " .. pr.path)
  assert(txt:find("get_host_placement(", 1, true), "Manca get_host_placement in " .. pr.path)
  assert(txt:find("905301", 1, true), "Manca magic 905301 in " .. pr.path)
  for _, pt in ipairs(pr.ptypes) do
    assert(not seen_pt[pt], "ptype duplicato: " .. tostring(pt))
    seen_pt[pt] = pr.path
    assert(txt:find("gmem[zp3_b + 4] = " .. tostring(pt), 1, true) or txt:find("gmem[zp3_b + 4] = zp3_pt", 1, true),
      "Manca scrittura plugin_type in " .. pr.path)
  end
end
for pt = 1, 12 do
  assert(seen_pt[pt], "Manca produttore per ptype " .. tostring(pt))
end

local pf = assert(io.open(root_dir .. "ZP Misura/ZP Voice-Music Probe.jsfx", "r"))
local ptxt = pf:read("*a"); pf:close()
assert(ptxt:find("probe_brown_tilt", 1, true), "Manca misura Brown tilt in Probe")
assert(ptxt:find("905360", 1, true), "Probe non rileva Telemetry Engine (905360)")

local mf = assert(io.open(root_dir .. "ZP Master/ZP Master Pro.jsfx", "r"))
local mtxt = mf:read("*a"); mf:close()
assert(mtxt:find("function zp3_scan_bus()", 1, true), "Manca zp3_scan_bus in Master Pro")
assert(mtxt:find("function zp3_read_track_name(", 1, true), "Manca zp3_read_track_name in Master Pro")
assert(mtxt:find("function zp3_request_open_fx(", 1, true), "Manca zp3_request_open_fx in Master Pro")
assert(mtxt:find("gmem[410] = 905410", 1, true), "Manca Master Reference Block 410..425 in Master Pro")
assert(mtxt:find("gmem[zp3_mb + 4] = 13", 1, true), "Manca pubblicazione ptype=13 in Master Pro")
assert(mtxt:find("gmem[3600] == 905360", 1, true), "Manca lettura Telemetry Engine in Master Pro")
assert(mtxt:find('"SINTESI"', 1, true) and mtxt:find('"CATENA (%d)"', 1, true), "Mancano schede SINTESI/CATENA in Master Pro")
assert(mtxt:find("gmem[10]==905010", 1, true) and mtxt:find("gmem[50]==905050", 1, true) and mtxt:find("gmem[60]==905060", 1, true),
  "Compatibilita' legacy v2.20 alterata in Master Pro")
assert(mtxt:find("slider67:master_profile=", 1, true) and mtxt:find("slider68:ox_input_db=0<-12,30,0.1>", 1, true)
  and mtxt:find("slider69:ox_enhance=", 1, true) and mtxt:find("slider73:ox_auto_rel=", 1, true)
  and mtxt:find("slider74:ox_clip=", 1, true) and mtxt:find("slider23:out_target_lufs=-16<-30,-6,0.1>", 1, true),
  "Mancano slider Transparent/Enhance/PreClip (+30 dB / Target -6) in Master Pro")
assert(mtxt:find("function ox_enh_shaper(", 1, true) and mtxt:find("function ox_clip_shaper(", 1, true),
  "Mancano shaper 2x oversampled ENHANCE/PRECLIP in Master Pro")
assert(mtxt:find("function aud_send_cmd()", 1, true) and mtxt:find("905367", 1, true) and mtxt:find("905368", 1, true),
  "Manca bridge Monitor FX Audition Noise in Master Pro")
assert(mtxt:find("gmem[3674] = clamp(aud_noise_snr, -24, 6)", 1, true),
  "Clamp gmem[3674] deve arrivare fino a +6 dB in Master Pro")

local af = assert(io.open(root_dir .. "ZP Master/ZP Audition Noise Monitor.jsfx", "r"), "Manca ZP Audition Noise Monitor.jsfx")
local atxt = af:read("*a"); af:close()
assert(atxt:find("options:gmem=ZPVoiceoverSharedBus", 1, true), "Manca gmem namespace in Audition Noise Monitor")
assert(atxt:find("905367", 1, true) and atxt:find("905368", 1, true), "Mancano magic 905367/905368 in Audition Noise Monitor")
assert(atxt:find("host_warn_non_master", 1, true), "Manca guardia anti-traccia ordinaria in Audition Noise Monitor")
assert(atxt:find("slider3:noise_snr_db=-12<-24,6,0.5>", 1, true), "Range slider3 SNR +6 dB mancante in Audition Noise Monitor")
assert(atxt:find("slider6:spk_profile=0<0,3,1{", 1, true), "Manca slider6 simulazione diffusore in Audition Noise Monitor")
assert(atxt:find("srate != last_srate", 1, true), "Manca controllo srate != last_srate in Audition Noise Monitor")

local prf = assert(io.open(root_dir .. "ZP Misura/ZP BrownSlope Prism.jsfx", "r"), "Manca ZP BrownSlope Prism.jsfx")
local prtxt = prf:read("*a"); prf:close()
assert(prtxt:find("function analyze_comb()", 1, true) and prtxt:find("gmem[zp3_b + 30] = comb_state > 0 ? comb_ms : 0;", 1, true)
  and prtxt:find("gmem[zp3_b + 31] = comb_state > 0 ? comb_est : 0;", 1, true),
  "Manca pubblicazione comb cepstrale (slot +30/+31) in BrownSlope Prism")
assert(prtxt:find("function rebuild_sr_tables()", 1, true), "Manca rebuild_sr_tables in BrownSlope Prism")

local cf = assert(io.open(root_dir .. "ZP Voce/ZP Harmonic Space Carver.jsfx", "r"), "Manca ZP Harmonic Space Carver.jsfx")
local ctxt = cf:read("*a"); cf:close()
assert(ctxt:find("function la_update_pdc()", 1, true) and ctxt:find("la_audio_tgt", 1, true) and ctxt:find("la_sc_tgt", 1, true),
  "Manca lookahead dual-tap / PDC onesto in Harmonic Space Carver")

local skf = assert(io.open(root_dir .. "ZP Voce/ZP Stagekeeper Dialogue Director.jsfx", "r"), "Manca ZP Stagekeeper Dialogue Director.jsfx")
local sktxt = skf:read("*a"); skf:close()
assert(sktxt:find("LIM_BUF_CAP = 2048", 1, true) and sktxt:find("G_BUF_CAP = 100000", 1, true) and sktxt:find("pdc_delay   = gate_la_samp", 1, true),
  "Manca fissaggio capacita' buffer / PDC onesto in Stagekeeper")

local bcf = assert(io.open(root_dir .. "ZP Voce/ZP BUS Chain.jsfx", "r"), "Manca ZP BUS Chain.jsfx")
local bctxt = bcf:read("*a"); bcf:close()
assert(bctxt:find("slider80:la2_char=", 1, true) and bctxt:find("slider81:analog_pad=", 1, true),
  "Mancano slider80 (LA2 Character) o slider81 (ANA PAD -6 dB) in BUS Chain")
assert(bctxt:find("function la2_tube_nl(", 1, true) and bctxt:find("la2_dry_d1_l", 1, true) and bctxt:find("function lim_sat_shape(", 1, true),
  "Mancano shaper 2x residuo LA2 GRAY (la2_tube_nl / dry_d1 in fase) o Voice Limiter in BUS Chain")

local lmf = assert(io.open(root_dir .. "ZP Misura/ZP Loudness Meter Multichannel.jsfx", "r"), "Manca ZP Loudness Meter Multichannel.jsfx")
local lmtxt = lmf:read("*a"); lmf:close()
assert(lmtxt:find("function draw_target_rotor(", 1, true) and lmtxt:find("function tgt_step_val(", 1, true),
  "Manca rotore target 9 scatti in Loudness Meter Multichannel")

local mvf = assert(io.open(root_dir .. "ZP Voce/ZP Magic Voice LAB.jsfx", "r"), "Manca ZP Magic Voice LAB.jsfx")
local mvtxt = mvf:read("*a"); mvf:close()
assert(mvtxt:find("function pre_shape(", 1, true) and mvtxt:find("function dbal_sat_shape(", 1, true) and mvtxt:find("function tp_isp4_chan(", 1, true),
  "Mancano shaper 2x / True Peak 4x cubico in Magic Voice LAB")

-- Verifica affiancamento Spoken Finish classico (3.10.2, 100% recall) + Spoken Finish Pro (1.0.0, Chebyshev + MAGIC)
local sfc = assert(io.open(root_dir .. "ZP Voce/ZP Spoken Finish.jsfx", "r"), "Manca ZP Spoken Finish.jsfx")
local sfctxt = sfc:read("*a"); sfc:close()
assert(sfctxt:find("@version 3.10.2", 1, true) and not sfctxt:find("slider34:", 1, true),
  "ZP Spoken Finish.jsfx classico deve restare al DSP 3.10.2 senza slider34 per recall sessioni")

local sfp = assert(io.open(root_dir .. "ZP Voce/ZP Spoken Finish Pro.jsfx", "r"), "Manca ZP Spoken Finish Pro.jsfx")
local sfptxt = sfp:read("*a"); sfp:close()
assert(sfptxt:find("function zp3_boot()", 1, true) and sfptxt:find("function zp3_claim(", 1, true)
  and sfptxt:find("get_host_placement(", 1, true) and sfptxt:find("905301", 1, true)
  and sfptxt:find("gmem[zp3_b + 4] = 4", 1, true),
  "Telemetria Shared Bus v3 mancante in ZP Spoken Finish Pro.jsfx")
assert(sfptxt:find("slider34:0<0,1,1{Off,On}>-Magic Signature", 1, true)
  and sfptxt:find("function sf_cheb_harm(", 1, true),
  "Motore Chebyshev / MAGIC mancante in ZP Spoken Finish Pro.jsfx")

-- Verifica matematica curva ENHANCE 2.51 (silenzio non sollevato, sillabe deboli sollevate fino a 7.5 dB, picchi protetti)
local function enhance_lift(in_db, ceil_db, enh_w)
  local rel = in_db - ceil_db
  local gate = math.max(0, math.min(1, (rel + 52) / 14))
  local t = math.max(0, math.min(1, (-rel - 2.5) / 32.0))
  local bell = math.sin(t * math.pi)
  return 7.5 * enh_w * gate * bell * bell
end
assert(enhance_lift(-60, -1, 1.0) < 0.01, "ENHANCE non deve alzare il rumore di fondo nel silenzio")
assert(enhance_lift(-20, -1, 1.0) > 5.5, "ENHANCE deve sollevare il corpo/sillabe deboli intorno a -20 dB")
assert(enhance_lift(-1.5, -1, 1.0) < 0.05, "ENHANCE deve azzerare il lift vicino al ceiling per preservare i transienti")

print("TUTTI OK")
