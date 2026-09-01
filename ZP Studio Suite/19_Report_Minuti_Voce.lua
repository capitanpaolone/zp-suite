-- @noindex

-- REPORT MINUTI VOCE
-- Linea: ZP Paolo Balestri
-- Suite: ZP Studio Suite for REAPER v1.0.5
-- Distribuzione gratuita.
-- Calcola minuti reali e minuti arrotondati in eccesso da regioni o item audio.

local SCRIPT_TITLE = "ZP Studio Suite v1.0.5 - Report Minuti Voce"
local PROJECT_VIEWER_SECTION = "ZP_RythmoBand_ProjectViewer"
local ROW_H = 30
local HEADER_H = 196
local FOOTER_H = 108
local CALC_ICON_NAME = "toolbar_misc_calculate_numeric.png"
local WORD_RATE_LOW = 120
local WORD_RATE_HIGH = 130
local REPORT_FILE_PREFIX = "Conteggi progetto"
local REPORT_FOLDER = "Conteggi"

local function script_dir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*)[/\\]") or "."
end

local ZP_UI = dofile(script_dir() .. "/ZP_UI.lua")

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
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
  return (out ~= "" and out:gsub("%s+$", "") or "") .. suffix
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function find_toolbar_icon(name)
  if not reaper.GetResourcePath then return nil end
  local base = reaper.GetResourcePath() .. "/Data/toolbar_icons/"
  local candidates = {
    base .. name,
    base .. "150/" .. name,
    base .. "200/" .. name,
    base .. "Default Green/RT_DefaultGreen_" .. name,
    base .. "Default Green/150/RT_DefaultGreen_" .. name,
    base .. "Grayscale/RT_Grayscale_" .. name,
    base .. "Grayscale/150/RT_Grayscale_" .. name
  }
  for _, path in ipairs(candidates) do
    if file_exists(path) then return path end
  end
  return nil
end

local function format_time(seconds)
  seconds = math.max(0, seconds or 0)
  local minutes = math.floor(seconds / 60)
  local secs = math.floor(seconds - minutes * 60 + 0.5)
  if secs >= 60 then
    minutes = minutes + 1
    secs = secs - 60
  end
  return string.format("%d:%02d", minutes, secs)
end

local function billed_minutes(seconds)
  if not seconds or seconds <= 0 then return 0 end
  local minutes = math.floor(seconds / 60)
  local remainder = seconds - (minutes * 60)
  if remainder > 30 then minutes = minutes + 1 end
  return math.max(1, minutes)
end

local function estimated_words(seconds, rate)
  if not seconds or seconds <= 0 then return 0 end
  return math.ceil((seconds / 60) * rate)
end

local function basename(path)
  return tostring(path or ""):match("([^/\\]+)$") or tostring(path or "")
end

local function dirname(path)
  return tostring(path or ""):match("^(.*)[/\\][^/\\]+$") or ""
end

local function strip_ext(name)
  return tostring(name or ""):gsub("%.[Rr][Pp][Pp]%-?[Bb]?[Aa]?[Kk]?$", ""):gsub("%.[^%.]+$", "")
end

local function safe_filename(name)
  name = trim(name)
  if name == "" then name = "Progetto_non_salvato" end
  name = name:gsub("[/\\:*?\"<>|]", "_"):gsub("%s+", " ")
  return name
end

local function project_name()
  local _, projfn = reaper.EnumProjects(-1, "")
  local name = strip_ext(basename(projfn or ""))
  if trim(name) == "" then name = "Progetto non salvato" end
  return name
end

local function project_report_dir()
  local dir = ""
  local _, projfn = reaper.EnumProjects(-1, "")
  dir = dirname(projfn or "")
  if trim(dir) == "" and reaper.GetProjectPath then dir = reaper.GetProjectPath("") or "" end
  if trim(dir) == "" and reaper.GetResourcePath then dir = reaper.GetResourcePath() or "" end
  if trim(dir) == "" then return nil end
  local report_dir = dir .. "/" .. REPORT_FOLDER
  if reaper.RecursiveCreateDirectory then
    reaper.RecursiveCreateDirectory(report_dir, 0)
  end
  return report_dir
end

local function unique_path(path)
  if not file_exists(path) then return path end
  local base, ext = tostring(path or ""):match("^(.*)%.([^%.]+)$")
  if not base then return path .. " - " .. os.date("%Y%m%d-%H%M%S") end
  local stamp = os.date("%Y%m%d-%H%M%S")
  local candidate = base .. " - " .. stamp .. "." .. ext
  if not file_exists(candidate) then return candidate end
  local n = 2
  repeat
    candidate = base .. " - " .. stamp .. "-" .. tostring(n) .. "." .. ext
    n = n + 1
  until not file_exists(candidate)
  return candidate
end

local function project_report_path(ext, suffix, make_unique)
  ext = ext or "txt"
  local dir = project_report_dir()
  if not dir then return nil end
  local name = REPORT_FILE_PREFIX .. " - " .. safe_filename(project_name())
  suffix = safe_filename(trim(suffix or ""))
  if suffix ~= "" then name = name .. " - " .. suffix end
  local path = dir .. "/" .. name .. "." .. ext
  return make_unique and unique_path(path) or path
end

local function preview_report_destination()
  local path = project_report_path("html", "", false)
  return path and dirname(path) or "(cartella progetto non disponibile)"
end

local function source_path_from_item(item)
  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then return "" end
  local source = reaper.GetMediaItemTake_Source(take)
  if not source then return "" end
  return reaper.GetMediaSourceFileName(source, "")
end

local function ext_lower(path)
  return (path:match("%.([^%.\\/]+)$") or ""):lower()
end

