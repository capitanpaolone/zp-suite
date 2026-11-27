-- Test della logica pura di ZP_Telemetry_Engine.lua (nessuna dipendenza REAPER/gfx)
-- Eseguibile con: lua gobbo_ricerca_battuta/test/test_telemetry_engine.lua

local info = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
local root = (info or "./") .. "../../"
local TE = dofile(root .. "ZP Studio Suite/ZP_Telemetry_Engine.lua")

local fails, total = 0, 0
local function check(name, cond, extra)
  total = total + 1
  if not cond then
    fails = fails + 1
    print("FAIL  " .. name .. (extra and ("  (" .. tostring(extra) .. ")") or ""))
  end
end

local function near(a, b, eps)
  return math.abs((a or 0) - (b or 0)) <= (eps or 0.05)
end

-- 1) Metro fisso di riferimento: Master Tone spento -> Brown 4.5 ±10% (±0.45 dB/oct)
do
  local ref = TE.compute_reference({ ok = true, tone_on = 0, tone_slope = 2.0, out_target_lufs = -16, lim_ceiling = -1 }, nil)
  check("ref tone OFF -> slope 4.5", near(ref.slope, 4.5, 0.001), ref.slope)
  check("ref tone OFF -> tol ±10% (0.45)", near(ref.slope_tol, 0.45, 0.001), ref.slope_tol)
  check("ref tone OFF -> mode 0", ref.mode == 0, ref.mode)
  check("ref tone OFF -> expected tilt vs brown 0", near(ref.expected_tilt_vs_brown, 0.0, 0.001))
end

-- 2) Precedenza Master Tone statico: piu' chiaro (tone_slope = -1.0 -> 3.5 dB/o) e offset zona 4
do
  local ref = TE.compute_reference({
    ok = true, tone_on = 1, tone_dyn_on = 0, tone_slope = -1.0,
    tone_gain1 = 0, tone_gain2 = 0, tone_gain3 = 0, tone_gain4 = 1.5,
    out_target_lufs = -14, lim_ceiling = -1.0,
  }, nil)
  check("ref Master Tone static brighter -> slope 3.5", near(ref.slope, 3.5, 0.001), ref.slope)
  check("ref Master Tone static -> expected tilt +1.0 vs brown", near(ref.expected_tilt_vs_brown, 1.0, 0.001), ref.expected_tilt_vs_brown)
  check("ref Master Tone static -> zone4 offset +1.5", near(ref.zone_offset[4], 1.5, 0.001), ref.zone_offset[4])
  check("ref Master Tone static -> mode 1", ref.mode == 1, ref.mode)
end

-- 3) Precedenza Master Tone dinamico: tone_slope = 5.2 dB/o (piu' scuro di Brown)
do
  local ref = TE.compute_reference({
    ok = true, tone_on = 1, tone_dyn_on = 1, tone_slope = 5.2,
    tone_gain1 = 0, tone_gain2 = 0, tone_gain3 = 0, tone_gain4 = 0,
  }, { det3 = -23.0, det4 = 0.5, det5 = -1.5 })
  check("ref Master Tone dyn -> slope 5.2", near(ref.slope, 5.2, 0.001), ref.slope)
  check("ref Master Tone dyn -> tol 0.52", near(ref.slope_tol, 0.52, 0.001), ref.slope_tol)
  check("ref Loudness Meter priority target -23", near(ref.lufs_target, -23.0, 0.001), ref.lufs_target)
  check("ref Loudness Meter priority tol 0.5", near(ref.lufs_tol, 0.5, 0.001), ref.lufs_tol)
  check("ref Loudness Meter priority TP -1.5", near(ref.tp_max, -1.5, 0.001), ref.tp_max)
end

-- 4) Verifica che se Master Tone vuole +1.0 dB/o piu' chiaro e Prism misura +1.0 dB/o vs Brown -> IN TOLLERANZA!
do
  local st = TE.new_state()
  local snap = {
    tracks = {
      { idx = 0, name = "Voce", parent_idx = -1, main_send = true, mute = false, solo = 0, fader_db = 0, peak_db = -12,
        fx = { { fx_idx = 0, name = "ZP Magic Voice LAB", enabled = true } } },
    },
    master_fx = {
      { fx_idx = 0, name = "ZP Master Pro", enabled = true },
      { fx_idx = 1, name = "ZP BrownSlope Prism", enabled = true },
    },
  }
  local nodes = {
    { plugin_type = 3, track_idx = 0, chain_pos = 0, status_flags = 1, rms_in_db = -20, rms_out_db = -18, activity_pct = 80, tone_low_db = 0, tone_mid_db = 0, tone_high_db = 1.0 },
    -- Spettro coerente con +1.0 dB/oct rispetto a Brown 4.5 sui 4 centri (80, 358, 1789, 7483 Hz)
    { plugin_type = 11, track_idx = -1, chain_pos = 1, status_flags = 1, tone_low_db = -3.3, tone_mid_db = -1.1, tone_high_db = 1.2, det6 = 3.2, bright_db = 1.0, det3 = 1, det2 = 1 },
  }
  local mref = { ok = true, tone_on = 1, tone_dyn_on = 0, tone_slope = -1.0, out_target_lufs = -16, ui_lufs_s = -16, ui_lufs_i = -16, ui_tp_db = -2.0, lim_ceiling = -1.0 }
  local rep
  for _ = 1, 25 do rep = TE.step(st, 0.25, true, snap, nodes, mref) end
  check("Master Tone brighter accepted as target -> tilt_err ~ 0", near(rep.tilt_err, 0.0, 0.05), rep.tilt_err)
  check("Master Tone brighter accepted -> status OK (1)", rep.status == 1, rep.status)
