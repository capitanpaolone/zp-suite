-- @noindex

-- ZP CHAIN BUILDER
-- ZP Studio Suite for REAPER
-- v2 Profile Structures — 2026-06-24
--
-- Crea, verifica e ripara strutture operative ZP senza cancellare item o FX.
-- Profili: Voiceover, ADR/Doppiaggio, E-learning, Podcast, Spot.

local SCRIPT_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "")
local ZP_UI = dofile(SCRIPT_DIR .. "ZP_UI.lua")

local TITLE = "ZP Chain Builder"
local BUS_NAME = "ZPVoiceoverSharedBus"
local BUS_MAGIC = 905026
local BUS_VERSION = 220

local GUARD_MAGIC = 905024
local GUARD_SLOT_MAGIC = 90
local GUARD_SLOT_TIME = 91
local GUARD_SLOT_STATE = 92
local GUARD_FRESH_SEC = 2.5

local PROFILES = {
  {
    id = 1, name = "Voiceover", short = "VOICEOVER",
    needs_music = false, needs_video_audio = false,
    target_lufs = -18, ceiling_db = -3,
    description =
      "Crea o completa:\n" ..
      "  ZP VO BUS\n" ..
      "    REC\n" ..
      "    EDIT\n\n" ..
      "Sul VO BUS inserisce BUS Chain e Probe VOICE come ultimo FX.\n" ..
      "Sul Master inserisce ZP Master Pro.\n\n" ..
      "Target Master: -18 LUFS | Ceiling: -3 dB."
  },
  {
    id = 2, name = "ADR / Doppiaggio", short = "ADR",
    needs_music = false, needs_video_audio = true,
    target_lufs = -21, ceiling_db = -6,
    description =
      "Crea la stessa struttura del Voiceover e aggiunge sopra al VO BUS:\n" ..
      "  VIDEO AUDIO\n\n" ..
      "VIDEO AUDIO non registra, non invia al Master e usa l'uscita hardware 1/2.\n" ..
      "Serve per ascoltare l'audio guida senza includerlo nel bounce.\n\n" ..
      "Target Master: -21 LUFS | Ceiling: -6 dB."
  },
  {
    id = 3, name = "E-learning", short = "ELEARNING",
    needs_music = false, needs_video_audio = false,
    target_lufs = -14, ceiling_db = -3,
    description =
      "Crea o completa:\n" ..
      "  ZP VO BUS\n" ..
      "    REC\n" ..
      "    EDIT\n\n" ..
      "Sul VO BUS inserisce BUS Chain e Probe VOICE come ultimo FX.\n" ..
      "Sul Master inserisce ZP Master Pro.\n\n" ..
      "Target Master: -14 LUFS | Ceiling: -3 dB."
  },
  {
    id = 4, name = "Podcast", short = "PODCAST",
    needs_music = true, needs_video_audio = false,
    target_lufs = -16, ceiling_db = -1,
    description =
      "Crea o completa due BUS:\n" ..
      "  ZP VO BUS -> REC + EDIT + Probe VOICE\n" ..
      "  ZP Music Bus -> una o piu' musiche + Probe MUSIC\n\n" ..
      "Sul Music Bus inserisce Harmonic Space Carver e Probe MUSIC come ultimo FX.\n" ..
      "Se le tracce musicali selezionate sono contigue, le racchiude nel nuovo Music Bus.\n\n" ..
      "Target Master: -16 LUFS | Ceiling: -1 dB."
  },
  {
    id = 5, name = "Spot", short = "SPOT",
    needs_music = true, needs_video_audio = false,
    target_lufs = -9, ceiling_db = -1,
    description =
      "Struttura come Podcast:\n" ..
      "  ZP VO BUS -> REC + EDIT + Probe VOICE\n" ..
      "  ZP Music Bus -> musiche + Probe MUSIC\n\n" ..
      "Music Probe e Harmonic Space Carver sono automatici.\n" ..
      "Le tracce musicali selezionate e contigue possono diventare figlie del Music Bus.\n\n" ..
      "Target Master: -9 LUFS | Ceiling: -1 dB."
  },
}

