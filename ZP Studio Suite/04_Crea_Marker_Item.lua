-- @noindex

-- CREA MARKER ITEM - LAUNCHER
-- Linea: ZP Paolo Balestri
-- Suite: ZP Studio Suite for REAPER v1.0.5
-- Distribuzione gratuita.
-- Finestra ponte moderna. Raccoglie le opzioni, si chiude, poi lancia
-- 04_worker_Crea_Marker_Item.lua che crea realmente i marker.
--
-- Seconda scheda "Fissa negli item": fa il lavoro del 14 (marker di progetto ->
-- marker dell'item) senza domande bloccanti; la finestra resta aperta e mostra l'esito.

local SCRIPT_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "")
local WORKER_PATH = SCRIPT_DIR .. "04_worker_Crea_Marker_Item.lua"
local FIX_PATH = SCRIPT_DIR .. "14_Marker_da_Timeline_a_Item.lua"
local ZP_UI = dofile(SCRIPT_DIR .. "ZP_UI.lua")

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function osara_active()
  return type(reaper.osara_outputMessage) == "function"
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

local function draw_button(rect, label, active, enabled, clicked, style)
  return ZP_UI.draw_button(rect, label, active, enabled, clicked, style)
end

local function draw_input(rect, text, active, clicked, cursor_pos, select_all)
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
  local placeholder = text == ""
  local display = placeholder and (active and "" or "NOME") or text
  if active and select_all and text ~= "" then
    local sw = gfx.measurestr(text)
    gfx.set(0.18, 0.44, 0.95, 0.55)
    gfx.rect(x + 8, y + 5, math.min(sw + 6, w - 16), h - 10, true)
  end
  if placeholder then
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

local function run_worker(config)
  if not file_exists(WORKER_PATH) then
    reaper.ShowMessageBox("Worker marker non trovato:\n" .. WORKER_PATH, "ZP Studio Suite", 0)
    return
  end
  _G.RYTHMOBAND_MARKER_CONFIG = config
  local ok, err = pcall(dofile, WORKER_PATH)
  _G.RYTHMOBAND_MARKER_CONFIG = nil
  if not ok then
    reaper.ShowMessageBox("Errore marker:\n\n" .. tostring(err), "ZP Studio Suite", 0)
  end
end