end

-- 5) Gating su PLAY/HOLD: in pausa o silenzio useful_sec e medie restano congelate
do
  local st = TE.new_state()
  local snap = {
    tracks = { { idx = 0, name = "Voce", parent_idx = -1, main_send = true, fader_db = 0, peak_db = -14, fx = { { fx_idx = 0, name = "Magic", enabled = true } } } },
    master_fx = {},
  }
  local nodes = { { plugin_type = 3, track_idx = 0, chain_pos = 0, status_flags = 1, rms_in_db = -20, rms_out_db = -18, activity_pct = 75 } }
  for _ = 1, 10 do TE.step(st, 0.25, true, snap, nodes, nil) end
  local u_before = st.useful_sec
  local rep_hold = TE.step(st, 0.5, false, snap, nodes, nil)
  check("HOLD in stop congela useful_sec", near(st.useful_sec, u_before, 0.0001), st.useful_sec)
  check("HOLD flag true in stop", rep_hold.holding == true)
end

-- 6) Tiro alla fune SENZA non-linearita' intermedia -> segnala OPPOSIZIONE (tono e gain)
do
  local st = TE.new_state()
  local snap = {
    tracks = {
      { idx = 0, name = "Voce 1", parent_idx = 1, main_send = true, fader_db = -5.5, peak_db = -12,
        fx = {
          { fx_idx = 0, name = "ZP Spoken Finish", enabled = true },
          { fx_idx = 1, name = "ZP Magic Voice LAB", enabled = true },
        } },
      { idx = 1, name = "VO_BUS", parent_idx = -1, main_send = true, fader_db = 0, peak_db = -12,
        fx = {
          { fx_idx = 0, name = "ZP BrownSlope Dynamic Guard", enabled = true },
        } },
    },
    master_fx = {},
  }
  -- Spoken Finish alza high (+3.2 dB) e trim +5.5 dB, Magic Voice LAB ha GR=0 / Sat=0 (lineare!),
  -- Fader Voce 1 e' a -5.5 dB, BrownSlope Guard taglia 4k-14k di -2.8 dB (det4=2.8)
  local nodes = {
    { plugin_type = 4, track_idx = 0, chain_pos = 0, status_flags = 1, rms_in_db = -22, rms_out_db = -16.5, gain_delta_db = 5.5, tone_low_db = 0, tone_mid_db = 0, tone_high_db = 3.2, harm_pct = 0, activity_pct = 80 },
    { plugin_type = 3, track_idx = 0, chain_pos = 1, status_flags = 1, rms_in_db = -16.5, rms_out_db = -16.5, gain_delta_db = 0, gr_comp_db = 0.1, gr_dyneq_db = 0.0, harm_pct = 0, activity_pct = 80 },
    { plugin_type = 7, track_idx = 1, chain_pos = 0, status_flags = 1, rms_in_db = -22, rms_out_db = -22, gain_delta_db = 0, det1 = 0, det2 = 0, det3 = 0, det4 = 2.8, gr_dyneq_db = 2.8, activity_pct = 80 },
  }
  local rep
  for _ = 1, 25 do rep = TE.step(st, 0.25, true, snap, nodes, nil) end
  local has_opp_tone, has_opp_gain = false, false
  for _, it in ipairs(rep.active_issues) do
    if it.kind == "opposition_tone" then has_opp_tone = true end
    if it.kind == "opposition_gain" then has_opp_gain = true end
  end
  check("Opposizione tonale senza NL intermedia rilevata", has_opp_tone)
  check("Opposizione gain (plugin +5.5 vs fader -5.5) rilevata", has_opp_gain)
  check("conflict_count >= 2", rep.conflict_count >= 2, rep.conflict_count)
