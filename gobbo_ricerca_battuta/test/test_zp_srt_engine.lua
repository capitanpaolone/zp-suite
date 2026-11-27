-- Collaudo logica pura + mock REAPER di ZP_SRT_Engine.lua
-- Eseguibile con: lua gobbo_ricerca_battuta/test/test_zp_srt_engine.lua

local info = debug.getinfo(1, "S").source:match("^@?(.*[/\\])") or "./"
local suite_dir = info .. "../../ZP Studio Suite/"

local ENG = dofile(suite_dir .. "ZP_SRT_Engine.lua")
local TESTO = dofile(suite_dir .. "ZP_Testo_Copione.lua")

local function assert_eq(got, want, label)
  if got ~= want then
    error(string.format("FAIL [%s]: atteso %q, ottenuto %q", label or "?", tostring(want), tostring(got)), 2)
  end
end

-- 1. Parsing SRT con BOM UTF-8, tag HTML e formattazione round-trip
do
  local raw_srt = "\239\187\1911\r\n00:00:01,250 --> 00:00:03,500\r\n<i>Ciao</i> mondo!\r\nSeconda riga.\r\n\r\n2\r\n00:00:04,000 --> 00:00:05,100\r\n{\\an8}Terza &amp; ultima.\r\n"
  local cues, err = ENG.parse_subtitles(raw_srt)
  assert(cues, err)
  assert_eq(#cues, 2, "numero cue SRT")
  assert_eq(cues[1].text, "Ciao mondo!\nSeconda riga.", "pulizia tag HTML SRT")
  assert_eq(cues[2].text, "Terza & ultima.", "pulizia ASS e entità")
  assert_eq(ENG.format_time(cues[1].start_pos), "00:00:01,250", "format_time start")

  local serialized = ENG.format_srt(cues)
  local reparsed = ENG.parse_subtitles(serialized)
  assert_eq(#reparsed, 2, "round-trip SRT count")
  assert_eq(reparsed[1].text, cues[1].text, "round-trip SRT text")
end

-- 2. Parsing WebVTT con NOTE, STYLE e <v Speaker>
do
  local vtt = [[WEBVTT

NOTE commento da ignorare

STYLE
::cue { color: yellow; }

cue-a
00:05.000 --> 00:07.200 align:start
<v Paolo>Buonasera a <00:00:05.500>tutti <sospira>

00:07.500 --> 00:09.000
Risposta rapida.
]]
  local cues, err = ENG.parse_subtitles(vtt)
  assert(cues, err)
  assert_eq(#cues, 2, "numero cue VTT")
  assert_eq(cues[1].text, "Paolo: Buonasera a tutti <sospira>", "voce VTT + conservazione <sospira>")
  assert_eq(ENG.format_time(cues[1].start_pos), "00:00:05,000", "tempo MM:SS.mmm VTT")
end

-- 3. Accorpa item brevi: parolina isolata agganciata a un dialogo lungo di 3 righe + direzione punteggiatura
do
  local raw_cues = {
    -- Caso A: blocco lungo di 3 righe seguito da 1 sola parola finale ("domani.") rimasta staccata
    {
      start_pos = 1.00, end_pos = 5.40,
      text = "Questo è un dialogo abbastanza lungo\ndistribuito su tre righe intere\nperché l'attore parla veloce fino a"
    },
    { start_pos = 5.55, end_pos = 6.10, text = "domani." },
    -- Caso B: frase finita col punto, poi parolina d'attacco ("Allora") prima della frase nuova
    { start_pos = 6.40, end_pos = 6.80, text = "Allora" },
    { start_pos = 6.95, end_pos = 9.20, text = "possiamo cominciare subito la registrazione." },
    -- Caso C: catena di 3 micro-item ravvicinati -> diventano una battuta unica
    { start_pos = 11.00, end_pos = 11.30, text = "Ma" },
    { start_pos = 11.40, end_pos = 11.75, text = "certo" },
    { start_pos = 11.85, end_pos = 12.60, text = "che sì!" },
  }

  local merged, absorbed = ENG.coalesce_cues(raw_cues, { max_words = 2, max_gap = 0.90 })
  assert_eq(absorbed, 4, "numero micro-item assorbiti")
  assert_eq(#merged, 3, "numero blocchi finali dopo coalesce")
  assert(merged[1].text:match("fino a domani%.$"), "parolina finale unita al blocco di 3 righe")
  assert_eq(merged[1].end_pos, 6.10, "durata estesa fino alla fine della parolina")
  assert_eq(merged[2].text, "Allora possiamo cominciare subito la registrazione.", "parolina iniziale unita a destra dopo punto fermo")
  assert_eq(merged[3].text, "Ma certo che sì!", "catena di micro-item fusa insieme")
end

-- 4. Guardrail Accorpa item brevi: NON unisce attraverso pause lunghe, trattini dialogo, cambi personaggio o sync audio
do
  local guarded = {
    { start_pos = 1.0, end_pos = 3.0, text = "MARIO: Dove vai?" },
    { start_pos = 3.2, end_pos = 3.8, text = "LAURA: Via." },           -- altro personaggio -> NO merge
    { start_pos = 4.0, end_pos = 4.5, text = "- Aspetta!" },            -- trattino cambio turno -> NO merge
    { start_pos = 7.0, end_pos = 7.5, text = "Troppo tardi." },         -- gap 2.5 s -> NO merge
    { start_pos = 7.7, end_pos = 8.2, text = "Già.", sync_key = "m1" }, -- agganciato audio 29 -> NO merge
  }
  local _, absorbed = ENG.plan_short_merges(guarded, { max_words = 2, max_gap = 0.90 })
  assert_eq(absorbed, 0, "nessuna unione indebita attraverso barriere dialogo/pausa/sync")

  -- Verifica deduplica personaggio identico ripetuto
  local same_role = {
    { start_pos = 1.0, end_pos = 3.0, text = "MARIO: Non credo proprio che sia" },
    { start_pos = 3.1, end_pos = 3.6, text = "MARIO: vero." },
  }
  local c_same, abs_same = ENG.coalesce_cues(same_role, { max_words = 2, max_gap = 0.90 })
  assert_eq(abs_same, 1, "stesso personaggio assorbito")
  assert_eq(c_same[1].text, "MARIO: Non credo proprio che sia vero.", "prefisso personaggio non duplicato")
end

-- 5. Divisione battute (alla playhead e per righe/frasi) + sovrapposizioni
do
  local l, r = ENG.split_cue_at_ratio("Prima riga del copione\nSeconda riga finale", 0.48)
  assert_eq(l, "Prima riga del copione", "split_cue_at_ratio sinistra")
  assert_eq(r, "Seconda riga finale", "split_cue_at_ratio destra")

  local parts = ENG.split_cue_lines("Riga uno\nRiga due più lunga\nRiga tre", 10.0, 16.0)
  assert(parts and #parts == 3, "split_cue_lines 3 righe")
  assert_eq(parts[1].start_pos, 10.0, "inizio prima parte")
  assert_eq(parts[3].end_pos, 16.0, "fine ultima parte")

  local ov_cues = {
    { start_pos = 1.0, end_pos = 3.5, text = "Uno" },
    { start_pos = 3.0, end_pos = 5.0, text = "Due" },
  }
  local lane_res, n_lane = ENG.resolve_overlaps(ov_cues, "lane")
  assert_eq(n_lane, 1, "overlap rilevato in modalità lane")
  assert_eq(lane_res[2].overlap, true, "seconda cue marcata overlap")

  local trim_res = ENG.resolve_overlaps(ov_cues, "trim")
  assert(trim_res[1].end_pos <= trim_res[2].start_pos, "overlap risolto in modalità trim")
end

-- 6. Mock REAPER: verifica che run_short_coalesce preservi ancore Gobbo e highlight in 1 solo Undo
do
  local track_obj = { name = "Rythmo Band Testi", items = {} }
  local undo_blocks = 0

  local function make_item(pos, len, notes, anchors, hl)
    local it = {
      track = track_obj,
      D_POSITION = pos,
      D_LENGTH = len,
      str = {
        ["P_NOTES"] = notes,
        ["P_NAME"] = notes,
        ["P_EXT:ZP_GOBBO_ANCHORS"] = anchors or "",
        ["P_EXT:RythmoBand_HIGHLIGHT"] = hl or "",
        ["P_EXT:ZP_SYNC_KEY"] = ""
      },
      selected = true
    }
    track_obj.items[#track_obj.items + 1] = it
    return it
  end

  -- Parola "subito" nella seconda micro-battuta ha un'ancora Gobbo all'offset 1!
  make_item(0.0, 3.0, "Dobbiamo andare via da qui", TESTO.serialize_anchors({ { guid = "{A001}", offset = 10 } }), "andare")
  make_item(3.1, 0.5, "subito.", TESTO.serialize_anchors({ { guid = "{A002}", offset = 1 } }), "subito")

  _G.reaper = {
    GetOS = function() return "OSX64" end,
    ColorToNative = function(r, g, b) return r * 65536 + g * 256 + b end,
    ValidatePtr2 = function(_, ptr, kind)
      if kind == "MediaItem*" then
        for _, x in ipairs(track_obj.items) do if x == ptr then return true end end
      end
      return false
    end,
    CountTrackMediaItems = function(tr) return #tr.items end,
    GetTrackMediaItem = function(tr, idx) return tr.items[idx + 1] end,
    GetMediaItemNumTakes = function() return 0 end,
    GetMediaItem_Track = function(it) return it.track end,
    GetMediaItemInfo_Value = function(it, k) return it[k] or 0 end,
    SetMediaItemInfo_Value = function(it, k, v) it[k] = v; return true end,
    GetSetMediaItemInfo_String = function(it, k, v, set)
      if set then it.str[k] = v; return true, v end
      return true, it.str[k] or ""
    end,
    GetSetMediaTrackInfo_String = function(tr, k, v, set)
      if set and k == "P_NAME" then tr.name = v end
      return true, tr.name
    end,
    DeleteTrackMediaItem = function(tr, it)
      for i, x in ipairs(tr.items) do
        if x == it then table.remove(tr.items, i); return true end
      end
      return false
    end,
    SelectAllMediaItems = function()
      for _, x in ipairs(track_obj.items) do x.selected = false end
    end,
    SetMediaItemSelected = function(it, sel) it.selected = sel end,
    UpdateItemInProject = function() end,
    UpdateArrange = function() end,
    PreventUIRefresh = function() end,
    Undo_BeginBlock = function() undo_blocks = undo_blocks + 1 end,
    Undo_EndBlock = function() end,
  }

  local ENG_REAPER = dofile(suite_dir .. "ZP_SRT_Engine.lua")
  local res, err = ENG_REAPER.run_short_coalesce("track", track_obj, { max_words = 2, max_gap = 0.90 })
  _G.reaper = nil

  assert(res, err)
  assert_eq(res.absorbed, 1, "mock REAPER absorbed count")
  assert_eq(#track_obj.items, 1, "mock REAPER item rimasto unico")
  assert_eq(undo_blocks, 1, "un solo blocco Undo aperto")

  local kept = track_obj.items[1]
  assert_eq(kept.str["P_NOTES"], "Dobbiamo andare via da qui subito.", "testo fuso in REAPER")
  assert_eq(kept.D_LENGTH, 3.6, "durata estesa fino a 3.6s")
  local parsed_anc = TESTO.parse_anchors(kept.str["P_EXT:ZP_GOBBO_ANCHORS"])
  assert_eq(#parsed_anc, 2, "entrambe le ancore Gobbo conservate")
  assert_eq(kept.str["P_NOTES"]:sub(parsed_anc[2].offset, parsed_anc[2].offset + 5), "subito", "offset seconda ancora ricalcolato sulla parola 'subito'")
  assert(kept.str["P_EXT:RythmoBand_HIGHLIGHT"]:find("andare") and kept.str["P_EXT:RythmoBand_HIGHLIGHT"]:find("subito"), "highlight preservate")
end

-- 7. Marker audio puri (senza aprire 31_SRT_da_Marker_Audio.lua in REAPER!)
do
  assert_eq(ENG.is_service_marker("#HSC 01"), true, "marker #HSC filtrato")
  assert_eq(ENG.is_service_marker("OK_001"), true, "marker SOLO Recorder filtrato")
  assert_eq(ENG.is_service_marker("Prima battuta"), false, "marker dialogo valido")
  local acues = ENG.audio_marker_cues({
    { src = 0.5, text = "#HSC" },
    { src = 1.0, text = "Ciao a tutti" },
    { src = 3.2, text = "Seconda frase" },
  }, 5.0)
  assert_eq(#acues, 2, "2 cue valide dai take marker")
  assert_eq(acues[1].end_pos, 3.2, "fine prima cue = inizio seconda")
  assert_eq(acues[2].end_pos, 5.0, "fine ultima cue limitata alla lunghezza sorgente")

  -- Regressione critica: il motore NON deve mai caricare script GUI (es. 31_SRT_da_Marker_Audio.lua)
  local src_eng = io.open(suite_dir .. "ZP_SRT_Engine.lua", "rb"):read("*a")
  assert(not src_eng:find("31_SRT_da_Marker_Audio", 1, true), "ZP_SRT_Engine non deve fare dofile su 31_SRT_da_Marker_Audio.lua")
end

print("TUTTI OK")