local function is_audio_item(item)
  if not item then return false end
  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then return false end
  local source = reaper.GetMediaItemTake_Source(take)
  if not source then return false end
  local source_type = ""
  if reaper.GetMediaSourceType then source_type = reaper.GetMediaSourceType(source, "") or "" end
  source_type = source_type:upper()
  if source_type:find("MIDI", 1, true) then return false end
  local path = reaper.GetMediaSourceFileName(source, "") or ""
  local ext = ext_lower(path)
  if ext == "" then return false end
  if ext == "mp4" or ext == "mov" or ext == "m4v" or ext == "avi" or ext == "mkv" then return false end
  return true
end

local function is_media_file_item(item)
  if not item then return false end
  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then return false end
  local source = reaper.GetMediaItemTake_Source(take)
  if not source then return false end
  local path = reaper.GetMediaSourceFileName(source, "") or ""
  return trim(path) ~= ""
end

local function item_overlap_seconds(item, ranges)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = pos + len
  if not ranges or #ranges == 0 then return math.max(0, len or 0) end
  local total = 0
  for _, range in ipairs(ranges) do
    local a = math.max(pos, range.pos)
    local b = math.min(item_end, range.end_pos)
    if b > a then total = total + (b - a) end
  end
  return total
end

local function track_name(track, fallback)
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  name = trim(name)
  if name == "" then name = fallback or "Traccia" end
  return name
end