end

-- 7) Stessa opposizione CON compressore terze parti attivo (host_gr_db = 4.0 dB) in mezzo -> PRE-ENFASI, NON conflitto!
do
  local st = TE.new_state()
  local snap = {
    tracks = {
      { idx = 0, name = "Voce 1", parent_idx = 1, main_send = true, fader_db = 0, peak_db = -12,
        fx = {
          { fx_idx = 0, name = "ZP Spoken Finish", enabled = true },
          { fx_idx = 1, name = "FabFilter Pro-C 2", enabled = true, host_gr_db = 4.0 },
        } },
      { idx = 1, name = "VO_BUS", parent_idx = -1, main_send = true, fader_db = 0, peak_db = -12,
        fx = {
          { fx_idx = 0, name = "ZP BrownSlope Dynamic Guard", enabled = true },
        } },
    },
    master_fx = {},
  }
  local nodes = {
    { plugin_type = 4, track_idx = 0, chain_pos = 0, status_flags = 1, rms_in_db = -20, rms_out_db = -20, tone_high_db = 3.0, activity_pct = 80 },
    { plugin_type = 7, track_idx = 1, chain_pos = 0, status_flags = 1, rms_in_db = -20, rms_out_db = -20, det4 = 2.6, gr_dyneq_db = 2.6, activity_pct = 80 },
  }
  local rep
  for _ = 1, 25 do rep = TE.step(st, 0.25, true, snap, nodes, nil) end
  local has_opp_tone = false
  for _, it in ipairs(rep.active_issues) do
    if it.kind == "opposition_tone" then has_opp_tone = true end
  end
  check("Con compressore 3rd-party attivo in mezzo: NON e' conflitto", not has_opp_tone)
  check("Con compressore 3rd-party attivo in mezzo: classificato come pre-enfasi", rep.preemph_count >= 1, rep.preemph_count)
end

