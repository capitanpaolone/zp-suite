-- @description ZP Harmonic Space Carver Cue Navigator (background helper)
-- @version 1.9
-- @author Paolo Balestri / Codex
-- @about Collega i Carver a REAPER: salti tra i cue, punto del cursore a trasporto fermo,
--   verifica del routing sidechain e cue come marker #HSC sul righello (seguono l'editing).
-- @changelog
--   1.9: i numeri unici si scrivono solo nel progetto attivo: i progetti aperti in sottofondo non
--        risultano mai modificati (in caso di doppione si rinumera il Carver del progetto attivo).
--   1.8: assegna a ogni Carver un numero unico fra tutti i progetti aperti (parametro "HSC Slot",
--        salvato nel Carver): due progetti in schede, o un Carver copiato con la traccia, non si
--        mescolano piu'. Le correzioni automatiche dei marker #HSC non creano punti di undo
--        (Ctrl+Z torna indietro nel lavoro senza incastrarsi); Riallinea e Tieni qui restano annullabili.
--   1.7: i cue si aggiungono e si tolgono solo dal Carver: un marker #HSC cancellato a mano torna,
--        uno aggiunto a mano sparisce; spostarli resta libero. Marker #HSC in lane 4 (fuori dalle
--        lane del Gestore Progetto). Un solo helper alla volta (l'ultimo avviato prende il posto).
--        Progetto riconosciuto anche dal file: un progetto vecchio aperto nella stessa scheda non
--        perde i cue. Riallinea non riparte al riavvio. Avviso (non bloccante) se ci sono cue rossi.
--        Ancore ricalcolate solo quando il progetto cambia.
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

-- Regole (1.7, decise da Paolo): i cue nascono e si tolgono SOLO dal Carver (pulsanti e tasti);
-- i marker #HSC si possono solo spostare (a mano, ripple). Un #HSC cancellato da fuori torna al suo
-- posto, uno aggiunto da fuori viene tolto. Marker = { num, pos }.

-- Accoppia due elenchi ordinati entro la tolleranza. Restituisce gli scompagnati di a e di b.
function HSC.unmatched(a, b, key_a, key_b)
  local la, lb = {}, {}
  for _, v in ipairs(a) do la[#la + 1] = v end
  for _, v in ipairs(b) do lb[#lb + 1] = v end
  local ka = key_a or function(v) return v end
  local kb = key_b or function(v) return v end
  table.sort(la, function(x, y) return ka(x) < ka(y) end)
  table.sort(lb, function(x, y) return kb(x) < kb(y) end)
  local ua, ub, i, j = {}, {}, 1, 1
  while i <= #la and j <= #lb do
    local d = ka(la[i]) - kb(lb[j])
    if math.abs(d) <= HSC.TOL then i, j = i + 1, j + 1
    elseif d < 0 then ua[#ua + 1] = la[i]; i = i + 1
    else ub[#ub + 1] = lb[j]; j = j + 1 end
  end
  for k = i, #la do ua[#ua + 1] = la[k] end
  for k = j, #lb do ub[#ub + 1] = lb[k] end
  return ua, ub
end

local function mpos(m) return m.pos end

-- Primo giro su un progetto: comanda il Carver. Marker senza cue = da togliere, cue senza marker = da creare.
function HSC.first_sync(markers, cues)
  local um, uc = HSC.unmatched(markers, cues, mpos)
  local del = {}
  for _, m in ipairs(um) do del[#del + 1] = m.num end
  return { delete = del, create = uc }
end

-- Lato marker: confronta i marker di adesso con quelli dell'ultimo giro (synced: num -> pos).
-- Spostati: accettati. Spariti: da rimettere (restore {pos, from}). Nuovi: da togliere (delete).
-- Rinumerati (sparito + nuovo nello stesso punto): stessa cosa, chiave cambiata (rekey old -> new).
function HSC.marker_side(synced, markers)
  local present, extra, used = {}, {}, {}
  for _, m in ipairs(markers) do present[m.num] = m.pos end
  for _, m in ipairs(markers) do if synced[m.num] == nil then extra[#extra + 1] = m end end
  local rekey, restore = {}, {}
  local nums = {}
  for num in pairs(synced) do nums[#nums + 1] = num end
  table.sort(nums)
  for _, num in ipairs(nums) do
    if present[num] == nil then
      local hit
      for k, e in ipairs(extra) do
        if not used[k] and math.abs(e.pos - synced[num]) <= HSC.TOL then hit = k; break end
      end
      if hit then used[hit] = true; rekey[num] = extra[hit].num
      else restore[#restore + 1] = { pos = synced[num], from = num } end
    end
  end
  local del = {}
  for k, e in ipairs(extra) do if not used[k] then del[#del + 1] = e.num end end
  return { rekey = rekey, restore = restore, delete = del }
end

-- Lato Carver: cosa e' cambiato nel Carver rispetto all'elenco che doveva avere (expected).
-- Cue aggiunti -> marker da creare; cue tolti -> marker (vicino a quel tempo) da togliere.
function HSC.carver_side(expected, cues, markers)
  local removed, added = HSC.unmatched(expected, cues)
  local create, del = {}, {}
  for _, t in ipairs(added) do
    local exists = false
    for _, m in ipairs(markers) do if math.abs(m.pos - t) <= HSC.TOL then exists = true; break end end
    if not exists then create[#create + 1] = t end
  end
  for _, t in ipairs(removed) do
    for _, m in ipairs(markers) do
      if math.abs(m.pos - t) <= HSC.TOL then del[#del + 1] = m.num; break end
    end
  end
  return { create = create, delete = del }
end

-- Elenco per il Carver: posizioni dei marker, ordinate, al massimo 64.
function HSC.positions(markers)
  local list = {}
  for _, m in ipairs(markers) do list[#list + 1] = m.pos end
  table.sort(list)
  while #list > HSC.MAX do table.remove(list) end
  return list
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
-- Numeri unici (Carver 2.6.3+): blocchi da 76 celle da 8310000 (+72/+73 maschere dei cue rossi).
local SLOT_BASE, SLOT_STRIDE, SLOT_MAX = 8310000, 76, 900

local function is_carver(track, fx)
  local ok, name = reaper.TrackFX_GetFXName(track, fx, "")
  return ok and name and name:lower():find("harmonic space carver", 1, true) ~= nil
end

local function slot_param(track, fx)
  for p = reaper.TrackFX_GetNumParams(track, fx) - 1, 0, -1 do
    local _, pname = reaper.TrackFX_GetParamName(track, fx, p, "")
    if pname and pname:find("HSC Slot", 1, true) then
      return p, math.floor(reaper.TrackFX_GetParam(track, fx, p) + 0.5)
    end
  end
end

-- Indirizzo gmem e indirizzo delle maschere, come li calcola il Carver.
local function addresses(track_index, fx, slot)
  if slot and slot >= 1 and slot <= SLOT_MAX then
    local base = SLOT_BASE + slot * SLOT_STRIDE
    return base, base + 72
  end
  local base = BASE_START + ((track_index + 2) * TRACK_STRIDE) + (fx * FX_STRIDE)
  return base, (fx < 32) and (base - fx * FX_STRIDE + 4032 + fx * 2) or nil
end

-- Numeri unici. L'helper scrive SOLO nel progetto attivo (i progetti in sottofondo non risultano mai
-- modificati): i Carver in sottofondo tengono i loro numeri, e se un Carver del progetto attivo ne ha
-- uno gia' usato (o nessuno) prende il primo libero. Restituisce i Carver del progetto attivo.
local function assign_slots()
  local active = reaper.EnumProjects(-1)
  local all = {}
  local function scan_proj(proj, is_active)
    local function scan(track, idx)
      for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
        if is_carver(track, fx) then
          local pidx, slot = slot_param(track, fx)
          all[#all + 1] = { track = track, idx = idx, fx = fx, pidx = pidx, slot = slot or 0, active = is_active }
        end
      end
    end
    scan(reaper.GetMasterTrack(proj), -1)
    for i = 0, reaper.CountTracks(proj) - 1 do scan(reaper.GetTrack(proj, i), i) end
  end
  local pi = 0
  while true do
    local proj = reaper.EnumProjects(pi)
    if not proj then break end
    if proj ~= active then scan_proj(proj, false) end
    pi = pi + 1
  end
  scan_proj(active, true)
  local used = {}
  for _, c in ipairs(all) do                -- prima i numeri dei progetti in sottofondo
    if not c.active and c.slot >= 1 and c.slot <= SLOT_MAX then used[c.slot] = true end
  end
  for _, c in ipairs(all) do                -- poi quelli del progetto attivo, se liberi
    if c.active then
      if c.pidx and c.slot >= 1 and c.slot <= SLOT_MAX and not used[c.slot] then used[c.slot] = true else c.need = true end
    end
  end
  local free = 1
  for _, c in ipairs(all) do
    if c.need and c.pidx then
      while used[free] do free = free + 1 end
      if free <= SLOT_MAX then
        reaper.TrackFX_SetParam(c.track, c.fx, c.pidx, free)
        c.slot = free; used[free] = true
      end
    end
  end
  local list = {}
  for _, c in ipairs(all) do if c.active then list[#list + 1] = c end end
  return list
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
  for _, c in ipairs(assign_slots()) do
    local slot = (c.pidx and c.slot >= 1) and c.slot or nil
    local base, mask = addresses(c.idx, c.fx, slot)
    if base >= 0 and base < SLOT_BASE + (SLOT_MAX + 1) * SLOT_STRIDE then
      out[#out + 1] = base
      list[#list + 1] = { base = base, mask = mask, track = c.track, fx = c.fx }
    end
  end
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
-- Un solo helper alla volta: l'ultimo avviato prende il posto dei precedenti.
-- ================================================================
local MY_ID = string.format("%.6f-%d", reaper.time_precise(), math.random(1, 1000000))
local function i_am_owner() return reaper.GetExtState("ZP_HSC", "owner") == MY_ID end

-- Messaggio non bloccante: OSARA se c'e', e un suggerimento vicino al mouse.
local tip_until = 0
local function notify(msg)
  if reaper.osara_outputMessage then reaper.osara_outputMessage(msg) end
  local x, y = reaper.GetMousePosition()
  reaper.TrackCtl_SetToolTip(msg, x + 14, y + 14, true)
  tip_until = reaper.time_precise() + 3
end

-- ================================================================
-- Marker #HSC: lettura, creazione (in lane 4), cancellazione
-- ================================================================
local MB = 3800                          -- casella comune dei comandi al Carver (vedi il JSFX)
local MARKER_COLOR = reaper.ColorToNative(36, 184, 212) | 0x1000000
local LOST_COLOR = reaper.ColorToNative(232, 64, 56) | 0x1000000
local HSC_LANE = 3                       -- lane 4 (REAPER le conta da 0): fuori dalle lane 1-2 del 17

local function read_cue_markers()
  local list, i = {}, 0
  while true do
    local retval, isrgn, pos, _, name, num, color = reaper.EnumProjectMarkers3(0, i)
    if retval == 0 then break end
    if HSC.is_cue_marker(name, isrgn) then list[#list + 1] = { pos = pos, num = num, name = name, color = color, idx = i } end
    i = i + 1
  end
  table.sort(list, function(a, b) return a.pos < b.pos end)
  return list
end

local function put_in_lane(enum_idx)
  if not (reaper.GetRegionOrMarker and reaper.SetRegionOrMarkerInfo_Value and reaper.GetRegionOrMarkerInfo_Value) then return end
  local entry = reaper.GetRegionOrMarker(0, enum_idx, "")
  if entry and reaper.GetRegionOrMarkerInfo_Value(0, entry, "I_LANENUMBER") ~= HSC_LANE then
    reaper.SetRegionOrMarkerInfo_Value(0, entry, "I_LANENUMBER", HSC_LANE)
  end
end

local function lane_sweep()
  for _, m in ipairs(read_cue_markers()) do put_in_lane(m.idx) end
end

-- Applica le modifiche ai marker. create = { tempo | {pos, from} }. Niente punti di undo: sono
-- correzioni automatiche (i cue li governa il Carver); un punto di undo qui incastrerebbe Ctrl+Z
-- (annulli, l'helper rimette, nuovo punto, e non torni mai piu' indietro).
-- Restituisce la mappa vecchio numero -> nuovo numero dei marker rimessi.
local function apply_marker_ops(create, delete)
  if #create == 0 and #delete == 0 then return {} end
  local moved = {}
  reaper.PreventUIRefresh(1)
  for _, num in ipairs(delete) do reaper.DeleteProjectMarker(0, num, false) end
  for _, c in ipairs(create) do
    local pos = type(c) == "table" and c.pos or c
    local num = reaper.AddProjectMarker2(0, false, pos, 0, HSC.NAME, -1, MARKER_COLOR)
    if type(c) == "table" and c.from and num and num >= 0 then moved[c.from] = num end
  end
  lane_sweep()
  reaper.PreventUIRefresh(-1)
  reaper.UpdateTimeline()
  return moved
end

local function cue_times(base)
  local list = {}
  for _, c in ipairs(read_cues(base)) do list[#list + 1] = c.time end
  return list
end

-- ================================================================
-- Ancore (definite qui perche' la sincronizzazione le rinumera)
-- ================================================================
local anchors, runtime = {}, {}
local function rekey_anchor(old, new)
  if old == new then return end
  anchors[new], anchors[old] = anchors[old], nil
  runtime[new], runtime[old] = runtime[old], nil
end

-- ================================================================
-- Sincronizzazione (ogni 0,25 s)
-- ================================================================
local synced, expected, pending, sync_key = nil, {}, nil, nil
local last_sync, last_mb_seen = -1, 0
local save_anchors                        -- definita con le ancore

local function project_key()
  local proj, fn = reaper.EnumProjects(-1)
  return tostring(proj) .. "|" .. tostring(fn or "")
end

local function send_list(base, list)
  local seq = math.floor(reaper.gmem_read(MB + 3) + 0.5) + 1
  reaper.gmem_write(MB + 10, #list)
  for i = 1, HSC.MAX do reaper.gmem_write(MB + 10 + i, list[i] or -1) end
  reaper.gmem_write(MB, base)
  reaper.gmem_write(MB + 1, 5)
  reaper.gmem_write(MB + 3, seq)
  pending = { base = base, seq = seq, t = reaper.time_precise(), list = list }
end

local function alive_carvers()
  local out = {}
  for _, c in ipairs(carvers) do if reaper.gmem_read(c.base + 69) == MAGIC then out[#out + 1] = c end end
  return out
end

local function sync()
  local key = project_key()
  if key ~= sync_key then synced, expected, pending, sync_key = nil, {}, nil, key end
  if pending then
    if math.floor(reaper.gmem_read(MB + 4) + 0.5) == pending.seq then
      expected[pending.base] = pending.list; pending = nil
    elseif reaper.time_precise() - pending.t > 1.0 then
      pending = nil                       -- Carver fermo: si riprova al prossimo giro
    end
    return
  end
  -- la casella e' occupata da un'azione da tastiera in corso: si aspetta (al massimo 1 s)
  if math.floor(reaper.gmem_read(MB + 4) + 0.5) ~= math.floor(reaper.gmem_read(MB + 3) + 0.5)
     and reaper.time_precise() - last_mb_seen < 1.0 then return end
  last_mb_seen = reaper.time_precise()

  local list = alive_carvers()
  if #list == 0 then return end           -- senza Carver i marker non si toccano
  local markers = read_cue_markers()
  local changed_anchors = false

  if synced == nil then
    -- primo giro su questo progetto: comanda il Carver (mai cancellare cue da qui)
    local ops = HSC.first_sync(markers, cue_times(list[1].base))
    apply_marker_ops(ops.create, ops.delete)
    lane_sweep()
    markers = read_cue_markers()
    expected[list[1].base] = HSC.positions(markers)
  else
    -- lato marker: spostamenti accettati, cancellazioni rimesse, aggiunte tolte
    local ops = HSC.marker_side(synced, markers)
    for old, new in pairs(ops.rekey) do rekey_anchor(old, new); changed_anchors = true end
    if #ops.restore > 0 or #ops.delete > 0 then
      local moved = apply_marker_ops(ops.restore, ops.delete)
      for old, new in pairs(moved) do rekey_anchor(old, new); changed_anchors = true end
      notify(#ops.restore > 0
        and string.format("Cue rimessi sul righello: %d. I cue si tolgono dal Carver (ADD/REMOVE, CLEAR ALL).", #ops.restore)
        or "I cue si aggiungono dal Carver: marker #HSC aggiunto a mano tolto.")
      markers = read_cue_markers()
    end
    -- lato Carver: cue aggiunti o tolti con i pulsanti o i tasti
    for _, c in ipairs(list) do
      if expected[c.base] then
        local cs = HSC.carver_side(expected[c.base], cue_times(c.base), markers)
        if #cs.create > 0 or #cs.delete > 0 then
          apply_marker_ops(cs.create, cs.delete)
          markers = read_cue_markers()
          expected[c.base] = HSC.positions(markers)
        end
      end
    end
  end
  synced = {}
  for _, m in ipairs(markers) do synced[m.num] = m.pos end
  if changed_anchors and save_anchors then save_anchors() end

  -- ogni Carver riceve le posizioni dei marker (un Carver per giro mentre si aspetta l'ack)
  local target = HSC.positions(markers)
  for _, c in ipairs(list) do
    if not HSC.same(HSC.sorted(cue_times(c.base)), target) then send_list(c.base, target); return end
    expected[c.base] = target
  end
end

-- ================================================================
-- Ancore nel progetto: stato, colori dei marker, maschere per i Carver
-- ================================================================
local anchors_key, voice_items_state = nil, -1
local cue_markers_cache, items_cache = {}, {}
local lost_count_said = 0

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

save_anchors = function()
  reaper.SetProjExtState(0, "ZP_HSC", "anchors", HSC.serialize(anchors))
end

-- Gira quando il progetto cambia (stato di REAPER), e comunque ogni 2 s.
local last_state, last_full = -1, -1
local function anchors_tick(force)
  local key = project_key()
  if key ~= anchors_key then
    local _, text = reaper.GetProjExtState(0, "ZP_HSC", "anchors")
    anchors, runtime, anchors_key, last_state = HSC.deserialize(text), {}, key, -1
    lane_sweep()
  end
  local state = reaper.GetProjectStateChangeCount(0)
  local now = reaper.time_precise()
  if not force and state == last_state and now - last_full < 2.0 then return end
  last_state, last_full = state, now
  local markers, items = read_cue_markers(), collect_voice_items()
  cue_markers_cache, items_cache = markers, items
  local dirty, lost, present, lost_n = false, {}, {}, 0
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
    if lost[i] then lost_n = lost_n + 1 end
    local want = lost[i] and LOST_COLOR or MARKER_COLOR
    if m.color ~= want then reaper.SetProjectMarker3(0, m.num, false, m.pos, 0, m.name, want) end
  end
  for k in pairs(anchors) do if not present[k] then anchors[k] = nil; runtime[k] = nil; dirty = true end end
  if dirty then save_anchors() end
  -- avviso forte ma non bloccante quando aumentano i cue fuori posto
  if lost_n > lost_count_said then
    notify(string.format("Cue fuori posto: %d. Scattano nel punto sbagliato finche' non li riallinei.", lost_n))
  end
  lost_count_said = lost_n
  local m1, m2 = HSC.masks(lost)
  for _, c in ipairs(carvers) do
    if c.mask then reaper.gmem_write(c.mask, m1); reaper.gmem_write(c.mask + 1, m2) end
  end
end

-- RIALLINEA / TIENI QUI su un cue (indice in ordine di tempo) o su tutti quelli fuori posto.
-- Restituisce quanti cue ha toccato.
anchor_command = function(kind, index)
  anchors_tick(true)
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
  anchors_tick(true)
  return done
end

-- Richieste dalle azioni da tastiera (ExtState ZP_HSC/req = "realign_all|seq").
-- La richiesta si cancella dopo l'uso; una richiesta trovata all'avvio e' vecchia e si ignora.
local function serve_requests()
  local req = reaper.GetExtState("ZP_HSC", "req")
  if req == "" then return end
  reaper.DeleteExtState("ZP_HSC", "req", false)
  local what, seq = req:match("^([%w_]+)|(.+)$")
  if what == "realign_all" then
    local n = anchor_command("realign", nil)
    reaper.SetExtState("ZP_HSC", "rep", seq .. "|" .. n, false)
  end
end

local function run()
  if not i_am_owner() then return end     -- un helper piu' nuovo ha preso il posto: questo si ferma
  local now = reaper.time_precise()
  if now - last_scan >= 1.0 then rescan(); last_scan = now end
  for _, base in ipairs(bases) do handle(base) end
  if now - last_sync >= 0.25 then sync(); anchors_tick(); serve_requests(); last_sync = now end
  if tip_until > 0 and now > tip_until then reaper.TrackCtl_SetToolTip("", 0, 0, true); tip_until = 0 end
  reaper.defer(run)
end

reaper.SetExtState("ZP_HSC", "owner", MY_ID, false)
reaper.DeleteExtState("ZP_HSC", "req", false)   -- richieste rimaste da prima: vecchie
-- simulazione fuori REAPER (test): espone i passi senza avviare il ciclo
if HSC_SYNC_SIM then return { sync = sync, rescan = rescan, anchors_tick = anchors_tick, anchor_command = anchor_command, serve_requests = serve_requests, run_once = function() local d = reaper.defer; reaper.defer = function() end; run(); reaper.defer = d end, id = MY_ID } end
run()
