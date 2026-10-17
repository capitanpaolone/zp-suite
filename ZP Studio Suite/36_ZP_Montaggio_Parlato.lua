-- @noindex
-- ZP Studio Suite for REAPER
-- 36 ZP Montaggio Parlato (prova, Fase 0+1): lo sgrossatore del parlato.
--
-- Legge gli item audio (selezionati, o tutta la traccia selezionata), li trascrive con ZP Speech
-- (parole con i tempi, in cache accanto al WAV: <nome>.zpwords.json), ascolta il file (click,
-- attacchi, voce che Whisper ha saltato e che viene ritrascritta a pezzi) e, col copione se c'e',
-- propone la struttura del montato:
--   * rifacimenti (click forti o parole del dizionario): via dall'attacco della prima versione
--     all'attacco della seconda, inizio su inizio
--   * stessa frase letta piu' volte: vince l'ultima completa
--   * "alternativa": la lettura dopo va nella corsia sotto (che non suona)
--   * parlato fuori testo e comandi: via
-- La pagina mostra il parlato come un copione segnato (barrato = si toglie). Si decide qui,
-- APPLICA lavora sugli item della traccia (split, niente render), con un solo Undo, e scrive le
-- note di montaggio in una traccia "ZP Montaggio <voce>" che si mostra/nasconde.
-- Il software sgrossa: il lavoro di fino si fa ascoltando in Timeline.
-- Progetto: docs/PROGETTO_22_Centrale_Montaggio_Parlato.md

local sep = package.config:sub(1, 1)
local SCRIPT_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "")
local UI = dofile(SCRIPT_DIR .. "ZP_UI.lua")
local M = dofile(SCRIPT_DIR .. "ZP_Montaggio.lua")
local T = UI.T

local TITLE = "ZP Montaggio Parlato"
local EXT = "ZP_MONTAGGIO"
local W0, H0 = 1240, 820

---------------------------------------------------------------------------
-- piccoli aiuti
---------------------------------------------------------------------------
local function q(v) return "'" .. tostring(v):gsub("'", "'\\''") .. "'" end
local function exists(p) local f = io.open(p, "rb"); if f then f:close(); return true end return false end
local function read_file(p) local f = io.open(p, "rb"); if not f then return nil end local d = f:read("*a"); f:close(); return d end
local function write_file(p, d) local f = io.open(p, "wb"); if not f then return false end f:write(d); f:close(); return true end
local function now() return reaper.time_precise() end
local function get_ext(k, def) local v = reaper.GetExtState(EXT, k); if v == "" then return def end return v end
local function set_ext(k, v) reaper.SetExtState(EXT, k, tostring(v), true) end
local function fmt_t(sec)
  sec = math.max(0, sec or 0)
  return string.format("%d:%05.2f", math.floor(sec / 60), sec % 60):gsub("%.", ",")
end

local function speech_cli()
  return (os.getenv("HOME") or "") .. "/Library/Application Support/ZP/runtimes/speech/bin/zp-speech"
end

local function jobs_dir()
  local d = reaper.GetResourcePath() .. sep .. "ZP_jobs" .. sep .. "montaggio"
  os.execute("/bin/mkdir -p " .. q(d))
  return d
end

local function project_dir()
  local _, fn = reaper.EnumProjects(-1)
  local dir = fn and fn ~= "" and fn:match("^(.*)[/\\]") or nil
  dir = (dir or (reaper.GetResourcePath() .. sep .. "ZP_Montaggio_senza_progetto")) .. sep .. "ZP_Montaggio"
  os.execute("/bin/mkdir -p " .. q(dir))
  return dir
end

---------------------------------------------------------------------------
-- stato
---------------------------------------------------------------------------
local S = {
  scope = get_ext("scope", "item"),          -- item | traccia
  modo = get_ext("modo", "slide"),           -- slide | timeline
  segnale = get_ext("segnale", "entrambi"),  -- click | parole | entrambi
  note_visibili = get_ext("note_visibili", "1") == "1",
  solo_dubbi = false,
  copione = nil, copione_nome = "",
  blocks = nil,                              -- un blocco per item analizzato
  status = T("Seleziona gli item (o una traccia), carica il copione se c'e', poi ANALIZZA."),
  busy = nil,                                -- coroutine dell'analisi
  sel = nil,                                 -- { b = blocco, iv = intervento }
  scroll = 0, page_h = 0,
  layout = nil, layout_w = 0,
  stop_at = nil,
  last_down = false,
}

---------------------------------------------------------------------------
-- copione: file (doc, docx, rtf, odt, pdf, txt) o appunti; resta nella cartella del progetto
---------------------------------------------------------------------------
local function copione_path() return project_dir() .. sep .. "copione.txt" end

local function load_saved_copione()
  local _, name = reaper.GetProjExtState(0, EXT, "copione_nome")
  local txt = read_file(copione_path())
  if txt and txt ~= "" then S.copione = txt; S.copione_nome = name ~= "" and name or T("copione") end
end

