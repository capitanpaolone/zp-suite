-- GESTIONE SRT RYTHMOBAND
-- Linea: ZP Paolo Balestri
-- Suite: ZP Studio Suite for REAPER v1.0.5
-- Distribuzione gratuita.
-- Launcher visuale. La finestra raccoglie le scelte, si chiude, poi lancia
-- 05_worker_Gestione_SRT.lua che fa il lavoro pesante su file e timeline.

local SCRIPT_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "")
local WORKER_PATH = SCRIPT_DIR .. "05_worker_Gestione_SRT.lua"
local ZP_UI = dofile(SCRIPT_DIR .. "ZP_UI.lua")

local SUBTITLE_TRACK_NAME = "Rythmo Band Testi"
local SRT_TEMPLATE_NAME = "SRT Track.RTrackTemplate"
local COLOR_SUBS = 0x2AA6D6


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

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function osara_active()
  return type(reaper.osara_outputMessage) == "function"
end

local function ext_lower(path)
  return (path:match("%.([^%.\\/]+)$") or ""):lower()
end

local function is_video(path)
  local ext = ext_lower(path)
  return ext == "mp4" or ext == "mov" or ext == "m4v" or ext == "avi" or ext == "mkv"
end

local function source_file_from_item(item)
  local take = reaper.GetActiveTake(item)
  if not take then return nil end
  local source = reaper.GetMediaItemTake_Source(take)
  if not source then return nil end
  local path = reaper.GetMediaSourceFileName(source, "")
  path = trim(path)
  if path == "" then return nil end
  return path
end

local function collect_video_items()
  local out = {}
  for t = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, t)
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      local path = source_file_from_item(item)
      if path and is_video(path) then table.insert(out, item) end
    end
  end
  return out
end

local function collect_selected_video_items()
  local out = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local path = source_file_from_item(item)
    if path and is_video(path) then table.insert(out, item) end
  end
  return out
end

local function region_at_position(pos)
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local total = num_markers + num_regions
  for i = 0, total - 1 do
    local ok, is_region, rgn_pos, rgn_end, name = reaper.EnumProjectMarkers(i)
    if ok and is_region and pos >= rgn_pos and pos < rgn_end then
      return trim(name or "") ~= "" and trim(name or "") or "senza nome"
    end
  end
  return nil
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

local function draw_srt_icon(x, y, size)
  gfx.set(0.10, 0.42, 0.48, 1)
  gfx.rect(x, y, size, size, true)
  gfx.set(0.05, 0.18, 0.22, 1)
  gfx.rect(x, y, size, size, false)
  gfx.set(0.92, 0.88, 0.70, 1)
  gfx.circle(x + size * 0.45, y + size * 0.50, size * 0.24, false)
  gfx.triangle(x + size * 0.66, y + size * 0.30, x + size * 0.66, y + size * 0.53, x + size * 0.86, y + size * 0.42, true)
  gfx.triangle(x + size * 0.24, y + size * 0.70, x + size * 0.24, y + size * 0.47, x + size * 0.04, y + size * 0.58, true)
end

