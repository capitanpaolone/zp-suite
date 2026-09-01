-- AGGIUNGI NP / NOTE PERSONAGGIO
-- Linea: ZP Paolo Balestri
-- Suite: ZP Studio Suite for REAPER v1.0.5
-- Distribuzione gratuita.
-- Test di fattibilita': per ogni ruolo crea una coppia:
--   voce1
--   BB Note Personaggio - voce1
-- La traccia voce resta una traccia normale. La traccia note e' disarmata,
-- nascosta dal mixer e figlia/folder child della traccia voce.

local SECTION = "RythmoBand_NP"
local KEY_ENABLED = "enabled"
local KEY_LAST_INDEX = "last_index"
local KEY_COLOR_INDEX = "color_index"
local NOTE_PREFIX = "BB Note Personaggio - "
local TEMPLATE_NAME = "RB Voice Track.RTrackTemplate"
local function trim(s)
  local out = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return out
end

local function caps_lock_on()
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

local function native_color(color)
  local r = (color >> 16) & 0xFF
  local g = (color >> 8) & 0xFF
  local b = color & 0xFF
  return reaper.ColorToNative(r, g, b) | 0x1000000
end

local function hsv_to_rgb(h, s, v)
  local i = math.floor(h * 6)
  local f = h * 6 - i
  local p = v * (1 - s)
  local q = v * (1 - f * s)
  local t = v * (1 - (1 - f) * s)
  i = i % 6
  if i == 0 then return v, t, p
  elseif i == 1 then return q, v, p
  elseif i == 2 then return p, v, t
  elseif i == 3 then return p, q, v
  elseif i == 4 then return t, p, v
  end
  return v, p, q
end

local function random_role_color()
  -- Palette variata a rotazione: sembra casuale, ma cambia in modo affidabile a ogni aggiunta.
  local _, saved = reaper.GetProjExtState(0, SECTION, KEY_COLOR_INDEX)
  local idx = (tonumber(saved) or 0) + 1
  reaper.SetProjExtState(0, SECTION, KEY_COLOR_INDEX, tostring(idx))
  local hue = ((idx * 0.61803398875) % 1.0)
  local sat = 0.44 + ((idx * 37) % 18) / 100
  local val = 0.72 + ((idx * 23) % 14) / 100
  local rf, gf, bf = hsv_to_rgb(hue, sat, val)
  local r = math.floor(rf * 255 + 0.5)
  local g = math.floor(gf * 255 + 0.5)
  local b = math.floor(bf * 255 + 0.5)
  return (r << 16) | (g << 8) | b
end

local function get_track_name(track)
  if not track then return "" end
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  return trim(name)
end

local function set_track_name(track, name)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
end

local function find_track_exact(name)
  for i=0, reaper.CountTracks(0)-1 do
    local track = reaper.GetTrack(0, i)
    if get_track_name(track) == name then return track, i end
  end
  return nil, nil
end

local function track_name_exists(name)
  return find_track_exact(name) ~= nil
end

local function unique_track_name(base)
  local candidate = trim(base)
  if candidate == "" then candidate = "voce1" end
  if not track_name_exists(candidate) and not track_name_exists(NOTE_PREFIX .. candidate) then return candidate end
  local n = 2
  while track_name_exists(candidate .. " " .. tostring(n)) or track_name_exists(NOTE_PREFIX .. candidate .. " " .. tostring(n)) do
    n = n + 1
  end
  return candidate .. " " .. tostring(n)
end

local function next_default_role()
  local idx = 1
  local _, saved = reaper.GetProjExtState(0, SECTION, KEY_LAST_INDEX)
  idx = tonumber(saved) or 1
  while track_name_exists("voce" .. tostring(idx)) or track_name_exists(NOTE_PREFIX .. "voce" .. tostring(idx)) do
    idx = idx + 1
  end
  return "voce" .. tostring(idx), idx
end

