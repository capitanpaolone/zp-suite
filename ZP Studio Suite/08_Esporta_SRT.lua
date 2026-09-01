-- ESPORTA SRT FINALI DA RYTHMOBAND
-- Linea: ZP Paolo Balestri
-- Suite: ZP Studio Suite for REAPER v1.0.5
-- Distribuzione gratuita.
-- Esporta per video selezionati, regione sotto cursore, tutte le regioni
-- o tutti i video.
-- I sottotitoli vengono esportati con timecode relativo allo start della
-- regione/video, non alla posizione assoluta in timeline.

local SUBTITLE_TRACK_NAME = "Rythmo Band Testi"
local SCRIPT_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "")
local ZP_UI = dofile(SCRIPT_DIR .. "ZP_UI.lua")

local function trim(s)
  local out = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return out
end

local function dirname(path)
  return path:match("^(.*)[/\\][^/\\]+$") or ""
end

local function basename(path)
  return path:match("[^/\\]+$") or path
end

local function basename_without_ext(path)
  local name = basename(path)
  local out = name:gsub("%.[^%.]+$", "")
  return out
end

local function quote(path)
  return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end

local function ext_lower(path)
  return (path:match("%.([^%.\\/]+)$") or ""):lower()
end

local function is_video_file(path)
  local ext = ext_lower(path)
  return ext == "mp4" or ext == "mov" or ext == "m4v" or ext == "avi" or ext == "mkv"
end

local function clean_text(text)
  text = text or ""
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  return text
end

local function safe_filename(name)
  name = trim(name or "")
  name = name:gsub("[/\\:]", "_")
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then name = "export" end
  return name
end

local function seconds_to_srt_time(seconds)
  seconds = math.max(0, seconds or 0)
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds / 60) % 60)
  local s = math.floor(seconds % 60)
  local ms = math.floor(((seconds - math.floor(seconds)) * 1000) + 0.5)
  if ms >= 1000 then
    ms = 0
    s = s + 1
    if s >= 60 then
      s = 0
      m = m + 1
      if m >= 60 then
        m = 0
        h = h + 1
      end
    end
  end
  return string.format("%02d:%02d:%02d,%03d", h, m, s, ms)
end

local function collect_subtitle_tracks()
  local tracks = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if name == SUBTITLE_TRACK_NAME or name:find(SUBTITLE_TRACK_NAME, 1, true) then
      table.insert(tracks, { track = track, name = name, index = i + 1 })
    end
  end
  return tracks
end

local function choose_subtitle_track_numeric(tracks)
  if #tracks == 0 then return nil, nil end
  if #tracks == 1 then return tracks[1].track, tracks[1].name end

  local selected_track = reaper.GetSelectedTrack(0, 0)
  local default_index = 1
  local lines = {}
  for i, info in ipairs(tracks) do
    if info.track == selected_track then default_index = i end
    table.insert(lines, tostring(i) .. " = " .. info.name)
  end

  reaper.ShowMessageBox(
    "Nel progetto ci sono piu' tracce SRT/testi.\n\n" .. table.concat(lines, "\n"),
    "ZP Studio Suite - Scegli flusso testi",
    0
  )

  local ok, value = reaper.GetUserInputs(
    "Flusso testi da esportare",
    1,
    "Numero traccia testi:",
    tostring(default_index)
  )
  if not ok then return nil, nil end
  local selected_index = tonumber(trim(value)) or default_index
  if selected_index < 1 or selected_index > #tracks then selected_index = default_index end
  return tracks[selected_index].track, tracks[selected_index].name
end

local function osara_active()
  return type(reaper.osara_outputMessage) == "function"
end

local function source_path_from_item(item)
  local take = reaper.GetActiveTake(item)
  if not take then return "" end
  local source = reaper.GetMediaItemTake_Source(take)
  if not source then return "" end
  return reaper.GetMediaSourceFileName(source, "")
