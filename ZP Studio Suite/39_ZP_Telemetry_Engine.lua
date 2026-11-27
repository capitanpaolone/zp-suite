-- @description ZP Telemetry Engine - analisi organica catena, metro Brown 4.5 / Master Tone e conflitti a monte
-- @author Paolo Balestri
-- @version 1.0
-- @noindex
-- @about
--   Servizio di analisi telemetrica a finestra lenta per la ZP Suite (separato da Cue Navigator).
--   Legge Shared Bus v3 (tutti i plugin ZP, Voice/Music Probe, BrownSlope Prism, Loudness Meter, Master Pro)
--   e il grafo reale di routing di REAPER (folder, send, fader, mute/solo e plugin esterni VST3/AU/CLAP con
--   GainReduction_dB host).
--   Usa un metro fisso di riferimento (Brown -4.5 dB/oct ±10%, oppure l'orizzonte di Tone Guard su Master Pro
--   quando acceso), distingue le opposizioni a vuoto dalla pre-enfasi intenzionale prima di un compressore/saturatore,
--   e apre con un clic qualsiasi plugin a monte (ZP o terze parti).

-- Zoom proporzionale (ZP_GfxScale.lua): finestra di partenza 840x580.
local gfx = gfx
do
  local zp_dir = (debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)[/\\]") or ".")
  local zp_chunk = loadfile(zp_dir .. package.config:sub(1, 1) .. "ZP_GfxScale.lua")
  if zp_chunk then
    ZP_GFX_SCALE_FN = function(w, h) return math.max(0.60, math.min(2.8, math.min(w / 840, h / 580))) end
    gfx = zp_chunk().wrap(gfx)
  end
end

local script_dir = (debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)[/\\]") or ".")
local sep = package.config:sub(1, 1)
local TE = dofile(script_dir .. sep .. "ZP_Telemetry_Engine.lua")

local EXT_SEC = "ZP_Telemetry_Engine"
local GMEM_NS = "ZPVoiceoverSharedBus"
local gmem_ok = false
if reaper.gmem_attach then
  reaper.gmem_attach(GMEM_NS)
  gmem_ok = true
end

local function is_en()
  if gmem_ok and reaper.gmem_read and reaper.gmem_read(3901) == 1 then return true end
  local v = reaper.GetExtState and reaper.GetExtState("ZP_Studio_Suite", "lang") or ""
  return v == "en"
end
local function L(it, en) return is_en() and en or it end