local function draw_input(rect, text, active, clicked, cursor_pos, select_all)
  local x, y, w, h = rect.x, rect.y, rect.w, rect.h
  local hover = point_in_rect(gfx.mouse_x, gfx.mouse_y, x, y, w, h)
  gfx.set(active and 0.18 or (hover and 0.15 or 0.11), active and 0.22 or 0.14, active and 0.32 or 0.20, 1)
  gfx.rect(x, y, w, h, true)
  gfx.set(active and 0.86 or 0.42, active and 0.70 or 0.39, active and 0.22 or 0.55, 1)
  gfx.rect(x, y, w, h, false)
  local display = text ~= "" and text or "REF"
  if active and select_all and text ~= "" then
    local sw = gfx.measurestr(text)
    gfx.set(0.18, 0.44, 0.95, 0.55)
    gfx.rect(x + 8, y + 5, math.min(sw + 6, w - 16), h - 10, true)
  end
  gfx.set(0.92, 0.90, 0.95, 1)
  gfx.x = x + 10
  gfx.y = y + 9
  gfx.drawstr(fit_text(display, w - 20))
  if active and not select_all and math.floor(reaper.time_precise() * 2) % 2 == 0 then
    cursor_pos = math.max(1, math.min(cursor_pos or (#text + 1), #text + 1))
    local tw = gfx.measurestr(text:sub(1, cursor_pos - 1))
    gfx.set(1.0, 0.78, 0.18, 1)
    gfx.rect(x + 11 + tw, y + 7, 2, h - 14, true)
  end
  return clicked and hover
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


local function native_color(rgb)
  local r = rgb & 0xFF
  local g = (rgb >> 8) & 0xFF
  local b = (rgb >> 16) & 0xFF
  return 0x1000000 | reaper.ColorToNative(r, g, b)
end

local function set_track_color(track, color)
  if track then reaper.SetTrackColor(track, native_color(color)) end
end

local function read_file(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local body = file:read("*a")
  file:close()
  return body
end

local function extract_first_track_chunk(body)
  local current = nil
  local depth = 0
  for line in ((body or "") .. "\n"):gmatch("([^\n]*)\n") do
    if not current and line:match("^%s*<TRACK") then
      current = { line }
      depth = 1
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

local function clean_template_chunk(chunk)
  return (chunk or ""):gsub("\n%s*TRACKID%s+%b{}\n", "\n")
end

local function find_track_exact(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if track_name == name then return track end
  end
  return nil
end

local function create_plain_track(name)
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local track = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
  set_track_color(track, COLOR_SUBS)
  return track
end

local function create_subtitle_track(name)
  if not reaper.SetTrackStateChunk then return create_plain_track(name) end
  local body = read_file(SCRIPT_DIR .. SRT_TEMPLATE_NAME)
  local chunk = body and extract_first_track_chunk(body) or nil
  if not chunk then return create_plain_track(name) end
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local track = reaper.GetTrack(0, idx)
  reaper.SetTrackStateChunk(track, clean_template_chunk(chunk), false)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
  set_track_color(track, COLOR_SUBS)
  return track
end

local function setup_subtitle_track(track)
  if not track then return end
  reaper.SetMediaTrackInfo_Value(track, "B_FREEMODE", 1)
  reaper.SetMediaTrackInfo_Value(track, "I_FREEMODE", 1)
  reaper.SetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE", 120)
  set_track_color(track, COLOR_SUBS)
end

local function get_or_create_subtitle_track()
  local track = find_track_exact(SUBTITLE_TRACK_NAME)
  if track then return track, false end
  return create_subtitle_track(SUBTITLE_TRACK_NAME), true
end

local function add_manual_text_item(track, text, start_pos, length)
  local item = reaper.AddMediaItemToTrack(track)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", start_pos)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", math.max(0.2, length or 5.0))
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", native_color(COLOR_SUBS))
  text = trim(text or "")
  if text == "" then text = "TESTO" end
  reaper.GetSetMediaItemInfo_String(item, "P_NAME", text:gsub("%s+", " "), true)
  reaper.GetSetMediaItemInfo_String(item, "P_NOTES", text, true)
  return item
end

local function create_empty_gobbo_track(save_after)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local track, created = get_or_create_subtitle_track()
  setup_subtitle_track(track)
  local pos = reaper.GetCursorPosition()
  local item = add_manual_text_item(track, "TESTO", pos, 5.0)

  reaper.Main_OnCommand(40289, 0) -- Item: Unselect all items
  if item then reaper.SetMediaItemSelected(item, true) end
  if track then reaper.SetOnlyTrackSelected(track) end
  if reaper.TrackList_AdjustWindows then reaper.TrackList_AdjustWindows(false) end
  reaper.UpdateArrange()

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ZP Studio Suite aggiungi traccia gobbo vuota", -1)
  if save_after then reaper.Main_SaveProject(0, false) end

  local msg = (created and "Traccia gobbo creata." or "Traccia gobbo gia' presente, riusata.") ..
    "\n\nTraccia: " .. SUBTITLE_TRACK_NAME ..
    "\nCreato item TESTO alla playhead." ..
    "\nDurata: 5 sec" ..
    (save_after and "\nProgetto salvato." or "\nProgetto non salvato.")
  reaper.ShowMessageBox(msg, "ZP Studio Suite", 0)
end

local function run_worker(config)
  if not file_exists(WORKER_PATH) then
    reaper.ShowMessageBox("Worker Gestione SRT non trovato:\n" .. WORKER_PATH, "ZP Studio Suite", 0)
    return
  end
  _G.RYTHMOBAND_SRT_CONFIG = config
  local ok, err = pcall(dofile, WORKER_PATH)
  _G.RYTHMOBAND_SRT_CONFIG = nil
  if not ok then
    reaper.ShowMessageBox("Errore Gestione SRT:\n\n" .. tostring(err), "ZP Studio Suite", 0)
  end
end

local function open_srt_bridge()
  if not gfx or not gfx.init then return false end

  local selected_op = nil
  local flag_overlaps = true
  local save_after = false
  local reference_suffix = "REF"
  local suffix_active = false
  local suffix_cursor = #reference_suffix + 1
  local suffix_select_all = false
  local suffix_last_click_time = 0
  local last_mouse_down = false

  gfx.init("ZP Studio Suite v1.0.5 - Gestione SRT", 720, 430)
  gfx.setfont(1, "Arial", 16)

  local function loop()
    local ch = gfx.getchar()
    if ch < 0 then gfx.quit() return end
    if ch == 27 then
      if suffix_active then suffix_active = false else gfx.quit() return end
    elseif suffix_active and ch == 8 then
      if suffix_select_all then
        reference_suffix = ""
        suffix_cursor = 1
        suffix_select_all = false
      elseif suffix_cursor > 1 then
        reference_suffix = reference_suffix:sub(1, suffix_cursor - 2) .. reference_suffix:sub(suffix_cursor)
        suffix_cursor = suffix_cursor - 1
      end
    elseif suffix_active and ch == 6579564 then
      if suffix_select_all then
        reference_suffix = ""
        suffix_cursor = 1
        suffix_select_all = false
      elseif suffix_cursor <= #reference_suffix then
        reference_suffix = reference_suffix:sub(1, suffix_cursor - 1) .. reference_suffix:sub(suffix_cursor + 1)
      end
    elseif suffix_active and ch == 1818584692 then
      suffix_cursor = math.max(1, suffix_cursor - 1)
      suffix_select_all = false
    elseif suffix_active and ch == 1919379572 then
      suffix_cursor = math.min(#reference_suffix + 1, suffix_cursor + 1)
      suffix_select_all = false
    elseif suffix_active and ch == 1752132965 then
      suffix_cursor = 1
      suffix_select_all = false
    elseif suffix_active and ch == 6647396 then
      suffix_cursor = #reference_suffix + 1
      suffix_select_all = false
    elseif suffix_active and ch >= 32 and ch <= 1114111 then
      if (caps_lock_on() or (gfx.mouse_cap & 8) == 8) and ch >= 97 and ch <= 122 then
        ch = ch - 32
      end
      local ok, typed = false, nil
      if utf8 and utf8.char then ok, typed = pcall(utf8.char, ch) end
      if not ok and ch <= 255 then typed = string.char(ch) end
      if typed and #reference_suffix < 24 and typed:match("[^/\\:%*%?\"<>|,]") then
        if suffix_select_all then
          reference_suffix = ""
          suffix_cursor = 1
          suffix_select_all = false
        end
        reference_suffix = reference_suffix:sub(1, suffix_cursor - 1) .. typed .. reference_suffix:sub(suffix_cursor)
        suffix_cursor = suffix_cursor + #typed
      end
    end

    local mouse_down = (gfx.mouse_cap & 1) == 1
    local clicked = mouse_down and not last_mouse_down
    last_mouse_down = mouse_down

    local selected_videos = collect_selected_video_items()
    local all_videos = collect_video_items()
    local cursor_region = region_at_position(reaper.GetCursorPosition())
    local help_text = ""

    local operations = {
      {
        id = 1,
        mode = "selected",
        operation = "replace",
        label = "Sostituisci SRT - video selezionati (" .. #selected_videos .. ")",
        enabled = #selected_videos > 0,
        help = "Sostituisce il testo della traccia principale solo dentro i blocchi dei video selezionati. Chiede manualmente quale SRT usare."
      },
      {
        id = 2,
        mode = "selected",
        operation = "reference",
        label = "Aggiungi lingua/reference (" .. #selected_videos .. " video selezionati)",
        enabled = #selected_videos == 1,
        help = "Aggiunge un flusso di riferimento, per esempio ENG o ORIG, senza toccare la traccia principale."
      },
      {
        id = 3,
        mode = "region",
        operation = "replace",
        label = "Sostituisci SRT regione sotto playhead" .. (cursor_region and (" - " .. cursor_region) or " (nessuna regione)"),
        enabled = cursor_region ~= nil,
        help = "Sostituisce i sottotitoli solo nell'intervallo della regione sotto la playhead. Utile se lavori per capitoli."
      },
      {
        id = 4,
        mode = "all",
        operation = "batch",
        label = "Batch omonimi - tutti i video (" .. #all_videos .. ")",
        enabled = #all_videos > 0,
        help = "Aggiorna tutti i video trovando automaticamente gli SRT con lo stesso nome nella cartella di ciascun video."
      },
      {
        id = 5,
        mode = "gobbo_empty",
        operation = "create_empty_gobbo_track",
        label = "Aggiungi traccia gobbo vuota",
        enabled = true,
        help = "Crea o riusa la traccia Rythmo Band Testi e aggiunge un item TESTO alla playhead, pronto per brevi testi statici."
      }
    }

    if not selected_op then
      if #selected_videos > 0 then selected_op = 1
      elseif cursor_region then selected_op = 3
      elseif #all_videos > 0 then selected_op = 4
      else selected_op = 5 end
    end
    local selected_valid = false
    for _, op in ipairs(operations) do
      if selected_op == op.id and op.enabled then selected_valid = true end
    end
    if not selected_valid then selected_op = nil end

    ZP_UI.fill_background()
    ZP_UI.draw_header({
      fallback_icon = draw_srt_icon,
      title = "Gestione SRT",
      description = "Scegli cosa aggiornare. La finestra si chiude prima di aprire file e modificare la timeline."
    })

    ZP_UI.draw_help_button({ x = gfx.w - 54, y = 18, w = 34, h = 28 }, clicked, "zp-gestione-srt")

    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x = 22
    gfx.y = 96
    gfx.drawstr("Operazione")

    for i, op in ipairs(operations) do
      local rect = { x = 22, y = 112 + ((i - 1) * 44), w = 470, h = 36 }
      if point_in_rect(gfx.mouse_x, gfx.mouse_y, rect.x, rect.y, rect.w, rect.h) then help_text = op.help end
      if draw_button(rect, op.label, selected_op == op.id, op.enabled, clicked, "tab") then selected_op = op.id end
    end

    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x = 524
    gfx.y = 88
    gfx.drawstr("Opzioni")

    local overlap_rect = { x = 524, y = 112, w = 168, h = 36 }
    if point_in_rect(gfx.mouse_x, gfx.mouse_y, overlap_rect.x, overlap_rect.y, overlap_rect.w, overlap_rect.h) then
      help_text = "Colora in rosso le cue che si sovrappongono e le mette nella corsia bassa della traccia SRT."
    end
    if draw_button(overlap_rect, "Overlap in rosso", flag_overlaps, true, clicked, "tab") then
      flag_overlaps = not flag_overlaps
    end
    local save_rect = { x = 524, y = 156, w = 168, h = 36 }
    if point_in_rect(gfx.mouse_x, gfx.mouse_y, save_rect.x, save_rect.y, save_rect.w, save_rect.h) then
      help_text = "Salva il progetto REAPER alla fine dell'operazione, dopo backup e import."
    end
    if draw_button(save_rect, "Salva progetto dopo", save_after, true, clicked, "tab") then
      save_after = not save_after
    end

    if selected_op == 2 then
      gfx.set(0.86, 0.82, 0.70, 1)
      gfx.x = 524
      gfx.y = 212
      gfx.drawstr("Suffisso traccia")
      local input_rect = { x = 524, y = 236, w = 168, h = 36 }
      if point_in_rect(gfx.mouse_x, gfx.mouse_y, input_rect.x, input_rect.y, input_rect.w, input_rect.h) then
        help_text = "Nome breve aggiunto alla traccia reference: REF crea una traccia testi reference. Doppio click seleziona tutto."
      end
      if draw_input(input_rect, reference_suffix, suffix_active, clicked, suffix_cursor, suffix_select_all) then
        local now = reaper.time_precise()
        if suffix_active and (now - suffix_last_click_time) < 0.35 then
          suffix_select_all = true
          suffix_cursor = #reference_suffix + 1
        else
          suffix_select_all = false
          suffix_cursor = cursor_from_mouse(reference_suffix, input_rect)
        end
        suffix_last_click_time = now
        suffix_active = true
      elseif clicked and not point_in_rect(gfx.mouse_x, gfx.mouse_y, input_rect.x, input_rect.y, input_rect.w, input_rect.h) then
        suffix_active = false
        suffix_select_all = false
      end
      gfx.set(0.68, 0.66, 0.74, 1)
      gfx.x = 524
      gfx.y = 278
      gfx.drawstr("Es. REF, ENG, ORIG")
    elseif clicked then
      suffix_active = false
      suffix_select_all = false
    end

    local chosen = nil
    for _, op in ipairs(operations) do
      if op.id == selected_op and op.enabled then chosen = op end
    end
    if help_text == "" and chosen then help_text = chosen.help end
    if help_text == "" then
      help_text = "Gli SRT scelti vengono copiati nel progetto e gli item vecchi finiscono su una traccia BKP."
    end

    gfx.set(0.74, 0.72, 0.80, 1)
    gfx.x = 22
    gfx.y = 336
    gfx.drawstr(fit_text(help_text, gfx.w - 44))

    if draw_button({ x = 430, y = 378, w = 124, h = 38 }, "Procedi", false, chosen ~= nil, clicked, "play") then
      local config = {
        mode = chosen.mode,
        operation = chosen.operation,
        flag_overlaps = flag_overlaps,
        save_after = save_after,
        reference_suffix = reference_suffix
      }
      gfx.quit()
      if chosen.operation == "create_empty_gobbo_track" then
        create_empty_gobbo_track(save_after)
      else
        run_worker(config)
      end
      return
    end
    if draw_button({ x = 566, y = 378, w = 124, h = 38 }, "Annulla", false, true, clicked) then
      gfx.quit()
      return
    end

    gfx.update()
    reaper.defer(loop)
  end

  reaper.defer(loop)
  return true
end

local function main()
  if _G.RYTHMOBAND_UPDATE_MODE or osara_active() then
    run_worker(nil)
    return
  end
  if not open_srt_bridge() then run_worker(nil) end
end

main()
