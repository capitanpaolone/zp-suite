--[[
  ZP Studio Suite for REAPER v1.0.5
  Script: Importa cartelle
  Autore: Paolo Balestri
  Distribuzione gratuita.

  Cosa fa:
  - chiede una cartella madre;
  - legge le sottocartelle dirette in ordine alfabetico naturale;
  - importa audio/video contenuti nelle sottocartelle su una traccia dedicata;
  - crea un marker col nome della sottocartella;
  - crea una regione col nome del file senza estensione;
  - lascia al Gestore Progetto la preparazione Mixdown e i report di export.

  Non fa ancora render automatico.
]]

local SCRIPT_TITLE = "ZP Studio Suite v1.0.5 - Import Cartelle"
local EXT_SECTION = "ZP_VoiceOverStudio_FolderVideoMixdown"
local MODE_IMPORT_AND_PREPARE = "import"
local MODE_PREPARE_EXISTING = "prepare_existing"
local VIDEO_TRACK_NAME = "MEDIA IMPORT"
local MIXDOWN_FOLDER_NAME = "Mixdown"
local COLOR_VIDEO = 0xE74C3C
local COLOR_REGION = reaper.ColorToNative(40, 170, 210) | 0x1000000
local COLOR_MARKER = reaper.ColorToNative(238, 116, 46) | 0x1000000
local DEFAULT_VIDEO_GAP = 10.0
local DEFAULT_FOLDER_GAP = 20.0
local PEAK_BUILD_MODE = "missing"
-- valori possibili:
-- "missing"  = consigliato, costruisce solo i peak mancanti
-- "selected" = ricostruisce i peak degli item importati
-- "all"      = fallback pesante, ricostruisce tutti i peak del progetto
local EPS = 0.000001
local sep = package.config:sub(1, 1)

local function script_dir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*)[/\\]") or "."
end

local ZP_UI = dofile(script_dir() .. "/ZP_UI.lua")

local function trim(s)
  local out = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return out
end

local function quote(path)
  return "'" .. tostring(path or ""):gsub("'", "'\\''") .. "'"
end

local function basename(path)
  return tostring(path or ""):match("[^/\\]+$") or tostring(path or "")
end

local function dirname(path)
  return tostring(path or ""):match("^(.*)[/\\][^/\\]+$") or ""
end

local function basename_without_ext(path)
  local name = basename(path)
  return name:gsub("%.[^%.]+$", "")
end

local function ext_lower(path)
  return (tostring(path or ""):match("%.([^%.\\/]+)$") or ""):lower()
end

local VIDEO_EXTENSIONS = {
  mp4 = true, mov = true, m4v = true, avi = true, mkv = true, webm = true
}

local AUDIO_EXTENSIONS = {
  wav = true, wave = true, mp3 = true, flac = true, aif = true, aiff = true,
  ogg = true, m4a = true, aac = true, opus = true, wma = true
}

local function is_importable_media(path)
  local ext = ext_lower(path)
  return VIDEO_EXTENSIONS[ext] == true or AUDIO_EXTENSIONS[ext] == true
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function ensure_directory(path)
  if reaper.RecursiveCreateDirectory then
    reaper.RecursiveCreateDirectory(path, 0)
    return true
  end
  return false
end

local function copy_file(src, dst)
  if src == dst then return true end
  local input = io.open(src, "rb")
  if not input then return false, "Impossibile leggere: " .. src end
  local output = io.open(dst, "wb")
  if not output then
    input:close()
    return false, "Impossibile scrivere: " .. dst
  end
  while true do
    local block = input:read(1024 * 1024)
    if not block then break end
    output:write(block)
  end
  input:close()
  output:close()
  return true
end

local function project_file_path()
  local _, project_path = reaper.EnumProjects(-1, "")
  project_path = trim(project_path or "")
  if project_path == "" then return nil end
  return project_path
end

local function project_dir()
  local path = project_file_path()
  if not path then return nil end
  return dirname(path)
end

local function ensure_saved_project()
  local path = project_file_path()
  if path then return path, project_dir() end

  local choice = reaper.ShowMessageBox(
    "Per questa operazione occorre salvare il progetto.\n\nVuoi aprire Salva progetto con nome?",
    "ZP Studio Suite",
    4
  )
  if choice ~= 6 then return nil, nil, "Progetto non salvato." end

  reaper.Main_SaveProject(0, true)
  path = project_file_path()
  if not path then return nil, nil, "Salvataggio progetto annullato." end
  return path, project_dir()
end

local function safe_filename(name)
  name = trim(tostring(name or ""))
  if name == "" then name = "Senza nome" end
  name = name:gsub("[/\\:*?\"<>|]", "_"):gsub("%s+", " ")
  return name
end

local function unique_path(folder, src_path)
  local name = safe_filename(basename(src_path))
  local candidate = folder .. sep .. name
  if not file_exists(candidate) then return candidate end

  local stem = name:gsub("%.[^%.]+$", "")
  local ext = name:match("(%.[^%.]+)$") or ""
  local index = 2
  while true do
    candidate = folder .. sep .. stem .. "_" .. tostring(index) .. ext
    if not file_exists(candidate) then return candidate end
    index = index + 1
  end
end

local function normalize_path(path)
  return tostring(path or ""):gsub("\\", "/"):gsub("/+$", "")
end

