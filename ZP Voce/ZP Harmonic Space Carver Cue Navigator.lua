-- @description ZP Harmonic Space Carver Cue Navigator (background helper)
-- @version 1.6
-- @author Paolo Balestri / Codex
-- @about Collega i Carver a REAPER: salti tra i cue, punto del cursore a trasporto fermo,
--   verifica del routing sidechain e cue come marker #HSC sul righello (seguono l'editing).
-- @changelog
--   1.6: ogni cue e' ancorato all'audio della voce che ha sotto (file e punto nel file). Se l'audio
--        si sposta e il cue no, il marker #HSC e il punto nel Carver diventano rossi: RIALLINEA porta
--        il cue dove adesso c'e' la sua voce, TIENI QUI accetta la posizione. Un marker trascinato a mano
--        prende come riferimento la voce nel punto nuovo. Ancore salvate nel progetto.
--   1.5: sa quali tracce sono voce: risale dal routing dei pin sidechain accesi (invii e figlie del
--        folder, poi le loro figlie e i loro invii; tracce mute escluse). Usata dall'azione
--        "ZP HSC - Mostra tracce voce" e, nella prossima versione, come riferimento dei cue.
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

-- ================================================================
-- Tracce voce di un Carver: quelle che arrivano ai pin delle fonti SC accese.
-- Si parte dai canali della traccia del Carver collegati ai pin SC (solo fonti ON), si prendono
-- gli invii e le figlie del folder che arrivano su quei canali, e da li' a ritroso le loro figlie
-- e i loro invii. Tracce mute e item muti non contano. Usa l'API di REAPER solo quando la chiami.
-- ================================================================
local function overlaps(set, first, count)
  for ch = first, first + count - 1 do if set[ch] then return true end end
  return false
end

local function send_width(src)
  local w = src >> 10
  return (w == 0) and 2 or ((w == 1) and 1 or w * 2)
end

function HSC.sc_channels(track, fx)
  local nchan = math.floor(reaper.GetMediaTrackInfo_Value(track, "I_NCHAN"))
  local set, any = {}, false
  for i = 0, 2 do
    local on = (i == 0)
    for p = 0, reaper.TrackFX_GetNumParams(track, fx) - 1 do
      local _, pname = reaper.TrackFX_GetParamName(track, fx, p, "")
      if pname and pname:find("SC " .. (i + 1) .. " On", 1, true) then
        on = reaper.TrackFX_GetParam(track, fx, p) >= 0.5; break
      end
    end
    if on then
      for pin = 2 + 2 * i, 3 + 2 * i do
        local lo = reaper.TrackFX_GetPinMappings(track, fx, 0, pin)
        for ch = 0, math.min(31, nchan - 1) do
          if (lo & (1 << ch)) ~= 0 then set[ch] = true; any = true end
        end
      end
    end
  end
  return set, any
end

