-- @noindex
-- ZP_Telemetry_Engine.lua
-- Modulo puro (senza dipendenze gfx/reaper) del motore telemetrico ZP Suite:
--   • Metro fisso di riferimento: Brown -4.5 dB/oct (±10% = ±0.45 dB/oct, 4 zone ±1.5/±3.0 dB)
--     con precedenza alla scelta di Tone Guard su ZP Master Pro quando acceso.
--   • Grafo reale di routing (DAG: folder, main send, send, mute/solo, fader, FX ZP + terze parti).
--   • Integratore a finestra lenta gated su PLAY + segnale utile (media breve + media di giudizio).
--   • Solver consultivo a 3 classi: Derive dal Target, Opposizioni ("tiro alla fune") con filtro
--     di non-linearita' intermedia (pre-enfasi/recupero), Concentrazione dinamica e Alert sicurezza.
--   • Attribuzione differenziale per blocchi di plugin esterni opachi lungo lo stesso percorso.

local M = {}

M.FRAME = {
  BASE_BROWN_SLOPE = 4.5,   -- dB/oct (-4.5 dB/oct)
  SLOPE_TOL_PCT = 0.10,     -- ±10% (±0.45 dB/oct a 4.5)
  ZONE_GREEN_DB = 1.5,
  ZONE_YELLOW_DB = 3.0,
  ZONE_LABELS = { "40-160", "160-800", "800-4k", "4k-14k" },
  VOICE_ZONE_LABELS = { "85-250", "250-800", "800-4k", "4k-14k" },
  ZONE_FC = { 80, 358, 1789, 7483 },
  VOICE_ZONE_FC = { 146, 447, 1789, 7483 },
  LUFS_TARGET_DEFAULT = -16.0,
  LUFS_TOL_DEFAULT = 1.0,
  TP_MAX_DEFAULT = -1.0,
  SHORT_WIN_SEC = 5.0,
  JUDGE_WIN_SEC = 18.0,
  MIN_JUDGE_SEC = 5.0,
  NONLINEAR_GR_DB = 1.5,
  NONLINEAR_HARM_PCT = 10.0,
  OPP_GAIN_MIN_DB = 2.5,
  OPP_TONE_MIN_DB = 1.8,
  EXT_RESID_GAIN_DB = 2.0,
  EXT_RESID_ZONE_DB = 1.8,
  COMP_SHARE_WARN = 0.70,
  COMP_TOTAL_MIN_DB = 5.0,
  SUB_RUMBLE_WARN_DB = 3.0,
  VM_TIGHT_DB = 6.0,
  VM_MASK_MAX_DB = 12.0,
  MUSIC_MID_COLLISION_DB = 1.5,
  CARVER_ACTIVE_DB = 1.5,
  CARVER_HEAVY_DB = 6.0,
}

M.PLUGIN_NAMES = {
  [1] = "BUS Chain",
  [2] = "Unified Chain",
  [3] = "Magic Voice LAB",
  [4] = "Spoken Finish",
  [5] = "Stagekeeper",
  [6] = "Click & Attack",
  [7] = "BrownSlope Grd",
  [8] = "Space Carver",
  [9] = "Voice Probe",
  [10] = "Music Probe",
  [11] = "BrownSlope Prsm",
  [12] = "Loudness Meter",
  [13] = "Master Pro",
}

M.KIND_CODE = {
  ok = 0,
  brown_tilt = 1,
  brown_zone = 2,
  loudness = 3,
  true_peak = 3,
  opposition_tone = 4,
  opposition_gain = 5,
  comp_concentration = 6,
  safety_alert = 7,
  voice_rumble = 8,
  music_masking = 9,
}

local LN2 = math.log(2)
local ZONE_X = {}
local ZONE_XM = 0
local VZONE_X = {}
local VZONE_XM = 0
for k = 1, 4 do
  ZONE_X[k] = math.log(M.FRAME.ZONE_FC[k] / 1000.0) / LN2
  ZONE_XM = ZONE_XM + ZONE_X[k] * 0.25
  VZONE_X[k] = math.log(M.FRAME.VOICE_ZONE_FC[k] / 1000.0) / LN2
  VZONE_XM = VZONE_XM + VZONE_X[k] * 0.25
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function round1(v)
  return math.floor((v or 0) * 10 + 0.5) / 10
end

function M.plugin_name(pt)
  return M.PLUGIN_NAMES[math.floor((pt or 0) + 0.5)] or "ZP Plugin"
end

function M.vol_to_db(vol)
  if not vol or vol <= 1e-6 then return -120.0 end
  return 20.0 * math.log(vol) / math.log(10)
end

-- Codec ASCII 20 char compatibile con Track Directory Shared Bus v3 (gmem[3072..3583])
function M.sanitize_name(name)
  local s = tostring(name or "")
  local out = {}
  local n = 0
  for i = 1, #s do
    local b = s:byte(i)
    if b >= 32 and b <= 126 then
      n = n + 1
      out[n] = string.char(b)
      if n >= 20 then break end
    elseif b >= 128 then
      n = n + 1
      out[n] = " "
      if n >= 20 then break end
    end
  end
  return table.concat(out):gsub("^%s+", ""):gsub("%s+$", "")
end

function M.pack_name(name)
  local s = M.sanitize_name(name)
  local len = #s
  local packed = { 0, 0, 0, 0, 0 }
  for g = 0, 4 do
    local b1 = (g * 4 + 1 <= len) and s:byte(g * 4 + 1) or 0
    local b2 = (g * 4 + 2 <= len) and s:byte(g * 4 + 2) or 0
    local b3 = (g * 4 + 3 <= len) and s:byte(g * 4 + 3) or 0
    local b4 = (g * 4 + 4 <= len) and s:byte(g * 4 + 4) or 0
    packed[g + 1] = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
  end
  return len, packed
end

function M.unpack_name(len, packed)
  local n = math.max(0, math.min(20, math.floor((len or 0) + 0.5)))
  local out = {}
  for i = 0, n - 1 do
    local g = math.floor(i / 4)
    local j = i - g * 4
    local w = packed[g + 1] or 0
    local div = (j == 0) and 1 or (j == 1) and 256 or (j == 2) and 65536 or 16777216
    local ch = math.floor(w / div) % 256
    if ch < 32 or ch > 126 then ch = 32 end
    out[i + 1] = string.char(ch)
  end
  return table.concat(out)
end