local FX = {
  unified = {
    label = "ZP BUS / Voiceover Unified Chain",
    match = { "zp bus chain", "zp voiceover unified chain" },
    candidates = {
      "JS: ZP_Paolo Balestri JSFX/ZP BUS Chain 1.0_BROWN-ANA.jsfx",
      "ZP_Paolo Balestri JSFX/ZP BUS Chain 1.0_BROWN-ANA.jsfx",
      "ZP BUS Chain 1.0_BROWN-ANA",
      "JS: ZP_Paolo Balestri JSFX/ZP Voiceover Unified Chain v4.0-dev.jsfx",
      "ZP Voiceover Unified Chain",
    },
  },
  master = {
    label = "ZP Master Pro",
    match = "zp master pro",
    candidates = {
      "JS: ZP_Paolo Balestri JSFX/ZP Master Pro.jsfx",
      "ZP_Paolo Balestri JSFX/ZP Master Pro.jsfx",
      "ZP Master Pro",
    },
  },
  space = {
    label = "ZP Harmonic Space Carver",
    match = "zp harmonic space carver",
    candidates = {
      "JS: ZP_Paolo Balestri JSFX/ZP Harmonic Space Carver Access View v2X.jsfx",
      "ZP_Paolo Balestri JSFX/ZP Harmonic Space Carver Access View v2X.jsfx",
      "ZP Harmonic Space Carver Access View v2X",
      "ZP Harmonic Space Carver",
    },
  },
  spoken = { label = "ZP Spoken Finish", match = "zp spoken finish" },
  probe = {
    label = "ZP Voice-Music Probe",
    match = "zp voice-music probe",
    candidates = {
      "JS: ZP_Paolo Balestri JSFX/ZP Voice-Music Probe.jsfx",
      "ZP_Paolo Balestri JSFX/ZP Voice-Music Probe.jsfx",
      "ZP Voice-Music Probe",
    },
  },
}

local function lower(s) return tostring(s or ""):lower() end
local function trim(s) return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

local function track_name(track)
  if not track then return "" end
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  return name or ""
end

local function set_track_name(track, name)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
end

local function track_index(track)
  return track and math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1) or -1
end

local function get_role(track)
  if not track then return "" end
  local _, role = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:ZP_CHAIN_ROLE", "", false)
  return role or ""
end

local function set_role(track, role)
  reaper.GetSetMediaTrackInfo_String(track, "P_EXT:ZP_CHAIN_ROLE", role, true)
end

local function find_fx(track, needle)
  if not track then return -1 end
  if type(needle) == "table" then
    for _, alias in ipairs(needle) do
      local index, name = find_fx(track, alias)
      if index >= 0 then return index, name end
    end
    return -1
  end
  needle = lower(needle)
  for i = 0, reaper.TrackFX_GetCount(track) - 1 do
    local _, name = reaper.TrackFX_GetFXName(track, i, "")
    if lower(name):find(needle, 1, true) then return i, name end
  end
  return -1
end

local function find_track_by_role(role)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    if get_role(track) == role then return track end
  end
end

local function find_named(names)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local n = lower(trim(track_name(track)))
    if names[n] then return track end
  end
end

local function find_track_with_fx(needle)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    if find_fx(track, needle) >= 0 then return track end
  end
end

local function find_vo_bus()
  return find_track_by_role("VO_BUS")
    or find_track_with_fx(FX.unified.match)
    or find_named({ ["zp vo bus"] = true, ["zp vo"] = true, ["vo bus"] = true })
end

local function find_music_bus()
  return find_track_by_role("MUSIC_BUS")
    or find_track_with_fx(FX.space.match)
    or find_named({ ["zp music bus"] = true, ["music bus"] = true, ["musiche"] = true })
end

local function insert_track(index, name)
  index = math.max(0, math.min(index, reaper.CountTracks(0)))
  reaper.InsertTrackAtIndex(index, true)
  local track = reaper.GetTrack(0, index)
  set_track_name(track, name)
  return track
end

local function add_fx_if_missing(track, spec)
  local existing = find_fx(track, spec.match)
  if existing >= 0 then return "found", existing end
  for _, candidate in ipairs(spec.candidates or {}) do
    local index = reaper.TrackFX_AddByName(track, candidate, false, 1)
    if index and index >= 0 then return "added", index end
  end
  return "missing", -1
end