-- 8) Attribuzione differenziale su EQ VST3 opaco interposto tra due Probe + pesatura energetica multi-traccia
do
  local st = TE.new_state()
  local snap = {
    tracks = {
      { idx = 0, name = "Voce Forte", parent_idx = -1, main_send = true, fader_db = 0, peak_db = -10,
        fx = {
          { fx_idx = 0, name = "ZP Voice-Music Probe", enabled = true },
          { fx_idx = 1, name = "FabFilter Pro-Q 3", enabled = true },
          { fx_idx = 2, name = "ZP Voice-Music Probe", enabled = true },
        } },
      { idx = 1, name = "Voce Bassa", parent_idx = -1, main_send = true, fader_db = -24, peak_db = -36,
        fx = {
          { fx_idx = 0, name = "ZP Spoken Finish", enabled = true },
        } },
    },
    master_fx = {
      { fx_idx = 0, name = "ZP BrownSlope Prism", enabled = true },
    },
  }
  local nodes = {
    -- Probe pre Pro-Q 3: piatta vs Brown, RMS -20
    { plugin_type = 9, track_idx = 0, chain_pos = 0, status_flags = 1, rms_in_db = -20, rms_out_db = -20, tone_low_db = 0, tone_mid_db = 0, tone_high_db = 0, det6 = 0, bright_db = 0, activity_pct = 85 },
    -- Probe post Pro-Q 3: +3.6 dB su 800-4k e +3.0 dB gain introdotti dal VST3 opaco!
    { plugin_type = 9, track_idx = 0, chain_pos = 2, status_flags = 1, rms_in_db = -17, rms_out_db = -17, tone_low_db = -1.0, tone_mid_db = -0.5, tone_high_db = 3.6, det6 = 0.5, bright_db = 0.9, activity_pct = 85 },
    -- Voce bassa (irrilevante energeticamente)
    { plugin_type = 4, track_idx = 1, chain_pos = 0, status_flags = 1, rms_in_db = -42, rms_out_db = -42, tone_high_db = 4.0, activity_pct = 20 },
    -- Prism sul Master vede l'eccesso su 800-4k
    { plugin_type = 11, track_idx = -1, chain_pos = 0, status_flags = 1, tone_low_db = -1.0, tone_mid_db = -0.5, tone_high_db = 3.6, det6 = 0.5, bright_db = 0.9, det3 = 1, det2 = 0 },
  }
  local rep
  for _ = 1, 25 do rep = TE.step(st, 0.25, true, snap, nodes, { ok = true, tone_on = 0 }) end
  check("Segmento esterno rilevato", #rep.ext_segments >= 1, #rep.ext_segments)
  check("Residuo differenziale gain ~ +3.0 dB su Pro-Q 3", #rep.ext_segments >= 1 and near(rep.ext_segments[1].resid_gain, 3.0, 0.1), #rep.ext_segments >= 1 and rep.ext_segments[1].resid_gain)
  check("Residuo differenziale zona3 ~ +3.6 dB su Pro-Q 3", #rep.ext_segments >= 1 and near(rep.ext_segments[1].resid_z[3], 3.6, 0.1), #rep.ext_segments >= 1 and rep.ext_segments[1].resid_z[3])
  local found_proq = false
  for _, it in ipairs(rep.active_issues) do
    if it.kind == "brown_zone" and it.detail_it:find("Pro-Q 3", 1, true) then found_proq = true end
  end
  check("Attribuzione zona 800-4k punta a FabFilter Pro-Q 3 (non alla traccia bassa)", found_proq)
end

-- 9) Solo/Mute nel grafo: traccia in mute esclusa, traccia in solo mantiene il suo bus padre
do
  local snap = {
    tracks = {
      { idx = 0, name = "Voce A", parent_idx = 2, main_send = true, mute = false, solo = 1, fader_db = 0, fx = {} },
      { idx = 1, name = "Voce B", parent_idx = 2, main_send = true, mute = false, solo = 0, fader_db = 0, fx = {} },
      { idx = 2, name = "VO_BUS", parent_idx = -1, main_send = true, mute = false, solo = 0, fader_db = 0, fx = {} },
      { idx = 3, name = "Musica", parent_idx = -1, main_send = true, mute = true, solo = 0, fader_db = 0, fx = {} },
    },
    master_fx = {},
  }
  local g = TE.build_graph(snap, {})
  check("Solo: Voce A attiva", g.tracks_by_idx[0].active == true)
  check("Solo: VO_BUS padre attivo", g.tracks_by_idx[2].active == true)
  check("Solo: Voce B esclusa", g.tracks_by_idx[1].active == false)
  check("Mute: Musica esclusa", g.tracks_by_idx[3].active == false)
end

-- 10) Scelta stilistica (toggle_ignore) + gmem summary [3600..3619]
do
  local st = TE.new_state()
  local snap = {
    tracks = { { idx = 0, name = "Voce", parent_idx = -1, main_send = true, fader_db = 0, peak_db = -12, fx = { { fx_idx = 0, name = "Magic", enabled = true } } } },
    master_fx = {},
  }
  local nodes = { { plugin_type = 3, track_idx = 0, chain_pos = 0, status_flags = 5, rms_out_db = -18, activity_pct = 80 } } -- bit 4 = DELTA
  local rep = TE.step(st, 0.25, true, snap, nodes, nil)
  check("Alert DELTA rilevato subito", #rep.active_issues == 1, #rep.active_issues)
  TE.toggle_ignore(st, rep.active_issues[1].key)
  local rep2 = TE.analyze(st)
  check("Dopo SCELTA VOLUTA active_issues == 0", #rep2.active_issues == 0, #rep2.active_issues)
  local summ = TE.build_gmem_summary(st, 100.5, 7)
  check("gmem[3600] magic 905360", summ[3600] == 905360)
  check("gmem[3603] ref_slope 4.5", near(summ[3603], 4.5, 0.001))
  check("gmem[3607] issue_count 0 dopo ignore", summ[3607] == 0)
end

-- 11) Verifica matematica calibrazione 4 bande Brown (-4.5 dB/oct) usata nella Voice-Music Probe
do
  local sr = 48000
  local c40 = math.exp(-2 * math.pi * 40 / sr)
  local c160 = math.exp(-2 * math.pi * 160 / sr)
  local c800 = math.exp(-2 * math.pi * 800 / sr)
  local c4k = math.exp(-2 * math.pi * 4000 / sr)
  local c14k = math.exp(-2 * math.pi * 14000 / sr)
  local function lp2(c, cw) return ((1 - c) * (1 - c)) / (1 + c * c - 2 * c * cw) end
  local function hp2(c, cw) return (2 * c * c * (1 - cw)) / (1 + c * c - 2 * c * cw) end
  local function band_powers(slope_db_oct)
    local alpha = slope_db_oct / (10 * math.log(2) / math.log(10))
    local fmin, fmax = 20, 18000
    local lstep = math.log(fmax / fmin) / 160
    local p = { 0, 0, 0, 0 }
    for fi = 0, 159 do
      local f = fmin * math.exp((fi + 0.5) * lstep)
      local df = f * lstep
      local cw = math.cos(2 * math.pi * f / sr)
      local psd = ((f / 1000) ^ (-alpha)) * df
      local ghp40 = hp2(c40, cw)
      local g1 = ghp40 * lp2(c160, cw)
      local g2 = ghp40 * hp2(c160, cw) * lp2(c800, cw)
      local g3 = ghp40 * hp2(c160, cw) * hp2(c800, cw) * lp2(c4k, cw)
      local g4 = ghp40 * hp2(c160, cw) * hp2(c800, cw) * hp2(c4k, cw) * lp2(c14k, cw)
      p[1] = p[1] + g1 * psd; p[2] = p[2] + g2 * psd; p[3] = p[3] + g3 * psd; p[4] = p[4] + g4 * psd
    end
    return p
  end
  local ref_p = band_powers(4.5)
  local pink_p = band_powers(3.0) -- Pink e' +1.5 dB/oct piu' brillante del Brown 4.5
  local z = {}
  local zm = 0
  for k = 1, 4 do
    z[k] = 10 * math.log(pink_p[k] / ref_p[k]) / math.log(10)
    zm = zm + z[k] * 0.25
  end
  for k = 1, 4 do z[k] = z[k] - zm end
  local x = { math.log(80/1000)/math.log(2), math.log(358/1000)/math.log(2), math.log(1789/1000)/math.log(2), math.log(7483/1000)/math.log(2) }
  local xm = 0.25 * (x[1] + x[2] + x[3] + x[4])
  local sxx, sxy = 0, 0
  for k = 1, 4 do sxx = sxx + (x[k]-xm)^2; sxy = sxy + (x[k]-xm)*z[k] end
  local tilt_pink = sxy / sxx
  check("Calibrazione 4 bande Probe: Pink (-3.0) risulta ~ +1.5 dB/o vs Brown (-4.5)", near(tilt_pink, 1.5, 0.25), tilt_pink)
end

-- 12) Profilo VOICE_ONLY: HPF voce su BrownSlope Prism (z1 = -4.5 dB, z2..z4 = 0) -> NESSUN falso allarme bassi o tilt
do
  local st = TE.new_state()
  local snap = {
    tracks = {
      { idx = 0, name = "Voce", parent_idx = -1, main_send = true, fader_db = 0, peak_db = -14,
        fx = { { fx_idx = 0, name = "ZP Voice-Music Probe", enabled = true } } },
    },
    master_fx = { { fx_idx = 0, name = "ZP BrownSlope Prism", enabled = true } },
  }
  local nodes = {
    { plugin_type = 9, track_idx = 0, chain_pos = 0, status_flags = 1, rms_out_db = -18, det4 = 80, activity_pct = 80, sub_excess_db = -9.0 },
    { plugin_type = 11, track_idx = -1, chain_pos = 0, status_flags = 1, tone_low_db = -4.5, tone_mid_db = 0.0, tone_high_db = 0.0, det6 = 0.0, bright_db = 0.75, det3 = 1, det2 = 1 },
  }
  local rep
  for _ = 1, 25 do rep = TE.step(st, 0.25, true, snap, nodes, { ok = true, tone_on = 0 }) end
  check("VOICE_ONLY rilevato", rep.program_mode == "VOICE_ONLY", rep.program_mode)
  check("VOICE_ONLY: HPF voce non falsa tilt (tilt_err ~ 0)", near(rep.tilt_err, 0.0, 0.05), rep.tilt_err)
  check("VOICE_ONLY: nessun falso allarme carenza 40-160 Hz", #rep.active_issues == 0, #rep.active_issues)
end

-- 13) Controllo Rumble <80 Hz sulla voce (solo eccesso)
do
  local st = TE.new_state()
  local snap = {
    tracks = { { idx = 0, name = "Voce", parent_idx = -1, main_send = true, fader_db = 0, peak_db = -14,
      fx = { { fx_idx = 0, name = "ZP Voice-Music Probe", enabled = true } } } },
    master_fx = {},
  }
  local nodes = {
    { plugin_type = 9, track_idx = 0, chain_pos = 0, status_flags = 1, rms_out_db = -18, det4 = 80, activity_pct = 80, sub_excess_db = 4.8, tone_low_db = 0, tone_mid_db = 0, tone_high_db = 0, det6 = 0, bright_db = 0 },
  }
  local rep
  for _ = 1, 25 do rep = TE.step(st, 0.25, true, snap, nodes, { ok = true, tone_on = 0 }) end
  local has_rumble = false
  for _, it in ipairs(rep.active_issues) do
    if it.kind == "voice_rumble" then has_rumble = true end
  end
  check("Rumble <80 Hz in eccesso (+4.8 dB) rilevato", has_rumble)
end

-- 14) FULL_MIX: mascheramento Voce/Musica + collisione 800-4k -> punta a ZP Harmonic Space Carver
do
  local st = TE.new_state()
  local snap = {
    tracks = {
      { idx = 0, name = "VO_BUS", parent_idx = -1, main_send = true, fader_db = 0, peak_db = -12,
        fx = { { fx_idx = 0, name = "ZP Voice-Music Probe", enabled = true } } },
      { idx = 1, name = "MUSIC_BUS", parent_idx = -1, main_send = true, fader_db = 0, peak_db = -15,
        fx = {
          { fx_idx = 0, name = "ZP Harmonic Space Carver", enabled = true },
          { fx_idx = 1, name = "ZP Voice-Music Probe", enabled = true },
        } },
    },
    master_fx = { { fx_idx = 0, name = "ZP BrownSlope Prism", enabled = true } },
  }
  local nodes = {
    { plugin_type = 9, track_idx = 0, chain_pos = 0, status_flags = 1, rms_out_db = -18.0, det4 = 85, activity_pct = 85, sub_excess_db = -8 },
    { plugin_type = 8, track_idx = 1, chain_pos = 0, status_flags = 1, rms_in_db = -21.5, rms_out_db = -21.5, det1 = 0.4, det2 = 0.2, det3 = 0.3, det4 = 0.1, det5 = 0.0, activity_pct = 80 },
    { plugin_type = 10, track_idx = 1, chain_pos = 1, status_flags = 1, rms_out_db = -21.5, tone_low_db = 2.6, tone_mid_db = 0.0, tone_high_db = 2.4, det6 = 0.0, bright_db = 0.0, activity_pct = 70 },
    { plugin_type = 11, track_idx = -1, chain_pos = 0, status_flags = 1, tone_low_db = 2.8, tone_mid_db = 0.0, tone_high_db = 1.0, det6 = 0.0, bright_db = 0.0, det3 = 1, det2 = 1 },
  }
  local rep
  for _ = 1, 25 do rep = TE.step(st, 0.25, true, snap, nodes, { ok = true, tone_on = 0 }) end
  check("FULL_MIX rilevato con Music Probe + HSC", rep.program_mode == "FULL_MIX", rep.program_mode)
  local has_vm_hsc, has_mid_hsc, has_low_hsc = false, false, false
  for _, it in ipairs(rep.active_issues) do
    if it.key == "masking:vm_carver" and it.track_idx == 1 and it.fx_idx == 0 then has_vm_hsc = true end
    if it.key == "masking:mid_carver" and it.track_idx == 1 and it.fx_idx == 0 then has_mid_hsc = true end
    if it.kind == "brown_zone" and it.track_idx == 1 and it.fx_idx == 0 then has_low_hsc = true end
  end
  check("Mascheramento V-M stretto punta a ZP Harmonic Space Carver", has_vm_hsc)
  check("Collisione formanti 800-4k punta a Carver Mid di ZP HSC", has_mid_hsc)
  check("Eccesso 40-160 al Master in FULL_MIX punta a Carver Low di ZP HSC", has_low_hsc)