local function path_is_inside(path, folder)
  local p = normalize_path(path)
  local f = normalize_path(folder)
  if p == "" or f == "" then return false end
  return p == f or p:sub(1, #f + 1) == f .. "/"
end

local function file_size(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  f:close()
  return size
end

local function candidate_project_dirs(project_folder, media_dir)
  local dirs = {}
  local seen = {}
  local function add(dir)
    dir = tostring(dir or "")
    if dir == "" then return end
    local key = normalize_path(dir)
    if key ~= "" and not seen[key] then
      seen[key] = true
      dirs[#dirs + 1] = dir
    end
  end
  add(project_folder)
  add(media_dir)
  local media_parent = dirname(media_dir)
  if basename(media_parent) == "Media" then add(media_parent) end
  return dirs
end

local function find_existing_project_file(src_path, project_folder, media_dir)
  local wanted_name = safe_filename(basename(src_path))
  local src_size = file_size(src_path)
  local fallback = nil
  for _, dir in ipairs(candidate_project_dirs(project_folder, media_dir)) do
    local candidate = dir .. sep .. wanted_name
    if file_exists(candidate) then
      local candidate_size = file_size(candidate)
      if src_size and candidate_size == src_size then return candidate, true end
      fallback = fallback or candidate
    end
  end
  return fallback, false
end

local zp_choice_dialog

local function ask_project_file_policy(src_path, existing_path, same_size, copy_state)
  copy_state = copy_state or {}
  if copy_state.policy then return copy_state.policy end

  local size_note = same_size and "Dimensione uguale: sembra lo stesso file." or "Attenzione: dimensione diversa o non verificabile."
  local policy, apply_all = zp_choice_dialog({
    title = "ZP Studio Suite - File gia presente",
    heading = "Occhio: questo file sembra gia' nel progetto",
    message = "File: " .. basename(src_path) .. "\nTrovato in: " .. existing_path .. "\n" .. size_note .. "\nChe facciamo?",
    apply_all_label = "Applica a tutti",
    button_w = 132,
    buttons = {
      { label = "Usa questo", value = "use_existing", style = "play_select" },
      { label = "Sovrascrivi", value = "overwrite", style = "danger" },
      { label = "Tieni entrambi", value = "copy_new", style = "tab" },
      { label = "Annulla", value = "abort" },
    },
    cancel_value = "abort"
  })
  if apply_all and policy ~= "abort" then copy_state.policy = policy end
  return policy
end

local function resolve_project_copy(src_path, project_folder, media_dir, copy_state)
  if path_is_inside(src_path, project_folder) then return src_path, "already_in_project" end
  local existing, same_size = find_existing_project_file(src_path, project_folder, media_dir)
  if existing then
    local policy = ask_project_file_policy(src_path, existing, same_size, copy_state)
    if policy == "use_existing" then return existing, "used_existing" end
    if policy == "overwrite" then
      local ok, err = copy_file(src_path, existing)
      if not ok then return nil, err end
      return existing, "overwritten"
    end
    if policy == "copy_new" then
      ensure_directory(media_dir)
      local dst = unique_path(media_dir, src_path)
      local ok, err = copy_file(src_path, dst)
      if not ok then return nil, err end
      return dst, "copied_new"
    end
    return nil, "Operazione annullata."
  end
  ensure_directory(media_dir)
  local dst = unique_path(media_dir, src_path)
  local ok, err = copy_file(src_path, dst)
  if not ok then return nil, err end
  return dst, "copied"
end

local function draw_wrapped_text(text, x, y, max_w, line_h, max_lines)
  text = tostring(text or "")
  local lines = {}
  for paragraph in (text .. "\n"):gmatch("(.-)\n") do
    local current = ""
    for word in paragraph:gmatch("%S+") do
      local candidate = current == "" and word or (current .. " " .. word)
      if gfx.measurestr(candidate) <= max_w then
        current = candidate
      else
        if current ~= "" then lines[#lines + 1] = current end
        current = word
      end
    end
    if current ~= "" then lines[#lines + 1] = current end
    if paragraph == "" then lines[#lines + 1] = "" end
  end
  local count = math.min(#lines, max_lines or #lines)
  for i = 1, count do
    gfx.x = x
    gfx.y = y + (i - 1) * line_h
    gfx.drawstr(ZP_UI.fit_text(lines[i], max_w))
  end
end

zp_choice_dialog = function(opts)
  opts = opts or {}
  local buttons = opts.buttons or {}
  if #buttons == 0 then return opts.cancel_value or "abort", false end

  local lines = {}
  if opts.heading and opts.heading ~= "" then
    lines[#lines + 1] = tostring(opts.heading)
    lines[#lines + 1] = ""
  end
  if opts.message and opts.message ~= "" then
    lines[#lines + 1] = tostring(opts.message)
    lines[#lines + 1] = ""
  end

  lines[#lines + 1] = "Opzioni disponibili:"
  for i, btn in ipairs(buttons) do
    lines[#lines + 1] = tostring(i) .. " - " .. tostring(btn.label or btn.value or "Scelta")
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Nella prossima casella inserisci solo il numero della scelta."

  reaper.ShowMessageBox(table.concat(lines, "\n"), opts.title or "ZP Studio Suite", 0)

  local ok, value = reaper.GetUserInputs(
    opts.title or "ZP Studio Suite",
    1,
    "Numero scelta 1-" .. tostring(#buttons) .. ":,extrawidth=260",
    "1"
  )
  if not ok then return opts.cancel_value or "abort", false end

  local index = tonumber((trim(value):match("%d+"))) or 0
  local button = buttons[index]
  if not button then
    reaper.ShowMessageBox("Scelta non valida. Operazione annullata.", opts.title or "ZP Studio Suite", 0)
    return opts.cancel_value or "abort", false
  end

  local result = button.value or (opts.cancel_value or "abort")
  local apply_all = false
  if opts.apply_all_label and result ~= (opts.cancel_value or "abort") then
    local apply = reaper.ShowMessageBox(
      tostring(opts.apply_all_label) .. "?",
      opts.title or "ZP Studio Suite",
      4
    )
    apply_all = apply == 6
  end
  return result, apply_all
end

local function unique_output_path(folder, base_name, extension, used_paths)
  extension = extension or ".wav"
  if extension:sub(1, 1) ~= "." then extension = "." .. extension end
  local stem = safe_filename(base_name):gsub("%.[^%.]+$", "")
  local candidate = folder .. sep .. stem .. extension
  local key = candidate:lower()
  if not used_paths[key] and not file_exists(candidate) then
    used_paths[key] = true
    return candidate
  end

  local index = 2
  while true do
    candidate = folder .. sep .. stem .. "_" .. tostring(index) .. extension
    key = candidate:lower()
    if not used_paths[key] and not file_exists(candidate) then
      used_paths[key] = true
      return candidate
    end
    index = index + 1
  end
end

local function natural_key(text)
  return tostring(text or ""):lower():gsub("%d+", function(d)
    return string.format("%012d", tonumber(d) or 0)
  end)
end

local function sort_by_natural_name(list)
  table.sort(list, function(a, b)
    return natural_key(basename(a)) < natural_key(basename(b))
  end)
end

local function scan_direct_subfolders(root)
  local folders = {}
  local cmd = "find " .. quote(root) .. " -mindepth 1 -maxdepth 1 -type d"
  local p = io.popen(cmd)
  if not p then return folders end
  for path in p:lines() do table.insert(folders, path) end
  p:close()
  sort_by_natural_name(folders)
  return folders
end

local function scan_media_files(folder)
  local media = {}
  local ignored = {}
  local cmd = "find " .. quote(folder) .. " -maxdepth 1 -type f"
  local p = io.popen(cmd)
  if not p then return media, ignored end
  for path in p:lines() do
    if is_importable_media(path) then
      table.insert(media, path)
    else
      table.insert(ignored, path)
    end
  end
  p:close()
  sort_by_natural_name(media)
  return media, ignored
end

local function native_track_color(color)
  local r = (color >> 16) & 0xFF
  local g = (color >> 8) & 0xFF
  local b = color & 0xFF
  return reaper.ColorToNative(r, g, b) | 0x1000000
end

local function set_track_color(track, color)
  reaper.SetTrackColor(track, native_track_color(color))
end

local function find_track_exact(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if track_name == name then return track end
  end
  return nil
end

local function get_or_create_video_track()
  local track = find_track_exact(VIDEO_TRACK_NAME)
  if track then return track end
  track = find_track_exact("VIDEO")
  if track then return track end
  reaper.InsertTrackAtIndex(0, true)
  track = reaper.GetTrack(0, 0)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", VIDEO_TRACK_NAME, true)
  set_track_color(track, COLOR_VIDEO)
  return track
end

local function video_file_length(path)
  local source = reaper.PCM_Source_CreateFromFile(path)
  if not source then return nil end
  return reaper.GetMediaSourceLength(source)
end

local function next_free_video_position(track, desired_start, duration, gap)
  desired_start = math.max(0, desired_start or 0)
  duration = math.max(0, duration or 0)
  gap = math.max(0, gap or 0)
  if not track or duration <= 0 then return desired_start end

  local ranges = {}
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if len and len > 0 then table.insert(ranges, { start_pos = pos, end_pos = pos + len }) end
  end
  table.sort(ranges, function(a, b) return a.start_pos < b.start_pos end)

  local candidate = desired_start
  for _, range in ipairs(ranges) do
    if candidate + duration <= range.start_pos + EPS then return candidate end
    if candidate < range.end_pos and candidate + duration > range.start_pos then
      candidate = range.end_pos + gap
    end
  end
  return candidate
end

local function add_video_item(track, path, start_pos)
  local source = reaper.PCM_Source_CreateFromFile(path)
  if not source then return nil, "REAPER non riesce a caricare il file media: " .. path end

  local item = reaper.AddMediaItemToTrack(track)
  local take = reaper.AddTakeToMediaItem(item)
  reaper.SetMediaItemTake_Source(take, source)
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", basename_without_ext(path), true)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", start_pos)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", reaper.GetMediaSourceLength(source))
  reaper.GetSetMediaItemInfo_String(item, "P_NAME", basename_without_ext(path), true)
  reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "ZP Studio Suite folder batch media", true)
  return item
end

local function save_selected_items()
  local selected = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    selected[#selected + 1] = reaper.GetSelectedMediaItem(0, i)
  end
  return selected
end

local function restore_selected_items(selected)
  reaper.Main_OnCommand(40289, 0) -- Item: Unselect all items
  for _, item in ipairs(selected or {}) do
    if reaper.ValidatePtr(item, "MediaItem*") then
      reaper.SetMediaItemSelected(item, true)
    end
  end
  reaper.UpdateArrange()
end

local function select_only_items(items)
  reaper.Main_OnCommand(40289, 0) -- Item: Unselect all items
  for _, item in ipairs(items or {}) do
    if reaper.ValidatePtr(item, "MediaItem*") then
      reaper.SetMediaItemSelected(item, true)
    end
  end
  reaper.UpdateArrange()
end

local function build_peaks_after_import(mode, imported_items)
  mode = mode or "missing"

  if mode == "selected" then
    if imported_items and #imported_items > 0 then
      local previous_selection = save_selected_items()
      select_only_items(imported_items)
      reaper.Main_OnCommand(40441, 0) -- Peaks: Rebuild peaks for selected items
      restore_selected_items(previous_selection)
    else
      reaper.Main_OnCommand(40047, 0) -- Peaks: Build any missing peaks
    end
  elseif mode == "all" then
    reaper.Main_OnCommand(40048, 0) -- Peaks: Rebuild all peaks
  else
    reaper.Main_OnCommand(40047, 0) -- Peaks: Build any missing peaks
  end

  reaper.UpdateArrange()
end

local function create_folder_marker(name, position)
  return reaper.AddProjectMarker2(0, false, position, 0, name, -1, COLOR_MARKER)
end

local function create_item_region(name, start_pos, end_pos)
  if end_pos <= start_pos then return nil end
  return reaper.AddProjectMarker2(0, true, start_pos, end_pos, name, -1, COLOR_REGION)
end

local function select_root_folder()
  local last = reaper.GetExtState(EXT_SECTION, "last_root") or ""
  if reaper.JS_Dialog_BrowseForFolder then
    local ok, folder = reaper.JS_Dialog_BrowseForFolder("Scegli cartella con audio/video o cartella madre", last)
    if ok and folder and trim(folder) ~= "" then return trim(folder) end
    return nil
  end

  local ok, path = reaper.GetUserFileNameForRead(last, "Scegli un file dentro la cartella madre", "")
  if not ok then return nil end
  return dirname(trim(path))
end

local function choose_workflow()
  return MODE_IMPORT_AND_PREPARE
end

local function get_settings()
  local ok, values = reaper.GetUserInputs(
    "Importa cartelle - ZP Studio Suite",
    3,
    "Pausa tra file sec:,Pausa tra cartelle sec:,Copia media nel progetto? 1 si 0 no:,extrawidth=620",
    tostring(DEFAULT_VIDEO_GAP) .. "," .. tostring(DEFAULT_FOLDER_GAP) .. ",0"
  )
  if not ok then return nil end
  local video_gap_txt, folder_gap_txt, copy_txt = values:match("^(.-),(.-),(.*)$")
  return {
    video_gap = tonumber(trim(video_gap_txt or "")) or DEFAULT_VIDEO_GAP,
    folder_gap = tonumber(trim(folder_gap_txt or "")) or DEFAULT_FOLDER_GAP,
    copy_files = trim(copy_txt or "") == "1",
    prepare_mixdown = false
  }
end

local function draw_import_icon(x, y, size)
  gfx.set(0.10, 0.42, 0.48, 1)
  gfx.rect(x, y, size, size, true)
  gfx.set(0.92, 0.88, 0.70, 1)
  gfx.rect(x + size * 0.28, y + size * 0.18, size * 0.30, size * 0.64, false)
  gfx.triangle(x + size * 0.60, y + size * 0.35, x + size * 0.60, y + size * 0.65, x + size * 0.84, y + size * 0.50, true)
end

local function point_in_rect(x, y, rx, ry, rw, rh)
  if ZP_UI and ZP_UI.point_in_rect then return ZP_UI.point_in_rect(x, y, rx, ry, rw, rh) end
  return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function fit_text(text, max_w)
  if ZP_UI and ZP_UI.fit_text then return ZP_UI.fit_text(text, max_w) end
  text = tostring(text or "")
  if gfx.measurestr(text) <= max_w then return text end
  local out = ""
  for i = 1, #text do
    local candidate = text:sub(1, i)
    if gfx.measurestr(candidate .. "...") > max_w then break end
    out = candidate
  end
  return out .. "..."
end

local function draw_panel(rect)
  gfx.set(0.10, 0.10, 0.14, 1)
  gfx.rect(rect.x, rect.y, rect.w, rect.h, true)
  gfx.set(0.32, 0.31, 0.42, 1)
  gfx.rect(rect.x, rect.y, rect.w, rect.h, false)
end

local function draw_button(rect, label, active, enabled, clicked, style)
  if ZP_UI and ZP_UI.draw_button then
    return ZP_UI.draw_button(rect, label, active, enabled, clicked, style)
  end
  enabled = enabled ~= false
  local hover = enabled and point_in_rect(gfx.mouse_x, gfx.mouse_y, rect.x, rect.y, rect.w, rect.h)
  gfx.set(active and 0.16 or hover and 0.24 or 0.13, active and 0.42 or hover and 0.32 or 0.13, active and 0.60 or hover and 0.44 or 0.19, enabled and 1 or 0.45)
  gfx.rect(rect.x, rect.y, rect.w, rect.h, true)
  gfx.set(0.42, 0.44, 0.56, 1)
  gfx.rect(rect.x, rect.y, rect.w, rect.h, false)
  gfx.setfont(1, "Arial", 14)
  gfx.set(0.92, 0.91, 0.94, enabled and 1 or 0.45)
  gfx.x = rect.x + 10
  gfx.y = rect.y + 8
  gfx.drawstr(fit_text(label, rect.w - 20))
  return clicked and hover and enabled
end

local function draw_folder_choice_box(rect, path, enabled)
  local has_path = trim(path or "") ~= ""
  gfx.set(has_path and 0.08 or 0.09, has_path and 0.14 or 0.10, has_path and 0.18 or 0.14, enabled and 1 or 0.45)
  gfx.rect(rect.x, rect.y, rect.w, rect.h, true)
  gfx.set(has_path and 0.30 or 0.24, has_path and 0.58 or 0.28, has_path and 0.64 or 0.38, enabled and 1 or 0.45)
  gfx.rect(rect.x, rect.y, rect.w, rect.h, false)

  local title = has_path and basename(path) or "Nessuna cartella scelta"
  local subtitle = has_path and dirname(path) or "Premi Scegli per indicare dove cercare audio/video"
  gfx.setfont(1, "Arial", 14, has_path and 'b' or nil)
  gfx.set(has_path and 0.90 or 0.62, has_path and 0.96 or 0.64, has_path and 0.96 or 0.72, enabled and 1 or 0.45)
  gfx.x = rect.x + 10
  gfx.y = rect.y + 6
  gfx.drawstr(fit_text(title, rect.w - 20))
  gfx.setfont(1, "Arial", 12)
  gfx.set(0.58, 0.72, 0.78, enabled and 0.95 or 0.38)
  gfx.x = rect.x + 10
  gfx.y = rect.y + 25
  gfx.drawstr(fit_text(subtitle, rect.w - 20))
end

local function open_suite_help(anchor)
  local help_path = script_dir() .. "/help/index.html"
  local suffix = anchor and anchor ~= "" and ("#" .. anchor) or ""
  local os_name = reaper.GetOS and reaper.GetOS() or ""
  if os_name:match("Win") then
    os.execute('start "" "' .. help_path:gsub('"', '\\"') .. suffix .. '"')
  elseif os_name:match("OSX") or os_name:match("macOS") then
    os.execute("open " .. quote(help_path .. suffix))
  else
    os.execute("xdg-open " .. quote(help_path .. suffix) .. " >/dev/null 2>&1 &")
  end
end

local function prepare_plan(root)
  local folders = scan_direct_subfolders(root)
  local plan = {}
  local ignored_count = 0

  local root_videos, root_ignored = scan_media_files(root)
  ignored_count = ignored_count + #root_ignored
  if #root_videos > 0 then
    table.insert(plan, {
      folder = root,
      folder_name = basename(root),
      videos = root_videos,
      is_root_folder = true
    })
  end

  for _, folder in ipairs(folders) do
    local videos, ignored = scan_media_files(folder)
    ignored_count = ignored_count + #ignored
    if #videos > 0 then
      table.insert(plan, {
        folder = folder,
        folder_name = basename(folder),
        videos = videos
      })
    end
  end
  return plan, ignored_count, #folders, #root_videos
end

local function count_plan_videos(plan)
  local n = 0
  for _, entry in ipairs(plan or {}) do n = n + #(entry.videos or {}) end
  return n
end

local function open_import_window(on_finish)
  on_finish = on_finish or function() end

  if not gfx or not gfx.init or not ZP_UI then
    local workflow = choose_workflow()
    if not workflow then return nil end
    if workflow == MODE_PREPARE_EXISTING then
      on_finish({ workflow = workflow })
      return true
    end
    local root = select_root_folder()
    if not root or trim(root) == "" then return nil end
    local settings = get_settings()
    if not settings then return nil end
    local plan, ignored_count, direct_folder_count, root_video_count = prepare_plan(root)
    on_finish({
      workflow = workflow,
      root = root,
      settings = settings,
      plan = plan,
      ignored_count = ignored_count,
      direct_folder_count = direct_folder_count,
      root_video_count = root_video_count
    })
    return true
  end

  local state = {
    workflow = MODE_IMPORT_AND_PREPARE,
    root = reaper.GetExtState(EXT_SECTION, "last_root") or "",
    video_gap = DEFAULT_VIDEO_GAP,
    folder_gap = DEFAULT_FOLDER_GAP,
    copy_files = true,
    prepare_mixdown = false,
    plan = nil,
    ignored_count = 0,
    direct_folder_count = 0,
    root_video_count = 0,
    status = "Scegli una cartella madre con sottocartelle audio/video, oppure una cartella con file direttamente.",
    result = nil,
    last_mouse_down = false
  }

  if trim(state.root) ~= "" then
    state.plan, state.ignored_count, state.direct_folder_count, state.root_video_count = prepare_plan(state.root)
    state.status = string.format("Pronto: %d cartelle/sezioni con media, %d file.", #(state.plan or {}), count_plan_videos(state.plan or {}))
  end

  gfx.init("ZP Studio Suite v1.0.5 - Importa cartelle", 860, 620)
  gfx.setfont(1, "Arial", 15)

  local function refresh_plan()
    if trim(state.root) == "" then
      state.plan = nil
      state.ignored_count = 0
      state.direct_folder_count = 0
      state.root_video_count = 0
      state.status = "Scegli una cartella madre con sottocartelle audio/video, oppure una cartella con file direttamente."
      return
    end
    state.plan, state.ignored_count, state.direct_folder_count = prepare_plan(state.root)
    state.status = string.format("Pronto: %d cartelle con media, %d file.", #(state.plan or {}), count_plan_videos(state.plan or {}))
  end

  local function choose_folder()
    local folder = select_root_folder()
    if folder and trim(folder) ~= "" then
      state.root = trim(folder)
      reaper.SetExtState(EXT_SECTION, "last_root", state.root, true)
      refresh_plan()
    end
  end

  local function finish()
    if state.workflow == MODE_PREPARE_EXISTING then
      state.result = { workflow = MODE_PREPARE_EXISTING }
      return
    end
    if trim(state.root) == "" then
      state.status = "Scegli prima la cartella madre."
      return
    end
    if not state.plan then refresh_plan() end
    if #(state.plan or {}) == 0 then
      state.status = "Nessun file audio/video trovato nella cartella scelta o nelle sue sottocartelle dirette."
      return
    end
    state.result = {
      workflow = MODE_IMPORT_AND_PREPARE,
      root = state.root,
      settings = {
        video_gap = state.video_gap,
        folder_gap = state.folder_gap,
        copy_files = state.copy_files,
        prepare_mixdown = state.prepare_mixdown
      },
      plan = state.plan,
      ignored_count = state.ignored_count,
      direct_folder_count = state.direct_folder_count,
      root_video_count = state.root_video_count
    }
  end

  local function loop()
    local ch = gfx.getchar()
    if ch < 0 then gfx.quit() return end
    if ch == 27 then gfx.quit() return end

    local mouse_down = (gfx.mouse_cap & 1) == 1
    local clicked = mouse_down and not state.last_mouse_down
    state.last_mouse_down = mouse_down

    ZP_UI.fill_background()
    ZP_UI.draw_header({
      fallback_icon = draw_import_icon,
      title = "Importa cartelle",
      credit = "ZP Studio Suite v1.0.5 - Paolo Balestri",
      description = "Importa cartelle audio/video e crea sulla timeline marker e regioni ordinate.",
      title_size = 23,
      credit_size = 13,
      description_size = 15
    })

    ZP_UI.draw_help_button({ x = gfx.w - 54, y = 18, w = 34, h = 28 }, clicked, "zp-mixdown-render")

    local left = { x = 22, y = 104, w = math.floor(gfx.w * 0.55), h = gfx.h - 178 }
    local right = { x = left.x + left.w + 22, y = 104, w = gfx.w - left.x - left.w - 44, h = left.h }
    draw_panel(left)
    draw_panel(right)

    gfx.setfont(1, "Arial", 16)
    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x = left.x + 12
    gfx.y = left.y + 12
    gfx.drawstr("Importazione")

    local y = left.y + 42
    draw_button({ x = left.x + 12, y = y, w = 432, h = 36 }, "Importa cartelle", true, false, clicked, "tab")

    y = y + 58
    gfx.setfont(1, "Arial", 15)
    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x = left.x + 12
    gfx.y = y
    gfx.drawstr("Cartella madre")
    y = y + 24
    local has_root = trim(state.root) ~= ""
    local choose_label = has_root and "Cartella scelta" or "Scegli..."
    if draw_button({ x = left.x + 12, y = y, w = 150, h = 46 }, choose_label, has_root, true, clicked, "tab") then
      choose_folder()
    end
    draw_folder_choice_box({ x = left.x + 176, y = y, w = left.w - 188, h = 46 }, state.root, true)

    y = y + 78
    gfx.setfont(1, "Arial", 15)
    gfx.set(0.86, 0.82, 0.70, state.workflow == MODE_IMPORT_AND_PREPARE and 1 or 0.45)
    gfx.x = left.x + 12
    gfx.y = y
    gfx.drawstr("Spazi")
    y = y + 26
    if draw_button({ x = left.x + 12, y = y, w = 42, h = 32 }, "-", false, state.workflow == MODE_IMPORT_AND_PREPARE, clicked) then
      state.video_gap = math.max(0, state.video_gap - 1)
    end
    if draw_button({ x = left.x + 58, y = y, w = 110, h = 32 }, "File " .. tostring(state.video_gap) .. "s", true, state.workflow == MODE_IMPORT_AND_PREPARE, clicked, "tab") then
      local ok, value = reaper.GetUserInputs("Pausa tra file", 1, "Secondi:,extrawidth=240", tostring(state.video_gap))
      if ok then state.video_gap = math.max(0, tonumber(trim(value)) or state.video_gap) end
    end
    if draw_button({ x = left.x + 172, y = y, w = 42, h = 32 }, "+", false, state.workflow == MODE_IMPORT_AND_PREPARE, clicked) then
      state.video_gap = state.video_gap + 1
    end
    if draw_button({ x = left.x + 236, y = y, w = 42, h = 32 }, "-", false, state.workflow == MODE_IMPORT_AND_PREPARE, clicked) then
      state.folder_gap = math.max(0, state.folder_gap - 1)
    end
    if draw_button({ x = left.x + 282, y = y, w = 124, h = 32 }, "Cartelle " .. tostring(state.folder_gap) .. "s", true, state.workflow == MODE_IMPORT_AND_PREPARE, clicked, "tab") then
      local ok, value = reaper.GetUserInputs("Pausa tra cartelle", 1, "Secondi:,extrawidth=240", tostring(state.folder_gap))
      if ok then state.folder_gap = math.max(0, tonumber(trim(value)) or state.folder_gap) end
    end
    if draw_button({ x = left.x + 410, y = y, w = 42, h = 32 }, "+", false, state.workflow == MODE_IMPORT_AND_PREPARE, clicked) then
      state.folder_gap = state.folder_gap + 1
    end

    y = y + 58
    if draw_button({ x = left.x + 12, y = y, w = 210, h = 36 }, "Copia media nel progetto", state.copy_files, state.workflow == MODE_IMPORT_AND_PREPARE, clicked, "tab") then
      state.copy_files = not state.copy_files
    end
    gfx.set(0.62, 0.70, 0.78, 1)
    gfx.x = left.x + 234
    gfx.y = y + 8
    gfx.drawstr("Mixdown: usa Gestore Progetto")

    gfx.setfont(1, "Arial", 16)
    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x = right.x + 12
    gfx.y = right.y + 12
    gfx.drawstr("Anteprima")
    gfx.setfont(1, "Arial", 14)
    gfx.set(0.68, 0.74, 0.82, 1)
    gfx.x = right.x + 12
    gfx.y = right.y + 42
    do
      local plan = state.plan or {}
      gfx.drawstr(string.format("Sottocartelle dirette: %d", state.direct_folder_count or 0))
      gfx.x = right.x + 12
      gfx.y = right.y + 66
      gfx.drawstr(string.format("File nella cartella scelta: %d", state.root_video_count or 0))
      gfx.x = right.x + 12
      gfx.y = right.y + 90
      gfx.drawstr(string.format("Cartelle/sezioni con media: %d", #plan))
      gfx.x = right.x + 12
      gfx.y = right.y + 114
      gfx.drawstr(string.format("File da importare: %d", count_plan_videos(plan)))
      gfx.x = right.x + 12
      gfx.y = right.y + 138
      gfx.drawstr(string.format("File ignorati: %d", state.ignored_count or 0))
      local list_y = right.y + 174
      local row = 0
      local max_rows = math.max(1, math.floor((right.y + right.h - list_y - 10) / 20))
      local shown_entries = 0
      for i = 1, #plan do
        if row >= max_rows then break end
        local entry = plan[i]
        shown_entries = shown_entries + 1
        gfx.x = right.x + 12
        gfx.y = list_y + row * 20
        gfx.set(0.82, 0.88, 0.92, 1)
        gfx.drawstr(fit_text(string.format("%02d  %s  (%d file)", i, entry.folder_name, #(entry.videos or {})), right.w - 24))
        row = row + 1

        gfx.set(0.62, 0.76, 0.68, 1)
        for j = 1, #(entry.videos or {}) do
          if row >= max_rows then break end
          gfx.x = right.x + 28
          gfx.y = list_y + row * 20
          gfx.drawstr(fit_text("- " .. basename(entry.videos[j]), right.w - 44))
          row = row + 1
        end
      end
      if shown_entries < #plan or row >= max_rows then
        gfx.x = right.x + 12
        gfx.y = list_y + math.min(row, max_rows - 1) * 20
        gfx.set(0.68, 0.74, 0.82, 1)
        gfx.drawstr("... elenco ridotto, importera' tutti i file trovati")
      end
    end

    local footer_y = gfx.h - 58
    gfx.setfont(1, "Arial", 15)
    gfx.set(0.70, 0.86, 0.70, 1)
    gfx.x = 22
    gfx.y = footer_y - 24
    gfx.drawstr(fit_text(state.status, gfx.w - 44))

    if draw_button({ x = gfx.w - 338, y = footer_y, w = 150, h = 38 }, "Importa", false, true, clicked, "save") then
      finish()
    end
    if draw_button({ x = gfx.w - 174, y = footer_y, w = 150, h = 38 }, "Annulla", false, true, clicked) then
      gfx.quit()
      return
    end

    gfx.update()
    if state.result then
      local result = state.result
      gfx.quit()
      state.result = nil
      reaper.defer(function() on_finish(result) end)
      return
    end
    reaper.defer(loop)
  end

  reaper.defer(loop)
  return true
end

local function encode_region_map(entries)
  local lines = {}
  for _, entry in ipairs(entries) do
    table.insert(lines, table.concat({
      tostring(entry.region_index or ""),
      tostring(entry.region_start or 0),
      tostring(entry.region_end or 0),
      entry.folder_name or "",
      entry.source_folder or "",
      entry.source_file or "",
      entry.clean_region_name or "",
      entry.imported_file or "",
      entry.mixdown_folder or "",
      entry.output_file or ""
    }, "\t"))
  end
  return table.concat(lines, "\n")
end

local function split_tab_line(line)
  local fields = {}
  for field in (tostring(line or "") .. "\t"):gmatch("(.-)\t") do
    fields[#fields + 1] = field
  end
  return fields
end

local function current_region_by_index(region_index)
  if not region_index then return nil end
  local _, markers, regions = reaper.CountProjectMarkers(0)
  for i = 0, markers + regions - 1 do
    local ok, is_region, pos, rgn_end, name, idx = reaper.EnumProjectMarkers3(0, i)
    if ok and is_region and idx == region_index then
      return {
        region_index = idx,
        region_start = pos,
        region_end = rgn_end,
        clean_region_name = trim(name) ~= "" and trim(name) or ("Regione " .. tostring(idx))
      }
    end
  end
  return nil
end

local function decode_saved_region_map()
  local ok, value = reaper.GetProjExtState(0, EXT_SECTION, "region_map")
  if ok ~= 1 or trim(value) == "" then return {} end

  local entries = {}
  for line in (value .. "\n"):gmatch("(.-)\n") do
    if trim(line) ~= "" then
      local f = split_tab_line(line)
      local region_index = tonumber(f[1])
      local current = current_region_by_index(region_index)
      if current then
        entries[#entries + 1] = {
          region_index = region_index,
          region_start = current.region_start,
          region_end = current.region_end,
          folder_name = trim(f[4]) ~= "" and trim(f[4]) or "Mixdown",
          source_folder = f[5] or "",
          source_file = f[6] or "",
          clean_region_name = current.clean_region_name,
          imported_file = f[8] or "",
          mixdown_folder = f[9] or "",
          output_file = f[10] or ""
        }
      end
    end
  end
  return entries
end

local function infer_region_map_from_project()
  local markers = {}
  local regions = {}
  local _, marker_count, region_count = reaper.CountProjectMarkers(0)
  for i = 0, marker_count + region_count - 1 do
    local ok, is_region, pos, rgn_end, name, idx = reaper.EnumProjectMarkers3(0, i)
    if ok and is_region and rgn_end and rgn_end > pos then
      regions[#regions + 1] = { pos = pos, rgn_end = rgn_end, name = name, idx = idx }
    elseif ok and not is_region then
      markers[#markers + 1] = { pos = pos, name = trim(name) ~= "" and trim(name) or "Mixdown" }
    end
  end
  table.sort(markers, function(a, b) return a.pos < b.pos end)
  table.sort(regions, function(a, b) return a.pos < b.pos end)

  local entries = {}
  for _, region in ipairs(regions) do
    local folder_name = "Mixdown"
    for _, marker in ipairs(markers) do
      if marker.pos <= region.pos + EPS then
        folder_name = marker.name
      else
        break
      end
    end
    entries[#entries + 1] = {
      region_index = region.idx,
      region_start = region.pos,
      region_end = region.rgn_end,
      folder_name = folder_name,
      source_folder = "",
      source_file = "",
      clean_region_name = trim(region.name) ~= "" and trim(region.name) or ("Regione " .. tostring(region.idx or #entries + 1)),
      imported_file = "",
      mixdown_folder = "",
      output_file = ""
    }
  end
  return entries
end

local function prepare_mixdown_folders(root, plan, settings)
  if not settings.prepare_mixdown then return nil, nil, {} end

  local base_dir = project_dir() or root
  local mixdown_root = base_dir .. sep .. MIXDOWN_FOLDER_NAME
  local errors = {}

  if not ensure_directory(mixdown_root) then
    table.insert(errors, "Non riesco a creare la cartella Mixdown: " .. mixdown_root)
  end

  local folder_map = {}
  for _, folder_entry in ipairs(plan) do
    local folder_name = safe_filename(folder_entry.folder_name)
    local dst = mixdown_root .. sep .. folder_name
    if not ensure_directory(dst) then
      table.insert(errors, "Non riesco a creare sottocartella Mixdown: " .. dst)
    end
    folder_map[folder_entry.folder] = dst
  end

  return mixdown_root, folder_map, errors
end

local function show_plan_summary(root, plan, direct_folder_count, ignored_count)
  local video_count = 0
  local lines = {}
  for _, entry in ipairs(plan) do
    video_count = video_count + #entry.videos
    table.insert(lines, string.format("%s: %d file", entry.folder_name, #entry.videos))
  end
  local preview = table.concat(lines, "\n")
  if #preview > 1500 then preview = preview:sub(1, 1500) .. "\n..." end
  local message = string.format(
    "Cartella scelta:\n%s\n\nSottocartelle dirette: %d\nCartelle/sezioni con media: %d\nFile da importare: %d\nFile non audio/video ignorati: %d\n\n%s\n\nProcedere con la creazione della timeline?",
    root,
    direct_folder_count,
    #plan,
    video_count,
    ignored_count,
    preview
  )
  return reaper.ShowMessageBox(message, "ZP Studio Suite - Fase 2", 4) == 6
end

local function show_report(report)
  local message = string.format(
    "Importa cartelle completato.\n\nCartelle analizzate: %d\nCartelle importate: %d\nFile importati: %d\nMarker creati: %d\nRegioni create: %d\nFile ignorati: %d\nErrori: %d\n\nPer nominare, organizzare e preparare il render usa Gestore Progetto.",
    report.direct_folders or 0,
    report.folders or 0,
    report.videos or 0,
    report.markers or 0,
    report.regions or 0,
    report.ignored or 0,
    #report.errors
  )
  if #report.errors > 0 then
    message = message .. "\n\nPrimi errori:\n"
    for i = 1, math.min(8, #report.errors) do
      message = message .. "- " .. report.errors[i] .. "\n"
    end
  end
  reaper.ShowMessageBox(message, "ZP Studio Suite", 0)
end

local function show_prepare_report(report)
  local message = string.format(
    "Preparazione Mixdown completata.\n\nRegioni mappate: %d\nCartelle Mixdown: %d\nErrori: %d\n\nMappa mixdown aggiornata nel progetto.",
    report.regions or 0,
    report.mixdown_folders or 0,
    #report.errors
  )
  if report.mixdown_root and report.mixdown_root ~= "" then
    message = message .. "\n\nMixdown:\n" .. report.mixdown_root
  end
  if #report.errors > 0 then
    message = message .. "\n\nPrimi errori:\n"
    for i = 1, math.min(8, #report.errors) do
      message = message .. "- " .. report.errors[i] .. "\n"
    end
  end
  reaper.ShowMessageBox(message, "ZP Studio Suite", 0)
end

local function prepare_mixdown_for_existing_project()
  local _, project_folder, err = ensure_saved_project()
  if not project_folder then
    reaper.ShowMessageBox(err or "Progetto non salvato.", "ZP Studio Suite", 0)
    return
  end

  -- In "Prepara progetto aperto" la timeline corrente e' la verita':
  -- marker = cartelle, regioni = file. La mappa salvata viene rigenerata,
  -- cosi' anche file aggiunti o spostati a mano entrano nel Mixdown.
  local entries = infer_region_map_from_project()
  local source = "marker e regioni del progetto"
  if #entries == 0 then
    entries = decode_saved_region_map()
    source = "mappa salvata"
  end
  if #entries == 0 then
    reaper.ShowMessageBox("Non trovo regioni da preparare per il Mixdown.", "ZP Studio Suite", 0)
    return
  end

  local choice = reaper.ShowMessageBox(
    string.format(
      "Preparo Mixdown dal progetto aperto.\n\nFonte: %s\nRegioni trovate: %d\n\nNon importo nulla e non modifico la timeline.\nProcedere?",
      source,
      #entries
    ),
    "ZP Studio Suite - Prepara Mixdown",
    4
  )
  if choice ~= 6 then return end

  local mixdown_root = project_folder .. sep .. MIXDOWN_FOLDER_NAME
  local report = { regions = #entries, mixdown_folders = 0, mixdown_root = mixdown_root, errors = {} }
  if not ensure_directory(mixdown_root) then
    table.insert(report.errors, "Non riesco a creare la cartella Mixdown: " .. mixdown_root)
  end

  local folder_paths = {}
  local used_output_paths = {}
  for _, entry in ipairs(entries) do
    local folder_key = trim(entry.source_folder) ~= "" and entry.source_folder or entry.folder_name
    local dst = folder_paths[folder_key]
    if not dst then
      dst = mixdown_root .. sep .. safe_filename(entry.folder_name)
      folder_paths[folder_key] = dst
      report.mixdown_folders = report.mixdown_folders + 1
      if not ensure_directory(dst) then
        table.insert(report.errors, "Non riesco a creare sottocartella Mixdown: " .. dst)
      end
    end
    entry.mixdown_folder = dst
    entry.output_file = unique_output_path(dst, entry.clean_region_name, ".wav", used_output_paths)
  end

  reaper.SetProjExtState(0, EXT_SECTION, "mixdown_root", mixdown_root)
  reaper.SetProjExtState(0, EXT_SECTION, "region_map", encode_region_map(entries))
  show_prepare_report(report)
end

local function import_plan(root, plan, settings, direct_folder_count, ignored_count)
  local project_folder = nil
  if settings.copy_files then
    local _, folder, err = ensure_saved_project()
    if not folder then
      reaper.ShowMessageBox(err or "Progetto non salvato.", "ZP Studio Suite", 0)
      return
    end
    project_folder = folder
  end

  local media_dir = nil
  if settings.copy_files then
    media_dir = project_folder .. sep .. "Media"
    ensure_directory(media_dir)
  end

  local mixdown_root, mixdown_folder_map, mixdown_errors = nil, nil, {}

  local report = {
    direct_folders = direct_folder_count,
    folders = 0,
    videos = 0,
    markers = 0,
    regions = 0,
    mixdown_folders = 0,
    mixdown_root = mixdown_root or "",
    ignored = ignored_count,
    errors = {}
  }
  for _, err in ipairs(mixdown_errors or {}) do table.insert(report.errors, err) end
  if mixdown_folder_map then
    for _ in pairs(mixdown_folder_map) do report.mixdown_folders = report.mixdown_folders + 1 end
  end
  local region_map = {}
  local used_output_paths = {}
  local imported_items = {}
  local copy_state = {}
  local video_track = get_or_create_video_track()
  local cursor = reaper.GetCursorPosition()

  reaper.PreventUIRefresh(1)
  reaper.Undo_BeginBlock()

  for _, folder_entry in ipairs(plan) do
    local folder_start = cursor
    create_folder_marker(folder_entry.folder_name, folder_start)
    report.markers = report.markers + 1
    report.folders = report.folders + 1

    for video_index, source_video in ipairs(folder_entry.videos) do
      local import_video = source_video
      if settings.copy_files and media_dir then
        local dst_dir = media_dir .. sep .. safe_filename(folder_entry.folder_name)
        local copied_video, copy_err = resolve_project_copy(source_video, project_folder, dst_dir, copy_state)
        if copied_video then
          import_video = copied_video
        else
          table.insert(report.errors, copy_err or ("Copia non riuscita: " .. source_video))
        end
      end

      local length = video_file_length(import_video)
      if not length or length <= 0 then
        table.insert(report.errors, "Durata non valida: " .. source_video)
      else
        cursor = next_free_video_position(video_track, cursor, length, 0)
        local item, err = add_video_item(video_track, import_video, cursor)
        if item then
          imported_items[#imported_items + 1] = item
          local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
          local start_pos = cursor
          local end_pos = start_pos + item_len
          local region_name = basename_without_ext(source_video)
          local region_index = create_item_region(region_name, start_pos, end_pos)
          local output_folder = mixdown_folder_map and mixdown_folder_map[folder_entry.folder] or ""
          local output_file = ""
          if output_folder ~= "" then
            output_file = unique_output_path(output_folder, region_name, ".wav", used_output_paths)
          end
          report.videos = report.videos + 1
          if region_index then report.regions = report.regions + 1 end
          table.insert(region_map, {
            region_index = region_index,
            region_start = start_pos,
            region_end = end_pos,
            folder_name = folder_entry.folder_name,
            source_folder = folder_entry.folder,
            source_file = source_video,
            clean_region_name = region_name,
            imported_file = import_video,
            mixdown_folder = output_folder,
            output_file = output_file
          })
          cursor = end_pos
          if video_index < #folder_entry.videos then
            cursor = cursor + math.max(0, settings.video_gap or 0)
          end
        else
          table.insert(report.errors, err or ("Import non riuscito: " .. source_video))
        end
      end
    end
    cursor = cursor + math.max(0, settings.folder_gap or 0)
  end

  reaper.SetProjExtState(0, EXT_SECTION, "root_folder", root)
  reaper.SetExtState(EXT_SECTION, "last_root", root, true)

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  build_peaks_after_import(PEAK_BUILD_MODE, imported_items)
  reaper.Undo_EndBlock("ZP Studio Suite: importa cartelle per mixdown", -1)

  local video_state = reaper.GetToggleCommandState(50125)
  if video_state == 0 then reaper.Main_OnCommand(50125, 0) end
  show_report(report)
end

local function main()
  open_import_window(function(options)
    if not options then return end

    local plan = options.plan or {}
    if #plan == 0 then
      reaper.ShowMessageBox("Nessun file audio/video trovato nella cartella scelta o nelle sue sottocartelle dirette:\n" .. tostring(options.root or ""), "ZP Studio Suite", 0)
      return
    end

    import_plan(
      options.root,
      plan,
      options.settings,
      options.direct_folder_count or 0,
      options.ignored_count or 0
    )
  end)
end

main()