end

local function collect_video_items()
  local videos = {}
  for t = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, t)
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      local source_path = source_path_from_item(item)
      if is_video_file(source_path) then
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        table.insert(videos, {
          item = item,
          source_path = source_path,
          base = basename_without_ext(source_path),
          pos = pos,
          len = len,
          end_pos = pos + len
        })
      end
    end
  end
  table.sort(videos, function(a, b) return a.pos < b.pos end)
  return videos
end

local function collect_selected_video_items()
  local selected = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local source_path = source_path_from_item(item)
    if is_video_file(source_path) then
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      table.insert(selected, {
        item = item,
        source_path = source_path,
        base = basename_without_ext(source_path),
        pos = pos,
        len = len,
        end_pos = pos + len
      })
    end
  end
  table.sort(selected, function(a, b) return a.pos < b.pos end)
  return selected
end

local function collect_regions()
  local regions = {}
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local total = num_markers + num_regions
  for i = 0, total - 1 do
    local ok, is_region, pos, rgn_end, name = reaper.EnumProjectMarkers(i)
    if ok and is_region and name and name ~= "" and rgn_end > pos then
      table.insert(regions, {
        base = name,
        pos = pos,
        len = rgn_end - pos,
        end_pos = rgn_end,
        is_region = true
      })
    end
  end
  table.sort(regions, function(a, b) return a.pos < b.pos end)
  return regions
end

local function find_region_for_range(range, regions)
  local center = range.pos + ((range.end_pos - range.pos) * 0.5)
  for _, region in ipairs(regions) do
    if center >= region.pos - 0.0001 and center <= region.end_pos + 0.0001 then
      return region
    end
  end
  return nil
end

local function region_under_cursor(regions)
  local cursor = reaper.GetCursorPosition()
  for _, region in ipairs(regions) do
    if cursor >= region.pos and cursor <= region.end_pos then return region end
  end
  return nil
end

local function collect_subtitle_items(track)
  local items = {}
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    notes = clean_text(notes)
    if notes ~= "" then
      table.insert(items, { item = item, pos = pos, len = len, end_pos = pos + len, text = notes })
    end
  end
  table.sort(items, function(a, b) return a.pos < b.pos end)
  return items
end

local function project_dir()
  local _, project_path = reaper.EnumProjects(-1, "")
  local dir = dirname(project_path or "")
  if dir ~= "" then return dir end
  return reaper.GetResourcePath()
end

local function choose_output_dir(default_dir)
  if reaper.JS_Dialog_BrowseForFolder then
    local ok, folder = reaper.JS_Dialog_BrowseForFolder("Scegli cartella export SRT", default_dir)
    folder = trim(folder or "")
    if ok and folder ~= "" then return folder end
    return nil
  end

  local ok, path = reaper.GetUserFileNameForRead(default_dir, "Scegli un file dentro la cartella export", "")
  if not ok then return nil end
  path = trim(path)
  if path == "" then return nil end
  local maybe_dir = dirname(path)
  if maybe_dir ~= "" then return maybe_dir end
  return path
end

local function ensure_dir(path)
  path = trim(path or "")
  if path == "" then return false end
  if reaper.RecursiveCreateDirectory then
    reaper.RecursiveCreateDirectory(path, 0)
    return true
  end
  os.execute("mkdir -p " .. quote(path))
  return true
end

local function write_srt(path, cues)
  local f = io.open(path, "wb")
  if not f then return false end
  for i, cue in ipairs(cues) do
    f:write(tostring(i), "\n")
    f:write(seconds_to_srt_time(cue.start_pos), " --> ", seconds_to_srt_time(cue.end_pos), "\n")
    f:write(cue.text, "\n\n")
  end
  f:close()
  return true
end