end

-- 15) FULL_MIX con HSC VCA Ducker gia' molto carico (-7.5 dB) -> consiglia di abbassare la musica a monte
do
  local st = TE.new_state()
  local snap = {
    tracks = {
      { idx = 0, name = "VO_BUS", parent_idx = -1, main_send = true, fader_db = 0, peak_db = -12,
        fx = { { fx_idx = 0, name = "ZP Voice-Music Probe", enabled = true } } },
      { idx = 1, name = "MUSIC_BUS", parent_idx = -1, main_send = true, fader_db = 0, peak_db = -14,
        fx = { { fx_idx = 0, name = "ZP Harmonic Space Carver", enabled = true } } },
    },
    master_fx = {},
  }
  local nodes = {
    { plugin_type = 9, track_idx = 0, chain_pos = 0, status_flags = 1, rms_out_db = -18.0, det4 = 85, activity_pct = 85 },
    { plugin_type = 8, track_idx = 1, chain_pos = 0, status_flags = 1, rms_in_db = -14.0, rms_out_db = -21.5, det1 = 7.5, det2 = 3.0, det3 = 1.0, det4 = 0.5, activity_pct = 80 },
  }
  local rep
  for _ = 1, 25 do rep = TE.step(st, 0.25, true, snap, nodes, { ok = true, tone_on = 0 }) end
  local has_heavy = false
  for _, it in ipairs(rep.active_issues) do
    if it.key == "masking:vm_heavy_carver" then has_heavy = true end
  end
  check("Con HSC VCA Ducker gia' a -7.5 dB consiglia riduzione musica a monte", has_heavy)