local function set_copione(txt, name)
  txt = tostring(txt or ""):gsub("\r\n?", "\n")
  if txt:match("^%s*$") then S.status = T("Il copione e' vuoto: niente caricato."); return end
  S.copione, S.copione_nome = txt, name
  write_file(copione_path(), txt)
  reaper.SetProjExtState(0, EXT, "copione_nome", name)
  local n = #M.tokens(txt)
  S.status = string.format(T("Copione caricato: %s, %d parole, %d frasi. Ora ANALIZZA."), name, n, #M.parse_copione(txt))
  if S.blocks then S.status = S.status .. " " .. T("(serve rifare l'analisi)") end
end

local function extract_text(path)
  local ext = (path:match("%.([%w]+)$") or ""):lower()
  if ext == "txt" or ext == "srt" then return read_file(path) end
  local cmd
  if ext == "pdf" then
    for _, p in ipairs({ "/opt/homebrew/bin/pdftotext", "/usr/local/bin/pdftotext" }) do
      if exists(p) then cmd = q(p) .. " -layout " .. q(path) .. " - 2>/dev/null" break end
    end
    if not cmd then return nil, T("Per i PDF serve pdftotext (brew install poppler). Intanto: apri il PDF, copia il testo e usa Incolla.") end
  else
    cmd = "/usr/bin/textutil -convert txt -stdout " .. q(path) .. " 2>/dev/null"
  end
  local h = io.popen(cmd); if not h then return nil, T("Non riesco a leggere il file.") end
  local out = h:read("*a"); h:close()
  if not out or out:match("^%s*$") then return nil, T("Dal file non esce testo (forse e' un'immagine scansionata).") end
  return out
end

local function choose_copione_file()
  local ok, path = reaper.GetUserFileNameForRead("", T("Copione (doc, docx, pdf, rtf, odt, txt)"), "")
  if not ok or not path or path == "" then return end
  local txt, err = extract_text(path)
  if not txt then S.status = err; return end
  set_copione(txt, path:match("([^/\\]+)$") or path)
end

local function paste_copione()
  if not reaper.CF_GetClipboard then S.status = T("Incolla richiede SWS: usa Carica file."); return end
  local txt = reaper.CF_GetClipboard("")
  set_copione(txt, T("testo incollato"))
end

---------------------------------------------------------------------------
-- item da lavorare
---------------------------------------------------------------------------
local function item_info(item)
  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then return nil end
  local src = reaper.GetMediaItemTake_Source(take)
  if reaper.GetMediaSourceParent then
    local parent = reaper.GetMediaSourceParent(src)
    while parent do src = parent; parent = reaper.GetMediaSourceParent(src) end
  end
  local path = reaper.GetMediaSourceFileName(src, "")
  if not path or path == "" then return nil end
  local _, name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"); if rate <= 0 then rate = 1 end
  return {
    item = item, take = take, track = reaper.GetMediaItem_Track(item), path = path,
    name = (name ~= "" and name) or path:match("([^/\\]+)$"),
    pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION"),
    len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
    offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"), rate = rate,
  }
end

local function collect_items()
  local list = {}
  if S.scope == "traccia" then
    local tr = reaper.GetSelectedTrack(0, 0)
    if not tr then return list, T("Seleziona una traccia.") end
    for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local it = item_info(reaper.GetTrackMediaItem(tr, i))
      if it then list[#list + 1] = it end
    end
  else
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
      local it = item_info(reaper.GetSelectedMediaItem(0, i))
      if it then list[#list + 1] = it end
    end
  end
  table.sort(list, function(a, b)
    if a.track ~= b.track then
      return reaper.GetMediaTrackInfo_Value(a.track, "IP_TRACKNUMBER") < reaper.GetMediaTrackInfo_Value(b.track, "IP_TRACKNUMBER")
    end
    return a.pos < b.pos
  end)
  if #list == 0 then return list, T("Nessun item audio: seleziona gli item o una traccia.") end
  return list
end

-- sorgente <-> progetto per un item
local function src_to_proj(b, t) return b.pos + (t - b.offs) / b.rate end

---------------------------------------------------------------------------
-- lavori in background (ZP Speech), uno alla volta
---------------------------------------------------------------------------
local function run_speech(wav, out_json)
  local d = jobs_dir()
  local done = d .. sep .. "done_" .. tostring(math.floor(now() * 1000))
  os.remove(done)
  local cmd = q(speech_cli()) .. " request " .. q(wav) .. " --format json --language it --output " .. q(out_json .. ".part")
    .. " && /bin/mv " .. q(out_json .. ".part") .. " " .. q(out_json)
  os.execute("/usr/bin/nohup /bin/bash -c " .. q("{ " .. cmd .. " ; } >/dev/null 2>&1; echo $? > " .. q(done)) .. " </dev/null >/dev/null 2>&1 &")
  local t0 = now()
  while not exists(done) do
    if now() - t0 > 3600 then return false, "timeout" end
    coroutine.yield()
  end
  local code = tonumber((read_file(done) or ""):match("%d+")) or 1
  os.remove(done)
  return code == 0
end

local function cache_path(wav) return (wav:gsub("%.[^./\\]+$", "")) .. ".zpwords.json" end

---------------------------------------------------------------------------
-- analisi (coroutine: non blocca la finestra)
---------------------------------------------------------------------------
local function analyze_job()
  local items, err = collect_items()
  if err then S.status = err; return end
  if not exists(speech_cli()) then
    S.status = T("ZP Speech non e' installato: nel repo zp-suite lancia speech-engine/install_macos.sh.")
    return
  end
  local frasi = S.copione and M.parse_copione(S.copione) or {}
  local by_path, paths = {}, {}
  for _, it in ipairs(items) do
    if not by_path[it.path] then by_path[it.path] = { path = it.path }; paths[#paths + 1] = it.path end
  end
  -- 1. trascrizioni (in cache accanto al WAV)
  for i, p in ipairs(paths) do
    local src = by_path[p]
    if not p:lower():match("%.wav$") then src.err = T("non e' un WAV") else
      local cp = cache_path(p)
      if not exists(cp) then
        S.status = string.format(T("Trascrivo %d di %d: %s (la prima volta; poi resta in cache)"), i, #paths, p:match("([^/\\]+)$"))
        if not run_speech(p, cp) then src.err = T("trascrizione non riuscita") end
      end
      if not src.err then
        local ok, doc = pcall(M.json_decode, read_file(cp) or "")
        if ok and doc then src.words = M.words_from_transcript(doc) else src.err = T("trascrizione illeggibile") end
      end
    end
  end
  -- 2. ascolto del file: energia, click
  for i, p in ipairs(paths) do
    local src = by_path[p]
    if not src.err then
      local info, e = M.wav_open(p)
      if not info then src.err = e else
        local env = M.env_new(info.sr, 0.005)
        local t0 = now()
        while true do
          local got = M.wav_read_env(info, env, 24000)
          if got == 0 then break end
          if now() - t0 > 0.03 then
            S.status = string.format(T("Ascolto il file %d di %d: %d%%"), i, #paths, math.floor(100 * info.pos / info.frames))
            coroutine.yield(); t0 = now()
          end
        end
        src.len = info.len
        M.wav_close(info)
        src.env = env
        src.clicks = M.find_clicks(env, tonumber(get_ext("click_db", "-12")))
      end
    end
  end
  -- 3. voce che Whisper ha saltato: ritrascrivo solo quei pezzi (solo dentro le parti usate)
  for _, p in ipairs(paths) do
    local src = by_path[p]
    if not src.err then
      local frs = M.fragments_needed(src.env, src.words, src.clicks, { min_voice = 0.8 })
      local used = {}
      for _, it in ipairs(items) do
        if it.path == p then used[#used + 1] = { s = it.offs, e = it.offs + it.len * it.rate } end
      end
      local todo = {}
      for _, f in ipairs(frs) do
        for _, u in ipairs(used) do if f.e > u.s and f.s < u.e then todo[#todo + 1] = f; break end end
      end
      for n, f in ipairs(todo) do
        S.status = string.format(T("Whisper ha saltato della voce: ritrascrivo il pezzo %d di %d (%s)"), n, #todo, fmt_t(f.s))
        local fw = jobs_dir() .. sep .. "frammento.wav"
        local fj = jobs_dir() .. sep .. "frammento.json"
        os.remove(fj)
        if M.wav_fragment(p, fw, f.s, f.e) and run_speech(fw, fj) then
          local ok, doc = pcall(M.json_decode, read_file(fj) or "")
          if ok and doc then src.words = M.merge_fragment(src.words, M.words_from_transcript(doc, f.s), f) end
        end
      end
    end
  end
  -- 4. piano per item
  local blocks = {}
  for _, it in ipairs(items) do
    local src = by_path[it.path]
    local b = it
    b.err = src.err
    if not src.err then
      local s0, s1 = it.offs, it.offs + it.len * it.rate
      local words = {}
      for _, w in ipairs(src.words) do if w.s >= s0 - 0.05 and w.e <= s1 + 0.05 then words[#words + 1] = w end end
      local sigs = {}
      for _, g in ipairs(src.clicks) do if g.s >= s0 and g.e <= s1 then sigs[#sigs + 1] = g end end
      b.plan = M.plan({ words = words, env = src.env, frasi = frasi, signals = sigs, segnale = S.segnale,
                        dict = M.DIZIONARIO, len = math.min(src.len, s1) })
      -- il tenuto non esce dalla parte usata dell'item
      for _, k in ipairs(b.plan.keep) do k.s = math.max(k.s, s0); k.e = math.min(k.e, s1) end
    end
    blocks[#blocks + 1] = b
  end
  S.blocks = blocks
  S.layout = nil
  S.sel = nil
  local n_iv, n_low, n_err = 0, 0, 0
  for _, b in ipairs(blocks) do
    if b.err then n_err = n_err + 1 else
      for _, iv in ipairs(b.plan.interventi) do n_iv = n_iv + 1; if iv.sicurezza == "bassa" then n_low = n_low + 1 end end
    end
  end
  S.status = string.format(T("Analisi fatta: %d item, %d interventi, %d da controllare."), #blocks, n_iv, n_low)
  if n_err > 0 then S.status = S.status .. " " .. string.format(T("%d item saltati (vedi la pagina)."), n_err) end
  if #frasi == 0 then S.status = S.status .. " " .. T("Senza copione: trovo solo rifacimenti e comandi.") end
end

local function start_analysis()
  if S.busy then return end
  S.busy = coroutine.create(analyze_job)
end

---------------------------------------------------------------------------
-- ascolto
---------------------------------------------------------------------------
local function play_range(b, s, e)
  local ps = src_to_proj(b, s) - 1.0
  local pe = src_to_proj(b, e) + 1.0
  reaper.SetEditCurPos(math.max(0, ps), true, false)
  reaper.OnPlayButton()
  S.stop_at = pe
end

local function check_stop()
  if S.stop_at and reaper.GetPlayState() & 1 == 1 then
    if reaper.GetPlayPosition() >= S.stop_at then reaper.OnStopButton(); S.stop_at = nil end
  elseif S.stop_at and reaper.GetPlayState() & 1 == 0 then S.stop_at = nil end
end

---------------------------------------------------------------------------
-- APPLICA: split degli item, via il tolto, alternative nella corsia sotto, note di montaggio
---------------------------------------------------------------------------
local NOTE_PREFIX = "ZP Montaggio "

local function notes_track_for(voice)
  local vguid = reaper.GetTrackGUID(voice)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, v = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ZP_MONTAGGIO", "", false)
    if v == vguid then return tr end
  end
  local idx = math.floor(reaper.GetMediaTrackInfo_Value(voice, "IP_TRACKNUMBER"))
  reaper.InsertTrackAtIndex(idx, false)
  local tr = reaper.GetTrack(0, idx)
  local _, vname = reaper.GetTrackName(voice)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", NOTE_PREFIX .. vname, true)
  reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ZP_MONTAGGIO", vguid, true)
  reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 0)
  return tr
end

local function set_notes_visible(vis)
  S.note_visibili = vis
  set_ext("note_visibili", vis and "1" or "0")
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, v = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ZP_MONTAGGIO", "", false)
    if v ~= "" then reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", vis and 1 or 0) end
  end
  if reaper.TrackList_AdjustWindows then reaper.TrackList_AdjustWindows(false) end
  reaper.UpdateArrange()
end

local NOTE_COLORS = { rosso = { 220, 60, 50 }, blu = { 60, 130, 220 }, viola = { 150, 110, 230 }, arancio = { 235, 140, 40 } }
local function add_note(tr, pos, len, text, color)
  local it = reaper.AddMediaItemToTrack(tr)
  reaper.SetMediaItemInfo_Value(it, "D_POSITION", pos)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH", math.max(0.5, len))
  reaper.GetSetMediaItemInfo_String(it, "P_NOTES", text, true)
  local c = NOTE_COLORS[color] or NOTE_COLORS.blu
  reaper.SetMediaItemInfo_Value(it, "I_CUSTOMCOLOR", reaper.ColorToNative(c[1], c[2], c[3]) | 0x1000000)
end

-- corsia sotto (REAPER 7, corsie fisse) che non suona; se non riesce, traccia "ALT" mutata
local function put_in_lane(track, item)
  reaper.SetMediaTrackInfo_Value(track, "I_FREEMODE", 2)
  local lanes = reaper.GetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES")
  if lanes < 2 then reaper.SetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES", 2) end
  reaper.SetMediaItemInfo_Value(item, "I_FIXEDLANE", 1)
  reaper.SetMediaTrackInfo_Value(track, "C_LANEPLAYS:1", 0)
  if reaper.GetMediaItemInfo_Value(item, "I_FIXEDLANE") == 1 then return true end
  -- ripiego
  local idx = math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
  local alt
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, v = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ZP_MONTAGGIO_ALT", "", false)
    if v == reaper.GetTrackGUID(track) then alt = tr end
  end
  if not alt then
    reaper.InsertTrackAtIndex(idx, false)
    alt = reaper.GetTrack(0, idx)
    local _, vname = reaper.GetTrackName(track)
    reaper.GetSetMediaTrackInfo_String(alt, "P_NAME", "ALT " .. vname, true)
    reaper.GetSetMediaTrackInfo_String(alt, "P_EXT:ZP_MONTAGGIO_ALT", reaper.GetTrackGUID(track), true)
    reaper.SetMediaTrackInfo_Value(alt, "B_MUTE", 1)
  end
  reaper.MoveMediaItemToTrack(item, alt)
  return false
end

local function iv_title(iv)
  if iv.tipo == "rifacimento" then
    return (iv.segnale == "click") and T("Rifacimento (click)") or T("Rifacimento (parola)")
  elseif iv.tipo == "superata" then return T("Lettura precedente")
  elseif iv.tipo == "fuori" then return T("Fuori testo")
  elseif iv.tipo == "comando" then return T("Comando")
  elseif iv.tipo == "alternativa" then return T("Alternativa")
  elseif iv.tipo == "omessa" then return T("Non letta")
  elseif iv.tipo == "click_solo" then return T("Click senza ripresa") end
  return iv.tipo
end

local function apply_block(b, notes)
  local p = b.plan
  -- pezzi in tempo sorgente con il loro destino: tieni | alt | via
  local s0, s1 = b.offs, b.offs + b.len * b.rate
  local marks = { s0, s1 }
  for _, k in ipairs(p.keep) do marks[#marks + 1] = k.s; marks[#marks + 1] = k.e end
  local alts = {}
  for _, a in ipairs(p.alt) do
    if not a.off and a.s < s1 and a.e > s0 then
      alts[#alts + 1] = a; marks[#marks + 1] = math.max(a.s, s0); marks[#marks + 1] = math.min(a.e, s1)
    end
  end
  table.sort(marks)
  local cuts_at = {}
  for _, m in ipairs(marks) do
    if m > s0 + 0.001 and m < s1 - 0.001 and (#cuts_at == 0 or m - cuts_at[#cuts_at] > 0.002) then cuts_at[#cuts_at + 1] = m end
  end
  local pieces, cur = {}, b.item
  for _, m in ipairs(cuts_at) do
    local right = reaper.SplitMediaItem(cur, src_to_proj(b, m))
    pieces[#pieces + 1] = cur
    if not right then cur = nil; break end
    cur = right
  end
  if cur then pieces[#pieces + 1] = cur end
  local function src_of(it)
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    return b.offs + (pos - b.pos) * b.rate, b.offs + (pos + len - b.pos) * b.rate
  end
  local orig_end = b.pos + b.len
  local kept, cursor, map = {}, nil, {}
  local alt_items = {}
  for _, it in ipairs(pieces) do
    local a, e = src_of(it)
    local mid = (a + e) / 2
    local fate = "via"
    for _, k in ipairs(p.keep) do if mid > k.s and mid < k.e then fate = "tieni" end end
    if fate == "via" then for _, al in ipairs(alts) do if mid > al.s and mid < al.e then fate = "alt"; alt_items[#alt_items + 1] = { item = it, a = al } end end end
    if fate == "tieni" then
      local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if not cursor then cursor = b.pos end   -- l'item pulito parte dove partiva
      reaper.SetMediaItemInfo_Value(it, "D_POSITION", cursor)
      reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN", 0.005)
      reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", 0.005)
      map[#map + 1] = { s = a, e = e, pos = cursor }
      cursor = cursor + len
      kept[#kept + 1] = it
    elseif fate == "via" then
      reaper.DeleteTrackMediaItem(b.track, it)
    end
  end
  local function new_pos(t)
    for _, m in ipairs(map) do if t >= m.s - 0.01 and t <= m.e + 0.01 then return m.pos + (t - m.s) / b.rate end end
    for i = #map, 1, -1 do if t >= map[i].e then return map[i].pos + (map[i].e - map[i].s) / b.rate end end
    return map[1] and map[1].pos or b.pos
  end
  -- alternative sotto la lettura che sostituiscono
  local in_lane = true
  for _, x in ipairs(alt_items) do
    local target = x.a.sotto and new_pos(x.a.sotto) or (cursor or b.pos)
    reaper.SetMediaItemInfo_Value(x.item, "D_POSITION", target)
    if not put_in_lane(b.track, x.item) then in_lane = false end
  end
  -- note di montaggio
  local tr = notes_track_for(b.track)
  for _, iv in ipairs(p.interventi) do
    local active = not iv.tieni
    local joins = false   -- nota solo per le cuciture che restano nel montato
    for _, k in ipairs(p.keep) do if iv.e and math.abs(k.s - iv.e) < 0.05 then joins = true end end
    if iv.tipo == "rifacimento" and active and joins then
      add_note(tr, new_pos(iv.s), 1.0, string.format(T("Rifacimento: tolti %s s. Ascolta la cucitura."), string.format("%.1f", iv.e - iv.s):gsub("%.", ",")),
        iv.sicurezza == "bassa" and "rosso" or "blu")
    elseif iv.tipo == "click_solo" then
      add_note(tr, new_pos(iv.s), 1.0, T("Controllare: click senza ripresa riconosciuta."), "rosso")
    elseif iv.tipo == "alternativa" and active then
      add_note(tr, new_pos(iv.altref and iv.altref.sotto or iv.s), 1.5, in_lane and T("ALT nella corsia sotto") or T("ALT nella traccia ALT (mutata)"), "viola")
    elseif iv.tipo == "omessa" then
      add_note(tr, cursor or b.pos, 2.0, string.format(T("Non letta: «%s»"), iv.testo or ""), "arancio")
    end
  end
  local new_end = cursor or b.pos
  return orig_end - new_end, orig_end
end

local function apply_all()
  if not S.blocks then return end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local done, shifted = 0, 0
  -- dalla fine all'inizio: lo spostamento della Timeline non tocca gli item ancora da fare
  for bi = #S.blocks, 1, -1 do
    local b = S.blocks[bi]
    if not b.err and b.plan and reaper.ValidatePtr(b.item, "MediaItem*") then
      local removed, orig_end = apply_block(b)
      done = done + 1
      if S.modo == "timeline" and removed > 0.001 then
        for i = 0, reaper.CountTrackMediaItems(b.track) - 1 do
          local it = reaper.GetTrackMediaItem(b.track, i)
          local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
          if pos >= orig_end - 0.0005 then reaper.SetMediaItemInfo_Value(it, "D_POSITION", pos - removed) end
        end
        shifted = shifted + removed
      end
    end
  end
  set_notes_visible(S.note_visibili)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(TITLE .. ": sgrossatura", -1)
  S.blocks, S.layout, S.sel = nil, nil, nil
  S.status = string.format(T("Applicato su %d item. Un solo Undo per tornare indietro. Il fino si fa in Timeline."), done)
  if shifted > 0 then S.status = S.status .. " " .. string.format(T("Timeline ricompattata di %s s."), string.format("%.1f", shifted):gsub("%.", ",")) end
end

---------------------------------------------------------------------------
-- pagina (stile copione): impaginazione delle parole
---------------------------------------------------------------------------
local PAGE_FONT = 19
local LINE_H = 34
local STYLE = {
  testo = { fg = { 0.08, 0.09, 0.11 } },
  rifatto = { fg = { 0.74, 0.12, 0.10 }, strike = true },
  superato = { fg = { 0.45, 0.45, 0.48 }, strike = true },
  fuori = { fg = { 0.66, 0.22, 0.12 }, strike = true },
  comando = { fg = { 0.04, 0.22, 0.48 }, bg = { 0.80, 0.89, 1.00 } },
  alt = { fg = { 0.22, 0.10, 0.48 }, bg = { 0.88, 0.84, 1.00 } },
  chip = { fg = { 1, 1, 1 }, bg = { 0.82, 0.12, 0.12 } },
  head = { fg = { 0.06, 0.24, 0.48 } },
  omessa = { fg = { 0.20, 0.10, 0.02 }, bg = { 1.00, 0.85, 0.70 } },
  errore = { fg = { 0.55, 0.10, 0.10 } },
}

local function iv_of_token(b, ti)
  for _, iv in ipairs(b.plan.interventi) do
    if iv.i1 and ti >= iv.i1 and ti <= iv.i2 and iv.tipo ~= "comando" then return iv end
  end
  for _, iv in ipairs(b.plan.interventi) do
    if iv.i1 and ti >= iv.i1 and ti <= iv.i2 then return iv end
  end
end

local function build_layout(w)
  gfx.setfont(1, "Arial", PAGE_FONT)
  local runs, x, y = {}, 0, 0
  local space = gfx.measurestr(" ")
  local function newline() x = 0; y = y + LINE_H end
  local function put(text, style, b, iv, s)
    local tw = gfx.measurestr(text)
    local pad = (STYLE[style] and STYLE[style].bg) and 8 or 0
    if x > 0 and x + tw + pad > w then newline() end
    runs[#runs + 1] = { x = x, y = y, w = tw + pad, text = text, style = style, b = b, iv = iv, s = s, pad = pad }
    x = x + tw + pad + space
  end
  for _, b in ipairs(S.blocks or {}) do
    if y > 0 then newline() end
    put("■ " .. tostring(b.name), "head", b); newline()
    if b.err then put(T("Saltato: ") .. b.err, "errore", b); newline()
    else
      local p = b.plan
      local clicks = {}
      for _, iv in ipairs(p.interventi) do
        if (iv.tipo == "rifacimento" and iv.segnale == "click") or iv.tipo == "click_solo" then clicks[#clicks + 1] = iv end
      end
      local ci, last_w = 1, nil
      for ti, tk in ipairs(p.toks) do
        while clicks[ci] and clicks[ci].cut and clicks[ci].cut.segnale.s <= tk.s do
          put(string.format("CLICK ×%d", clicks[ci].cut.segnale.n or 1), "chip", b, clicks[ci], clicks[ci].cut.segnale.s); ci = ci + 1
        end
        while clicks[ci] and not clicks[ci].cut and clicks[ci].s <= tk.s do put("CLICK ?", "chip", b, clicks[ci], clicks[ci].s); ci = ci + 1 end
        if tk.w ~= last_w then
          last_w = tk.w
          local st = p.stato[ti]
          put(p.words[tk.w].text, st, b, iv_of_token(b, ti), tk.s)
        end
      end
      for _, iv in ipairs(p.interventi) do
        if iv.tipo == "omessa" then newline(); put(T("NON LETTA: ") .. (iv.testo or ""), "omessa", b, iv) end
      end
      newline()
    end
  end
  S.layout, S.layout_w, S.page_h = runs, w, y + LINE_H
end

---------------------------------------------------------------------------
-- disegno
---------------------------------------------------------------------------
local C = UI.colors
local function setc(c, a) gfx.set(c[1], c[2], c[3], a or 1) end
local function text(s, x, y, size, col)
  gfx.setfont(1, "Arial", size or 16); setc(col or C.text); gfx.x, gfx.y = x, y; gfx.drawstr(tostring(s or ""))
end

local function all_interventi()
  local list = {}
  for _, b in ipairs(S.blocks or {}) do
    if b.plan then
      for _, iv in ipairs(b.plan.interventi) do
        if not S.solo_dubbi or iv.sicurezza ~= "alta" then list[#list + 1] = { b = b, iv = iv } end
      end
    end
  end
  return list
end

local function select_step(dir)
  local list = all_interventi()
  if #list == 0 then return end
  local idx = 0
  for i, x in ipairs(list) do if S.sel and x.iv == S.sel.iv then idx = i end end
  idx = math.max(1, math.min(#list, idx + dir))
  S.sel = list[idx]
  -- porta in vista la parola
  for _, r in ipairs(S.layout or {}) do
    if r.iv == S.sel.iv then S.scroll = math.max(0, r.y - 120); break end
  end
end

local function draw_side(x, y, w, h, clicked)
  UI.draw_panel({ x = x, y = y, w = w, h = h }, T("Qui"))
  local yy = y + 40
  local sel = S.sel
  local function btn(rx, ry, rw, label, active, enabled, style)
    return UI.draw_button({ x = rx, y = ry, w = rw, h = 34 }, label, active, enabled, clicked, style)
  end
  if not sel then
    for _, line in ipairs(UI.wrap_text(T("Clicca una parola segnata nella pagina, o usa le frecce per scorrere gli interventi."), w - 28)) do
      text(line, x + 14, yy, 16, C.muted); yy = yy + 22
    end
  else
    local iv = sel.iv
    text(iv_title(iv), x + 14, yy, 20, C.title); yy = yy + 30
    if iv.sicurezza == "bassa" then
      gfx.set(0.86, 0.16, 0.14, 1); gfx.rect(x + 14, yy, 128, 24, 1)
      text(T("CONTROLLARE"), x + 22, yy + 3, 15, { 1, 1, 1 }); yy = yy + 32
    end
    if iv.s then text(fmt_t(iv.s) .. "  →  " .. fmt_t(iv.e), x + 14, yy, 16, C.muted); yy = yy + 26 end
    local desc = iv.testo
    if not desc and iv.i1 then
      local parts, lw = {}, nil
      for i = iv.i1, iv.i2 do local tk = sel.b.plan.toks[i]; if tk.w ~= lw then lw = tk.w; parts[#parts + 1] = sel.b.plan.words[tk.w].text end end
      desc = table.concat(parts, " ")
    end
    for _, line in ipairs(UI.wrap_text("«" .. tostring(desc or "") .. "»", w - 28)) do
      if yy > y + h - 260 then break end
      text(line, x + 14, yy, 16, C.text); yy = yy + 22
    end
    yy = yy + 10
    if iv.s and btn(x + 14, yy, w - 28, "▶ " .. T("Ascolta"), false, true, "play") then play_range(sel.b, iv.s, iv.e) end
    yy = yy + 42
    if iv.i1 or iv.cut then
      local is_alt = iv.tipo == "alternativa"
      local half = math.floor((w - 36) / 2)
      if btn(x + 14, yy, half, is_alt and T("In corsia") or T("Togli"), not iv.tieni, true, "tab") and iv.tieni then
        M.set_tieni(sel.b.plan, iv, false); S.layout = nil
      end
      if btn(x + 22 + half, yy, half, is_alt and T("Non metterla") or T("Tieni"), iv.tieni == true, true, "tab") and not iv.tieni then
        M.set_tieni(sel.b.plan, iv, true); S.layout = nil
      end
      yy = yy + 42
    end
  end
  -- legenda
  local ly = y + h - 200
  text(T("Legenda"), x + 14, ly, 15, C.muted); ly = ly + 24
  local leg = {
    { T("barrato rosso: si toglie"), { 0.95, 0.40, 0.36 } },
    { T("barrato grigio: lettura superata"), { 0.70, 0.70, 0.74 } },
    { T("azzurro: comando detto"), { 0.55, 0.78, 1.00 } },
    { T("viola: alternativa, corsia sotto"), { 0.78, 0.68, 1.00 } },
    { T("CLICK: segnale di rifacimento"), { 1.00, 0.45, 0.42 } },
    { T("arancio: frase non letta"), { 1.00, 0.70, 0.40 } },
  }
  for _, l in ipairs(leg) do text(l[1], x + 14, ly, 15, l[2]); ly = ly + 22 end
end

local function draw_page(x, y, w, h, clicked)
  gfx.set(0.95, 0.94, 0.91, 1); gfx.rect(x, y, w, h, 1)
  local inner_w = w - 44
  if not S.blocks then
    gfx.setfont(1, "Arial", 18); gfx.set(0.35, 0.35, 0.38, 1)
    local yy = y + 30
    local msg = S.busy and T("Analisi in corso: la pagina compare alla fine.") or
      T("Qui comparira' il parlato come un copione segnato: barrato quello che si toglie, i comandi in azzurro, le alternative in viola. Clicca una parola per vederla a destra e ascoltarla.")
    for _, line in ipairs(UI.wrap_text(msg, inner_w)) do gfx.x, gfx.y = x + 22, yy; gfx.drawstr(line); yy = yy + 26 end
    return
  end
  if not S.layout or S.layout_w ~= inner_w then build_layout(inner_w) end
  S.scroll = math.max(0, math.min(S.scroll, math.max(0, S.page_h - h + 40)))
  gfx.setfont(1, "Arial", PAGE_FONT)
  local ox, oy = x + 22, y + 18 - S.scroll
  local hover_hit
  for _, r in ipairs(S.layout) do
    local ry = oy + r.y
    if ry > y - LINE_H and ry < y + h then
      local st = STYLE[r.style] or STYLE.testo
      local rx = ox + r.x
      if st.bg and ry >= y then setc(st.bg); gfx.rect(rx, ry - 3, r.w, LINE_H - 8, 1) end
      if S.sel and r.iv and r.iv == S.sel.iv and ry >= y then
        gfx.set(0.11, 0.44, 0.88, 1); gfx.rect(rx - 3, ry - 5, r.w + 6, LINE_H - 4, 0); gfx.rect(rx - 2, ry - 4, r.w + 4, LINE_H - 6, 0)
      end
      if ry >= y and ry + LINE_H - 10 <= y + h then
        setc(st.fg); gfx.x, gfx.y = rx + r.pad / 2, ry
        gfx.drawstr(r.text)
        if st.strike then
          local my = ry + math.floor(PAGE_FONT * 0.55)
          gfx.line(rx, my, rx + r.w, my); gfx.line(rx, my + 1, rx + r.w, my + 1)
        end
      end
      if UI.point_in_rect(gfx.mouse_x, gfx.mouse_y, rx, ry - 4, r.w, LINE_H - 6) and gfx.mouse_y >= y and gfx.mouse_y <= y + h then hover_hit = r end
    end
  end
  if clicked and hover_hit then
    if hover_hit.iv then S.sel = { b = hover_hit.b, iv = hover_hit.iv }
    elseif hover_hit.s and hover_hit.b and hover_hit.b.plan then
      S.sel = nil
      reaper.SetEditCurPos(src_to_proj(hover_hit.b, hover_hit.s), true, false)
    end
  end
  -- scorrimento
  if gfx.mouse_wheel ~= 0 and UI.point_in_rect(gfx.mouse_x, gfx.mouse_y, x, y, w, h) then
    S.scroll = S.scroll - gfx.mouse_wheel / 2
    gfx.mouse_wheel = 0
  end
  if S.page_h > h then
    local bar_h = math.max(30, h * h / S.page_h)
    local bar_y = y + (h - bar_h) * (S.scroll / math.max(1, S.page_h - h + 40))
    gfx.set(0.55, 0.55, 0.60, 0.8); gfx.rect(x + w - 8, bar_y, 5, bar_h, 1)
  end
end

local function seg_buttons(x, y, opts, current, clicked, on_pick)
  local cx = x
  for _, o in ipairs(opts) do
    gfx.setfont(1, "Arial", 16)
    local bw = gfx.measurestr(o[2]) + 30
    if UI.draw_button({ x = cx, y = y, w = bw, h = 32 }, o[2], current == o[1], true, clicked, "tab") then on_pick(o[1]) end
    cx = cx + bw + 6
  end
  return cx
end

local function draw()
  UI.fill_background()
  local down = (gfx.mouse_cap & 1) == 1
  local clicked = down and not S.last_down
  S.last_down = down
  UI.draw_header({ title = TITLE, x = 18, y = 12 })
  UI.draw_help_button({ x = gfx.w - 52, y = 16, w = 34, h = 30 }, clicked and not S.busy, nil)
  -- riga 1: cosa, modo, segnale
  local y1 = 66
  text(T("Cosa"), 18, y1 + 7, 15, C.muted)
  local nx = seg_buttons(66, y1, { { "item", T("Item selezionati") }, { "traccia", T("Traccia selezionata") } }, S.scope, clicked and not S.busy,
    function(v) S.scope = v; set_ext("scope", v) end)
  text(T("Modo"), nx + 14, y1 + 7, 15, C.muted)
  nx = seg_buttons(nx + 66, y1, { { "slide", T("Slide separate") }, { "timeline", "Timeline" } }, S.modo, clicked,
    function(v) S.modo = v; set_ext("modo", v) end)
  text(T("Segnale"), nx + 14, y1 + 7, 15, C.muted)
  seg_buttons(nx + 86, y1, { { "click", T("Click") }, { "parole", T("Parole") }, { "entrambi", T("Entrambi") } }, S.segnale, clicked and not S.busy,
    function(v) S.segnale = v; set_ext("segnale", v); if S.blocks then S.status = T("Segnale cambiato: rifai ANALIZZA (le trascrizioni sono in cache, e' veloce).") end end)
  -- riga 2: copione e analizza
  local y2 = y1 + 44
  text(T("Copione"), 18, y2 + 7, 15, C.muted)
  if UI.draw_button({ x = 96, y = y2, w = 130, h = 32 }, T("Carica file…"), false, not S.busy, clicked) then choose_copione_file() end
  if UI.draw_button({ x = 232, y = y2, w = 96, h = 32 }, T("Incolla"), false, not S.busy, clicked) then paste_copione() end
  if UI.draw_button({ x = 334, y = y2, w = 74, h = 32 }, T("Togli"), false, S.copione ~= nil and not S.busy, clicked) then
    S.copione, S.copione_nome = nil, ""; os.remove(copione_path()); reaper.SetProjExtState(0, EXT, "copione_nome", "")
    S.status = T("Copione tolto: l'analisi trovera' solo rifacimenti e comandi.")
  end
  local cop = S.copione and (S.copione_nome .. " · " .. string.format(T("%d parole"), #M.tokens(S.copione))) or T("nessuno: solo rifacimenti e comandi")
  text(UI.fit_text(cop, gfx.w - 420 - 190), 420, y2 + 7, 16, S.copione and C.text or C.muted)
  if UI.draw_button({ x = gfx.w - 178, y = y2 - 2, w = 160, h = 36 }, S.busy and T("ANALIZZO…") or T("ANALIZZA"), S.busy ~= nil, not S.busy, clicked, "play_select") then start_analysis() end
  -- stato
  local y3 = y2 + 44
  text(UI.fit_text(S.status, gfx.w - 36), 18, y3, 16, S.busy and { 1.0, 0.82, 0.45 } or C.text)
  -- pagina + pannello laterale
  local top = y3 + 30
  local bottom = gfx.h - 60
  local side_w = 320
  draw_page(18, top, gfx.w - side_w - 46, bottom - top, clicked)
  draw_side(gfx.w - side_w - 18, top, side_w, bottom - top, clicked)
  -- barra in basso
  local by = gfx.h - 48
  local list = all_interventi()
  if UI.draw_button({ x = 18, y = by, w = 48, h = 34 }, "◀", false, #list > 0, clicked) then select_step(-1) end
  if UI.draw_button({ x = 72, y = by, w = 48, h = 34 }, "▶", false, #list > 0, clicked) then select_step(1) end
  if UI.draw_button({ x = 128, y = by, w = 150, h = 34 }, T("Solo dubbi"), S.solo_dubbi, S.blocks ~= nil, clicked, "tab") then S.solo_dubbi = not S.solo_dubbi end
  local n_low = 0
  for _, x in ipairs(list) do if x.iv.sicurezza == "bassa" then n_low = n_low + 1 end end
  text(string.format(T("%d interventi · %d da controllare"), #list, n_low), 292, by + 8, 16, n_low > 0 and { 1.0, 0.55, 0.50 } or C.muted)
  if UI.draw_button({ x = gfx.w - 400, y = by, w = 210, h = 34 }, S.note_visibili and T("Note montaggio: visibili") or T("Note montaggio: nascoste"), S.note_visibili, true, clicked, "tab") then
    set_notes_visible(not S.note_visibili)
  end
  if UI.draw_button({ x = gfx.w - 178, y = by, w = 160, h = 34 }, T("APPLICA ▸"), false, S.blocks ~= nil and not S.busy, clicked, "play") then apply_all() end
end

---------------------------------------------------------------------------
-- giro
---------------------------------------------------------------------------
local function loop()
  if S.busy then
    local ok, err = coroutine.resume(S.busy)
    if not ok then S.status = T("Errore nell'analisi: ") .. tostring(err); S.busy = nil
    elseif coroutine.status(S.busy) == "dead" then S.busy = nil end
  end
  check_stop()
  draw()
  gfx.update()
  local ch = gfx.getchar()
  if ch == 27 or ch < 0 then
    set_ext("w", gfx.w); set_ext("h", gfx.h)
    gfx.quit(); return
  end
  reaper.defer(loop)
end

load_saved_copione()
gfx.init(TITLE, tonumber(get_ext("w", W0)) or W0, tonumber(get_ext("h", H0)) or H0)
loop()
