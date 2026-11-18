-- @noindex

-- RYTHMOBAND PROJECT VIEWER
-- Linea: ZP Paolo Balestri
-- Suite: ZP Studio Suite for REAPER v1.0.5
-- Distribuzione gratuita.
-- Vista cronologica editoriale di marker e regioni.

local SCRIPT_TITLE = "ZP Studio Suite v1.0.5 - Project"
local EXT_SECTION = "ZP_RythmoBand_ProjectViewer"
local UI_SCALE = 1.15
local ROW_H = math.floor(29 * UI_SCALE + 0.5)
local HEADER_H = math.floor(86 * UI_SCALE + 0.5) + 20
local FOOTER_H = math.floor(52 * UI_SCALE + 0.5)
local PLAY_PREROLL = 0.10
local TABLE_W = 900
local ACTION_RENDER_PROJECT = 40015

reaper.atexit(function()
  reaper.SetProjExtState(0, EXT_SECTION, "render_selected_regions", "")
  reaper.SetProjExtState(0, EXT_SECTION, "render_selected_count", "0")
end)

local function script_dir()
  local source = debug.getinfo(1, "S").source:sub(2)
  return source:match("^(.*)[/\\]") or "."
end

local ZP_UI = dofile(script_dir() .. "/ZP_UI.lua")

local function has_bit(value, bit)
  return (value & bit) == bit
end

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
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

local function point_in_rect(x, y, rx, ry, rw, rh)
  return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function row_key(row)
  if not row then return "" end
  return string.format("%s:%s:%.9f:%.9f", row.kind or "", tostring(row.idx or ""), row.pos or 0, row.end_pos or row.pos or 0)
end

local function format_time(seconds)
  if reaper.format_timestr_pos then
    return reaper.format_timestr_pos(seconds or 0, "", 5)
  end
  local value = math.max(0, seconds or 0)
  local m = math.floor(value / 60)
  local s = value - (m * 60)
  return string.format("%02d:%06.3f", m, s)
end

local function bool_from_state(value, fallback)
  if value == nil or value == "" then return fallback end
  return value == "1" or value == "true"
end

local function draw_button(rect, label, active, enabled, clicked, style)
  return ZP_UI.draw_button(rect, label, active, enabled, clicked, style)
end

local function draw_compact_tool(rect, label, active, enabled, clicked, kind)
  local hit = ZP_UI.draw_button(rect, "", active, enabled, clicked, "tab")
  local k = UI_SCALE
  local cx, cy = rect.x + rect.w / 2, rect.y + 8 * k
  gfx.set(0.82, 0.90, 0.94, enabled and 1 or 0.38)
  if kind == "refresh" then
    gfx.circle(cx, cy, 5 * k, false, true)
    gfx.triangle(cx + 2 * k, cy - 6 * k, cx + 7 * k, cy - 5 * k, cx + 4 * k, cy - 1 * k)
  elseif kind == "dock" then
    gfx.rect(cx - 6 * k, cy - 5 * k, 12 * k, 10 * k, false)
    gfx.line(cx - 6 * k, cy - 1 * k, cx + 6 * k, cy - 1 * k)
  elseif kind == "scroll" then
    gfx.triangle(cx - 7 * k, cy, cx - 2 * k, cy - 4 * k, cx - 2 * k, cy + 4 * k)
    gfx.triangle(cx + 7 * k, cy, cx + 2 * k, cy - 4 * k, cx + 2 * k, cy + 4 * k)
  elseif kind == "play" then
    ZP_UI.draw_symbol("play", cx, cy, 12 * k)
  elseif kind == "marker" then
    gfx.line(cx - 4 * k, cy - 6 * k, cx - 4 * k, cy + 6 * k)
    gfx.triangle(cx - 3 * k, cy - 6 * k, cx + 5 * k, cy - 4 * k, cx - 3 * k, cy)
  elseif kind == "region" then
    gfx.line(cx - 6 * k, cy - 5 * k, cx - 6 * k, cy + 5 * k)
    gfx.line(cx + 6 * k, cy - 5 * k, cx + 6 * k, cy + 5 * k)
    gfx.line(cx - 6 * k, cy - 5 * k, cx + 6 * k, cy - 5 * k)
    gfx.line(cx - 6 * k, cy + 5 * k, cx + 6 * k, cy + 5 * k)
  elseif kind == "gap" then
    gfx.rect(cx - 8 * k, cy - 4 * k, 5 * k, 8 * k, true)
    gfx.rect(cx + 3 * k, cy - 4 * k, 5 * k, 8 * k, true)
    gfx.line(cx - 1 * k, cy, cx + 1 * k, cy)
  end
  local overlay_y = rect.y + 16 * k
  gfx.set(0.03, 0.04, 0.06, 0.80)
  gfx.rect(rect.x + 1, overlay_y, rect.w - 2, rect.y + rect.h - overlay_y - 1, true)
  gfx.setfont(1, "Arial", math.floor(9 * k + 0.5), "b")
  gfx.set(0.97, 0.98, 1.00, enabled and 1 or 0.82)
  local caption = fit_text(label, rect.w - 3)
  local tw = gfx.measurestr(caption)
  gfx.x, gfx.y = rect.x + (rect.w - tw) / 2, overlay_y + 1
  gfx.drawstr(caption)
  local hover = point_in_rect(gfx.mouse_x, gfx.mouse_y, rect.x, rect.y, rect.w, rect.h)
  return hit, hover
end