local function choose_mode()
  local ok, csv = reaper.GetUserInputs(
    "Esporta SRT finali",
    1,
    "Modo 1 video selez. 2 regione cursore 3 tutte regioni 4 tutti video:",
    "1"
  )
  if not ok then return nil end
  local mode = tonumber(trim(csv)) or 1
  if mode < 1 or mode > 4 then mode = 1 end
  return mode
end

local function choose_single_name(default_name)
  local ok, value = reaper.GetUserInputs(
    "Nome SRT",
    1,
    "Nome file senza .srt:,extrawidth=420",
    safe_filename(default_name)
  )
  if not ok then return nil end
  return safe_filename(value)
end

local function collect_cues_for_range(range, subs)
  local cues = {}
  for _, sub in ipairs(subs) do
    if sub.pos >= range.pos - 0.0001 and sub.pos < range.end_pos + 0.0001 then
      local start_pos = sub.pos - range.pos
      local end_pos = sub.end_pos - range.pos
      if end_pos > start_pos then
        table.insert(cues, { start_pos = start_pos, end_pos = end_pos, text = sub.text })
      end
    end
  end
  return cues
end

local function label_for_mode(mode)
  if mode == 1 then return "video selezionati" end
  if mode == 2 then return "regione sotto cursore" end
  if mode == 3 then return "tutte le regioni" end
  return "tutti i video"
end

local function suggested_mode()
  if #collect_selected_video_items() > 0 then return 1 end
  if region_under_cursor(collect_regions()) then return 2 end
  return 3
end

local function default_track_index(tracks)
  local selected_track = reaper.GetSelectedTrack(0, 0)
  for i, info in ipairs(tracks) do
    if info.track == selected_track then return i end
  end
  return 1
end

local function point_in_rect(x, y, rx, ry, rw, rh)
  return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function fit_text(text, max_w)
  text = tostring(text or "")
  if gfx.measurestr(text) <= max_w then return text end

  local suffix = "..."
  local suffix_w = gfx.measurestr(suffix)
  local out = ""
  for i = 1, #text do
    local candidate = text:sub(1, i)
    if gfx.measurestr(candidate) + suffix_w > max_w then break end
    out = candidate
  end
  out = out:gsub("%s+$", "")
  if out == "" then return suffix end
  return out .. suffix
end

local function draw_button(rect, label, active, enabled, clicked, style)
  return ZP_UI.draw_button(rect, label, active, enabled, clicked, style)
end

