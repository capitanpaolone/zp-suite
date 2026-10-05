-- @description ZP Harmonic Space Carver Cue Navigator (background helper)
-- @version 1.4
-- @author Paolo Balestri / Codex
-- @about Collega i Carver a REAPER: salti tra i cue, punto del cursore a trasporto fermo,
--   verifica del routing sidechain e cue come marker #HSC sul righello (seguono l'editing).
-- @changelog
--   1.4: i cue diventano anche marker di servizio "#HSC" sul righello. Il marker comanda: se lo
--        sposti, lo cancelli, lo aggiungi o lo sposta un taglio in ripple, il Carver si aggiorna;
--        ADD/REMOVE, UNDO e CLEAR ALL del Carver creano o tolgono i marker. Ctrl+Z vale anche per i cue.
--        Al primo avvio i cue gia' salvati nel Carver diventano marker.
--   1.3: controlla il routing delle fonti sidechain di ogni Carver (pin collegati ai canali della
--        traccia, invii e tracce figlie del folder che arrivano su quei canali) e lo scrive in base+71.
--   1.2: comando 4 = "dove e' il cursore": risponde con la posizione del cursore di REAPER
--        (base+70), cosi' il Carver aggiunge un cue anche a trasporto fermo.
--   1.1: rilegge l'elenco degli FX una volta al secondo (prima a ogni giro, ~30 volte al secondo);
--        a ogni giro controlla solo gli indirizzi dei Carver trovati.
-- ================================================================
-- Sincronizzazione cue <-> marker #HSC: logica pura (provata da test_hsc_sync.lua).
-- ================================================================
local HSC = { TOL = 0.005, MAX = 64, NAME = "#HSC" }