local function collect_selected_item_blocks()
  local items = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    if item then
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      if len > 0 then items[#items + 1] = { item = item, pos = pos, finish = pos + len } end
    end
  end
  table.sort(items, function(a, b)
    if math.abs(a.pos - b.pos) > 0.000000001 then return a.pos < b.pos end
    return a.finish < b.finish
  end)
  local blocks = {}
  for _, entry in ipairs(items) do
    local block = blocks[#blocks]
    if block and entry.pos < block.finish - 0.000000001 then
      block.finish = math.max(block.finish, entry.finish)
      block.items[#block.items + 1] = entry.item
    else
      blocks[#blocks + 1] = { pos = entry.pos, finish = entry.finish, items = { entry.item } }
    end
  end
  return blocks, #items
end

local function insert_selected_item_gaps()
  local previous_gap = reaper.GetExtState(EXT_SECTION, "item_gap_seconds")
  if previous_gap == "" then previous_gap = "1" end
  local ok, raw = reaper.GetUserInputs("ZP Project — Spazio fra item", 1,
    "Gap in secondi (es. 1.5),extrawidth=220", previous_gap)
  if not ok then return end
  local gap_text = (raw or ""):gsub(",", ".")
  local seconds = tonumber(gap_text)
  if not seconds or seconds <= 0 or seconds > 3600 then
    reaper.ShowMessageBox("Inserisci una durata maggiore di zero e non superiore a 3600 secondi.", "ZP Project", 0)
    return
  end
  local blocks, item_count = collect_selected_item_blocks()
  if item_count == 0 then
    reaper.ShowMessageBox("REAPER non rileva item media selezionati nella timeline. Seleziona gli item nell'Arrange e riprova.", "ZP Project", 0)
    return
  end
  if item_count < 2 then
    reaper.ShowMessageBox(string.format("REAPER rileva %d item selezionato/i. Seleziona almeno due item nella timeline.", item_count), "ZP Project", 0)
    return
  end
  if #blocks < 2 then
    reaper.ShowMessageBox(string.format("REAPER rileva %d item selezionati, ma si sovrappongono e formano un solo gruppo. Servono almeno due gruppi temporali. Item che si toccano senza sovrapporsi contano come gruppi distinti.", item_count), "ZP Project", 0)
    return
  end
  local mode = reaper.ShowMessageBox(
    string.format("Inserire %.3g secondi in ciascuno dei %d varchi fra i gruppi selezionati?\n\nSì: ripple globale, inserisce spazio e sposta gli item successivi su tutte le tracce.\nNo: sposta solo i gruppi selezionati successivi.\nAnnulla: non fare nulla.", seconds, #blocks - 1),
    "ZP Project — Modalità", 3)
  if mode == 3 then return end
  local global = mode == 1
  if not global then
    local selected = {}
    for _, block in ipairs(blocks) do for _, item in ipairs(block.items) do selected[item] = true end end
    local collisions = {}
    for block_index = 2, #blocks do
      local shift = seconds * (block_index - 1)
      for _, item in ipairs(blocks[block_index].items) do
        local track = reaper.GetMediaItemTrack(item)
        local moved_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION") + shift
        local moved_end = moved_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if track then
          for j = 0, reaper.CountTrackMediaItems(track) - 1 do
            local other = reaper.GetTrackMediaItem(track, j)
            if other and not selected[other] then
              local other_start = reaper.GetMediaItemInfo_Value(other, "D_POSITION")
              local other_end = other_start + reaper.GetMediaItemInfo_Value(other, "D_LENGTH")
              if moved_start < other_end - 0.000000001 and moved_end > other_start + 0.000000001 then collisions[other] = true end
            end
          end
        end
      end
    end
    local collision_count = 0
    for _ in pairs(collisions) do collision_count = collision_count + 1 end
    if collision_count > 0 then
      local proceed = reaper.ShowMessageBox(string.format(
        "Spostando solo i selezionati, %d item non selezionati sulla stessa traccia potrebbero sovrapporsi ai gruppi spostati. Gli altri item resteranno fermi. Continuare?", collision_count),
        "ZP Project — Controllo", 3)
      if proceed ~= 1 then return end
    end
  end
  local boundaries = {}
  for i = 2, #blocks do boundaries[#boundaries + 1] = blocks[i].pos end

  if global then
    if not reaper.GetSet_LoopTimeRange2 or not reaper.Main_OnCommand then
      reaper.ShowMessageBox("REAPER non espone le funzioni necessarie per il ripple globale.", "ZP Project", 0)
      return
    end
    local crossing_items, locked_items = {}, {}
    for _, boundary in ipairs(boundaries) do
      for i = 0, reaper.CountMediaItems(0) - 1 do
        local item = reaper.GetMediaItem(0, i)
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local finish = pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local lock = reaper.GetMediaItemInfo_Value(item, "C_LOCK") or 0
        if pos < boundary - 0.000000001 and finish > boundary + 0.000000001 then crossing_items[item] = true end
        if pos >= boundary - 0.000000001 and lock ~= 0 then locked_items[item] = true end
      end
    end
    local crossing, locked = 0, 0
    for _ in pairs(crossing_items) do crossing = crossing + 1 end
    for _ in pairs(locked_items) do locked = locked + 1 end
    if crossing > 0 or locked > 0 then
      reaper.ShowMessageBox(string.format(
        "Ripple globale non avviato: %d item attraversano un punto d'inserimento e %d item successivi sono bloccati.\n\nRisolvi questi casi oppure usa Solo selezionati.", crossing, locked),
        "ZP Project — Controllo", 0)
      return
    end
  end

  reaper.SetExtState(EXT_SECTION, "item_gap_seconds", tostring(seconds), true)
  local old_cursor = reaper.GetCursorPosition()
  local old_start, old_end = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  reaper.Undo_BeginBlock2(0)
  local success, err = pcall(function()
    if global then
      -- Inserendo dal piu' tardo al piu' vicino si conservano i confini ancora da processare.
      for i = #boundaries, 1, -1 do
        local at = boundaries[i]
        reaper.GetSet_LoopTimeRange2(0, true, false, at, at + seconds, false)
        reaper.Main_OnCommand(40200, 0) -- Time selection: Insert empty space at time selection (moving later items)
      end
    else
      for i = 2, #blocks do
        local shift = seconds * (i - 1)
        for _, item in ipairs(blocks[i].items) do
          local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
          reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos + shift)
        end
      end
    end
  end)
  reaper.GetSet_LoopTimeRange2(0, true, false, old_start, old_end, false)
  reaper.SetEditCurPos(old_cursor, false, false)
  reaper.Undo_EndBlock2(0, global and "ZP Project: spazio fra item (ripple globale)" or "ZP Project: spazio fra item selezionati", -1)
  if not success then
    reaper.ShowMessageBox("Operazione interrotta: " .. tostring(err) .. "\nUsa Annulla se il progetto risulta modificato.", "ZP Project", 0)
    return
  end
  reaper.UpdateArrange()
end

local function is_render_shortcut(ch)
  local cmd_or_ctrl = has_bit(gfx.mouse_cap, 32) or has_bit(gfx.mouse_cap, 4)
  local option_or_alt = has_bit(gfx.mouse_cap, 16)
  return cmd_or_ctrl and option_or_alt and (ch == 82 or ch == 114 or ch == 174)
end

local function draw_project_icon(x, y, size)
  gfx.set(0.10, 0.42, 0.48, 1)
  gfx.rect(x, y, size, size, true)
  gfx.set(0.05, 0.18, 0.22, 1)
  gfx.rect(x, y, size, size, false)
  gfx.set(0.92, 0.88, 0.70, 1)
  local k = size / 28
  local dot = math.max(4 * k, math.floor(size * 0.14))
  local line_w = size - dot - 14 * k
  local y1 = y + math.floor(size * 0.28)
  local y2 = y + math.floor(size * 0.52)
  local y3 = y + math.floor(size * 0.76)
  gfx.rect(x + 7 * k, y1 - 2 * k, dot, dot, true)
  gfx.rect(x + 7 * k, y2 - 2 * k, dot, dot, true)
  gfx.rect(x + 7 * k, y3 - 2 * k, dot, dot, true)
  gfx.rect(x + 15 * k + dot, y1, line_w, 3 * k, true)
  gfx.rect(x + 15 * k + dot, y2, line_w, 3 * k, true)
  gfx.rect(x + 15 * k + dot, y3, line_w, 3 * k, true)
end

local function native_color_to_rgb(color)
  if not color or color == 0 then return nil end
  local r, g, b = reaper.ColorFromNative(color & 0xFFFFFF)
  return (r or 0) / 255, (g or 0) / 255, (b or 0) / 255
end

local function collect_project_marks()
  local markers, regions = {}, {}
  local _, marker_count, region_count = reaper.CountProjectMarkers(0)
  local total = marker_count + region_count
  for i = 0, total - 1 do
    local ok, is_region, pos, rgn_end, name, idx, color = reaper.EnumProjectMarkers3(0, i)
    if ok then
      local entry = {
        is_region = is_region,
        pos = pos or 0,
        rgn_end = rgn_end or pos or 0,
        name = trim(name or ""),
        idx = idx,
        color = color or 0
      }
      if is_region then table.insert(regions, entry) else table.insert(markers, entry) end
    end
  end
  table.sort(markers, function(a, b) return a.pos < b.pos end)
  table.sort(regions, function(a, b)
    if math.abs(a.pos - b.pos) > 0.000001 then return a.pos < b.pos end
    return a.rgn_end < b.rgn_end
  end)
  return markers, regions
end

local function build_rows()
  local markers, regions = collect_project_marks()
  local rows = {}
  local used_regions = {}
  local EPS = 0.000001

  local function add_marker_group(label, pos)
    table.insert(rows, {
      kind = "marker",
      label = label,
      pos = pos or 0,
      end_pos = nil,
      idx = "-",
      color = 0,
      synthetic = true
    })
  end

  local function add_region(region, parent_marker)
    used_regions[region] = true
    table.insert(rows, {
      kind = "region",
      label = region.name ~= "" and region.name or "(senza nome)",
      pos = region.pos,
      end_pos = region.rgn_end,
      idx = region.idx,
      color = region.color,
      parent = parent_marker,
      source = region
    })
  end

  local first_marker = markers[1]
  local before_first = {}
  for _, region in ipairs(regions) do
    if not first_marker or region.pos < first_marker.pos - EPS then
      table.insert(before_first, region)
    end
  end
  if #before_first > 0 then
    add_marker_group(first_marker and "[Prima del primo marker]" or "[Senza marker]", before_first[1].pos)
    for _, region in ipairs(before_first) do add_region(region, nil) end
  end

  for m_index, marker in ipairs(markers) do
    local next_marker = markers[m_index + 1]
    local marker_end = next_marker and next_marker.pos or nil
    table.insert(rows, {
      kind = "marker",
      label = marker.name ~= "" and marker.name or "(marker senza nome)",
      pos = marker.pos,
      end_pos = marker_end,
      idx = marker.idx,
      color = marker.color,
      source = marker
    })
    for _, region in ipairs(regions) do
      if region.pos >= marker.pos - EPS and (not next_marker or region.pos < next_marker.pos - EPS) then
        add_region(region, marker)
      end
    end
  end

  for _, region in ipairs(regions) do
    if not used_regions[region] then add_region(region, nil) end
  end

  table.sort(rows, function(a, b)
    if math.abs(a.pos - b.pos) > 0.000001 then return a.pos < b.pos end
    if a.kind ~= b.kind then return a.kind == "marker" end
    return (a.end_pos or a.pos) < (b.end_pos or b.pos)
  end)

  return rows, #markers, #regions
end

local function set_project_mark(entry, new_name)
  if not entry or not entry.idx then return false end
  new_name = trim(new_name)
  local is_region = entry.kind == "region"
  local end_pos = is_region and (entry.end_pos or entry.pos) or 0
  if reaper.SetProjectMarker3 then
    return reaper.SetProjectMarker3(0, entry.idx, is_region, entry.pos, end_pos, new_name, entry.color or 0)
  end
  reaper.DeleteProjectMarker(0, entry.idx, is_region)
  reaper.AddProjectMarker2(0, is_region, entry.pos, end_pos, new_name, entry.idx, entry.color or 0)
  return true
end

local function speak(text)
  if reaper.osara_outputMessage then
    reaper.osara_outputMessage(text)
  else
    reaper.ShowMessageBox(text, SCRIPT_TITLE, 0)
  end
end

local function run_osara_mode()
  local rows, marker_count, region_count = build_rows()
  local lines = {
    string.format("ZP Studio Suite - Project. Marker: %d. Regioni: %d.", marker_count, region_count)
  }
  for _, row in ipairs(rows) do
    local prefix = row.kind == "marker" and "Marker" or "Regione"
    table.insert(lines, string.format("%s %s %s", prefix, format_time(row.pos), row.label))
  end
  speak(table.concat(lines, ". "))
end

local KEY_BACKSPACE = 8
local KEY_DELETE = 6579564
local KEY_LEFT = 1818584692
local KEY_RIGHT = 1919379572
local KEY_HOME = 1752132965
local KEY_END = 6647396
local KEY_SPACE = 32

local function is_select_all_key(ch)
  if ch == 1 then return true end
  local ctrl_or_cmd = (gfx.mouse_cap & 4) == 4 or (gfx.mouse_cap & 32) == 32
  return ctrl_or_cmd and (ch == 65 or ch == 97)
end

local function is_copy_key(ch)
  if ch == 3 then return true end
  local ctrl_or_cmd = (gfx.mouse_cap & 4) == 4 or (gfx.mouse_cap & 32) == 32
  return ctrl_or_cmd and (ch == 67 or ch == 99)
end

local function is_paste_key(ch)
  if ch == 22 then return true end
  local ctrl_or_cmd = (gfx.mouse_cap & 4) == 4 or (gfx.mouse_cap & 32) == 32
  return ctrl_or_cmd and (ch == 86 or ch == 118)
end

local function is_cut_key(ch)
  if ch == 24 then return true end
  local ctrl_or_cmd = (gfx.mouse_cap & 4) == 4 or (gfx.mouse_cap & 32) == 32
  return ctrl_or_cmd and (ch == 88 or ch == 120)
end

local function is_undo_key(ch)
  if ch == 26 then return true end
  local ctrl_or_cmd = (gfx.mouse_cap & 4) == 4 or (gfx.mouse_cap & 32) == 32
  return ctrl_or_cmd and (ch == 90 or ch == 122)
end

local function prev_cursor(text, cursor)
  text = tostring(text or "")
  cursor = math.max(1, math.min(cursor or (#text + 1), #text + 1))
  if cursor <= 1 then return 1 end
  if utf8 and utf8.offset then
    local p = utf8.offset(text, -1, cursor)
    if p then return p end
  end
  return math.max(1, cursor - 1)
end

local function next_cursor(text, cursor)
  text = tostring(text or "")
  cursor = math.max(1, math.min(cursor or (#text + 1), #text + 1))
  if cursor > #text then return #text + 1 end
  if utf8 and utf8.offset then
    local n = utf8.offset(text, 2, cursor)
    if n then return n end
  end
  return math.min(#text + 1, cursor + 1)
end

local function cursor_from_x(text, target_x, left_x)
  text = tostring(text or "")
  local pos = 1
  while pos <= #text do
    local next_pos = next_cursor(text, pos)
    local before = text:sub(1, pos - 1)
    local chunk = text:sub(1, next_pos - 1)
    local mid = left_x + gfx.measurestr(before) + ((gfx.measurestr(chunk) - gfx.measurestr(before)) * 0.5)
    if target_x < mid then return pos end
    pos = next_pos
  end
  return #text + 1
end

local caps_lock_cache_time = nil
local caps_lock_cache_value = false

local function caps_lock_on()
  if reaper.GetOS and tostring(reaper.GetOS()):match("OSX") then
    local now = reaper.time_precise and reaper.time_precise() or os.clock()
    if caps_lock_cache_time and (now - caps_lock_cache_time) < 0.12 then
      return caps_lock_cache_value
    end
    local ok, pipe = pcall(io.popen, "ioreg -r -k IOHIDKeyboardCapsLockState -d 1 2>/dev/null")
    if ok and pipe then
      local out = pipe:read("*a") or ""
      pipe:close()
      caps_lock_cache_time = now
      caps_lock_cache_value = out:match("IOHIDKeyboardCapsLockState%s*=%s*1") ~= nil
      if caps_lock_cache_value then return true end
    end
  end
  if reaper.JS_VKeys_GetState then
    for _, cutoff in ipairs({-2, -1, 0}) do
      local ok, state = pcall(reaper.JS_VKeys_GetState, cutoff)
      if ok and type(state) == "string" then
        for _, key in ipairs({0x14, 57}) do
          local b = state:byte(key + 1)
          if b and b ~= 0 then return true end
        end
      end
    end
  end
  return false
end

local function text_from_char(ch)
  if ch < 32 or ch > 255 then return nil end
  if (caps_lock_on() or (gfx.mouse_cap & 8) == 8) and ch >= 97 and ch <= 122 then
    ch = ch - 32
  end
  local ok, typed = false, nil
  if utf8 and utf8.char then ok, typed = pcall(utf8.char, ch) end
  if not ok and ch <= 255 then typed = string.char(ch) end
  return typed
end

local function edit_text_at_cursor(text, cursor, ch)
  text = tostring(text or "")
  cursor = math.max(1, math.min(cursor or (#text + 1), #text + 1))
  if ch == KEY_BACKSPACE then
    local p = prev_cursor(text, cursor)
    if p < cursor then text = text:sub(1, p - 1) .. text:sub(cursor) end
    return text, p
  elseif ch == KEY_DELETE then
    local n = next_cursor(text, cursor)
    if n > cursor then text = text:sub(1, cursor - 1) .. text:sub(n) end
    return text, cursor
  elseif ch == KEY_LEFT then
    return text, prev_cursor(text, cursor)
  elseif ch == KEY_RIGHT then
    return text, next_cursor(text, cursor)
  elseif ch == KEY_HOME then
    return text, 1
  elseif ch == KEY_END then
    return text, #text + 1
  end
  local typed = text_from_char(ch)
  if typed then return text:sub(1, cursor - 1) .. typed .. text:sub(cursor), cursor + #typed end
  return text, cursor
end

local function draw_project_window()
  if not gfx or not gfx.init then return false end

  local show_markers = bool_from_state(reaper.GetExtState(EXT_SECTION, "show_markers"), true)
  local show_regions = bool_from_state(reaper.GetExtState(EXT_SECTION, "show_regions"), true)
  local auto_play = bool_from_state(reaper.GetExtState(EXT_SECTION, "auto_play"), false)
  local invert_h_scroll = bool_from_state(reaper.GetExtState(EXT_SECTION, "invert_h_scroll"), false)
  local dock_state = tonumber(reaper.GetExtState(EXT_SECTION, "dock_state")) or 0
  local scroll = 0
  local h_scroll = 0
  local selected = 1
  local render_selected = {}
  local render_anchor = nil
  local native_render_selection = false
  local last_mouse_down = false
  local last_click_time = 0
  local last_click_row = nil
  local last_project_state = -1
  local last_time_sel_start = nil
  local last_time_sel_end = nil
  local rows, marker_count, region_count = build_rows()
  local edit_row = nil
  local edit_text = ""
  local edit_cursor = 1
  local edit_sel_start = nil
  local edit_sel_end = nil
  local edit_drag_anchor = nil
  local edit_dragging = false
  local edit_last_click_time = 0
  local edit_clipboard = ""
  local edit_undo = {}
  local play_until = nil
  local h_dragging = false
  local h_drag_start_x = 0
  local h_drag_start_scroll = 0

  -- toolbar: icona accesa finche' la finestra e' aperta; un altro clic sull'icona la chiude (REAPER 7.03+)
  if reaper.set_action_options then reaper.set_action_options(1 | 4); reaper.atexit(function() reaper.set_action_options(8) end) end
  gfx.init(SCRIPT_TITLE, 920, 620, dock_state)
  gfx.setfont(1, "Arial", math.floor(15 * UI_SCALE + 0.5))

  local function filtered_rows()
    local out = {}
    for _, row in ipairs(rows) do
      if (row.kind == "marker" and show_markers) or (row.kind == "region" and show_regions) then
        table.insert(out, row)
      end
    end
    return out
  end

  local function refresh(force)
    local state_count = reaper.GetProjectStateChangeCount(0)
    if force or state_count ~= last_project_state then
      rows, marker_count, region_count = build_rows()
      last_project_state = state_count
    end
  end

  local function stop_play()
    play_until = nil
    reaper.Main_OnCommand(1016, 0)
  end

  local function play_entry(row)
    if not row then return end
    play_until = row.kind == "region" and row.end_pos or row.end_pos
    reaper.SetEditCurPos(math.max(0, row.pos - PLAY_PREROLL), true, false)
    reaper.Main_OnCommand(1007, 0)
  end

  local function toggle_selected_play(row)
    local play_state = reaper.GetPlayState()
    if (play_state & 1) == 1 then
      stop_play()
    else
      play_entry(row)
    end
  end

  local function commit_edit(visible)
    if not edit_row then return end
    local row = visible[edit_row]
    if row then
      local old_label = (row.label == "(senza nome)" or row.label == "(marker senza nome)") and "" or (row.label or "")
      if trim(edit_text) ~= trim(old_label) then
        reaper.Undo_BeginBlock()
        set_project_mark(row, edit_text)
        reaper.Undo_EndBlock("ZP Studio Suite: rinomina da Project", -1)
      end
      refresh(true)
    end
    edit_row = nil
    edit_text = ""
    edit_cursor = 1
    edit_sel_start = nil
    edit_sel_end = nil
    edit_drag_anchor = nil
    edit_dragging = false
    edit_undo = {}
  end

  local function cancel_edit()
    edit_row = nil
    edit_text = ""
    edit_cursor = 1
    edit_sel_start = nil
    edit_sel_end = nil
    edit_drag_anchor = nil
    edit_dragging = false
    edit_undo = {}
  end

  local function edit_push_undo()
    edit_undo[#edit_undo + 1] = {
      text = edit_text,
      cursor = edit_cursor,
      sel_start = edit_sel_start,
      sel_end = edit_sel_end
    }
    if #edit_undo > 60 then table.remove(edit_undo, 1) end
  end

  local function edit_restore_undo()
    local state = table.remove(edit_undo)
    if not state then return end
    edit_text = state.text or ""
    edit_cursor = state.cursor or (#edit_text + 1)
    edit_sel_start = state.sel_start
    edit_sel_end = state.sel_end
  end

  local function edit_set_cursor(pos)
    edit_cursor = math.max(1, math.min(pos or 1, #edit_text + 1))
    edit_sel_start = nil
    edit_sel_end = nil
  end

  local function edit_set_selection(a, b)
    local max_pos = #edit_text + 1
    a = math.max(1, math.min(a or 1, max_pos))
    b = math.max(1, math.min(b or a, max_pos))
    edit_cursor = b
    if a == b then
      edit_sel_start = nil
      edit_sel_end = nil
    else
      edit_sel_start = math.min(a, b)
      edit_sel_end = math.max(a, b)
    end
  end

  local function edit_selection_range()
    if not edit_sel_start or edit_sel_start == edit_sel_end then return nil, nil end
    return math.min(edit_sel_start, edit_sel_end), math.max(edit_sel_start, edit_sel_end)
  end

  local function edit_selected_text()
    local a, b = edit_selection_range()
    if not a then return "" end
    return edit_text:sub(a, b - 1)
  end

  local function edit_delete_selection()
    local a, b = edit_selection_range()
    if not a then return false end
    edit_text = edit_text:sub(1, a - 1) .. edit_text:sub(b)
    edit_set_cursor(a)
    return true
  end

  local function edit_insert_text(value)
    value = tostring(value or ""):gsub("\r\n", " "):gsub("[\r\n]", " ")
    if value == "" then return end
    edit_push_undo()
    edit_delete_selection()
    edit_text = edit_text:sub(1, edit_cursor - 1) .. value .. edit_text:sub(edit_cursor)
    edit_cursor = edit_cursor + #value
  end

  local function edit_backspace()
    if edit_selection_range() then edit_push_undo(); edit_delete_selection(); return end
    if edit_cursor <= 1 then return end
    edit_push_undo()
    local p = prev_cursor(edit_text, edit_cursor)
    edit_text = edit_text:sub(1, p - 1) .. edit_text:sub(edit_cursor)
    edit_cursor = p
  end

  local function edit_delete()
    if edit_selection_range() then edit_push_undo(); edit_delete_selection(); return end
    if edit_cursor > #edit_text then return end
    edit_push_undo()
    local n = next_cursor(edit_text, edit_cursor)
    edit_text = edit_text:sub(1, edit_cursor - 1) .. edit_text:sub(n)
  end

  local function edit_copy()
    local selected_text = edit_selected_text()
    if selected_text == "" then return end
    edit_clipboard = selected_text
    if reaper.CF_SetClipboard then pcall(reaper.CF_SetClipboard, selected_text) end
  end

  local function edit_paste()
    local clip = edit_clipboard
    if reaper.CF_GetClipboard then
      local ok, value = pcall(reaper.CF_GetClipboard, "")
      if ok and value and value ~= "" then clip = value end
    end
    edit_insert_text(clip or "")
  end

  local function edit_cut()
    if edit_selected_text() == "" then return end
    edit_copy()
    edit_push_undo()
    edit_delete_selection()
  end

  local function edit_select_word_at_cursor()
    if edit_text == "" then return end
    local pos = math.min(math.max(1, edit_cursor or 1), #edit_text)
    if edit_text:sub(pos, pos):match("[%s%p]") and pos > 1 then pos = pos - 1 end
    while pos > 1 and edit_text:sub(pos, pos):match("[%s%p]") do pos = pos - 1 end
    local a = pos
    while a > 1 and not edit_text:sub(a - 1, a - 1):match("[%s%p]") do a = a - 1 end
    local b = pos + 1
    while b <= #edit_text and not edit_text:sub(b, b):match("[%s%p]") do b = b + 1 end
    edit_set_selection(a, b)
  end

  local function listview_region_id(list, row_index)
    for col = 0, 4 do
      local text = reaper.JS_ListView_GetItemText(list, row_index, col) or ""
      local region_id = tonumber(text:match("^%s*R(%d+)%s*$"))
      if region_id then return region_id end
    end
    return nil
  end

  local function count_render_selected()
    local count = 0
    for _ in pairs(render_selected) do count = count + 1 end
    return count
  end

  local function set_timeline_time_selection(start_pos, end_pos)
    start_pos = tonumber(start_pos)
    end_pos = tonumber(end_pos)
    if not start_pos or not end_pos or end_pos <= start_pos then return false end
    reaper.GetSet_LoopTimeRange2(0, true, false, start_pos, end_pos, false)
    last_time_sel_start = start_pos
    last_time_sel_end = end_pos
    reaper.UpdateArrange()
    return true
  end

  local function show_row_time_selection(row)
    if not row or row.kind ~= "region" then return false end
    return set_timeline_time_selection(row.pos, row.end_pos)
  end

  local function show_render_selection_time_range(visible, fallback_row)
    local start_pos, end_pos
    for _, row in ipairs(visible) do
      if row.kind == "region" and render_selected[row_key(row)] then
        start_pos = start_pos and math.min(start_pos, row.pos) or row.pos
        end_pos = end_pos and math.max(end_pos, row.end_pos or row.pos) or (row.end_pos or row.pos)
      end
    end
    if start_pos and end_pos and end_pos > start_pos then
      return set_timeline_time_selection(start_pos, end_pos)
    end
    return show_row_time_selection(fallback_row)
  end

  local function clean_render_selection(visible)
    local alive = {}
    for _, row in ipairs(visible) do
      if row.kind == "region" then alive[row_key(row)] = true end
    end
    for key in pairs(render_selected) do
      if not alive[key] then render_selected[key] = nil end
    end
  end

  local function save_render_selection(visible)
    local lines = {}
    local selected_region_ids = {}
    for _, row in ipairs(visible) do
      if row.kind == "region" and render_selected[row_key(row)] then
        selected_region_ids[row.idx] = true
        table.insert(lines, table.concat({
          tostring(row.idx or ""),
          tostring(row.pos or 0),
          tostring(row.end_pos or 0),
          row.label or ""
        }, "\t"))
      end
    end
    reaper.SetProjExtState(0, EXT_SECTION, "render_selected_regions", table.concat(lines, "\n"))
    reaper.SetProjExtState(0, EXT_SECTION, "render_selected_count", tostring(#lines))
    native_render_selection = false

    if reaper.JS_Window_Find and reaper.JS_Window_FindChildByID and
      reaper.JS_ListView_GetItemCount and reaper.JS_ListView_GetItemText and
      reaper.JS_ListView_SetItemState then
      local title = reaper.JS_Localize and reaper.JS_Localize("Region/Marker Manager", "common") or "Region/Marker Manager"
      local manager = reaper.JS_Window_Find(title, true)
      local opened_manager = false
      if not manager and #lines > 0 then
        reaper.Main_OnCommand(40326, 0) -- View: Region/Marker Manager
        manager = reaper.JS_Window_Find(title, true)
        opened_manager = manager ~= nil
      end
      if manager then
        local list = reaper.JS_Window_FindChildByID(manager, 1071)
        if list then
          local item_count = reaper.JS_ListView_GetItemCount(list)
          reaper.JS_ListView_SetItemState(list, -1, 0x0, 0x3)
          for i = 0, item_count - 1 do
            local region_id = listview_region_id(list, i)
            if region_id and selected_region_ids[region_id] then
              reaper.JS_ListView_SetItemState(list, i, 0x3, 0x3)
              native_render_selection = true
            end
          end
          if #lines > 0 then
            reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 5, true)
          end
        end
        if opened_manager and reaper.JS_Window_Show then
          reaper.JS_Window_Show(manager, "HIDE")
        end
      end
    end
  end

  local function set_region_range_selection(visible, from_idx, to_idx)
    render_selected = {}
    if not from_idx or not to_idx then return end
    if from_idx > to_idx then from_idx, to_idx = to_idx, from_idx end
    for i = from_idx, to_idx do
      local row = visible[i]
      if row and row.kind == "region" then render_selected[row_key(row)] = true end
    end
  end

  local function select_all_visible_regions(visible)
    render_selected = {}
    render_anchor = nil
    for i, row in ipairs(visible) do
      if row.kind == "region" then
        render_selected[row_key(row)] = true
        if not render_anchor then render_anchor = i end
      end
    end
    save_render_selection(visible)
    show_render_selection_time_range(visible)
  end

  local function sync_selection_from_reaper(visible)
    local t_start, t_end = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    if last_time_sel_start == nil then 
      last_time_sel_start, last_time_sel_end = t_start, t_end 
    end
    if math.abs(t_start - last_time_sel_start) > 0.001 or math.abs(t_end - last_time_sel_end) > 0.001 then
      last_time_sel_start = t_start
      last_time_sel_end = t_end
      if t_start == t_end then
        local count = 0
        for _ in pairs(render_selected) do count = count + 1 end
        if count > 0 then
          render_selected = {}
          reaper.SetProjExtState(0, EXT_SECTION, "render_selected_regions", "")
          reaper.SetProjExtState(0, EXT_SECTION, "render_selected_count", "0")
        end
      else
        local matched = {}
        local any_changed = false
        for _, row in ipairs(visible) do
          if row.kind == "region" then
            local r_start = row.pos
            local r_end = row.end_pos or row.pos
            if r_start < t_end - 0.001 and r_end > t_start + 0.001 then
              local key = row_key(row)
              matched[key] = true
              if not render_selected[key] then any_changed = true end
            end
          end
        end
        if not any_changed then
          for key in pairs(render_selected) do
            if not matched[key] then any_changed = true break end
          end
        end
        if any_changed then
          render_selected = matched
          local lines = {}
          for _, row in ipairs(visible) do
            if row.kind == "region" and render_selected[row_key(row)] then
              table.insert(lines, table.concat({
                tostring(row.idx or ""),
                tostring(row.pos or 0),
                tostring(row.end_pos or 0),
                row.label or ""
              }, "\t"))
            end
          end
          reaper.SetProjExtState(0, EXT_SECTION, "render_selected_regions", table.concat(lines, "\n"))
          reaper.SetProjExtState(0, EXT_SECTION, "render_selected_count", tostring(#lines))
        end
      end
    end
  end

  local function sync_from_region_manager(visible)
    if not (reaper.JS_Window_Find and reaper.JS_Window_FindChildByID and
      reaper.JS_ListView_GetItemCount and reaper.JS_ListView_GetItemText and
      reaper.JS_ListView_GetItemState) then
      return false
    end
    local title = reaper.JS_Localize and reaper.JS_Localize("Region/Marker Manager", "common") or "Region/Marker Manager"
    local manager = reaper.JS_Window_Find(title, true)
    if not manager then return false end
    local list = reaper.JS_Window_FindChildByID(manager, 1071)
    if not list then return false end

    local item_count = reaper.JS_ListView_GetItemCount(list)
    local selected_ids = {}
    
    for i = 0, item_count - 1 do
      local state = reaper.JS_ListView_GetItemState(list, i) or 0
      if (state & 0x2) == 0x2 then
        local region_id = listview_region_id(list, i)
        if region_id then
          selected_ids[region_id] = true
        end
      end
    end
    
    local any_changed = false
    local matched = {}
    for _, row in ipairs(visible) do
      if row.kind == "region" then
        local key = row_key(row)
        if selected_ids[row.idx] then
          matched[key] = true
          if not render_selected[key] then any_changed = true end
        end
      end
    end
    
    if not any_changed then
      for key in pairs(render_selected) do
        if not matched[key] then any_changed = true break end
      end
    end
    
    if any_changed then
      render_selected = matched
      local lines = {}
      for _, row in ipairs(visible) do
        if row.kind == "region" and render_selected[row_key(row)] then
          table.insert(lines, table.concat({
            tostring(row.idx or ""),
            tostring(row.pos or 0),
            tostring(row.end_pos or 0),
            row.label or ""
          }, "\t"))
        end
      end
      reaper.SetProjExtState(0, EXT_SECTION, "render_selected_regions", table.concat(lines, "\n"))
      reaper.SetProjExtState(0, EXT_SECTION, "render_selected_count", tostring(#lines))
      return true
    end
    return false
  end

  local function handle_render_selection_click(visible, idx, range_anchor)
    local row = visible[idx]
    if not row or row.kind ~= "region" then return false end
    local ctrl_or_cmd = has_bit(gfx.mouse_cap, 4) or has_bit(gfx.mouse_cap, 32)
    local shift = has_bit(gfx.mouse_cap, 8)
    local key = row_key(row)
    if shift then
      local anchor = range_anchor or render_anchor or idx
      set_region_range_selection(visible, anchor, idx)
      render_anchor = anchor
    elseif ctrl_or_cmd then
      render_selected[key] = not render_selected[key] or nil
      render_anchor = idx
    else
      render_selected = {}
      render_selected[key] = true
      render_anchor = idx
    end
    save_render_selection(visible)
    if ctrl_or_cmd or shift then
      show_render_selection_time_range(visible, row)
    else
      show_row_time_selection(row)
    end
    return ctrl_or_cmd or shift
  end

  local function loop()
    local ch = gfx.getchar()
    if ch < 0 then gfx.quit() return end
    local current_dock = gfx.dock and gfx.dock(-1) or dock_state
    if current_dock ~= dock_state then
      dock_state = current_dock
      reaper.SetExtState(EXT_SECTION, "dock_state", tostring(dock_state), true)
    end
    refresh(false)
    local visible = filtered_rows()
    if selected > #visible then selected = math.max(1, #visible) end
    clean_render_selection(visible)
    local is_playing = (reaper.GetPlayState() & 1) == 1
    local selection_changed = false

    sync_selection_from_reaper(visible)
    sync_from_region_manager(visible)

    if play_until then
      local play_state = reaper.GetPlayState()
      if (play_state & 1) == 1 then
        if reaper.GetPlayPosition() >= play_until - 0.02 then stop_play() end
      else
        play_until = nil
      end
    end

    if not edit_row and is_select_all_key(ch) then
      select_all_visible_regions(visible)
      ch = 0
    elseif not edit_row and is_render_shortcut(ch) then
      reaper.Main_OnCommand(ACTION_RENDER_PROJECT, 0)
      ch = 0
    end

    if ch == 27 then
      if edit_row then
        cancel_edit()
      else
        gfx.quit()
        return
      end
    elseif edit_row and ch > 0 then
      if is_select_all_key(ch) then
        edit_set_selection(1, #edit_text + 1)
      elseif is_copy_key(ch) then
        edit_copy()
      elseif is_paste_key(ch) then
        edit_paste()
      elseif is_cut_key(ch) then
        edit_cut()
      elseif is_undo_key(ch) then
        edit_restore_undo()
      elseif ch == 13 then
        commit_edit(visible)
      elseif ch == 9 then
        commit_edit(visible)
        if selected < #visible then
          selected = selected + 1
          selection_changed = true
        end
      elseif ch == KEY_BACKSPACE then
        edit_backspace()
      elseif ch == KEY_DELETE then
        edit_delete()
      elseif ch == KEY_LEFT then
        edit_set_cursor(prev_cursor(edit_text, edit_cursor))
      elseif ch == KEY_RIGHT then
        edit_set_cursor(next_cursor(edit_text, edit_cursor))
      elseif ch == KEY_HOME then
        edit_set_cursor(1)
      elseif ch == KEY_END then
        edit_set_cursor(#edit_text + 1)
      else
        local typed = text_from_char(ch)
        if typed then edit_insert_text(typed) end
      end
    elseif ch == KEY_SPACE and visible[selected] then
      toggle_selected_play(visible[selected])
    elseif ch == 13 and visible[selected] then
      play_entry(visible[selected])
    end

    local mouse_down = (gfx.mouse_cap & 1) == 1
    local clicked = mouse_down and not last_mouse_down
    local released = (not mouse_down) and last_mouse_down
    last_mouse_down = mouse_down
    local wheel = gfx.mouse_wheel
    gfx.mouse_wheel = 0
    local h_wheel = gfx.mouse_hwheel or 0
    if gfx.mouse_hwheel then gfx.mouse_hwheel = 0 end
    if released then h_dragging = false end

    ZP_UI.fill_background()
    ZP_UI.draw_header({
      x = 12,
      y = 18,
      icon_size = math.floor(28 * UI_SCALE + 0.5),
      fallback_icon = draw_project_icon,
      title = "Project",
      title_size = math.floor(20 * UI_SCALE + 0.5),
      credit_offset = math.floor(46 * UI_SCALE + 0.5),
      description = ""
    })

    local help_rect = { x = gfx.w - 58, y = 16, w = 39, h = 32, font = math.floor(15 * UI_SCALE + 0.5) }
    ZP_UI.draw_help_button(help_rect, clicked, "zp-project-viewer")

    gfx.setfont(1, "Arial", math.floor(13 * UI_SCALE + 0.5))

    local b_y1, b_y2, b_h, button_x = 8, 47, math.floor(28 * UI_SCALE + 0.5), 128
    local compact_hover = nil
    local function compact_rect(row, col)
      return { x = button_x + col * math.floor(46 * UI_SCALE + 0.5), y = row == 1 and b_y1 or b_y2,
        w = math.floor(42 * UI_SCALE + 0.5), h = b_h }
    end
    local lang = ZP_UI.get_lingua and ZP_UI.get_lingua() or "it"
    local help_text = {
      refresh = {"Aggiorna la lista", "Reload the list", "Rilegge marker e regioni del progetto.", "Reloads project markers and regions."},
      dock = {"Aggancia / sgancia", "Dock / float", "Aggancia la finestra o la rende libera.", "Docks the window or makes it float."},
      scroll = {"Inverte lo scorrimento", "Invert scrolling", "Cambia la direzione della rotella orizzontale.", "Reverses horizontal wheel direction."},
      gap = {"Spazio fra item", "Space between items", "Imposta i secondi; scegli ripple globale su tutte le tracce o solo selezionati.", "Set the gap, then choose global ripple on all tracks or selected items only."},
      play = {"Click per ascoltare", "Click to audition", "Attiva o disattiva l'ascolto automatico della riga selezionata.", "Toggles automatic audition of the selected row."},
      marker = {"Mostra / nasconde marker", "Show / hide markers", "Filtra le righe marker nella lista.", "Filters marker rows in the list."},
      region = {"Mostra / nasconde regioni", "Show / hide regions", "Filtra le righe regione nella lista.", "Filters region rows in the list."},
      row_play = {"Play", "Play", "Riproduce la regione della riga selezionata.", "Plays the region on the selected row."},
      row_stop = {"Stop", "Stop", "Ferma la riproduzione della regione.", "Stops region playback."},
    }
    local function tool(row, col, label, active, kind, key, action)
      local rect = compact_rect(row, col)
      local hit, hovering = draw_compact_tool(rect, label, active, true, clicked, kind)
      if hovering then
        local t = help_text[key]
        compact_hover = { title = t[lang == "en" and 2 or 1], body = t[lang == "en" and 4 or 3] }
      end
      if hit then action() end
    end
    tool(1, 0, "Refresh", false, "refresh", "refresh", function() refresh(true) end)
    local docked = (dock_state & 1) == 1
    tool(1, 1, docked and "Float" or "Dock", docked, "dock", "dock", function()
      local target_dock = docked and 0 or 1
      if gfx.dock then gfx.dock(target_dock); dock_state = gfx.dock(-1) else dock_state = target_dock end
      reaper.SetExtState(EXT_SECTION, "dock_state", tostring(dock_state), true)
    end)
    tool(1, 2, "Scroll", invert_h_scroll, "scroll", "scroll", function()
      invert_h_scroll = not invert_h_scroll
      reaper.SetExtState(EXT_SECTION, "invert_h_scroll", invert_h_scroll and "1" or "0", true)
    end)
    tool(1, 3, "Spazio", false, "gap", "gap", insert_selected_item_gaps)
    tool(2, 0, "Click", auto_play, "play", "play", function()
      auto_play = not auto_play
      reaper.SetExtState(EXT_SECTION, "auto_play", auto_play and "1" or "0", true)
    end)
    tool(2, 1, "Marker", show_markers, "marker", "marker", function()
      show_markers = not show_markers
      reaper.SetExtState(EXT_SECTION, "show_markers", show_markers and "1" or "0", true)
    end)
    tool(2, 2, "Regioni", show_regions, "region", "region", function()
      show_regions = not show_regions
      reaper.SetExtState(EXT_SECTION, "show_regions", show_regions and "1" or "0", true)
    end)
    local list = { x = 8, y = HEADER_H, w = gfx.w - 16, h = gfx.h - HEADER_H - FOOTER_H }
    local table_w = math.max(TABLE_W, list.w)
    local max_h_scroll = math.max(0, table_w - list.w)
    h_scroll = math.max(0, math.min(max_h_scroll, h_scroll))
    local function vx(x) return list.x + x - h_scroll end
    local col_type = 12
    local col_name = 100
    local col_region_name = 128
    local col_start = 640
    local col_end = 760
    local col_len = 880
    local clip_left = list.x + 8
    local clip_right = list.x + list.w - 16
    local function draw_text_clipped(text, x, y, max_w)
      if x >= clip_right or x + 8 < clip_left then return end
      local visible_w = math.max(0, math.min(max_w or 120, clip_right - x))
      if visible_w < 8 then return end
      gfx.x = x
      gfx.y = y
      gfx.drawstr(fit_text(text, visible_w))
    end
    local function draw_rect_clipped(x, y, w, h, filled)
      local x1 = math.max(x, clip_left)
      local x2 = math.min(x + w, clip_right)
      if x2 <= x1 then return end
      gfx.rect(x1, y, x2 - x1, h, filled)
    end
    local function hscroll_step(raw)
      local dir = raw > 0 and 1 or -1
      if invert_h_scroll then dir = -dir end
      return dir * 42
    end
    gfx.set(0.10, 0.10, 0.13, 1)
    gfx.rect(list.x, list.y, list.w, list.h, true)
    gfx.set(0.34, 0.36, 0.42, 1)
    gfx.rect(list.x, list.y, list.w, list.h, false)

    local table_clip = { x = list.x + 1, y = list.y + 1, w = list.w - 2, h = list.h - 20 }
    if gfx.setclip then gfx.setclip(table_clip.x, table_clip.y, table_clip.w, table_clip.h) end

    gfx.setfont(1, "Arial", math.floor(14 * UI_SCALE + 0.5))
    gfx.set(0.64, 0.64, 0.72, 1)
    draw_text_clipped("Tipo", vx(col_type), list.y + math.floor(8 * UI_SCALE), 70)
    draw_text_clipped("Nome", vx(col_name), list.y + math.floor(8 * UI_SCALE), col_start - col_name - 16)
    draw_text_clipped("Start", vx(col_start), list.y + math.floor(8 * UI_SCALE), 94)
    draw_text_clipped("End", vx(col_end), list.y + math.floor(8 * UI_SCALE), 94)
    draw_text_clipped("Durata", vx(col_len), list.y + math.floor(8 * UI_SCALE), 94)

    local max_rows = math.max(1, math.floor((list.h - 48) / ROW_H))
    if #visible == 0 then
      selected = 1
      scroll = 0
    else
      selected = math.max(1, math.min(selected, #visible))
    end
    local over_list = point_in_rect(gfx.mouse_x, gfx.mouse_y, list.x, list.y, list.w, list.h)
    local over_hbar_zone = point_in_rect(gfx.mouse_x, gfx.mouse_y, list.x, list.y + list.h - 22, list.w, 22)
    local scrolled_vertically = false
    if over_list and h_wheel ~= 0 then
      h_scroll = math.max(0, math.min(max_h_scroll, h_scroll - hscroll_step(h_wheel)))
    elseif over_list and wheel ~= 0 then
      local horizontal_wheel = (gfx.mouse_cap & 8) == 8
      if horizontal_wheel or over_hbar_zone then
        h_scroll = math.max(0, math.min(max_h_scroll, h_scroll - hscroll_step(wheel)))
      else
        local step = wheel > 0 and -2 or 2
        if invert_h_scroll then step = -step end
        scroll = math.max(0, math.min(math.max(0, #visible - max_rows), scroll + step))
        scrolled_vertically = true
      end
    end
    if selection_changed then
      if selected <= scroll then scroll = math.max(0, selected - 1) end
      if selected > scroll + max_rows then scroll = selected - max_rows end
    end

    for row_i = 1, math.min(max_rows, #visible) do
      local idx = scroll + row_i
      local row = visible[idx]
      if not row then break end
      local y = list.y + math.floor(34 * UI_SCALE) + ((row_i - 1) * ROW_H)
      local row_rect = { x = list.x + 6, y = y - 4, w = list.w - 12, h = ROW_H }
      local text_y = y + 2
      local hovered = point_in_rect(gfx.mouse_x, gfx.mouse_y, row_rect.x, row_rect.y, row_rect.w, row_rect.h)
      if idx == selected then
        gfx.set(0.12, 0.34, 0.46, 1)
        gfx.rect(row_rect.x, row_rect.y, row_rect.w, row_rect.h, true)
      elseif hovered then
        gfx.set(0.16, 0.16, 0.20, 1)
        gfx.rect(row_rect.x, row_rect.y, row_rect.w, row_rect.h, true)
      end
      if row.kind == "region" and render_selected[row_key(row)] then
        gfx.set(0.95, 0.66, 0.18, 1)
        gfx.rect(row_rect.x + 1, row_rect.y + 1, 4, row_rect.h - 2, true)
        gfx.rect(row_rect.x + 1, row_rect.y + 1, row_rect.w - 2, row_rect.h - 2, false)
      end

      local name_x = vx(row.kind == "region" and col_region_name or col_name)
      local name_w = math.max(80, col_start - (row.kind == "region" and col_region_name or col_name) - 16)
      local in_name_field = point_in_rect(gfx.mouse_x, gfx.mouse_y, name_x - 4, y - 2, name_w, 23)

      if clicked and hovered then
        local now = reaper.time_precise()
        local same = last_click_row == idx and (now - last_click_time) < 0.35
        local previous_selected = selected
        selected = idx
        if previous_selected ~= selected then selection_changed = true end
        if edit_row == idx and in_name_field then
          local cursor = cursor_from_x(edit_text, gfx.mouse_x, name_x)
          if same then
            edit_set_cursor(cursor)
            edit_select_word_at_cursor()
          else
            edit_set_cursor(cursor)
            edit_drag_anchor = cursor
            edit_dragging = true
          end
        else
          if edit_row then commit_edit(visible) end
          local was_render_select = handle_render_selection_click(visible, idx, previous_selected)
          reaper.SetEditCurPos(row.pos, true, false)
          if auto_play then play_entry(row) end
          if same and not was_render_select and row.kind ~= "marker" then
            edit_row = idx
            if row.label == "(senza nome)" or row.label == "(marker senza nome)" then
              edit_text = ""
            else
              edit_text = row.label
            end
            edit_cursor = #edit_text + 1
            edit_sel_start = nil
            edit_sel_end = nil
            edit_drag_anchor = nil
            edit_dragging = false
            edit_undo = {}
            if edit_text ~= "" then edit_set_selection(1, #edit_text + 1) end
          end
        end
        last_click_row = idx
        last_click_time = now
      end

      if edit_row == idx and edit_dragging and mouse_down then
        local cursor = cursor_from_x(edit_text, gfx.mouse_x, name_x)
        edit_set_selection(edit_drag_anchor or cursor, cursor)
      elseif not mouse_down and edit_row == idx then
        edit_dragging = false
      end

      local r, g, b = native_color_to_rgb(row.color)
      if row.kind == "marker" then
        if r then gfx.set(r, g, b, 1) else gfx.set(0.90, 0.42, 0.16, 1) end
        draw_rect_clipped(vx(col_type - 6), y + 2, 25, 15, true)
        if r then gfx.set(math.min(1, r + 0.12), math.min(1, g + 0.12), math.min(1, b + 0.12), 1) else gfx.set(1.0, 0.62, 0.25, 1) end
        draw_rect_clipped(vx(col_type - 6), y + 2, 6, ROW_H - 8, true)
      else
        if r then gfx.set(r, g, b, 1) else gfx.set(0.20, 0.66, 0.86, 1) end
        draw_rect_clipped(vx(col_type - 3), y + 4, 12, 12, true)
      end

      gfx.set(row.kind == "marker" and 1.0 or 0.75, row.kind == "marker" and 0.87 or 0.84, row.kind == "marker" and 0.68 or 0.94, 1)
      local type_label = row.kind == "marker" and (row.synthetic and "--" or "M" .. tostring(row.idx)) or "R" .. tostring(row.idx)
      draw_text_clipped(type_label, vx(col_type + 25), text_y, 64)

      if edit_row == idx then
        gfx.set(0.13, 0.17, 0.24, 1)
        draw_rect_clipped(name_x - 4, y - 2, name_w, 26, true)
        gfx.set(1.0, 0.78, 0.18, 1)
        draw_rect_clipped(name_x - 4, y - 2, name_w, 26, false)
        local sel_a, sel_b = edit_selection_range()
        if sel_a then
          local before_w = gfx.measurestr(edit_text:sub(1, sel_a - 1))
          local text_w = math.min(gfx.measurestr(edit_text:sub(sel_a, sel_b - 1)), name_w - 10)
          gfx.set(0.22, 0.48, 0.70, 0.95)
          draw_rect_clipped(name_x + math.min(before_w, name_w - 10), text_y - 1, text_w + 4, 21, true)
        end
        gfx.set(0.92, 0.92, 0.96, 1)
        draw_text_clipped(edit_text ~= "" and edit_text or "(nome)", name_x, text_y, name_w - 10)
        if not sel_a and math.floor(reaper.time_precise() * 2) % 2 == 0 then
          local tw = gfx.measurestr(edit_text:sub(1, edit_cursor - 1))
          gfx.set(1.0, 0.78, 0.18, 1)
          draw_rect_clipped(name_x + math.min(tw, name_w - 14), text_y - 2, 2, 20, true)
        end
      else
        gfx.setfont(1, "Arial", math.floor((row.kind == "marker" and 15 or 14) * UI_SCALE + 0.5))
        gfx.set(row.kind == "marker" and 0.96 or 0.86, row.kind == "marker" and 0.94 or 0.86, row.kind == "marker" and 0.90 or 0.90, 1)
        draw_text_clipped(row.label, name_x, text_y, name_w - 10)
      end

      gfx.setfont(1, "Arial", math.floor(14 * UI_SCALE + 0.5))
      gfx.set(0.82, 0.82, 0.86, 1)
      draw_text_clipped(format_time(row.pos), vx(col_start), text_y, 106)
      draw_text_clipped(row.kind == "region" and row.end_pos and format_time(row.end_pos) or "-", vx(col_end), text_y, 106)
      draw_text_clipped(row.kind == "region" and row.end_pos and format_time(row.end_pos - row.pos) or "-", vx(col_len), text_y, 106)
    end

    if #visible == 0 then
      gfx.set(0.55, 0.55, 0.62, 1)
      gfx.x = list.x + 14
      gfx.y = list.y + 42
      gfx.drawstr("Nessun marker/regione da mostrare.")
    end

    if gfx.setclip then gfx.setclip(0, 0, gfx.w, gfx.h) end

    if #visible > max_rows then
      local sb_h = math.max(24, (max_rows / #visible) * (list.h - 44))
      local sb_y = list.y + 32 + (scroll / math.max(1, #visible - max_rows)) * ((list.h - 44) - sb_h)
      gfx.set(0.20, 0.20, 0.25, 1)
      gfx.rect(list.x + list.w - 10, list.y + 32, 5, list.h - 44, true)
      gfx.set(0.28, 0.58, 0.74, 1)
      gfx.rect(list.x + list.w - 10, sb_y, 5, sb_h, true)
    end

    if max_h_scroll > 0 then
      local hbar = { x = list.x + 8, y = list.y + list.h - 14, w = list.w - 16, h = 8 }
      local thumb_w = math.max(36, (list.w / table_w) * hbar.w)
      local thumb_x = hbar.x + (h_scroll / max_h_scroll) * (hbar.w - thumb_w)
      local hover_h = point_in_rect(gfx.mouse_x, gfx.mouse_y, hbar.x, hbar.y - 5, hbar.w, hbar.h + 10)
      local hover_thumb = point_in_rect(gfx.mouse_x, gfx.mouse_y, thumb_x, hbar.y - 5, thumb_w, hbar.h + 10)
      if clicked and hover_h then
        h_dragging = true
        h_drag_start_x = gfx.mouse_x
        local track_w = math.max(1, hbar.w - thumb_w)
        if hover_thumb then
          h_drag_start_scroll = h_scroll
        else
          h_scroll = math.max(0, math.min(max_h_scroll, ((gfx.mouse_x - hbar.x - thumb_w * 0.5) / track_w) * max_h_scroll))
          h_drag_start_scroll = h_scroll
        end
      end
      if h_dragging and mouse_down then
        local track_w = math.max(1, hbar.w - thumb_w)
        h_scroll = math.max(0, math.min(max_h_scroll, h_drag_start_scroll + ((gfx.mouse_x - h_drag_start_x) / track_w) * max_h_scroll))
      end
      gfx.set(0.18, 0.18, 0.23, 1)
      gfx.rect(hbar.x, hbar.y, hbar.w, hbar.h, true)
      gfx.set(0.30, 0.58, 0.72, 1)
      gfx.rect(thumb_x, hbar.y, thumb_w, hbar.h, true)
    end

    local selected_row = visible[selected]
    local footer_y = gfx.h - FOOTER_H + 8
    local play_rect = { x = 8, y = footer_y - 3, w = math.floor(48 * UI_SCALE + 0.5), h = math.floor(44 * UI_SCALE + 0.5) }
    local stop_rect = { x = math.floor(62 * UI_SCALE + 0.5), y = footer_y - 3, w = math.floor(48 * UI_SCALE + 0.5), h = math.floor(44 * UI_SCALE + 0.5) }
    if ZP_UI.draw_round_button(play_rect, "play", is_playing, selected_row ~= nil, clicked, { caption = "Play", caption_size = math.floor(11 * UI_SCALE + 0.5) }) then play_entry(selected_row) end
    if ZP_UI.draw_round_button(stop_rect, "stop", false, true, clicked, { caption = "Stop", caption_size = math.floor(11 * UI_SCALE + 0.5) }) then stop_play() end
    if point_in_rect(gfx.mouse_x, gfx.mouse_y, play_rect.x, play_rect.y, play_rect.w, play_rect.h) then
      local t = help_text.row_play; compact_hover = { title = t[lang == "en" and 2 or 1], body = t[lang == "en" and 4 or 3] }
    elseif point_in_rect(gfx.mouse_x, gfx.mouse_y, stop_rect.x, stop_rect.y, stop_rect.w, stop_rect.h) then
      local t = help_text.row_stop; compact_hover = { title = t[lang == "en" and 2 or 1], body = t[lang == "en" and 4 or 3] }
    end

    gfx.setfont(1, "Arial", math.floor(13 * UI_SCALE + 0.5))
    gfx.set(0.84, 0.82, 0.88, 1)
    gfx.x = 154
    gfx.y = footer_y - 2
    gfx.drawstr(selected_row and fit_text((selected_row.kind == "marker" and "Selezionato marker: " or "Selezionata regione: ") .. selected_row.label, gfx.w - 170) or "Nessuna riga selezionata")
    gfx.set(0.58, 0.56, 0.64, 1)
    gfx.x = 154
    gfx.y = footer_y + 18
    local render_count = count_render_selected()
    local native_note = render_count > 0 and (native_render_selection and "native OK" or "Project") or "-"
    gfx.drawstr(fit_text(string.format("Render selezionate: %d (%s)   Totale: %d marker, %d regioni", render_count, native_note, marker_count, region_count), gfx.w - 170))
    local help_y = HEADER_H - 22
    gfx.set(0.025, 0.035, 0.055, 0.98)
    gfx.rect(8, help_y, gfx.w - 16, 18, true)
    gfx.set(0.30, 0.70, 0.88, 1)
    gfx.rect(8, help_y, gfx.w - 16, 18, false)
    gfx.set(0.35, 0.78, 0.94, 1)
    gfx.rect(8, help_y + 2, 3, 14, true)
    gfx.setfont(1, "Arial", math.floor(11 * UI_SCALE + 0.5), compact_hover and "b" or "")
    gfx.set(0.91, 0.95, 0.98, 1)
    local info_text
    if compact_hover then
      info_text = compact_hover.title .. " — " .. compact_hover.body
    elseif lang == "en" then
      info_text = "Hover over a button to read what it does."
    else
      info_text = "Passa il puntatore su un pulsante per leggerne la funzione."
    end
    gfx.x, gfx.y = 18, help_y + 1
    gfx.drawstr(fit_text(info_text, gfx.w - 34))

    gfx.update()
    reaper.defer(loop)
  end

  reaper.defer(loop)
  return true
end

local function main()
  if type(reaper.osara_outputMessage) == "function" then
    run_osara_mode()
    return
  end
  if not draw_project_window() then run_osara_mode() end
end

main()