local function open_export_settings_visual(tracks, on_done)
  if not gfx or not gfx.init then return false end

  local track_index = default_track_index(tracks)
  local mode = suggested_mode()
  local destination_mode = "srt_export"
  local custom_out_dir = ""
  local last_mouse_down = false

  gfx.init("ZP Studio Suite v1.0.5 - Export SRT", 760, 500)
  gfx.setfont(1, "Arial", 16)

  local function loop()
    local ch = gfx.getchar()
    if ch < 0 or ch == 27 then gfx.quit() return end

    local mouse_down = (gfx.mouse_cap & 1) == 1
    local clicked = mouse_down and not last_mouse_down
    last_mouse_down = mouse_down

    local regions = collect_regions()
    local selected_videos = collect_selected_video_items()
    local all_videos = collect_video_items()
    local cursor_region = region_under_cursor(regions)

    ZP_UI.fill_background()

    gfx.set(0.10, 0.42, 0.48, 1)
    gfx.rect(22, 16, 34, 34, true)
    gfx.set(0.92, 0.88, 0.70, 1)
    gfx.rect(30, 22, 16, 22, false)
    gfx.triangle(44, 29, 44, 39, 53, 34, true)
    gfx.set(0.92, 0.88, 0.78, 1)
    gfx.x = 66
    gfx.y = 18
    gfx.setfont(1, "Arial", 20)
    gfx.drawstr("Export SRT")

    gfx.setfont(1, "Arial", 12)
    gfx.set(0.56, 0.72, 0.86, 1)
    gfx.x = 66
    gfx.y = 42
    gfx.drawstr("ZP Studio Suite v1.0.5 - Paolo Balestri")

    gfx.setfont(1, "Arial", 15)
    gfx.set(0.68, 0.66, 0.74, 1)
    gfx.x = 22
    gfx.y = 60
    gfx.drawstr("Scegli cosa esportare e quale flusso testi usare.")
    ZP_UI.draw_help_button({ x = gfx.w - 54, y = 18, w = 34, h = 28 }, clicked, "zp-gestione-srt")

    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x = 22
    gfx.y = 92
    gfx.drawstr("Cosa esportare")

    local mode_buttons = {
      { mode = 1, label = "Video selezionati (" .. #selected_videos .. ")", enabled = #selected_videos > 0 },
      { mode = 2, label = "Regione al cursore" .. (cursor_region and (" - " .. cursor_region.base) or " (nessuna)"), enabled = cursor_region ~= nil },
      { mode = 3, label = "Tutte le regioni (" .. #regions .. ")", enabled = #regions > 0 },
      { mode = 4, label = "Tutti i video (" .. #all_videos .. ")", enabled = #all_videos > 0 }
    }

    for i, button in ipairs(mode_buttons) do
      local rect = { x = 22, y = 108 + ((i - 1) * 42), w = 330, h = 34 }
      if draw_button(rect, button.label, mode == button.mode, button.enabled, clicked, "tab") then mode = button.mode end
    end

    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x = 386
    gfx.y = 84
    gfx.drawstr("Flusso testi")

    local list_y = 108
    for i, info in ipairs(tracks) do
      local rect = { x = 386, y = list_y + ((i - 1) * 42), w = 300, h = 34 }
      if draw_button(rect, info.name, track_index == i, true, clicked, "tab") then track_index = i end
    end

    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x = 22
    gfx.y = 300
    gfx.drawstr("Destinazione")

    local project_folder = project_dir()
    local out_dir = project_folder
    if destination_mode == "srt_export" then
      out_dir = project_folder .. "/SRT_export"
    elseif destination_mode == "custom" then
      out_dir = custom_out_dir ~= "" and custom_out_dir or project_folder
    end

    if draw_button({ x = 22, y = 318, w = 140, h = 34 }, "Progetto", destination_mode == "project", true, clicked, "tab") then
      destination_mode = "project"
    end
    if draw_button({ x = 174, y = 318, w = 140, h = 34 }, "SRT_export", destination_mode == "srt_export", true, clicked, "tab") then
      destination_mode = "srt_export"
    end
    if draw_button({ x = 326, y = 318, w = 120, h = 34 }, "Scegli...", destination_mode == "custom", true, clicked, "tab") then
      local picked = choose_output_dir(custom_out_dir ~= "" and custom_out_dir or project_folder)
      if picked and picked ~= "" then
        custom_out_dir = picked
        destination_mode = "custom"
      end
    end
    gfx.set(0.70, 0.72, 0.78, 1)
    gfx.x = 458
    gfx.y = 326
    gfx.drawstr(fit_text(out_dir, gfx.w - 480))

    gfx.set(0.48, 0.47, 0.54, 1)
    gfx.x = 22
    gfx.y = 368
    if #selected_videos == 0 and not cursor_region then
      gfx.drawstr(fit_text("Suggerimento: puoi selezionare un video o spostare il cursore dentro una regione, poi cliccare la scelta relativa.", gfx.w - 44))
    else
      gfx.drawstr(fit_text("Il contesto si aggiorna mentre la finestra e' aperta. Scegli... apre il selettore cartella del sistema.", gfx.w - 44))
    end

    local ok_enabled = (mode == 1 and #selected_videos > 0)
      or (mode == 2 and cursor_region ~= nil)
      or (mode == 3 and #regions > 0)
      or (mode == 4 and #all_videos > 0)

    if draw_button({ x = 430, y = 430, w = 124, h = 38 }, "Esporta", false, ok_enabled, clicked, "save") then
      local track = tracks[track_index]
      local out_dir = project_dir()
      if destination_mode == "srt_export" then
        out_dir = project_dir() .. "/SRT_export"
      elseif destination_mode == "custom" and custom_out_dir ~= "" then
        out_dir = custom_out_dir
      end
      gfx.quit()
      on_done(track.track, track.name, mode, out_dir)
      return
    end

    if draw_button({ x = 566, y = 430, w = 124, h = 38 }, "Annulla", false, true, clicked) then
      gfx.quit()
      return
    end

    gfx.update()
    reaper.defer(loop)
  end

  reaper.defer(loop)
  return true
end

local function choose_export_settings_numeric(tracks)
  if #tracks == 0 then return nil, nil, nil end
  local track, name = choose_subtitle_track_numeric(tracks)
  if not track then return nil, nil, nil end
  local mode = choose_mode()
  if not mode then return nil, nil, nil end
  return track, name, mode
end

local function run_export(sub_track, sub_track_name, mode, visual_out_dir)
  local regions = collect_regions()
  local ranges = {}
  if mode == 1 then
    ranges = collect_selected_video_items()
    for _, range in ipairs(ranges) do
      local region = find_region_for_range(range, regions)
      if region then range.base = region.base end
    end
  elseif mode == 2 then
    local region = region_under_cursor(regions)
    if region then ranges = { region } end
  elseif mode == 3 then
    ranges = regions
  else
    ranges = collect_video_items()
    for _, range in ipairs(ranges) do
      local region = find_region_for_range(range, regions)
      if region then range.base = region.base end
    end
  end

  if #ranges == 0 then
    reaper.ShowMessageBox("Nessun blocco trovato per il modo scelto:\n" .. label_for_mode(mode), "ZP Studio Suite", 0)
    return
  end

  local out_dir = trim(visual_out_dir or "")
  if out_dir == "" then out_dir = choose_output_dir(project_dir()) end
  if not out_dir then return end
  ensure_dir(out_dir)

  local subs = collect_subtitle_items(sub_track)
  local exported = 0
  local skipped = 0
  local custom_single_name = nil
  if #ranges == 1 then
    custom_single_name = choose_single_name(ranges[1].base)
    if not custom_single_name then return end
  end

  for _, range in ipairs(ranges) do
    local cues = collect_cues_for_range(range, subs)

    if #cues > 0 then
      local filename = custom_single_name or safe_filename(range.base)
      local out_path = out_dir .. "/" .. filename .. ".srt"
      if write_srt(out_path, cues) then exported = exported + 1 else skipped = skipped + 1 end
    else
      skipped = skipped + 1
    end
  end

  reaper.ShowMessageBox(
    "Export SRT completato.\n\nModo: " .. label_for_mode(mode) ..
    "\nFlusso testi: " .. (sub_track_name or SUBTITLE_TRACK_NAME) ..
    "\nBlocchi trovati: " .. #ranges ..
    "\nSRT esportati: " .. exported ..
    "\nBlocchi senza export/errori: " .. skipped ..
    "\n\nCartella:\n" .. out_dir,
    "ZP Studio Suite",
    0
  )
end

local function main()
  local subtitle_tracks = collect_subtitle_tracks()
  if #subtitle_tracks == 0 then
    reaper.ShowMessageBox("Traccia testi/SRT non trovata:\n" .. SUBTITLE_TRACK_NAME, "ZP Studio Suite", 0)
    return
  end

  if not osara_active() then
    local opened = open_export_settings_visual(subtitle_tracks, run_export)
    if opened then return end
  end

  local sub_track, sub_track_name, mode = choose_export_settings_numeric(subtitle_tracks)
  if not sub_track or not mode then return end
  run_export(sub_track, sub_track_name, mode)
end

main()