end

-- 16) Immediate safety_alert se REAPER ha Ignore PDC attivo (pdc_mode == 2) con latenza FX > 0
do
  local st = TE.new_state()
  local snap = {
    tracks = {
      { idx = 0, name = "VO", parent_idx = -1, main_send = true, fader_db = 0, peak_db = -18,
        fx = {
          { fx_idx = 0, name = "ZP Harmonic Space Carver", enabled = true, pdc_samples = 960, pdc_mode = 2 },
          { fx_idx = 1, name = "ZP Magic Voice LAB", enabled = true, pdc_samples = 960, pdc_mode = 1 },
        } },
    },
    master_fx = {},
  }
  local rep = TE.step(st, 0.25, true, snap, {}, { ok = false })
  local hit_bad, hit_good = false, false
  for _, it in ipairs(rep.active_issues) do
    if it.key == "pdc_ignored:0:0" and it.kind == "safety_alert" and it.severity == 3 then hit_bad = true end
    if it.key == "pdc_ignored:0:1" then hit_good = true end
  end
  check("FX con pdc_mode=2 e pdc_samples>0 emette safety_alert immediato", hit_bad)
  check("FX con pdc_mode=1 non emette falso alert PDC ignorato", not hit_good)
end

-- 17) Immediate safety_alert su comb filtering rilevato da BrownSlope Prism (ptype=11, comb_ms/comb_est)
do
  local st = TE.new_state()
  local snap = {
    tracks = {},
    master_fx = { { fx_idx = 0, name = "ZP BrownSlope Prism", enabled = true } },
  }
  local nodes_bad = {
    { plugin_type = 11, track_idx = -1, chain_pos = 0, status_flags = 1, det3 = 1, comb_ms = 2.0, comb_est = 0.35 },
  }
  local rep_bad = TE.step(st, 0.25, true, snap, nodes_bad, { ok = false })
  local has_comb = false
  for _, it in ipairs(rep_bad.active_issues) do
    if it.key == "comb:-1:0" and it.kind == "safety_alert" and it.severity == 3 then has_comb = true end
  end
  check("Comb filtering forte rilevato da Prism emette safety_alert immediato", has_comb)

  local st2 = TE.new_state()
  local nodes_clean = {
    { plugin_type = 11, track_idx = -1, chain_pos = 0, status_flags = 1, det3 = 1, comb_ms = 0, comb_est = 0 },
  }
  local rep_clean = TE.step(st2, 0.25, true, snap, nodes_clean, { ok = false })
  local false_comb = false
  for _, it in ipairs(rep_clean.active_issues) do
    if it.key == "comb:-1:0" then false_comb = true end
  end
  check("Prism senza comb filtering non emette falsi alert", not false_comb)
end

if fails == 0 then
  print("TUTTI OK")
else
  print("FALLITI " .. fails .. " su " .. total)
  os.exit(1)
end
