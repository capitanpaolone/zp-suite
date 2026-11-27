-- @noindex

-- ZP Studio Suite for REAPER
-- ZP_SRT_Engine.lua: motore unificato per sottotitoli SRT / WebVTT / Excel (.xlsx)
-- e gestione delle tracce testi Rythmo Band in REAPER.
--
-- La prima parte del modulo è logica pura (nessuna dipendenza da REAPER) ed è
-- collaudabile direttamente da terminale con lua.

local M = {}

M.VERSION = "2.0.0"
M.SUBTITLE_TRACK_NAME = "Rythmo Band Testi"
M.VIDEO_TRACK_NAME = "VIDEO"
M.VOX_TRACK_NAME = "VOX"
M.SRT_TEMPLATE_NAME = "SRT Track.RTrackTemplate"

M.COLOR_SUBS    = 0x3498DB
M.COLOR_OVERLAP = 0xE53935
M.COLOR_VIDEO   = 0x7E57C2
M.COLOR_VOX     = 0x26A69A
M.COLOR_BKP     = 0x546E7A

---------------------------------------------------------------------------
-- 1. UTILITA' STRINGHE E PERCORSI (PURE)
---------------------------------------------------------------------------

function M.trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.basename(path)
  path = tostring(path or "")
  return path:match("[^/\\]+$") or path
end

function M.dirname(path)
  path = tostring(path or "")
  return path:match("^(.*)[/\\][^/\\]+$") or ""
end

function M.ext_lower(path)
  return (tostring(path or ""):match("%.([^%.\\/]+)$") or ""):lower()
end

function M.stem(path)
  local name = M.basename(path)
  return (name:gsub("%.[^%.]+$", ""))
end

function M.safe_filename(name)
  name = M.trim(name):gsub('[<>:"/\\|%?%*]', "_")
  name = M.trim(name)
  return name ~= "" and name or "sottotitoli"
end

local VIDEO_EXT = { mp4 = true, mov = true, m4v = true, mkv = true, avi = true, webm = true }
local SUB_EXT   = { srt = true, vtt = true, xlsx = true }

function M.is_video_file(path)
  return VIDEO_EXT[M.ext_lower(path)] == true
end

function M.is_subtitle_file(path)
  return SUB_EXT[M.ext_lower(path)] == true
end

---------------------------------------------------------------------------
-- 2. PARSING E FORMATTAZIONE SRT / WEBVTT (PURE)
---------------------------------------------------------------------------

function M.parse_time(raw)
  local text = M.trim(raw)
  if text == "" then return nil end
  local clean = text:gsub(",", ".")
  local h, m, s, ms = clean:match("^(%d+):(%d%d):(%d%d)%.(%d%d%d)$")
  if h then
    return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + tonumber(ms) / 1000.0
  end
  local m2, s2, ms2 = clean:match("^(%d%d):(%d%d)%.(%d%d%d)$")
  if m2 then
    return tonumber(m2) * 60 + tonumber(s2) + tonumber(ms2) / 1000.0
  end
  local h3, m3, s3 = clean:match("^(%d+):(%d%d):(%d%d)$")
  if h3 then
    return tonumber(h3) * 3600 + tonumber(m3) * 60 + tonumber(s3)
  end
  return nil
end

function M.format_time(seconds)
  local total_ms = math.max(0, math.floor((tonumber(seconds) or 0) * 1000.0 + 0.5))
  local h = total_ms // 3600000
  local rem = total_ms % 3600000
  local m = rem // 60000
  rem = rem % 60000
  local s = rem // 1000
  local ms = rem % 1000
  return string.format("%02d:%02d:%02d,%03d", h, m, s, ms)
end

local FORMAT_TAGS = {
  i = true, b = true, u = true, s = true, c = true, v = true,
  font = true, lang = true, ruby = true, rt = true
}

function M.clean_cue_text(text)
  text = tostring(text or ""):gsub("^\239\187\191", "")
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  local function voice(name)
    name = M.trim(name)
    return name ~= "" and (name .. ": ") or ""
  end
  text = text:gsub("<[vV]%s+([^>]-)%s*>", voice):gsub("<[vV]%.[^%s>]*%s+([^>]-)%s*>", voice)
  text = text:gsub("<(/?)([%a]*)([^>]*)>", function(slash, name, rest)
    if FORMAT_TAGS[name:lower()] and (rest == "" or rest:match("^[%s%.]")) then return "" end
    if name == "" and slash == "" and rest:match("^%d[%d:%.]*$") then return "" end
  end)
  text = text:gsub("{\\[^}]*}", "") -- tag ASS/SSA {\\an8} ecc.
  text = text:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&nbsp;", " ")
  local lines = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = M.trim(line)
  end
  return M.trim(table.concat(lines, "\n"))
end

local function parse_timing_line(line)
  local lhs, rhs = line:match("^%s*([%d:,%.]+)%s*%-%->%s*([%d:,%.]+)")
  if not lhs or not rhs then return nil, nil end
  local a, b = M.parse_time(lhs), M.parse_time(rhs)
  if not a or not b then return nil, nil end
  return a, b
end

