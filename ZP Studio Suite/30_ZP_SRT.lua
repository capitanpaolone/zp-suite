-- @noindex

-- ZP Studio Suite for REAPER
-- 30 ZP SRT (v2.1): stazione unica sottotitoli e copioni video.
-- Tutto in una sola finestra ridimensionabile con zoom proporzionale (zero scansioni a riposo):
--   1 · CARICA               (Video + SRT/VTT/XLSX, Solo SRT, Solo Video, Cartella Batch)
--   2 · SOSTITUISCI & LINGUE (Aggiorna sottotitoli con backup su traccia BKP muta o aggiungi lingua Reference)
--   3 · MODIFICA & ACCORPA   (Ispettore live, Editor testo integrato, Accorpa item brevi, Unisci/Dividi, Offset)
--   4 · ESPORTA              (SRT da qualsiasi traccia testi per video/regioni + SRT dai marker dell'audio)

local BASE_W, BASE_H = 880, 620
local sep = package.config:sub(1, 1)
local here = (debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)[/\\][^/\\]+$") or ".")
local function path_of(name) return here .. sep .. name end
local function exists(p)
  local f = io.open(p, "rb")
  if f then f:close(); return true end
  return false
end

local gfx = gfx
if exists(path_of("ZP_GfxScale.lua")) then
  ZP_GFX_SCALE_FN = function(w, h)
    return math.max(0.65, math.min(3.0, math.min(w / BASE_W, h / BASE_H)))
  end
  gfx = dofile(path_of("ZP_GfxScale.lua")).wrap(gfx)
end

if not exists(path_of("ZP_UI.lua")) or not exists(path_of("ZP_SRT_Engine.lua")) then
  reaper.ShowMessageBox("Moduli ZP_UI.lua o ZP_SRT_Engine.lua mancanti accanto a 30_ZP_SRT.lua.", "ZP SRT", 0)
  return
end

local UI     = dofile(path_of("ZP_UI.lua"))
local ENG    = dofile(path_of("ZP_SRT_Engine.lua"))
local TESTO  = dofile(path_of("ZP_Testo_Copione.lua"))
local EDITOR = dofile(path_of("ZP_Editor_Copione.lua"))

local function L(it, en)
  return (UI.get_lingua() == "en") and en or it
end

---------------------------------------------------------------------------
-- 1. STATO PERSISTENTE E PREFERENZE OPERATIVE
---------------------------------------------------------------------------

local EXT_SEC = "ZP_STUDIO_SUITE"

local function get_ext(key, def)
  local v = reaper.GetExtState(EXT_SEC, key)
  return (v and v ~= "") and v or def
end

local function set_ext(key, val)
  reaper.SetExtState(EXT_SEC, key, tostring(val or ""), true)
end

local state = {
  tab               = tonumber(get_ext("SRT30_tab", "1")) or 1,
  active_track_name = ENG.SUBTITLE_TRACK_NAME,
  -- Tab 1: Carica
  pos_mode          = get_ext("SRT30_pos_auto", "auto"),
  overlap_mode      = get_ext("SRT30_overlap", "lane"),
  coalesce_import   = get_ext("SRT30_coal_imp", "0") == "1",
  create_region     = get_ext("SRT30_mk_rgn", "1") ~= "0",
  create_vox        = get_ext("SRT30_mk_vox", "0") == "1",
  copy_to_media     = get_ext("SRT30_cp_media", "1") ~= "0",
  batch_gap         = tonumber(get_ext("SRT30_batch_gap", "3")) or 3,
  -- Tab 2: Sostituisci & Lingue
  rep_op            = get_ext("SRT30_rep_op", "replace"),
  lang_suffix       = get_ext("SRT30_lang", "ENG"),
  make_bkp          = get_ext("SRT30_mk_bkp", "1") ~= "0",
  -- Tab 3: Accorpa item brevi
  short_max_words   = tonumber(get_ext("SRT30_sh_words", "2")) or 2,
  short_max_gap     = tonumber(get_ext("SRT30_sh_gap", "0.9")) or 0.9,
  -- Tab 4: Esporta
  exp_dest          = get_ext("SRT30_exp_dest", "srt_export"),
  exp_custom_dir    = get_ext("SRT30_exp_dir", ""),
  exp_bak           = get_ext("SRT30_exp_bak", "1") ~= "0",
}

local dirty_scan = true

do
  local forced = tonumber(reaper.GetExtState(EXT_SEC, "ZP_SRT_TAB"))
  if forced and forced >= 1 and forced <= 4 then
    state.tab = forced
    reaper.DeleteExtState(EXT_SEC, "ZP_SRT_TAB", false)
  end
  if state.tab < 1 or state.tab > 4 then state.tab = 1 end
end

local function save_prefs()
  set_ext("SRT30_tab",      state.tab)
  set_ext("SRT30_pos_auto", state.pos_mode)
  set_ext("SRT30_overlap",  state.overlap_mode)
  set_ext("SRT30_coal_imp", state.coalesce_import and "1" or "0")
  set_ext("SRT30_mk_rgn",   state.create_region and "1" or "0")
  set_ext("SRT30_mk_vox",   state.create_vox and "1" or "0")
  set_ext("SRT30_cp_media", state.copy_to_media and "1" or "0")
  set_ext("SRT30_batch_gap",state.batch_gap)
  set_ext("SRT30_rep_op",   state.rep_op)
  set_ext("SRT30_lang",     state.lang_suffix)
  set_ext("SRT30_mk_bkp",   state.make_bkp and "1" or "0")
  set_ext("SRT30_sh_words", state.short_max_words)
  set_ext("SRT30_sh_gap",   string.format("%.2f", state.short_max_gap))
  set_ext("SRT30_exp_dest", state.exp_dest)
  set_ext("SRT30_exp_dir",  state.exp_custom_dir)
  set_ext("SRT30_exp_bak",  state.exp_bak and "1" or "0")
end

local function current_coalesce_opts(enabled_flag)
  return {
    enabled   = enabled_flag == true,
    max_words = state.short_max_words,
    min_dur   = (state.short_max_words <= 1) and 0.85 or 1.05,
    max_gap   = state.short_max_gap,
    max_chars = 240,
    max_dur   = 12.0
  }
end

---------------------------------------------------------------------------
-- 2. CONTROLLI GRAFICI NITIDI E AD ALTO CONTRASTO (ZERO LAG HOVER)
---------------------------------------------------------------------------

local status_msg = nil
local hover_help = nil

local function set_status(kind, text)
  if not text or text == "" then return end
  status_msg = {
    kind = kind or "ok",
    text = tostring(text):gsub("[\r\n]+", "  ·  ")
  }
  dirty_scan = true
  if reaper.osara_outputMessage then
    reaper.osara_outputMessage(status_msg.text)
  end
end

local function in_rect(r)
  return gfx.mouse_x >= r.x and gfx.mouse_x <= r.x + r.w
     and gfx.mouse_y >= r.y and gfx.mouse_y <= r.y + r.h
end

local function hint_rect(r, text)
  if text and in_rect(r) then
    hover_help = text
  end
end

local function fmt_tc(sec)
  if reaper.format_timestr_pos then
    return reaper.format_timestr_pos(sec or 0, "", 5)
  end
  return ENG.format_time(sec or 0)
end

-- Pannello di sezione con titolo leggibile (13 px bold)
local function draw_section_panel(rect, title)
  gfx.set(0.085, 0.092, 0.115, 1)
  UI.fill_round(rect.x, rect.y, rect.w, rect.h, 7)
  gfx.set(0.24, 0.26, 0.33, 1)
  if gfx.roundrect then gfx.roundrect(rect.x, rect.y, rect.w - 1, rect.h - 1, 7, true)
  else gfx.rect(rect.x, rect.y, rect.w, rect.h, false) end

  local top = 10
  if title and title ~= "" then
    gfx.setfont(1, "Arial", 13, "b")
    gfx.set(0.74, 0.78, 0.88, 1)
    gfx.x, gfx.y = rect.x + 14, rect.y + 8
    gfx.drawstr(UI.fit_text(title, rect.w - 28))
    gfx.set(0.18, 0.20, 0.26, 1)
    gfx.line(rect.x + 12, rect.y + 28, rect.x + rect.w - 12, rect.y + 28)
    top = 36
  end
  return { x = rect.x + 14, y = rect.y + top, w = rect.w - 28, h = rect.h - top - 12 }
end

-- Scheda principale (4 tab in alto): contrasto pieno, accento superiore, testo centrato 14 px bold
local function draw_tab_btn(rect, label, active, clicked, help_txt)
  if help_txt and in_rect(rect) then hover_help = help_txt end
  local hover = in_rect(rect)

  if active then
    gfx.set(0.10, 0.32, 0.50, 1)
  elseif hover then
    gfx.set(0.18, 0.22, 0.30, 1)
  else
    gfx.set(0.11, 0.12, 0.16, 1)
  end
  UI.fill_round(rect.x, rect.y, rect.w, rect.h, 5)

  if active then
    gfx.set(0.32, 0.78, 1.00, 1)
    gfx.rect(rect.x + 4, rect.y + 1, rect.w - 8, 3, true)
    gfx.set(0.46, 0.82, 1.00, 1)
  elseif hover then
    gfx.set(0.50, 0.62, 0.78, 1)
  else
    gfx.set(0.28, 0.30, 0.38, 1)
  end
  if gfx.roundrect then gfx.roundrect(rect.x, rect.y, rect.w - 1, rect.h - 1, 5, true)
  else gfx.rect(rect.x, rect.y, rect.w, rect.h, false) end

  gfx.setfont(1, "Arial", 14, "b")
  if active then gfx.set(0.98, 0.99, 1.00, 1)
  elseif hover then gfx.set(0.94, 0.96, 1.00, 1)
  else gfx.set(0.78, 0.81, 0.88, 1) end

  local fit = UI.fit_text(label, rect.w - 16)
  local tw, th = gfx.measurestr(fit)
  gfx.x = rect.x + math.floor((rect.w - tw) * 0.5)
  gfx.y = rect.y + math.floor((rect.h - th) * 0.5) + 1
  gfx.drawstr(fit)

  return clicked and hover
end

-- Pulsante selettore/comando compatto centrato (contrasto netto anche da acceso!)
-- style: "seg" (default blu scuro), "green" (azione pronta), "subtle" (barra in basso / menu)
local function draw_seg_btn(rect, label, active, enabled, clicked, style, help_txt)
  enabled = enabled ~= false
  if help_txt and in_rect(rect) then hover_help = help_txt end
  local hover = enabled and in_rect(rect)
  local fsize = rect.font or 13

  if not enabled then
    gfx.set(0.085, 0.09, 0.11, 1)
  elseif style == "green" then
    if hover then gfx.set(0.14, 0.50, 0.26, 1) else gfx.set(0.09, 0.36, 0.19, 1) end
  elseif active then
    if hover then gfx.set(0.14, 0.42, 0.64, 1) else gfx.set(0.11, 0.35, 0.54, 1) end
  elseif hover then
    gfx.set(0.20, 0.24, 0.33, 1)
  elseif style == "subtle" then
    gfx.set(0.105, 0.12, 0.16, 1)
  else
    gfx.set(0.13, 0.14, 0.19, 1)
  end
  UI.fill_round(rect.x, rect.y, rect.w, rect.h, 5)

  if not enabled then
    gfx.set(0.20, 0.21, 0.25, 1)
  elseif style == "green" then
    gfx.set(hover and 0.52 or 0.36, hover and 0.96 or 0.80, hover and 0.64 or 0.48, 1)
  elseif active then
    gfx.set(0.48, 0.84, 1.00, 1)
  elseif hover then
    gfx.set(0.56, 0.68, 0.86, 1)
  else
    gfx.set(0.30, 0.32, 0.40, 1)
  end
  if gfx.roundrect then gfx.roundrect(rect.x, rect.y, rect.w - 1, rect.h - 1, 5, true)
  else gfx.rect(rect.x, rect.y, rect.w, rect.h, false) end

  gfx.setfont(1, "Arial", fsize, (active or style == "green") and "b" or "")
  if not enabled then
    gfx.set(0.44, 0.46, 0.52, 1)
  elseif active or style == "green" or hover then
    gfx.set(0.97, 0.98, 1.00, 1)
  else
    gfx.set(0.86, 0.88, 0.93, 1)
  end

  local fit = UI.fit_text(label, rect.w - 16)
  local tw, th = gfx.measurestr(fit)
  gfx.x = rect.align_left and (rect.x + 12) or (rect.x + math.floor((rect.w - tw) * 0.5))
  gfx.y = rect.y + math.floor((rect.h - th) * 0.5)
  gfx.drawstr(fit)

  return clicked and enabled and hover
end

-- Card azione primaria (Titolo 15 px bold + Sottotitolo 13 px dentro lo stesso pulsante!)
-- tone: "blue" (carica/aggiorna) o "green" (esporta/salva)
local function draw_action_card(rect, title, subtitle, enabled, clicked, tone, help_txt)
  enabled = enabled ~= false
  if help_txt and in_rect(rect) then hover_help = help_txt end
  local hover = enabled and in_rect(rect)
  local is_green = (tone == "green")

  if not enabled then
    gfx.set(0.09, 0.095, 0.115, 1)
  elseif is_green then
    if hover then gfx.set(0.13, 0.44, 0.24, 1) else gfx.set(0.09, 0.30, 0.17, 1) end
  else
    if hover then gfx.set(0.16, 0.34, 0.52, 1) else gfx.set(0.11, 0.22, 0.34, 1) end
  end
  UI.fill_round(rect.x, rect.y, rect.w, rect.h, 6)

  -- Tacca laterale luminosa
  if enabled then
    if is_green then gfx.set(0.38, 0.94, 0.56, 1)
    else gfx.set(0.38, 0.78, 1.00, 1) end
  else
    gfx.set(0.24, 0.25, 0.30, 1)
  end
  gfx.rect(rect.x + 3, rect.y + 6, 4, rect.h - 12, true)

  if not enabled then
    gfx.set(0.20, 0.22, 0.26, 1)
  elseif hover then
    if is_green then gfx.set(0.55, 0.98, 0.68, 1) else gfx.set(0.56, 0.88, 1.00, 1) end
  else
    if is_green then gfx.set(0.28, 0.68, 0.40, 1) else gfx.set(0.28, 0.52, 0.74, 1) end
  end
  if gfx.roundrect then gfx.roundrect(rect.x, rect.y, rect.w - 1, rect.h - 1, 6, true)
  else gfx.rect(rect.x, rect.y, rect.w, rect.h, false) end

  local tx = rect.x + 16
  local max_tw = rect.w - 26
  if subtitle and subtitle ~= "" then
    gfx.setfont(1, "Arial", 15, "b")
    if enabled then gfx.set(0.96, 0.97, 1.00, 1) else gfx.set(0.46, 0.48, 0.54, 1) end
    gfx.x, gfx.y = tx, rect.y + 7
    gfx.drawstr(UI.fit_text(title, max_tw))

    gfx.setfont(1, "Arial", 13)
    if enabled then gfx.set(hover and 0.84 or 0.70, hover and 0.90 or 0.76, hover and 0.98 or 0.86, 1)
    else gfx.set(0.38, 0.40, 0.46, 1) end
    gfx.x, gfx.y = tx, rect.y + 28
    gfx.drawstr(UI.fit_text(subtitle, max_tw))
  else
    gfx.setfont(1, "Arial", 14, "b")
    if enabled then gfx.set(0.96, 0.97, 1.00, 1) else gfx.set(0.46, 0.48, 0.54, 1) end
    local fit = UI.fit_text(title, max_tw)
    local _, th = gfx.measurestr(fit)
    gfx.x, gfx.y = tx, rect.y + math.floor((rect.h - th) * 0.5)
    gfx.drawstr(fit)
  end

  return clicked and enabled and hover
end

-- Interruttore con LED verde e font 14 px leggibile
local function draw_toggle_row(rect, label, on, enabled, clicked, help_txt)
  enabled = enabled ~= false
  if help_txt and in_rect(rect) then hover_help = help_txt end
  local hover = enabled and in_rect(rect)

  if not enabled then gfx.set(0.085, 0.09, 0.11, 1)
  elseif hover then gfx.set(0.18, 0.20, 0.27, 1)
  else gfx.set(0.12, 0.13, 0.17, 1) end
  UI.fill_round(rect.x, rect.y, rect.w, rect.h, 5)

  gfx.set(hover and 0.48 or 0.30, hover and 0.54 or 0.32, hover and 0.66 or 0.40, enabled and 1 or 0.5)
  if gfx.roundrect then gfx.roundrect(rect.x, rect.y, rect.w - 1, rect.h - 1, 5, true)
  else gfx.rect(rect.x, rect.y, rect.w, rect.h, false) end

  local cx, cy, r = rect.x + 15, rect.y + math.floor(rect.h * 0.5), 5
  if on and enabled then
    gfx.set(0.25, 0.95, 0.48, 0.26); gfx.circle(cx, cy, r + 3, true, true)
    gfx.set(0.32, 0.96, 0.52, 1)
  else
    gfx.set(0.24, 0.26, 0.32, 1)
  end
  gfx.circle(cx, cy, r, true, true)

  gfx.setfont(1, "Arial", 14, on and "b" or "")
  if not enabled then gfx.set(0.45, 0.46, 0.50, 1)
  elseif on then gfx.set(0.96, 0.97, 0.99, 1)
  else gfx.set(0.82, 0.84, 0.90, 1) end
  local fit = UI.fit_text(label, rect.w - 36)
  local _, th = gfx.measurestr(fit)
  gfx.x, gfx.y = rect.x + 29, rect.y + math.floor((rect.h - th) * 0.5)
  gfx.drawstr(fit)

  return clicked and enabled and hover
end

---------------------------------------------------------------------------
-- 3. APERTURA STRUMENTI GEMELLI SENZA CHIUDERE ZP SRT
---------------------------------------------------------------------------

local function norm_path(p)
  return (tostring(p):gsub("\\", "/"):gsub("/+", "/"):lower())
end

local function command_for(path)
  local f = io.open(reaper.GetResourcePath() .. sep .. "reaper-kb.ini", "rb")
  local kb = f and f:read("*a") or ""
  if f then f:close() end
  local want = norm_path(path)
  local scripts = reaper.GetResourcePath() .. "/Scripts/"
  for line in kb:gmatch("[^\n]+") do
    local section, id, rest = line:match('^SCR%s+%d+%s+(%d+)%s+(RS%x+)%s+"[^"]*"%s+(.-)%s*$')
    if section == "0" and rest then
      local p = rest:match('^"(.*)"$') or rest
      if not p:match("^/") and not p:match("^%a:[/\\]") then p = scripts .. p end
      if norm_path(p) == want then
        local cmd = reaper.NamedCommandLookup("_" .. id)
        if cmd and cmd > 0 then return cmd end
      end
    end
  end
  if reaper.AddRemoveReaScript then
    local cmd = reaper.AddRemoveReaScript(true, 0, path, true)
    if cmd and cmd > 0 then return cmd end
  end
  return 0
end

local function launch_companion(script_name)
  local p = path_of(script_name)
  if not exists(p) then
    set_status("err", L("Script non trovato: ", "Script not found: ") .. script_name)
    return
  end
  local cmd = command_for(p)
  if cmd > 0 then
    reaper.Main_OnCommand(cmd, 0)
  else
    set_status("err", L("Impossibile registrare l'azione: ", "Cannot register action: ") .. script_name)
  end
end

---------------------------------------------------------------------------
-- 4. EDITOR TESTO INTEGRATO (ZP_Editor_Copione DENTRO ZP SRT)
---------------------------------------------------------------------------

local edit_modal = nil
local local_clipboard = ""

local function utf8_prev_cursor(text, cur)
  if cur <= 1 then return 1 end
  local i = cur - 1
  while i > 1 and text:byte(i) >= 128 and text:byte(i) < 192 do i = i - 1 end
  return i
end

local function utf8_next_cursor(text, cur)
  local len = #text
  if cur > len then return len + 1 end
  local b = text:byte(cur)
  local step = 1
  if b >= 240 then step = 4
  elseif b >= 224 then step = 3
  elseif b >= 192 then step = 2 end
  return math.min(len + 1, cur + step)
end

local function char_from_code(code)
  if code < 32 or code > 0x10FFFF then return nil end
  local ok, ch = pcall(utf8.char, code)
  return ok and ch or nil
end

local function ed_selection_range()
  if not edit_modal or not edit_modal.sel_a or not edit_modal.sel_b then return nil, nil end
  if edit_modal.sel_a == edit_modal.sel_b then return nil, nil end
  return math.min(edit_modal.sel_a, edit_modal.sel_b), math.max(edit_modal.sel_a, edit_modal.sel_b)
end

local function ed_set_selection(a, b)
  if not edit_modal then return end
  if not a or not b or a == b then
    edit_modal.sel_a, edit_modal.sel_b = nil, nil
    if a then edit_modal.cursor = math.max(1, math.min(#edit_modal.text + 1, a)) end
  else
    edit_modal.sel_a = math.max(1, math.min(#edit_modal.text + 1, a))
    edit_modal.sel_b = math.max(1, math.min(#edit_modal.text + 1, b))
    edit_modal.cursor = edit_modal.sel_b
  end
end

local function ed_set_cursor(pos)
  if not edit_modal then return end
  edit_modal.cursor = math.max(1, math.min(#edit_modal.text + 1, pos))
  edit_modal.sel_a, edit_modal.sel_b = nil, nil
end

local function ed_push_undo()
  if not edit_modal then return end
  edit_modal.undo_stack = edit_modal.undo_stack or {}
  local st = edit_modal.undo_stack
  if #st == 0 or st[#st].text ~= edit_modal.text then
    st[#st + 1] = { text = edit_modal.text, cursor = edit_modal.cursor }
    if #st > 40 then table.remove(st, 1) end
  end
end

local function ed_restore_undo()
  if not edit_modal or not edit_modal.undo_stack or #edit_modal.undo_stack == 0 then return end
  local prev = table.remove(edit_modal.undo_stack)
  edit_modal.text = prev.text
  ed_set_cursor(prev.cursor)
end

local function ed_insert_text(ins)
  if not edit_modal then return end
  ed_push_undo()
  local a, b = ed_selection_range()
  if not a then a, b = edit_modal.cursor, edit_modal.cursor end
  edit_modal.text = edit_modal.text:sub(1, a - 1) .. ins .. edit_modal.text:sub(b)
  ed_set_cursor(a + #ins)
end

local function ed_backspace()
  if not edit_modal then return end
  local a = ed_selection_range()
  if a then ed_insert_text("") return end
  if edit_modal.cursor <= 1 then return end
  ed_push_undo()
  local prev = utf8_prev_cursor(edit_modal.text, edit_modal.cursor)
  edit_modal.text = edit_modal.text:sub(1, prev - 1) .. edit_modal.text:sub(edit_modal.cursor)
  ed_set_cursor(prev)
end

local function ed_delete()
  if not edit_modal then return end
  local a = ed_selection_range()
  if a then ed_insert_text("") return end
  if edit_modal.cursor > #edit_modal.text then return end
  ed_push_undo()
  local nxt = utf8_next_cursor(edit_modal.text, edit_modal.cursor)
  edit_modal.text = edit_modal.text:sub(1, edit_modal.cursor - 1) .. edit_modal.text:sub(nxt)
end

local function ed_selected_text()
  local a, b = ed_selection_range()
  if not a then return "" end
  return edit_modal.text:sub(a, b - 1)
end

local function ed_select_word()
  if not edit_modal then return end
  local txt = edit_modal.text
  local c = math.max(1, math.min(#txt, edit_modal.cursor))
  if #txt == 0 then return end
  local a, b = c, c
  while a > 1 and not txt:sub(a - 1, a - 1):match("%s") do a = a - 1 end
  while b <= #txt and not txt:sub(b, b):match("%s") do b = b + 1 end
  if a < b then ed_set_selection(a, b) end
end

local function ed_visual_lines(max_w)
  local txt = edit_modal and edit_modal.text or ""
  local lines = {}
  local idx = 1
  local len = #txt
  while idx <= len + 1 do
    local nl = txt:find("\n", idx, true)
    local p_end = nl and (nl - 1) or len
    if p_end < idx then
      lines[#lines + 1] = { text = "", start = idx, finish = idx - 1 }
    else
      local seg_start = idx
      local cur_line = ""
      local last_ok_end = idx - 1
      local p = idx
      while p <= p_end do
        local ws_s, ws_e = txt:find("%S+", p)
        if not ws_s or ws_s > p_end then break end
        ws_e = math.min(ws_e, p_end)
        local word = txt:sub(ws_s, ws_e)
        local cand = (cur_line == "") and word or (cur_line .. " " .. word)
        if gfx.measurestr(cand) <= max_w or cur_line == "" then
          cur_line = cand
          last_ok_end = ws_e
        else
          lines[#lines + 1] = { text = cur_line, start = seg_start, finish = last_ok_end }
          seg_start = ws_s
          cur_line = word
          last_ok_end = ws_e
        end
        p = ws_e + 1
      end
      lines[#lines + 1] = { text = cur_line, start = seg_start, finish = p_end }
    end
    if not nl then break end
    idx = nl + 1
    if nl == len then
      lines[#lines + 1] = { text = "", start = len + 1, finish = len }
      break
    end
  end
  if #lines == 0 then lines[1] = { text = "", start = 1, finish = 0 } end
  return lines
end

local function ed_cursor_at(mx, my)
  if not edit_modal or not edit_modal.lines then return 1 end
  local row = math.max(1, math.min(#edit_modal.lines, math.floor((my - (edit_modal.text_y or 0)) / math.max(1, edit_modal.line_h or 20)) + 1))
  local line = edit_modal.lines[row]
  if not line or line.finish < line.start then return line and line.start or 1 end
  return TESTO.cursor_in_words(edit_modal.text, line.start, line.finish, math.max(0, mx - (edit_modal.text_x or 0)), gfx.measurestr)
end

local function ed_cursor_point(mx, my)
  ed_set_cursor(ed_cursor_at(mx, my))
end

local function ed_move_vertical(delta)
  if not edit_modal or not edit_modal.lines then return end
  local lines = edit_modal.lines
  local ci = #lines
  for i, ln in ipairs(lines) do
    if edit_modal.cursor >= ln.start and edit_modal.cursor <= ln.finish + 1 then ci = i; break end
  end
  local target_i = math.max(1, math.min(#lines, ci + delta))
  local cur_ln = lines[ci]
  local px = gfx.measurestr(edit_modal.text:sub(cur_ln.start, edit_modal.cursor - 1))
  local tgt = lines[target_i]
  if tgt.finish < tgt.start then ed_set_cursor(tgt.start)
  else ed_set_cursor(TESTO.cursor_in_words(edit_modal.text, tgt.start, tgt.finish, px, gfx.measurestr)) end
end

local function parse_highlights_raw(raw)
  local list, seen = {}, {}
  for term in tostring(raw or ""):gmatch("[^\r\n]+") do
    local t = ENG.trim(term)
    if t ~= "" and not seen[t] then seen[t] = true; list[#list + 1] = t end
  end
  return list
end

local function open_item_editor(item, title_override)
  if not item or not reaper.ValidatePtr2(0, item, "MediaItem*") then return end
  local _, raw_notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
  local _, raw_hl    = reaper.GetSetMediaItemInfo_String(item, "P_EXT:RythmoBand_HIGHLIGHT", "", false)
  local _, raw_anc   = reaper.GetSetMediaItemInfo_String(item, "P_EXT:ZP_GOBBO_ANCHORS", "", false)
  local norm_text    = tostring(raw_notes or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  if norm_text == "TESTO" then norm_text = "" end
  edit_modal = {
    item                = item,
    title               = title_override or "Modifica battuta",
    mode                = "subtitle",
    text                = norm_text,
    original            = norm_text,
    cursor              = #norm_text + 1,
    highlights          = parse_highlights_raw(raw_hl),
    original_highlights = raw_hl or "",
    anchors             = TESTO.parse_anchors(raw_anc or ""),
    anchors_text        = norm_text,
    opening_mouse_down  = true,
    font_size           = 20,
    undo_stack          = {}
  }
end

local function save_item_editor()
  if not edit_modal then return end
  local item = edit_modal.item
  local new_text = ENG.trim(edit_modal.text:gsub("\r\n", "\n"):gsub("\r", "\n"))
  if item and reaper.ValidatePtr2(0, item, "MediaItem*") and new_text ~= "" then
    local anchors = TESTO.relocate_anchors(edit_modal.anchors_text or edit_modal.original, new_text, edit_modal.anchors or {})
    local hl_terms, seen = {}, {}
    for _, v in ipairs(edit_modal.highlights or {}) do
      if v ~= "" and not seen[v] then seen[v] = true; hl_terms[#hl_terms + 1] = v end
    end
    if edit_modal.import_highlights then
      for _, v in ipairs(edit_modal.imported_highlights or {}) do
        if v ~= "" and not seen[v] then seen[v] = true; hl_terms[#hl_terms + 1] = v end
      end
    end

    reaper.Undo_BeginBlock()
    reaper.GetSetMediaItemInfo_String(item, "P_NOTES", new_text, true)
    reaper.GetSetMediaItemInfo_String(item, "P_EXT:ZP_GOBBO_ANCHORS", TESTO.serialize_anchors(anchors), true)
    reaper.GetSetMediaItemInfo_String(item, "P_EXT:RythmoBand_HIGHLIGHT", table.concat(hl_terms, "\n"), true)
    if new_text ~= edit_modal.original then
      reaper.GetSetMediaItemInfo_String(item, "P_EXT:ZP_GOBBO_TIMING", "", true)
      reaper.GetSetMediaItemInfo_String(item, "P_EXT:ZP_GOBBO_TIMING_TEXT", "", true)
    end
    TESTO.name_text_item(reaper, item, new_text)
    reaper.UpdateItemInProject(item)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("ZP SRT: modifica testo battuta", -1)
    set_status("ok", L("Battuta aggiornata.", "Subtitle cue updated."))
  end
  edit_modal = nil
  dirty_scan = true
end

local function ed_paste()
  local text = TESTO.clipboard(reaper, reaper.GetOS())
  if text and text ~= "" then ed_insert_text(text)
  elseif local_clipboard ~= "" then ed_insert_text(TESTO.normalize(local_clipboard)) end
end

local function ed_copy()
  local sel = ed_selected_text()
  if sel ~= "" then
    local_clipboard = sel
    if reaper.CF_SetClipboard then reaper.CF_SetClipboard(sel) end
  end
end

local function ed_cut()
  local sel = ed_selected_text()
  if sel ~= "" then
    ed_copy()
    ed_insert_text("")
  end
end

local function ed_transform(fn, sel_only)
  local a, b = ed_selection_range()
  if sel_only and not a then return end
  a, b = a or 1, b or (#edit_modal.text + 1)
  local res = fn(edit_modal.text:sub(a, b - 1))
  ed_set_selection(a, b)
  ed_insert_text(res)
  ed_set_selection(a, a + #res)
end

local function ed_toggle_highlight()
  if not edit_modal then return end
  if ed_selected_text() == "" then ed_select_word() end
  local term = ENG.trim(ed_selected_text():gsub("[\r\n]+", " "))
  if term == "" then return end
  local list, found = edit_modal.highlights, false
  for i = #list, 1, -1 do
    if TESTO.lower(list[i]) == TESTO.lower(term) then
      table.remove(list, i); found = true
    end
  end
  if not found then list[#list + 1] = term end
end

local function ed_load_file()
  local ok, path = reaper.GetUserFileNameForRead("", "ZP - Carica testo (.docx, .odt, .rtf, .txt, .xlsx)", "")
  if not ok or not path or path == "" then return end
  local text, terms
  if path:lower():match("%.xlsx$") then
    local xlsx = dofile(path_of("ZP_Xlsx_Copione.lua"))
    local cues, info = xlsx.read(function(name) return TESTO.zip_member(path, name, reaper.GetOS()) end, { choose = xlsx.menu })
    if cues then text, terms = xlsx.to_text(cues), {} elseif info then terms = info else return end
  else
    text, terms = TESTO.read_file(path, reaper.GetOS())
  end
  if not text then
    set_status("err", tostring(terms or "Errore lettura file."))
    return
  end
  ed_insert_text(text)
  edit_modal.imported_highlights = terms
end

local function process_editor_key(ch)
  if not edit_modal or ch <= 0 then return false end
  gfx.setfont(1, "Arial", edit_modal.layout_font or 20)
  if ch == 13 then
    if (gfx.mouse_cap & 8) == 8 then ed_insert_text("\n")
    else save_item_editor() end
    return true
  elseif ch == 27 then
    edit_modal = nil
    return true
  elseif ch == 8 then ed_backspace(); return true
  elseif ch == 1 then ed_set_selection(1, #edit_modal.text + 1); return true
  elseif ch == 3 then ed_copy(); return true
  elseif ch == 22 then ed_paste(); return true
  elseif ch == 24 then ed_cut(); return true
  elseif ch == 26 or (((gfx.mouse_cap & 4) == 4 or (gfx.mouse_cap & 32) == 32) and (ch == 90 or ch == 122)) then
    ed_restore_undo(); return true
  elseif ch == 5 then ed_toggle_highlight(); return true
  elseif ch == 6579564 then ed_delete(); return true
  elseif ch == 1818584692 then ed_set_cursor(utf8_prev_cursor(edit_modal.text, edit_modal.cursor)); return true
  elseif ch == 1919379572 then ed_set_cursor(utf8_next_cursor(edit_modal.text, edit_modal.cursor)); return true
  elseif ch == 30064 then ed_move_vertical(-1); return true
  elseif ch == 1685026670 then ed_move_vertical(1); return true
  elseif ch == 1752132965 then ed_set_cursor(1); return true
  elseif ch == 6647396 then ed_set_cursor(#edit_modal.text + 1); return true
  elseif ch >= 32 and ch <= 1114111 then
    local s = char_from_code(ch)
    if s then ed_insert_text(s) end
    return true
  end
  return true
end

local function draw_editor_overlay(pressed, released)
  if not edit_modal then return end
  if gfx.mouse_wheel ~= 0 then
    edit_modal.wheel = gfx.mouse_wheel
    gfx.mouse_wheel = 0
  end
  gfx.set(0.02, 0.02, 0.04, 0.78)
  gfx.rect(0, 0, gfx.w, gfx.h, true)
  local action = EDITOR.draw(edit_modal, {
    ui            = UI,
    T             = UI.T,
    font          = "Arial",
    lines         = ed_visual_lines,
    stats         = TESTO.stats,
    selection     = ed_selection_range,
    cursor_point  = ed_cursor_point,
    cursor_at     = ed_cursor_at,
    set_selection = ed_set_selection,
    select_word   = ed_select_word,
    time          = reaper.time_precise,
    pressed       = pressed,
    released      = released
  })
  if action == "paste" then ed_paste()
  elseif action == "load" then ed_load_file()
  elseif action == "clean" then ed_transform(function(s) return TESTO.normalize(s, true) end)
  elseif action == "join" then ed_transform(TESTO.join_lines)
  elseif action == "highlight" then ed_toggle_highlight()
  elseif action == "tools" then
    gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
    local choice = gfx.showmenu(table.concat({
      UI.T("Separa frasi per respiro"),
      UI.T("Selezione: minuscolo"),
      UI.T("Selezione: MAIUSCOLO"),
      UI.T("Selezione: iniziale maiuscola"),
      UI.T("Annulla modifica (Ctrl+Z)"),
      (edit_modal.import_highlights and "!" or "") .. UI.T("Importa grassetto/evidenziato")
    }, "|"))
    if choice == 1 then ed_transform(TESTO.breathe)
    elseif choice == 2 then ed_transform(TESTO.lower, true)
    elseif choice == 3 then ed_transform(TESTO.upper, true)
    elseif choice == 4 then ed_transform(TESTO.sentence_case, true)
    elseif choice == 5 then ed_restore_undo()
    elseif choice == 6 then edit_modal.import_highlights = not edit_modal.import_highlights end
  elseif action == "save" then save_item_editor()
  elseif action == "cancel" then edit_modal = nil end
end

---------------------------------------------------------------------------
-- 5. STRISCIA CONTESTO + BARRA DELLE 4 SCHEDE
---------------------------------------------------------------------------

local function draw_pill(x, y, h, label, value, accent)
  gfx.setfont(1, "Arial", 13)
  local lw = label ~= "" and gfx.measurestr(label .. ": ") or 0
  gfx.setfont(1, "Arial", 13, "b")
  local vw = gfx.measurestr(value)
  local w = lw + vw + 18

  gfx.set(0.11, 0.12, 0.16, 1)
  UI.fill_round(x, y, w, h, 5)
  if accent == "amber" then gfx.set(0.88, 0.62, 0.20, 0.90)
  elseif accent == "green" then gfx.set(0.26, 0.78, 0.46, 0.85)
  else gfx.set(0.28, 0.30, 0.38, 0.90) end
  if gfx.roundrect then gfx.roundrect(x, y, w - 1, h - 1, 5, true)
  else gfx.rect(x, y, w, h, false) end

  local tx = x + 9
  local _, th = gfx.measurestr("A")
  local ty = y + math.floor((h - th) * 0.5)
  if label ~= "" then
    gfx.setfont(1, "Arial", 13)
    gfx.set(0.66, 0.70, 0.78, 1)
    gfx.x, gfx.y = tx, ty
    gfx.drawstr(label .. ": ")
    tx = tx + lw
  end
  gfx.setfont(1, "Arial", 13, "b")
  if accent == "amber" then gfx.set(0.98, 0.80, 0.34, 1)
  elseif accent == "green" then gfx.set(0.46, 0.96, 0.64, 1)
  else gfx.set(0.93, 0.94, 0.97, 1) end
  gfx.x, gfx.y = tx, ty
  gfx.drawstr(value)
  return x + w + 8
end

local function pick_subtitle_track_menu(ctx)
  local items, map = {}, {}
  for _, tr in ipairs(ctx.sub_tracks) do
    local mark = (tr.name == ctx.active_track_name) and "!" or ""
    items[#items + 1] = mark .. tr.name .. " (" .. tostring(tr.count) .. ")"
    map[#items] = tr.name
  end
  if #items > 0 then items[#items + 1] = "" end
  items[#items + 1] = L("+ Crea / usa «Rythmo Band Testi»", "+ Create / use «Rythmo Band Testi»")
  local create_main_idx = #items
  items[#items + 1] = L("+ Nuova traccia lingua…", "+ New language track…")
  local create_lang_idx = #items

  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local pick = gfx.showmenu(table.concat(items, "|"))
  if pick <= 0 then return end
  local actual = {}
  for idx, s in ipairs(items) do
    if s ~= "" then actual[#actual + 1] = idx end
  end
  local orig_idx = actual[pick]
  if not orig_idx then return end
  if map[orig_idx] then
    state.active_track_name = map[orig_idx]
    dirty_scan = true
  elseif orig_idx == create_main_idx then
    reaper.Undo_BeginBlock()
    ENG.get_or_create_subtitle_track(ENG.SUBTITLE_TRACK_NAME)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("ZP SRT: crea traccia testi", -1)
    state.active_track_name = ENG.SUBTITLE_TRACK_NAME
    dirty_scan = true
    set_status("ok", L("Traccia «Rythmo Band Testi» pronta.", "Track «Rythmo Band Testi» ready."))
  elseif orig_idx == create_lang_idx then
    local ok, val = reaper.GetUserInputs(L("Nuova traccia lingua", "New language track"), 1, L("Sigla lingua (es. ENG, ORIG, FRA):", "Language tag (e.g. ENG, ORIG, FRA):"), state.lang_suffix)
    if ok and ENG.trim(val) ~= "" then
      local tag = ENG.trim(val):upper():gsub("[^%w_%-]", "")
      local name = ENG.SUBTITLE_TRACK_NAME .. " " .. tag
      reaper.Undo_BeginBlock()
      ENG.get_or_create_subtitle_track(name)
      reaper.UpdateArrange()
      reaper.Undo_EndBlock("ZP SRT: crea traccia " .. name, -1)
      state.active_track_name = name
      state.lang_suffix = tag
      save_prefs()
      dirty_scan = true
      set_status("ok", L("Traccia creata: ", "Track created: ") .. name)
    end
  end
end

local function draw_context_and_tabs(ctx, clicked)
  local pad = 20
  local cy = 62
  local tr_rect = { x = pad, y = cy, w = 248, h = 28, font = 13, align_left = true }
  if draw_seg_btn(tr_rect, L("Flusso: ", "Track: ") .. ctx.active_track_name .. "  ▾", false, true, clicked, "subtle",
      L("Scegli su quale traccia di testo lavorare o creane una nuova.", "Choose which subtitle track to work on or create a new one.")) then
    pick_subtitle_track_menu(ctx)
  end

  local px = tr_rect.x + tr_rect.w + 8
  px = draw_pill(px, cy, 28, L("Video sel", "Sel videos"), tostring(#ctx.sel_videos) .. "/" .. tostring(#ctx.all_videos), #ctx.sel_videos > 0 and "green" or nil)
  if ctx.cur_region then
    gfx.setfont(1, "Arial", 13)
    px = draw_pill(px, cy, 28, L("Regione", "Region"), UI.fit_text(ctx.cur_region.name, 145), "green")
  else
    px = draw_pill(px, cy, 28, "Playhead", fmt_tc(ctx.cursor), nil)
  end
  px = draw_pill(px, cy, 28, L("Battute sel", "Sel cues"), tostring(#ctx.sel_texts), #ctx.sel_texts > 0 and "green" or nil)
  if ctx.short_trk > 0 and px < gfx.w - 110 then
    draw_pill(px, cy, 28, L("Brevi", "Short"), tostring(ctx.short_trk), "amber")
  end

  local ty = 98
  local gap = 8
  local tw = math.floor((gfx.w - pad * 2 - gap * 3) / 4)
  local edit_badge = ctx.short_trk > 0 and (" (" .. tostring(ctx.short_trk) .. ")") or ""
  local tabs = {
    { id = 1, label = L("1 · CARICA", "1 · LOAD"),
      help = L("Importa video + SRT/VTT/Excel, solo SRT, solo video o una cartella intera in sequenza.", "Import video + SRT/VTT/Excel, SRT only, video only, or an entire folder batch.") },
    { id = 2, label = L("2 · SOSTITUISCI & LINGUE", "2 · REPLACE & LANG"),
      help = L("Aggiorna i sottotitoli (con copia di sicurezza su traccia BKP muta) o aggiungi una traccia lingua Reference.", "Update subtitles (with muted BKP track safety copy) or add a Reference language track.") },
    { id = 3, label = L("3 · MODIFICA & ACCORPA", "3 · EDIT & COALESCE") .. edit_badge,
      help = L("Ispeziona e correggi il testo, accorpa automaticamente gli item brevi da 1-3 parole, unisci, dividi o sposta.", "Inspect and edit cue text, auto-coalesce 1-3 word micro-items, merge, split, or nudge.") },
    { id = 4, label = L("4 · ESPORTA", "4 · EXPORT"),
      help = L("Esporta gli SRT finali da qualsiasi traccia testi (per video o regioni) oppure dai take marker dell'audio.", "Export final SRTs from any subtitle track (by video or region) or from audio take markers.") },
  }
  for i, t in ipairs(tabs) do
    local r = { x = pad + (i - 1) * (tw + gap), y = ty, w = tw, h = 36 }
    if draw_tab_btn(r, t.label, state.tab == t.id, clicked, t.help) then
      state.tab = t.id
      save_prefs()
    end
  end
end

---------------------------------------------------------------------------
-- 6. SCHEDA 1 · CARICA
---------------------------------------------------------------------------

local function run_single_import(mode)
  local res, err = ENG.import_single({
    mode             = mode,
    pos_mode         = state.pos_mode,
    overlap_mode     = state.overlap_mode,
    coalesce_opts    = current_coalesce_opts(state.coalesce_import),
    create_region    = state.create_region,
    create_vox_track = state.create_vox,
    copy_to_media    = state.copy_to_media,
    track_name       = state.active_track_name
  })
  dirty_scan = true
  if err then
    set_status("err", err)
  elseif res then
    local parts = {}
    if res.video_name then parts[#parts + 1] = "Video: " .. res.video_name end
    if res.srt_name then parts[#parts + 1] = string.format("%s (%d cue)", res.srt_name, res.cues or 0) end
    if (res.absorbed or 0) > 0 then parts[#parts + 1] = string.format(L("%d micro-item accorpati", "%d short cues coalesced"), res.absorbed) end
    if (res.overlaps or 0) > 0 and state.overlap_mode == "lane" then
      parts[#parts + 1] = string.format(L("%d sovrapposte in corsia 2", "%d overlaps on lane 2"), res.overlaps)
    end
    if state.copy_to_media and not res.copied_media and res.srt_name then
      parts[#parts + 1] = L("progetto non salvato: SRT letto sul posto", "unsaved project: SRT linked in place")
    end
    set_status("ok", table.concat(parts, "  ·  "))
  end
end

local function draw_tab_load(ctx, clicked)
  local pad, y0, h0 = 20, 144, gfx.h - 242
  local col_gap = 16
  local lw = math.floor((gfx.w - pad * 2 - col_gap) * 0.49)
  local rw = (gfx.w - pad * 2 - col_gap) - lw

  local left  = draw_section_panel({ x = pad, y = y0, w = lw, h = h0 }, L("COSA CARICARE IN TIMELINE", "WHAT TO LOAD INTO TIMELINE"))
  local right = draw_section_panel({ x = pad + lw + col_gap, y = y0, w = rw, h = h0 }, L("POSIZIONE E REGOLE D'INGRESSO", "PLACEMENT & IMPORT RULES"))

  local by = left.y + 2
  local cards = {
    {
      title = L("Video + SRT / VTT / Excel…", "Video + SRT / VTT / Excel…"),
      sub   = L("Importa il video, crea la regione e allinea le battute", "Imports video, creates region, and aligns subtitle cues"),
      fn    = function() run_single_import("video_srt") end
    },
    {
      title = L("Solo SRT / VTT / Excel…", "SRT / VTT / Excel only…"),
      sub   = (function()
        local base = L("Carica solo i sottotitoli su «" .. ctx.active_track_name .. "»", "Loads cues onto track «" .. ctx.active_track_name .. "»")
        if state.pos_mode ~= "auto" then return base end
        if ctx.cur_region then
          return L("Timecode dalla regione «" .. ctx.cur_region.name .. "»", "Timecode from region «" .. ctx.cur_region.name .. "»")
        elseif #ctx.sel_videos > 0 then
          return L("Sotto il video «" .. ctx.sel_videos[1].base .. "»", "Under video «" .. ctx.sel_videos[1].base .. "»")
        end
        return base .. L(" · alla playhead", " · at playhead")
      end)(),
      fn    = function() run_single_import("srt_only") end
    },
    {
      title = L("Solo Video…", "Video only…"),
      sub   = L("Carica il video sulla traccia VIDEO", "Loads video onto VIDEO track"),
      fn    = function() run_single_import("video_only") end
    },
    {
      title = L("Cartella Batch (Video + SRT omonimi)…", "Folder Batch (Videos + matching SRTs)…"),
      sub   = L("Accoda tutti i video di una cartella coi rispettivi SRT/VTT", "Queues all videos in a folder with matching SRT/VTT files"),
      fn    = function()
        local res, err = ENG.import_folder_batch({
          pos_mode         = state.pos_mode,
          overlap_mode     = state.overlap_mode,
          coalesce_opts    = current_coalesce_opts(state.coalesce_import),
          create_region    = state.create_region,
          create_vox_track = state.create_vox,
          copy_to_media    = state.copy_to_media,
          batch_gap        = state.batch_gap,
          track_name       = state.active_track_name
        })
        dirty_scan = true
        if err then set_status("err", err)
        elseif res then
          set_status("ok", string.format(
            L("Cartella «%s»: %d video, %d SRT (%d battute, %d brevi accorpate).",
              "Folder «%s»: %d videos, %d SRTs (%d cues, %d short coalesced)."),
            res.folder, res.videos, res.srts, res.cues, res.absorbed or 0
          ))
        end
      end
    }
  }

  for _, c in ipairs(cards) do
    if draw_action_card({ x = left.x, y = by, w = left.w, h = 52 }, c.title, c.sub, true, clicked, "blue", c.sub) then
      c.fn()
    end
    by = by + 62
  end

  local gy = left.y + left.h - 30
  gfx.setfont(1, "Arial", 13)
  UI.set_color(UI.colors.muted)
  gfx.x, gfx.y = left.x, gy + 6
  gfx.drawstr(L("Stacco cartella batch:", "Folder batch gap:"))
  local gx = left.x + 150
  for _, gval in ipairs({ 1, 3, 5, 10 }) do
    if draw_seg_btn({ x = gx, y = gy, w = 52, h = 28, font = 13 }, tostring(gval) .. "s", state.batch_gap == gval, true, clicked, "seg") then
      state.batch_gap = gval; save_prefs()
    end
    gx = gx + 58
  end

  -- Colonna destra
  local ry = right.y + 2
  gfx.setfont(1, "Arial", 13, "b")
  UI.set_color(UI.colors.title)
  gfx.x, gfx.y = right.x, ry
  gfx.drawstr(L("Punto di inserimento in timeline", "Timeline insertion point"))
  ry = ry + 22

  local pos_opts = {
    { id = "cursor",         label = L("Alla Playhead", "At Playhead") },
    { id = "zero",           label = "00:00:00" },
    { id = "selected_video", label = L("Sul video selezionato", "On selected video") },
    { id = "end",            label = L("In coda al progetto", "At project end") },
  }
  -- Riga "Auto": la regione sotto la playhead comanda il timecode; senza regione, sotto il video selezionato
  if draw_seg_btn({ x = right.x, y = ry, w = right.w, h = 30, font = 13 },
      L("Auto: regione › video selezionato › playhead", "Auto: region › selected video › playhead"),
      state.pos_mode == "auto", true, clicked, "seg",
      L("Clicca un video in timeline, oppure fai doppio clic su una regione: la regione comanda il timecode, altrimenti l'SRT va sotto il video selezionato, altrimenti alla playhead.",
        "Click a video in the timeline, or double-click a region: the region sets the timecode, otherwise the SRT goes under the selected video, otherwise at the playhead.")) then
    state.pos_mode = "auto"; save_prefs()
  end
  ry = ry + 36
  local pw = math.floor((right.w - 8) / 2)
  for i, p in ipairs(pos_opts) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local pr = { x = right.x + col * (pw + 8), y = ry + row * 34, w = pw, h = 29, font = 13 }
    local en = (p.id ~= "selected_video") or (#ctx.sel_videos > 0)
    if draw_seg_btn(pr, p.label, state.pos_mode == p.id, en, clicked, "seg") then
      state.pos_mode = p.id; save_prefs()
    end
  end
  ry = ry + 74

  gfx.setfont(1, "Arial", 13, "b")
  UI.set_color(UI.colors.title)
  gfx.x, gfx.y = right.x, ry
  gfx.drawstr(L("Sovrapposizioni tra battute", "Overlapping cues"))
  ry = ry + 22

  local ow = math.floor((right.w - 8) / 2)
  if draw_seg_btn({ x = right.x, y = ry, w = ow, h = 29, font = 13 },
      L("2ª corsia rossa (integra)", "2nd red lane (intact)"), state.overlap_mode == "lane", true, clicked, "seg") then
    state.overlap_mode = "lane"; save_prefs()
  end
  if draw_seg_btn({ x = right.x + ow + 8, y = ry, w = right.w - ow - 8, h = 29, font = 13 },
      L("Accorcia coda precedente", "Trim previous tail"), state.overlap_mode == "trim", true, clicked, "seg") then
    state.overlap_mode = "trim"; save_prefs()
  end
  ry = ry + 40

  local toggles = {
    {
      val = state.coalesce_import,
      lbl = string.format(L("Accorpa subito item brevi (≤ %d parole)", "Coalesce short cues on import (≤ %d words)"), state.short_max_words),
      hlp = L("Unisce automaticamente le paroline isolate da 1-2 parole lasciate da Whisper/MacWhisper al dialogo adiacente.", "Automatically merges isolated 1-2 word Whisper slivers into their adjacent dialogue cue."),
      set = function(v) state.coalesce_import = v end
    },
    {
      val = state.create_region,
      lbl = L("Crea regione di progetto col nome del video", "Create project region named after video"),
      hlp = L("Comoda per esportare in seguito gli SRT o i render per singolo episodio/clip.", "Handy for later per-clip SRT export or rendering."),
      set = function(v) state.create_region = v end
    },
    {
      val = state.create_vox,
      lbl = L("Crea traccia audio VOX se assente", "Create VOX audio track if missing"),
      hlp = L("Prepara subito una traccia VOX pulita per registrare.", "Prepares a clean VOX track ready for recording."),
      set = function(v) state.create_vox = v end
    },
    {
      val = state.copy_to_media,
      lbl = ctx.saved_dir
        and L("Copia e registra SRT in Media/ del progetto", "Copy & register SRT in project Media/")
        or  L("Copia in Media/ (salva il progetto per attivarla)", "Copy to Media/ (save project to activate)"),
      hlp = L("Con ZP Consolidate e il registro di progetto, gli SRT restano sempre dentro Media/ senza toccare gli originali esterni.", "Keeps imported SRTs inside project Media/ without altering external originals."),
      set = function(v) state.copy_to_media = v end
    }
  }

  for _, tg in ipairs(toggles) do
    if draw_toggle_row({ x = right.x, y = ry, w = right.w, h = 29 }, tg.lbl, tg.val, true, clicked, tg.hlp) then
      tg.set(not tg.val); save_prefs()
    end
    ry = ry + 34
  end
end

---------------------------------------------------------------------------
-- 7. SCHEDA 2 · SOSTITUISCI & LINGUE
---------------------------------------------------------------------------

local function run_replace_action(scope)
  local res, err = ENG.replace_or_add_language({
    operation     = state.rep_op,
    scope         = scope,
    lang_suffix   = state.lang_suffix,
    track_name    = state.active_track_name,
    make_backup   = state.make_bkp,
    overlap_mode  = state.overlap_mode,
    copy_to_media = state.copy_to_media,
    coalesce_opts = current_coalesce_opts(state.coalesce_import)
  })
  dirty_scan = true
  if err then
    set_status("err", err)
  elseif res then
    local msg = string.format(
      L("Traccia «%s»: %d blocchi aggiornati, %d battute", "Track «%s»: %d blocks updated, %d cues"),
      res.track_name, res.blocks, res.cues
    )
    if (res.backed_up or 0) > 0 and res.bkp_track then
      msg = msg .. string.format(L(" (%d vecchi item in mute su «%s»)", " (%d old items muted on «%s»)"), res.backed_up, res.bkp_track)
    end
    if (res.absorbed or 0) > 0 then
      msg = msg .. string.format(L(", %d brevi accorpate", ", %d short coalesced"), res.absorbed)
    end
    set_status("ok", msg .. ".")
  end
end

local function draw_tab_replace(ctx, clicked)
  local pad, y0, h0 = 20, 144, gfx.h - 242
  local col_gap = 16
  local lw = math.floor((gfx.w - pad * 2 - col_gap) * 0.48)
  local rw = (gfx.w - pad * 2 - col_gap) - lw

  local left  = draw_section_panel({ x = pad, y = y0, w = lw, h = h0 }, L("MODALITA' E LINGUA", "MODE & LANGUAGE"))
  local right = draw_section_panel({ x = pad + lw + col_gap, y = y0, w = rw, h = h0 }, L("DOVE APPLICARE IN TIMELINE", "WHERE TO APPLY IN TIMELINE"))

  local ly = left.y + 4
  local bw = math.floor((left.w - 8) / 2)
  if draw_seg_btn({ x = left.x, y = ly, w = bw, h = 34, font = 14 },
      L("Sostituisci testi", "Replace subtitles"), state.rep_op == "replace", true, clicked, "seg") then
    state.rep_op = "replace"; save_prefs()
  end
  if draw_seg_btn({ x = left.x + bw + 8, y = ly, w = left.w - bw - 8, h = 34, font = 14 },
      L("Aggiungi lingua / Ref", "Add Language / Ref"), state.rep_op == "reference", true, clicked, "seg") then
    state.rep_op = "reference"; save_prefs()
  end
  ly = ly + 46

  if state.rep_op == "reference" then
    gfx.setfont(1, "Arial", 13, "b")
    UI.set_color(UI.colors.title)
    gfx.x, gfx.y = left.x, ly
    gfx.drawstr(UI.fit_text(L("Sigla lingua → «Rythmo Band Testi " .. state.lang_suffix .. "»", "Language tag → «Rythmo Band Testi " .. state.lang_suffix .. "»"), left.w))
    ly = ly + 22
    local presets = { "ENG", "ORIG", "FRA", "ESP", "DEU" }
    local cw = math.floor((left.w - 5 * 6) / 6)
    for i, tag in ipairs(presets) do
      if draw_seg_btn({ x = left.x + (i - 1) * (cw + 6), y = ly, w = cw, h = 30, font = 13 }, tag, state.lang_suffix == tag, true, clicked, "seg") then
        state.lang_suffix = tag; save_prefs()
      end
    end
    local custom_x = left.x + 5 * (cw + 6)
    if draw_seg_btn({ x = custom_x, y = ly, w = left.w - 5 * (cw + 6), h = 30, font = 13 }, L("Altro…", "Custom…"), false, true, clicked, "subtle") then
      local ok, v = reaper.GetUserInputs(L("Sigla lingua Reference", "Reference language tag"), 1, L("Sigla (es. POR, JPN, TRAD):", "Tag (e.g. POR, JPN, REF):"), state.lang_suffix)
      if ok and ENG.trim(v) ~= "" then
        state.lang_suffix = ENG.trim(v):upper():gsub("[^%w_%-]", "")
        save_prefs()
      end
    end
    ly = ly + 44
  else
    gfx.setfont(1, "Arial", 13)
    UI.set_color(UI.colors.muted)
    local info_lines = UI.wrap_text(
      L("Aggiorna le battute sulla traccia attiva «" .. ctx.active_track_name .. "» solo nell'intervallo del video o della regione scelta, lasciando intatto il resto della timeline.",
        "Updates cues on active track «" .. ctx.active_track_name .. "» strictly within the chosen video or region range, leaving the rest untouched."),
      left.w
    )
    for _, ln in ipairs(info_lines) do
      gfx.x, gfx.y = left.x, ly; gfx.drawstr(ln); ly = ly + 19
    end
    ly = ly + 12
  end

  if draw_toggle_row({ x = left.x, y = ly, w = left.w, h = 30 },
      L("Salva vecchie battute su traccia BKP (in mute)", "Keep old cues on muted BKP safety track"), state.make_bkp, true, clicked,
      L("Sposta le vecchie battute sostituite su un'unica traccia muta «BKP» invece di cancellarle.", "Moves replaced cues onto a single muted «BKP» safety track instead of deleting them.")) then
    state.make_bkp = not state.make_bkp; save_prefs()
  end
  ly = ly + 36

  if draw_toggle_row({ x = left.x, y = ly, w = left.w, h = 30 },
      string.format(L("Accorpa item brevi (≤ %d parole)", "Coalesce short cues (≤ %d words)"), state.short_max_words), state.coalesce_import, true, clicked) then
    state.coalesce_import = not state.coalesce_import; save_prefs()
  end
  ly = ly + 36

  if draw_toggle_row({ x = left.x, y = ly, w = left.w, h = 30 },
      L("Accorcia sovrapposizioni invece della 2ª corsia", "Trim overlaps instead of 2nd red lane"), state.overlap_mode == "trim", true, clicked) then
    state.overlap_mode = (state.overlap_mode == "trim") and "lane" or "trim"; save_prefs()
  end

  local ry = right.y + 6
  local verb = (state.rep_op == "reference")
    and (L("Aggiungi «", "Add «") .. state.lang_suffix .. "» ")
    or  L("Sostituisci ", "Replace ")

  if draw_action_card({ x = right.x, y = ry, w = right.w, h = 58 },
      verb .. string.format(L("sui video selezionati (%d)", "on selected videos (%d)"), #ctx.sel_videos),
      L("Chiede l'SRT/VTT/Excel per ciascun video selezionato (1 o più video)", "Prompts for SRT/VTT/Excel for each selected video (1 or multiple)"),
      #ctx.sel_videos > 0, clicked, "blue") then
    run_replace_action("selected_videos")
  end
  ry = ry + 72

  local reg_lbl = ctx.cur_region and ("«" .. UI.fit_text(ctx.cur_region.name, 140) .. "»") or L("(nessuna al cursore)", "(none at cursor)")
  if draw_action_card({ x = right.x, y = ry, w = right.w, h = 58 },
      verb .. L("nella regione ", "in region ") .. reg_lbl,
      L("Allinea i tempi dell'SRT all'inizio della regione sotto la playhead", "Aligns SRT timestamps to the start of the region under the playhead"),
      ctx.cur_region ~= nil, clicked, "blue") then
    run_replace_action("cursor_region")
  end
  ry = ry + 72

  if draw_action_card({ x = right.x, y = ry, w = right.w, h = 58 },
      verb .. string.format(L("da file omonimi su tutti i video (%d)", "from matching files on all videos (%d)"), #ctx.all_videos),
      L("Cerca automaticamente accanto a ogni video un .srt/.vtt con lo stesso nome", "Automatically loads matching sidecar .srt/.vtt files next to project videos"),
      #ctx.all_videos > 0, clicked, "blue") then
    run_replace_action("all_matching")
  end
end

---------------------------------------------------------------------------
-- 8. SCHEDA 3 · MODIFICA & ACCORPA
---------------------------------------------------------------------------

local function draw_tab_edit(ctx, clicked)
  local pad, y0, h0 = 20, 144, gfx.h - 242
  local col_gap = 16
  local lw = math.floor((gfx.w - pad * 2 - col_gap) * 0.45)
  local rw = (gfx.w - pad * 2 - col_gap) - lw

  local left  = draw_section_panel({ x = pad, y = y0, w = lw, h = h0 }, L("ISPETTORE & TESTO BATTUTA LIVE", "LIVE CUE INSPECTOR & TEXT"))
  local right = draw_section_panel({ x = pad + lw + col_gap, y = y0, w = rw, h = h0 }, L("ACCORPA ITEM BREVI · UNISCI · DIVIDI · SPOSTA", "COALESCE SHORT CUES · MERGE · SPLIT · NUDGE"))

  local info = ctx.sel_info
  local ly = left.y + 2
  local btn_bar_y = left.y + left.h - 34

  if not info then
    gfx.setfont(1, "Arial", 14)
    UI.set_color(UI.colors.muted)
    local msg = UI.wrap_text(
      L("Seleziona un item in timeline per vederne origine, durata, CPS e testo completo, oppure crea subito una nuova battuta alla playhead.",
        "Select any timeline item to inspect its source, duration, CPS, and full text, or create a new cue at the playhead."),
      left.w
    )
    for _, ln in ipairs(msg) do gfx.x, gfx.y = left.x, ly; gfx.drawstr(ln); ly = ly + 21 end
  else
    local rows = {
      { L("Traccia", "Track"), info.track_name .. (info.count > 1 and string.format(L("  (+%d sel.)", "  (+%d sel.)"), info.count - 1) or "") },
      { L("Tempo", "Time"),    fmt_tc(info.pos) .. " → " .. fmt_tc(info.end_pos) .. string.format("  (%.2f s)", info.len) },
    }
    if info.is_text then
      rows[#rows + 1] = {
        L("Metriche", "Metrics"),
        string.format(L("%d parole · %d righe · %.1f CPS", "%d words · %d lines · %.1f CPS"), info.words, info.lines, info.cps)
      }
      local orig_str
      if info.sync_key ~= "" then
        orig_str = L("Agganciata a marker audio (29)", "Linked to audio marker (29)")
      elseif info.srt_file ~= "" or info.srt_cue ~= "" then
        orig_str = (info.srt_file ~= "" and info.srt_file or "SRT") .. (info.srt_cue ~= "" and ("  #" .. info.srt_cue) or "")
      else
        orig_str = L("Scritta / modificata in timeline", "Manual / timeline cue")
      end
      rows[#rows + 1] = { L("Origine", "Origin"), orig_str }
    elseif info.is_video then
      rows[#rows + 1] = { L("Tipo", "Type"), L("Item Video: ", "Video item: ") .. ENG.basename(info.src_path) }
    elseif info.is_audio then
      rows[#rows + 1] = { L("Audio", "Audio"), ENG.basename(info.src_path) .. string.format(L(" (%d marker)", " (%d markers)"), info.take_markers or 0) }
    end

    for _, kv in ipairs(rows) do
      gfx.setfont(1, "Arial", 13)
      UI.set_color(UI.colors.muted)
      gfx.x, gfx.y = left.x, ly
      gfx.drawstr(kv[1] .. ":")
      gfx.setfont(1, "Arial", 13, "b")
      if kv[1] == L("Metriche", "Metrics") and info.cps > 20 then
        gfx.set(0.98, 0.78, 0.32, 1)
      else
        UI.set_color(UI.colors.text)
      end
      gfx.x, gfx.y = left.x + 72, ly
      gfx.drawstr(UI.fit_text(kv[2], left.w - 74))
      ly = ly + 20
    end

    if info.is_text then
      ly = ly + 6
      local box_h = math.max(56, btn_bar_y - ly - 10)
      local box_r = { x = left.x, y = ly, w = left.w, h = box_h }
      local b_hover = in_rect(box_r)
      gfx.set(b_hover and 0.09 or 0.06, b_hover and 0.10 or 0.065, b_hover and 0.13 or 0.085, 1)
      UI.fill_round(box_r.x, box_r.y, box_r.w, box_r.h, 5)
      gfx.set(b_hover and 0.44 or 0.26, b_hover and 0.56 or 0.28, b_hover and 0.74 or 0.36, 1)
      if gfx.roundrect then gfx.roundrect(box_r.x, box_r.y, box_r.w - 1, box_r.h - 1, 5, true) end
      hint_rect(box_r, L("Clicca sul riquadro o su «Modifica testo…» per correggere la battuta.", "Click the text box or «Edit text…» to edit this cue."))
      if clicked and b_hover then
        open_item_editor(info.item)
      end

      gfx.setfont(1, "Arial", 15)
      UI.set_color(info.text ~= "" and UI.colors.text or UI.colors.muted)
      local preview = info.text ~= "" and info.text or L("(battuta vuota — clicca per scrivere)", "(empty cue — click to type)")
      local wrapped = UI.wrap_text(preview, box_r.w - 18)
      local max_ln = math.max(1, math.floor((box_r.h - 12) / 21))
      for i = 1, math.min(#wrapped, max_ln) do
        gfx.x, gfx.y = box_r.x + 9, box_r.y + 6 + (i - 1) * 21
        local s = (i == max_ln and #wrapped > max_ln) and UI.fit_text(wrapped[i] .. " …", box_r.w - 18) or wrapped[i]
        gfx.drawstr(s)
      end
    end
  end

  local half_l = math.floor((left.w - 8) / 2)
  local can_edit = info ~= nil and info.is_text
  if draw_seg_btn({ x = left.x, y = btn_bar_y, w = half_l, h = 32, font = 14 },
      L("Modifica testo…", "Edit text…"), can_edit, can_edit, clicked, "seg",
      L("Apre l'editor completo (Incolla pulito, Pulisci spazi, Unisci righe PDF, Evidenzia) dentro ZP SRT.", "Opens the full script editor right inside ZP SRT.")) then
    open_item_editor(info.item)
  end

  if draw_seg_btn({ x = left.x + half_l + 8, y = btn_bar_y, w = left.w - half_l - 8, h = 32, font = 14 },
      L("+ Nuova battuta qui", "+ New cue here"), false, true, clicked, "green",
      L("Crea un item di testo di 3 s alla playhead sulla traccia attiva e apre subito l'editor.", "Creates a 3 s subtitle cue at the playhead and opens the editor immediately.")) then
    local created = ENG.create_blank_cue(ctx.active_track_name, "TESTO", 3.0)
    dirty_scan = true
    if created then open_item_editor(created, L("Nuova battuta", "New cue")) end
  end

  -- DESTRA: 1) Accorpa item brevi  2) Unisci & Dividi  3) Nudge
  local ry = right.y + 2
  gfx.setfont(1, "Arial", 13, "b")
  UI.set_color(UI.colors.gold)
  gfx.x, gfx.y = right.x, ry
  gfx.drawstr(UI.fit_text(L("Accorpa item brevi (assorbe le paroline isolate nel dialogo vicino)", "Coalesce short cues (absorbs isolated 1-3 word crumbs into dialogue)"), right.w))
  ry = ry + 22

  gfx.setfont(1, "Arial", 13)
  UI.set_color(UI.colors.muted)
  gfx.x, gfx.y = right.x, ry + 5
  gfx.drawstr(L("Soglia:", "Max:"))
  local sx = right.x + 50
  for _, wopt in ipairs({ { 1, "1 par." }, { 2, L("≤2 par.", "≤2 w") }, { 3, L("≤3 par.", "≤3 w") } }) do
    if draw_seg_btn({ x = sx, y = ry, w = 62, h = 26, font = 13 }, wopt[2], state.short_max_words == wopt[1], true, clicked, "seg") then
      state.short_max_words = wopt[1]; save_prefs(); dirty_scan = true
    end
    sx = sx + 66
  end

  gfx.setfont(1, "Arial", 13)
  UI.set_color(UI.colors.muted)
  gfx.x, gfx.y = sx + 6, ry + 5
  gfx.drawstr("Gap:")
  sx = sx + 40
  for _, gopt in ipairs({ 0.5, 0.9, 1.5 }) do
    if draw_seg_btn({ x = sx, y = ry, w = 48, h = 26, font = 13 }, string.format("%.1fs", gopt), math.abs(state.short_max_gap - gopt) < 0.05, true, clicked, "seg") then
      state.short_max_gap = gopt; save_prefs(); dirty_scan = true
    end
    sx = sx + 52
  end
  ry = ry + 34

  local c_opts = current_coalesce_opts(true)
  local w3 = math.floor((right.w - 12) / 3)
  local coal_btns = {
    {
      scope = "selected",
      label = string.format(L("Selezionati (%d)", "Selected (%d)"), ctx.short_sel),
      en    = #ctx.sel_texts >= 2 and ctx.short_sel > 0,
      hlp   = L("Accorpa i micro-item solo tra le battute selezionate (1 solo passo di Undo, preserva ancore Gobbo).", "Coalesces short crumbs strictly within selected text items (single Undo step, preserves Gobbo anchors).")
    },
    {
      scope = "region",
      label = string.format(L("Regione (%d)", "Region (%d)"), ctx.short_reg),
      en    = ctx.cur_region ~= nil and ctx.short_reg > 0,
      hlp   = L("Accorpa tutti i micro-item dentro la regione sotto la playhead.", "Coalesces all short crumbs inside the region under the playhead.")
    },
    {
      scope = "track",
      label = string.format(L("Traccia (%d)", "Track (%d)"), ctx.short_trk),
      en    = ctx.active_track ~= nil and ctx.short_trk > 0,
      hlp   = L("Pulisce l'intera traccia testi attiva dai micro-item isolati rispettando pause e cambi personaggio.", "Cleans the entire active subtitle track from isolated crumbs while respecting pauses and speaker changes.")
    }
  }
  for i, cb in ipairs(coal_btns) do
    local w_use = (i == 3) and (right.w - 2 * (w3 + 6)) or w3
    if draw_seg_btn({ x = right.x + (i - 1) * (w3 + 6), y = ry, w = w_use, h = 36, font = 13 },
        cb.label, false, cb.en, clicked, cb.en and "green" or "seg", cb.hlp) then
      local res, err = ENG.run_short_coalesce(cb.scope, ctx.active_track, c_opts)
      dirty_scan = true
      if err then set_status("err", err)
      elseif res then
        set_status("ok", string.format(
          L("Accorpamento completato: %d micro-item assorbiti in %d battute (Cmd+Z per annullare).",
            "Coalescing complete: %d short items absorbed into %d cues (Cmd+Z to undo)."),
          res.absorbed, res.groups
        ))
      end
    end
  end
  ry = ry + 50

  gfx.set(0.18, 0.20, 0.26, 1)
  gfx.line(right.x, ry - 7, right.x + right.w, ry - 7)
  gfx.setfont(1, "Arial", 13, "b")
  UI.set_color(UI.colors.title)
  gfx.x, gfx.y = right.x, ry
  gfx.drawstr(L("Unione e divisione manuale", "Manual merge & split"))
  ry = ry + 22

  local mw = math.floor((right.w - 12) / 3)
  local merge_lbl = (#ctx.sel_texts >= 2)
    and string.format(L("Unisci sel. (%d)", "Merge sel. (%d)"), #ctx.sel_texts)
    or  L("Unisci + prossima", "Merge + next")
  if draw_seg_btn({ x = right.x, y = ry, w = mw, h = 36, font = 13 }, merge_lbl, false, #ctx.sel_texts >= 1, clicked, "seg",
      L("Con 1 battuta selezionata la unisce alla successiva; con 2 o più selezionate le unisce tutte in una.", "With 1 cue selected merges with the next one; with 2+ selected merges them all into one.")) then
    local res, err = ENG.merge_selected_or_next()
    dirty_scan = true
    if err then set_status("err", err)
    elseif res then set_status("ok", string.format(L("Unite %d battute.", "Merged %d cues."), res.count or 2)) end
  end

  if draw_seg_btn({ x = right.x + mw + 6, y = ry, w = mw, h = 36, font = 13 },
      L("Dividi a Playhead", "Split at Playhead"), false, ctx.active_track ~= nil or #ctx.sel_texts > 0, clicked, "seg",
      L("Taglia la battuta alla playhead spezzando il testo sul confine di parola o frase corrispondente.", "Splits the cue at the playhead, snapping the text cut to the matching word or sentence boundary.")) then
    local res, err = ENG.split_at_playhead(ctx.active_track)
    dirty_scan = true
    if err then set_status("err", err)
    elseif res then set_status("ok", L("Battuta divisa alla playhead.", "Cue split at playhead.")) end
  end

  if draw_seg_btn({ x = right.x + (mw + 6) * 2, y = ry, w = right.w - (mw + 6) * 2, h = 36, font = 13 },
      L("Separa righe", "Split lines"), false, #ctx.sel_texts > 0, clicked, "seg",
      L("Se una battuta contiene 2-3 righe o più frasi accorpate, le separa in battute consecutive proporzionali.", "Separates a multi-line or multi-sentence cue into consecutive proportional cues.")) then
    local res, err = ENG.split_multiline_selected()
    dirty_scan = true
    if err then set_status("err", err)
    elseif res then
      set_status("ok", string.format(L("Separate %d battute in %d item.", "Split %d cues into %d items."), res.split_items, res.resulting))
    end
  end
  ry = ry + 50

  gfx.set(0.18, 0.20, 0.26, 1)
  gfx.line(right.x, ry - 7, right.x + right.w, ry - 7)
  gfx.setfont(1, "Arial", 13, "b")
  UI.set_color(UI.colors.title)
  gfx.x, gfx.y = right.x, ry
  gfx.drawstr(L("Sposta nel tempo le battute selezionate", "Nudge selected cues in time"))
  ry = ry + 22

  local nudges = {
    { lbl = "-500ms", dt = -0.5,  snap = false },
    { lbl = "-100ms", dt = -0.1,  snap = false },
    { lbl = "+100ms", dt =  0.1,  snap = false },
    { lbl = "+500ms", dt =  0.5,  snap = false },
    { lbl = L("1ª → Playhead", "1st → Playhead"), dt = 0, snap = true },
  }
  local nw = math.floor((right.w - 4 * 6) / 5)
  for i, nd in ipairs(nudges) do
    local w_use = (i == 5) and (right.w - 4 * (nw + 6)) or nw
    if draw_seg_btn({ x = right.x + (i - 1) * (nw + 6), y = ry, w = w_use, h = 32, font = 13 },
        nd.lbl, false, #ctx.sel_texts > 0, clicked, "seg",
        L("Sposta tutte le battute di testo selezionate mantenendo intatte le distanze reciproche.", "Shifts all selected text cues together while keeping their relative spacing.")) then
      local res, err = ENG.nudge_text_items("selected", ctx.active_track, nd.dt, nd.snap)
      dirty_scan = true
      if err then set_status("err", err)
      elseif res then
        set_status("ok", string.format(L("Spostate %d battute (%+.3f s).", "Moved %d cues (%+.3f s)."), res.moved, res.shift))
      end
    end
  end
end

---------------------------------------------------------------------------
-- 9. SCHEDA 4 · ESPORTA
---------------------------------------------------------------------------

local function resolve_export_dir()
  local base = ENG.default_dir()
  if state.exp_dest == "project" then return base end
  if state.exp_dest == "custom" and state.exp_custom_dir ~= "" then return state.exp_custom_dir end
  return base .. sep .. "SRT_export"
end

local function run_timeline_export(ctx, scope)
  local res, err = ENG.export_timeline_srt({
    track         = ctx.active_track,
    scope         = scope,
    out_dir       = resolve_export_dir(),
    make_bak      = state.exp_bak,
    copy_to_media = state.copy_to_media
  })
  if err then
    set_status("err", err)
  elseif res then
    local first = res.files[1] and res.files[1].name or ""
    set_status("ok", string.format(
      L("Esportati %d file SRT (%s%s) in %s", "Exported %d SRT files (%s%s) to %s"),
      #res.files, first, (#res.files > 1 and "…" or ""), res.out_dir
    ))
  end
end

local function draw_tab_export(ctx, clicked)
  local pad, y0, h0 = 20, 144, gfx.h - 242
  local col_gap = 16
  local lw = math.floor((gfx.w - pad * 2 - col_gap) * 0.53)
  local rw = (gfx.w - pad * 2 - col_gap) - lw

  local left  = draw_section_panel({ x = pad, y = y0, w = lw, h = h0 }, L("ESPORTA SRT DALLA TRACCIA TESTI ATTIVA", "EXPORT SRT FROM ACTIVE SUBTITLE TRACK"))
  local right = draw_section_panel({ x = pad + lw + col_gap, y = y0, w = rw, h = h0 }, L("DESTINAZIONE & SRT DAI MARKER AUDIO", "DESTINATION & SRT FROM AUDIO MARKERS"))

  local ly = left.y + 2
  gfx.setfont(1, "Arial", 13)
  UI.set_color(UI.colors.muted)
  gfx.x, gfx.y = left.x, ly
  gfx.drawstr(UI.fit_text(
    L("Sorgente: «" .. ctx.active_track_name .. "» (tempi azzerati su ogni video/regione)",
      "Source: «" .. ctx.active_track_name .. "» (timecode zeroed per video/region)"),
    left.w
  ))
  ly = ly + 24

  local has_tr = ctx.active_track ~= nil
  local exp_modes = {
    {
      scope = "selected_videos",
      label = string.format(L("Esporta Video selezionati (%d)", "Export Selected videos (%d)"), #ctx.sel_videos),
      en    = has_tr and #ctx.sel_videos > 0,
      hlp   = L("Scrive un file .srt per ogni video selezionato, con timecode che parte da 00:00:00 sull'inizio del video.", "Writes one .srt per selected video, with timecode zeroed at each video's start.")
    },
    {
      scope = "cursor_region",
      label = L("Esporta Regione alla playhead", "Export Region at playhead") .. (ctx.cur_region and (" («" .. UI.fit_text(ctx.cur_region.name, 110) .. "»)") or ""),
      en    = has_tr and ctx.cur_region ~= nil,
      hlp   = L("Scrive il .srt della sola regione sotto il cursore, con timecode relativo all'inizio della regione.", "Writes the .srt for the region under the playhead, zeroed at the region start.")
    },
    {
      scope = "all_regions",
      label = string.format(L("Esporta Tutte le regioni (%d)", "Export All regions (%d)"), #ctx.regions),
      en    = has_tr and #ctx.regions > 0,
      hlp   = L("Scrive un .srt nominato per ciascuna regione del progetto.", "Writes one .srt per project region.")
    },
    {
      scope = "all_videos",
      label = string.format(L("Esporta Tutti i video (%d)", "Export All videos (%d)"), #ctx.all_videos),
      en    = has_tr and #ctx.all_videos > 0,
      hlp   = L("Scrive un .srt per ciascun video presente in timeline.", "Writes one .srt per video item in the timeline.")
    },
    {
      scope = "whole_track",
      label = L("Esporta Intera traccia (da 00:00:00)", "Export Whole track (from 00:00:00)"),
      en    = has_tr,
      hlp   = L("Scrive tutte le battute della traccia in un unico .srt con i tempi assoluti dalla timeline.", "Writes all cues on the track into a single .srt starting from 00:00:00.")
    }
  }

  for _, em in ipairs(exp_modes) do
    if draw_action_card({ x = left.x, y = ly, w = left.w, h = 40 }, em.label, nil, em.en, clicked, "green", em.hlp) then
      run_timeline_export(ctx, em.scope)
    end
    ly = ly + 48
  end

  local ry = right.y + 2
  gfx.setfont(1, "Arial", 13, "b")
  UI.set_color(UI.colors.title)
  gfx.x, gfx.y = right.x, ry
  gfx.drawstr(L("Cartella di consegna", "Output folder"))
  ry = ry + 22

  local dw = math.floor((right.w - 12) / 3)
  if draw_seg_btn({ x = right.x, y = ry, w = dw, h = 30, font = 13 },
      "SRT_export", state.exp_dest == "srt_export", true, clicked, "seg") then
    state.exp_dest = "srt_export"; save_prefs()
  end
  if draw_seg_btn({ x = right.x + dw + 6, y = ry, w = dw, h = 30, font = 13 },
      L("Progetto", "Project"), state.exp_dest == "project", true, clicked, "seg") then
    state.exp_dest = "project"; save_prefs()
  end
  if draw_seg_btn({ x = right.x + (dw + 6) * 2, y = ry, w = right.w - (dw + 6) * 2, h = 30, font = 13 },
      L("Scegli…", "Choose…"), state.exp_dest == "custom", true, clicked, "seg") then
    local picked = ENG.choose_folder(resolve_export_dir(), L("Dove salvo gli SRT esportati?", "Choose SRT export folder"))
    if picked and picked ~= "" then
      state.exp_custom_dir = picked
      state.exp_dest = "custom"
      save_prefs()
    end
  end
  ry = ry + 36

  gfx.setfont(1, "Arial", 13)
  UI.set_color(UI.colors.muted)
  gfx.x, gfx.y = right.x, ry
  gfx.drawstr(UI.fit_text("→ " .. resolve_export_dir(), right.w))
  ry = ry + 24

  if draw_toggle_row({ x = right.x, y = ry, w = right.w, h = 29 },
      L("Conserva copia .bak se l'SRT esiste già", "Keep .bak backup if SRT already exists"), state.exp_bak, true, clicked) then
    state.exp_bak = not state.exp_bak; save_prefs()
  end
  ry = ry + 44

  gfx.set(0.18, 0.20, 0.26, 1)
  gfx.line(right.x, ry - 8, right.x + right.w, ry - 8)
  gfx.setfont(1, "Arial", 13, "b")
  UI.set_color(UI.colors.title)
  gfx.x, gfx.y = right.x, ry
  gfx.drawstr(L("SRT dai take marker dell'audio montato (31)", "SRT from edited audio take markers (31)"))
  ry = ry + 22

  local audio_cues = 0
  for _, s in ipairs(ctx.audio_srcs) do audio_cues = audio_cues + #(s.cues or {}) end

  gfx.setfont(1, "Arial", 13)
  UI.set_color(UI.colors.muted)
  local a_desc = (#ctx.audio_srcs == 0)
    and L("Seleziona uno o più item audio con marker delle battute (es. da 29 Trascrizione o dopo un Glue).",
          "Select one or more audio items containing dialogue take markers (e.g. from 29 Transcription or after Glue).")
    or  string.format(L("Pronti %d file sorgente audio (%d battute valide, esclusi #HSC e marker SOLO).",
                        "Ready: %d audio source files (%d valid cues, excluding #HSC & SOLO markers)."),
                      #ctx.audio_srcs, audio_cues)
  for _, ln in ipairs(UI.wrap_text(a_desc, right.w)) do
    gfx.x, gfx.y = right.x, ry; gfx.drawstr(ln); ry = ry + 19
  end
  ry = ry + 10

  if draw_action_card({ x = right.x, y = ry, w = right.w, h = 42 },
      string.format(L("Scrivi SRT dall'audio (%d cue)", "Write SRT from audio (%d cues)"), audio_cues),
      nil, audio_cues > 0, clicked, "green",
      L("Esporta i take marker degli item audio selezionati nella cartella di consegna qui sopra.", "Exports take markers of selected audio items into the output folder above.")) then
    local res, err = ENG.export_audio_markers_srt({
      out_dir       = resolve_export_dir(),
      existing_mode = state.exp_bak and "bak" or "overwrite",
      copy_to_media = state.copy_to_media
    })
    if err then set_status("err", err)
    elseif res then
      set_status("ok", string.format(
        L("Scritti %d SRT dai marker audio in %s", "Wrote %d SRTs from audio markers to %s"),
        #res.files, res.out_dir
      ))
    end
  end
end

---------------------------------------------------------------------------
-- 10. BARRA INFERIORE (PONTI RAPIDI + STATO / AIUTO CONTESTUALE)
---------------------------------------------------------------------------

local function draw_footer(clicked)
  local pad = 20
  local bridge_y = gfx.h - 86

  local bridges = {
    { label = L("Gobbo Verticale (02)", "Vertical Prompter (02)"),     script = "02_Gobbo_Verticale.lua",
      help  = L("Apre il Gobbo Verticale continuo per leggere, cercare parole e seguire tutte le tracce.", "Opens the continuous Vertical Teleprompter.") },
    { label = L("Gobbo Orizzontale (03)", "Horizontal Prompter (03)"), script = "03_Gobbo_Orizzontale.lua",
      help  = L("Apre la Rythmo Band orizzontale per il doppiaggio a sync stretto.", "Opens the Horizontal Rythmo Band prompter.") },
    { label = L("Trascrizione Audio (29)", "Audio Transcription (29)"), script = "29_ZP_Trascrizione.lua",
      help  = L("Apre 29 ZP Trascrizione per trascrivere un audio o agganciare un SRT ai suoi tagli.", "Opens 29 ZP Transcription to transcribe audio or bind an SRT that follows cuts.") },
    { label = L("SRT Tools Web (26)", "SRT Tools Web (26)"),           script = "26_SRT_Tools.lua",
      help  = L("Apre il convertitore per testi Word/TXT con timecode liberi o pulizie speciali.", "Opens SRT Tools converter for freeform Word/TXT scripts with timecodes.") },
  }

  local gap = 8
  local bw = math.floor((gfx.w - pad * 2 - gap * (#bridges - 1)) / #bridges)
  for i, br in ipairs(bridges) do
    local w_use = (i == #bridges) and (gfx.w - pad * 2 - (#bridges - 1) * (bw + gap)) or bw
    local r = { x = pad + (i - 1) * (bw + gap), y = bridge_y, w = w_use, h = 28, font = 13 }
    if draw_seg_btn(r, br.label, false, true, clicked, "subtle", br.help) then
      launch_companion(br.script)
    end
  end

  local sy = gfx.h - 50
  UI.set_color(UI.colors.panel_border)
  gfx.line(pad, sy - 4, gfx.w - pad, sy - 4)

  if status_msg and not hover_help then
    local c = status_msg.kind == "err" and { 0.40, 0.10, 0.10, 1 }
           or status_msg.kind == "warn" and { 0.36, 0.24, 0.08, 1 }
           or { 0.09, 0.28, 0.16, 1 }
    gfx.set(c[1], c[2], c[3], 1)
    UI.fill_round(pad, sy, gfx.w - pad * 2, 42, 5)
    gfx.setfont(1, "Arial", 14, "b")
    gfx.set(0.95, 0.96, 0.98, 1)
    local lines = UI.wrap_text(status_msg.text, gfx.w - pad * 2 - 48)
    for i = 1, math.min(2, #lines) do
      gfx.x, gfx.y = pad + 12, sy + 5 + (i - 1) * 18
      gfx.drawstr(lines[i])
    end
    if draw_seg_btn({ x = gfx.w - pad - 30, y = sy + 8, w = 24, h = 25, font = 13 }, "×", false, true, clicked, "subtle") then
      status_msg = nil
    end
  else
    gfx.setfont(1, "Arial", 14)
    UI.set_color(hover_help and UI.colors.text or UI.colors.muted)
    local msg = hover_help or L(
      "Passa col mouse su un comando per la guida rapida. Tutte le modifiche in timeline si annullano con un solo Cmd/Ctrl+Z.",
      "Hover over any control for quick guidance. Every timeline edit undoes cleanly in a single Cmd/Ctrl+Z."
    )
    local lines = UI.wrap_text(msg, gfx.w - pad * 2)
    for i = 1, math.min(2, #lines) do
      gfx.x, gfx.y = pad, sy + 2 + (i - 1) * 19
      gfx.drawstr(lines[i])
    end
  end
end

---------------------------------------------------------------------------
-- 11. CICLO PRINCIPALE GFX (CACHE BASATA SU STATE CHANGE: ZERO CARICO CPU)
---------------------------------------------------------------------------

if reaper.set_action_options then
  reaper.set_action_options(1 | 4)
  reaper.atexit(function() reaper.set_action_options(8) end)
end

-- Finestra di partenza ingrandita (1,25×): stesse proporzioni del layout 880×620, ma caratteri
-- fisicamente grandi come in ZP Consolidate (≈16 px di testo). Dimensione scelta dall'utente ricordata.
local WIN_ZOOM = 1.25
local init_w, init_h = math.floor(BASE_W * WIN_ZOOM), math.floor(BASE_H * WIN_ZOOM)
do
  local sw, sh = get_ext("SRT30_win", ""):match("^(%d+),(%d+)$")
  sw, sh = tonumber(sw), tonumber(sh)
  if sw and sh and sw >= 560 and sh >= 400 then init_w, init_h = sw, sh end
end
gfx.init("ZP Studio Suite - ZP SRT", init_w, init_h, 0)
local saved_win_w, saved_win_h = init_w, init_h

local last_down = false
local cached_ctx = nil
local last_proj_state = -1
local last_proj_ptr = nil
local last_sel_sig = ""
local last_cursor = -1
local last_ts_sig = ""
local function refresh_context_if_needed()
  local proj_ptr = reaper.EnumProjects(-1, "")
  local proj_state = reaper.GetProjectStateChangeCount(0)
  local sel_cnt = reaper.CountSelectedMediaItems(0)
  local first_it = sel_cnt > 0 and reaper.GetSelectedMediaItem(0, 0) or nil
  local last_it  = sel_cnt > 1 and reaper.GetSelectedMediaItem(0, sel_cnt - 1) or nil
  local sel_tr   = reaper.GetSelectedTrack(0, 0)
  local sel_sig  = string.format("%d:%s:%s:%s", sel_cnt, tostring(first_it), tostring(last_it), tostring(sel_tr))
  local cur_pos  = reaper.GetCursorPosition()
  local ts, te   = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local ts_sig   = string.format("%.3f:%.3f", ts or 0, te or 0)

  if dirty_scan or not cached_ctx or proj_state ~= last_proj_state or proj_ptr ~= last_proj_ptr or sel_sig ~= last_sel_sig then
    cached_ctx = ENG.scan_context(state.active_track_name, current_coalesce_opts(true))
    state.active_track_name = cached_ctx.active_track_name
    last_proj_state = proj_state
    last_proj_ptr   = proj_ptr
    last_sel_sig    = sel_sig
    last_cursor     = cur_pos
    last_ts_sig     = ts_sig
    dirty_scan      = false
  elseif math.abs(cur_pos - last_cursor) > 0.001 or ts_sig ~= last_ts_sig then
    -- Solo playhead o selezione temporale (doppio clic su regione): zero letture di tracce/item
    last_cursor = cur_pos
    last_ts_sig = ts_sig
    cached_ctx.cursor = cur_pos
    local old_rgn = cached_ctx.cur_region
    local new_rgn = ENG.region_at_cursor(cached_ctx.regions)
    cached_ctx.cur_region = new_rgn
    if new_rgn ~= old_rgn then
      if new_rgn and cached_ctx.trk_items then
        cached_ctx.short_reg = ENG.count_short_in_range(cached_ctx.trk_items, new_rgn.start_pos, new_rgn.end_pos, current_coalesce_opts(true))
      else
        cached_ctx.short_reg = 0
      end
    end
  end
end

local function loop()
  local ch = gfx.getchar()
  if ch < 0 then
    save_prefs()
    gfx.quit()
    return
  end

  local down = (gfx.mouse_cap & 1) == 1
  local pressed  = down and not last_down
  local released = (not down) and last_down
  local clicked  = pressed and (edit_modal == nil)
  last_down = down
  hover_help = nil

  -- ricorda la dimensione scelta (solo a mouse rilasciato: nessuna scrittura durante il trascinamento)
  if not down then
    local rw_, rh_ = gfx._real.w, gfx._real.h
    if rw_ and rh_ and (rw_ ~= saved_win_w or rh_ ~= saved_win_h) and rw_ > 0 and rh_ > 0 then
      saved_win_w, saved_win_h = rw_, rh_
      set_ext("SRT30_win", string.format("%d,%d", rw_, rh_))
    end
  end

  if edit_modal then
    process_editor_key(ch)
  elseif ch == 27 then
    save_prefs()
    gfx.quit()
    return
  end

  refresh_context_if_needed()

  UI.fill_background()
  -- Nessuna description sotto la firma: evita qualsiasi collisione con la barra contesto a y=62!
  UI.draw_header({ title = "ZP SRT", title_size = 22 })
  UI.draw_help_button({ x = gfx.w - 54, y = 16, w = 34, h = 28 }, clicked, "tool-30")

  draw_context_and_tabs(cached_ctx, clicked)

  if state.tab == 1 then
    draw_tab_load(cached_ctx, clicked)
  elseif state.tab == 2 then
    draw_tab_replace(cached_ctx, clicked)
  elseif state.tab == 3 then
    draw_tab_edit(cached_ctx, clicked)
  else
    draw_tab_export(cached_ctx, clicked)
  end

  draw_footer(clicked)

  if edit_modal then
    draw_editor_overlay(pressed, released)
  end

  gfx.update()
  reaper.defer(loop)
end

loop()