local function collect_regions()
  local out = {}
  local _, markers, regions = reaper.CountProjectMarkers(0)
  for i = 0, markers + regions - 1 do
    local ok, is_region, pos, rgn_end, name, idx = reaper.EnumProjectMarkers3(0, i)
    if ok and is_region and rgn_end and rgn_end > pos then
      table.insert(out, {
        idx = idx,
        name = trim(name) ~= "" and trim(name) or ("Regione " .. tostring(idx or #out + 1)),
        pos = pos,
        end_pos = rgn_end,
        seconds = rgn_end - pos
      })
    end
  end
  table.sort(out, function(a, b) return a.pos < b.pos end)
  return out
end

local function listview_region_id(list, row_index)
  for col = 0, 4 do
    local text = reaper.JS_ListView_GetItemText(list, row_index, col) or ""
    local region_id = tonumber(text:match("^%s*R(%d+)%s*$"))
    if region_id then return region_id end
  end
  return nil
end

local function selected_regions_from_region_manager()
  if not (reaper.JS_Window_Find and reaper.JS_Window_FindChildByID and
    reaper.JS_ListView_GetItemCount and reaper.JS_ListView_GetItemText and
    reaper.JS_ListView_GetItemState) then
    return {}
  end
  local title = reaper.JS_Localize and reaper.JS_Localize("Region/Marker Manager", "common") or "Region/Marker Manager"
  local manager = reaper.JS_Window_Find(title, true)
  if not manager then return {} end
  local list = reaper.JS_Window_FindChildByID(manager, 1071)
  if not list then return {} end
  local by_idx = {}
  for _, region in ipairs(collect_regions()) do by_idx[region.idx] = region end
  local selected = {}
  local item_count = reaper.JS_ListView_GetItemCount(list)
  for i = 0, item_count - 1 do
    local state = reaper.JS_ListView_GetItemState(list, i) or 0
    if (state & 0x2) == 0x2 then
      local region_id = listview_region_id(list, i)
      local region = region_id and by_idx[region_id] or nil
      if region then selected[#selected + 1] = region end
    end
  end
  table.sort(selected, function(a, b) return a.pos < b.pos end)
  return selected
end

local function marker_name_for_pos(pos)
  local current = nil
  local _, markers, region_count = reaper.CountProjectMarkers(0)
  for i = 0, markers + region_count - 1 do
    local ok, is_region, marker_pos, _, name, idx = reaper.EnumProjectMarkers3(0, i)
    if ok and not is_region and marker_pos <= (pos or 0) + 0.0001 then
      if not current or marker_pos >= current.pos then current = { pos = marker_pos, name = trim(name or ""), idx = idx } end
    end
  end
  if not current then return "" end
  if current.name ~= "" then return current.name end
  return "Marker " .. tostring(current.idx or "")
end

local function section_name_for_regions(regions)
  if not regions or #regions == 0 then return "" end
  local first_pos = regions[1].pos or 0
  local marker_name = marker_name_for_pos(first_pos)
  if marker_name ~= "" then return marker_name end
  if #regions == 1 then return regions[1].name or "Regione" end
  return "Regioni selezionate"
end

local function selected_regions_from_project_viewer()
  local ok, value = reaper.GetProjExtState(0, PROJECT_VIEWER_SECTION, "render_selected_regions")
  if ok ~= 1 or trim(value) == "" then return {} end
  local selected = {}
  for line in (value .. "\n"):gmatch("(.-)\n") do
    local idx, pos, rgn_end, name = line:match("^(.-)\t(.-)\t(.-)\t(.*)$")
    pos, rgn_end = tonumber(pos), tonumber(rgn_end)
    if pos and rgn_end and rgn_end > pos then
      table.insert(selected, {
        idx = tonumber(idx),
        name = trim(name) ~= "" and trim(name) or ("Regione " .. tostring(idx or #selected + 1)),
        pos = pos,
        end_pos = rgn_end,
        seconds = rgn_end - pos
      })
    end
  end
  table.sort(selected, function(a, b) return a.pos < b.pos end)
  return selected
end

local function region_under_cursor()
  local cursor = reaper.GetCursorPosition()
  for _, region in ipairs(collect_regions()) do
    if cursor >= region.pos and cursor <= region.end_pos then return { region } end
  end
  return {}
end

local function collect_selected_tracks()
  local out = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    table.insert(out, reaper.GetSelectedTrack(0, i))
  end
  return out
end

local function collect_selected_audio_items()
  local out = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    if is_audio_item(item) then table.insert(out, item) end
  end
  return out
end

local function track_has_media_file_items(track)
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    if is_media_file_item(reaper.GetTrackMediaItem(track, i)) then return true end
  end
  return false
end

local function track_has_audio_items(track)
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    if is_audio_item(reaper.GetTrackMediaItem(track, i)) then return true end
  end
  return false
end

local function collect_audio_tracks()
  local out = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    if track_has_audio_items(track) then table.insert(out, track) end
  end
  return out
end

local function collect_media_file_tracks()
  local out = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    if track_has_media_file_items(track) then table.insert(out, track) end
  end
  return out
end

local function summarize_tracks(tracks, ranges, item_filter)
  item_filter = item_filter or is_audio_item
  local rows = {}
  local total_seconds, total_billed, total_items = 0, 0, 0
  for order, track in ipairs(tracks) do
    local seconds, items = 0, 0
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      if item_filter(item) then
        local overlap = item_overlap_seconds(item, ranges)
        if overlap > 0 then
          seconds = seconds + overlap
          items = items + 1
        end
      end
    end
    if seconds > 0 then
      local bill = billed_minutes(seconds)
      table.insert(rows, {
        kind = "track",
        name = track_name(track, "Traccia " .. tostring(order)),
        seconds = seconds,
        billed = bill,
        items = items
      })
      total_seconds = total_seconds + seconds
      total_billed = total_billed + bill
      total_items = total_items + items
    end
  end
  return rows, total_seconds, total_billed, total_items
end

local function summarize_selected_items(items)
  local rows, by_track = {}, {}
  local total_seconds, total_billed, total_items = 0, 0, 0
  for _, item in ipairs(items) do
    local track = reaper.GetMediaItem_Track(item)
    if track then
      local key = tostring(track)
      local row = by_track[key]
      if not row then
        row = {
          kind = "items",
          name = track_name(track, "Traccia"),
          seconds = 0,
          billed = 0,
          items = 0
        }
        by_track[key] = row
        table.insert(rows, row)
      end
      local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      if len and len > 0 then
        row.seconds = row.seconds + len
        row.items = row.items + 1
        total_seconds = total_seconds + len
        total_items = total_items + 1
      end
    end
  end
  for _, row in ipairs(rows) do
    row.billed = billed_minutes(row.seconds)
    total_billed = total_billed + row.billed
  end
  return rows, total_seconds, total_billed, total_items
end

local function summarize_regions(regions)
  local rows = {}
  local total_seconds, total_billed = 0, 0
  for _, region in ipairs(regions) do
    local seconds = region.seconds or math.max(0, (region.end_pos or 0) - (region.pos or 0))
    local bill = billed_minutes(seconds)
    table.insert(rows, {
      kind = "region",
      name = region.name,
      seconds = seconds,
      billed = bill,
      items = 0
    })
    total_seconds = total_seconds + seconds
    total_billed = total_billed + bill
  end
  return rows, total_seconds, total_billed, 0
end

local function count_key(parts)
  return table.concat(parts, "|"):gsub("[\r\n,]", " "):gsub("%s+", " ")
end

local function source_display_name(path, fallback)
  local name = basename(path or "")
  if trim(name) == "" then name = fallback or "File senza nome" end
  return name
end

local function item_detail_row(item, mode_label, scope_label, item_label)
  if not item then return nil end
  local track = reaper.GetMediaItem_Track(item)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION") or 0
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
  if len <= 0 then return nil end
  local path = source_path_from_item(item)
  local track_label = track and track_name(track, "Traccia") or ""
  local name = source_display_name(path, track_label)
  local id = count_key({ project_name(), path ~= "" and path or name, string.format("%.3f", pos), string.format("%.3f", len) })
  return {
    id = id,
    project = project_name(),
    mode = mode_label or "",
    scope = scope_label or "",
    marker = marker_name_for_pos(pos),
    track = track_label,
    name = name,
    path = path,
    kind = item_label or "Item audio",
    start_pos = pos,
    end_pos = pos + len,
    seconds = math.max(0, len),
    billed = billed_minutes(len),
    words_low = estimated_words(len, WORD_RATE_LOW),
    words_high = estimated_words(len, WORD_RATE_HIGH)
  }
end

local function detail_rows_from_items(items, mode_label, scope_label, item_label)
  local out = {}
  for _, item in ipairs(items or {}) do
    local row = item_detail_row(item, mode_label, scope_label, item_label)
    if row then table.insert(out, row) end
  end
  return out
end

local function detail_rows_from_tracks(tracks, mode_label, scope_label, item_filter, item_label)
  local out = {}
  item_filter = item_filter or is_audio_item
  for _, track in ipairs(tracks or {}) do
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      if item_filter(item) then
        local row = item_detail_row(item, mode_label, scope_label, item_label)
        if row then table.insert(out, row) end
      end
    end
  end
  return out
end

local function detail_rows_from_regions(regions, mode_label, scope_label)
  local out = {}
  for _, region in ipairs(regions or {}) do
    local seconds = region.seconds or math.max(0, (region.end_pos or 0) - (region.pos or 0))
    local id = count_key({ project_name(), "REGION", tostring(region.idx or region.name or ""), string.format("%.3f", region.pos or 0), string.format("%.3f", region.end_pos or 0) })
    table.insert(out, {
      id = id,
      project = project_name(),
      mode = mode_label or "",
      scope = scope_label or "",
      marker = marker_name_for_pos(region.pos or 0),
      track = "",
      name = region.name or ("Regione " .. tostring(region.idx or #out + 1)),
      path = "",
      kind = "Regione",
      start_pos = region.pos or 0,
      end_pos = region.end_pos or 0,
      seconds = seconds,
      billed = billed_minutes(seconds),
      words_low = estimated_words(seconds, WORD_RATE_LOW),
      words_high = estimated_words(seconds, WORD_RATE_HIGH)
    })
  end
  return out
end

local function set_clipboard(text)
  if reaper.CF_SetClipboard then
    local ok = pcall(reaper.CF_SetClipboard, text)
    if ok then return true end
  end
  reaper.ShowConsoleMsg(text .. "\n")
  return false
end

local function draw_calculator_fallback(x, y, size)
  gfx.set(0.10, 0.42, 0.48, 1)
  gfx.rect(x, y, size, size, true)
  gfx.set(0.05, 0.18, 0.22, 1)
  gfx.rect(x, y, size, size, false)
  gfx.set(0.92, 0.88, 0.70, 1)
  gfx.rect(x + 5, y + 5, size - 10, 8, true)
  gfx.set(0.03, 0.10, 0.12, 1)
  local key = math.max(3, math.floor(size / 6))
  local gap = math.max(2, math.floor(size / 12))
  local start_x = x + 6
  local start_y = y + 18
  for row = 0, 2 do
    for col = 0, 2 do
      gfx.rect(start_x + col * (key + gap), start_y + row * (key + gap), key, key, true)
    end
  end
end

local function build_report_text(mode_label, rows, total_seconds, total_billed, total_items, item_label)
  item_label = item_label or "Item audio"
  local total_rounded_once = billed_minutes(total_seconds)
  local lines = {
    "ZP Studio Suite v1.0.5 - Report Minuti Voce",
    "Progetto: " .. project_name(),
    "Modo: " .. mode_label,
    ""
  }
  for _, row in ipairs(rows) do
    local suffix = row.items and row.items > 0 and (" | " .. item_label:lower() .. ": " .. tostring(row.items)) or ""
    table.insert(lines, string.format(
      "%s | reale %s | fatturato %d min | parole stimate %d/min: %d | %d/min: %d%s",
      row.name,
      format_time(row.seconds),
      row.billed,
      WORD_RATE_LOW,
      estimated_words(row.seconds, WORD_RATE_LOW),
      WORD_RATE_HIGH,
      estimated_words(row.seconds, WORD_RATE_HIGH),
      suffix
    ))
  end
  table.insert(lines, "")
  table.insert(lines, string.format("Totale reale: %s", format_time(total_seconds)))
  table.insert(lines, string.format("Totale reale arrotondato: %d min", total_rounded_once))
  table.insert(lines, string.format("Parole stimate %d/min: %d", WORD_RATE_LOW, estimated_words(total_seconds, WORD_RATE_LOW)))
  table.insert(lines, string.format("Parole stimate %d/min: %d", WORD_RATE_HIGH, estimated_words(total_seconds, WORD_RATE_HIGH)))
  if total_items and total_items > 0 then table.insert(lines, string.format("%s conteggiati: %d", item_label, total_items)) end
  return table.concat(lines, "\n")
end

local function report_preview_lines(text, start_line, max_lines, max_w)
  local lines = {}
  start_line = math.max(1, start_line or 1)
  local n = 0
  for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    n = n + 1
    if n >= start_line then
      table.insert(lines, fit_text(line, max_w))
      if #lines >= max_lines then break end
    end
  end
  return lines
end

local function count_report_lines(text)
  local n = 0
  for _ in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do n = n + 1 end
  return n
end

local function write_text_file(path, text)
  local f, err = io.open(path, "w")
  if not f then return nil, err or "Impossibile scrivere il file." end
  f:write(text)
  f:write("\n")
  f:close()
  return true
end

local function encode_data_block(rows)
  local lines = {}
  table.insert(lines, "<!-- ZP_DATA_START")
  for _, row in ipairs(rows) do
    local cartella = (row.cartella or ""):gsub("[\r\n]", " "):gsub("|||", "___")
    local nome = (row.nome or ""):gsub("[\r\n]", " "):gsub("|||", "___")
    local data = (row.data or ""):gsub("[\r\n]", " "):gsub("|||", "___")
    table.insert(lines, string.format("%s|||%s|||%s|||%s|||%s|||%s|||%s",
      row.id, cartella, nome, tostring(row.durata_sec or 0), row.durata_str or "", tostring(row.minuti or 0), data))
  end
  table.insert(lines, "ZP_DATA_END -->")
  return table.concat(lines, "\n")
end

local function parse_data_block(html_path)
  local rows = {}
  local keys = {}
  local f = io.open(html_path, "r")
  if not f then return rows, keys, false end
  local content = f:read("*a")
  f:close()
  
  local data_block = content:match("<!%-%- ZP_DATA_START%s+(.-)%s+ZP_DATA_END %-%->")
  if data_block then
    for line in data_block:gmatch("([^\r\n]+)") do
      local id, cartella, nome, d_sec, d_str, min, data = line:match("^(.-)|||(.-)|||(.-)|||(.-)|||(.-)|||(.-)|||(.*)$")
      if id then
        keys[id] = true
        table.insert(rows, {
          id = id,
          cartella = cartella,
          nome = nome,
          durata_sec = tonumber(d_sec) or 0,
          durata_str = d_str,
          minuti = tonumber(min) or 0,
          data = data
        })
      end
    end
  end
  return rows, keys, true
end

local function html_escape(value)
  value = tostring(value == nil and "" or value)
  value = value:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
  return value
end

local function build_html_report(all_rows, html_path)
  local total_seconds, total_billed_sum_rows, total_items = 0, 0, 0
  local blocks_by_name = {}
  local block_order = {}
  
  for _, row in ipairs(all_rows) do
    local cartella = trim(row.cartella or "")
    if cartella == "" then cartella = "Senza nome" end
    
    local block = blocks_by_name[cartella]
    if not block then
      block = {
        name = cartella,
        rows = {},
        total_seconds = 0,
        total_billed = 0
      }
      blocks_by_name[cartella] = block
      table.insert(block_order, block)
    end
    table.insert(block.rows, row)
    block.total_seconds = block.total_seconds + (row.durata_sec or 0)
    block.total_billed = block.total_billed + (row.minuti or 0)
    
    total_seconds = total_seconds + (row.durata_sec or 0)
    total_billed_sum_rows = total_billed_sum_rows + (row.minuti or 0)
    total_items = total_items + 1
  end
  
  local total_billed_once = billed_minutes(total_seconds)
  
  local last_date = os.date("%d/%m/%Y %H:%M:%S")
  if #all_rows > 0 and all_rows[#all_rows].data then
    last_date = all_rows[#all_rows].data
  end
  
  local out = {
    '<!doctype html><html><head><meta charset="utf-8">',
    '<title>Report Minuti Voce - ' .. html_escape(project_name()) .. '</title>',
    '<style>',
    'body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; margin: 40px auto; max-width: 900px; color: #333; line-height: 1.6; }',
    'h1 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 10px; margin-bottom: 20px; }',
    '.header-info { display: flex; justify-content: space-between; margin-bottom: 30px; font-size: 1.1em; color: #555; }',
    'table { width: 100%; border-collapse: collapse; margin-bottom: 30px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }',
    'th, td { padding: 12px 15px; text-align: left; border-bottom: 1px solid #ddd; }',
    'th { background-color: #f8f9fa; font-weight: 600; color: #2c3e50; }',
    'tr:hover { background-color: #f5f5f5; }',
    '.subtotal { background-color: #e8f4f8; font-weight: bold; }',
    '.subtotal td { border-top: 2px solid #bce8f1; border-bottom: 2px solid #bce8f1; }',
    '.footer-summary { background-color: #2c3e50; color: white; padding: 20px; border-radius: 5px; margin-top: 30px; }',
    '.footer-summary h2 { margin-top: 0; font-size: 1.4em; border-bottom: 1px solid #455a64; padding-bottom: 10px; }',
    '.footer-stats { display: flex; justify-content: space-between; flex-wrap: wrap; }',
    '.stat-box { flex: 1; min-width: 200px; margin: 10px 0; }',
    '.stat-value { font-size: 1.5em; font-weight: bold; color: #3498db; }',
    '</style>',
    '</head><body>',
    '<h1>Report Minuti Voce</h1>',
    '<div class="header-info">',
    '  <div><strong>Progetto:</strong> ' .. html_escape(project_name()) .. '</div>',
    '  <div><strong>Data:</strong> ' .. html_escape(last_date) .. '</div>',
    '</div>',
    '<table><thead><tr>',
    '  <th>Cartella / Selezione</th>',
    '  <th>File conteggiato</th>',
    '  <th>Durata file</th>',
    '  <th>Minuti conteggiati</th>',
    '  <th>Data conteggio</th>',
    '</tr></thead><tbody>'
  }
  
  for _, block in ipairs(block_order) do
    for _, row in ipairs(block.rows) do
      table.insert(out, '<tr>')
      table.insert(out, '  <td>' .. html_escape(row.cartella) .. '</td>')
      table.insert(out, '  <td>' .. html_escape(row.nome) .. '</td>')
      table.insert(out, '  <td>' .. html_escape(row.durata_str) .. '</td>')
      table.insert(out, '  <td>' .. tostring(row.minuti) .. '</td>')
      table.insert(out, '  <td>' .. html_escape(row.data) .. '</td>')
      table.insert(out, '</tr>')
    end
    
    table.insert(out, '<tr class="subtotal">')
    table.insert(out, '  <td colspan="2">Totale ' .. html_escape(block.name) .. '</td>')
    local block_billed_once = billed_minutes(block.total_seconds)
    table.insert(out, '  <td>' .. html_escape(format_time(block.total_seconds)) .. '</td>')
    table.insert(out, '  <td>' .. tostring(block_billed_once) .. ' min. conteggiabili</td>')
    table.insert(out, '  <td></td>')
    table.insert(out, '</tr>')
  end
  
  table.insert(out, '</tbody></table>')
  
  table.insert(out, '<div class="footer-summary">')
  table.insert(out, '  <h2>Riepilogo Totale</h2>')
  table.insert(out, '  <div class="footer-stats">')
  table.insert(out, '    <div class="stat-box">Totale reale:<br><span class="stat-value">' .. html_escape(format_time(total_seconds)) .. '</span></div>')
  table.insert(out, '    <div class="stat-box">Minuti conteggiabili:<br><span class="stat-value">' .. tostring(total_billed_once) .. ' min.</span></div>')
  table.insert(out, '    <div class="stat-box">File conteggiati:<br><span class="stat-value">' .. tostring(total_items) .. '</span></div>')
  table.insert(out, '  </div>')
  table.insert(out, '  <p style="margin:12px 0 0;color:#d7e6f2;font-size:0.95em;">Il totale conteggiabile &egrave; calcolato sulla durata complessiva del blocco/progetto, non sommando gli arrotondamenti delle singole righe.</p>')
  table.insert(out, '</div>')
  
  table.insert(out, encode_data_block(all_rows))
  
  table.insert(out, '</body></html>')
  return write_text_file(html_path, table.concat(out, "\n"))
end

local function save_report_file(detail_rows)
  local html_path = project_report_path("html", "", false)
  if not html_path then return nil, "Cartella progetto non disponibile." end
  
  local existing_rows, keys, existed = parse_data_block(html_path)
  local saved_at = os.date("%d/%m/%Y %H:%M:%S")
  
  local added, skipped = 0, 0
  for _, row in ipairs(detail_rows or {}) do
    if row.id and not keys[row.id] then
      local marker_cartella = trim(row.marker or "")
      if marker_cartella == "" and trim(row.scope or "") ~= "" then
        marker_cartella = trim(row.scope)
      end
      local progetto = trim(row.project or "")
      local cartella = marker_cartella ~= "" and marker_cartella or progetto
      
      table.insert(existing_rows, {
        id = row.id,
        cartella = cartella,
        nome = row.name,
        durata_sec = row.seconds or 0,
        durata_str = format_time(row.seconds),
        minuti = row.billed or 0,
        data = saved_at
      })
      keys[row.id] = true
      added = added + 1
    else
      skipped = skipped + 1
    end
  end
  
  local ok, html_err = build_html_report(existing_rows, html_path)
  if not ok then return nil, html_err end
  return html_path, added, skipped
end

local function open_window()
  if not gfx or not gfx.init then return false end
  local mode = 2
  local scroll = 0
  local last_mouse_down = false
  local copied_message = ""
  local copied_time = 0
  local pending_report_text = nil
  local pending_detail_rows = {}
  local pending_report_label = ""
  local pending_report_suffix = ""
  local pending_report_scroll = 0
  local calc_icon = -1

  gfx.init(SCRIPT_TITLE, 940, 610)
  gfx.setfont(1, "Arial", 17)
  local calc_path = find_toolbar_icon(CALC_ICON_NAME)
  if calc_path then
    calc_icon = 0
    if gfx.loadimg(calc_icon, calc_path) < 0 then calc_icon = -1 end
  end

  local function calculate()
    if mode == 1 then
      local regions = selected_regions_from_region_manager()
      local label = "Regioni selezionate"
      if #regions == 0 then
        regions = selected_regions_from_project_viewer()
      end
      if #regions == 0 then
        regions = region_under_cursor()
        label = "Regione sotto playhead"
      end
      local report_suffix = section_name_for_regions(regions)
      local rows, total_seconds, total_billed, total_items = summarize_regions(regions)
      local detail_rows = detail_rows_from_regions(regions, label, report_suffix)
      return rows, total_seconds, total_billed, total_items, label, #regions == 0 and "Nessuna regione selezionata nel Region/Marker Manager, in Project Viewer o sotto playhead." or "", "Item", report_suffix, detail_rows
    elseif mode == 2 then
      local regions = collect_regions()
      local rows, total_seconds, total_billed, total_items = summarize_regions(regions)
      local detail_rows = detail_rows_from_regions(regions, "Tutte le regioni", "Tutte le regioni")
      return rows, total_seconds, total_billed, total_items, "Tutte le regioni", #regions == 0 and "Nessuna regione nel progetto." or "", "Item", "", detail_rows
    elseif mode == 3 then
      local items = collect_selected_audio_items()
      local rows, total_seconds, total_billed, total_items = summarize_selected_items(items)
      local detail_rows = detail_rows_from_items(items, "Item selezionati", "Item selezionati", "Item audio")
      return rows, total_seconds, total_billed, total_items, "Item selezionati", #items == 0 and "Nessun item audio reale selezionato." or "", "Item audio", "", detail_rows
    elseif mode == 4 then
      local tracks = collect_selected_tracks()
      local rows, total_seconds, total_billed, total_items = summarize_tracks(tracks, nil)
      local detail_rows = detail_rows_from_tracks(tracks, "Tracce selezionate", "Tracce selezionate", is_audio_item, "Item audio")
      return rows, total_seconds, total_billed, total_items, "Tracce selezionate", #tracks == 0 and "Nessuna traccia selezionata." or "", "Item audio", "", detail_rows
    elseif mode == 5 then
      local tracks = collect_audio_tracks()
      local rows, total_seconds, total_billed, total_items = summarize_tracks(tracks, nil)
      local detail_rows = detail_rows_from_tracks(tracks, "Tutte le tracce audio", "Tutte le tracce audio", is_audio_item, "Item audio")
      return rows, total_seconds, total_billed, total_items, "Tutte le tracce audio", #tracks == 0 and "Nessuna traccia con item audio reale." or "", "Item audio", "", detail_rows
    else
      local tracks = collect_media_file_tracks()
      local rows, total_seconds, total_billed, total_items = summarize_tracks(tracks, nil, is_media_file_item)
      local detail_rows = detail_rows_from_tracks(tracks, "Tutti i file", "Tutti i file", is_media_file_item, "Item file")
      return rows, total_seconds, total_billed, total_items, "Tutti i file", #tracks == 0 and "Nessuna traccia con file audio/video reale." or "", "Item file", "", detail_rows
    end
  end

  local function loop()
    local ch = gfx.getchar()
    if ch < 0 then gfx.quit() return end
    if ch == 27 then
      if pending_report_text then
        pending_report_text = nil
        pending_detail_rows = {}
        pending_report_label = ""
        pending_report_suffix = ""
      else
        gfx.quit()
        return
      end
    end
    local mouse_down = (gfx.mouse_cap & 1) == 1
    local clicked = mouse_down and not last_mouse_down
    last_mouse_down = mouse_down
    local wheel = gfx.mouse_wheel or 0
    gfx.mouse_wheel = 0

    local rows, total_seconds, total_billed, total_items, mode_label, warning, item_label, report_suffix, detail_rows = calculate()

    ZP_UI.fill_background()
    ZP_UI.draw_header({
      icon_id = calc_icon,
      fallback_icon = draw_calculator_fallback,
      title = "Report Minuti Voce",
      description = "Conta minuti reali e minuti arrotondati in eccesso al minuto pieno.",
      title_size = 23,
      credit_size = 13,
      description_size = 16
    })

    ZP_UI.draw_help_button({ x = gfx.w - 54, y = 18, w = 34, h = 28 }, clicked, "zp-report-minuti")

    if ZP_UI.draw_button({ x = 22, y = 104, w = 170, h = 34 }, "Regioni selezionate", mode == 1, true, clicked, "tab") then mode = 1 scroll = 0 end
    if ZP_UI.draw_button({ x = 204, y = 104, w = 152, h = 34 }, "Tutte le regioni", mode == 2, true, clicked, "tab") then mode = 2 scroll = 0 end
    if ZP_UI.draw_button({ x = 368, y = 104, w = 152, h = 34 }, "Item selezionati", mode == 3, true, clicked, "tab") then mode = 3 scroll = 0 end
    if ZP_UI.draw_button({ x = 22, y = 146, w = 170, h = 34 }, "Tracce selezionate", mode == 4, true, clicked, "tab") then mode = 4 scroll = 0 end
    if ZP_UI.draw_button({ x = 204, y = 146, w = 170, h = 34 }, "Tutte tracce audio", mode == 5, true, clicked, "tab") then mode = 5 scroll = 0 end
    if ZP_UI.draw_button({ x = 386, y = 146, w = 132, h = 34 }, "Tutti i file", mode == 6, true, clicked, "tab") then mode = 6 scroll = 0 end
    local copied_recently = copied_message ~= "" and (reaper.time_precise() - copied_time) < 1.3
    if ZP_UI.draw_button({ x = gfx.w - 164, y = 146, w = 142, h = 34 }, copied_recently and "OK salvato" or "Copia + HTML", copied_recently, #rows > 0, clicked, "copy") then
      pending_report_text = build_report_text(mode_label, rows, total_seconds, total_billed, total_items, item_label)
      pending_detail_rows = detail_rows or {}
      pending_report_label = mode_label
      pending_report_suffix = report_suffix or ""
      pending_report_scroll = 0
    end

    gfx.setfont(1, "Arial", 15)
    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x = 22
    gfx.y = 188
    gfx.drawstr(mode_label)

    if warning ~= "" then
      gfx.set(0.95, 0.62, 0.42, 1)
      gfx.x = 156
      gfx.y = 188
      gfx.drawstr(fit_text(warning, gfx.w - 178))
    end

    local list = { x = 22, y = HEADER_H + 28, w = gfx.w - 44, h = gfx.h - HEADER_H - FOOTER_H - 28 }
    local rows_visible = math.max(1, math.floor((list.h - 32) / ROW_H))
    scroll = math.max(0, math.min(math.max(0, #rows - rows_visible), scroll))
    if point_in_rect(gfx.mouse_x, gfx.mouse_y, list.x, list.y, list.w, list.h) and wheel ~= 0 then
      scroll = math.max(0, math.min(math.max(0, #rows - rows_visible), scroll - (wheel > 0 and 1 or -1)))
    end

    gfx.set(0.10, 0.10, 0.14, 1)
    gfx.rect(list.x, list.y, list.w, list.h, true)
    gfx.set(0.32, 0.31, 0.42, 1)
    gfx.rect(list.x, list.y, list.w, list.h, false)

    local item_col_x = list.x + list.w - 70
    local billed_col_x = item_col_x - 120
    local real_col_x = billed_col_x - 110
    local name_max_w = math.max(180, real_col_x - list.x - 26)

    gfx.setfont(1, "Arial", 14)
    gfx.set(0.72, 0.70, 0.80, 1)
    gfx.x = list.x + 10
    gfx.y = list.y + 9
    gfx.drawstr("Nome")
    gfx.x = real_col_x
    gfx.drawstr("Reale")
    gfx.x = billed_col_x
    gfx.drawstr("Fatt.")
    gfx.x = item_col_x
    gfx.drawstr("Item")

    gfx.setfont(1, "Arial", 15)
    for i = 1, math.min(rows_visible, #rows) do
      local idx = scroll + i
      local row = rows[idx]
      local y = list.y + 34 + ((i - 1) * ROW_H)
      if idx % 2 == 0 then
        gfx.set(0.12, 0.12, 0.17, 1)
        gfx.rect(list.x + 5, y - 4, list.w - 10, ROW_H - 2, true)
      end
      gfx.set(0.90, 0.89, 0.93, 1)
      gfx.x = list.x + 10
      gfx.y = y
      gfx.drawstr(fit_text(row.name, name_max_w))
      gfx.x = real_col_x
      gfx.drawstr(format_time(row.seconds))
      gfx.x = billed_col_x
      gfx.drawstr(tostring(row.billed) .. " min")
      gfx.x = item_col_x
      gfx.drawstr(row.items and row.items > 0 and tostring(row.items) or "-")
    end

    if #rows == 0 then
      gfx.set(0.55, 0.53, 0.62, 1)
      gfx.x = list.x + 10
      gfx.y = list.y + 44
      gfx.setfont(1, "Arial", 15)
      gfx.drawstr("Nessun dato da conteggiare.")
    end

    if #rows > rows_visible then
      local sb_h = math.max(34, (rows_visible / #rows) * (list.h - 16))
      local sb_y = list.y + 8 + (scroll / math.max(1, #rows - rows_visible)) * ((list.h - 16) - sb_h)
      gfx.set(0.12, 0.48, 0.64, 1)
      gfx.rect(list.x + list.w - 7, sb_y, 4, sb_h, true)
    end

    local footer_y = gfx.h - FOOTER_H + 14
    local total_rounded_once = billed_minutes(total_seconds)
    gfx.setfont(1, "Arial", 17)
    gfx.set(0.92, 0.88, 0.78, 1)
    gfx.x = 22
    gfx.y = footer_y
    gfx.drawstr(string.format("Totale reale: %s", format_time(total_seconds)))
    gfx.x = 230
    gfx.drawstr(string.format("Arrotondato totale: %d min", total_rounded_once))
    if total_items > 0 then
      gfx.x = 470
      gfx.drawstr(string.format("%s: %d", item_label or "Item audio", total_items))
    end
    gfx.x = 22
    gfx.y = footer_y + 28
    gfx.drawstr(string.format("Parole stimate: %d/min %d   |   %d/min %d", WORD_RATE_LOW, estimated_words(total_seconds, WORD_RATE_LOW), WORD_RATE_HIGH, estimated_words(total_seconds, WORD_RATE_HIGH)))

    if copied_message ~= "" and reaper.time_precise() - copied_time < 2.0 then
      gfx.set(0.54, 0.90, 0.62, 1)
      gfx.x = 22
      gfx.y = footer_y + 52
      gfx.drawstr(copied_message)
    end

    if pending_report_text then
      gfx.set(0.0, 0.0, 0.0, 0.62)
      gfx.rect(0, 0, gfx.w, gfx.h, true)

      local modal_w = math.min(gfx.w - 80, 720)
      local modal_h = math.min(gfx.h - 80, 470)
      local mx = math.floor((gfx.w - modal_w) * 0.5)
      local my = math.floor((gfx.h - modal_h) * 0.5)

      gfx.set(0.09, 0.09, 0.13, 1)
      gfx.rect(mx, my, modal_w, modal_h, true)
      gfx.set(0.34, 0.46, 0.58, 1)
      gfx.rect(mx, my, modal_w, modal_h, false)

      gfx.setfont(1, "Arial", 22)
      gfx.set(0.92, 0.88, 0.78, 1)
      gfx.x = mx + 22
      gfx.y = my + 18
      gfx.drawstr("Conferma conteggio")

      gfx.setfont(1, "Arial", 15)
      gfx.set(0.72, 0.78, 0.88, 1)
      gfx.x = mx + 22
      gfx.y = my + 50
      gfx.drawstr("Controlla il report. Se confermi, lo copio e aggiorno CSV + HTML qui:")
      gfx.setfont(1, "Arial", 13)
      gfx.set(0.56, 0.72, 0.86, 1)
      gfx.x = mx + 22
      gfx.y = my + 70
      gfx.drawstr(fit_text(preview_report_destination(), modal_w - 44))

      local preview = { x = mx + 22, y = my + 104, w = modal_w - 44, h = modal_h - 182 }
      gfx.set(0.07, 0.07, 0.10, 1)
      gfx.rect(preview.x, preview.y, preview.w, preview.h, true)
      gfx.set(0.30, 0.30, 0.40, 1)
      gfx.rect(preview.x, preview.y, preview.w, preview.h, false)

      gfx.setfont(1, "Arial", 15)
      gfx.set(0.90, 0.89, 0.93, 1)
      local max_lines = math.max(1, math.floor((preview.h - 18) / 22))
      local total_preview_lines = count_report_lines(pending_report_text)
      local max_scroll = math.max(0, total_preview_lines - max_lines)
      if point_in_rect(gfx.mouse_x, gfx.mouse_y, preview.x, preview.y, preview.w, preview.h) and wheel ~= 0 then
        pending_report_scroll = math.max(0, math.min(max_scroll, pending_report_scroll - (wheel > 0 and 3 or -3)))
      end
      pending_report_scroll = math.max(0, math.min(max_scroll, pending_report_scroll))
      local lines = report_preview_lines(pending_report_text, pending_report_scroll + 1, max_lines, preview.w - 32)
      for i, line in ipairs(lines) do
        gfx.x = preview.x + 11
        gfx.y = preview.y + 10 + (i - 1) * 22
        gfx.drawstr(line)
      end
      if max_scroll > 0 then
        local sb_h = math.max(34, (max_lines / total_preview_lines) * (preview.h - 16))
        local sb_y = preview.y + 8 + (pending_report_scroll / max_scroll) * ((preview.h - 16) - sb_h)
        gfx.set(0.16, 0.58, 0.78, 1)
        gfx.rect(preview.x + preview.w - 8, sb_y, 5, sb_h, true)
      end

      if ZP_UI.draw_button({ x = mx + modal_w - 336, y = my + modal_h - 58, w = 170, h = 36 }, "Conferma e salva", false, true, clicked, "save") then
        set_clipboard(pending_report_text)
        local html_path, added, skipped = save_report_file(pending_detail_rows)
        copied_message = html_path and ("Report HTML aggiornato: +" .. tostring(added or 0) .. " nuove righe") or ("Report copiato. File non salvato: " .. tostring(added or "errore"))
        if html_path then
          reaper.ShowMessageBox("Report conteggi aggiornato in:\n\n" .. html_path .. "\n\nNuove righe: " .. tostring(added or 0) .. "\nGià presenti: " .. tostring(skipped or 0), "ZP Studio Suite", 0)
        else
          reaper.ShowMessageBox("Non sono riuscito a salvare il file:\n\n" .. tostring(added or "errore"), "ZP Studio Suite", 0)
        end
        copied_time = reaper.time_precise()
        pending_report_text = nil
        pending_detail_rows = {}
        pending_report_label = ""
        pending_report_suffix = ""
      end
      if ZP_UI.draw_button({ x = mx + modal_w - 152, y = my + modal_h - 58, w = 130, h = 36 }, "Annulla", false, true, clicked, "danger") then
        pending_report_text = nil
        pending_detail_rows = {}
        pending_report_label = ""
        pending_report_suffix = ""
      end
    end

    gfx.update()
    reaper.defer(loop)
  end

  loop()
  return true
end

if not open_window() then
  reaper.ShowMessageBox("Impossibile aprire la finestra Report Minuti Voce.", "ZP Studio Suite", 0)
end