local function ensure_probe_last(track, mode)
  local index = find_fx(track, FX.probe.match)
  local result = "found"
  if index < 0 then
    result = "missing"
    for _, candidate in ipairs(FX.probe.candidates) do
      index = reaper.TrackFX_AddByName(track, candidate, false, 1)
      if index and index >= 0 then result = "added" break end
    end
  end
  if not index or index < 0 then return "missing", -1 end

  -- slider1 / parameter 0: VOICE=0, MUSIC=1.
  reaper.TrackFX_SetParam(track, index, 0, mode or 0)

  local last = reaper.TrackFX_GetCount(track) - 1
  if index ~= last then
    reaper.TrackFX_CopyToTrack(track, index, track, last, true)
    index = last
    result = result == "added" and "added" or "moved"
    reaper.TrackFX_SetParam(track, index, 0, mode or 0)
  end
  return result, index
end

local function collect_direct_children(bus)
  local out = {}
  if not bus then return out end
  local idx = track_index(bus)
  local start_depth = reaper.GetMediaTrackInfo_Value(bus, "I_FOLDERDEPTH")
  if start_depth <= 0 then return out end

  local depth = 1
  for i = idx + 1, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    if depth == 1 then out[#out + 1] = track end
    depth = depth + reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    if depth <= 0 then break end
  end
  return out
end

local function find_direct_child(bus, names)
  for _, track in ipairs(collect_direct_children(bus)) do
    if names[lower(trim(track_name(track)))] then return track end
  end
end

local function ensure_two_child_folder(bus, first_name, second_name, report)
  local bus_idx = track_index(bus)
  local children = collect_direct_children(bus)
  local first = find_direct_child(bus, { [lower(first_name)] = true })
  local second = find_direct_child(bus, { [lower(second_name)] = true })

  if #children == 0 then
    reaper.SetMediaTrackInfo_Value(bus, "I_FOLDERDEPTH", 1)
    first = insert_track(bus_idx + 1, first_name)
    second = insert_track(bus_idx + 2, second_name)
    reaper.SetMediaTrackInfo_Value(first, "I_FOLDERDEPTH", 0)
    reaper.SetMediaTrackInfo_Value(second, "I_FOLDERDEPTH", -1)
    report[#report + 1] = "AGGIUNTO  Sottotracce " .. first_name .. " + " .. second_name
    return first, second, true
  end

  -- Existing folders are preserved. Missing children are inserted just after the bus,
  -- without reordering existing material.
  if not first then
    first = insert_track(bus_idx + 1, first_name)
    reaper.SetMediaTrackInfo_Value(first, "I_FOLDERDEPTH", 0)
    report[#report + 1] = "AGGIUNTO  Sottotraccia " .. first_name
  end
  if not second then
    second = insert_track(track_index(first) + 1, second_name)
    reaper.SetMediaTrackInfo_Value(second, "I_FOLDERDEPTH", 0)
    report[#report + 1] = "AGGIUNTO  Sottotraccia " .. second_name
  end
  return first, second, false
end

local function selected_tracks()
  local out = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    out[#out + 1] = reaper.GetSelectedTrack(0, i)
  end
  table.sort(out, function(a, b) return track_index(a) < track_index(b) end)
  return out
end

local function safe_music_selection()
  local selected = selected_tracks()
  local out = {}
  for _, track in ipairs(selected) do
    local role = get_role(track)
    local name = lower(track_name(track))
    if role == "" and not name:find("zp vo", 1, true) and not name:find("master", 1, true) then
      out[#out + 1] = track
    end
  end
  if #out == 0 then return out, false end
  for i = 2, #out do
    if track_index(out[i]) ~= track_index(out[i - 1]) + 1 then return out, false end
  end
  return out, true
end

local function create_music_bus_from_selection(report)
  local selected, contiguous = safe_music_selection()
  if #selected > 0 and contiguous then
    local first_idx = track_index(selected[1])
    local bus = insert_track(first_idx, "ZP Music Bus")
    set_role(bus, "MUSIC_BUS")
    reaper.SetMediaTrackInfo_Value(bus, "I_FOLDERDEPTH", 1)

    -- Insertion shifted the selected tracks by +1.
    local last = selected[#selected]
    local old_end = reaper.GetMediaTrackInfo_Value(last, "I_FOLDERDEPTH")
    reaper.SetMediaTrackInfo_Value(last, "I_FOLDERDEPTH", old_end - 1)
    report[#report + 1] = "AGGIUNTO  ZP Music Bus attorno alle tracce musicali selezionate"
    return bus
  end

  local bus = insert_track(reaper.CountTracks(0), "ZP Music Bus")
  set_role(bus, "MUSIC_BUS")
  reaper.SetMediaTrackInfo_Value(bus, "I_FOLDERDEPTH", 1)
  local music = insert_track(track_index(bus) + 1, "MUSIC")
  reaper.SetMediaTrackInfo_Value(music, "I_FOLDERDEPTH", -1)
  report[#report + 1] = "AGGIUNTO  ZP Music Bus con sottotraccia MUSIC"
  if #selected > 0 and not contiguous then
    report[#report + 1] = "AVVISO    Tracce selezionate non contigue: non sono state spostate automaticamente"
  end
  return bus
end

local function ensure_video_audio_track(vo_bus, report)
  local existing = find_track_by_role("VIDEO_AUDIO")
    or find_named({ ["video audio"] = true, ["audio video"] = true, ["video guide"] = true })

  local track = existing
  if not track then
    track = insert_track(math.max(0, track_index(vo_bus)), "VIDEO AUDIO")
    set_role(track, "VIDEO_AUDIO")
    report[#report + 1] = "AGGIUNTO  VIDEO AUDIO sopra il VO BUS"
  else
    report[#report + 1] = "TROVATO   VIDEO AUDIO"
  end

  reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 0)
  reaper.SetMediaTrackInfo_Value(track, "I_RECMON", 0)
  reaper.SetMediaTrackInfo_Value(track, "B_MAINSEND", 0)

  local hw_count = reaper.GetTrackNumSends(track, 1)
  if hw_count == 0 then
    local send = reaper.CreateTrackSend(track, nil)
    if send and send >= 0 then
      reaper.SetTrackSendInfo_Value(track, 1, send, "I_SRCCHAN", 0)
      reaper.SetTrackSendInfo_Value(track, 1, send, "I_DSTCHAN", 0)
      report[#report + 1] = "OK        VIDEO AUDIO -> uscita hardware 1/2, esclusa dal Master"
    else
      report[#report + 1] = "AVVISO    VIDEO AUDIO esclusa dal Master; uscita hardware da verificare"
    end
  else
    report[#report + 1] = "OK        VIDEO AUDIO gia' esclusa dal Master e con uscita hardware"
  end
  return track
end

local function configure_master(profile, report)
  local master = reaper.GetMasterTrack(0)
  local result, fx = add_fx_if_missing(master, FX.master)
  report[#report + 1] =
    (result == "found" and "TROVATO   " or result == "added" and "AGGIUNTO  " or "MANCA     ")
    .. FX.master.label .. " sul Master"

  if fx and fx >= 0 then
    -- JSFX parameter indices are zero-based:
    -- slider2 Ceiling, slider23 Target LUFS, slider30 Final Limiter.
    reaper.TrackFX_SetParam(master, fx, 1, profile.ceiling_db)
    reaper.TrackFX_SetParam(master, fx, 22, profile.target_lufs)
    reaper.TrackFX_SetParam(master, fx, 29, 1)
    report[#report + 1] = string.format(
      "IMPOSTATO Master target %.0f LUFS | Ceiling %.0f dB | Final LIM ON",
      profile.target_lufs, profile.ceiling_db
    )
  end
  return result ~= "missing"
end

local function write_bus_profile(profile)
  if reaper.gmem_attach and reaper.gmem_write then
    reaper.gmem_attach(BUS_NAME)
    reaper.gmem_write(0, BUS_MAGIC)
    reaper.gmem_write(1, BUS_VERSION)
    reaper.gmem_write(2, profile.id)
  end
  reaper.SetProjExtState(0, "ZP_CHAIN_BUILDER", "delivery_profile", tostring(profile.id))
  reaper.SetProjExtState(0, "ZP_CHAIN_BUILDER", "target_lufs", tostring(profile.target_lufs))
  reaper.SetProjExtState(0, "ZP_CHAIN_BUILDER", "ceiling_db", tostring(profile.ceiling_db))
end

local function probe_guard_is_running()
  if not (reaper.gmem_attach and reaper.gmem_read) then return false end
  reaper.gmem_attach(BUS_NAME)
  local magic = reaper.gmem_read(GUARD_SLOT_MAGIC)
  local stamp = reaper.gmem_read(GUARD_SLOT_TIME)
  local state = reaper.gmem_read(GUARD_SLOT_STATE)
  return magic == GUARD_MAGIC and state == 1 and stamp > 0
    and (reaper.time_precise() - stamp) <= GUARD_FRESH_SEC
end

local function ensure_probe_guard_running()
  if probe_guard_is_running() then
    return "TROVATO   ZP Probe Guard gia' attivo"
  end

  local guard_path = SCRIPT_DIR .. "24_ZP_Probe_Guard.lua"
  local file = io.open(guard_path, "r")
  if not file then
    return "MANCA     24_ZP_Probe_Guard.lua nella cartella del Chain Builder"
  end
  file:close()

  local command = reaper.AddRemoveReaScript
    and reaper.AddRemoveReaScript(true, 0, guard_path, true)
    or 0
  if not command or command == 0 then
    return "MANCA     Impossibile registrare automaticamente ZP Probe Guard"
  end
  reaper.Main_OnCommand(command, 0)
  return "ATTIVATO  ZP Probe Guard"
end

local function inspect(profile)
  local vo = find_vo_bus()
  local music = profile.needs_music and find_music_bus() or nil
  local master = reaper.GetMasterTrack(0)
  local video = profile.needs_video_audio and (
    find_track_by_role("VIDEO_AUDIO")
    or find_named({ ["video audio"] = true, ["audio video"] = true })
  ) or nil

  return {
    profile = profile,
    vo = vo,
    rec = vo and find_direct_child(vo, { ["rec"] = true }) or nil,
    edit = vo and find_direct_child(vo, { ["edit"] = true, ["editing"] = true }) or nil,
    music = music,
    video = video,
    vo_fx = vo and find_fx(vo, FX.unified.match) >= 0 or false,
    voice_probe = vo and find_fx(vo, FX.probe.match) >= 0 or false,
    voice_probe_last = vo and find_fx(vo, FX.probe.match) == reaper.TrackFX_GetCount(vo) - 1 or false,
    music_fx = music and find_fx(music, FX.space.match) >= 0 or false,
    music_probe = music and find_fx(music, FX.probe.match) >= 0 or false,
    music_probe_last = music and find_fx(music, FX.probe.match) == reaper.TrackFX_GetCount(music) - 1 or false,
    master_fx = find_fx(master, FX.master.match) >= 0,
  }
end

local function check_report(snapshot)
  local p = snapshot.profile
  local lines = {
    "Profilo: " .. p.name,
    string.format("Target: %.0f LUFS | Ceiling: %.0f dB", p.target_lufs, p.ceiling_db),
    "",
  }

  lines[#lines + 1] = snapshot.vo and "TROVATO   ZP VO BUS" or "MANCA     ZP VO BUS"
  lines[#lines + 1] = snapshot.rec and "TROVATO   REC" or "MANCA     REC"
  lines[#lines + 1] = snapshot.edit and "TROVATO   EDIT" or "MANCA     EDIT"
  lines[#lines + 1] = snapshot.vo_fx and "TROVATO   BUS Chain sul VO BUS" or "MANCA     BUS Chain sul VO BUS"
  lines[#lines + 1] = snapshot.voice_probe
    and (snapshot.voice_probe_last and "TROVATO   Probe VOICE ultimo FX" or "DA RIPARARE Probe VOICE non ultimo")
    or "MANCA     Probe VOICE"

  if p.needs_video_audio then
    lines[#lines + 1] = snapshot.video and "TROVATO   VIDEO AUDIO fuori dal Master" or "MANCA     VIDEO AUDIO"
  end

  if p.needs_music then
    lines[#lines + 1] = snapshot.music and "TROVATO   ZP Music Bus" or "MANCA     ZP Music Bus"
    lines[#lines + 1] = snapshot.music_fx and "TROVATO   Harmonic Space Carver" or "MANCA     Harmonic Space Carver"
    lines[#lines + 1] = snapshot.music_probe
      and (snapshot.music_probe_last and "TROVATO   Probe MUSIC ultimo FX" or "DA RIPARARE Probe MUSIC non ultimo")
      or "MANCA     Probe MUSIC"
  end

  lines[#lines + 1] = snapshot.master_fx and "TROVATO   ZP Master Pro" or "MANCA     ZP Master Pro"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Trasforma progetto crea solo gli elementi mancanti."
  lines[#lines + 1] = "Item e FX esistenti non vengono cancellati."
  return table.concat(lines, "\n")
end

local function apply_profile(profile)
  local report = { "Profilo: " .. profile.name, "" }
  local changed = false

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local vo = find_vo_bus()
  if not vo then
    vo = insert_track(reaper.CountTracks(0), "ZP VO BUS")
    report[#report + 1] = "AGGIUNTO  ZP VO BUS"
    changed = true
  else
    report[#report + 1] = "TROVATO   ZP VO BUS"
  end
  set_role(vo, "VO_BUS")

  local rec, edit = ensure_two_child_folder(vo, "REC", "EDIT", report)
  if rec then set_role(rec, "VO_REC") end
  if edit then set_role(edit, "VO_EDIT") end

  local bus_result = add_fx_if_missing(vo, FX.unified)
  report[#report + 1] =
    (bus_result == "found" and "TROVATO   " or bus_result == "added" and "AGGIUNTO  " or "MANCA     ")
    .. FX.unified.label
  changed = changed or bus_result == "added"

  local voice_probe_result = ensure_probe_last(vo, 0)
  report[#report + 1] =
    (voice_probe_result == "found" and "TROVATO   " or voice_probe_result == "moved" and "RIPARATO  "
      or voice_probe_result == "added" and "AGGIUNTO  " or "MANCA     ")
    .. "Probe VOICE (ultimo FX)"
  changed = changed or voice_probe_result == "added" or voice_probe_result == "moved"

  if profile.needs_video_audio then
    ensure_video_audio_track(vo, report)
    changed = true
  end

  if profile.needs_music then
    local music = find_music_bus()
    if not music then
      music = create_music_bus_from_selection(report)
      changed = true
    else
      report[#report + 1] = "TROVATO   ZP Music Bus"
    end
    set_role(music, "MUSIC_BUS")

    local space_result = add_fx_if_missing(music, FX.space)
    report[#report + 1] =
      (space_result == "found" and "TROVATO   " or space_result == "added" and "AGGIUNTO  " or "MANCA     ")
      .. FX.space.label
    changed = changed or space_result == "added"

    local music_probe_result = ensure_probe_last(music, 1)
    report[#report + 1] =
      (music_probe_result == "found" and "TROVATO   " or music_probe_result == "moved" and "RIPARATO  "
        or music_probe_result == "added" and "AGGIUNTO  " or "MANCA     ")
      .. "Probe MUSIC (ultimo FX)"
    changed = changed or music_probe_result == "added" or music_probe_result == "moved"
  end

  configure_master(profile, report)
  write_bus_profile(profile)
  report[#report + 1] = ensure_probe_guard_running()
  report[#report + 1] = ""
  report[#report + 1] = "Nessun item o FX esistente eliminato."

  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("ZP Chain Builder - " .. profile.name, changed and -1 or 0)

  return table.concat(report, "\n")
end

local HELP_TEXT =
  "ZP CHAIN BUILDER\n\n" ..
  "TRASFORMA PROGETTO\n" ..
  "Crea o completa la struttura scelta, aggiunge i plugin mancanti, assegna i ruoli dei Probe " ..
  "e configura target LUFS e ceiling di ZP Master Pro.\n\n" ..
  "CHECK / REPAIR\n" ..
  "Controlla la struttura attuale. Se mancano elementi, propone di crearli senza cancellare item o FX.\n\n" ..
  "VO BUS\n" ..
  "Contiene REC ed EDIT. BUS Chain e Probe VOICE sono sul BUS, con il Probe come ultimo FX.\n\n" ..
  "MUSIC BUS\n" ..
  "Usato da Podcast e Spot. Harmonic Space Carver e Probe MUSIC sono sul BUS. " ..
  "Il Probe misura la somma di tutte le musiche.\n\n" ..
  "TRACCE SELEZIONATE\n" ..
  "Se Podcast/Spot non hanno ancora un Music Bus e le tracce selezionate sono contigue, " ..
  "il Builder crea il BUS attorno a esse. Se non sono contigue, crea un BUS con una traccia MUSIC vuota.\n\n" ..
  "ADR / DOPPIAGGIO\n" ..
  "VIDEO AUDIO non invia al Master ed esce su hardware 1/2, per non entrare nel bounce.\n\n" ..
  "PROBE GUARD\n" ..
  "Viene rilevato e avviato automaticamente se disponibile nella stessa cartella."

local function run_ui()
  local profile_index = 1
  local _, stored = reaper.GetProjExtState(0, "ZP_CHAIN_BUILDER", "delivery_profile")
  local stored_id = tonumber(stored)
  if stored_id and PROFILES[stored_id] then profile_index = stored_id end

  local report_text = PROFILES[profile_index].description
  local last_mouse_down = false

  gfx.init("ZP Studio Suite - ZP Chain Builder", 780, 640)
  gfx.setfont(1, "Arial", 15)

  local function loop()
    local ch = gfx.getchar()
    if ch < 0 or ch == 27 then gfx.quit() return end

    local mouse_down = (gfx.mouse_cap & 1) == 1
    local clicked = mouse_down and not last_mouse_down
    last_mouse_down = mouse_down

    ZP_UI.fill_background()
    ZP_UI.draw_header({
      title = TITLE,
      credit = "ZP Studio Suite - Paolo Balestri",
      description = "Crea e adatta strutture VO, ADR, e-learning, podcast e spot.",
    })

    if ZP_UI.draw_button({ x = gfx.w - 54, y = 18, w = 34, h = 28 }, "?", false, true, clicked) then
      reaper.ShowMessageBox(HELP_TEXT, TITLE .. " - Istruzioni", 0)
    end

    gfx.setfont(1, "Arial", 14)
    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x, gfx.y = 22, 94
    gfx.drawstr("Delivery profile")

    local bw, gap = 230, 10
    for i, profile in ipairs(PROFILES) do
      local col = (i - 1) % 3
      local row = math.floor((i - 1) / 3)
      if ZP_UI.draw_button(
        { x = 22 + col * (bw + gap), y = 116 + row * 44, w = bw, h = 38 },
        profile.name, i == profile_index, true, clicked, "tab"
      ) then
        profile_index = i
        write_bus_profile(profile)
        report_text = profile.description
      end
    end

    gfx.set(0.68, 0.66, 0.74, 1)
    gfx.x, gfx.y = 22, 214
    gfx.drawstr("Cosa fa il profilo")

    gfx.set(0.10, 0.10, 0.14, 1)
    gfx.rect(22, 236, gfx.w - 44, 300, true)
    gfx.set(0.32, 0.31, 0.42, 1)
    gfx.rect(22, 236, gfx.w - 44, 300, false)
    gfx.setfont(1, "Arial", 14)
    gfx.set(0.92, 0.91, 0.94, 1)
    gfx.x, gfx.y = 36, 252
    gfx.drawstr(report_text, 5, 36, 252, gfx.w - 36, 522)

    if ZP_UI.draw_button({ x = 22, y = 570, w = 230, h = 40 }, "Trasforma progetto", false, true, clicked, "save") then
      report_text = apply_profile(PROFILES[profile_index])
      reaper.ShowMessageBox(report_text, TITLE .. " - Report finale", 0)
    end

    if ZP_UI.draw_button({ x = 262, y = 570, w = 230, h = 40 }, "Check / Repair", false, true, clicked, "tab") then
      local profile = PROFILES[profile_index]
      local snapshot = inspect(profile)
      report_text = check_report(snapshot)
      local answer = reaper.ShowMessageBox(
        report_text .. "\n\nCreare o riparare gli elementi mancanti?",
        TITLE, 4
      )
      if answer == 6 then
        report_text = apply_profile(profile)
        reaper.ShowMessageBox(report_text, TITLE .. " - Report finale", 0)
      end
    end

    if ZP_UI.draw_button({ x = gfx.w - 142, y = 570, w = 120, h = 40 }, "Chiudi", false, true, clicked) then
      gfx.quit()
      return
    end

    gfx.update()
    reaper.defer(loop)
  end

  loop()
end

run_ui()