function M.parse_subtitles(content, custom_clean)
  if type(content) ~= "string" then return nil, "Contenuto sottotitoli vuoto." end
  local clean_fn = custom_clean or M.clean_cue_text
  local norm = content:gsub("^\239\187\191", ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  if M.trim(norm) == "" then return nil, "File sottotitoli vuoto." end

  local blocks, current = {}, {}
  for line in (norm .. "\n\n"):gmatch("([^\n]*)\n") do
    if M.trim(line) == "" then
      if #current > 0 then
        blocks[#blocks + 1] = current
        current = {}
      end
    else
      current[#current + 1] = line
    end
  end

  local cues = {}
  for _, blk in ipairs(blocks) do
    local first = M.trim(blk[1] or "")
    local skip = false
    if first:match("^WEBVTT") or first:match("^NOTE") or first:match("^STYLE") or first:match("^REGION") then
      -- Se nel blocco WEBVTT c'è subito un cue attaccato sotto senza riga vuota, cerchiamo la freccia
      local has_arrow = false
      for k = 2, #blk do
        if blk[k]:find("-->", 1, true) then has_arrow = true; break end
      end
      if not has_arrow then skip = true end
    end

    if not skip then
      local timing_idx = nil
      for k = 1, math.min(3, #blk) do
        if blk[k]:find("-->", 1, true) then
          timing_idx = k
          break
        end
      end
      if timing_idx then
        local start_pos, end_pos = parse_timing_line(blk[timing_idx])
        if start_pos and end_pos and end_pos > start_pos then
          local cue_id = timing_idx > 1 and M.trim(blk[timing_idx - 1]) or tostring(#cues + 1)
          local raw_lines = {}
          for k = timing_idx + 1, #blk do
            raw_lines[#raw_lines + 1] = blk[k]
          end
          local text = clean_fn(table.concat(raw_lines, "\n"))
          if text ~= "" then
            cues[#cues + 1] = {
              start_pos = start_pos,
              end_pos   = end_pos,
              text      = text,
              cue_id    = cue_id,
              order     = #cues + 1
            }
          end
        end
      end
    end
  end

  if #cues == 0 then
    return nil, "Nessuna battuta valida trovata nel file."
  end

  table.sort(cues, function(a, b)
    if a.start_pos ~= b.start_pos then return a.start_pos < b.start_pos end
    if a.end_pos ~= b.end_pos then return a.end_pos < b.end_pos end
    return (a.order or 0) < (b.order or 0)
  end)

  for i, c in ipairs(cues) do
    c.index = i
  end
  return cues
end

function M.format_srt(cues)
  local out = {}
  for i, cue in ipairs(cues or {}) do
    local s = cue.start_pos or cue.start or 0
    local e = cue.end_pos or cue.stop or cue.finish or (s + 1)
    if e <= s then e = s + 0.20 end
    local text = M.trim(tostring(cue.text or ""):gsub("\r\n", "\n"):gsub("\r", "\n"))
    if text ~= "" then
      out[#out + 1] = string.format("%d\n%s --> %s\n%s\n", #out + 1, M.format_time(s), M.format_time(e), text)
    end
  end
  return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- 3. METRICHE TESTO E SOVRAPPOSIZIONI (PURE)
---------------------------------------------------------------------------

function M.count_words(text)
  local n = 0
  local clean = tostring(text or ""):gsub("\r\n", " "):gsub("[\r\n\t]+", " ")
  for token in clean:gmatch("%S+") do
    if token:find("[%w\128-\255]") then
      n = n + 1
    end
  end
  return n
end

function M.count_lines(text)
  local s = M.trim(tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n"))
  if s == "" then return 0 end
  local n = 0
  for line in (s .. "\n"):gmatch("([^\n]*)\n") do
    if M.trim(line) ~= "" then n = n + 1 end
  end
  return math.max(1, n)
end

function M.char_length(text)
  local clean = tostring(text or ""):gsub("[\r\n]+", " "):gsub("%s+", " ")
  clean = M.trim(clean)
  local ok, len = pcall(utf8.len, clean)
  if ok and len then return len end
  return #clean
end

function M.cps(text, dur)
  local d = math.max(0.1, tonumber(dur) or 0.1)
  return M.char_length(text) / d
end

-- mode: "lane" (mantiene i tempi, segna cue.overlap=true per la corsia rossa)
--       "trim" (accorcia la battuta precedente o sposta di 10 ms per evitare accavallamenti)
function M.resolve_overlaps(cues, mode)
  mode = mode or "lane"
  local out = {}
  for i, c in ipairs(cues or {}) do
    out[i] = {
      start_pos = c.start_pos,
      end_pos   = c.end_pos,
      text      = c.text,
      cue_id    = c.cue_id,
      index     = c.index or i,
      overlap   = false
    }
  end
  if #out <= 1 then return out, 0 end

  local overlap_count = 0
  if mode == "trim" then
    for i = 2, #out do
      local prev = out[i - 1]
      local cur = out[i]
      if cur.start_pos < prev.end_pos - 0.001 then
        overlap_count = overlap_count + 1
        local trimmed_prev_end = cur.start_pos - 0.010
        if trimmed_prev_end - prev.start_pos >= 0.18 then
          prev.end_pos = trimmed_prev_end
        else
          prev.end_pos = math.max(prev.start_pos + 0.18, cur.start_pos)
          cur.start_pos = prev.end_pos + 0.005
          if cur.end_pos - cur.start_pos < 0.18 then
            cur.end_pos = cur.start_pos + 0.18
          end
        end
      end
    end
  else
    local max_end = out[1].end_pos
    for i = 2, #out do
      local cur = out[i]
      if cur.start_pos < max_end - 0.001 then
        cur.overlap = true
        overlap_count = overlap_count + 1
      end
      if cur.end_pos > max_end then max_end = cur.end_pos end
    end
  end
  return out, overlap_count
end

---------------------------------------------------------------------------
-- 4. ACCORPA ITEM BREVI ("SMART SHORT-CUE COALESCER" — PURE)
---------------------------------------------------------------------------
-- Risolve il caso tipico dei sottotitoli automatici (Whisper / MacWhisper / YouTube):
-- micro-item da 1 o 2 parole rimasti isolati prima, dopo o dentro una battuta più lunga
-- (anche di 2-3 righe dello stesso dialogo).

local function extract_speaker_prefix(text)
  local first_line = tostring(text or ""):match("^%s*([^\r\n]+)") or ""
  -- Riconosce "MARIO: testo" o "Narratore: testo" all'inizio riga
  local role, rest = first_line:match("^([%a\128-\255][%w\128-\255%s'%.%-]-):%s+(.+)$")
  if role and #role <= 28 and not role:find("[%.!%?]") then
    return M.trim(role), rest
  end
  return nil, nil
end

local function starts_with_dialogue_dash(text)
  local s = M.trim(text)
  return s:match("^%-+%s+%S") ~= nil
    or s:match("^\226\128\147%s*%S") ~= nil -- en-dash –
    or s:match("^\226\128\148%s*%S") ~= nil -- em-dash —
end

local function ends_with_strong_stop(text)
  local s = M.trim(text)
  -- Esclude abbreviazioni comuni di 1-2 lettere tipo "Sig." o "Dr."? Per una parola singola breve tipo "tardi." è fine frase!
  return s:match("[%.!%?][\'\")%]\194\187]*$") ~= nil
    or s:match("\226\128\166[\'\")%]\194\187]*$") ~= nil -- ellissi …
end

function M.is_short_cue(text, dur, opts)
  opts = opts or {}
  local max_words = tonumber(opts.max_words) or 2
  local min_dur   = tonumber(opts.min_dur) or 1.05
  local words = M.count_words(text)
  if words == 0 then return false end
  if words <= max_words then return true end
  if dur and dur < min_dur and words <= (max_words + 1) then return true end
  return false
end

local function join_two_texts(left_text, right_text)
  local lt = M.trim(left_text)
  local rt = M.trim(right_text)
  if lt == "" then return rt end
  if rt == "" then return lt end
  local l_role = extract_speaker_prefix(lt)
  local r_role = extract_speaker_prefix(rt)
  if l_role and r_role and l_role:lower() == r_role:lower() then
    -- Toglie l'etichetta personaggio ripetuta nella seconda parte
    rt = rt:gsub("^%s*[^:\r\n]+:%s*", "", 1)
  end
  return lt .. " " .. rt
end

local function refresh_group_meta(g)
  local txt = M.trim(g.text)
  g.words     = M.count_words(txt)
  g.chars     = M.char_length(txt)
  local role  = extract_speaker_prefix(txt)
  g.role      = role
  g.role_lc   = role and role:lower() or nil
  g.has_dash  = starts_with_dialogue_dash(txt)
  g.ends_stop = ends_with_strong_stop(txt)
end

local function can_merge_pair(left_g, right_g, opts)
  if not left_g or not right_g then return false end
  if (left_g.sync_key and left_g.sync_key ~= "") or (right_g.sync_key and right_g.sync_key ~= "") then
    return false
  end
  local max_gap   = tonumber(opts.max_gap) or 0.90
  local max_chars = tonumber(opts.max_chars) or 240
  local max_dur   = tonumber(opts.max_dur) or 12.0

  local gap = right_g.start_pos - left_g.end_pos
  if gap > max_gap or gap < -1.0 then return false end

  -- Non attraversa un trattino di cambio interlocutore sulla seconda battuta
  if right_g.has_dash then return false end

  -- Non fonde due personaggi espliciti diversi (es. MARIO: vs LAURA:)
  if left_g.role_lc and right_g.role_lc and left_g.role_lc ~= right_g.role_lc then
    return false
  end
  if not left_g.role_lc and right_g.role_lc then
    return false
  end

  local combined_dur = math.max(left_g.end_pos, right_g.end_pos) - left_g.start_pos
  if combined_dur > max_dur then return false end

  local approx_chars = (left_g.chars or 0) + 1 + (right_g.chars or 0)
  if left_g.role_lc and right_g.role_lc and left_g.role_lc == right_g.role_lc then
    approx_chars = approx_chars - (#right_g.role + 2)
  end
  if approx_chars > max_chars then return false end

  return true
end

-- Calcola i gruppi di unione per gli item brevi.
-- items: lista ordinata { { start_pos, end_pos, text, sync_key? }, ... }
-- Restituisce:
--   merge_groups: solo i gruppi con #indices >= 2 ({ indices = {...}, start_pos, end_pos, text })
--   absorbed_count: numero di micro-item assorbiti
--   all_groups: l'intera sequenza risultante dopo l'accorpamento
function M.plan_short_merges(items, opts)
  opts = opts or {}
  local max_words = tonumber(opts.max_words) or 2
  local min_dur   = tonumber(opts.min_dur) or 1.05
  local groups = {}
  for i, it in ipairs(items or {}) do
    local s = tonumber(it.start_pos or it.pos) or 0
    local e = tonumber(it.end_pos or it.finish) or (s + (tonumber(it.len) or 0))
    local g = {
      indices   = { i },
      start_pos = s,
      end_pos   = e,
      text      = tostring(it.text or ""),
      sync_key  = it.sync_key or ""
    }
    refresh_group_meta(g)
    groups[i] = g
  end

  local guard = 0
  local max_iters = #groups * 2 + 4
  while guard < max_iters do
    guard = guard + 1
    local best_idx, best_dir, best_words = nil, nil, math.huge

    for i = 1, #groups do
      local g = groups[i]
      local dur = g.end_pos - g.start_pos
      local is_short = (g.words > 0) and (g.words <= max_words or (dur < min_dur and g.words <= max_words + 1))
      if (g.sync_key == "") and is_short then
        local left_ok  = can_merge_pair(groups[i - 1], g, opts)
        local right_ok = can_merge_pair(g, groups[i + 1], opts)
        if left_ok or right_ok then
          local w = g.words
          if w < best_words then
            best_words = w
            best_idx = i
            if left_ok and not right_ok then
              best_dir = -1
            elseif right_ok and not left_ok then
              best_dir = 1
            else
              local prev_g = groups[i - 1]
              local next_g = groups[i + 1]
              local gap_l = math.max(0, g.start_pos - prev_g.end_pos)
              local gap_r = math.max(0, next_g.start_pos - g.end_pos)

              if prev_g.ends_stop and not g.ends_stop then
                best_dir = 1
              elseif g.ends_stop and not prev_g.ends_stop then
                best_dir = -1
              elseif math.abs(gap_l - gap_r) > 0.12 then
                best_dir = (gap_l <= gap_r) and -1 or 1
              else
                best_dir = -1
              end
            end
          end
        end
      end
    end

    if not best_idx then break end

    local a_idx = (best_dir == -1) and (best_idx - 1) or best_idx
    local b_idx = a_idx + 1
    local ga, gb = groups[a_idx], groups[b_idx]
    for _, orig_i in ipairs(gb.indices) do
      ga.indices[#ga.indices + 1] = orig_i
    end
    ga.end_pos = math.max(ga.end_pos, gb.end_pos)
    ga.text    = join_two_texts(ga.text, gb.text)
    refresh_group_meta(ga)
    table.remove(groups, b_idx)
  end

  local merge_groups = {}
  local absorbed = 0
  for _, g in ipairs(groups) do
    if #g.indices >= 2 then
      merge_groups[#merge_groups + 1] = g
      absorbed = absorbed + (#g.indices - 1)
    end
  end
  return merge_groups, absorbed, groups
end

function M.coalesce_cues(cues, opts)
  if not cues or #cues <= 1 then return cues or {}, 0 end
  local _, absorbed, all_groups = M.plan_short_merges(cues, opts)
  if absorbed == 0 then return cues, 0 end
  local out = {}
  for i, g in ipairs(all_groups) do
    local first_cue = cues[g.indices[1]] or {}
    out[i] = {
      start_pos = g.start_pos,
      end_pos   = g.end_pos,
      text      = g.text,
      cue_id    = first_cue.cue_id or tostring(i),
      index     = i
    }
  end
  return out, absorbed
end

---------------------------------------------------------------------------
-- 5. DIVISIONE BATTUTE (ALLA PLAYHEAD O PER RIGHE — PURE)
---------------------------------------------------------------------------

-- Spezza un testo in (left_text, right_text) vicino a ratio (0..1),
-- agganciandosi al confine di riga, punteggiatura o parola più vicino.
function M.split_cue_at_ratio(text, ratio)
  local clean = M.trim(tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n"))
  if clean == "" then return nil, nil end
  ratio = math.max(0.08, math.min(0.92, tonumber(ratio) or 0.5))
  local target_byte = math.max(1, math.min(#clean, math.floor(#clean * ratio + 0.5)))

  -- Raccoglie tutti i confini tra parole (spazi o ritorni a capo)
  local breaks = {}
  local pos = 1
  while pos <= #clean do
    local s, e = clean:find("%s+", pos)
    if not s then break end
    local left_part  = M.trim(clean:sub(1, s - 1))
    local right_part = M.trim(clean:sub(e + 1))
    if left_part ~= "" and right_part ~= "" then
      local has_nl = clean:sub(s, e):find("\n", 1, true) ~= nil
      local has_punct = left_part:match("[%.!%?:;,]$") ~= nil
      breaks[#breaks + 1] = {
        mid       = (s + e) * 0.5,
        left      = left_part,
        right     = right_part,
        has_nl    = has_nl,
        has_punct = has_punct
      }
    end
    pos = e + 1
  end

  if #breaks == 0 then return nil, nil end

  local best, best_score = nil, math.huge
  local span = math.max(1, #clean)
  for _, br in ipairs(breaks) do
    local dist = math.abs(br.mid - target_byte) / span
    -- Piccolo bonus se nelle vicinanze c'è un ritorno a capo o punteggiatura
    local bonus = (br.has_nl and 0.12 or 0) + (br.has_punct and 0.06 or 0)
    local score = dist - (dist <= 0.22 and bonus or 0)
    if score < best_score then
      best_score = score
      best = br
    end
  end
  return best.left, best.right
end

-- Divide una battuta multi-riga (o multi-frase se su 1 riga sola) in sotto-battute proporzionali.
function M.split_cue_lines(text, start_pos, end_pos)
  local clean = M.trim(tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n"))
  local total_dur = (tonumber(end_pos) or 0) - (tonumber(start_pos) or 0)
  if clean == "" or total_dur < 0.30 then return nil, "Battuta troppo breve o vuota per essere divisa." end

  local parts = {}
  for line in (clean .. "\n"):gmatch("([^\n]*)\n") do
    local t = M.trim(line)
    if t ~= "" then parts[#parts + 1] = t end
  end

  -- Se era tutto su una riga sola (es. dopo un'unione con spazio), prova a spezzare sulle frasi (. ? !)
  if #parts < 2 then
    parts = {}
    local sentence_split = clean:gsub("([%.!%?]+[\'\")%]\194\187]*)%s+", "%1\n")
    for line in (sentence_split .. "\n"):gmatch("([^\n]*)\n") do
      local t = M.trim(line)
      if t ~= "" then parts[#parts + 1] = t end
    end
  end

  if #parts < 2 then
    return nil, "La battuta non contiene più righe o frasi separabili."
  end

  local weights, sum_w = {}, 0
  for i, p in ipairs(parts) do
    local w = math.max(2, M.char_length(p))
    weights[i] = w
    sum_w = sum_w + w
  end

  local out = {}
  local cursor = start_pos
  for i, p in ipairs(parts) do
    local dur = (i == #parts) and (end_pos - cursor) or (total_dur * (weights[i] / sum_w))
    local finish = (i == #parts) and end_pos or (cursor + dur)
    out[#out + 1] = {
      start_pos = cursor,
      end_pos   = finish,
      text      = p
    }
    cursor = finish
  end
  return out
end

---------------------------------------------------------------------------
-- 5b. MARKER AUDIO -> CUE SRT (STESSE REGOLE DI 31, PURA SENZA APRIRE GUI)
---------------------------------------------------------------------------

local AUDIO_LAST_MAX = 8.0
local AUDIO_MIN_LEN  = 0.3
local SERVICE_PREFIXES = { "SOLO_MARK", "OK", "BAD", "ALT", "NOISE", "INSERT" }

function M.is_service_marker(name)
  name = M.trim(name)
  local c = name:sub(1, 1)
  if c == "#" or c == "!" then return true end
  for _, p in ipairs(SERVICE_PREFIXES) do
    if name:match("^" .. p .. "_%d+$") then return true end
  end
  return false
end

function M.audio_marker_cues(markers, source_len)
  local list = {}
  for _, m in ipairs(markers or {}) do
    local text = M.trim(m.text)
    if text ~= "" and not M.is_service_marker(text) and (tonumber(m.src) or -1) >= 0 then
      list[#list + 1] = { start_pos = tonumber(m.src), text = text, len = m.len }
    end
  end
  table.sort(list, function(a, b) return a.start_pos < b.start_pos end)
  local cues = {}
  for _, c in ipairs(list) do
    if not cues[#cues] or c.start_pos - cues[#cues].start_pos > 0.001 then
      cues[#cues + 1] = c
    end
  end
  for i, c in ipairs(cues) do
    local nxt = cues[i + 1] and cues[i + 1].start_pos
    local stop
    if c.len and c.len > 0 then
      stop = c.start_pos + c.len
    else
      local cap = (source_len and source_len > c.start_pos) and source_len or (c.start_pos + AUDIO_LAST_MAX)
      stop = nxt or math.min(c.start_pos + AUDIO_LAST_MAX, cap)
    end
    if stop - c.start_pos < AUDIO_MIN_LEN then stop = c.start_pos + AUDIO_MIN_LEN end
    c.end_pos = stop
    c.len = nil
  end
  return cues
end

if not reaper then
  return M
end

---------------------------------------------------------------------------
-- 6. SEZIONE REAPER (INTEGRAZIONE TIMELINE, FILE E GOBBO)
---------------------------------------------------------------------------

local sep = package.config:sub(1, 1)
local SCRIPT_DIR = (debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*[/\\])") or "")

local _mods = {}
local function mod(name)
  if not _mods[name] then
    _mods[name] = dofile(SCRIPT_DIR .. name)
  end
  return _mods[name]
end

local function ZP_TESTO() return mod("ZP_Testo_Copione.lua") end
local function ZP_XLSX()  return mod("ZP_Xlsx_Copione.lua") end
local function ZP_REG()   return mod("ZP_SRT_Progetto.lua") end

local function native_color(hex)
  local r = (hex >> 16) & 0xFF
  local g = (hex >> 8) & 0xFF
  local b = hex & 0xFF
  return reaper.ColorToNative(r, g, b) | 0x1000000
end

function M.file_exists(path)
  if not path or path == "" then return false end
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

function M.read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

function M.write_file(path, content)
  local f, err = io.open(path, "wb")
  if not f then return false, tostring(err or "Impossibile scrivere il file.") end
  f:write(content)
  f:close()
  return true
end

function M.ensure_dir(path)
  path = M.trim(path)
  if path == "" then return false end
  if reaper.RecursiveCreateDirectory then
    reaper.RecursiveCreateDirectory(path, 0)
    return true
  end
  return false
end

function M.project_saved_dir()
  local _, proj_path = reaper.EnumProjects(-1, "")
  if not proj_path or proj_path == "" then return nil end
  local d = M.dirname(proj_path)
  return d ~= "" and d or nil
end

function M.default_dir()
  return M.project_saved_dir() or reaper.GetResourcePath()
end

local function get_track_name(track)
  if not track then return "" end
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  return M.trim(name)
end

local function get_item_str(item, key)
  local _, val = reaper.GetSetMediaItemInfo_String(item, key, "", false)
  return val or ""
end

local function set_item_str(item, key, val)
  reaper.GetSetMediaItemInfo_String(item, key, tostring(val or ""), true)
end

local function item_source_path(item)
  local take = reaper.GetActiveTake(item)
  if not take then return "" end
  local src = reaper.GetMediaItemTake_Source(take)
  if not src then return "" end
  return reaper.GetMediaSourceFileName(src, "") or ""
end

local function is_bkp_track_name(name)
  return name:match("%sBKP$") ~= nil or name:match("%sBKP%s*%d+$") ~= nil
end

function M.is_subtitle_track_name(name)
  if is_bkp_track_name(name) then return false end
  return name == M.SUBTITLE_TRACK_NAME or name:sub(1, #M.SUBTITLE_TRACK_NAME + 1) == (M.SUBTITLE_TRACK_NAME .. " ")
end

function M.find_track_exact(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if get_track_name(tr) == name then return tr, i end
  end
  return nil, nil
end

local function extract_first_track_chunk(text)
  local current, depth = nil, 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    if not current and line:match("^%s*<TRACK") then
      current = { line }; depth = 1
    elseif current then
      current[#current + 1] = line
      if line:match("^%s*<") then depth = depth + 1 end
      if line:match("^%s*>%s*$") then
        depth = depth - 1
        if depth == 0 then return table.concat(current, "\n") end
      end
    end
  end
  return nil
end

function M.setup_subtitle_track(track)
  if not track then return end
  reaper.SetMediaTrackInfo_Value(track, "B_FREEMODE", 1)
  reaper.SetMediaTrackInfo_Value(track, "I_FREEMODE", 1)
  if reaper.GetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE") < 80 then
    reaper.SetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE", 110)
  end
end

function M.get_or_create_subtitle_track(name, insert_idx)
  name = M.trim(name) ~= "" and M.trim(name) or M.SUBTITLE_TRACK_NAME
  local existing = M.find_track_exact(name)
  if existing then
    M.setup_subtitle_track(existing)
    return existing
  end

  local idx = insert_idx or reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local track = reaper.GetTrack(0, idx)
  local tpl_text = M.read_file(SCRIPT_DIR .. M.SRT_TEMPLATE_NAME)
  local chunk = tpl_text and extract_first_track_chunk(tpl_text) or nil
  if chunk and reaper.SetTrackStateChunk then
    chunk = chunk:gsub("\n%s*TRACKID%s+%b{}\n", "\n")
    reaper.SetTrackStateChunk(track, chunk, false)
  end
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
  reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", native_color(M.COLOR_SUBS))
  M.setup_subtitle_track(track)
  return track
end

function M.get_or_create_plain_track(name, hex_color, insert_idx)
  local existing = M.find_track_exact(name)
  if existing then return existing end
  local idx = insert_idx or reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local track = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
  if hex_color then
    reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", native_color(hex_color))
  end
  return track
end

---------------------------------------------------------------------------
-- 7. SCANSIONE CONTESTO LIVE DEL PROGETTO
---------------------------------------------------------------------------

function M.collect_subtitle_tracks()
  local list = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local name = get_track_name(tr)
    if M.is_subtitle_track_name(name) then
      list[#list + 1] = {
        track = tr,
        name  = name,
        index = i + 1,
        count = reaper.CountTrackMediaItems(tr)
      }
    end
  end
  return list
end

function M.collect_video_items(selected_only)
  local videos = {}
  if selected_only then
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      local path = item_source_path(item)
      if M.is_video_file(path) then
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        videos[#videos + 1] = {
          item = item, path = path, base = M.stem(path),
          start_pos = pos, len = len, end_pos = pos + len
        }
      end
    end
  else
    for t = 0, reaper.CountTracks(0) - 1 do
      local tr = reaper.GetTrack(0, t)
      for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
        local item = reaper.GetTrackMediaItem(tr, i)
        local path = item_source_path(item)
        if M.is_video_file(path) then
          local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
          local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
          videos[#videos + 1] = {
            item = item, path = path, base = M.stem(path),
            start_pos = pos, len = len, end_pos = pos + len
          }
        end
      end
    end
  end
  table.sort(videos, function(a, b) return a.start_pos < b.start_pos end)
  return videos
end

function M.collect_regions()
  local regions = {}
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  for i = 0, (num_markers + num_regions) - 1 do
    local ok, is_rgn, pos, rgn_end, name, markrgnidx = reaper.EnumProjectMarkers(i)
    if ok and is_rgn and rgn_end > pos then
      local label = M.trim(name) ~= "" and M.trim(name) or ("Regione_" .. tostring(markrgnidx))
      regions[#regions + 1] = {
        name = label, base = label,
        start_pos = pos, end_pos = rgn_end, len = rgn_end - pos,
        rgn_id = markrgnidx
      }
    end
  end
  table.sort(regions, function(a, b) return a.start_pos < b.start_pos end)
  return regions
end

-- Regione "attiva": prima quella scelta con doppio clic (REAPER ne fa la selezione temporale, che coincide
-- con i bordi della regione), altrimenti quella sotto la playhead.
function M.region_at_cursor(regions)
  regions = regions or M.collect_regions()
  if reaper.GetSet_LoopTimeRange then
    local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if ts and te and te - ts > 0.01 then
      for _, r in ipairs(regions) do
        if math.abs(r.start_pos - ts) < 0.002 and math.abs(r.end_pos - te) < 0.002 then
          return r
        end
      end
    end
  end
  local cur = reaper.GetCursorPosition()
  for _, r in ipairs(regions) do
    if cur >= r.start_pos - 0.0001 and cur <= r.end_pos + 0.0001 then
      return r
    end
  end
  return nil
end

function M.collect_text_items_on_track(track, start_pos, end_pos)
  local list = {}
  if not track then return list end
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    if reaper.GetMediaItemNumTakes(item) == 0 then
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      local finish = pos + len
      local inside = true
      if start_pos and end_pos then
        local mid = pos + len * 0.5
        inside = (mid >= start_pos - 0.001 and mid <= end_pos + 0.001)
      end
      if inside then
        local notes = get_item_str(item, "P_NOTES"):gsub("\r\n", "\n"):gsub("\r", "\n")
        list[#list + 1] = {
          item      = item,
          track     = track,
          start_pos = pos,
          end_pos   = finish,
          len       = len,
          text      = M.trim(notes),
          raw_notes = notes,
          sync_key  = M.trim(get_item_str(item, "P_EXT:ZP_SYNC_KEY"))
        }
      end
    end
  end
  table.sort(list, function(a, b) return a.start_pos < b.start_pos end)
  return list
end

function M.collect_selected_text_items()
  local list = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    if reaper.GetMediaItemNumTakes(item) == 0 then
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      local notes = get_item_str(item, "P_NOTES"):gsub("\r\n", "\n"):gsub("\r", "\n")
      list[#list + 1] = {
        item      = item,
        track     = reaper.GetMediaItem_Track(item),
        start_pos = pos,
        end_pos   = pos + len,
        len       = len,
        text      = M.trim(notes),
        raw_notes = notes,
        sync_key  = M.trim(get_item_str(item, "P_EXT:ZP_SYNC_KEY"))
      }
    end
  end
  table.sort(list, function(a, b) return a.start_pos < b.start_pos end)
  return list
end

function M.collect_selected_audio_marker_sources()
  local by_src, order = {}, {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = reaper.GetActiveTake(item)
    local src = take and reaper.GetMediaItemTake_Source(take)
    local path = src and reaper.GetMediaSourceFileName(src, "") or ""
    if path ~= "" and not M.is_video_file(path) then
      local entry = by_src[path]
      if not entry then
        entry = { path = path, len = reaper.GetMediaSourceLength(src), markers = {}, items = 0 }
        by_src[path] = entry
        order[#order + 1] = entry
      end
      entry.items = entry.items + 1
      for m = 0, reaper.GetNumTakeMarkers(take) - 1 do
        local pos, name = reaper.GetTakeMarker(take, m)
        if pos and pos >= 0 then
          entry.markers[#entry.markers + 1] = { src = pos, text = name }
        end
      end
    end
  end
  for _, e in ipairs(order) do
    e.cues = M.audio_marker_cues(e.markers, e.len)
  end
  return order
end

function M.count_short_in_range(trk_items, start_pos, end_pos, coalesce_opts)
  if not trk_items or #trk_items < 2 then return 0 end
  local sub = {}
  for _, it in ipairs(trk_items) do
    local mid = it.start_pos + it.len * 0.5
    if mid >= start_pos - 0.001 and mid <= end_pos + 0.001 then
      sub[#sub + 1] = it
    end
  end
  if #sub < 2 then return 0 end
  local _, abs = M.plan_short_merges(sub, coalesce_opts)
  return abs
end

function M.scan_context(active_track_name, coalesce_opts)
  local sub_tracks = M.collect_subtitle_tracks()
  local active_track = nil
  if active_track_name and active_track_name ~= "" then
    for _, t in ipairs(sub_tracks) do
      if t.name == active_track_name then active_track = t.track; break end
    end
  end
  if not active_track and #sub_tracks > 0 then
    local sel_tr = reaper.GetSelectedTrack(0, 0)
    for _, t in ipairs(sub_tracks) do
      if t.track == sel_tr then active_track = t.track; active_track_name = t.name; break end
    end
    if not active_track then
      active_track = sub_tracks[1].track
      active_track_name = sub_tracks[1].name
    end
  end

  local regions = M.collect_regions()
  local cur_region = M.region_at_cursor(regions)
  local sel_videos = M.collect_video_items(true)
  local all_videos = M.collect_video_items(false)
  local sel_texts  = M.collect_selected_text_items()
  local audio_srcs = M.collect_selected_audio_marker_sources()

  local short_sel, short_reg, short_trk = 0, 0, 0
  local trk_items = nil
  if #sel_texts >= 2 then
    local by_tr = {}
    for _, it in ipairs(sel_texts) do
      by_tr[it.track] = by_tr[it.track] or {}
      by_tr[it.track][#by_tr[it.track] + 1] = it
    end
    for _, grp in pairs(by_tr) do
      local _, abs = M.plan_short_merges(grp, coalesce_opts)
      short_sel = short_sel + abs
    end
  end
  if active_track then
    trk_items = M.collect_text_items_on_track(active_track)
    local _, abs_t = M.plan_short_merges(trk_items, coalesce_opts)
    short_trk = abs_t
    if cur_region then
      short_reg = M.count_short_in_range(trk_items, cur_region.start_pos, cur_region.end_pos, coalesce_opts)
    end
  end

  return {
    saved_dir         = M.project_saved_dir(),
    cursor            = reaper.GetCursorPosition(),
    sub_tracks        = sub_tracks,
    active_track      = active_track,
    active_track_name = active_track_name or M.SUBTITLE_TRACK_NAME,
    trk_items         = trk_items,
    regions           = regions,
    cur_region        = cur_region,
    sel_videos        = sel_videos,
    all_videos        = all_videos,
    sel_texts         = sel_texts,
    audio_srcs        = audio_srcs,
    sel_total         = reaper.CountSelectedMediaItems(0),
    sel_info          = M.inspect_selection(),
    short_sel         = short_sel,
    short_reg         = short_reg,
    short_trk         = short_trk
  }
end

---------------------------------------------------------------------------
-- 8. SELETTORI FILE / CARTELLE E CARICAMENTO SOTTOTITOLI (.SRT/.VTT/.XLSX)
---------------------------------------------------------------------------

function M.choose_video_file(initial_dir)
  local ok, path = reaper.GetUserFileNameForRead(
    (initial_dir or M.default_dir()) .. sep,
    "Scegli file video (.mp4, .mov, .mkv, .m4v, .avi)",
    ""
  )
  if not ok or M.trim(path) == "" then return nil end
  return M.trim(path)
end

function M.choose_subtitle_file(initial_dir, title)
  local ok, path = reaper.GetUserFileNameForRead(
    (initial_dir or M.default_dir()) .. sep,
    title or "Scegli sottotitoli (.srt, .vtt o Excel .xlsx)",
    ""
  )
  if not ok or M.trim(path) == "" then return nil, nil end
  path = M.trim(path)
  local resolved, err = ZP_XLSX().resolve_choice(path, reaper, SCRIPT_DIR)
  if not resolved then return nil, err end
  return resolved, nil
end

function M.choose_folder(initial_dir, title)
  local def = initial_dir or M.default_dir()
  if reaper.JS_Dialog_BrowseForFolder then
    local rv, folder = reaper.JS_Dialog_BrowseForFolder(title or "Scegli cartella", def)
    if rv == 1 and folder and M.trim(folder) ~= "" then return M.trim(folder) end
    return nil
  end
  if reaper.GetUserFileNameForWrite then
    local ok, f = reaper.GetUserFileNameForWrite(def .. sep .. "cartella.srt", title or "Scegli la cartella di destinazione", "srt")
    if ok and f ~= "" then return M.dirname(f) end
    return nil
  end
  local ok, f = reaper.GetUserFileNameForRead(def .. sep, title or "Scegli un file dentro la cartella desiderata", "")
  if ok and f ~= "" then return M.dirname(f) end
  return nil
end

function M.load_cues_from_file(path, coalesce_opts)
  local resolved, xerr = ZP_XLSX().resolve_choice(path, reaper, SCRIPT_DIR)
  if not resolved then return nil, xerr end
  local raw = M.read_file(resolved)
  if not raw then return nil, "Impossibile leggere il file: " .. tostring(resolved) end
  local cues, perr = M.parse_subtitles(raw)
  if not cues then return nil, perr end
  local absorbed = 0
  if coalesce_opts and coalesce_opts.enabled then
    cues, absorbed = M.coalesce_cues(cues, coalesce_opts)
  end
  return cues, resolved, absorbed
end

function M.find_sidecar_subtitle(video_path)
  local dir = M.dirname(video_path)
  local base = M.stem(video_path)
  for _, ext in ipairs({ ".srt", ".vtt", ".SRT", ".VTT" }) do
    local p = dir .. sep .. base .. ext
    if M.file_exists(p) then return p end
  end
  return nil
end

---------------------------------------------------------------------------
-- 9. SCRITTURA E BACKUP ITEM TESTO IN TIMELINE
---------------------------------------------------------------------------

function M.write_cues_to_track(track, cues, base_offset, overlap_mode, srt_path)
  local resolved_cues, overlap_count = M.resolve_overlaps(cues, overlap_mode or "lane")
  local testo = ZP_TESTO()
  local srt_file = srt_path and M.basename(srt_path) or ""
  local created = 0

  for i, cue in ipairs(resolved_cues) do
    local abs_start = (base_offset or 0) + cue.start_pos
    local abs_end   = (base_offset or 0) + cue.end_pos
    if abs_end > abs_start + 0.02 then
      local item = reaper.AddMediaItemToTrack(track)
      reaper.SetMediaItemInfo_Value(item, "D_POSITION", abs_start)
      reaper.SetMediaItemInfo_Value(item, "D_LENGTH", abs_end - abs_start)
      if cue.overlap then
        reaper.SetMediaItemInfo_Value(item, "F_FREEMODE_Y", 0.52)
        reaper.SetMediaItemInfo_Value(item, "F_FREEMODE_H", 0.46)
        reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", native_color(M.COLOR_OVERLAP))
      else
        reaper.SetMediaItemInfo_Value(item, "F_FREEMODE_Y", 0.02)
        reaper.SetMediaItemInfo_Value(item, "F_FREEMODE_H", 0.46)
        reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", native_color(M.COLOR_SUBS))
      end
      set_item_str(item, "P_NOTES", cue.text)
      testo.name_text_item(reaper, item, string.format("%03d %s", i, cue.text))
      if srt_path and srt_path ~= "" then
        set_item_str(item, "P_EXT:RythmoBand_SRT_PATH", srt_path)
        set_item_str(item, "P_EXT:RythmoBand_SRT_FILE", srt_file)
      end
      set_item_str(item, "P_EXT:RythmoBand_SRT_CUE", tostring(cue.cue_id or i))
      reaper.UpdateItemInProject(item)
      created = created + 1
    end
  end
  return created, overlap_count
end

-- Sposta o copia gli item esistenti in un intervallo su un'unica traccia muta "<Nome> BKP"
function M.backup_and_clear_range(track, start_pos, end_pos, make_backup)
  local to_remove = {}
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    if reaper.GetMediaItemNumTakes(item) == 0 then
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      local mid = pos + len * 0.5
      local hit = (not start_pos and not end_pos)
        or (mid >= start_pos - 0.001 and mid <= end_pos + 0.001)
      if hit then
        to_remove[#to_remove + 1] = item
      end
    end
  end
  if #to_remove == 0 then return 0, nil end

  local bkp_name = nil
  if make_backup ~= false then
    bkp_name = get_track_name(track) .. " BKP"
    local bkp_tr = M.find_track_exact(bkp_name)
    if not bkp_tr then
      local _, tr_idx = M.find_track_exact(get_track_name(track))
      bkp_tr = M.get_or_create_subtitle_track(bkp_name, (tr_idx or reaper.CountTracks(0) - 1) + 1)
    end
    reaper.SetMediaTrackInfo_Value(bkp_tr, "B_MUTE", 1)
    reaper.SetMediaTrackInfo_Value(bkp_tr, "B_SHOWINMIXER", 0)
    reaper.SetMediaTrackInfo_Value(bkp_tr, "I_CUSTOMCOLOR", native_color(M.COLOR_BKP))

    -- Pulisce eventuali vecchi BKP nello stesso intervallo per non impilare duplicati infiniti
    for i = reaper.CountTrackMediaItems(bkp_tr) - 1, 0, -1 do
      local old_it = reaper.GetTrackMediaItem(bkp_tr, i)
      local p = reaper.GetMediaItemInfo_Value(old_it, "D_POSITION")
      local l = reaper.GetMediaItemInfo_Value(old_it, "D_LENGTH")
      local m = p + l * 0.5
      if (not start_pos and not end_pos) or (m >= start_pos - 0.001 and m <= end_pos + 0.001) then
        reaper.DeleteTrackMediaItem(bkp_tr, old_it)
      end
    end

    for _, item in ipairs(to_remove) do
      reaper.MoveMediaItemToTrack(item, bkp_tr)
    end
    return #to_remove, bkp_name
  else
    for _, item in ipairs(to_remove) do
      reaper.DeleteTrackMediaItem(track, item)
    end
    return #to_remove, nil
  end
end

local function register_srt_if_saved(source_id, srt_path, lang, kind, copy_to_media)
  if copy_to_media == false or not M.project_saved_dir() then
    return srt_path, false
  end
  local copied, err = ZP_REG().copy_to_media(source_id, srt_path, lang or "", kind or "srt")
  if copied then return copied, true end
  return srt_path, false, err
end

---------------------------------------------------------------------------
-- 10. TAB 1 · CARICA (VIDEO + SRT, SOLO VIDEO, SOLO SRT, CARTELLA BATCH)
---------------------------------------------------------------------------

local function add_video_to_track(track, video_path, start_pos)
  local src = reaper.PCM_Source_CreateFromFile(video_path)
  if not src then return nil, nil, "REAPER non riesce ad aprire il video: " .. M.basename(video_path) end
  local len = reaper.GetMediaSourceLength(src)
  local item = reaper.AddMediaItemToTrack(track)
  local take = reaper.AddTakeToMediaItem(item)
  reaper.SetMediaItemTake_Source(take, src)
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", M.stem(video_path), true)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", start_pos)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len)
  set_item_str(item, "P_NOTES", "RythmoBand video start=" .. tostring(start_pos))
  reaper.UpdateItemInProject(item)
  return item, len, nil
end

local function project_end_time()
  local max_end = 0
  for t = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, t)
    for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      local e = reaper.GetMediaItemInfo_Value(it, "D_POSITION") + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if e > max_end then max_end = e end
    end
  end
  return max_end
end

-- Punto d'ingresso dei sottotitoli. "auto" = regola di Paolo (2026-11-25):
--   la REGIONE sotto la playhead comanda il timecode; senza regione l'SRT va sotto il VIDEO selezionato;
--   altrimenti alla playhead. Restituisce posizione, tipo ("region"|"video"|"playhead") e nome.
function M.resolve_anchor(pos_mode)
  if pos_mode == "zero" then return 0.0, "zero", "00:00:00" end
  if pos_mode == "end" then
    local e = project_end_time()
    return (e > 0.01 and (e + 3.0) or 0.0), "end", nil
  end
  if pos_mode == "selected_video" then
    local vids = M.collect_video_items(true)
    if #vids > 0 then return vids[1].start_pos, "video", vids[1].base end
  end
  if pos_mode == "auto" then
    local reg = M.region_at_cursor()
    if reg then return reg.start_pos, "region", reg.name end
    local vids = M.collect_video_items(true)
    if #vids > 0 then return vids[1].start_pos, "video", vids[1].base end
  end
  return reaper.GetCursorPosition(), "playhead", nil
end

local function compute_insert_start(pos_mode)
  return (M.resolve_anchor(pos_mode))
end

function M.import_single(opts)
  opts = opts or {}
  local mode = opts.mode or "video_srt" -- "video_srt", "video_only", "srt_only"
  local video_path = opts.video_path
  local srt_path   = opts.srt_path

  if (mode == "video_srt" or mode == "video_only") and (not video_path or video_path == "") then
    video_path = M.choose_video_file(opts.initial_dir)
    if not video_path then return nil, nil end
  end

  if mode == "video_srt" and (not srt_path or srt_path == "") then
    local sidecar = M.find_sidecar_subtitle(video_path)
    local start_dir = M.dirname(video_path)
    srt_path, opts._err = M.choose_subtitle_file(start_dir, sidecar and ("Scegli SRT/VTT/XLSX (trovato: " .. M.basename(sidecar) .. ")") or nil)
    if not srt_path then
      if opts._err then return nil, opts._err end
      return nil, nil
    end
  elseif mode == "srt_only" and (not srt_path or srt_path == "") then
    srt_path, opts._err = M.choose_subtitle_file(opts.initial_dir)
    if not srt_path then
      if opts._err then return nil, opts._err end
      return nil, nil
    end
  end

  local cues, resolved_srt, absorbed = nil, nil, 0
  if srt_path and srt_path ~= "" then
    cues, resolved_srt, absorbed = M.load_cues_from_file(srt_path, opts.coalesce_opts)
    if not cues then return nil, tostring(resolved_srt or "Errore lettura SRT.") end
  end

  local start_pos = compute_insert_start((opts.pos_mode == "auto" and mode ~= "srt_only") and "cursor" or opts.pos_mode)
  local track_name = M.trim(opts.track_name) ~= "" and M.trim(opts.track_name) or M.SUBTITLE_TRACK_NAME

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local ok, result = pcall(function()
    local v_len = 0
    local stored_srt = resolved_srt
    if video_path and video_path ~= "" then
      local v_track = M.get_or_create_plain_track(M.VIDEO_TRACK_NAME, M.COLOR_VIDEO, 0)
      local _, len, verr = add_video_to_track(v_track, video_path, start_pos)
      if not len then error(verr, 0) end
      v_len = len
      if opts.create_region ~= false then
        reaper.AddProjectMarker2(0, true, start_pos, start_pos + v_len, M.stem(video_path), -1, 0)
      end
      if opts.create_vox_track then
        M.get_or_create_plain_track(M.VOX_TRACK_NAME, M.COLOR_VOX)
      end
    end

    local created_cues, overlaps = 0, 0
    local copied_media = false
    if cues then
      local sub_track = M.get_or_create_subtitle_track(track_name)
      local source_id = (video_path and video_path ~= "") and video_path or ("srt:" .. M.stem(resolved_srt) .. ":" .. string.format("%.3f", start_pos))
      stored_srt, copied_media = register_srt_if_saved(source_id, resolved_srt, "", "importazione", opts.copy_to_media)
      if opts.clear_range and v_len > 0 then
        M.backup_and_clear_range(sub_track, start_pos, start_pos + v_len, true)
      end
      created_cues, overlaps = M.write_cues_to_track(sub_track, cues, start_pos, opts.overlap_mode, stored_srt)
      reaper.SetOnlyTrackSelected(sub_track)
    end

    if reaper.TrackList_AdjustWindows then reaper.TrackList_AdjustWindows(false) end
    reaper.UpdateArrange()
    if video_path and video_path ~= "" then
      reaper.Main_OnCommand(40047, 0) -- Build any missing peaks
    end
    return {
      video_name   = video_path and M.basename(video_path) or nil,
      srt_name     = stored_srt and M.basename(stored_srt) or nil,
      cues         = created_cues,
      overlaps     = overlaps,
      absorbed     = absorbed,
      copied_media = copied_media,
      start_pos    = start_pos
    }
  end)

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ZP SRT: carica media / sottotitoli", -1)
  if not ok then
    reaper.Undo_DoUndo2(0)
    return nil, tostring(result)
  end
  return result, nil
end

function M.import_folder_batch(opts)
  opts = opts or {}
  local folder = opts.folder or M.choose_folder(opts.initial_dir, "Scegli cartella con video (e SRT/VTT omonimi)")
  if not folder then return nil, nil end

  local videos = {}
  local idx = 0
  while true do
    local fname = reaper.EnumerateFiles(folder, idx)
    if not fname then break end
    local full = folder .. sep .. fname
    if M.is_video_file(full) then
      videos[#videos + 1] = full
    end
    idx = idx + 1
  end
  table.sort(videos, function(a, b) return a:lower() < b:lower() end)
  if #videos == 0 then
    return nil, "Nessun file video (.mp4, .mov, .mkv, .m4v, .avi) trovato nella cartella scelta."
  end

  local gap_sec = math.max(0, tonumber(opts.batch_gap) or 3.0)
  local pos_cursor = compute_insert_start(opts.pos_mode == "auto" and "cursor" or opts.pos_mode)
  local track_name = M.trim(opts.track_name) ~= "" and M.trim(opts.track_name) or M.SUBTITLE_TRACK_NAME

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local ok, summary = pcall(function()
    local v_track = M.get_or_create_plain_track(M.VIDEO_TRACK_NAME, M.COLOR_VIDEO, 0)
    local sub_track = M.get_or_create_subtitle_track(track_name)
    if opts.create_vox_track then
      M.get_or_create_plain_track(M.VOX_TRACK_NAME, M.COLOR_VOX)
    end

    local n_vid, n_srt, n_cues, n_abs = 0, 0, 0, 0
    for _, vpath in ipairs(videos) do
      local _, vlen, verr = add_video_to_track(v_track, vpath, pos_cursor)
      if vlen then
        n_vid = n_vid + 1
        if opts.create_region ~= false then
          reaper.AddProjectMarker2(0, true, pos_cursor, pos_cursor + vlen, M.stem(vpath), -1, 0)
        end
        local sidecar = M.find_sidecar_subtitle(vpath)
        if sidecar then
          local cues, resolved, abs = M.load_cues_from_file(sidecar, opts.coalesce_opts)
          if cues then
            local stored = register_srt_if_saved(vpath, resolved, "", "importazione_batch", opts.copy_to_media)
            local c_cnt = M.write_cues_to_track(sub_track, cues, pos_cursor, opts.overlap_mode, stored)
            n_srt = n_srt + 1
            n_cues = n_cues + c_cnt
            n_abs = n_abs + (abs or 0)
          end
        end
        pos_cursor = pos_cursor + vlen + gap_sec
      elseif verr then
        error(verr, 0)
      end
    end

    if reaper.TrackList_AdjustWindows then reaper.TrackList_AdjustWindows(false) end
    reaper.UpdateArrange()
    reaper.Main_OnCommand(40047, 0)
    return { videos = n_vid, srts = n_srt, cues = n_cues, absorbed = n_abs, folder = M.basename(folder) }
  end)

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ZP SRT: carica cartella video + SRT", -1)
  if not ok then
    reaper.Undo_DoUndo2(0)
    return nil, tostring(summary)
  end
  return summary, nil
end

---------------------------------------------------------------------------
-- 11. TAB 2 · SOSTITUISCI & LINGUE (CON BACKUP PULITO SU TRACCIA BKP)
---------------------------------------------------------------------------

function M.replace_or_add_language(opts)
  opts = opts or {}
  local operation = opts.operation or "replace" -- "replace" o "reference"
  local scope     = opts.scope or "selected_videos" -- "selected_videos", "cursor_region", "all_matching"
  local lang_tag  = M.trim(opts.lang_suffix or "ENG"):upper():gsub("[^%w_%-]", "")
  if operation == "reference" and lang_tag == "" then lang_tag = "REF" end

  local target_track_name = (operation == "reference")
    and (M.SUBTITLE_TRACK_NAME .. " " .. lang_tag)
    or (M.trim(opts.track_name) ~= "" and M.trim(opts.track_name) or M.SUBTITLE_TRACK_NAME)

  local blocks = {}
  if scope == "selected_videos" then
    local vids = M.collect_video_items(true)
    if #vids == 0 then return nil, "Seleziona almeno un item video sulla timeline." end
    for _, v in ipairs(vids) do
      local chosen, err = M.choose_subtitle_file(M.dirname(v.path), "Scegli SRT/VTT/XLSX per " .. M.basename(v.path))
      if not chosen then
        if err then return nil, err end
        return nil, nil
      end
      local cues, resolved, abs = M.load_cues_from_file(chosen, opts.coalesce_opts)
      if not cues then return nil, tostring(resolved) end
      blocks[#blocks + 1] = {
        label = M.basename(v.path), source_id = v.path,
        start_pos = v.start_pos, end_pos = v.end_pos,
        srt_path = resolved, cues = cues, absorbed = abs or 0
      }
    end
  elseif scope == "cursor_region" then
    local reg = M.region_at_cursor()
    if not reg then return nil, "Posiziona la playhead dentro una regione." end
    local chosen, err = M.choose_subtitle_file(M.default_dir(), "Scegli SRT/VTT/XLSX per la regione «" .. reg.name .. "»")
    if not chosen then
      if err then return nil, err end
      return nil, nil
    end
    local cues, resolved, abs = M.load_cues_from_file(chosen, opts.coalesce_opts)
    if not cues then return nil, tostring(resolved) end
    blocks[#blocks + 1] = {
      label = reg.name, source_id = "region:" .. reg.name .. ":" .. string.format("%.3f", reg.start_pos),
      start_pos = reg.start_pos, end_pos = reg.end_pos,
      srt_path = resolved, cues = cues, absorbed = abs or 0
    }
  else
    -- Tutti i video con file omonimo (.srt / .vtt o _<LANG>.srt) accanto
    local vids = M.collect_video_items(false)
    if #vids == 0 then return nil, "Nessun item video trovato nel progetto." end
    for _, v in ipairs(vids) do
      local candidate = nil
      if operation == "reference" then
        local dir, stem = M.dirname(v.path), M.stem(v.path)
        for _, sep_ch in ipairs({ "_", ".", "-" }) do
          for _, ext in ipairs({ ".srt", ".vtt" }) do
            local p = dir .. sep .. stem .. sep_ch .. lang_tag .. ext
            local pl = dir .. sep .. stem .. sep_ch .. lang_tag:lower() .. ext
            if M.file_exists(p) then candidate = p; break end
            if M.file_exists(pl) then candidate = pl; break end
          end
          if candidate then break end
        end
      end
      if not candidate then candidate = M.find_sidecar_subtitle(v.path) end
      if candidate then
        local cues, resolved, abs = M.load_cues_from_file(candidate, opts.coalesce_opts)
        if cues then
          blocks[#blocks + 1] = {
            label = M.basename(v.path), source_id = v.path,
            start_pos = v.start_pos, end_pos = v.end_pos,
            srt_path = resolved, cues = cues, absorbed = abs or 0
          }
        end
      end
    end
    if #blocks == 0 then
      return nil, "Nessun file SRT/VTT omonimo trovato accanto ai video del progetto."
    end
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local ok, res = pcall(function()
    local sub_track = M.get_or_create_subtitle_track(target_track_name)
    local backed_up, bkp_track_name = 0, nil
    local total_cues, total_overlaps, total_abs = 0, 0, 0

    for _, blk in ipairs(blocks) do
      local moved, bname = M.backup_and_clear_range(sub_track, blk.start_pos, blk.end_pos, opts.make_backup ~= false)
      backed_up = backed_up + moved
      if bname then bkp_track_name = bname end

      local kind = (operation == "reference") and "riferimento" or "sostituzione"
      local lang = (operation == "reference") and lang_tag:lower() or ""
      local stored = register_srt_if_saved(blk.source_id, blk.srt_path, lang, kind, opts.copy_to_media)
      local c_cnt, ov_cnt = M.write_cues_to_track(sub_track, blk.cues, blk.start_pos, opts.overlap_mode, stored)
      total_cues = total_cues + c_cnt
      total_overlaps = total_overlaps + ov_cnt
      total_abs = total_abs + blk.absorbed
    end

    reaper.SetOnlyTrackSelected(sub_track)
    if reaper.TrackList_AdjustWindows then reaper.TrackList_AdjustWindows(false) end
    reaper.UpdateArrange()
    return {
      track_name = target_track_name,
      blocks     = #blocks,
      cues       = total_cues,
      overlaps   = total_overlaps,
      absorbed   = total_abs,
      backed_up  = backed_up,
      bkp_track  = bkp_track_name
    }
  end)

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ZP SRT: " .. (operation == "reference" and ("aggiungi lingua " .. lang_tag) or "sostituisci sottotitoli"), -1)
  if not ok then
    reaper.Undo_DoUndo2(0)
    return nil, tostring(res)
  end
  return res, nil
end

---------------------------------------------------------------------------
-- 12. TAB 3 · ISPEZIONE, MODIFICA, ACCORPA ITEM BREVI, UNISCI/DIVIDI/OFFSET
---------------------------------------------------------------------------

function M.inspect_selection()
  local count = reaper.CountSelectedMediaItems(0)
  if count == 0 then return nil end
  local item = reaper.GetSelectedMediaItem(0, 0)
  local track = reaper.GetMediaItem_Track(item)
  local tr_name = get_track_name(track)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local src_path = item_source_path(item)
  local notes = get_item_str(item, "P_NOTES"):gsub("\r\n", "\n"):gsub("\r", "\n")
  local clean_notes = M.trim(notes)

  local info = {
    item       = item,
    count      = count,
    track_name = tr_name ~= "" and tr_name or "(senza nome)",
    pos        = pos,
    end_pos    = pos + len,
    len        = len,
    is_text    = (src_path == "" and reaper.GetMediaItemNumTakes(item) == 0),
    is_video   = M.is_video_file(src_path),
    is_audio   = (src_path ~= "" and not M.is_video_file(src_path)),
    src_path   = src_path,
    text       = clean_notes,
    raw_notes  = notes,
    words      = M.count_words(clean_notes),
    lines      = M.count_lines(clean_notes),
    cps        = M.cps(clean_notes, len),
    srt_file   = M.trim(get_item_str(item, "P_EXT:RythmoBand_SRT_FILE")),
    srt_path   = M.trim(get_item_str(item, "P_EXT:RythmoBand_SRT_PATH")),
    srt_cue    = M.trim(get_item_str(item, "P_EXT:RythmoBand_SRT_CUE")),
    sync_key   = M.trim(get_item_str(item, "P_EXT:ZP_SYNC_KEY"))
  }

  if info.srt_file == "" and info.srt_path ~= "" then
    info.srt_file = M.basename(info.srt_path)
  end
  if info.is_audio then
    local take = reaper.GetActiveTake(item)
    info.take_markers = take and reaper.GetNumTakeMarkers(take) or 0
  end
  return info
end

function M.create_blank_cue(track_name, text, duration)
  local name = M.trim(track_name) ~= "" and M.trim(track_name) or M.SUBTITLE_TRACK_NAME
  local body = M.trim(text) ~= "" and M.trim(text) or "TESTO"
  local len  = math.max(0.5, tonumber(duration) or 3.0)
  local pos  = reaper.GetCursorPosition()
  local testo = ZP_TESTO()

  reaper.Undo_BeginBlock()
  local tr = M.get_or_create_subtitle_track(name)
  local item = reaper.AddMediaItemToTrack(tr)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len)
  reaper.SetMediaItemInfo_Value(item, "F_FREEMODE_Y", 0.02)
  reaper.SetMediaItemInfo_Value(item, "F_FREEMODE_H", 0.46)
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", native_color(M.COLOR_SUBS))
  set_item_str(item, "P_NOTES", body)
  testo.name_text_item(reaper, item, body)
  reaper.SelectAllMediaItems(0, false)
  reaper.SetMediaItemSelected(item, true)
  reaper.SetOnlyTrackSelected(tr)
  reaper.UpdateItemInProject(item)
  if reaper.TrackList_AdjustWindows then reaper.TrackList_AdjustWindows(false) end
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("ZP SRT: nuova battuta alla playhead", -1)
  return item
end

-- Unisce una singola lista di MediaItem* sulla stessa traccia preservando ancore Gobbo e highlight
-- (senza aprire sotto-blocchi Undo annidati, così funziona anche per decine di gruppi in 1 solo Cmd+Z!)
local function merge_item_group_in_place(items)
  local testo = ZP_TESTO()
  if #items < 2 then return false end
  local list, track = {}, nil
  for _, item in ipairs(items) do
    if not reaper.ValidatePtr2(0, item, "MediaItem*") then return false end
    if reaper.GetMediaItemNumTakes(item) > 0 then return false end
    if M.trim(get_item_str(item, "P_EXT:ZP_SYNC_KEY")) ~= "" then return false end
    local tr = reaper.GetMediaItem_Track(item)
    if track and tr ~= track then return false end
    track = tr
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local raw = get_item_str(item, "P_NOTES"):gsub("\r\n", "\n"):gsub("\r", "\n")
    list[#list + 1] = {
      item       = item,
      pos        = pos,
      finish     = pos + len,
      order      = #list,
      text       = raw,
      anchors    = testo.parse_anchors(get_item_str(item, "P_EXT:ZP_GOBBO_ANCHORS")),
      highlights = get_item_str(item, "P_EXT:RythmoBand_HIGHLIGHT")
    }
  end
  table.sort(list, function(a, b)
    if a.pos ~= b.pos then return a.pos < b.pos end
    return a.order < b.order
  end)

  local parts, anchors, terms, seen = {}, {}, {}, {}
  local finish = list[1].finish
  local size = 0
  for _, e in ipairs(list) do
    local lead = #(e.text:match("^%s*") or "")
    local body = M.trim(e.text)
    if e.finish > finish then finish = e.finish end
    if body ~= "" then
      -- Se il personaggio è ripetuto identico ("MARIO: ..."), lo pulisce mantenendo l'offset
      if #parts > 0 then
        local prev_role = extract_speaker_prefix(parts[1])
        local cur_role  = extract_speaker_prefix(body)
        if prev_role and cur_role and prev_role:lower() == cur_role:lower() then
          local stripped = body:gsub("^([^:\r\n]+:%s*)", "", 1)
          lead = lead + (#body - #stripped)
          body = stripped
        end
      end
      local shift = size + (#parts > 0 and 1 or 0) - lead
      for _, anchor in ipairs(e.anchors) do
        anchors[#anchors + 1] = {
          guid   = anchor.guid,
          offset = anchor.offset > 0 and math.max(1, anchor.offset + shift) or anchor.offset
        }
      end
      size = size + (#parts > 0 and 1 or 0) + #body
      parts[#parts + 1] = body
    end
    for term in e.highlights:gmatch("[^\r\n]+") do
      if not seen[term] then seen[term] = true; terms[#terms + 1] = term end
    end
  end

  local merged_text = table.concat(parts, " ")
  local first = list[1]
  set_item_str(first.item, "P_NOTES", merged_text)
  set_item_str(first.item, "P_EXT:ZP_GOBBO_ANCHORS", testo.serialize_anchors(anchors))
  set_item_str(first.item, "P_EXT:RythmoBand_HIGHLIGHT", table.concat(terms, "\n"))
  set_item_str(first.item, "P_EXT:ZP_GOBBO_TIMING", "")
  set_item_str(first.item, "P_EXT:ZP_GOBBO_TIMING_TEXT", "")
  reaper.SetMediaItemInfo_Value(first.item, "D_LENGTH", math.max(0.1, finish - first.pos))
  for i = 2, #list do
    reaper.DeleteTrackMediaItem(track, list[i].item)
  end
  testo.name_text_item(reaper, first.item, merged_text)
  reaper.UpdateItemInProject(first.item)
  return true, first.item
end

-- Esegue "Accorpa item brevi" su: "selected", "region" o "track"
function M.run_short_coalesce(scope, track, opts)
  opts = opts or {}
  local batches = {}

  if scope == "selected" then
    local sel = M.collect_selected_text_items()
    if #sel < 2 then return nil, "Seleziona almeno 2 battute di testo (oppure scegli Regione o Traccia)." end
    local by_tr, tr_order = {}, {}
    for _, it in ipairs(sel) do
      if not by_tr[it.track] then
        by_tr[it.track] = {}
        tr_order[#tr_order + 1] = it.track
      end
      by_tr[it.track][#by_tr[it.track] + 1] = it
    end
    for _, tr in ipairs(tr_order) do batches[#batches + 1] = by_tr[tr] end
  elseif scope == "region" then
    if not track then return nil, "Nessuna traccia testi attiva." end
    local reg = M.region_at_cursor()
    if not reg then return nil, "Posiziona la playhead dentro una regione." end
    local items = M.collect_text_items_on_track(track, reg.start_pos, reg.end_pos)
    if #items < 2 then return nil, "Meno di 2 battute di testo nella regione corrente." end
    batches[1] = items
  else
    if not track then return nil, "Nessuna traccia testi attiva." end
    local items = M.collect_text_items_on_track(track)
    if #items < 2 then return nil, "Meno di 2 battute sulla traccia testi." end
    batches[1] = items
  end

  local planned_ops = {}
  local total_absorbed = 0
  for _, list in ipairs(batches) do
    local m_groups, abs = M.plan_short_merges(list, opts)
    total_absorbed = total_absorbed + abs
    for _, g in ipairs(m_groups) do
      local ptrs = {}
      for _, idx in ipairs(g.indices) do
        ptrs[#ptrs + 1] = list[idx].item
      end
      planned_ops[#planned_ops + 1] = ptrs
    end
  end

  if total_absorbed == 0 or #planned_ops == 0 then
    return { groups = 0, absorbed = 0 }, nil
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local merged_groups = 0
  local survivors = {}
  for _, ptrs in ipairs(planned_ops) do
    local ok_m, kept = merge_item_group_in_place(ptrs)
    if ok_m then
      merged_groups = merged_groups + 1
      if kept then survivors[#survivors + 1] = kept end
    end
  end
  if scope == "selected" and #survivors > 0 then
    reaper.SelectAllMediaItems(0, false)
    for _, it in ipairs(survivors) do
      if reaper.ValidatePtr2(0, it, "MediaItem*") then
        reaper.SetMediaItemSelected(it, true)
      end
    end
  end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("ZP SRT: accorpa item brevi", -1)

  return { groups = merged_groups, absorbed = total_absorbed }, nil
end

function M.merge_selected_or_next()
  local testo = ZP_TESTO()
  local sel = M.collect_selected_text_items()
  if #sel == 0 then return nil, "Seleziona una o più battute di testo sulla stessa traccia." end

  local targets = {}
  if #sel == 1 then
    local cur = sel[1]
    local all_on_tr = M.collect_text_items_on_track(cur.track)
    local nxt = nil
    for i, e in ipairs(all_on_tr) do
      if e.item == cur.item then
        nxt = all_on_tr[i + 1]
        break
      end
    end
    if not nxt then return nil, "Non c'è una battuta successiva su questa traccia." end
    targets = { cur.item, nxt.item }
  else
    for _, e in ipairs(sel) do targets[#targets + 1] = e.item end
  end

  local merged_item, info = testo.merge_text_items(reaper, targets, function(it, txt)
    testo.name_text_item(reaper, it, txt)
  end)
  if not merged_item then return nil, tostring(info) end
  return info, nil
end

function M.split_at_playhead(active_track)
  local cur = reaper.GetCursorPosition()
  local target = nil

  -- Cerca prima tra gli item selezionati, altrimenti sulla traccia testi attiva sotto la playhead
  for _, it in ipairs(M.collect_selected_text_items()) do
    if cur > it.start_pos + 0.08 and cur < it.end_pos - 0.08 then
      target = it; break
    end
  end
  if not target and active_track then
    for _, it in ipairs(M.collect_text_items_on_track(active_track)) do
      if cur > it.start_pos + 0.08 and cur < it.end_pos - 0.08 then
        target = it; break
      end
    end
  end
  if not target then
    return nil, "Metti la playhead all'interno della battuta da dividere (almeno a 80 ms dai bordi)."
  end
  if target.sync_key ~= "" then
    return nil, "Questa battuta segue un marker audio (29): dividila dall'item audio."
  end

  local ratio = (cur - target.start_pos) / math.max(0.1, target.len)
  local left_txt, right_txt = M.split_cue_at_ratio(target.raw_notes, ratio)
  if not left_txt or not right_txt then
    return nil, "Serve almeno una coppia di parole per poter dividere la battuta."
  end

  local testo = ZP_TESTO()
  reaper.Undo_BeginBlock()
  local right_item = reaper.SplitMediaItem(target.item, cur)
  if not right_item then
    reaper.Undo_EndBlock("ZP SRT: dividi annullato", -1)
    return nil, "REAPER non ha potuto dividere l'item alla playhead."
  end
  set_item_str(target.item, "P_NOTES", left_txt)
  set_item_str(right_item,  "P_NOTES", right_txt)
  set_item_str(target.item, "P_EXT:ZP_GOBBO_TIMING", "")
  set_item_str(right_item,  "P_EXT:ZP_GOBBO_TIMING", "")
  testo.name_text_item(reaper, target.item, left_txt)
  testo.name_text_item(reaper, right_item, right_txt)
  reaper.SelectAllMediaItems(0, false)
  reaper.SetMediaItemSelected(right_item, true)
  reaper.UpdateItemInProject(target.item)
  reaper.UpdateItemInProject(right_item)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("ZP SRT: dividi battuta alla playhead", -1)
  return { left = left_txt, right = right_txt }, nil
end

function M.split_multiline_selected()
  local sel = M.collect_selected_text_items()
  if #sel == 0 then return nil, "Seleziona almeno una battuta multi-riga (o con più frasi) da separare." end
  local testo = ZP_TESTO()

  local plans = {}
  for _, it in ipairs(sel) do
    if it.sync_key == "" then
      local parts = M.split_cue_lines(it.raw_notes, it.start_pos, it.end_pos)
      if parts and #parts >= 2 then
        plans[#plans + 1] = { orig = it, parts = parts }
      end
    end
  end
  if #plans == 0 then
    return nil, "Nessuna delle battute selezionate ha più righe o più frasi separabili."
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local created_total = 0
  local new_sel = {}
  for _, pl in ipairs(plans) do
    local orig = pl.orig
    local tr = orig.track
    local col = reaper.GetMediaItemInfo_Value(orig.item, "I_CUSTOMCOLOR")
    local fy  = reaper.GetMediaItemInfo_Value(orig.item, "F_FREEMODE_Y")
    local fh  = reaper.GetMediaItemInfo_Value(orig.item, "F_FREEMODE_H")
    local spath = get_item_str(orig.item, "P_EXT:RythmoBand_SRT_PATH")
    local sfile = get_item_str(orig.item, "P_EXT:RythmoBand_SRT_FILE")

    -- Aggiorna il primo sul posto e crea i successivi
    local p1 = pl.parts[1]
    reaper.SetMediaItemInfo_Value(orig.item, "D_POSITION", p1.start_pos)
    reaper.SetMediaItemInfo_Value(orig.item, "D_LENGTH", p1.end_pos - p1.start_pos)
    set_item_str(orig.item, "P_NOTES", p1.text)
    set_item_str(orig.item, "P_EXT:ZP_GOBBO_TIMING", "")
    testo.name_text_item(reaper, orig.item, p1.text)
    reaper.UpdateItemInProject(orig.item)
    new_sel[#new_sel + 1] = orig.item
    created_total = created_total + 1

    for k = 2, #pl.parts do
      local pk = pl.parts[k]
      local ni = reaper.AddMediaItemToTrack(tr)
      reaper.SetMediaItemInfo_Value(ni, "D_POSITION", pk.start_pos)
      reaper.SetMediaItemInfo_Value(ni, "D_LENGTH", pk.end_pos - pk.start_pos)
      if col and col ~= 0 then reaper.SetMediaItemInfo_Value(ni, "I_CUSTOMCOLOR", col) end
      if fy and fh and fh > 0 then
        reaper.SetMediaItemInfo_Value(ni, "F_FREEMODE_Y", fy)
        reaper.SetMediaItemInfo_Value(ni, "F_FREEMODE_H", fh)
      end
      set_item_str(ni, "P_NOTES", pk.text)
      if spath ~= "" then set_item_str(ni, "P_EXT:RythmoBand_SRT_PATH", spath) end
      if sfile ~= "" then set_item_str(ni, "P_EXT:RythmoBand_SRT_FILE", sfile) end
      testo.name_text_item(reaper, ni, pk.text)
      reaper.UpdateItemInProject(ni)
      new_sel[#new_sel + 1] = ni
      created_total = created_total + 1
    end
  end

  reaper.SelectAllMediaItems(0, false)
  for _, it in ipairs(new_sel) do reaper.SetMediaItemSelected(it, true) end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("ZP SRT: dividi righe in battute", -1)
  return { split_items = #plans, resulting = created_total }, nil
end

function M.nudge_text_items(scope, active_track, delta_sec, snap_first_to_cursor)
  local list
  if scope == "selected" then
    list = M.collect_selected_text_items()
    if #list == 0 then return nil, "Seleziona le battute di testo da spostare." end
  elseif scope == "region" then
    local reg = M.region_at_cursor()
    if not reg or not active_track then return nil, "Posiziona la playhead in una regione con traccia testi attiva." end
    list = M.collect_text_items_on_track(active_track, reg.start_pos, reg.end_pos)
  else
    if not active_track then return nil, "Nessuna traccia testi attiva." end
    list = M.collect_text_items_on_track(active_track)
  end
  if #list == 0 then return nil, "Nessuna battuta trovata." end

  local shift = tonumber(delta_sec) or 0
  if snap_first_to_cursor then
    shift = reaper.GetCursorPosition() - list[1].start_pos
  end
  -- Evita di spingere prima di 00:00:00
  if list[1].start_pos + shift < 0 then
    shift = -list[1].start_pos
  end
  if math.abs(shift) < 0.0005 then return { moved = 0, shift = 0 }, nil end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local moved = 0
  for _, it in ipairs(list) do
    if it.sync_key == "" then
      reaper.SetMediaItemInfo_Value(it.item, "D_POSITION", math.max(0, it.start_pos + shift))
      reaper.UpdateItemInProject(it.item)
      moved = moved + 1
    end
  end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("ZP SRT: sposta battute nel tempo", -1)
  return { moved = moved, shift = shift }, nil
end

---------------------------------------------------------------------------
-- 13. TAB 4 · ESPORTA SRT (DA TIMELINE E DAI MARKER DELL'AUDIO)
---------------------------------------------------------------------------

local function find_region_for_video(video, regions)
  local mid = video.start_pos + video.len * 0.5
  for _, r in ipairs(regions) do
    if mid >= r.start_pos - 0.001 and mid <= r.end_pos + 0.001 then
      return r
    end
  end
  return nil
end

function M.export_timeline_srt(opts)
  opts = opts or {}
  local track = opts.track
  if not track then return nil, "Nessuna traccia testi selezionata per l'esportazione." end
  local scope = opts.scope or "selected_videos"
  local out_dir = M.trim(opts.out_dir or "")
  if out_dir == "" then out_dir = M.default_dir() .. sep .. "SRT_export" end
  M.ensure_dir(out_dir)

  local regions = M.collect_regions()
  local ranges = {}
  if scope == "selected_videos" then
    for _, v in ipairs(M.collect_video_items(true)) do
      local reg = find_region_for_video(v, regions)
      ranges[#ranges + 1] = { base = reg and reg.base or v.base, start_pos = v.start_pos, end_pos = v.end_pos, source_id = v.path }
    end
  elseif scope == "cursor_region" then
    local r = M.region_at_cursor(regions)
    if r then
      ranges[1] = { base = r.base, start_pos = r.start_pos, end_pos = r.end_pos, source_id = "region:" .. r.base .. ":" .. string.format("%.3f", r.start_pos) }
    end
  elseif scope == "all_regions" then
    for _, r in ipairs(regions) do
      ranges[#ranges + 1] = { base = r.base, start_pos = r.start_pos, end_pos = r.end_pos, source_id = "region:" .. r.base .. ":" .. string.format("%.3f", r.start_pos) }
    end
  elseif scope == "all_videos" then
    for _, v in ipairs(M.collect_video_items(false)) do
      local reg = find_region_for_video(v, regions)
      ranges[#ranges + 1] = { base = reg and reg.base or v.base, start_pos = v.start_pos, end_pos = v.end_pos, source_id = v.path }
    end
  elseif scope == "whole_track" then
    local all_items = M.collect_text_items_on_track(track)
    if #all_items > 0 then
      local tr_name = get_track_name(track)
      ranges[1] = {
        base      = M.safe_filename(tr_name),
        start_pos = 0.0,
        end_pos   = all_items[#all_items].end_pos + 1.0,
        source_id = "track:" .. tr_name
      }
    end
  end

  if #ranges == 0 then
    return nil, "Nessun intervallo trovato per il modo di esportazione scelto."
  end

  local all_subs = M.collect_text_items_on_track(track)
  if #all_subs == 0 then
    return nil, "La traccia testi scelta non contiene battute."
  end

  local written, skipped_empty = {}, 0
  for _, rg in ipairs(ranges) do
    local rel_cues = {}
    for _, sub in ipairs(all_subs) do
      if sub.text ~= "" and sub.start_pos >= rg.start_pos - 0.001 and sub.start_pos < rg.end_pos + 0.001 then
        local cs = math.max(0, sub.start_pos - rg.start_pos)
        local ce = math.max(cs + 0.15, sub.end_pos - rg.start_pos)
        rel_cues[#rel_cues + 1] = { start_pos = cs, end_pos = ce, text = sub.text }
      end
    end
    if #rel_cues > 0 then
      local fname = M.safe_filename(rg.base) .. ".srt"
      local out_path = out_dir .. sep .. fname
      if opts.make_bak ~= false and M.file_exists(out_path) then
        local old = M.read_file(out_path)
        if old then M.write_file(out_path .. ".bak", old) end
      end
      local ok_w, werr = M.write_file(out_path, M.format_srt(rel_cues))
      if not ok_w then return nil, werr end
      register_srt_if_saved(rg.source_id, out_path, "", "esportazione:" .. fname:lower(), opts.copy_to_media)
      written[#written + 1] = { path = out_path, name = fname, cues = #rel_cues }
    else
      skipped_empty = skipped_empty + 1
    end
  end

  if #written == 0 then
    return nil, "Nessuna battuta cade negli intervalli scelti."
  end
  return { files = written, skipped = skipped_empty, out_dir = out_dir }, nil
end

function M.export_audio_markers_srt(opts)
  opts = opts or {}
  local sources = M.collect_selected_audio_marker_sources()
  if #sources == 0 then
    return nil, "Seleziona almeno un item audio con take marker delle battute."
  end
  local out_dir = M.trim(opts.out_dir or "")
  if out_dir == "" then out_dir = M.default_dir() .. sep .. "SRT_export" end
  M.ensure_dir(out_dir)

  local existing_mode = opts.existing_mode or "bak" -- "bak", "overwrite", "skip"
  local written, skipped = {}, 0

  for _, src in ipairs(sources) do
    if #src.cues > 0 then
      local fname = M.safe_filename(M.stem(src.path)) .. ".srt"
      local out_path = out_dir .. sep .. fname
      local exists = M.file_exists(out_path)
      if exists and existing_mode == "skip" then
        skipped = skipped + 1
      else
        if exists and existing_mode == "bak" then
          local old = M.read_file(out_path)
          if old then M.write_file(out_path .. ".bak", old) end
        end
        local ok_w, werr = M.write_file(out_path, M.format_srt(src.cues))
        if not ok_w then return nil, werr end
        register_srt_if_saved(src.path, out_path, "", "marker_audio", opts.copy_to_media)
        written[#written + 1] = { path = out_path, name = fname, cues = #src.cues }
      end
    else
      skipped = skipped + 1
    end
  end

  if #written == 0 then
    return nil, "Nessun marker di testo esportato dagli item audio selezionati."
  end
  return { files = written, skipped = skipped, out_dir = out_dir }, nil
end

return M