-- Lettura sicura gmem Shared Bus v3 (64 slot x 32 float + Master Reference 410..425)
local function read_gmem_nodes(now_t)
  local nodes = {}
  if not gmem_ok or not reaper.gmem_read then return nodes, { ok = false } end
  local gr = reaper.gmem_read
  for i = 0, 63 do
    local b = 1024 + i * 32
    if gr(b) == 905301 then
      local ts = gr(b + 1)
      if (now_t - ts) <= 2.5 then
        local s0 = gr(b + 2)
        local nd = {
          inst_key = gr(b + 3),
          plugin_type = gr(b + 4),
          track_idx = gr(b + 5),
          chain_pos = gr(b + 6),
          host_flags = gr(b + 7),
          stage_role = gr(b + 8),
          status_flags = gr(b + 9),
          gr_comp_db = gr(b + 10),
          gr_dyneq_db = gr(b + 11),
          gr_lim_db = gr(b + 12),
          tone_low_db = gr(b + 13),
          tone_mid_db = gr(b + 14),
          tone_high_db = gr(b + 15),
          harm_pct = gr(b + 16),
          rms_in_db = gr(b + 17),
          rms_out_db = gr(b + 18),
          peak_out_db = gr(b + 19),
          gain_delta_db = gr(b + 20),
          activity_pct = gr(b + 21),
          crest_db = gr(b + 22),
          bright_db = gr(b + 23),
          det1 = gr(b + 24),
          det2 = gr(b + 25),
          det3 = gr(b + 26),
          det4 = gr(b + 27),
          det5 = gr(b + 28),
          det6 = gr(b + 29),
          sub_excess_db = gr(b + 30),
          voice_band_flag = gr(b + 31),
          comb_ms = (math.floor((gr(b + 4) or 0) + 0.5) == 11) and gr(b + 30) or 0,
          comb_est = (math.floor((gr(b + 4) or 0) + 0.5) == 11) and gr(b + 31) or 0,
        }
        local s1 = gr(b + 2)
        if s0 == s1 then
          nodes[#nodes + 1] = nd
        end
      end
    end
  end

  local mref = { ok = false }
  if gr(410) == 905410 and (now_t - gr(411)) <= 3.0 then
    mref = {
      ok = true,
      tone_on = gr(412),
      tone_dyn_on = gr(413),
      tone_slope = gr(414),
      tone_gain1 = gr(415),
      tone_gain2 = gr(416),
      tone_gain3 = gr(417),
      tone_gain4 = gr(418),
      out_mode = gr(419),
      out_target_lufs = gr(420),
      lim_ceiling = gr(421),
      ui_lufs_s = gr(422),
      ui_lufs_i = gr(423),
      ui_tp_db = gr(424),
      target_profile = gr(425),
    }
  end
  return nodes, mref
end

local function read_fx_list(tr)
  local list = {}
  if not tr or not reaper.TrackFX_GetCount then return list end
  local cnt = reaper.TrackFX_GetCount(tr) or 0
  for fi = 0, cnt - 1 do
    local name = "FX " .. tostring(fi + 1)
    if reaper.TrackFX_GetFXName then
      local ok, nm = reaper.TrackFX_GetFXName(tr, fi, "")
      if ok and nm and nm ~= "" then
        name = nm:gsub("^JS:%s*", ""):gsub("^VST3i?:%s*", ""):gsub("^VSTi?:%s*", ""):gsub("^AUi?:%s*", ""):gsub("^CLAPi?:%s*", "")
      end
    end
    local enabled = reaper.TrackFX_GetEnabled and reaper.TrackFX_GetEnabled(tr, fi) or true
    local offline = reaper.TrackFX_GetOffline and reaper.TrackFX_GetOffline(tr, fi) or false
    local host_gr = 0
    local pcont = nil
    local pdc_samples = 0
    local pdc_mode = nil
    local chain_pdc_reporting = nil
    local chain_pdc_actual = nil
    if reaper.TrackFX_GetNamedConfigParm then
      local ok_gr, gr_str = reaper.TrackFX_GetNamedConfigParm(tr, fi, "GainReduction_dB")
      if ok_gr and gr_str and gr_str ~= "" then
        local v = tonumber(gr_str)
        if v then host_gr = (v < 0) and -v or v end
      end
      local ok_pc, pc_str = reaper.TrackFX_GetNamedConfigParm(tr, fi, "parent_container")
      if ok_pc and pc_str and pc_str ~= "" then pcont = pc_str end
      local ok_pdc, pdc_str = reaper.TrackFX_GetNamedConfigParm(tr, fi, "pdc")
      if ok_pdc and pdc_str and pdc_str ~= "" then
        local pv = tonumber(pdc_str)
        if pv then pdc_samples = math.max(0, math.floor(pv + 0.5)) end
      end
      local ok_pm, pm_str = reaper.TrackFX_GetNamedConfigParm(tr, fi, "chain_pdc_mode")
      if ok_pm and pm_str and pm_str ~= "" then
        local mv = tonumber(pm_str)
        if mv then pdc_mode = math.floor(mv + 0.5) end
      end
      local ok_pr, pr_str = reaper.TrackFX_GetNamedConfigParm(tr, fi, "chain_pdc_reporting")
      if ok_pr and pr_str and pr_str ~= "" then
        local rv = tonumber(pr_str)
        if rv then chain_pdc_reporting = math.max(0, math.floor(rv + 0.5)) end
      end
      local ok_pa, pa_str = reaper.TrackFX_GetNamedConfigParm(tr, fi, "chain_pdc_actual")
      if ok_pa and pa_str and pa_str ~= "" then
        local av = tonumber(pa_str)
        if av then chain_pdc_actual = math.max(0, math.floor(av + 0.5)) end
      end
    end
    list[#list + 1] = {
      fx_idx = fi,
      name = name,
      enabled = enabled,
      offline = offline,
      host_gr_db = host_gr,
      parent_container = pcont,
      pdc_samples = pdc_samples,
      pdc_mode = pdc_mode,
      chain_pdc_reporting = chain_pdc_reporting,
      chain_pdc_actual = chain_pdc_actual,
    }
  end
  return list
end

-- Snapshot completo del grafo di routing del progetto attivo
local function collect_project_snap()
  local snap = { tracks = {}, master_fx = {} }
  local n_tr = reaper.CountTracks and reaper.CountTracks(0) or 0
  local ptr_to_idx = {}
  local tr_ptrs = {}

  for i = 0, n_tr - 1 do
    local tr = reaper.GetTrack(0, i)
    if tr then
      ptr_to_idx[tr] = i
      tr_ptrs[i] = tr
    end
  end

  for i = 0, n_tr - 1 do
    local tr = tr_ptrs[i]
    if tr then
      local _, tname = reaper.GetTrackName(tr, "")
      local parent_tr = reaper.GetParentTrack and reaper.GetParentTrack(tr) or nil
      local parent_idx = (parent_tr and ptr_to_idx[parent_tr] ~= nil) and ptr_to_idx[parent_tr] or -1
      local main_send = (reaper.GetMediaTrackInfo_Value(tr, "B_MAINSEND") or 1) >= 0.5
      local mute = (reaper.GetMediaTrackInfo_Value(tr, "B_MUTE") or 0) >= 0.5
      local solo = reaper.GetMediaTrackInfo_Value(tr, "I_SOLO") or 0
      local fader_vol = reaper.GetMediaTrackInfo_Value(tr, "D_VOL") or 1.0
      local fader_db = TE.vol_to_db(fader_vol)
      local pk0 = reaper.Track_GetPeakInfo and reaper.Track_GetPeakInfo(tr, 0) or 0
      local pk1 = reaper.Track_GetPeakInfo and reaper.Track_GetPeakInfo(tr, 1) or 0
      local peak_db = TE.vol_to_db(math.max(pk0, pk1))

      local sends = {}
      local n_sd = reaper.GetTrackNumSends and reaper.GetTrackNumSends(tr, 0) or 0
      for s = 0, n_sd - 1 do
        local dest = reaper.GetTrackSendInfo_Value(tr, 0, s, "P_DESTTRACK")
        local dest_idx = (dest and ptr_to_idx[dest] ~= nil) and ptr_to_idx[dest] or -1
        local svol = reaper.GetTrackSendInfo_Value(tr, 0, s, "D_VOL") or 1.0
        local smute = (reaper.GetTrackSendInfo_Value(tr, 0, s, "B_MUTE") or 0) >= 0.5
        local smode = reaper.GetTrackSendInfo_Value(tr, 0, s, "I_SENDMODE") or 0
        sends[#sends + 1] = {
          dest_idx = dest_idx,
          send_db = TE.vol_to_db(svol),
          mute = smute,
          mode = smode,
        }
      end

      snap.tracks[#snap.tracks + 1] = {
        idx = i,
        name = tname or ("Tr " .. tostring(i + 1)),
        parent_idx = parent_idx,
        main_send = main_send,
        mute = mute,
        solo = solo,
        fader_db = fader_db,
        peak_db = peak_db,
        sends = sends,
        fx = read_fx_list(tr),
      }
    end
  end

  local mtr = reaper.GetMasterTrack and reaper.GetMasterTrack(0) or nil
  snap.master_fx = read_fx_list(mtr)
  return snap
end

-- Apertura diretta di qualsiasi FX (ZP o terze parti) su traccia o Master
local function open_fx_window(track_idx, fx_idx)
  if track_idx == nil or fx_idx == nil or fx_idx < 0 then return false end
  local tr = (track_idx < 0) and reaper.GetMasterTrack(0) or reaper.GetTrack(0, track_idx)
  if not tr then return false end
  local cnt = reaper.TrackFX_GetCount(tr) or 0
  if fx_idx >= cnt then return false end
  reaper.TrackFX_Show(tr, fx_idx, 3)
  return true
end

-- Fallback Track Directory + Open-FX SOLO se Cue Navigator non e' attivo
local dir_hb = 0
local last_dir_write = 0
local last_cmd_seq = -1
local function serve_fallback_directory_and_open(now_t, snap)
  if not gmem_ok or not reaper.gmem_read or not reaper.gmem_write then return end
  local gr, gw = reaper.gmem_read, reaper.gmem_write
  local cue_nav_alive = (gr(1004) > 0) and ((now_t - gr(1005)) <= 3.0) and (dir_hb == 0 or gr(1004) ~= dir_hb)
  if cue_nav_alive then return end

  if (now_t - last_dir_write) >= 0.5 then
    last_dir_write = now_t
    local cnt = math.min(64, #snap.tracks)
    for i = 0, 63 do
      local base = 3072 + i * 8
      local tr = snap.tracks[i + 1]
      if tr and tr.idx == i then
        local flags = 1
        if tr.mute then flags = flags + 2 end
        if (tr.solo or 0) > 0 then flags = flags + 4 end
        local uname = string.upper(tr.name or "")
        if uname:find("VO_BUS", 1, true) or uname:find("VOCE", 1, true) or uname:find("VOICE", 1, true) then flags = flags + 16 end
        if uname:find("MUSIC", 1, true) or uname:find("MUSICA", 1, true) then flags = flags + 32 end
        local nlen, packed = TE.pack_name(tr.name or "")
        gw(base + 0, flags)
        gw(base + 1, tr.parent_idx or -1)
        gw(base + 2, nlen)
        for g = 0, 4 do gw(base + 3 + g, packed[g + 1] or 0) end
      else
        for k = 0, 7 do gw(base + k, 0) end
      end
    end
    dir_hb = dir_hb + 1
    gw(1004, dir_hb)
    gw(1005, now_t)
    gw(1006, cnt)
  end

  local req = math.floor(gr(1010) + 0.5)
  local ack = math.floor(gr(1011) + 0.5)
  if req > 0 and req ~= ack and req ~= last_cmd_seq then
    last_cmd_seq = req
    local ti = math.floor(gr(1008) + 0.5)
    local fi = math.floor(gr(1009) + 0.5)
    local ok = open_fx_window(ti, fi)
    gw(1012, ok and 1 or 2)
    gw(1011, req)
  end
end

-- Stato UI e loop
local state = TE.new_state()
local active_tab = 0 -- 0 = ACCORDATURA, 1 = GRAFO CATENA
local scroll_y = { [0] = 0, [1] = 0 }
local last_cap = 0
local last_tick_t = reaper.time_precise()
local te_hb = 0
local status_toast = ""
local status_toast_until = 0

local function hit(x, y, w, h)
  return gfx.mouse_x >= x and gfx.mouse_x <= x + w and gfx.mouse_y >= y and gfx.mouse_y <= y + h
end

local function draw_btn(x, y, w, h, label, bg_r, bg_g, bg_b, txt_r, txt_g, txt_b, click)
  local hvr = hit(x, y, w, h)
  local mul = hvr and 1.18 or 1.0
  gfx.set(math.min(1, bg_r * mul), math.min(1, bg_g * mul), math.min(1, bg_b * mul), 1)
  gfx.rect(x, y, w, h, 1)
  gfx.set(0.32, 0.40, 0.50, 0.75)
  gfx.rect(x, y, w, h, 0)
  gfx.setfont(1, "Arial", 11, string.byte("b"))
  local tw, th = gfx.measurestr(label)
  gfx.set(txt_r, txt_g, txt_b, 1)
  gfx.x = x + (w - tw) * 0.5
  gfx.y = y + (h - th) * 0.5
  gfx.drawstr(label)
  return hvr and click
end

local function draw_zone_card(x, y, w, h, lbl, val, valid, green_lim, yellow_lim)
  gfx.set(0.11, 0.13, 0.17, 1)
  gfx.rect(x, y, w, h, 1)
  local av = math.abs(val)
  if not valid then
    gfx.set(0.35, 0.40, 0.48, 0.7)
  elseif av <= green_lim then
    gfx.set(0.24, 0.84, 0.52, 0.95)
  elseif av <= yellow_lim then
    gfx.set(0.95, 0.72, 0.22, 0.95)
  else
    gfx.set(0.96, 0.34, 0.28, 0.95)
  end
  gfx.rect(x, y, w, 3, 1)
  gfx.set(0.22, 0.26, 0.34, 0.85)
  gfx.rect(x, y, w, h, 0)

  gfx.setfont(1, "Arial", 10, string.byte("b"))
  gfx.set(0.60, 0.68, 0.78, 1)
  gfx.x = x + 8; gfx.y = y + 7
  gfx.drawstr(lbl .. " Hz")

  gfx.setfont(1, "Arial", 14, string.byte("b"))
  if not valid then
    gfx.set(0.50, 0.56, 0.64, 1)
  elseif av <= green_lim then
    gfx.set(0.32, 0.92, 0.58, 1)
  elseif av <= yellow_lim then
    gfx.set(0.98, 0.78, 0.30, 1)
  else
    gfx.set(1.0, 0.44, 0.36, 1)
  end
  gfx.x = x + 8; gfx.y = y + 22
  gfx.drawstr(valid and string.format("%+.1f dB", val) or "--")

  -- Barra bipolare ±6 dB con corridoio verde ±1.5 dB
  local bx, by, bw, bh = x + 8, y + h - 14, w - 16, 8
  local cx = bx + bw * 0.5
  gfx.set(0.06, 0.07, 0.09, 1)
  gfx.rect(bx, by, bw, bh, 1)
  local gw = bw * (green_lim / 6.0)
  gfx.set(0.24, 0.84, 0.52, 0.20)
  gfx.rect(cx - gw * 0.5, by, gw, bh, 1)
  if valid then
    local fw = math.max(-1, math.min(1, val / 6.0)) * (bw * 0.5)
    if av <= green_lim then gfx.set(0.26, 0.86, 0.54, 0.9)
    elseif av <= yellow_lim then gfx.set(0.95, 0.72, 0.24, 0.9)
    else gfx.set(0.96, 0.36, 0.30, 0.9) end
    if fw >= 0 then gfx.rect(cx, by + 1, math.max(1, fw), bh - 2, 1)
    else gfx.rect(cx + fw, by + 1, math.max(1, -fw), bh - 2, 1) end
  end
  gfx.set(0.45, 0.52, 0.62, 0.8)
  gfx.line(cx, by - 1, cx, by + bh + 1)
end

local function draw_ui(rep, click)
  local W, H = 840, 580
  gfx.set(0.065, 0.075, 0.095, 1)
  gfx.rect(0, 0, W, H, 1)

  -- Header
  gfx.set(0.095, 0.112, 0.145, 1)
  gfx.rect(0, 0, W, 44, 1)
  gfx.set(0.20, 0.25, 0.34, 1)
  gfx.line(0, 44, W, 44)

  gfx.setfont(1, "Arial", 16, string.byte("b"))
  gfx.set(0.92, 0.95, 0.99, 1)
  gfx.x = 14; gfx.y = 12
  gfx.drawstr("ZP TELEMETRY ENGINE · latocardioide.it · dubbertools.com")

  -- Pill stato PLAY/HOLD + secondi utili
  local pill_x = 228
  if rep.holding then
    gfx.set(0.24, 0.20, 0.12, 1)
  else
    gfx.set(0.10, 0.30, 0.20, 1)
  end
  gfx.rect(pill_x, 10, 126, 24, 1)
  gfx.setfont(1, "Arial", 11, string.byte("b"))
  if rep.holding then gfx.set(0.98, 0.78, 0.34, 1) else gfx.set(0.38, 0.94, 0.62, 1) end
  gfx.x = pill_x + 8; gfx.y = 16
  gfx.drawstr(string.format("%s · %.1fs", rep.holding and "HOLD" or "PLAY", rep.useful_sec))

  -- Badge Metro di riferimento
  local ref_x = 362
  local ref_lbl = L("METRO: ", "FRAME: ") .. (is_en() and rep.ref.mode_label_en or rep.ref.mode_label_it)
  gfx.set(rep.ref.mode == 0 and 0.13 or 0.18, rep.ref.mode == 0 and 0.18 or 0.16, rep.ref.mode == 0 and 0.26 or 0.30, 1)
  gfx.rect(ref_x, 10, 260, 24, 1)
  gfx.set(0.76, 0.88, 0.98, 1)
  gfx.x = ref_x + 8; gfx.y = 16
  gfx.drawstr(ref_lbl)

  -- Stato globale
  local st_x = 630
  local st_txt = L("ATTESA", "WAITING")
  if rep.status == 1 then
    gfx.set(0.12, 0.34, 0.22, 1); st_txt = L("IN TOLLERANZA", "IN WINDOW")
  elseif rep.status == 2 then
    gfx.set(0.38, 0.26, 0.08, 1); st_txt = L("ATTENZIONE", "ATTENTION")
  elseif rep.status >= 3 then
    gfx.set(0.44, 0.13, 0.12, 1); st_txt = L("ACCORDATURA", "TUNE CHAIN")
  else
    gfx.set(0.16, 0.19, 0.24, 1)
  end
  gfx.rect(st_x, 10, 114, 24, 1)
  gfx.set(0.96, 0.97, 0.99, 1)
  local stw, sth = gfx.measurestr(st_txt)
  gfx.x = st_x + (114 - stw) * 0.5; gfx.y = 10 + (24 - sth) * 0.5
  gfx.drawstr(st_txt)

  if draw_btn(752, 10, 74, 24, "RESET", 0.32, 0.14, 0.14, 0.98, 0.86, 0.84, click) then
    TE.reset_state(state)
    status_toast = L("Medie azzerate.", "Averages reset.")
    status_toast_until = reaper.time_precise() + 2.0
  end

  -- Fascia Metro Uscita Master (4 zone Brown + Tilt + Loudness/TP)
  local my = 54
  local zw = 128
  local zlabels = (rep.master_spec.valid and rep.master_spec.is_voice_band) and TE.FRAME.VOICE_ZONE_LABELS or TE.FRAME.ZONE_LABELS
  for k = 1, 4 do
    draw_zone_card(14 + (k - 1) * (zw + 8), my, zw, 62, zlabels[k], rep.z_err[k], rep.master_spec.valid, rep.ref.zone_green, rep.ref.zone_yellow)
  end

  -- Card Tilt
  local tx = 14 + 4 * (zw + 8)
  gfx.set(0.11, 0.13, 0.17, 1); gfx.rect(tx, my, 128, 62, 1)
  gfx.set(0.22, 0.26, 0.34, 0.85); gfx.rect(tx, my, 128, 62, 0)
  gfx.setfont(1, "Arial", 10, string.byte("b")); gfx.set(0.60, 0.68, 0.78, 1)
  gfx.x = tx + 8; gfx.y = my + 7; gfx.drawstr(L("TILT vs METRO", "TILT vs FRAME"))
  gfx.setfont(1, "Arial", 14, string.byte("b"))
  local tok = rep.master_spec.valid and math.abs(rep.tilt_err) <= rep.ref.slope_tol
  if not rep.master_spec.valid then gfx.set(0.50, 0.56, 0.64, 1)
  elseif tok then gfx.set(0.32, 0.92, 0.58, 1) else gfx.set(0.98, 0.66, 0.26, 1) end
  gfx.x = tx + 8; gfx.y = my + 23
  gfx.drawstr(rep.master_spec.valid and string.format("%+.2f dB/o", rep.tilt_err) or "--")
  gfx.setfont(1, "Arial", 10); gfx.set(0.56, 0.64, 0.74, 1)
  gfx.x = tx + 8; gfx.y = my + 44
  gfx.drawstr(string.format("±%.2f · %s", rep.ref.slope_tol, rep.master_spec.valid and rep.master_spec.source:sub(1, 12) or "n/d"))

  -- Card Loudness / TP
  local lx = tx + 136
  local lw = W - lx - 14
  gfx.set(0.11, 0.13, 0.17, 1); gfx.rect(lx, my, lw, 62, 1)
  gfx.set(0.22, 0.26, 0.34, 0.85); gfx.rect(lx, my, lw, 62, 0)
  gfx.setfont(1, "Arial", 10, string.byte("b")); gfx.set(0.60, 0.68, 0.78, 1)
  gfx.x = lx + 8; gfx.y = my + 7; gfx.drawstr(string.format("LUFS (T %.1f)", rep.ref.lufs_target))
  gfx.setfont(1, "Arial", 14, string.byte("b"))
  local lok = rep.master_loud.valid and math.abs(rep.lufs_err) <= rep.ref.lufs_tol
  if not rep.master_loud.valid then gfx.set(0.50, 0.56, 0.64, 1)
  elseif lok then gfx.set(0.32, 0.92, 0.58, 1) else gfx.set(0.98, 0.66, 0.26, 1) end
  gfx.x = lx + 8; gfx.y = my + 23
  gfx.drawstr(rep.master_loud.valid and string.format("%+.1f LU", rep.lufs_err) or "--")
  gfx.setfont(1, "Arial", 10); gfx.set(0.58, 0.66, 0.76, 1)
  gfx.x = lx + 8; gfx.y = my + 44
  gfx.drawstr(rep.master_loud.valid and string.format("TP %.1f dB", rep.master_loud.tp) or "n/d")

  -- Barra Tab
  local ty = 126
  local tab0_lbl = string.format("%s (%d)", L("ACCORDATURA", "TUNING"), #rep.active_issues)
  local tab1_lbl = string.format("%s (%d)", L("GRAFO CATENA", "CHAIN GRAPH"), state.graph and #state.graph.tracks or 0)
  if draw_btn(14, ty, 175, 24, tab0_lbl, active_tab == 0 and 0.18 or 0.12, active_tab == 0 and 0.46 or 0.15, active_tab == 0 and 0.82 or 0.20, 0.96, 0.98, 1.0, click) then
    active_tab = 0
  end
  if draw_btn(196, ty, 175, 24, tab1_lbl, active_tab == 1 and 0.18 or 0.12, active_tab == 1 and 0.46 or 0.15, active_tab == 1 and 0.82 or 0.20, 0.96, 0.98, 1.0, click) then
    active_tab = 1
  end

  -- Conteggio pre-enfasi riconosciute + profilo acustico + V-M / HSC + ripristina scelte ignorate
  local ign_cnt = 0
  for _ in pairs(state.ignored) do ign_cnt = ign_cnt + 1 end
  local pmode_txt = (rep.program_mode == "FULL_MIX")
    and ((rep.carver and rep.carver.valid)
      and string.format("FULL MIX · HSC Duck -%.1f / Mid -%.1f", rep.carver.vca_duck, rep.carver.carver_mid)
      or "FULL MIX (40-14k)")
    or L("SOLO VOCE (85-14k)", "VOICE ONLY (85-14k)")
  if rep.program_mode == "FULL_MIX" and (rep.vm_speech_sec or 0) >= 1.0 then
    pmode_txt = pmode_txt .. string.format(" · V-M %+.1f dB", rep.vm_diff_avg or 0)
  end
  gfx.setfont(1, "Arial", 10, string.byte("b")); gfx.set(0.60, 0.74, 0.86, 1)
  gfx.x = 380; gfx.y = ty + 2
  gfx.drawstr(pmode_txt)
  gfx.setfont(1, "Arial", 10); gfx.set(0.54, 0.64, 0.74, 1)
  gfx.x = 380; gfx.y = ty + 14
  gfx.drawstr(string.format(L("Pre-enfasi: %d  |  Volute: %d", "Pre-emph: %d  |  Intended: %d"), rep.preemph_count, ign_cnt))
  if ign_cnt > 0 then
    if draw_btn(W - 146, ty, 132, 24, L("Ripristina scelte", "Restore choices"), 0.18, 0.22, 0.28, 0.88, 0.92, 0.98, click) then
      TE.clear_ignored(state)
    end
  end

  -- Area contenuto scorrevole
  local cy, ch = 158, H - 158 - 30
  gfx.set(0.085, 0.098, 0.122, 1)
  gfx.rect(14, cy, W - 28, ch, 1)
  gfx.set(0.20, 0.24, 0.32, 0.9)
  gfx.rect(14, cy, W - 28, ch, 0)

  if gfx.mouse_wheel ~= 0 then
    scroll_y[active_tab] = math.max(0, scroll_y[active_tab] - (gfx.mouse_wheel > 0 and 36 or -36))
    gfx.mouse_wheel = 0
  end

  local sc = scroll_y[active_tab]
  local ycur = cy + 10 - sc
  local max_y = cy + ch - 8

  if active_tab == 0 then
    if not rep.ready and #rep.issues == 0 then
      gfx.setfont(1, "Arial", 13); gfx.set(0.68, 0.74, 0.82, 1)
      gfx.x = 28; gfx.y = cy + 20
      gfx.drawstr(string.format(L("Avvia PLAY per raccogliere almeno %.0f s di segnale utile (raccolti: %.1f s).", "Start PLAY to gather at least %.0f s of useful signal (gathered: %.1f s)."), TE.FRAME.MIN_JUDGE_SEC, rep.useful_sec))
      gfx.setfont(1, "Arial", 11); gfx.set(0.54, 0.62, 0.72, 1)
      gfx.x = 28; gfx.y = cy + 44
      gfx.drawstr(L("Le segnalazioni lavorano sulle medie: nessuna reazione isterica sui picchi isolati.", "Advice is based on useful-signal averages: no jittery reactions on isolated peaks."))
    elseif #rep.issues == 0 then
      gfx.setfont(1, "Arial", 14, string.byte("b")); gfx.set(0.32, 0.92, 0.58, 1)
      gfx.x = 28; gfx.y = cy + 20
      gfx.drawstr(L("Catena accordata dentro il margine di riferimento.", "Chain is balanced within the reference window."))
      ycur = cy + 50 - sc
    else
      for _, it in ipairs(rep.issues) do
        local rh = 56
        if ycur + rh > cy + 2 and ycur < max_y then
          if it.ignored then
            gfx.set(0.11, 0.12, 0.15, 0.70)
          elseif it.severity >= 3 then
            gfx.set(0.24, 0.11, 0.11, 0.95)
          else
            gfx.set(0.20, 0.16, 0.10, 0.95)
          end
          gfx.rect(22, ycur, W - 44, rh - 6, 1)
          if it.ignored then gfx.set(0.36, 0.40, 0.48, 0.8)
          elseif it.severity >= 3 then gfx.set(0.96, 0.34, 0.28, 1)
          else gfx.set(0.96, 0.72, 0.24, 1) end
          gfx.rect(22, ycur, 4, rh - 6, 1)

          gfx.setfont(1, "Arial", 12, string.byte("b"))
          if it.ignored then gfx.set(0.56, 0.60, 0.68, 1) else gfx.set(0.95, 0.97, 0.99, 1) end
          gfx.x = 34; gfx.y = ycur + 7
          gfx.drawstr(is_en() and it.title_en or it.title_it)

          gfx.setfont(1, "Arial", 11)
          gfx.set(0.68, 0.74, 0.82, 1)
          gfx.x = 34; gfx.y = ycur + 26
          gfx.drawstr(is_en() and it.detail_en or it.detail_it)

          local bx = W - 196
          if it.fx_idx ~= nil and it.fx_idx >= 0 then
            if draw_btn(bx, ycur + 12, 76, 24, L("APRI FX", "OPEN FX"), 0.18, 0.42, 0.72, 0.96, 0.98, 1.0, click) then
              open_fx_window(it.track_idx, it.fx_idx)
              status_toast = L("Finestra FX aperta.", "FX window opened.")
              status_toast_until = reaper.time_precise() + 2.0
            end
          end
          local ign_lbl = it.ignored and L("RIATTIVA", "UNMUTE") or L("VOLUTA", "INTENDED")
          if draw_btn(bx + 82, ycur + 12, 84, 24, ign_lbl, 0.20, 0.24, 0.30, 0.86, 0.90, 0.96, click) then
            TE.toggle_ignore(state, it.key)
          end
        end
        ycur = ycur + rh
      end
    end

    -- Sezione informativa Pre-enfasi riconosciute
    if #rep.pre_emphasis > 0 then
      ycur = ycur + 6
      if ycur + 22 > cy and ycur < max_y then
        gfx.setfont(1, "Arial", 11, string.byte("b")); gfx.set(0.46, 0.74, 0.62, 1)
        gfx.x = 24; gfx.y = ycur
        gfx.drawstr(L("PRE-ENFASI / RECUPERI RICONOSCIUTI (non segnalati come conflitto):", "RECOGNIZED PRE-EMPHASIS / MAKEUP (not flagged as conflict):"))
      end
      ycur = ycur + 20
      for _, pe in ipairs(rep.pre_emphasis) do
        if ycur + 20 > cy and ycur < max_y then
          gfx.setfont(1, "Arial", 11); gfx.set(0.60, 0.72, 0.68, 1)
          gfx.x = 30; gfx.y = ycur
          gfx.drawstr("• " .. (is_en() and pe.title_en or pe.title_it))
        end
        ycur = ycur + 19
      end
    end
  else
    -- Tab 1: GRAFO CATENA (tracce attive + FX ZP e terze parti + Master)
    local graph = state.graph
    if graph then
      local function draw_fx_row(sg, indent_px)
        local rh = 24
        if ycur + rh > cy + 2 and ycur < max_y then
          local av = state.stage_avg[sg.key]
          local hvr = hit(24 + indent_px, ycur, W - 48 - indent_px, rh - 2)
          if hvr then gfx.set(0.16, 0.22, 0.30, 0.95) else gfx.set(0.11, 0.13, 0.17, 0.90) end
          gfx.rect(24 + indent_px, ycur, W - 48 - indent_px, rh - 2, 1)

          gfx.setfont(1, "Arial", 11, string.byte("b"))
          if not sg.enabled then gfx.set(0.45, 0.48, 0.54, 1)
          elseif sg.is_zp then gfx.set(0.46, 0.82, 0.98, 1)
          else gfx.set(0.86, 0.76, 0.54, 1) end
          gfx.x = 32 + indent_px; gfx.y = ycur + 5
          local tag = sg.is_zp and "[ZP]" or "[EXT]"
          gfx.drawstr(string.format("%s FX%d %s", tag, sg.fx_idx + 1, sg.name:sub(1, 28)))

          local gr = av and av.gr_total or sg.gr_total or 0
          local gd = av and av.gain_delta or sg.gain_delta_db or 0
          local hm = av and av.harm or sg.harm_pct or 0
          gfx.setfont(1, "Arial", 11); gfx.set(0.76, 0.82, 0.90, 1)
          gfx.x = 420; gfx.y = ycur + 5
          if not sg.enabled then
            gfx.drawstr("BYPASS")
          else
            gfx.drawstr(string.format("GR %.1f dB  |  Gain %+.1f dB  |  Sat %.0f%%", gr, gd, hm))
          end

          if hvr and click then
            open_fx_window(sg.track_idx, sg.fx_idx)
            status_toast = L("Aperto: ", "Opened: ") .. sg.name
            status_toast_until = reaper.time_precise() + 2.0
          end
        end
        ycur = ycur + rh
      end

      for _, tr in ipairs(graph.tracks) do
        if tr.active then
          local ind = math.min(60, (tr.depth or 0) * 16)
          if ycur + 22 > cy + 2 and ycur < max_y then
            gfx.setfont(1, "Arial", 12, string.byte("b")); gfx.set(0.86, 0.92, 0.98, 1)
            gfx.x = 22 + ind; gfx.y = ycur + 3
            local dest_s = (tr.parent_idx >= 0 and graph.tracks_by_idx[tr.parent_idx])
              and (" -> " .. graph.tracks_by_idx[tr.parent_idx].name) or " -> MASTER"
            gfx.drawstr(string.format("Tr %d · %s  (Fader %+.1f dB)%s", tr.idx + 1, tr.name, tr.fader_db, dest_s))
          end
          ycur = ycur + 22
          for _, sg in ipairs(graph.track_stages[tr.idx] or {}) do
            draw_fx_row(sg, ind + 14)
          end
        end
      end

      -- Master track
      if ycur + 24 > cy + 2 and ycur < max_y then
        gfx.setfont(1, "Arial", 12, string.byte("b")); gfx.set(0.45, 0.92, 0.65, 1)
        gfx.x = 22; gfx.y = ycur + 4
        gfx.drawstr("MASTER TRACK")
      end
      ycur = ycur + 24
      for _, sg in ipairs(graph.master_stages or {}) do
        draw_fx_row(sg, 14)
      end

      -- Eventuali residui differenziali di segmenti esterni
      if #rep.ext_segments > 0 then
        ycur = ycur + 8
        if ycur + 20 > cy and ycur < max_y then
          gfx.setfont(1, "Arial", 11, string.byte("b")); gfx.set(0.92, 0.78, 0.42, 1)
          gfx.x = 22; gfx.y = ycur
          gfx.drawstr(L("RESIDUI DIFFERENZIALI BLOCCHI ESTERNI:", "DIFFERENTIAL RESIDUALS ON EXTERNAL BLOCKS:"))
        end
        ycur = ycur + 19
        for _, seg in ipairs(rep.ext_segments) do
          if ycur + 20 > cy and ycur < max_y then
            gfx.setfont(1, "Arial", 11); gfx.set(0.84, 0.80, 0.66, 1)
            gfx.x = 28; gfx.y = ycur
            local zs = seg.has_z_diff and string.format("  |  ΔZ: %+.1f %+.1f %+.1f %+.1f dB", seg.resid_z[1], seg.resid_z[2], seg.resid_z[3], seg.resid_z[4]) or ""
            gfx.drawstr(string.format("• %s: ΔGain %+.1f dB%s", seg.label, seg.resid_gain, zs))
          end
          ycur = ycur + 19
        end
      end
    end
  end

  -- Footer
  gfx.setfont(1, "Arial", 10); gfx.set(0.52, 0.60, 0.70, 1)
  gfx.x = 14; gfx.y = H - 22
  if reaper.time_precise() < status_toast_until and status_toast ~= "" then
    gfx.set(0.45, 0.92, 0.66, 1)
    gfx.drawstr(status_toast)
  else
    gfx.drawstr(L("ZP Telemetry Engine · Solo consultivo (nessuna modifica automatica) · Clic su riga o APRI FX apre il plugin.", "ZP Telemetry Engine · Advisory only (zero automatic changes) · Click any row or OPEN FX to open plugin."))
  end
end

local function main_loop()
  local ch = gfx.getchar()
  if ch < 0 or ch == 27 then
    local dock, x, y, w, h = gfx.dock(-1, 0, 0, 0, 0)
    if reaper.SetExtState then
      reaper.SetExtState(EXT_SEC, "win", string.format("%d,%d,%d,%d,%d", dock, x, y, w, h), true)
    end
    return
  end

  local now_t = reaper.time_precise()
  if (now_t - last_tick_t) >= 0.25 or not state.last_report then
    local dt = now_t - last_tick_t
    last_tick_t = now_t
    local snap = collect_project_snap()
    local nodes, mref = read_gmem_nodes(now_t)
    local playing = (reaper.GetPlayState() & 1) == 1
    TE.step(state, dt, playing, snap, nodes, mref)

    te_hb = te_hb + 1
    if gmem_ok and reaper.gmem_write then
      local summ = TE.build_gmem_summary(state, now_t, te_hb)
      for idx, val in pairs(summ) do
        reaper.gmem_write(idx, val)
      end
    end
    serve_fallback_directory_and_open(now_t, snap)
  end

  local click = ((gfx.mouse_cap & 1) == 1) and ((last_cap & 1) == 0)
  last_cap = gfx.mouse_cap
  draw_ui(state.last_report or TE.analyze(state), click)
  gfx.update()
  reaper.defer(main_loop)
end

-- Apertura finestra (ripristina posizione se salvata)
local dx, dy, dw, dh, dd = 120, 120, 840, 580, 0
if reaper.GetExtState then
  local saved = reaper.GetExtState(EXT_SEC, "win")
  if saved and saved ~= "" then
    local sd, sx, sy, sw, sh = saved:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
    if sw and sh then
      dd = tonumber(sd) or 0; dx = tonumber(sx) or 120; dy = tonumber(sy) or 120
      dw = math.max(540, tonumber(sw) or 840); dh = math.max(380, tonumber(sh) or 580)
    end
  end
end
gfx.init("ZP Telemetry Engine", dw, dh, dd, dx, dy)
main_loop()