local function open_marker_bridge()
  if not gfx or not gfx.init then return false end

  local tab = 1                 -- 1 crea marker dagli item, 2 fissa i marker negli item (14)
  local fix_all = true
  local fix_remove = false
  local fix_status = ""
  local fix_info_t, fix_items, fix_markers = -1, 0, 0
  local mode = 2
  local base_name = "NOME"
  local add_video_tc = true
  local input_active = false
  local input_cursor = #base_name + 1
  local input_select_all = false
  local input_last_click_time = 0
  local last_mouse_down = false

  -- toolbar: icona accesa finche' la finestra e' aperta; un altro clic sull'icona la chiude (REAPER 7.03+)
  if reaper.set_action_options then reaper.set_action_options(1 | 4); reaper.atexit(function() reaper.set_action_options(8) end) end
  gfx.init("ZP Studio Suite v1.0.5 - Marker", 620, 380)
  gfx.setfont(1, "Arial", 16)

  local function edit_input_char(ch)
    if ch == 8 then
      if input_select_all then
        base_name = ""
        input_cursor = 1
        input_select_all = false
      elseif input_cursor > 1 then
        base_name = base_name:sub(1, input_cursor - 2) .. base_name:sub(input_cursor)
        input_cursor = input_cursor - 1
      end
    elseif ch == 6579564 then
      if input_select_all then
        base_name = ""
        input_cursor = 1
        input_select_all = false
      elseif input_cursor <= #base_name then
        base_name = base_name:sub(1, input_cursor - 1) .. base_name:sub(input_cursor + 1)
      end
    elseif ch == 1818584692 then
      input_cursor = math.max(1, input_cursor - 1)
      input_select_all = false
    elseif ch == 1919379572 then
      input_cursor = math.min(#base_name + 1, input_cursor + 1)
      input_select_all = false
    elseif ch == 1752132965 then
      input_cursor = 1
      input_select_all = false
    elseif ch == 6647396 then
      input_cursor = #base_name + 1
      input_select_all = false
    elseif ch == 1 then
      input_select_all = true
      input_cursor = #base_name + 1
    elseif ch == 22 and reaper.CF_GetClipboard then
      local _, clip = reaper.CF_GetClipboard("")
      if input_select_all then
        base_name = ""
        input_cursor = 1
        input_select_all = false
      end
      local paste = (clip or ""):gsub("[\r\n,;]+", " ")
      base_name = base_name:sub(1, input_cursor - 1) .. paste .. base_name:sub(input_cursor)
      input_cursor = input_cursor + #paste
    elseif ch >= 32 and ch <= 1114111 then
      if (caps_lock_on() or (gfx.mouse_cap & 8) == 8) and ch >= 97 and ch <= 122 then
        ch = ch - 32
      end
      local ok, typed = false, nil
      if utf8 and utf8.char then ok, typed = pcall(utf8.char, ch) end
      if not ok and ch <= 255 then typed = string.char(ch) end
      if typed and #base_name < 32 and typed:match("[^,]") then
        if input_select_all then
          base_name = ""
          input_cursor = 1
          input_select_all = false
        end
        base_name = base_name:sub(1, input_cursor - 1) .. typed .. base_name:sub(input_cursor)
        input_cursor = input_cursor + #typed
      end
    end
  end

  local function loop()
    local ch = gfx.getchar()
    if ch < 0 then gfx.quit() return end
    if ch == 27 then
      if input_active then input_active = false else gfx.quit() return end
    elseif input_active then
      edit_input_char(ch)
    end

    local mouse_down = (gfx.mouse_cap & 1) == 1
    local clicked = mouse_down and not last_mouse_down
    last_mouse_down = mouse_down
    local selected_count = reaper.CountSelectedMediaItems(0)
    local help_text = ""

    ZP_UI.fill_background()

    gfx.set(0.10, 0.42, 0.48, 1)
    gfx.rect(22, 16, 34, 34, true)
    gfx.set(0.92, 0.88, 0.70, 1)
    gfx.line(33, 23, 33, 43)
    gfx.triangle(34, 23, 34, 34, 48, 28, true)
    gfx.set(0.92, 0.88, 0.78, 1)
    gfx.x = 66
    gfx.y = 18
    gfx.setfont(1, "Arial", 20)
    gfx.drawstr("Marker")

    gfx.setfont(1, "Arial", 12)
    gfx.set(0.56, 0.72, 0.86, 1)
    gfx.x = 66
    gfx.y = 42
    gfx.drawstr("ZP Studio Suite v1.0.5 - Paolo Balestri")

    gfx.setfont(1, "Arial", 15)
    gfx.set(0.68, 0.66, 0.74, 1)
    gfx.x = 22
    gfx.y = 60
    gfx.drawstr(tab == 1 and "Crea marker all'inizio degli item selezionati. La finestra si chiude prima di scrivere in timeline."
      or "Marker di progetto dentro gli item -> marker dell'item: seguono tagli e spostamenti.")
    ZP_UI.draw_help_button({ x = gfx.w - 54, y = 18, w = 34, h = 28 }, clicked, tab == 1 and "tool-04" or "tool-14")
    if draw_button({ x = 300, y = 16, w = 128, h = 30 }, "Crea dagli item", tab == 1, true, clicked, "tab") then tab = 1 end
    if draw_button({ x = 434, y = 16, w = 128, h = 30 }, "Fissa negli item", tab == 2, true, clicked, "tab") then
      tab = 2; input_active = false; fix_info_t = -1
    end

    if tab == 2 then
      -- quanti item e quanti marker di progetto ci cadono dentro (aggiornato ogni mezzo secondo)
      local now = reaper.time_precise()
      if now - fix_info_t > 0.5 then
        fix_info_t = now
        local n = reaper.CountSelectedMediaItems(0)
        fix_items = fix_all and n or math.min(n, 1)
        local ranges = {}
        for i = 0, fix_items - 1 do
          local it = reaper.GetSelectedMediaItem(0, i)
          local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
          ranges[#ranges + 1] = { pos, pos + reaper.GetMediaItemInfo_Value(it, "D_LENGTH") }
        end
        fix_markers = 0
        local _, nm, nr = reaper.CountProjectMarkers(0)
        for i = 0, nm + nr - 1 do
          local rv, isrgn, pos = reaper.EnumProjectMarkers3(0, i)
          if rv > 0 and not isrgn then
            for _, r in ipairs(ranges) do
              if pos >= r[1] and pos < r[2] then fix_markers = fix_markers + 1; break end
            end
          end
        end
      end

      gfx.set(0.86, 0.82, 0.70, 1)
      gfx.x, gfx.y = 22, 96
      gfx.drawstr("Item")
      local r_all, r_first = { x = 22, y = 112, w = 180, h = 36 }, { x = 210, y = 112, w = 180, h = 36 }
      if point_in_rect(gfx.mouse_x, gfx.mouse_y, r_all.x, r_all.y, r_all.w, r_all.h) then help_text = "Fissa i marker in tutti gli item selezionati." end
      if point_in_rect(gfx.mouse_x, gfx.mouse_y, r_first.x, r_first.y, r_first.w, r_first.h) then help_text = "Solo nel primo item selezionato." end
      if draw_button(r_all, "Tutti i selezionati", fix_all, true, clicked, "tab") then fix_all = true; fix_info_t = -1 end
      if draw_button(r_first, "Solo il primo", not fix_all, true, clicked, "tab") then fix_all = false; fix_info_t = -1 end

      gfx.set(0.86, 0.82, 0.70, 1)
      gfx.x, gfx.y = 22, 174
      gfx.drawstr("Dopo")
      local r_rm = { x = 22, y = 198, w = 368, h = 36 }
      if point_in_rect(gfx.mouse_x, gfx.mouse_y, r_rm.x, r_rm.y, r_rm.w, r_rm.h) then
        help_text = "ON: i marker di progetto copiati spariscono dalla timeline. OFF: restano anche li'. Si annulla con un Undo."
      end
      if draw_button(r_rm, fix_remove and "Cancella dalla timeline: ON" or "Cancella dalla timeline: OFF", fix_remove, true, clicked, "tab") then
        fix_remove = not fix_remove
      end

      gfx.set(0.74, 0.72, 0.80, 1)
      gfx.x, gfx.y = 22, 256
      gfx.drawstr(fit_text(string.format("Item: %d   Marker di progetto dentro: %d   (quelli gia' presenti nell'item vengono saltati)",
        fix_items, fix_markers), gfx.w - 44))
      gfx.set(0.92, 0.88, 0.78, 1)
      gfx.x, gfx.y = 22, 280
      gfx.drawstr(fit_text(help_text ~= "" and help_text or fix_status, gfx.w - 44))

      if draw_button({ x = 372, y = 320, w = 96, h = 38 }, "Fissa", false, fix_items > 0 and fix_markers > 0, clicked, "save") then
        _G.ZP_14_ALL, _G.ZP_14_REMOVE, _G.ZP_14_QUIET = fix_all, fix_remove, true
        local ok, res = pcall(dofile, FIX_PATH)
        _G.ZP_14_ALL, _G.ZP_14_REMOVE, _G.ZP_14_QUIET = nil, nil, nil
        fix_status = ok and (tostring(res or "Nessuna modifica."):gsub("\n", "   ")) or ("Errore: " .. tostring(res))
        fix_info_t = -1
      end
      if draw_button({ x = 486, y = 320, w = 96, h = 38 }, "Chiudi", false, true, clicked) then
        gfx.quit()
        return
      end
      gfx.update()
      reaper.defer(loop)
      return
    end

    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x = 22
    gfx.y = 96
    gfx.drawstr("Nome marker")

    local modes = {
      { id = 0, label = "Vuoto", help = "Crea marker senza nome. Se TC video e' ON, il marker prende solo il timecode." },
      { id = 1, label = "Nome fisso", help = "Crea tutti i marker con lo stesso nome base." },
      { id = 2, label = "Numerati", help = "Crea marker progressivi: NOME 001, NOME 002, NOME 003..." }
    }
    for i, info in ipairs(modes) do
      local rect = { x = 22 + ((i - 1) * 160), y = 112, w = 148, h = 36 }
      if point_in_rect(gfx.mouse_x, gfx.mouse_y, rect.x, rect.y, rect.w, rect.h) then help_text = info.help end
      if draw_button(rect, info.label, mode == info.id, true, clicked, "tab") then mode = info.id end
    end

    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x = 22
    gfx.y = 174
    gfx.drawstr("Nome base")

    local input_rect = { x = 22, y = 198, w = 300, h = 36 }
    if mode == 0 then
      gfx.set(0.14, 0.13, 0.18, 0.75)
      gfx.rect(input_rect.x, input_rect.y, input_rect.w, input_rect.h, true)
      gfx.set(0.46, 0.44, 0.52, 1)
      gfx.x = input_rect.x + 10
      gfx.y = input_rect.y + 9
      gfx.drawstr("Non usato con marker vuoti")
    else
      if point_in_rect(gfx.mouse_x, gfx.mouse_y, input_rect.x, input_rect.y, input_rect.w, input_rect.h) then
        help_text = "Nome scritto nei marker. Doppio click seleziona tutto; frecce e backspace funzionano nel campo."
      end
      if draw_input(input_rect, base_name, input_active, clicked, input_cursor, input_select_all) then
        local now = reaper.time_precise()
        if input_active and (now - input_last_click_time) < 0.35 then
          input_select_all = true
          input_cursor = #base_name + 1
        else
          input_select_all = false
          input_cursor = cursor_from_mouse(base_name, input_rect)
        end
        input_last_click_time = now
        input_active = true
      elseif clicked and not point_in_rect(gfx.mouse_x, gfx.mouse_y, input_rect.x, input_rect.y, input_rect.w, input_rect.h) then
        input_active = false
        input_select_all = false
      end
    end

    gfx.set(0.86, 0.82, 0.70, 1)
    gfx.x = 372
    gfx.y = 174
    gfx.drawstr("Opzioni")
    local tc_rect = { x = 372, y = 198, w = 196, h = 36 }
    if point_in_rect(gfx.mouse_x, gfx.mouse_y, tc_rect.x, tc_rect.y, tc_rect.w, tc_rect.h) then
      help_text = "Aggiunge al nome marker il timecode relativo al video o alla regione corrente."
    end
    if draw_button(tc_rect, "TC video", add_video_tc, true, clicked, "tab") then add_video_tc = not add_video_tc end

    gfx.set(0.74, 0.72, 0.80, 1)
    gfx.x = 22
    gfx.y = 276
    if help_text == "" then
      help_text = "Item selezionati: " .. tostring(selected_count) .. ". I marker verranno creati all'inizio di ogni item selezionato."
    end
    gfx.drawstr(fit_text(help_text, gfx.w - 44))

    local ready = selected_count > 0 and (mode == 0 or trim(base_name) ~= "")
    if draw_button({ x = 372, y = 320, w = 96, h = 38 }, "Crea", false, ready, clicked, "save") then
      local config = { mode = mode, base_name = trim(base_name ~= "" and base_name or "Marker"), add_video_tc = add_video_tc }
      gfx.quit()
      run_worker(config)
      return
    end
    if draw_button({ x = 486, y = 320, w = 96, h = 38 }, "Annulla", false, true, clicked) then
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
  if osara_active() then
    run_worker(nil)
    return
  end
  if not open_marker_bridge() then run_worker(nil) end
end

main()