-- Calcola il metro di riferimento attivo (Brown 4.5 ±10% fisso se Tone Guard Master spento,
-- oppure orientato dalla scelta su Master Pro se Tone Guard e' acceso).
function M.compute_reference(master_ref, loudness_node)
  local ref = {
    slope = M.FRAME.BASE_BROWN_SLOPE,
    slope_tol = M.FRAME.BASE_BROWN_SLOPE * M.FRAME.SLOPE_TOL_PCT,
    zone_offset = { 0, 0, 0, 0 },
    zone_green = M.FRAME.ZONE_GREEN_DB,
    zone_yellow = M.FRAME.ZONE_YELLOW_DB,
    mode = 0,
    mode_label_it = "Brown 4.5 ±10% (fisso)",
    mode_label_en = "Brown 4.5 ±10% (fixed)",
    lufs_target = M.FRAME.LUFS_TARGET_DEFAULT,
    lufs_tol = M.FRAME.LUFS_TOL_DEFAULT,
    tp_max = M.FRAME.TP_MAX_DEFAULT,
  }

  if master_ref and master_ref.ok then
    if (master_ref.tone_on or 0) >= 0.5 then
      local ts = tonumber(master_ref.tone_slope) or 0
      local dyn = (master_ref.tone_dyn_on or 0) >= 0.5
      if dyn then
        ref.mode = 2
        ref.slope = (ts >= 1.5) and clamp(ts, 0.5, 9.0) or clamp(M.FRAME.BASE_BROWN_SLOPE + ts, 0.5, 9.0)
        ref.mode_label_it = string.format("Master Tone DIN (%.1f dB/o)", ref.slope)
        ref.mode_label_en = string.format("Master Tone DYN (%.1f dB/o)", ref.slope)
      else
        ref.mode = 1
        ref.slope = clamp(M.FRAME.BASE_BROWN_SLOPE + ts, 0.5, 9.0)
        ref.mode_label_it = string.format("Master Tone (%.1f dB/o)", ref.slope)
        ref.mode_label_en = string.format("Master Tone (%.1f dB/o)", ref.slope)
      end
      ref.slope_tol = math.max(0.45, math.abs(ref.slope) * M.FRAME.SLOPE_TOL_PCT)
      ref.zone_offset = {
        clamp(tonumber(master_ref.tone_gain1) or 0, -6, 6),
        clamp(tonumber(master_ref.tone_gain2) or 0, -6, 6),
        clamp(tonumber(master_ref.tone_gain3) or 0, -6, 6),
        clamp(tonumber(master_ref.tone_gain4) or 0, -6, 6),
      }
    end
    if tonumber(master_ref.out_target_lufs) and master_ref.out_target_lufs > -60 and master_ref.out_target_lufs < 0 then
      ref.lufs_target = master_ref.out_target_lufs
    end
    if tonumber(master_ref.lim_ceiling) and master_ref.lim_ceiling > -20 and master_ref.lim_ceiling <= 0 then
      ref.tp_max = master_ref.lim_ceiling
    end
  end

  if loudness_node then
    local lt = tonumber(loudness_node.det3)
    local tol = tonumber(loudness_node.det4)
    local tp = tonumber(loudness_node.det5)
    if lt and lt > -60 and lt < 0 then ref.lufs_target = lt end
    if tol and tol >= 0.2 and tol <= 6.0 then ref.lufs_tol = tol end
    if tp and tp > -20 and tp <= 0 then ref.tp_max = tp end
  end

  -- Spostamento atteso rispetto al rumore Brown -4.5 dB/oct (per confrontare Prism/Probe)
  ref.expected_tilt_vs_brown = M.FRAME.BASE_BROWN_SLOPE - ref.slope
  ref.expected_zone_vs_brown = {}
  for k = 1, 4 do
    ref.expected_zone_vs_brown[k] = ref.expected_tilt_vs_brown * (ZONE_X[k] - ZONE_XM) + ref.zone_offset[k]
  end

  return ref
end

-- Estrae vettore 4 zone (o approssimazione 3->4 bande per nodi ZP timbrici) da un nodo v3
local function node_tone_zones(nd)
  local pt = math.floor((nd.plugin_type or 0) + 0.5)
  if pt == 9 or pt == 10 or pt == 11 then
    return {
      tonumber(nd.tone_low_db) or 0,
      tonumber(nd.tone_mid_db) or 0,
      tonumber(nd.tone_high_db) or 0,
      tonumber(nd.det6) or 0,
    }, true
  elseif pt == 13 then
    return {
      tonumber(nd.tone_low_db) or 0,
      tonumber(nd.tone_mid_db) or 0,
      tonumber(nd.tone_high_db) or 0,
      tonumber(nd.det6) or 0,
    }, false
  elseif pt == 7 then
    -- BrownSlope Dynamic Guard: det1..det4 sono riduzioni (segno negativo) sulle 4 bande
    return {
      -(tonumber(nd.det1) or 0),
      -(tonumber(nd.det2) or 0),
      -(tonumber(nd.det3) or 0),
      -(tonumber(nd.det4) or 0),
    }, false
  elseif pt == 3 or pt == 4 then
    -- Magic Voice LAB (3 bande DynBal in dB) / Spoken Finish (body/pres/air in dB proxy)
    local lo = tonumber(nd.tone_low_db) or 0
    local mi = tonumber(nd.tone_mid_db) or 0
    local hi = tonumber(nd.tone_high_db) or 0
    return { lo, 0.5 * (lo + mi), mi, hi }, false
  end
  return { 0, 0, 0, 0 }, false
end

local function make_stage_key(track_idx, fx_idx, kind, dest_idx)
  if kind == "fx" then
    return string.format("fx:%d:%d", track_idx, fx_idx)
  elseif kind == "fader" then
    return string.format("fader:%d", track_idx)
  else
    return string.format("send:%d:%d", track_idx, dest_idx or -1)
  end
end

-- Costruisce il grafo reale di routing (DAG) del progetto e collega i nodi Shared Bus v3 agli FX
function M.build_graph(project_snap, gmem_nodes)
  local tracks_by_idx = {}
  local track_list = {}
  local any_solo = false

  for _, tr in ipairs((project_snap and project_snap.tracks) or {}) do
    local t = {
      idx = tr.idx,
      name = (tr.name and tr.name ~= "") and tr.name or ("Tr " .. tostring(tr.idx + 1)),
      parent_idx = (tr.parent_idx ~= nil) and tr.parent_idx or -1,
      main_send = (tr.main_send == nil) and true or (tr.main_send and true or false),
      mute = tr.mute and true or false,
      solo = (tonumber(tr.solo) or 0) > 0,
      fader_db = tonumber(tr.fader_db) or 0.0,
      peak_db = tonumber(tr.peak_db) or -120.0,
      sends = tr.sends or {},
      fx = tr.fx or {},
      children = {},
      out_edges = {},
      in_edges = {},
      feeds_master = false,
      active = false,
      depth = 0,
    }
    if t.solo then any_solo = true end
    tracks_by_idx[t.idx] = t
    track_list[#track_list + 1] = t
  end

  table.sort(track_list, function(a, b) return a.idx < b.idx end)

  -- Mappa nodi v3 per (track_idx, fx_idx)
  local zp_map = {}
  local master_zp_nodes = {}
  local prism_nodes = {}
  local loudness_nodes = {}
  local probe_nodes = {}
  local voice_probes = {}
  local music_probes = {}
  local carver_nodes = {}

  for _, nd in ipairs(gmem_nodes or {}) do
    local ti = math.floor((nd.track_idx or -2) + 0.5)
    local fi = math.floor((nd.chain_pos or -1) + 0.5)
    local pt = math.floor((nd.plugin_type or 0) + 0.5)
    local k = string.format("%d:%d", ti, fi)
    zp_map[k] = nd
    if ti == -1 then master_zp_nodes[#master_zp_nodes + 1] = nd end
    if pt == 11 then prism_nodes[#prism_nodes + 1] = nd end
    if pt == 12 then loudness_nodes[#loudness_nodes + 1] = nd end
    if pt == 9 or pt == 10 then probe_nodes[#probe_nodes + 1] = nd end
    if pt == 9 then voice_probes[#voice_probes + 1] = nd end
    if pt == 10 then music_probes[#music_probes + 1] = nd end
    if pt == 8 then carver_nodes[#carver_nodes + 1] = nd end
  end

  -- Collega archi di routing (parent folder / master + sends)
  for _, t in ipairs(track_list) do
    if t.main_send then
      local dest = (t.parent_idx >= 0 and tracks_by_idx[t.parent_idx]) and t.parent_idx or -1
      t.out_edges[#t.out_edges + 1] = { dest_idx = dest, gain_db = t.fader_db, kind = "fader" }
      if dest >= 0 then
        local pt = tracks_by_idx[dest]
        pt.children[#pt.children + 1] = t.idx
        pt.in_edges[#pt.in_edges + 1] = t.idx
      end
    end
    for _, sd in ipairs(t.sends) do
      if not sd.mute and sd.dest_idx ~= nil and sd.dest_idx >= 0 and tracks_by_idx[sd.dest_idx] then
        local mode = tonumber(sd.mode) or 0 -- 0=post-fader, 1=pre-fx, 3=pre-fader
        local g = (tonumber(sd.send_db) or 0.0) + ((mode == 0) and t.fader_db or 0.0)
        t.out_edges[#t.out_edges + 1] = { dest_idx = sd.dest_idx, gain_db = g, kind = "send", mode = mode }
        tracks_by_idx[sd.dest_idx].in_edges[#tracks_by_idx[sd.dest_idx].in_edges + 1] = t.idx
      end
    end
  end

  -- Stato solo effettivo (in REAPER solo su una traccia abilita i suoi antenati/destinatari e i suoi figli)
  local solo_allowed = {}
  if any_solo then
    local function mark_down(ti, seen)
      if ti < 0 or seen[ti] then return end
      seen[ti] = true
      solo_allowed[ti] = true
      local tr = tracks_by_idx[ti]
      if not tr then return end
      for _, e in ipairs(tr.out_edges) do
        if e.dest_idx >= 0 then mark_down(e.dest_idx, seen) end
      end
    end
    local function mark_children(ti, seen)
      if ti < 0 or seen[ti] then return end
      seen[ti] = true
      solo_allowed[ti] = true
      local tr = tracks_by_idx[ti]
      if not tr then return end
      for _, ci in ipairs(tr.children) do mark_children(ci, seen) end
    end
    for _, t in ipairs(track_list) do
      if t.solo then
        mark_down(t.idx, {})
        mark_children(t.idx, {})
      end
    end
  end

  -- Determina raggiungibilita' al Master rispettando mute/solo
  local function can_reach_master(ti, visited)
    if ti == -1 then return true end
    if visited[ti] then return false end
    local tr = tracks_by_idx[ti]
    if not tr then return false end
    if tr.mute and not tr.solo then return false end
    if any_solo and not solo_allowed[ti] then return false end
    visited[ti] = true
    for _, e in ipairs(tr.out_edges) do
      if e.dest_idx == -1 or can_reach_master(e.dest_idx, visited) then
        return true
      end
    end
    return false
  end

  for _, t in ipairs(track_list) do
    t.feeds_master = can_reach_master(t.idx, {})
    t.active = t.feeds_master
    -- Calcola profondita' gerarchica per UI ad albero
    local d = 0
    local p = t.parent_idx
    local guard = 0
    while p >= 0 and tracks_by_idx[p] and guard < 16 do
      d = d + 1
      p = tracks_by_idx[p].parent_idx
      guard = guard + 1
    end
    t.depth = d
  end

  local function build_fx_stage(tr_idx, tr_name, fx_item)
    local fi = fx_item.fx_idx
    local nd = zp_map[string.format("%d:%d", tr_idx, fi)]
    local enabled = (fx_item.enabled == nil) and true or (fx_item.enabled and true or false)
    local offline = fx_item.offline and true or false
    local active_fx = enabled and not offline
    local st = {
      key = make_stage_key(tr_idx, fi, "fx"),
      kind = "fx",
      track_idx = tr_idx,
      track_name = tr_name,
      fx_idx = fi,
      name = fx_item.name or (nd and M.plugin_name(nd.plugin_type)) or ("FX " .. tostring(fi + 1)),
      enabled = active_fx,
      offline = offline,
      is_zp = (nd ~= nil),
      ptype = nd and math.floor((nd.plugin_type or 0) + 0.5) or 0,
      pdc_samples = math.max(0, math.floor((tonumber(fx_item.pdc_samples) or 0) + 0.5)),
      pdc_mode = (fx_item.pdc_mode ~= nil) and math.floor(tonumber(fx_item.pdc_mode) + 0.5) or -1,
      stage_role = nd and math.floor((nd.stage_role or 0) + 0.5) or (tr_idx == -1 and 4 or 0),
      status_flags = nd and math.floor((nd.status_flags or 0) + 0.5) or (active_fx and 1 or 2),
      gr_comp = nd and math.max(0, tonumber(nd.gr_comp_db) or 0) or 0,
      gr_dyneq = nd and math.max(0, tonumber(nd.gr_dyneq_db) or 0) or 0,
      gr_lim = nd and math.max(0, tonumber(nd.gr_lim_db) or 0) or 0,
      host_gr_db = math.max(0, tonumber(fx_item.host_gr_db) or 0),
      harm_pct = nd and math.max(0, tonumber(nd.harm_pct) or 0) or 0,
      rms_in_db = nd and (tonumber(nd.rms_in_db) or -120) or -120,
      rms_out_db = nd and (tonumber(nd.rms_out_db) or -120) or -120,
      peak_out_db = nd and (tonumber(nd.peak_out_db) or -120) or -120,
      gain_delta_db = nd and (tonumber(nd.gain_delta_db) or 0) or 0,
      activity_pct = nd and math.max(0, tonumber(nd.activity_pct) or 0) or 0,
      crest_db = nd and (tonumber(nd.crest_db) or -1) or -1,
      tilt = nd and (tonumber(nd.bright_db) or -99) or -99,
      raw_node = nd,
    }
    if nd then
      local zones, has_brown = node_tone_zones(nd)
      st.tone_zones = zones
      st.has_brown_zones = has_brown
      st.gr_total = st.gr_comp + st.gr_dyneq + st.gr_lim
      if (st.status_flags % 4) >= 2 then
        st.enabled = false
      end
    else
      st.tone_zones = { 0, 0, 0, 0 }
      st.has_brown_zones = false
      st.gr_total = active_fx and st.host_gr_db or 0
    end
    return st
  end

  local master_stages = {}
  local seen_mfx = {}
  for _, fx_item in ipairs((project_snap and project_snap.master_fx) or {}) do
    seen_mfx[fx_item.fx_idx] = true
    master_stages[#master_stages + 1] = build_fx_stage(-1, "MASTER", fx_item)
  end
  -- Se esistono nodi ZP su Master in gmem ma non in master_fx (es. snapshot parziale), aggiungili comunque
  for _, nd in ipairs(master_zp_nodes) do
    local fi = math.floor((nd.chain_pos or 0) + 0.5)
    if not seen_mfx[fi] then
      master_stages[#master_stages + 1] = build_fx_stage(-1, "MASTER", { fx_idx = fi, name = M.plugin_name(nd.plugin_type), enabled = true })
    end
  end
  table.sort(master_stages, function(a, b) return a.fx_idx < b.fx_idx end)

  -- Collega lista FX su ogni traccia (includendo eventuali nodi gmem su tracce senza elenco FX)
  local track_stages = {}
  for _, t in ipairs(track_list) do
    local list = {}
    local seen_fx = {}
    for _, fx_item in ipairs(t.fx) do
      seen_fx[fx_item.fx_idx] = true
      list[#list + 1] = build_fx_stage(t.idx, t.name, fx_item)
    end
    for _, nd in ipairs(gmem_nodes or {}) do
      local ti = math.floor((nd.track_idx or -2) + 0.5)
      local fi = math.floor((nd.chain_pos or 0) + 0.5)
      if ti == t.idx and not seen_fx[fi] then
        seen_fx[fi] = true
        list[#list + 1] = build_fx_stage(t.idx, t.name, { fx_idx = fi, name = M.plugin_name(nd.plugin_type), enabled = true })
      end
    end
    table.sort(list, function(a, b) return a.fx_idx < b.fx_idx end)
    track_stages[t.idx] = list
  end

  -- Identifica tracce sorgente (foglie attive: nessun ingresso attivo da altre tracce, oppure tracce attive con propri FX/segnale)
  local leaf_tracks = {}
  for _, t in ipairs(track_list) do
    if t.active then
      local has_active_in = false
      for _, src_i in ipairs(t.in_edges) do
        if tracks_by_idx[src_i] and tracks_by_idx[src_i].active then
          has_active_in = true
          break
        end
      end
      if not has_active_in then
        leaf_tracks[#leaf_tracks + 1] = t.idx
      end
    end
  end
  if #leaf_tracks == 0 then
    for _, t in ipairs(track_list) do
      if t.active then leaf_tracks[#leaf_tracks + 1] = t.idx end
    end
  end

  -- Enumera tutti i percorsi ordinati foglia -> Master
  local paths = {}
  local function dfs_path(ti, cur_stages, cur_tracks, visited)
    if #paths >= 64 then return end
    if ti == -1 then
      local full = {}
      for i = 1, #cur_stages do full[i] = cur_stages[i] end
      for i = 1, #master_stages do full[#full + 1] = master_stages[i] end
      local tr_copy = {}
      for i = 1, #cur_tracks do tr_copy[i] = cur_tracks[i] end
      paths[#paths + 1] = {
        leaf_track_idx = tr_copy[1],
        tracks = tr_copy,
        stages = full,
      }
      return
    end
    if visited[ti] then return end
    local tr = tracks_by_idx[ti]
    if not tr or not tr.active then return end
    visited[ti] = true
    cur_tracks[#cur_tracks + 1] = ti

    local base_len = #cur_stages
    for _, st in ipairs(track_stages[ti] or {}) do
      cur_stages[#cur_stages + 1] = st
    end

    for _, edge in ipairs(tr.out_edges) do
      if edge.dest_idx == -1 or (tracks_by_idx[edge.dest_idx] and tracks_by_idx[edge.dest_idx].active) then
        local gain_stage = {
          key = make_stage_key(ti, -1, edge.kind, edge.dest_idx),
          kind = edge.kind,
          track_idx = ti,
          track_name = tr.name,
          fx_idx = -1,
          dest_idx = edge.dest_idx,
          name = (edge.kind == "send") and ("Send -> " .. (tracks_by_idx[edge.dest_idx] and tracks_by_idx[edge.dest_idx].name or "Master")) or ("Fader " .. tr.name),
          enabled = true,
          is_zp = false,
          ptype = 0,
          gr_comp = 0, gr_dyneq = 0, gr_lim = 0, host_gr_db = 0, gr_total = 0,
          harm_pct = 0,
          gain_delta_db = edge.gain_db,
          rms_in_db = tr.peak_db - 10,
          rms_out_db = tr.peak_db - 10,
          peak_out_db = tr.peak_db,
          tone_zones = { 0, 0, 0, 0 },
          has_brown_zones = false,
          activity_pct = (tr.peak_db > -50) and 50 or 0,
          status_flags = 1,
          tilt = -99,
        }
        cur_stages[#cur_stages + 1] = gain_stage
        dfs_path(edge.dest_idx, cur_stages, cur_tracks, visited)
        cur_stages[#cur_stages] = nil
      end
    end

    while #cur_stages > base_len do cur_stages[#cur_stages] = nil end
    cur_tracks[#cur_tracks] = nil
    visited[ti] = nil
  end

  for _, li in ipairs(leaf_tracks) do
    dfs_path(li, {}, {}, {})
  end

  local has_full_branch = false
  for _, nd in ipairs(music_probes) do
    local ti = math.floor((nd.track_idx or -2) + 0.5)
    if ti == -1 or (tracks_by_idx[ti] and tracks_by_idx[ti].active) then has_full_branch = true; break end
  end
  if not has_full_branch then
    for _, nd in ipairs(carver_nodes) do
      local ti = math.floor((nd.track_idx or -2) + 0.5)
      if ti == -1 or (tracks_by_idx[ti] and tracks_by_idx[ti].active) then has_full_branch = true; break end
    end
  end

  return {
    tracks = track_list,
    tracks_by_idx = tracks_by_idx,
    track_stages = track_stages,
    master_stages = master_stages,
    paths = paths,
    prism_nodes = prism_nodes,
    loudness_nodes = loudness_nodes,
    probe_nodes = probe_nodes,
    voice_probes = voice_probes,
    music_probes = music_probes,
    carver_nodes = carver_nodes,
    program_mode = has_full_branch and "FULL_MIX" or "VOICE_ONLY",
    any_solo = any_solo,
  }
end

-- Stato persistente dell'integratore lento
function M.new_state()
  return {
    useful_sec = 0.0,
    short_sec = 0.0,
    vm_speech_sec = 0.0,
    vm_diff_avg = 0.0,
    holding = true,
    stage_avg = {},     -- key -> medie (short/judge)
    master_spec = { valid = false, source = "", is_voice_band = false, track_idx = -2, fx_idx = -1, z = { 0, 0, 0, 0 }, tilt = 0, verdict = 0 },
    master_loud = { valid = false, source = "", lufs_s = -100, lufs_i = -100, tp = -150, lra = 0 },
    voice_bus = { valid = false, rms = -120, speech = 0, sub_excess = -12, z = { 0, 0, 0, 0 }, track_idx = -2, fx_idx = -1 },
    music_bus = { valid = false, rms = -120, has_z = false, z = { 0, 0, 0, 0 }, track_idx = -2, fx_idx = -1 },
    carver = { valid = false, track_idx = -2, fx_idx = -1, track_name = "", vca_duck = 0, carver_mid = 0, carver_low = 0, carver_high = 0, glue_gr = 0, sc_act = 0 },
    ref = M.compute_reference(nil, nil),
    graph = nil,
    ignored = {},       -- key -> true (scelte stilistiche confermate dall'utente)
    last_report = nil,
  }
end

function M.reset_state(st)
  st.useful_sec = 0.0
  st.short_sec = 0.0
  st.vm_speech_sec = 0.0
  st.vm_diff_avg = 0.0
  st.stage_avg = {}
  st.master_spec = { valid = false, source = "", is_voice_band = false, track_idx = -2, fx_idx = -1, z = { 0, 0, 0, 0 }, tilt = 0, verdict = 0 }
  st.master_loud = { valid = false, source = "", lufs_s = -100, lufs_i = -100, tp = -150, lra = 0 }
  st.voice_bus = { valid = false, rms = -120, speech = 0, sub_excess = -12, z = { 0, 0, 0, 0 }, track_idx = -2, fx_idx = -1 }
  st.music_bus = { valid = false, rms = -120, has_z = false, z = { 0, 0, 0, 0 }, track_idx = -2, fx_idx = -1 }
  st.carver = { valid = false, track_idx = -2, fx_idx = -1, track_name = "", vca_duck = 0, carver_mid = 0, carver_low = 0, carver_high = 0, glue_gr = 0, sc_act = 0 }
  st.last_report = nil
end

function M.toggle_ignore(st, key)
  if not key then return end
  if st.ignored[key] then st.ignored[key] = nil else st.ignored[key] = true end
  st.last_report = M.analyze(st)
end

function M.clear_ignored(st)
  st.ignored = {}
  st.last_report = M.analyze(st)
end

local function ema(prev, val, alpha, init)
  if init or prev == nil then return val end
  return prev + alpha * (val - prev)
end

-- Sceglie i sensori di riferimento al Master (priorita': su Master > bus piu' a valle)
local function pick_master_sensors(graph, master_ref)
  local best_spec = nil
  local best_spec_prio = -1
  for _, nd in ipairs(graph.prism_nodes or {}) do
    if (tonumber(nd.det3) or 0) >= 0.5 then -- have_data == 1
      local ti = math.floor((nd.track_idx or -2) + 0.5)
      local prio = (ti == -1) and 100 or 60
      if prio > best_spec_prio then
        best_spec_prio = prio
        best_spec = {
          source = (ti == -1) and "BrownSlope Prism (Master)" or "BrownSlope Prism",
          is_voice_band = false,
          track_idx = ti,
          fx_idx = math.floor((nd.chain_pos or -1) + 0.5),
          z = { tonumber(nd.tone_low_db) or 0, tonumber(nd.tone_mid_db) or 0, tonumber(nd.tone_high_db) or 0, tonumber(nd.det6) or 0 },
          tilt = tonumber(nd.bright_db) or 0,
          verdict = math.floor((nd.det2 or 0) + 0.5),
        }
      end
    end
  end
  for _, nd in ipairs(graph.probe_nodes or {}) do
    local ti = math.floor((nd.track_idx or -2) + 0.5)
    local pt = math.floor((nd.plugin_type or 0) + 0.5)
    local rms = tonumber(nd.rms_out_db) or -120
    if rms > -65 then
      local prio = (ti == -1) and 85 or ((pt == 9) and 50 or 40)
      if prio > best_spec_prio then
        best_spec_prio = prio
        best_spec = {
          source = (pt == 9) and "Voice Probe (85-14k)" or "Full/Music Probe (40-14k)",
          is_voice_band = (pt == 9),
          track_idx = ti,
          fx_idx = math.floor((nd.chain_pos or -1) + 0.5),
          z = { tonumber(nd.tone_low_db) or 0, tonumber(nd.tone_mid_db) or 0, tonumber(nd.tone_high_db) or 0, tonumber(nd.det6) or 0 },
          tilt = tonumber(nd.bright_db) or 0,
          verdict = 1,
        }
      end
    end
  end

  local best_loud = nil
  local best_loud_node = nil
  local best_loud_prio = -1
  for _, nd in ipairs(graph.loudness_nodes or {}) do
    local ti = math.floor((nd.track_idx or -2) + 0.5)
    local prio = (ti == -1) and 100 or 60
    if prio > best_loud_prio then
      best_loud_prio = prio
      best_loud_node = nd
      best_loud = {
        source = "ZP Loudness Meter",
        lufs_s = tonumber(nd.rms_in_db) or -100,
        lufs_i = tonumber(nd.rms_out_db) or -100,
        tp = tonumber(nd.peak_out_db) or -150,
        lra = tonumber(nd.det2) or 0,
      }
    end
  end
  if not best_loud and master_ref and master_ref.ok then
    best_loud = {
      source = "ZP Master Pro",
      lufs_s = tonumber(master_ref.ui_lufs_s) or -100,
      lufs_i = tonumber(master_ref.ui_lufs_i) or -100,
      tp = tonumber(master_ref.ui_tp_db) or -150,
      lra = 0,
    }
  end

  return best_spec, best_loud, best_loud_node
end

-- Un passo di campionamento del Telemetry Engine (tipicamente dt = 0.25 s)
function M.step(st, dt, playing, project_snap, gmem_nodes, master_ref)
  dt = math.max(0.01, math.min(2.0, tonumber(dt) or 0.25))
  local graph = M.build_graph(project_snap, gmem_nodes)
  st.graph = graph

  local spec_now, loud_now, loud_node = pick_master_sensors(graph, master_ref)
  st.ref = M.compute_reference(master_ref, loud_node)

  -- Verifica presenza segnale utile (gated su PLAY + energia sopra soglia)
  local has_signal = false
  if playing then
    if loud_now and ((loud_now.lufs_s or -100) > -52 or (loud_now.lufs_i or -100) > -52) then
      has_signal = true
    end
    if not has_signal then
      for _, nd in ipairs(gmem_nodes or {}) do
        if (tonumber(nd.rms_out_db) or -120) > -48 or (tonumber(nd.activity_pct) or 0) > 15 then
          has_signal = true
          break
        end
      end
    end
    if not has_signal then
      for _, tr in ipairs(graph.tracks) do
        if tr.active and (tr.peak_db or -120) > -45 then
          has_signal = true
          break
        end
      end
    end
  end

  if not has_signal then
    st.holding = true
    st.last_report = M.analyze(st)
    return st.last_report
  end

  st.holding = false
  local first_sample = (st.useful_sec <= 0.0001)
  st.useful_sec = st.useful_sec + dt
  st.short_sec = math.min(M.FRAME.SHORT_WIN_SEC, st.short_sec + dt)

  local a_short = 1.0 - math.exp(-dt / M.FRAME.SHORT_WIN_SEC)
  local a_judge = (st.useful_sec < M.FRAME.JUDGE_WIN_SEC)
    and math.min(1.0, dt / math.max(dt, st.useful_sec))
    or (1.0 - math.exp(-dt / M.FRAME.JUDGE_WIN_SEC))

  -- Aggiorna medie per tutti gli stadi incontrati nei percorsi attivi
  local updated = {}
  for _, path in ipairs(graph.paths) do
    for _, sg in ipairs(path.stages) do
      if not updated[sg.key] then
        updated[sg.key] = true
        local rec = st.stage_avg[sg.key]
        local is_new = (rec == nil)
        if is_new then
          rec = {
            samples = 0,
            rms_in = sg.rms_in_db,
            rms_out = sg.rms_out_db,
            gain_delta = sg.gain_delta_db,
            gr_comp = sg.gr_comp,
            gr_dyneq = sg.gr_dyneq,
            gr_lim = sg.gr_lim,
            gr_total = sg.gr_total,
            harm = sg.harm_pct,
            z = { sg.tone_zones[1], sg.tone_zones[2], sg.tone_zones[3], sg.tone_zones[4] },
            tilt = sg.tilt,
            short_gr = sg.gr_total,
          }
          st.stage_avg[sg.key] = rec
        else
          rec.rms_in = ema(rec.rms_in, sg.rms_in_db, a_judge, false)
          rec.rms_out = ema(rec.rms_out, sg.rms_out_db, a_judge, false)
          rec.gain_delta = ema(rec.gain_delta, sg.gain_delta_db, a_judge, false)
          rec.gr_comp = ema(rec.gr_comp, sg.gr_comp, a_judge, false)
          rec.gr_dyneq = ema(rec.gr_dyneq, sg.gr_dyneq, a_judge, false)
          rec.gr_lim = ema(rec.gr_lim, sg.gr_lim, a_judge, false)
          rec.gr_total = ema(rec.gr_total, sg.gr_total, a_judge, false)
          rec.harm = ema(rec.harm, sg.harm_pct, a_judge, false)
          for k = 1, 4 do
            rec.z[k] = ema(rec.z[k], sg.tone_zones[k], a_judge, false)
          end
          if sg.tilt > -90 then
            rec.tilt = (rec.tilt <= -90) and sg.tilt or ema(rec.tilt, sg.tilt, a_judge, false)
          end
          rec.short_gr = ema(rec.short_gr, sg.gr_total, a_short, false)
        end
        rec.samples = rec.samples + 1
      end
    end
  end

  if spec_now then
    local ms = st.master_spec
    local init = first_sample or not ms.valid
    ms.valid = true
    ms.source = spec_now.source
    ms.is_voice_band = spec_now.is_voice_band and true or false
    ms.track_idx = spec_now.track_idx
    ms.fx_idx = spec_now.fx_idx
    ms.verdict = spec_now.verdict
    ms.tilt = ema(ms.tilt, spec_now.tilt, a_judge, init)
    for k = 1, 4 do
      ms.z[k] = ema(ms.z[k], spec_now.z[k], a_judge, init)
    end
  end

  if loud_now then
    local ml = st.master_loud
    local init = first_sample or not ml.valid
    ml.valid = true
    ml.source = loud_now.source
    if (loud_now.lufs_s or -100) > -90 then ml.lufs_s = ema(ml.lufs_s, loud_now.lufs_s, a_judge, init) end
    if (loud_now.lufs_i or -100) > -90 then ml.lufs_i = loud_now.lufs_i end
    if (loud_now.tp or -150) > -140 then ml.tp = init and loud_now.tp or math.max(ml.tp, loud_now.tp) end
    ml.lra = loud_now.lra or 0
  end

  -- Integra ramo Voce, ramo Musica/FX e ZP Harmonic Space Carver (per rumble <80 Hz e mascheramento V-M durante parlato)
  local vp_now = nil
  for _, nd in ipairs(graph.voice_probes or {}) do
    local ti = math.floor((nd.track_idx or -2) + 0.5)
    if ti == -1 or (graph.tracks_by_idx[ti] and graph.tracks_by_idx[ti].active) then
      if not vp_now or (tonumber(nd.rms_out_db) or -120) > (tonumber(vp_now.rms_out_db) or -120) then vp_now = nd end
    end
  end
  if vp_now then
    local vb = st.voice_bus
    local init = not vb.valid
    vb.valid = true
    vb.track_idx = math.floor((vp_now.track_idx or -2) + 0.5)
    vb.fx_idx = math.floor((vp_now.chain_pos or -1) + 0.5)
    vb.rms = ema(vb.rms, tonumber(vp_now.rms_out_db) or -120, a_judge, init)
    vb.speech = ema(vb.speech, tonumber(vp_now.det4) or tonumber(vp_now.activity_pct) or 0, a_judge, init)
    local sub_ex = tonumber(vp_now.sub_excess_db)
    if sub_ex ~= nil then vb.sub_excess = ema(vb.sub_excess, sub_ex, a_judge, init) end
    vb.z[1] = ema(vb.z[1], tonumber(vp_now.tone_low_db) or 0, a_judge, init)
    vb.z[2] = ema(vb.z[2], tonumber(vp_now.tone_mid_db) or 0, a_judge, init)
    vb.z[3] = ema(vb.z[3], tonumber(vp_now.tone_high_db) or 0, a_judge, init)
    vb.z[4] = ema(vb.z[4], tonumber(vp_now.det6) or 0, a_judge, init)
  end

  local cv_now = nil
  for _, nd in ipairs(graph.carver_nodes or {}) do
    local ti = math.floor((nd.track_idx or -2) + 0.5)
    if ti == -1 or (graph.tracks_by_idx[ti] and graph.tracks_by_idx[ti].active) then
      cv_now = nd; break
    end
  end
  if cv_now then
    local cv = st.carver
    local init = not cv.valid
    local ti = math.floor((cv_now.track_idx or -2) + 0.5)
    cv.valid = true
    cv.track_idx = ti
    cv.fx_idx = math.floor((cv_now.chain_pos or -1) + 0.5)
    cv.track_name = (graph.tracks_by_idx[ti] and graph.tracks_by_idx[ti].name) or ("Tr " .. tostring(ti + 1))
    cv.vca_duck = ema(cv.vca_duck, math.max(0, tonumber(cv_now.det1) or tonumber(cv_now.gr_comp_db) or 0), a_judge, init)
    cv.carver_mid = ema(cv.carver_mid, math.max(0, tonumber(cv_now.det2) or 0), a_judge, init)
    cv.carver_low = ema(cv.carver_low, math.max(0, tonumber(cv_now.det3) or 0), a_judge, init)
    cv.carver_high = ema(cv.carver_high, math.max(0, tonumber(cv_now.det4) or 0), a_judge, init)
    cv.glue_gr = ema(cv.glue_gr, math.max(0, tonumber(cv_now.det5) or tonumber(cv_now.gr_lim_db) or 0), a_judge, init)
    cv.sc_act = ema(cv.sc_act, math.max(0, tonumber(cv_now.activity_pct) or 0), a_judge, init)
  end

  local mp_now = nil
  for _, nd in ipairs(graph.music_probes or {}) do
    local ti = math.floor((nd.track_idx or -2) + 0.5)
    if ti == -1 or (graph.tracks_by_idx[ti] and graph.tracks_by_idx[ti].active) then
      if not mp_now or (tonumber(nd.rms_out_db) or -120) > (tonumber(mp_now.rms_out_db) or -120) then mp_now = nd end
    end
  end
  if mp_now then
    local mb = st.music_bus
    local init = not mb.valid
    mb.valid = true
    mb.has_z = true
    mb.track_idx = math.floor((mp_now.track_idx or -2) + 0.5)
    mb.fx_idx = math.floor((mp_now.chain_pos or -1) + 0.5)
    mb.rms = ema(mb.rms, tonumber(mp_now.rms_out_db) or -120, a_judge, init)
    mb.z[1] = ema(mb.z[1], tonumber(mp_now.tone_low_db) or 0, a_judge, init)
    mb.z[2] = ema(mb.z[2], tonumber(mp_now.tone_mid_db) or 0, a_judge, init)
    mb.z[3] = ema(mb.z[3], tonumber(mp_now.tone_high_db) or 0, a_judge, init)
    mb.z[4] = ema(mb.z[4], tonumber(mp_now.det6) or 0, a_judge, init)
  elseif cv_now then
    local mb = st.music_bus
    local init = not mb.valid
    mb.valid = true
    mb.has_z = false
    mb.track_idx = math.floor((cv_now.track_idx or -2) + 0.5)
    mb.fx_idx = math.floor((cv_now.chain_pos or -1) + 0.5)
    mb.rms = ema(mb.rms, tonumber(cv_now.rms_out_db) or -120, a_judge, init)
  end

  -- Rapporto V-M integrato SOLO quando la voce sta parlando sopra la musica (mai su intro/stacchi solo musica)
  local v_rms_inst = vp_now and (tonumber(vp_now.rms_out_db) or -120) or -120
  local v_sp_inst = vp_now and (tonumber(vp_now.det4) or tonumber(vp_now.activity_pct) or 0) or (cv_now and (tonumber(cv_now.activity_pct) or 0) or 0)
  local m_rms_inst = mp_now and (tonumber(mp_now.rms_out_db) or -120) or (cv_now and (tonumber(cv_now.rms_out_db) or -120) or -120)
  if v_sp_inst >= 25 and v_rms_inst > -48 and m_rms_inst > -52 then
    local first_vm = (st.vm_speech_sec <= 0.0001)
    st.vm_speech_sec = st.vm_speech_sec + dt
    local a_vm = (st.vm_speech_sec < M.FRAME.JUDGE_WIN_SEC)
      and math.min(1.0, dt / math.max(dt, st.vm_speech_sec))
      or (1.0 - math.exp(-dt / M.FRAME.JUDGE_WIN_SEC))
    st.vm_diff_avg = ema(st.vm_diff_avg, v_rms_inst - m_rms_inst, a_vm, first_vm)
  end

  st.last_report = M.analyze(st)
  return st.last_report
end

-- Calcola pesi energetici dei percorsi attivi (w_i = P_i / sum P_j)
local function compute_path_weights(graph, stage_avg)
  local weights = {}
  local psum = 0.0
  for pi, path in ipairs(graph.paths) do
    local best_rms = -90.0
    for _, sg in ipairs(path.stages) do
      if sg.track_idx == path.leaf_track_idx then
        local av = stage_avg[sg.key]
        local r = av and av.rms_out or sg.rms_out_db
        if r and r > best_rms and r > -100 then best_rms = r end
      end
    end
    local tr = graph.tracks_by_idx[path.leaf_track_idx]
    if best_rms <= -89 and tr and (tr.peak_db or -120) > -100 then
      best_rms = tr.peak_db - 10.0
    end
    local lin = (best_rms > -85) and (10.0 ^ (best_rms / 10.0)) or 1e-9
    weights[pi] = lin
    psum = psum + lin
  end
  for pi = 1, #weights do
    weights[pi] = (psum > 0) and (weights[pi] / psum) or (1.0 / math.max(1, #weights))
  end
  return weights
end

-- Verifica se uno stadio intermedio e' attivamente non-lineare (ragione valida per pre-enfasi/recupero)
local function stage_is_active_nonlinear(sg, avg)
  if not sg.enabled then return false, nil end
  if sg.kind ~= "fx" then return false, nil end
  local gr = avg and avg.gr_total or sg.gr_total or 0
  local harm = avg and avg.harm or sg.harm_pct or 0
  if gr >= M.FRAME.NONLINEAR_GR_DB then
    return true, string.format("%s (GR %.1f dB)", sg.name, gr)
  end
  if harm >= M.FRAME.NONLINEAR_HARM_PCT then
    return true, string.format("%s (Sat %.0f%%)", sg.name, harm)
  end
  return false, nil
end

-- Solver diagnostico completo: restituisce report strutturato per UI e per gmem[3600..3619]
function M.analyze(st)
  local graph = st.graph or { tracks = {}, tracks_by_idx = {}, paths = {}, master_stages = {} }
  local ref = st.ref
  local avg_map = st.stage_avg or {}
  local weights = compute_path_weights(graph, avg_map)

  local issues = {}
  local pre_emphasis = {}
  local ext_segments = {}
  local seen_keys = {}

  local function add_issue(item)
    if seen_keys[item.key] then return end
    seen_keys[item.key] = true
    item.ignored = st.ignored[item.key] and true or false
    issues[#issues + 1] = item
  end

  local function add_preemph(item)
    if seen_keys["pe:" .. item.key] then return end
    seen_keys["pe:" .. item.key] = true
    pre_emphasis[#pre_emphasis + 1] = item
  end

  -- 1. Alert sicurezza a monte (DELTA / SOLO / CHECK / CLAMP) — immediati, non aspettano MIN_JUDGE_SEC
  for _, path in ipairs(graph.paths) do
    for _, sg in ipairs(path.stages) do
      if sg.kind == "fx" and sg.is_zp and sg.enabled then
        local fl = sg.status_flags or 0
        local is_delta = (fl % 8) >= 4
        local is_solo = (fl % 16) >= 8
        local is_check = (fl % 32) >= 16
        local is_clamp = (fl % 64) >= 32
        if is_delta or is_solo or is_check then
          local tag = is_check and "CHECK" or (is_delta and "DELTA" or "SOLO")
          add_issue({
            key = string.format("safety:%d:%d:%s", sg.track_idx, sg.fx_idx, tag),
            kind = "safety_alert",
            severity = 3,
            track_idx = sg.track_idx,
            fx_idx = sg.fx_idx,
            value = 1,
            title_it = string.format("Alert %s attivo su %s · %s", tag, sg.track_name, sg.name),
            title_en = string.format("%s alert active on %s · %s", tag, sg.track_name, sg.name),
            detail_it = "Modalita' di ascolto/controllo lasciata attiva a monte del Master.",
            detail_en = "Audition/check mode left enabled upstream of Master.",
            action_hint = { track_idx = sg.track_idx, fx_idx = sg.fx_idx, domain = "safety", suggested_delta_db = 0 },
          })
        elseif is_clamp then
          add_issue({
            key = string.format("clamp:%d:%d", sg.track_idx, sg.fx_idx),
            kind = "safety_alert",
            severity = 2,
            track_idx = sg.track_idx,
            fx_idx = sg.fx_idx,
            value = 1,
            title_it = string.format("Limite uscita raggiunto su %s · %s", sg.track_name, sg.name),
            title_en = string.format("Output limit hit on %s · %s", sg.track_name, sg.name),
            detail_it = "Lo stadio sta saturando o toccando il fondo corsa di uscita.",
            detail_en = "Stage is clipping or hitting its output trim limit.",
            action_hint = { track_idx = sg.track_idx, fx_idx = sg.fx_idx, domain = "gain", suggested_delta_db = -2.0 },
          })
        end
      end
    end
  end

  -- 1b. Controllo immediato PDC ignorato (chain_pdc_mode == 2 con latenza FX > 0) su tracce, bus e Master
  local function check_pdc_ignored(stages)
    for _, sg in ipairs(stages or {}) do
      if sg.kind == "fx" and sg.enabled and sg.pdc_mode == 2 and (sg.pdc_samples or 0) > 0 then
        local ti = sg.track_idx or -1
        local where = (ti < 0) and "MASTER" or sg.track_name
        add_issue({
          key = string.format("pdc_ignored:%d:%d", ti, sg.fx_idx or 0),
          kind = "safety_alert",
          severity = 3,
          track_idx = ti,
          fx_idx = sg.fx_idx,
          value = sg.pdc_samples,
          title_it = string.format("PDC ignorato su %s · %s (%d camp.)", where, sg.name, sg.pdc_samples),
          title_en = string.format("PDC ignored on %s · %s (%d spl)", where, sg.name, sg.pdc_samples),
          detail_it = "REAPER ha 'Ignore PDC' attivo con un FX a latenza non nulla: rischio comb filtering o fuori-fase su mandate e bus.",
          detail_en = "REAPER has 'Ignore PDC' enabled with non-zero FX latency: risk of comb filtering or phase mismatch.",
          action_hint = { track_idx = ti, fx_idx = sg.fx_idx, domain = "phase", suggested_delta_db = 0 },
        })
      end
    end
  end
  for _, path in ipairs(graph.paths) do
    check_pdc_ignored(path.stages)
  end
  check_pdc_ignored(graph.master_stages)

  -- 1c. Controllo immediato comb filtering da BrownSlope Prism (ptype=11, slot +30/+31)
  for _, nd in ipairs(graph.prism_nodes or {}) do
    if (tonumber(nd.det3) or 0) >= 0.5 then
      local cms = tonumber(nd.comb_ms) or tonumber(nd.sub_excess_db) or 0
      local cest = tonumber(nd.comb_est) or tonumber(nd.voice_band_flag) or 0
      if cms > 0.1 and math.abs(cest) >= 0.12 then
        local ti = math.floor((nd.track_idx or -1) + 0.5)
        local fi = math.floor((nd.chain_pos or 0) + 0.5)
        local pct = math.floor(math.abs(cest) * 100 + 0.5)
        local sev = (math.abs(cest) >= 0.22) and 3 or 2
        local where = (ti < 0) and "MASTER" or (graph.tracks_by_idx and graph.tracks_by_idx[ti] and graph.tracks_by_idx[ti].name or ("Tr " .. tostring(ti + 1)))
        add_issue({
          key = string.format("comb:%d:%d", ti, fi),
          kind = "safety_alert",
          severity = sev,
          track_idx = ti,
          fx_idx = fi,
          value = cms,
          title_it = string.format("Comb filtering su %s (%.2f ms, ~%d%%)", where, cms, pct),
          title_en = string.format("Comb filtering on %s (%.2f ms, ~%d%%)", where, cms, pct),
          detail_it = "BrownSlope Prism ha rilevato una cancellazione periodica di fase: verifica ritardi, dry/wet e routing paralleli.",
          detail_en = "BrownSlope Prism detected periodic phase cancellation: check latency compensation, dry/wet mix and parallel routing.",
          action_hint = { track_idx = ti, fx_idx = fi, domain = "phase", suggested_delta_db = 0 },
        })
      end
    end
  end

  -- 2. Scostamenti medi dal riferimento Master (Brown 4.5 ±10% o Master Tone)
  --    In modalita' VOICE_ONLY (senza Musica/FX), la mancanza di energia sotto 80 Hz su un sensore full-band
  --    (BrownSlope Prism) non e' un errore: viene valutata la pendenza espressiva sulle zone 2..4 (160-14k)
  --    o direttamente sulla Voice Probe (85-14k), controllando <80 Hz solo per eccessi di rumble.
  local program_mode = graph.program_mode or "VOICE_ONLY"
  local z_err = { 0, 0, 0, 0 }
  local tilt_err = 0.0
  local lufs_err = 0.0
  local ready = (st.useful_sec >= M.FRAME.MIN_JUDGE_SEC)

  if st.master_spec.valid then
    local use_vzone = st.master_spec.is_voice_band
    for k = 1, 4 do
      local exp_z = use_vzone
        and (ref.expected_tilt_vs_brown * (VZONE_X[k] - VZONE_XM) + ref.zone_offset[k])
        or ref.expected_zone_vs_brown[k]
      z_err[k] = st.master_spec.z[k] - exp_z
    end
    if program_mode == "VOICE_ONLY" and not use_vzone and z_err[1] < -1.0 then
      -- Voce filtrata con HPF su sensore full-band: calcola tilt residuo sulle zone 2..4 (160-14k)
      local xm3 = (ZONE_X[2] + ZONE_X[3] + ZONE_X[4]) / 3.0
      local zm3 = (z_err[2] + z_err[3] + z_err[4]) / 3.0
      local sxx3, sxy3 = 0.0, 0.0
      for k = 2, 4 do
        local dx = ZONE_X[k] - xm3
        sxx3 = sxx3 + dx * dx
        sxy3 = sxy3 + dx * (z_err[k] - zm3)
      end
      tilt_err = (sxx3 > 0.001) and (sxy3 / sxx3) or (st.master_spec.tilt - ref.expected_tilt_vs_brown)
    else
      tilt_err = st.master_spec.tilt - ref.expected_tilt_vs_brown
    end
  end
  if st.master_loud.valid then
    local lmeas = (st.master_loud.lufs_i > -80) and st.master_loud.lufs_i or st.master_loud.lufs_s
    if lmeas > -80 then
      lufs_err = lmeas - ref.lufs_target
    end
  end

  -- 3. Analisi differenziale dei segmenti con FX esterni opachi lungo ogni percorso
  for pi, path in ipairs(graph.paths) do
    local w = weights[pi] or 0
    if w >= 0.15 then
      local meas_idx = {}
      for i, sg in ipairs(path.stages) do
        local av = avg_map[sg.key]
        local has_rms = (sg.kind == "fx" and sg.is_zp and ((av and av.rms_out or sg.rms_out_db) > -85))
        if has_rms then
          meas_idx[#meas_idx + 1] = i
        end
      end
      for m = 1, #meas_idx - 1 do
        local i1 = meas_idx[m]
        local i2 = meas_idx[m + 1]
        local s1 = path.stages[i1]
        local s2 = path.stages[i2]
        local ext_list = {}
        local known_gain = 0.0
        local known_z = { 0, 0, 0, 0 }
        for j = i1 + 1, i2 - 1 do
          local sm = path.stages[j]
          local am = avg_map[sm.key]
          if sm.kind == "fader" or sm.kind == "send" then
            known_gain = known_gain + (sm.gain_delta_db or 0)
          elseif sm.kind == "fx" and sm.enabled then
            if sm.is_zp then
              known_gain = known_gain + (am and am.gain_delta or sm.gain_delta_db or 0)
              for k = 1, 4 do known_z[k] = known_z[k] + (am and am.z[k] or sm.tone_zones[k] or 0) end
            else
              ext_list[#ext_list + 1] = sm
            end
          end
        end
        if #ext_list > 0 then
          local a1 = avg_map[s1.key]
          local a2 = avg_map[s2.key]
          local r1 = a1 and a1.rms_out or s1.rms_out_db
          local r2 = a2 and a2.rms_in or s2.rms_in_db
          if r2 <= -90 then r2 = a2 and a2.rms_out or s2.rms_out_db end
          local resid_gain = (r2 - r1) - known_gain
          local resid_z = { 0, 0, 0, 0 }
          local has_z_diff = s1.has_brown_zones and s2.has_brown_zones
          if has_z_diff then
            for k = 1, 4 do
              local z1 = a1 and a1.z[k] or s1.tone_zones[k]
              local z2 = a2 and a2.z[k] or s2.tone_zones[k]
              resid_z[k] = (z2 - z1) - known_z[k]
            end
          end
          local names = {}
          for _, ex in ipairs(ext_list) do names[#names + 1] = ex.name end
          ext_segments[#ext_segments + 1] = {
            path_idx = pi,
            weight = w,
            fx_list = ext_list,
            label = (#ext_list == 1) and (ext_list[1].track_name .. " · " .. ext_list[1].name)
                    or string.format("%d FX esterni (%s)", #ext_list, table.concat(names, ", ")),
            track_idx = ext_list[1].track_idx,
            fx_idx = ext_list[1].fx_idx,
            resid_gain = resid_gain,
            resid_z = resid_z,
            has_z_diff = has_z_diff,
          }
        end
      end
    end
  end

  -- Helper: trova il maggior contributore a monte nella stessa direzione di segno (val_err)
  local function find_top_contributor(domain, zone_k, err_sign)
    local best = nil
    local best_score = 0
    for pi, path in ipairs(graph.paths) do
      local w = weights[pi] or 0
      if w >= 0.10 then
        for _, sg in ipairs(path.stages) do
          -- Le sonde passive (stage_role == 3 o ptype 9..12: Probe, Prism, Loudness Meter) misurano ma non alterano il segnale.
          local is_passive = (sg.stage_role == 3) or (sg.ptype >= 9 and sg.ptype <= 12)
          if sg.enabled and sg.track_idx ~= -1 and not is_passive then
            local av = avg_map[sg.key]
            local v = 0
            if domain == "gain" then
              v = av and av.gain_delta or sg.gain_delta_db or 0
            elseif domain == "zone" and zone_k then
              v = av and av.z[zone_k] or sg.tone_zones[zone_k] or 0
            elseif domain == "tilt" then
              if sg.has_brown_zones then
                v = av and av.tilt or sg.tilt or 0
              else
                local z4 = av and av.z[4] or sg.tone_zones[4] or 0
                local z1 = av and av.z[1] or sg.tone_zones[1] or 0
                v = (z4 - z1) * 0.25
              end
            end
            if v * err_sign > 0.3 then
              local sc = math.abs(v) * w
              if sc > best_score then
                best_score = sc
                best = { stage = sg, val = v, weight = w, external = false }
              end
            end
          end
        end
      end
    end
    -- Confronta anche con eventuali residui differenziali di blocchi esterni opachi
    for _, seg in ipairs(ext_segments) do
      local v = 0
      if domain == "gain" then
        v = seg.resid_gain
      elseif domain == "zone" and zone_k and seg.has_z_diff then
        v = seg.resid_z[zone_k]
      elseif domain == "tilt" and seg.has_z_diff then
        v = (seg.resid_z[4] - seg.resid_z[1]) * 0.25
      end
      if v * err_sign >= ((domain == "gain") and M.FRAME.EXT_RESID_GAIN_DB or M.FRAME.EXT_RESID_ZONE_DB) then
        local sc = math.abs(v) * seg.weight
        if sc > best_score then
          best_score = sc
          best = {
            stage = { track_idx = seg.track_idx, fx_idx = seg.fx_idx, track_name = "", name = seg.label, kind = "fx" },
            val = v,
            weight = seg.weight,
            external = true,
            label = seg.label,
          }
        end
      end
    end
    return best
  end

  if ready then
    -- 4A. Derive dal Target: Brown Slope tilt
    if st.master_spec.valid and math.abs(tilt_err) > ref.slope_tol then
      local sgn = (tilt_err > 0) and 1 or -1
      local contrib = find_top_contributor("tilt", nil, sgn)
      local sev = (math.abs(tilt_err) > ref.slope_tol * 2.0) and 3 or 2
      local who_it = contrib and (contrib.external and contrib.label or (contrib.stage.track_name .. " · " .. contrib.stage.name)) or "catena a monte"
      local who_en = contrib and (contrib.external and contrib.label or (contrib.stage.track_name .. " · " .. contrib.stage.name)) or "upstream chain"
      add_issue({
        key = string.format("target:tilt:%d", sgn),
        kind = "brown_tilt",
        severity = sev,
        track_idx = contrib and contrib.stage.track_idx or st.master_spec.track_idx,
        fx_idx = contrib and contrib.stage.fx_idx or st.master_spec.fx_idx,
        value = tilt_err,
        title_it = string.format("Pendenza %+.2f dB/o fuori margine (±%.2f) — %s", tilt_err, ref.slope_tol, (sgn > 0) and "piu' chiaro" or "piu' scuro"),
        title_en = string.format("Slope %+.2f dB/o out of window (±%.2f) — %s", tilt_err, ref.slope_tol, (sgn > 0) and "brighter" or "darker"),
        detail_it = string.format("Rif %.1f dB/o (%s). Spinta media principale: %s.", ref.slope, ref.mode_label_it, who_it),
        detail_en = string.format("Ref %.1f dB/o (%s). Primary average push: %s.", ref.slope, ref.mode_label_en, who_en),
        action_hint = { track_idx = contrib and contrib.stage.track_idx or -1, fx_idx = contrib and contrib.stage.fx_idx or -1, domain = "tilt", suggested_delta_db = round1(-tilt_err) },
      })
    end

    -- 4B. Derive dal Target: 4 zone Brown (in VOICE_ONLY su sensore full-band ignora la carenza <80 Hz)
    if st.master_spec.valid then
      local worst_k, worst_abs = nil, 0
      for k = 1, 4 do
        local skip_sub_deficit = (k == 1 and program_mode == "VOICE_ONLY" and not st.master_spec.is_voice_band and z_err[1] < 0)
        if not skip_sub_deficit and math.abs(z_err[k]) > ref.zone_green and math.abs(z_err[k]) > worst_abs then
          worst_abs = math.abs(z_err[k])
          worst_k = k
        end
      end
      if worst_k then
        local ze = z_err[worst_k]
        local sgn = (ze > 0) and 1 or -1
        local zlabels = st.master_spec.is_voice_band and M.FRAME.VOICE_ZONE_LABELS or M.FRAME.ZONE_LABELS
        local zlbl = zlabels[worst_k]
        local contrib = find_top_contributor("zone", worst_k, sgn)
        local sev = (worst_abs > ref.zone_yellow) and 3 or 2
        local target_tr = contrib and contrib.stage.track_idx or st.master_spec.track_idx
        local target_fx = contrib and contrib.stage.fx_idx or st.master_spec.fx_idx
        local who_it = contrib and (contrib.external and contrib.label or string.format("%s · %s (%+.1f dB)", contrib.stage.track_name, contrib.stage.name, contrib.val)) or "catena a monte"
        local who_en = contrib and (contrib.external and contrib.label or string.format("%s · %s (%+.1f dB)", contrib.stage.track_name, contrib.stage.name, contrib.val)) or "upstream chain"
        -- In FULL_MIX: se 40-160 Hz eccede e il bus Musica/FX e' alto su quella zona, attribuisci a Musica / HSC Carver Low
        if worst_k == 1 and sgn > 0 and program_mode == "FULL_MIX" and st.music_bus.valid and st.music_bus.has_z and st.music_bus.z[1] >= M.FRAME.ZONE_GREEN_DB then
          if st.carver.valid and st.carver.carver_low < M.FRAME.CARVER_ACTIVE_DB then
            who_it = string.format("Bus Musica/FX (%+.1f dB su 40-160) — verifica Carver Low su %s · Harmonic Space Carver (ora -%.1f dB)", st.music_bus.z[1], st.carver.track_name, st.carver.carver_low)
            who_en = string.format("Music/FX bus (%+.1f dB at 40-160) — check Carver Low on %s · Harmonic Space Carver (now -%.1f dB)", st.music_bus.z[1], st.carver.track_name, st.carver.carver_low)
            target_tr, target_fx = st.carver.track_idx, st.carver.fx_idx
          else
            who_it = string.format("Bus Musica/FX (%+.1f dB su 40-160 Hz, non la voce)", st.music_bus.z[1])
            who_en = string.format("Music/FX bus (%+.1f dB at 40-160 Hz, not voice)", st.music_bus.z[1])
            target_tr, target_fx = st.music_bus.track_idx, st.music_bus.fx_idx
          end
        end
        add_issue({
          key = string.format("target:zone:%d:%d", worst_k, sgn),
          kind = "brown_zone",
          severity = sev,
          track_idx = target_tr,
          fx_idx = target_fx,
          value = ze,
          title_it = string.format("Zona %s Hz a %+.1f dB dal riferimento (±%.1f dB)", zlbl, ze, ref.zone_green),
          title_en = string.format("Zone %s Hz at %+.1f dB from reference (±%.1f dB)", zlbl, ze, ref.zone_green),
          detail_it = string.format("Contributo medio principale a monte: %s.", who_it),
          detail_en = string.format("Primary upstream average contributor: %s.", who_en),
          action_hint = { track_idx = target_tr, fx_idx = target_fx, domain = "zone_" .. tostring(worst_k), suggested_delta_db = round1(-ze) },
        })
      end
    end

    -- 4B-bis. Controllo Rumble < 80 Hz sulla voce (solo eccesso, mai carenza)
    if st.voice_bus.valid and st.voice_bus.sub_excess > M.FRAME.SUB_RUMBLE_WARN_DB then
      add_issue({
        key = string.format("voice:rumble:%d", st.voice_bus.track_idx),
        kind = "voice_rumble",
        severity = (st.voice_bus.sub_excess > M.FRAME.SUB_RUMBLE_WARN_DB + 3.0) and 3 or 2,
        track_idx = st.voice_bus.track_idx,
        fx_idx = st.voice_bus.fx_idx,
        value = st.voice_bus.sub_excess,
        title_it = string.format("Rumble / Sub <80 Hz in eccesso sulla voce (%+.1f dB)", st.voice_bus.sub_excess),
        title_en = string.format("Excess sub <80 Hz rumble on voice (%+.1f dB)", st.voice_bus.sub_excess),
        detail_it = "Energia non vocale sotto 80 Hz rilevata dalla Voice Probe: verifica HPF o prossimita' microfonica a monte.",
        detail_en = "Non-vocal energy below 80 Hz detected by Voice Probe: check upstream HPF or mic proximity.",
        action_hint = { track_idx = st.voice_bus.track_idx, fx_idx = st.voice_bus.fx_idx, domain = "hpf", suggested_delta_db = round1(-st.voice_bus.sub_excess) },
      })
    end

    -- 4D. Mascheramento Voce vs Musica/FX e consulenza su ZP Harmonic Space Carver (solo durante parlato attivo)
    if program_mode == "FULL_MIX" and st.vm_speech_sec >= M.FRAME.MIN_JUDGE_SEC then
      local vm = st.vm_diff_avg
      local cv = st.carver
      local mb = st.music_bus
      if vm < M.FRAME.VM_TIGHT_DB then
        if cv.valid then
          if cv.vca_duck >= M.FRAME.CARVER_HEAVY_DB then
            add_issue({
              key = "masking:vm_heavy_carver",
              kind = "music_masking",
              severity = 3,
              track_idx = cv.track_idx,
              fx_idx = cv.fx_idx,
              value = vm,
              title_it = string.format("Musica alta a monte di Harmonic Space Carver (V-M %+.1f dB, Duck -%.1f dB)", vm, cv.vca_duck),
              title_en = string.format("Music too hot upstream of Harmonic Space Carver (V-M %+.1f dB, Duck -%.1f dB)", vm, cv.vca_duck),
              detail_it = "Il VCA Ducker sta gia' lavorando molto: abbassa il livello/fader del bus musica a monte prima di schiacciare oltre.",
              detail_en = "VCA Ducker is already working hard: lower upstream music level/fader before pushing ducking further.",
              action_hint = { track_idx = cv.track_idx, fx_idx = cv.fx_idx, domain = "music_level", suggested_delta_db = round1(vm - M.FRAME.VM_TIGHT_DB) },
            })
          else
            add_issue({
              key = "masking:vm_carver",
              kind = "music_masking",
              severity = (vm < 3.0) and 3 or 2,
              track_idx = cv.track_idx,
              fx_idx = cv.fx_idx,
              value = vm,
              title_it = string.format("Mascheramento Voce/Musica (V-M %+.1f dB durante parlato) — regola ZP HSC", vm),
              title_en = string.format("Voice/Music masking (V-M %+.1f dB during speech) — adjust ZP HSC", vm),
              detail_it = string.format("%s · Harmonic Space Carver: VCA Duck -%.1f dB, Carver Mid -%.1f dB. Apri HSC per dosare ducking/carving.", cv.track_name, cv.vca_duck, cv.carver_mid),
              detail_en = string.format("%s · Harmonic Space Carver: VCA Duck -%.1f dB, Carver Mid -%.1f dB. Open HSC to adjust ducking/carving.", cv.track_name, cv.vca_duck, cv.carver_mid),
              action_hint = { track_idx = cv.track_idx, fx_idx = cv.fx_idx, domain = "carver_duck", suggested_delta_db = round1(M.FRAME.VM_TIGHT_DB - vm) },
            })
          end
        else
          add_issue({
            key = "masking:vm_no_carver",
            kind = "music_masking",
            severity = (vm < 3.0) and 3 or 2,
            track_idx = mb.track_idx,
            fx_idx = mb.fx_idx,
            value = vm,
            title_it = string.format("Mascheramento Voce/Musica (V-M %+.1f dB durante parlato)", vm),
            title_en = string.format("Voice/Music masking (V-M %+.1f dB during speech)", vm),
            detail_it = "Musica molto vicina alla voce: inserisci ZP Harmonic Space Carver sul bus musica o riduci il fader musica.",
            detail_en = "Music sits close to voice: insert ZP Harmonic Space Carver on music bus or lower music fader.",
            action_hint = { track_idx = mb.track_idx, fx_idx = -1, domain = "music_level", suggested_delta_db = round1(vm - M.FRAME.VM_TIGHT_DB) },
          })
        end
      end

      if mb.valid and mb.has_z and mb.z[3] >= M.FRAME.MUSIC_MID_COLLISION_DB and vm < M.FRAME.VM_MASK_MAX_DB then
        if cv.valid and cv.carver_mid < M.FRAME.CARVER_ACTIVE_DB then
          add_issue({
            key = "masking:mid_carver",
            kind = "music_masking",
            severity = 2,
            track_idx = cv.track_idx,
            fx_idx = cv.fx_idx,
            value = mb.z[3],
            title_it = string.format("Collisione formanti 800-4k Hz (Musica %+.1f dB) — usa Carver Mid su ZP HSC", mb.z[3]),
            title_en = string.format("Formant collision 800-4k Hz (Music %+.1f dB) — engage Carver Mid on ZP HSC", mb.z[3]),
            detail_it = string.format("Invece di alzare la presenza della voce, scava 800-4k su %s · Harmonic Space Carver (Carver Mid ora -%.1f dB).", cv.track_name, cv.carver_mid),
            detail_en = string.format("Instead of boosting voice presence, carve 800-4k on %s · Harmonic Space Carver (Carver Mid now -%.1f dB).", cv.track_name, cv.carver_mid),
            action_hint = { track_idx = cv.track_idx, fx_idx = cv.fx_idx, domain = "carver_mid", suggested_delta_db = round1(-mb.z[3]) },
          })
        elseif not cv.valid then
          add_issue({
            key = "masking:mid_no_carver",
            kind = "music_masking",
            severity = 2,
            track_idx = mb.track_idx,
            fx_idx = mb.fx_idx,
            value = mb.z[3],
            title_it = string.format("Collisione formanti 800-4k Hz: bus Musica a %+.1f dB sotto la voce", mb.z[3]),
            title_en = string.format("Formant collision 800-4k Hz: Music bus at %+.1f dB under speech", mb.z[3]),
            detail_it = "La musica invade la fascia di intelligibilita': usa ZP Harmonic Space Carver (Carver Mid) invece di spingere la voce.",
            detail_en = "Music crowds the intelligibility band: use ZP Harmonic Space Carver (Carver Mid) instead of pushing voice EQ.",
            action_hint = { track_idx = mb.track_idx, fx_idx = mb.fx_idx, domain = "carver_mid", suggested_delta_db = round1(-mb.z[3]) },
          })
        end
      end
    end

    -- 4C. Derive dal Target: Loudness & True Peak
    if st.master_loud.valid then
      if math.abs(lufs_err) > ref.lufs_tol then
        local sgn = (lufs_err > 0) and 1 or -1
        local contrib = find_top_contributor("gain", nil, sgn)
        local sev = (math.abs(lufs_err) > ref.lufs_tol * 2.0) and 3 or 2
        local who = contrib and (contrib.external and contrib.label or string.format("%s · %s (%+.1f dB)", contrib.stage.track_name, contrib.stage.name, contrib.val)) or "fader / trim a monte"
        add_issue({
          key = string.format("target:lufs:%d", sgn),
          kind = "loudness",
          severity = sev,
          track_idx = contrib and contrib.stage.track_idx or -1,
          fx_idx = contrib and contrib.stage.fx_idx or -1,
          value = lufs_err,
          title_it = string.format("Loudness %+.1f LU rispetto a %.1f LUFS (±%.1f LU)", lufs_err, ref.lufs_target, ref.lufs_tol),
          title_en = string.format("Loudness %+.1f LU vs %.1f LUFS target (±%.1f LU)", lufs_err, ref.lufs_target, ref.lufs_tol),
          detail_it = string.format("Sorgente %s. Spinta principale: %s.", st.master_loud.source, who),
          detail_en = string.format("Source %s. Main drive: %s.", st.master_loud.source, who),
          action_hint = { track_idx = contrib and contrib.stage.track_idx or -1, fx_idx = contrib and contrib.stage.fx_idx or -1, domain = "gain", suggested_delta_db = round1(-lufs_err) },
        })
      end
      if st.master_loud.tp > ref.tp_max + 0.15 then
        add_issue({
          key = "target:tp",
          kind = "true_peak",
          severity = 3,
          track_idx = -1,
          fx_idx = 0,
          value = st.master_loud.tp,
          title_it = string.format("True Peak %.1f dBTP oltre soglia %.1f dBTP", st.master_loud.tp, ref.tp_max),
          title_en = string.format("True Peak %.1f dBTP over %.1f dBTP ceiling", st.master_loud.tp, ref.tp_max),
          detail_it = "Riduci il livello a monte o verifica il ceiling del limiter finale.",
          detail_en = "Lower upstream drive or check final limiter ceiling.",
          action_hint = { track_idx = -1, fx_idx = 0, domain = "gain", suggested_delta_db = round1(ref.tp_max - st.master_loud.tp) },
        })
      end
    end

    -- 5. Tiro alla fune (Opposizioni di Tono e Gain) CON filtro di non-linearita' intermedia
    for _, path in ipairs(graph.paths) do
      local stages = path.stages
      for i = 1, #stages - 1 do
        local A = stages[i]
        if A.enabled and (A.kind == "fx" or A.kind == "fader" or A.kind == "send") and not A.has_brown_zones then
          local aA = avg_map[A.key]
          local gA = aA and aA.gain_delta or A.gain_delta_db or 0
          local zA = aA and aA.z or A.tone_zones

          for j = i + 1, #stages do
            local B = stages[j]
            if B.enabled and (B.kind == "fx" or B.kind == "fader" or B.kind == "send") and not B.has_brown_zones then
              local aB = avg_map[B.key]
              local gB = aB and aB.gain_delta or B.gain_delta_db or 0
              local zB = aB and aB.z or B.tone_zones

              -- Controlla se tra A e B c'e' almeno uno stadio non-lineare realmente attivo
              local has_nl = false
              local nl_reason = nil
              for m = i + 1, j - 1 do
                local ok_nl, why = stage_is_active_nonlinear(stages[m], avg_map[stages[m].key])
                if ok_nl then
                  has_nl = true
                  nl_reason = why
                  break
                end
              end

              -- 5A. Opposizione tonale su una delle 4 zone
              if A.kind == "fx" and B.kind == "fx" and A.is_zp and B.is_zp then
                for k = 1, 4 do
                  local va = zA[k] or 0
                  local vb = zB[k] or 0
                  if (va * vb < 0) and math.abs(va) >= M.FRAME.OPP_TONE_MIN_DB and math.abs(vb) >= M.FRAME.OPP_TONE_MIN_DB then
                    local pair_key = string.format("opp_tone:%s:%s:%d", A.key, B.key, k)
                    local zlbl = M.FRAME.ZONE_LABELS[k]
                    if has_nl then
                      add_preemph({
                        key = pair_key,
                        kind = "pre_emphasis_tone",
                        track_idx = A.track_idx,
                        fx_idx = A.fx_idx,
                        title_it = string.format("Pre-enfasi %s Hz (%s %+.1f dB -> %s -> %s %+.1f dB)", zlbl, A.name, va, nl_reason, B.name, vb),
                        title_en = string.format("Pre-emphasis %s Hz (%s %+.1f dB -> %s -> %s %+.1f dB)", zlbl, A.name, va, nl_reason, B.name, vb),
                      })
                    else
                      add_issue({
                        key = pair_key,
                        kind = "opposition_tone",
                        severity = 2,
                        track_idx = A.track_idx,
                        fx_idx = A.fx_idx,
                        second_track_idx = B.track_idx,
                        second_fx_idx = B.fx_idx,
                        value = math.min(math.abs(va), math.abs(vb)),
                        title_it = string.format("Opposizione %s Hz: %s (%+.1f dB) <-> %s (%+.1f dB)", zlbl, A.name, va, B.name, vb),
                        title_en = string.format("Opposing EQ %s Hz: %s (%+.1f dB) <-> %s (%+.1f dB)", zlbl, A.name, va, B.name, vb),
                        detail_it = "Nessuna compressione o saturazione attiva in mezzo: i due interventi si compensano a vicenda.",
                        detail_en = "No active compression or saturation in between: both EQ moves cancel each other.",
                        action_hint = { track_idx = A.track_idx, fx_idx = A.fx_idx, domain = "zone_" .. tostring(k), suggested_delta_db = round1(-va * 0.5) },
                      })
                    end
                    break -- una segnalazione per coppia (A,B)
                  end
                end
              end

              -- 5B. Opposizione di Gain Staging (es. trim +6 dB poi fader -6 dB senza dinamica/sat in mezzo)
              if (gA * gB < 0) and math.abs(gA) >= M.FRAME.OPP_GAIN_MIN_DB and math.abs(gB) >= M.FRAME.OPP_GAIN_MIN_DB then
                local pair_key = string.format("opp_gain:%s:%s", A.key, B.key)
                if has_nl then
                  add_preemph({
                    key = pair_key,
                    kind = "pre_emphasis_gain",
                    track_idx = A.track_idx,
                    fx_idx = A.fx_idx,
                    title_it = string.format("Drive -> Recupero (%s %+.1f dB -> %s -> %s %+.1f dB)", A.name, gA, nl_reason, B.name, gB),
                    title_en = string.format("Drive -> Makeup (%s %+.1f dB -> %s -> %s %+.1f dB)", A.name, gA, nl_reason, B.name, gB),
                  })
                else
                  add_issue({
                    key = pair_key,
                    kind = "opposition_gain",
                    severity = 2,
                    track_idx = A.track_idx,
                    fx_idx = A.fx_idx,
                    second_track_idx = B.track_idx,
                    second_fx_idx = B.fx_idx,
                    value = math.min(math.abs(gA), math.abs(gB)),
                    title_it = string.format("Gain opposto: %s (%+.1f dB) <-> %s (%+.1f dB)", A.name, gA, B.name, gB),
                    title_en = string.format("Opposing gain: %s (%+.1f dB) <-> %s (%+.1f dB)", A.name, gA, B.name, gB),
                    detail_it = "Nessuno stadio dinamico/saturazione attivo in mezzo: guadagno spinto e poi riabbassato.",
                    detail_en = "No active dynamics/saturation in between: level pushed then pulled back down.",
                    action_hint = { track_idx = A.track_idx, fx_idx = A.fx_idx, domain = "gain", suggested_delta_db = round1(-gA * 0.5) },
                  })
                end
              end
            end
          end
        end
      end

      -- 6. Concentrazione di carico dinamico su un solo stadio lungo il percorso
      local gr_sum = 0.0
      local dyn_stages = 0
      local top_dyn = nil
      local top_dyn_gr = 0.0
      for _, sg in ipairs(path.stages) do
        if sg.kind == "fx" and sg.enabled then
          local av = avg_map[sg.key]
          local gr = av and av.gr_total or sg.gr_total or 0
          if gr >= 0.3 then
            dyn_stages = dyn_stages + 1
            gr_sum = gr_sum + gr
            if gr > top_dyn_gr then
              top_dyn_gr = gr
              top_dyn = sg
            end
          end
        end
      end
      if dyn_stages >= 2 and gr_sum >= M.FRAME.COMP_TOTAL_MIN_DB and top_dyn and (top_dyn_gr / gr_sum) >= M.FRAME.COMP_SHARE_WARN then
        local share_pct = math.floor((top_dyn_gr / gr_sum) * 100 + 0.5)
        add_issue({
          key = string.format("comp_conc:%s", top_dyn.key),
          kind = "comp_concentration",
          severity = 2,
          track_idx = top_dyn.track_idx,
          fx_idx = top_dyn.fx_idx,
          value = top_dyn_gr,
          title_it = string.format("Carico comp concentrato su %s · %s (%.1f dB = %d%%)", top_dyn.track_name, top_dyn.name, top_dyn_gr, share_pct),
          title_en = string.format("Dynamics load focused on %s · %s (%.1f dB = %d%%)", top_dyn.track_name, top_dyn.name, top_dyn_gr, share_pct),
          detail_it = string.format("Su %.1f dB di GR totale lungo il ramo, uno stadio sta facendo quasi tutto il lavoro.", gr_sum),
          detail_en = string.format("Out of %.1f dB total GR along this branch, one stage is doing almost all the work.", gr_sum),
          action_hint = { track_idx = top_dyn.track_idx, fx_idx = top_dyn.fx_idx, domain = "dynamics", suggested_delta_db = round1(-(top_dyn_gr * 0.3)) },
        })
      end
    end
  end

  -- Ordina segnalazioni: non ignorate prima, poi severita' decrescente, poi valore assoluto
  table.sort(issues, function(a, b)
    if a.ignored ~= b.ignored then return not a.ignored end
    if a.severity ~= b.severity then return a.severity > b.severity end
    return math.abs(a.value or 0) > math.abs(b.value or 0)
  end)

  local active_issues = {}
  local conflict_count = 0
  local max_sev = 0
  for _, it in ipairs(issues) do
    if not it.ignored then
      active_issues[#active_issues + 1] = it
      if it.severity > max_sev then max_sev = it.severity end
      if it.kind == "opposition_tone" or it.kind == "opposition_gain" then
        conflict_count = conflict_count + 1
      end
    end
  end

  local status = 0
  if max_sev >= 3 or conflict_count > 0 then
    status = 3
  elseif max_sev == 2 then
    status = 2
  elseif ready and (st.master_spec.valid or st.master_loud.valid or #graph.paths > 0) then
    status = 1
  end

  local rep = {
    ready = ready,
    holding = st.holding,
    useful_sec = st.useful_sec,
    status = status,
    program_mode = program_mode,
    vm_speech_sec = st.vm_speech_sec,
    vm_diff_avg = st.vm_diff_avg,
    voice_bus = st.voice_bus,
    music_bus = st.music_bus,
    carver = st.carver,
    ref = ref,
    z_err = z_err,
    tilt_err = tilt_err,
    lufs_err = lufs_err,
    master_spec = st.master_spec,
    master_loud = st.master_loud,
    issues = issues,
    active_issues = active_issues,
    pre_emphasis = pre_emphasis,
    ext_segments = ext_segments,
    conflict_count = conflict_count,
    preemph_count = #pre_emphasis,
    path_weights = weights,
  }
  st.last_report = rep
  return rep
end

-- Compila il blocco gmem[3600..3619] letto da Master Pro e Voice-Music Probe
function M.build_gmem_summary(st, now_t, hb)
  local rep = st.last_report or M.analyze(st)
  local top = rep.active_issues[1]
  return {
    [3600] = 905360,
    [3601] = hb or 1,
    [3602] = now_t or 0,
    [3603] = rep.ref.slope,
    [3604] = rep.ref.mode,
    [3605] = rep.useful_sec,
    [3606] = rep.status,
    [3607] = #rep.active_issues,
    [3608] = top and (M.KIND_CODE[top.kind] or 0) or 0,
    [3609] = top and (top.track_idx or -2) or -2,
    [3610] = top and (top.fx_idx or -1) or -1,
    [3611] = top and (top.value or 0) or 0,
    [3612] = rep.z_err[1] or 0,
    [3613] = rep.z_err[2] or 0,
    [3614] = rep.z_err[3] or 0,
    [3615] = rep.z_err[4] or 0,
    [3616] = rep.tilt_err or 0,
    [3617] = rep.lufs_err or 0,
    [3618] = rep.conflict_count or 0,
    [3619] = rep.preemph_count or 0,
  }
end

return M