local function get_track_index(track)
  if not track then return nil end
  local ptr = tostring(track)
  for i=0, reaper.CountTracks(0)-1 do
    local current = reaper.GetTrack(0, i)
    if tostring(current) == ptr then return i end
  end
  return nil
end

local function create_track_at(index, name)
  reaper.InsertTrackAtIndex(index, true)
  local track = reaper.GetTrack(0, index)
  set_track_name(track, name)
  return track
end

local function script_dir()
  if not reaper.get_action_context then return "" end
  local _, script_path = reaper.get_action_context()
  return (script_path or ""):match("^(.*)[/\\][^/\\]+$") or ""
end

local ZP_UI = dofile(script_dir() .. "/ZP_UI.lua")

local function template_paths()
  local paths = {}
  local dir = script_dir()
  if dir ~= "" then paths[#paths + 1] = dir .. "/" .. TEMPLATE_NAME end
  if reaper.GetResourcePath then
    paths[#paths + 1] = reaper.GetResourcePath() .. "/TrackTemplates/" .. TEMPLATE_NAME
  end
  return paths
end

local function read_file(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  return text
end

local function extract_track_chunks(text)
  local chunks = {}
  local current = nil
  local depth = 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    if not current and line:match("^%s*<TRACK") then
      current = {line}
      depth = 1
    elseif current then
      current[#current + 1] = line
      if line:match("^%s*<") then depth = depth + 1 end
      if line:match("^%s*>%s*$") then
        depth = depth - 1
        if depth == 0 then
          chunks[#chunks + 1] = table.concat(current, "\n")
          current = nil
        end
      end
    end
  end
  return chunks
end

local function clean_template_chunk(chunk)
  chunk = chunk:gsub("\n%s*TRACKID%s+%b{}\n", "\n")
  return chunk
end

local function create_tracks_from_template_at(index)
  if not reaper.SetTrackStateChunk then return nil, nil end
  local text = nil
  for _, path in ipairs(template_paths()) do
    text = read_file(path)
    if text then break end
  end
  if not text then return nil, nil end
  local chunks = extract_track_chunks(text)
  if #chunks < 2 then return nil, nil end

  reaper.InsertTrackAtIndex(index, true)
  reaper.InsertTrackAtIndex(index + 1, true)
  local voice_track = reaper.GetTrack(0, index)
  local note_track = reaper.GetTrack(0, index + 1)
  reaper.SetTrackStateChunk(voice_track, clean_template_chunk(chunks[1]), false)
  reaper.SetTrackStateChunk(note_track, clean_template_chunk(chunks[2]), false)
  return voice_track, note_track
end

local function set_rgb_track_color(track, color)
  if track then reaper.SetTrackColor(track, native_color(color)) end
end

local function mirror_track_color(src, dst, fallback)
  if not dst then return end
  local color = src and reaper.GetTrackColor(src) or 0
  if color and color ~= 0 then
    reaper.SetTrackColor(dst, color)
  else
    set_rgb_track_color(dst, fallback or random_role_color())
  end
end

local function parse_roles(text)
  local roles = {}
  text = (text or ""):gsub(";", ","):gsub("\n", ",")
  for token in text:gmatch("[^,]+") do
    local role = trim(token)
    if role ~= "" then roles[#roles + 1] = role end
  end
  if #roles == 0 then roles[#roles + 1] = "voce1" end
  return roles
end

local function point_in_rect(px, py, x, y, w, h)
  return px >= x and px <= x + w and py >= y and py <= y + h
end

local function draw_button(rect, label, active, enabled, clicked, style)
  if style == "ok" then style = "save" end
  return ZP_UI.draw_button(rect, label, active, enabled, clicked, style)
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

local function cursor_from_mouse(text, rect)
  text = tostring(text or "")
  local target_x = gfx.mouse_x - (rect.x + 10)
  if target_x <= 0 then return 1 end
  if target_x >= gfx.measurestr(text) then return #text + 1 end

  local best_pos = 1
  local best_dist = math.huge
  for pos = 1, #text + 1 do
    local w = gfx.measurestr(text:sub(1, pos - 1))
    local dist = math.abs(target_x - w)
    if dist < best_dist then
      best_dist = dist
      best_pos = pos
    end
  end
  return best_pos
end

local function draw_text_input(rect, text, active, clicked, cursor_pos, select_all, placeholder)
  local x, y, w, h = rect.x, rect.y, rect.w, rect.h
  local hover = point_in_rect(gfx.mouse_x, gfx.mouse_y, x, y, w, h)
  if active then
    gfx.set(0.96, 0.97, 1.00, 1)
  elseif hover then
    gfx.set(0.90, 0.92, 0.97, 1)
  else
    gfx.set(0.84, 0.86, 0.92, 1)
  end
  gfx.rect(x, y, w, h, true)
  gfx.set(active and 0.95 or 0.42, active and 0.68 or 0.48, active and 0.18 or 0.62, 1)
  gfx.rect(x, y, w, h, false)

  local empty = text == ""
  local display = empty and (active and "" or (placeholder or "")) or text
  if active and select_all and text ~= "" then
    local sw = gfx.measurestr(text)
    gfx.set(0.18, 0.44, 0.95, 0.55)
    gfx.rect(x + 8, y + 5, math.min(sw + 6, w - 16), h - 10, true)
  end
  if empty then
    gfx.set(0.46, 0.47, 0.52, 1)
  elseif active and select_all then
    gfx.set(1.0, 1.0, 1.0, 1)
  else
    gfx.set(0.04, 0.05, 0.08, 1)
  end
  gfx.x = x + 10
  gfx.y = y + 9
  gfx.drawstr(fit_text(display, w - 20))

  if active and not select_all and math.floor(reaper.time_precise() * 2) % 2 == 0 then
    cursor_pos = math.max(1, math.min(cursor_pos or (#text + 1), #text + 1))
    local tw = gfx.measurestr(text:sub(1, cursor_pos - 1))
    gfx.set(0.04, 0.05, 0.08, 1)
    gfx.rect(x + 11 + tw, y + 7, 2, h - 14, true)
  end

  return clicked and hover
end

local function prompt_roles_visual(default_role, on_done)
  local text = default_role or "voce1"
  local active_input = true
  local input_cursor = #text + 1
  local input_select_all = text ~= ""
  local input_last_click_time = 0
  local ok = false
  local last_mouse_down = false
  gfx.init("ZP Studio Suite v1.0.5 - Actor / Note", 660, 310, 0, 180, 180)

  local function close_dialog(result)
    ok = result and true or false
    gfx.quit()
    if on_done then on_done(ok, text) end
  end

  local function loop()
    local char = gfx.getchar()
    if char < 0 then close_dialog(false); return end
    local mouse_down = (gfx.mouse_cap & 1) == 1
    local clicked = mouse_down and not last_mouse_down
    last_mouse_down = mouse_down

    if clicked then
      local input_rect = { x = 34, y = 126, w = 592, h = 34 }
      if point_in_rect(gfx.mouse_x, gfx.mouse_y, input_rect.x, input_rect.y, input_rect.w, input_rect.h) then
        local now = reaper.time_precise()
        if active_input and (now - input_last_click_time) < 0.35 then
          input_select_all = true
          input_cursor = #text + 1
        else
          input_select_all = false
          input_cursor = cursor_from_mouse(text, input_rect)
        end
        input_last_click_time = now
        active_input = true
      else
        active_input = false
        input_select_all = false
      end
    end

    if active_input and char > 0 then
      if char == 27 then
        close_dialog(false)
        return
      elseif char == 13 then
        close_dialog(true)
        return
      elseif char == 8 then
        if input_select_all then
          text = ""
          input_cursor = 1
          input_select_all = false
        elseif input_cursor > 1 then
          text = text:sub(1, input_cursor - 2) .. text:sub(input_cursor)
          input_cursor = input_cursor - 1
        end
      elseif char == 6579564 then
        if input_select_all then
          text = ""
          input_cursor = 1
          input_select_all = false
        elseif input_cursor <= #text then
          text = text:sub(1, input_cursor - 1) .. text:sub(input_cursor + 1)
        end
      elseif char == 1818584692 then
        input_cursor = math.max(1, input_cursor - 1)
        input_select_all = false
      elseif char == 1919379572 then
        input_cursor = math.min(#text + 1, input_cursor + 1)
        input_select_all = false
      elseif char == 1752132965 then
        input_cursor = 1
        input_select_all = false
      elseif char == 6647396 then
        input_cursor = #text + 1
        input_select_all = false
      elseif char == 1 then
        input_select_all = true
        input_cursor = #text + 1
      elseif char == 22 and reaper.CF_GetClipboard then
        local _, clip = reaper.CF_GetClipboard("")
        if input_select_all then
          text = ""
          input_cursor = 1
          input_select_all = false
        end
        local paste = (clip or ""):gsub("[\r\n;]+", ", ")
        text = text:sub(1, input_cursor - 1) .. paste .. text:sub(input_cursor)
        input_cursor = input_cursor + #paste
      elseif char >= 32 and char <= 1114111 then
        if (caps_lock_on() or (gfx.mouse_cap & 8) == 8) and char >= 97 and char <= 122 then
          char = char - 32
        end
        local ok_char, typed = false, nil
        if utf8 and utf8.char then ok_char, typed = pcall(utf8.char, char) end
        if not ok_char and char <= 255 then typed = string.char(char) end
        if typed and typed ~= "\n" and typed ~= "\r" and #text < 240 then
          if input_select_all then
            text = ""
            input_cursor = 1
            input_select_all = false
          end
          text = text:sub(1, input_cursor - 1) .. typed .. text:sub(input_cursor)
          input_cursor = input_cursor + #typed
        end
      end
    elseif char == 27 then
      close_dialog(false)
      return
    end

    ZP_UI.fill_background()
    gfx.set(0.10, 0.42, 0.48, 1)
    gfx.rect(32, 26, 34, 34, true)
    gfx.set(0.92, 0.88, 0.70, 1)
    gfx.circle(49, 36, 6, false)
    gfx.line(49, 42, 49, 53)
    gfx.line(41, 46, 57, 46)
    gfx.setfont(1, "Arial", 22)
    gfx.set(0.92, 0.88, 0.78, 1)
    gfx.x = 76
    gfx.y = 28
    gfx.drawstr("Aggiungi Actor / Note")
    gfx.setfont(1, "Arial", 13)
    gfx.set(0.56, 0.72, 0.86, 1)
    gfx.x = 78
    gfx.y = 58
    gfx.drawstr("ZP Studio Suite v1.0.5 - Paolo Balestri")
    gfx.set(0.72, 0.70, 0.78, 1)
    gfx.x = 34
    gfx.y = 84
    gfx.drawstr("Crea una traccia voce e la relativa traccia note personaggio per il gobbo.")
    ZP_UI.draw_help_button({ x = gfx.w - 54, y = 18, w = 34, h = 28 }, clicked, "zp-regia-ruoli")
    gfx.x = 34
    gfx.y = 104
    gfx.drawstr("Puoi inserire piu' ruoli separati da virgola.")

    gfx.set(0.72, 0.70, 0.78, 1)
    gfx.x = 34
    gfx.y = 112
    gfx.drawstr("Ruolo / ruoli")
    draw_text_input({ x = 34, y = 126, w = 592, h = 34 }, text, active_input, false, input_cursor, input_select_all, "voce1")

    gfx.set(0.66, 0.65, 0.70, 1)
    gfx.x = 34
    gfx.y = 176
    gfx.drawstr("Esempio: Mario, Laura, Narratore")

    if draw_button({x = 390, y = 238, w = 112, h = 36}, "Crea", false, trim(text) ~= "", clicked, "ok") then
      close_dialog(true)
      return
    end
    if draw_button({x = 514, y = 238, w = 112, h = 36}, "Annulla", false, true, clicked) then
      close_dialog(false)
      return
    end
    gfx.update()
    reaper.defer(loop)
  end

  reaper.defer(loop)
end

local function tag_track(track, value)
  if track then reaper.GetSetMediaTrackInfo_String(track, "P_EXT:RythmoBand_NP", value or "1", true) end
end

local function set_track_tcp_visible(track, visible)
  if not track then return end
  reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", visible and 1 or 0)
end

local function set_track_mixer_visible(track, visible)
  if not track then return end
  reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", visible and 1 or 0)
end

local function remove_all_track_sends(track)
  if not track or not reaper.RemoveTrackSend then return end
  local count = 0
  if reaper.GetTrackNumSends then
    count = reaper.GetTrackNumSends(track, 0) or 0
  elseif reaper.CountTrackSends then
    count = reaper.CountTrackSends(track, 0) or 0
  end
  for i = count - 1, 0, -1 do
    reaper.RemoveTrackSend(track, 0, i)
  end
end

local function neutralize_note_track(track)
  if not track then return end
  reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 0)
  reaper.SetMediaTrackInfo_Value(track, "I_RECMON", 0)
  reaper.SetMediaTrackInfo_Value(track, "I_RECINPUT", -1)
  reaper.SetMediaTrackInfo_Value(track, "I_RECMODE", 0)
  reaper.SetMediaTrackInfo_Value(track, "I_SOLO", 0)
  reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 0)
  reaper.SetMediaTrackInfo_Value(track, "B_PHASE", 0)
  reaper.SetMediaTrackInfo_Value(track, "B_MAINSEND", 0)
  reaper.SetMediaTrackInfo_Value(track, "I_AUTOMODE", 0)
  reaper.SetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE", 28)
  remove_all_track_sends(track)
  set_track_mixer_visible(track, false)
  tag_track(track, "person_note")
end

local function prepare_voice_track(track, role_name, color)
  if not track then return end
  set_track_name(track, role_name)
  set_rgb_track_color(track, color)
  set_track_tcp_visible(track, true)
  set_track_mixer_visible(track, true)
  reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 1)
  reaper.SetMediaTrackInfo_Value(track, "I_FOLDERCOMPACT", 0)
  -- Usa il mono hardware input 1 per le tracce voce create da Actor / Note.
  reaper.SetMediaTrackInfo_Value(track, "I_RECINPUT", 0)
  tag_track(track, "voice")
end

local function repair_existing_np_pairs()
  for i=0, reaper.CountTracks(0)-1 do
    local note_track = reaper.GetTrack(0, i)
    local note_name = get_track_name(note_track)
    if note_name:find(NOTE_PREFIX, 1, true) == 1 then
      local role_name = trim(note_name:sub(#NOTE_PREFIX + 1))
      neutralize_note_track(note_track)
      set_track_tcp_visible(note_track, true)
      reaper.SetMediaTrackInfo_Value(note_track, "I_FOLDERDEPTH", -1)

      local previous = i > 0 and reaper.GetTrack(0, i - 1) or nil
      if previous and get_track_name(previous) == role_name then
        reaper.SetMediaTrackInfo_Value(previous, "I_FOLDERDEPTH", 1)
        reaper.SetMediaTrackInfo_Value(previous, "I_FOLDERCOMPACT", 0)
        tag_track(previous, "voice")
        mirror_track_color(previous, note_track, random_role_color())
      end
    end
  end
end

local function folder_depth_before_index(index)
  local depth = 0
  for i=0, math.min(index, reaper.CountTracks(0)) - 1 do
    local track = reaper.GetTrack(0, i)
    depth = depth + math.floor(reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") or 0)
  end
  return depth
end

local function safe_top_level_insert_index()
  local count = reaper.CountTracks(0)
  if folder_depth_before_index(count) == 0 then return count end

  local depth = 0
  local last_top_level_boundary = count
  for i=0, count-1 do
    if depth == 0 then last_top_level_boundary = i end
    local track = reaper.GetTrack(0, i)
    depth = depth + math.floor(reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") or 0)
  end
  return last_top_level_boundary
end

local function ensure_role_pair(role_name, role_index)
  role_name = unique_track_name(role_name)
  local voice_idx = safe_top_level_insert_index()
  local voice_track, note_track = create_tracks_from_template_at(voice_idx)
  if not voice_track or not note_track then
    voice_track = create_track_at(voice_idx, role_name)
  end

  local color = random_role_color()
  prepare_voice_track(voice_track, role_name, color)

  local note_name = NOTE_PREFIX .. role_name
  voice_idx = get_track_index(voice_track) or voice_idx
  if not note_track then
    note_track = create_track_at(voice_idx + 1, note_name)
  end

  set_track_name(note_track, note_name)
  mirror_track_color(voice_track, note_track, color)
  neutralize_note_track(note_track)
  set_track_tcp_visible(note_track, true)
  reaper.SetMediaTrackInfo_Value(note_track, "I_FOLDERDEPTH", -1)

  return voice_track, note_track
end

local function for_each_np_note_track(fn)
  for i=0, reaper.CountTracks(0)-1 do
    local track = reaper.GetTrack(0, i)
    local _, ext = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:RythmoBand_NP", "", false)
    local name = get_track_name(track)
    if ext == "person_note" or name:find(NOTE_PREFIX, 1, true) == 1 then fn(track) end
  end
end

local function get_enabled()
  local ok, value = reaper.GetProjExtState(0, SECTION, KEY_ENABLED)
  return ok == 1 and value == "1"
end

local function set_enabled(enabled)
  reaper.SetProjExtState(0, SECTION, KEY_ENABLED, enabled and "1" or "0")
end

local function save_next_index_from_roles(roles)
  local max_idx = 0
  for _, role in ipairs(roles) do
    local n = role:match("^voce(%d+)$")
    if n then max_idx = math.max(max_idx, tonumber(n) or 0) end
  end
  if max_idx > 0 then reaper.SetProjExtState(0, SECTION, KEY_LAST_INDEX, tostring(max_idx + 1)) end
end

local function refresh()
  if reaper.TrackList_AdjustWindows then reaper.TrackList_AdjustWindows(false) end
  reaper.UpdateArrange()
end

local function create_roles_from_text(roles_text)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local roles = parse_roles(roles_text)
  local created_roles = {}
  repair_existing_np_pairs()
  for i, role_name in ipairs(roles) do
    local voice_track = ensure_role_pair(role_name, i)
    created_roles[#created_roles + 1] = get_track_name(voice_track)
  end
  set_enabled(true)
  save_next_index_from_roles(created_roles)

  reaper.PreventUIRefresh(-1)
  refresh()
  reaper.Undo_EndBlock("ZP Studio Suite aggiungi actor", -1)

  reaper.ShowMessageBox(
    "NP aggiunto.\n\nPer ogni ruolo ho preparato:\n" ..
    "  voce\n  " .. NOTE_PREFIX .. "voce\n\n" ..
    "Ruoli creati: " .. table.concat(created_roles, ", ") ..
    "\n\nLe tracce BB Note Personaggio sono figlie della relativa voce, visibili nel TCP, nascoste dal mixer e disarmate.",
    "ZP Studio Suite - Actor",
    0
  )
end

local function main()
  local default_role = next_default_role()
  prompt_roles_visual(default_role, function(ok, roles_text)
    if ok then create_roles_from_text(roles_text) end
  end)
end

main()