function HSC.is_cue_marker(name, isrgn)
  if isrgn then return false end
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return name == HSC.NAME or name:sub(1, #HSC.NAME + 1) == HSC.NAME .. " "
end

function HSC.sorted(list)
  local out = {}
  for i, t in ipairs(list or {}) do out[i] = t end
  table.sort(out)
  return out
end

function HSC.same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if math.abs(a[i] - b[i]) > HSC.TOL then return false end end
  return true
end

local function contains(list, t)
  for _, v in ipairs(list) do if math.abs(v - t) <= HSC.TOL then return true end end
  return false
end

-- Confronta marker e cue del Carver con l'ultima istantanea sincronizzata.
-- Restituisce un piano: { to_carver = elenco | nil, add = {tempi}, remove = {tempi}, snapshot = elenco, warn = testo|nil }.
-- Regole: il marker comanda; se e' cambiato solo il Carver, si aggiornano i marker;
-- prima volta (nessuna istantanea): marker presenti -> al Carver, altrimenti i cue diventano marker.
function HSC.plan(snapshot, markers, cues)
  markers, cues = HSC.sorted(markers), HSC.sorted(cues)
  local p = { add = {}, remove = {} }
  local function markers_win()
    local list = {}
    for i = 1, math.min(#markers, HSC.MAX) do list[i] = markers[i] end
    if #markers > HSC.MAX then p.warn = "Piu' di 64 marker #HSC: il Carver usa i primi 64" end
    if not HSC.same(list, cues) then p.to_carver = list end
    p.snapshot = list
  end
  if snapshot == nil then
    if #markers > 0 then markers_win() else
      for _, t in ipairs(cues) do p.add[#p.add + 1] = t end
      p.snapshot = cues
    end
    return p
  end
  snapshot = HSC.sorted(snapshot)
  local markers_changed = not HSC.same(markers, snapshot)
  local cues_changed = not HSC.same(cues, snapshot)
  if markers_changed then
    markers_win()
  elseif cues_changed then
    for _, t in ipairs(cues) do if not contains(markers, t) then p.add[#p.add + 1] = t end end
    for _, t in ipairs(markers) do if not contains(cues, t) then p.remove[#p.remove + 1] = t end end
    p.snapshot = cues
  else
    p.snapshot = snapshot
  end
  return p
end

if HSC_SYNC_TEST then return HSC end

local GMEM_NAME = "ZPVoiceoverSharedBus"
local MAGIC = 905243
local BASE_START = 4096
local TRACK_STRIDE = 4096
local FX_STRIDE = 72
local MAX_BASE = 8300000
local last_seq = {}
reaper.gmem_attach(GMEM_NAME)

local function read_cues(base)
  local n = math.max(0, math.min(64, math.floor(reaper.gmem_read(base + 4) + 0.5)))
  local cues = {}
  for i = 0, n - 1 do
    local t = reaper.gmem_read(base + 5 + i)
    if t >= 0 then cues[#cues + 1] = {time = t, index = i} end
  end
  table.sort(cues, function(a,b) return a.time < b.time end)
  return cues
end

local function seek(time)
  local playing = (reaper.GetPlayState() & 1) == 1
  reaper.SetEditCurPos2(0, time, true, playing)
end

local function handle(base)
  if reaper.gmem_read(base + 69) ~= MAGIC then return end
  local seq = math.floor(reaper.gmem_read(base + 1) + 0.5)
  local ack = math.floor(reaper.gmem_read(base + 3) + 0.5)
  if seq == ack or seq == last_seq[base] then return end
  local cmd = math.floor(reaper.gmem_read(base) + 0.5)
  if cmd == 4 then
    -- il Carver chiede il punto per un cue: cursore di edit (o playhead se sta suonando)
    local pos = ((reaper.GetPlayState() & 1) == 1) and (reaper.GetPlayPosition2 or reaper.GetPlayPosition)() or reaper.GetCursorPosition()
    reaper.gmem_write(base + 70, pos)
    reaper.gmem_write(base + 3, seq)
    last_seq[base] = seq
    return
  end
  local cues = read_cues(base)
  local selected = -1
  local target = nil
  if cmd == 1 or cmd == 2 then
    local now = ((reaper.GetPlayState() & 1) == 1) and (reaper.GetPlayPosition2 or reaper.GetPlayPosition)() or reaper.GetCursorPosition()
    if cmd == 1 then
      for _, cue in ipairs(cues) do
        if cue.time < now - 0.001 then selected = cue.index; target = cue.time else break end
      end
    else
      for _, cue in ipairs(cues) do
        if cue.time > now + 0.001 then selected = cue.index; target = cue.time; break end
      end
    end
  elseif cmd == 3 then
    selected = math.floor(reaper.gmem_read(base + 2) + 0.5)
    for _, cue in ipairs(cues) do
      if cue.index == selected then target = cue.time; break end
    end
  end
  reaper.gmem_write(base + 2, selected)
  if target then seek(target) end
  reaper.gmem_write(base + 3, seq)
  last_seq[base] = seq
end

-- Indirizzi gmem dei Carver nel progetto: si ricalcolano ogni secondo (spostare un FX o
-- una traccia cambia l'indirizzo, che il plugin ricalcola da solo nella sua GUI).
local bases, carvers, last_scan = {}, {}, -1
local function scan_track(track, track_index, out, list)
  local n = reaper.TrackFX_GetCount(track)
  for fx = 0, n - 1 do
    local ok, name = reaper.TrackFX_GetFXName(track, fx, "")
    if ok and name and name:lower():find("harmonic space carver", 1, true) then
      local base = BASE_START + ((track_index + 2) * TRACK_STRIDE) + (fx * FX_STRIDE)
      if base >= 0 and base < MAX_BASE then
        out[#out + 1] = base
        list[#list + 1] = {base = base, track = track, fx = fx}
      end
    end
  end
end

-- Canali della traccia (0-based) su cui arriva segnale: ricezioni e tracce figlie del folder.
local function fed_channels(track)
  local fed = {}
  for r = 0, reaper.GetTrackNumSends(track, -1) - 1 do
    local src = math.floor(reaper.GetTrackSendInfo_Value(track, -1, r, "I_SRCCHAN"))
    if src >= 0 then
      local dst = math.floor(reaper.GetTrackSendInfo_Value(track, -1, r, "I_DSTCHAN"))
      local w = src >> 10
      local nch = (w == 0) and 2 or ((w == 1) and 1 or w * 2)
      local ch = dst & 1023
      if (dst & 1024) ~= 0 then nch = 1 end
      for k = 0, nch - 1 do fed[ch + k] = true end
    end
  end
  for i = 0, reaper.CountTracks(0) - 1 do
    local child = reaper.GetTrack(0, i)
    if reaper.GetParentTrack(child) == track and reaper.GetMediaTrackInfo_Value(child, "B_MAINSEND") == 1 then
      local offs = math.floor(reaper.GetMediaTrackInfo_Value(child, "C_MAINSEND_OFFS"))
      local nch = math.floor(reaper.GetMediaTrackInfo_Value(child, "C_MAINSEND_NCH"))
      if nch <= 0 then nch = math.floor(reaper.GetMediaTrackInfo_Value(child, "I_NCHAN")) end
      for k = 0, nch - 1 do fed[offs + k] = true end
    end
  end
  return fed
end

-- Per le fonti SC1-SC3 (pin di ingresso 2-3, 4-5, 6-7): pin collegati a un canale esistente
-- (bit 1) e almeno uno di quei canali alimentato (bit 2). Valore = 64 + somma(codice * 4^i).
local function route_value(track, fx)
  local nchan = math.floor(reaper.GetMediaTrackInfo_Value(track, "I_NCHAN"))
  local fed = fed_channels(track)
  local value = 64
  for i = 0, 2 do
    local mapped, fedok = false, false
    for pin = 2 + 2 * i, 3 + 2 * i do
      local lo = reaper.TrackFX_GetPinMappings(track, fx, 0, pin)
      for ch = 0, math.min(31, nchan - 1) do
        if (lo & (1 << ch)) ~= 0 then
          mapped = true
          if fed[ch] then fedok = true end
        end
      end
    end
    local code = (mapped and 1 or 0) + (fedok and 2 or 0)
    value = value + code * (4 ^ i)
  end
  return value
end

local function rescan()
  local out, list = {}, {}
  scan_track(reaper.GetMasterTrack(0), -1, out, list)
  for i = 0, reaper.CountTracks(0) - 1 do scan_track(reaper.GetTrack(0, i), i, out, list) end
  bases, carvers = out, list
  for _, c in ipairs(carvers) do
    if reaper.gmem_read(c.base + 69) == MAGIC then reaper.gmem_write(c.base + 71, route_value(c.track, c.fx)) end
  end
end

-- ================================================================
-- Sincronizzazione nel progetto (ogni 0,25 s)
-- ================================================================
local MB = 3800                          -- casella comune dei comandi al Carver (vedi il JSFX)
local MARKER_COLOR = reaper.ColorToNative(36, 184, 212) | 0x1000000
local snapshots, sync_project, pending, last_sync = {}, nil, nil, -1
local last_mb_seen, warned = 0, false

local function read_markers()
  local list, i = {}, 0
  while true do
    local retval, isrgn, pos, _, name = reaper.EnumProjectMarkers3(0, i)
    if retval == 0 then break end
    if HSC.is_cue_marker(name, isrgn) then list[#list + 1] = pos end
    i = i + 1
  end
  return list
end

local function cue_times(base)
  local list = {}
  for _, c in ipairs(read_cues(base)) do list[#list + 1] = c.time end
  return list
end

local function apply_markers(add, remove)
  if #add == 0 and #remove == 0 then return end
  reaper.Undo_BeginBlock2(0)
  reaper.PreventUIRefresh(1)
  if #remove > 0 then
    -- dall'ultimo indice al primo, cosi' gli indici restano validi
    local i = reaper.CountProjectMarkers(0) - 1
    while i >= 0 do
      local retval, isrgn, pos, _, name = reaper.EnumProjectMarkers3(0, i)
      if retval ~= 0 and HSC.is_cue_marker(name, isrgn) then
        for _, t in ipairs(remove) do
          if math.abs(pos - t) <= HSC.TOL then reaper.DeleteProjectMarkerByIndex(0, i); break end
        end
      end
      i = i - 1
    end
  end
  for _, t in ipairs(add) do reaper.AddProjectMarker2(0, false, t, 0, HSC.NAME, -1, MARKER_COLOR) end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock2(0, "ZP HSC: cue sul righello", -1)
end

-- Manda l'elenco al Carver (comando 5). Un comando alla volta: si aspetta l'ack prima del successivo.
local function send_list(base, list)
  local seq = math.floor(reaper.gmem_read(MB + 3) + 0.5) + 1
  reaper.gmem_write(MB + 10, #list)
  for i = 1, HSC.MAX do reaper.gmem_write(MB + 10 + i, list[i] or -1) end
  reaper.gmem_write(MB, base)
  reaper.gmem_write(MB + 1, 5)
  reaper.gmem_write(MB + 3, seq)
  pending = { base = base, seq = seq, t = reaper.time_precise(), snapshot = list }
end

local function sync()
  local proj = reaper.EnumProjects(-1)
  if proj ~= sync_project then snapshots, pending, sync_project = {}, nil, proj end
  if pending then
    if math.floor(reaper.gmem_read(MB + 4) + 0.5) == pending.seq then
      snapshots[pending.base] = pending.snapshot; pending = nil
    elseif reaper.time_precise() - pending.t > 1.0 then
      pending = nil                       -- Carver fermo: si riprova al prossimo giro
    end
    return
  end
  -- la casella e' occupata da un'azione da tastiera in corso: si aspetta
  if math.floor(reaper.gmem_read(MB + 4) + 0.5) ~= math.floor(reaper.gmem_read(MB + 3) + 0.5)
     and reaper.time_precise() - (last_mb_seen or 0) < 1.0 then return end
  last_mb_seen = reaper.time_precise()
  local markers = read_markers()
  for _, c in ipairs(carvers) do
    if reaper.gmem_read(c.base + 69) == MAGIC then
      local p = HSC.plan(snapshots[c.base], markers, cue_times(c.base))
      if p.warn and not warned then warned = true; if reaper.osara_outputMessage then reaper.osara_outputMessage(p.warn) end end
      if #p.add > 0 or #p.remove > 0 then
        apply_markers(p.add, p.remove)
        markers = read_markers()
      end
      if p.to_carver then
        send_list(c.base, p.to_carver)
        return                            -- un Carver per giro mentre si aspetta l'ack
      end
      snapshots[c.base] = p.snapshot
    end
  end
end

local function run()
  local now = reaper.time_precise()
  if now - last_scan >= 1.0 then rescan(); last_scan = now end
  for _, base in ipairs(bases) do handle(base) end
  if now - last_sync >= 0.25 then sync(); last_sync = now end
  reaper.defer(run)
end
-- simulazione fuori REAPER (test): espone i passi senza avviare il ciclo
if HSC_SYNC_SIM then return { sync = sync, rescan = rescan } end
run()