function HSC.voice_tracks(track, fx)
  local channels = HSC.sc_channels(track, fx)
  local found, list, visited = {}, {}, {}
  local function children_of(parent)
    local out = {}
    for i = 0, reaper.CountTracks(0) - 1 do
      local t = reaper.GetTrack(0, i)
      if reaper.GetParentTrack(t) == parent and reaper.GetMediaTrackInfo_Value(t, "B_MAINSEND") == 1 then out[#out + 1] = t end
    end
    return out
  end
  local function add_tree(t)
    if visited[t] then return end
    visited[t] = true
    if reaper.GetMediaTrackInfo_Value(t, "B_MUTE") == 1 then return end
    if not found[t] then found[t] = true; list[#list + 1] = t end
    for _, c in ipairs(children_of(t)) do add_tree(c) end
    for r = 0, reaper.GetTrackNumSends(t, -1) - 1 do
      if reaper.GetTrackSendInfo_Value(t, -1, r, "I_SRCCHAN") >= 0 and reaper.GetTrackSendInfo_Value(t, -1, r, "B_MUTE") == 0 then
        add_tree(reaper.GetTrackSendInfo_Value(t, -1, r, "P_SRCTRACK"))
      end
    end
  end
  visited[track] = true
  for r = 0, reaper.GetTrackNumSends(track, -1) - 1 do
    local src = math.floor(reaper.GetTrackSendInfo_Value(track, -1, r, "I_SRCCHAN"))
    if src >= 0 and reaper.GetTrackSendInfo_Value(track, -1, r, "B_MUTE") == 0 then
      local dst = math.floor(reaper.GetTrackSendInfo_Value(track, -1, r, "I_DSTCHAN"))
      local n = ((dst & 1024) ~= 0) and 1 or send_width(src)
      if overlaps(channels, dst & 1023, n) then add_tree(reaper.GetTrackSendInfo_Value(track, -1, r, "P_SRCTRACK")) end
    end
  end
  for _, c in ipairs(children_of(track)) do
    local offs = math.floor(reaper.GetMediaTrackInfo_Value(c, "C_MAINSEND_OFFS"))
    local n = math.floor(reaper.GetMediaTrackInfo_Value(c, "C_MAINSEND_NCH"))
    if n <= 0 then n = math.floor(reaper.GetMediaTrackInfo_Value(c, "I_NCHAN")) end
    if overlaps(channels, offs, n) then add_tree(c) end
  end
  table.sort(list, function(a, b)
    return reaper.GetMediaTrackInfo_Value(a, "IP_TRACKNUMBER") < reaper.GetMediaTrackInfo_Value(b, "IP_TRACKNUMBER")
  end)
  return list
end

-- Quante tracce voce hanno audio vero (item non muti con un file).
function HSC.has_audio(track)
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local take = reaper.GetActiveTake(item)
    if take and reaper.GetMediaItemInfo_Value(item, "B_MUTE") == 0 and not reaper.TakeIsMIDI(take) then
      local src = reaper.GetMediaItemTake_Source(take)
      if src and (reaper.GetMediaSourceFileName(src, "") or "") ~= "" then return true end
    end
  end
  return false
end

-- ================================================================
-- Ancore dei cue all'audio della voce: logica pura (provata da test_hsc_sync.lua).
-- Un item voce e' { file, pos, len, offs, rate, track }: pos/len in timeline, offs = inizio nel file.
-- Un'ancora e' { file, src }: il punto del file sotto il cue ("" = nessuna voce: cue libero).
-- ================================================================
HSC.ATOL = 0.02          -- scarto oltre il quale un cue e' fuori posto (s)
HSC.AFTER, HSC.BEFORE = 5.0, 2.0   -- voce finita da poco prima del cue / che parte subito dopo

function HSC.make_anchor(pos, items)
  local best, best_key
  for _, it in ipairs(items) do                         -- voce sotto il cue
    if pos >= it.pos - 1e-9 and pos <= it.pos + it.len + 1e-9 then
      if not best or it.track < best.track then best = it end
    end
  end
  if not best then                                      -- voce appena finita
    for _, it in ipairs(items) do
      local e = it.pos + it.len
      if e <= pos and pos - e <= HSC.AFTER and (not best_key or e > best_key) then best, best_key = it, e end
    end
  end
  if not best then                                      -- voce che parte subito dopo
    best_key = nil
    for _, it in ipairs(items) do
      if it.pos > pos and it.pos - pos <= HSC.BEFORE and (not best_key or it.pos < best_key) then best, best_key = it, it.pos end
    end
  end
  if not best then return { file = "", src = 0 } end
  return { file = best.file, src = best.offs + (pos - best.pos) * best.rate }
end

-- Dove si trova adesso in timeline il punto dell'ancora (nil = audio sparito). Se lo stesso file
-- compare piu' volte, vale l'occorrenza piu' vicina a "near".
function HSC.expected(anchor, items, near)
  if not anchor or anchor.file == "" then return nil end
  local best, bestd
  for _, it in ipairs(items) do
    if it.file == anchor.file then
      local lo = it.offs - HSC.BEFORE * it.rate
      local hi = it.offs + (it.len + HSC.AFTER) * it.rate
      if anchor.src >= lo and anchor.src <= hi then
        local t = it.pos + (anchor.src - it.offs) / it.rate
        local d = math.abs(t - (near or t))
        if not bestd or d < bestd then best, bestd = t, d end
      end
    end
  end
  return best
end

-- "free" cue senza voce, "ok" al suo posto, "reanchor" trascinato a mano (si ancora al punto nuovo),
-- "lost" l'audio si e' spostato (o non c'e' piu') e il cue no.
function HSC.judge(anchor, pos, exp, prev_pos, prev_exp)
  if not anchor or anchor.file == "" then return "free" end
  if exp and math.abs(exp - pos) <= HSC.ATOL then return "ok" end
  local marker_moved = prev_pos ~= nil and math.abs(pos - prev_pos) > HSC.ATOL
  local audio_moved = (prev_exp == nil) ~= (exp == nil) or (exp ~= nil and prev_exp ~= nil and math.abs(exp - prev_exp) > HSC.ATOL)
  if marker_moved and not audio_moved then return "reanchor" end
  return "lost"
end

function HSC.serialize(anchors)
  local keys, out = {}, {}
  for k in pairs(anchors) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local a = anchors[k]
    out[#out + 1] = string.format("%d\t%.6f\t%s", k, a.src or 0, a.file or "")
  end
  return table.concat(out, "\n")
end

function HSC.deserialize(text)
  local anchors = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local k, src, file = line:match("^(%-?%d+)\t([%-%d%.]+)\t(.*)$")
    if k then anchors[tonumber(k)] = { src = tonumber(src) or 0, file = file } end
  end
  return anchors
end

-- Maschere dei cue fuori posto (indici in ordine di tempo): cue 0-31 e 32-63.
function HSC.masks(lost)
  local m1, m2 = 0, 0
  for i, v in ipairs(lost) do
    if v then
      if i <= 32 then m1 = m1 + 2 ^ (i - 1) else m2 = m2 + 2 ^ (i - 33) end
    end
  end
  return m1, m2
end

if HSC_SYNC_TEST or HSC_LIBRARY then return HSC end

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

local anchor_command               -- definita piu' sotto (ancore dei cue)
local function handle(base)
  if reaper.gmem_read(base + 69) ~= MAGIC then return end
  local seq = math.floor(reaper.gmem_read(base + 1) + 0.5)
  local ack = math.floor(reaper.gmem_read(base + 3) + 0.5)
  if seq == ack or seq == last_seq[base] then return end
  local cmd = math.floor(reaper.gmem_read(base) + 0.5)
  if cmd == 6 or cmd == 7 then
    -- RIALLINEA (6) / TIENI QUI (7) sul cue selezionato nel Carver
    if anchor_command then anchor_command(cmd == 6 and "realign" or "keep", math.floor(reaper.gmem_read(base + 2) + 0.5)) end
    reaper.gmem_write(base + 3, seq)
    last_seq[base] = seq
    return
  end
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

local voice_list = {}                 -- tracce voce di tutti i Carver (aggiornata da rescan)
local function rescan()
  local out, list = {}, {}
  scan_track(reaper.GetMasterTrack(0), -1, out, list)
  for i = 0, reaper.CountTracks(0) - 1 do scan_track(reaper.GetTrack(0, i), i, out, list) end
  bases, carvers = out, list
  local seen, vl = {}, {}
  for _, c in ipairs(carvers) do
    for _, t in ipairs(HSC.voice_tracks(c.track, c.fx)) do if not seen[t] then seen[t] = true; vl[#vl + 1] = t end end
  end
  voice_list = vl
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

-- ================================================================
-- Ancore nel progetto: stato, colori dei marker, maschere per i Carver
-- ================================================================
local LOST_COLOR = reaper.ColorToNative(232, 64, 56) | 0x1000000
local anchors, runtime, anchors_project = {}, {}, nil
local cue_markers_cache, items_cache = {}, {}

local function source_file(take)
  local src = reaper.GetMediaItemTake_Source(take)
  while src do
    local f = reaper.GetMediaSourceFileName(src, "") or ""
    if f ~= "" then return f end
    src = reaper.GetMediaSourceParent and reaper.GetMediaSourceParent(src) or nil
  end
  return ""
end

local function collect_voice_items()
  local items = {}
  for _, t in ipairs(voice_list) do
    local tn = reaper.GetMediaTrackInfo_Value(t, "IP_TRACKNUMBER")
    for i = 0, reaper.CountTrackMediaItems(t) - 1 do
      local item = reaper.GetTrackMediaItem(t, i)
      local take = reaper.GetActiveTake(item)
      if take and reaper.GetMediaItemInfo_Value(item, "B_MUTE") == 0 and not reaper.TakeIsMIDI(take) then
        local f = source_file(take)
        if f ~= "" then
          items[#items + 1] = { file = f, track = tn,
            pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION"), len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
            offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"),
            rate = math.max(0.0001, reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")) }
        end
      end
    end
  end
  return items
end

local function read_cue_markers()
  local list, i = {}, 0
  while true do
    local retval, isrgn, pos, _, name, num, color = reaper.EnumProjectMarkers3(0, i)
    if retval == 0 then break end
    if HSC.is_cue_marker(name, isrgn) then list[#list + 1] = { pos = pos, num = num, name = name, color = color } end
    i = i + 1
  end
  table.sort(list, function(a, b) return a.pos < b.pos end)
  return list
end

local function save_anchors()
  reaper.SetProjExtState(0, "ZP_HSC", "anchors", HSC.serialize(anchors))
end

local function anchors_tick()
  local proj = reaper.EnumProjects(-1)
  if proj ~= anchors_project then
    local _, text = reaper.GetProjExtState(0, "ZP_HSC", "anchors")
    anchors, runtime, anchors_project = HSC.deserialize(text), {}, proj
  end
  local markers, items = read_cue_markers(), collect_voice_items()
  cue_markers_cache, items_cache = markers, items
  local dirty, lost, present = false, {}, {}
  for i, m in ipairs(markers) do
    present[m.num] = true
    local a, rt = anchors[m.num], runtime[m.num] or {}
    runtime[m.num] = rt
    local st, exp
    if not a then
      a = HSC.make_anchor(m.pos, items); anchors[m.num] = a; dirty = true
      exp = HSC.expected(a, items, m.pos); st = (a.file == "") and "free" or "ok"
    else
      if a.file == "" then                -- cue libero: si aggancia appena ha una voce vicina
        local na = HSC.make_anchor(m.pos, items)
        if na.file ~= "" then a = na; anchors[m.num] = a; dirty = true end
      end
      exp = HSC.expected(a, items, m.pos)
      st = HSC.judge(a, m.pos, exp, rt.prev_pos, rt.prev_exp)
      if st == "reanchor" then
        a = HSC.make_anchor(m.pos, items); anchors[m.num] = a; dirty = true
        exp = HSC.expected(a, items, m.pos); st = (a.file == "") and "free" or "ok"
      end
    end
    rt.prev_pos, rt.prev_exp, rt.status, rt.exp = m.pos, exp, st, exp
    lost[i] = (st == "lost")
    local want = lost[i] and LOST_COLOR or MARKER_COLOR
    if m.color ~= want then reaper.SetProjectMarker3(0, m.num, false, m.pos, 0, m.name, want) end
  end
  for k in pairs(anchors) do if not present[k] then anchors[k] = nil; runtime[k] = nil; dirty = true end end
  if dirty then save_anchors() end
  local m1, m2 = HSC.masks(lost)
  for _, c in ipairs(carvers) do
    if c.fx < 32 then
      local track_base = c.base - c.fx * FX_STRIDE
      reaper.gmem_write(track_base + 4032 + c.fx * 2, m1)
      reaper.gmem_write(track_base + 4033 + c.fx * 2, m2)
    end
  end
end

-- RIALLINEA / TIENI QUI su un cue (indice in ordine di tempo) o su tutti quelli fuori posto.
-- Restituisce quanti cue ha toccato.
anchor_command = function(kind, index)
  anchors_tick()
  local targets = {}
  for i, m in ipairs(cue_markers_cache) do
    local rt = runtime[m.num]
    if (index == nil or index == i - 1) and rt and rt.status == "lost" then targets[#targets + 1] = m end
  end
  if #targets == 0 then return 0 end
  local done = 0
  reaper.Undo_BeginBlock2(0)
  for _, m in ipairs(targets) do
    local rt = runtime[m.num]
    if kind == "realign" and rt.exp then
      reaper.SetProjectMarker3(0, m.num, false, rt.exp, 0, m.name, MARKER_COLOR)
      rt.prev_pos = rt.exp; done = done + 1
    elseif kind == "keep" then
      anchors[m.num] = HSC.make_anchor(m.pos, items_cache); runtime[m.num] = nil; done = done + 1
    end
  end
  save_anchors()
  reaper.UpdateTimeline()
  reaper.Undo_EndBlock2(0, kind == "realign" and "ZP HSC: riallinea cue" or "ZP HSC: tieni il cue qui", -1)
  return done
end

-- Richieste dalle azioni da tastiera (ExtState ZP_HSC/req = "realign_all|seq").
local last_req = ""
local function serve_requests()
  local req = reaper.GetExtState("ZP_HSC", "req")
  if req == "" or req == last_req then return end
  last_req = req
  local what, seq = req:match("^([%w_]+)|(.+)$")
  if what == "realign_all" then
    local n = anchor_command("realign", nil)
    reaper.SetExtState("ZP_HSC", "rep", seq .. "|" .. n, false)
  end
end

local function run()
  local now = reaper.time_precise()
  if now - last_scan >= 1.0 then rescan(); last_scan = now end
  for _, base in ipairs(bases) do handle(base) end
  if now - last_sync >= 0.25 then sync(); anchors_tick(); serve_requests(); last_sync = now end
  reaper.defer(run)
end
-- simulazione fuori REAPER (test): espone i passi senza avviare il ciclo
if HSC_SYNC_SIM then return { sync = sync, rescan = rescan, anchors_tick = anchors_tick, anchor_command = anchor_command, serve_requests = serve_requests } end
run()
