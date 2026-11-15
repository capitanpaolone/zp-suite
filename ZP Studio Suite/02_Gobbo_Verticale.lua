-- @noindex

--[[
   * ReaScript Name: ZP Studio Suite Teleprompter Nativo
   * Linea: ZP Paolo Balestri
   * Suite: ZP Studio Suite for REAPER (versione dinamica dal 00)
   * Credito idea gobbo: da un'idea di Nicola Lanci.
   * Distribuzione gratuita.
   * Description: Versione TELEPROMPTER VERTICALE CONTINUO.
                  Mostra l'intero testo come un unico "documento" (stile copione o PDF),
                  evidenziando la battuta corrente e scorrendo la pagina
                  verticalmente per mantenere il focus al centro dello schermo.
]]

local default_track_name = "Rythmo Band Testi"
local notes_track_name = "Rythmo Band Note"
local notes_track_tcp_layout = "C"
local settings_section = "RythmoBand_Teleprompter"
local gobbo_state_section = "RythmoBand_Gobbo_State"
local gobbo_state_key = "vertical_ts"
local SCRIPT_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "")
local ZP_UI = dofile(SCRIPT_DIR .. 'ZP_UI.lua')
local ZP_TESTO = dofile(SCRIPT_DIR .. 'ZP_Testo_Copione.lua')
local ZP_EDITOR = dofile(SCRIPT_DIR .. 'ZP_Editor_Copione.lua')
local ZP_LINGUA
do
    local path = SCRIPT_DIR .. "ZP_Lingua.lua"
    local f = io.open(path, "r")
    if f then
        f:close()
        local ok, loaded = pcall(dofile, path)
        if ok and type(loaded) == "table" and type(loaded.T) == "function" then
            ZP_LINGUA = loaded
        end
    end
end
local function T(s)
    if ZP_LINGUA then return ZP_LINGUA.T(s) end
    if _G.T then return _G.T(s) end
    return s
end
local function SimpleSearchFallback()
    local M = {}
    function M.fold(s) return tostring(s or ""):gsub("\r\n", "\n"):gsub("\r", "\n"):lower() end
    function M.find(text, query)
        local q = tostring(query or ""):gsub('^"(.*)"$', "%1")
        q = q:gsub("^“(.*)”$", "%1")
        if q == "" then return nil end
        local a, b = M.fold(text):find(M.fold(q), 1, true)
        return a, b
    end
    function M.count(items, query, current_item)
        local total, current = 0, nil
        for _, item in ipairs(items or {}) do
            if M.find(item.notes or item.text or "", query) then
                total = total + 1
                if item == current_item then current = total end
            end
        end
        return total, current
    end
    function M.results(items, query, max_results)
        local out,total={},0
        for _,item in ipairs(items or {}) do
            local a,b=M.find(item.notes or item.text or "",query)
            if a then
                total=total+1
                if #out<(max_results or 500) then out[#out+1]={item=item,offset_start=a,offset_end=b,snippet=(item.notes or ""):sub(math.max(1,a-30),math.min(#(item.notes or ""),b+30)),snip_a=a-math.max(1,a-30)+1,snip_b=b-math.max(1,a-30)+1} end
            end
        end
        return out,total
    end
    function M.replace(text, query, replacement, all)
        text,replacement=tostring(text or ""),tostring(replacement or "")
        local chunks,cursor,from,n={},1,1,0
        while true do
            local a,b=M.find(text:sub(from),query)
            if not a then break end
            a,b=a+from-1,b+from-1
            chunks[#chunks+1]=text:sub(cursor,a-1); chunks[#chunks+1]=replacement
            n,cursor,from=n+1,b+1,b+1
            if not all then break end
        end
        if n==0 then return text,0 end
        chunks[#chunks+1]=text:sub(cursor)
        return table.concat(chunks),n
    end
    function M.word_matches(word, query) return M.find(word, query) ~= nil end
    return M
end

local ZP_CERCA
do
    local path = SCRIPT_DIR .. "ZP_cerca.lua"
    local file = io.open(path, "r")
    if file then
        file:close()
        local ok, loaded = pcall(dofile, path)
        if ok and type(loaded) == "table" and type(loaded.find) == "function" and type(loaded.results) == "function" and type(loaded.replace) == "function" then ZP_CERCA = loaded end
    end
    if not ZP_CERCA then
        if reaper.GetExtState("ZP_STUDIO_SUITE", "cerca_helper_missing_session") ~= "1" then
            reaper.ShowMessageBox(T("ZP_cerca.lua non è disponibile o non si carica. Il Gobbo userà una ricerca semplice per sottostringa finché il file non viene ripristinato."), T("ZP Studio Suite - ricerca"), 0)
            reaper.SetExtState("ZP_STUDIO_SUITE", "cerca_helper_missing_session", "1", false)
        end
        ZP_CERCA = SimpleSearchFallback()
    end
end
local cached_items = {}
local cached_notes = {}
-- Risultati tenuti da un fotogramma all'altro per non rifare la scansione delle tracce:
-- traccia del testo (finche' il progetto non cambia) e visibilita' mostrata nel pannello laterale.
local frame_cache = { track_state = -1, vis_time = -1 }
-- Note agganciate alla battuta (vedi SyncLinkedNotes)
local NOTE_LINK_MAX_DISTANCE = 10.0   -- oltre questa distanza da ogni battuta la nota resta libera
local NOTE_LINK_EPSILON = 0.0005
local cached_character_notes = {}
local cached_regions = {}
local cached_video_items = {}
local cached_headers = {}
local character_lane_by_key = {}
local last_proj_state = -1
local last_track_guid = ""
local selected_text_track_guid = ""
local WINDOW_TITLE = ("ZP Studio Suite " .. ZP_UI.suite_version() .. " - ") .. T("Gobbo")
local READ_ALL = "ALL"   -- flusso virtuale "Tutti" (Leggi tutto): tutte le tracce testo insieme
local current_text_track = nil
local last_win_w = 0

local document_total_h = 0
local document_scroll_y = 0

-- Impostazioni Font e Finestra
local default_font = "Arial"
local master_font_size = 16
local show_settings_timer = 0
local document_margin_x = 54
local speaker_shoulder_w = 116
local scroll_follow = 0.045
local side_panel_w = 210
local theme_mode = "medium"
local full_contrast = false
local sfumato_pre_roll = 5.0
local sfumato_post_roll = 3.0
local word_follow = false
local fixed_block_mode = false
local notes_panel_open = true
local panels_hidden = false -- TAB: maschera temporanea, non modifica le preferenze.
local sidebar_collapsed = false










local tc_alert_mode = "off"
local countdown_alert = true
-- Bip prima della battuta: due bip a 3 e 2 secondi dall'attacco, l'ultimo secondo resta muto.
local beep = { on = false, db = -12, db_min = -36, db_max = -6, source = nil, last_item = nil, last_n = nil }
local max_character_rows = 1
local reading_point = 0.34
local timed_scroll_wpm = 120
local focus_zone = true
local timed_manual_override = false
local timed_reposition_requested = false
local timed_override_item = nil
local active_progress = 0.0
local show_timecode = true
local timecode_offset = 0.0
local window_w = 820
local window_h = 900
local window_x = 100
local window_y = 100
local window_dock = 0
local last_saved_window_state = ""
local sidebar_scroll_y = 0
local sidebar_content_h = 0
local sidebar_clip_top = nil
local sidebar_clip_bottom = nil
local sidebar_scroll_dragging = false

-- L'altezza di ogni blocco è dipendente solo da quanto testo c'è.
-- Il teleprompter non si basa più sulla velocità fissa in pixel/secondo
-- per simulare la timeline, ma scorre il proprio layout di testo.

-- === PANNELLO IMPOSTAZIONI ===
local mouse_was_down = false
local note_context_was_down = false
local note_empty_click_time = 0
local last_edit_click_time = 0
local last_edit_click_item = nil
local inline_edit = nil
local inline_clipboard = ""
local search_query = ""
local search_cursor = 1
local search_sel_start = nil
local search_sel_end = nil
local search_replace_open = false
local replace_query = ""
local replace_cursor = 1
local replace_sel_start = nil
local replace_sel_end = nil
local search_active_field = "find"
local search_input_rect = nil
local replace_input_rect = nil
local search_last_click_time = 0
local search_results, search_results_total = {}, 0
local search_results_dirty, search_results_deadline = true, 0
local search_results_current, search_list_scroll = 0, 0
local search_list_rect, search_scroll_dragging, search_scroll_drag_offset = nil, false, 0
local search_hit_item = nil
local search_hit_query = ""
local search_hit_until = 0
local search_panel_open = false
local search_message = ""
local search_message_until = 0
local search_virtual_pos = nil
local help_button_down = false
local studio_edit_mode = false
local studio_edit_sync = true
local edit_scroll_dragging = false
local edit_scroll_was_dragging = false

-- Variabili per Play Pos Interpolation
local last_play_pos_raw = -1
local last_play_pos_time = 0

local COLOR_SUBS = 0x3498DB
local COLOR_NOTES = 0xF2C94C
local SPEAKER_PALETTE = {
    {name="Rosa", color=0xD84D7A},
    {name="Verde", color=0x57B86A},
    {name="Ocra", color=0xD7B24C},
    {name="Azzurro", color=0x45A7D8},
    {name="Viola", color=0x9B68D8},
    {name="Arancio", color=0xE07A3F},
    {name="Turchese", color=0x35B8A6},
    {name="Rosso", color=0xD4483E},
}
local character_note_prefix = "BB Note Personaggio - "
local NOTE_DEFAULT_LEN = 3.0
local NOTE_HOT_MARGIN = 0.35
local NOTE_WAKE_LEAD = 5.0
local NOTES_PANEL_W = 250
local TC_ALERT_LEAD = 3.0

function lerp(a, b, t) return a + (b - a) * t end

function trim(s)
    local out = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return out
end

function bool_to_state(value)
    return value and "1" or "0"
end

function state_to_bool(value, fallback)
    if value == "1" then return true end
    if value == "0" then return false end
    return fallback
end

function CapsLockOn()
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

function TextCharFromCode(char)
    if char < 32 or char > 1114111 then return nil end
    if (CapsLockOn() or (gfx.mouse_cap & 8) == 8) and char >= 97 and char <= 122 then
        char = char - 32
    end
    local ok, ch = false, nil
    if utf8 and utf8.char then ok, ch = pcall(utf8.char, char) end
    if not ok and char <= 255 then ch = string.char(char) end
    return ch
end

function SaveSettings()
    reaper.SetExtState(settings_section,"focus_zone",focus_zone and "1" or "0",true)
    reaper.SetExtState(settings_section, "theme_mode", theme_mode, true)
    reaper.SetExtState(settings_section, "full_contrast", bool_to_state(full_contrast), true)
    reaper.SetExtState(settings_section, "word_follow", bool_to_state(word_follow), true)
    reaper.SetExtState(settings_section, "fixed_block_mode", bool_to_state(fixed_block_mode), true)
    reaper.SetExtState(settings_section, "notes_panel_open", bool_to_state(notes_panel_open), true)
    reaper.SetExtState(settings_section, "sidebar_collapsed", bool_to_state(sidebar_collapsed), true)
    reaper.SetExtState(settings_section, "tc_alert_mode", tc_alert_mode, true)
    reaper.SetExtState(settings_section, "countdown_alert", bool_to_state(countdown_alert), true)
    reaper.SetExtState(settings_section, "countdown_beep", bool_to_state(beep.on), true)
    reaper.SetExtState(settings_section, "countdown_beep_db", tostring(beep.db), true)
    reaper.SetExtState(settings_section, "max_character_rows", tostring(max_character_rows), true)
    reaper.SetExtState(settings_section, "reading_point", tostring(reading_point), true)
    reaper.SetExtState(settings_section, "timed_scroll_wpm", tostring(timed_scroll_wpm), true)
    reaper.SetExtState(settings_section, "show_timecode", bool_to_state(show_timecode), true)
    reaper.SetExtState(settings_section, "master_font_size", tostring(master_font_size), true)
    reaper.SetExtState(settings_section, "document_margin_x", tostring(document_margin_x), true)
    reaper.SetExtState(settings_section, "scroll_follow", tostring(scroll_follow), true)
    reaper.SetExtState(settings_section, "studio_edit_mode", bool_to_state(studio_edit_mode), true)
    reaper.SetExtState(settings_section, "studio_edit_sync", bool_to_state(studio_edit_sync), true)
    reaper.SetExtState(settings_section, "window_w", tostring(window_w), true)
    reaper.SetExtState(settings_section, "window_h", tostring(window_h), true)
    reaper.SetExtState(settings_section, "window_x", tostring(window_x), true)
    reaper.SetExtState(settings_section, "window_y", tostring(window_y), true)
    reaper.SetExtState(settings_section, "window_dock", tostring(window_dock), true)
end

function LoadSettings()
    focus_zone=reaper.GetExtState(settings_section,"focus_zone")~="0"
    if reaper.GetExtState(settings_section, "read_all") == "1" then selected_text_track_guid = READ_ALL end
    local saved_theme = reaper.GetExtState(settings_section, "theme_mode")
    if saved_theme == "dark" or saved_theme == "medium" or saved_theme == "light" then
        theme_mode = saved_theme
    end

    full_contrast = state_to_bool(reaper.GetExtState(settings_section, "full_contrast"), full_contrast)
    word_follow = state_to_bool(reaper.GetExtState(settings_section, "word_follow"), word_follow)
    fixed_block_mode = state_to_bool(reaper.GetExtState(settings_section, "fixed_block_mode"), fixed_block_mode)
    notes_panel_open = state_to_bool(reaper.GetExtState(settings_section, "notes_panel_open"), notes_panel_open)
    sidebar_collapsed = state_to_bool(reaper.GetExtState(settings_section, "sidebar_collapsed"), sidebar_collapsed)
    show_timecode = state_to_bool(reaper.GetExtState(settings_section, "show_timecode"), show_timecode)
    countdown_alert = state_to_bool(reaper.GetExtState(settings_section, "countdown_alert"), countdown_alert)
    beep.on = state_to_bool(reaper.GetExtState(settings_section, "countdown_beep"), beep.on)
    beep.db = math.max(beep.db_min, math.min(beep.db_max, tonumber(reaper.GetExtState(settings_section, "countdown_beep_db")) or beep.db))
    studio_edit_mode = state_to_bool(reaper.GetExtState(settings_section, "studio_edit_mode"), studio_edit_mode)
    studio_edit_sync = state_to_bool(reaper.GetExtState(settings_section, "studio_edit_sync"), studio_edit_sync)
    local saved_tc_alert = reaper.GetExtState(settings_section, "tc_alert_mode")
    -- "box" = il riquadro del timecode lampeggia quando una battuta sta per arrivare.
    -- I vecchi valori ("side", "line") valgono come spento.
    tc_alert_mode = saved_tc_alert == "box" and "box" or "off"
    max_character_rows = 1

    master_font_size = math.max(10, math.min(60, tonumber(reaper.GetExtState(settings_section, "master_font_size")) or master_font_size))
    document_margin_x = math.max(20, math.min(180, tonumber(reaper.GetExtState(settings_section, "document_margin_x")) or document_margin_x))
    scroll_follow = math.max(0.010, math.min(0.120, tonumber(reaper.GetExtState(settings_section, "scroll_follow")) or scroll_follow))

    local saved_reading = tonumber(reaper.GetExtState(settings_section, "reading_point"))
    if saved_reading then reading_point = math.max(0.12, math.min(0.65, saved_reading)) end
    timed_scroll_wpm = math.max(40, math.min(240, tonumber(reaper.GetExtState(settings_section, "timed_scroll_wpm")) or timed_scroll_wpm))

    window_w = math.max(420, tonumber(reaper.GetExtState(settings_section, "window_w")) or window_w)
    window_h = math.max(360, tonumber(reaper.GetExtState(settings_section, "window_h")) or window_h)
    window_x = tonumber(reaper.GetExtState(settings_section, "window_x")) or window_x
    window_y = tonumber(reaper.GetExtState(settings_section, "window_y")) or window_y
    window_dock = tonumber(reaper.GetExtState(settings_section, "window_dock")) or window_dock
end

function SaveWindowStateIfChanged()
    local dock, x, y, w, h = gfx.dock(-1, 0, 0, 0, 0)
    w = w or gfx.w
    h = h or gfx.h
    x = x or window_x
    y = y or window_y
    dock = dock or window_dock

    local rw, rh = math.floor(w + 0.5), math.floor(h + 0.5)
    local rx, ry = math.floor(x + 0.5), math.floor(y + 0.5)

    if last_saved_window_state == "" or rw ~= window_w or rh ~= window_h
        or rx ~= window_x or ry ~= window_y or dock ~= window_dock then
        window_w = rw
        window_h = rh
        window_x = rx
        window_y = ry
        window_dock = dock
        last_saved_window_state = "salvato"
        SaveSettings()
    end
end

function IsTextFlowTrackName(name)
    local normalized = trim(name or ""):lower()
    if normalized:find("%sbkp%s") then return false end
    return normalized:find(default_track_name:lower(), 1, true) == 1
end

function IsValidTrack(track)
    if not track then return false end
    if reaper.ValidatePtr2 then return reaper.ValidatePtr2(0, track, "MediaTrack*") end
    return true
end

function CollectTextFlowTracks()
    local tracks = {}
    for i=0, reaper.CountTracks(0)-1 do
        local t = reaper.GetTrack(0, i)
        local _, name = reaper.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
        name = trim(name or "")
        if IsTextFlowTrackName(name) then
            table.insert(tracks, {track=t, name=name, guid=reaper.GetTrackGUID(t), index=i})
        end
    end
    table.sort(tracks, function(a, b) return a.index < b.index end)
    return tracks
end

function FindTextFlowByGuid(guid)
    if not guid or guid == "" then return nil end
    for _, entry in ipairs(CollectTextFlowTracks()) do
        if entry.guid == guid then return entry end
    end
    return nil
end

function GetRythmoTrack()
    if selected_text_track_guid == READ_ALL then
        -- Leggi tutto: i testi nuovi vanno nella traccia principale, la lettura le prende tutte
        local tracks = CollectTextFlowTracks()
        for _, entry in ipairs(tracks) do
            if trim(entry.name) == default_track_name then return entry.track end
        end
        return tracks[1] and tracks[1].track or nil
    end
    local selected = FindTextFlowByGuid(selected_text_track_guid)
    if selected then
        current_text_track = selected.track
        return selected.track
    end

    if IsValidTrack(current_text_track) and IsTextFlowTrackName(GetTrackName(current_text_track)) then
        selected_text_track_guid = reaper.GetTrackGUID(current_text_track)
        return current_text_track
    end
    current_text_track = nil

    local tracks = CollectTextFlowTracks()
    for _, entry in ipairs(tracks) do
        if trim(entry.name) == default_track_name then
            current_text_track = entry.track
            selected_text_track_guid = entry.guid
            return entry.track
        end
    end

    if #tracks > 0 then
        current_text_track = tracks[1].track
        selected_text_track_guid = tracks[1].guid
        return tracks[1].track
    end
    return nil
end

function GetOrCreateTextFlowTrack()
    local track = GetRythmoTrack()
    if track then return track end

    local idx = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(idx, true)
    track = reaper.GetTrack(0, idx)
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", default_track_name, true)
    reaper.SetTrackColor(track, NativeColor(COLOR_SUBS))
    reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
    reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 1)
    selected_text_track_guid = reaper.GetTrackGUID(track)
    current_text_track = track
    return track
end

local function CountTimedTextWords(text)
    local count = 0
    for _ in tostring(text or ""):gmatch("%S+") do count = count + 1 end
    return math.max(1, count)
end

local function TimedTextDuration(text, wpm)
    text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local words = CountTimedTextWords(text)
    local notes_w = (not panels_hidden and notes_panel_open) and NOTES_PANEL_W or 0
    local side_w = not panels_hidden and (sidebar_collapsed and 30 or side_panel_w) or 0
    local available_w = math.max(200, gfx.w - side_w - notes_w - speaker_shoulder_w - document_margin_x * 2)
    gfx.setfont(1, default_font, master_font_size)
    local lines = WrapText(text, available_w)
    local blank_lines, text_lines = 0, 0
    for _, line in ipairs(lines) do
        if trim(line) == "" then blank_lines = blank_lines + 1 else text_lines = text_lines + 1 end
    end
    -- La pausa di una riga vuota equivale al tempo medio necessario per leggere
    -- una riga piena; il numero di righe dipende poi da font e larghezza del Gobbo.
    local rate = math.max(40, math.min(240, wpm or 120))
    local average_words_per_line = words / math.max(1, text_lines)
    local pause_seconds=average_words_per_line*60/rate
    return math.max(5, words*60/rate)+blank_lines*pause_seconds,blank_lines,pause_seconds
end

function AddTimedGobboTextItem()
    local pos = GetCurrentProjectPosition()
    local ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if ts_start and ts_end and ts_end - ts_start > 0.2 then pos = ts_start end
    local editor_w = math.min(900, math.max(480, gfx.w - 80))
    local editor_h = math.max(240, math.min(420, gfx.h - 60))
    -- Editor dedicato: non richiama OnStopButton, quindi non interrompe play o REC.
    inline_edit = {
        item = nil, mode = "timed_new", timed_position = pos, timed_wpm = timed_scroll_wpm,
        text = "", original = "", cursor = 1,
        x = math.max(12, (gfx.w - editor_w) * 0.5),
        y = math.max(12, (gfx.h - editor_h) * 0.42),
        w = editor_w, h = editor_h,
        font_size = math.max(18, math.min(master_font_size, 28)),
        title = T("Nuovo testo temporizzato"), undo_stack = {}
    }
end

function SetTimedScrollSpeed(delta, play_pos)
    timed_scroll_wpm = math.max(40, math.min(240, timed_scroll_wpm + delta))
    reaper.SetExtState(settings_section, "timed_scroll_wpm", tostring(timed_scroll_wpm), true)
    play_pos = play_pos or GetCurrentProjectPosition()
    for _, item in ipairs(cached_items or {}) do
        if item.timed_scroll and play_pos >= item.pos and play_pos < item.pos + item.len then
            local _, text = reaper.GetSetMediaItemInfo_String(item.item, "P_NOTES", "", false)
            local duration = TimedTextDuration(text or "", timed_scroll_wpm)
            reaper.GetSetMediaItemInfo_String(item.item,'P_EXT:ZP_GOBBO_TIMING','',true)
            reaper.GetSetMediaItemInfo_String(item.item,'P_EXT:ZP_GOBBO_TIMING_TEXT','',true)
            reaper.Undo_BeginBlock()
            local _,_,pause_seconds=TimedTextDuration(text or "",timed_scroll_wpm)
            reaper.GetSetMediaItemInfo_String(item.item,"P_EXT:ZP_TIMED_SCROLL_PAUSE_WEIGHT",tostring(pause_seconds*timed_scroll_wpm/60),true)
            reaper.SetMediaItemInfo_Value(item.item, "D_LENGTH", duration)
            reaper.GetSetMediaItemInfo_String(item.item, "P_EXT:ZP_TIMED_SCROLL_WPM", tostring(timed_scroll_wpm), true)
            reaper.UpdateItemInProject(item.item)
            reaper.Undo_EndBlock("ZP Studio Suite: regola velocità testo temporizzato", -1)
            break
        end
    end
end

function TextFlowDisplayName(name)
    name = trim(name or "")
    if name == default_track_name then return "Principale" end
    if name:find(default_track_name, 1, true) == 1 then
        local suffix = trim(name:sub(#default_track_name + 1))
        if suffix ~= "" then return suffix end
    end
    return name ~= "" and name or "Nessuno"
end

function CurrentTextFlowEntry()
    local track = GetRythmoTrack()
    if not track then return nil end
    return {track=track, name=GetTrackName(track), guid=reaper.GetTrackGUID(track)}
end

function CurrentTextFlowLabel()
    if selected_text_track_guid == READ_ALL then return "Tutti" end
    local entry = CurrentTextFlowEntry()
    if not entry then return "Nessun testo" end
    return TextFlowDisplayName(entry.name)
end

-- Titolo della finestra con il flusso letto: si vede anche a menu chiuso.
-- gfx.init(nome) a finestra aperta cambia solo il titolo; prima dell'apertura non fa nulla.
local window_title_shown = ""
function UpdateWindowTitle()
    if not gfx.w or gfx.w <= 0 then return end
    local title = WINDOW_TITLE .. " - " .. T("Flusso:") .. " " .. CurrentTextFlowLabel()
    if title ~= window_title_shown then
        window_title_shown = title
        gfx.init(title)
    end
end

-- Segui i tagli: dopo 10 s senza modifiche al progetto riporta i testi sull'audio
-- (ZP_sincronizza_aggancio.lua, accanto a questo script). Stesso interruttore della
-- finestra ZP Trascrizione. Non gira durante la registrazione; se non c'e' niente da
-- allineare non crea punti di Undo.
local FOLLOW_SECTION, FOLLOW_KEY, FOLLOW_DELAY = "ZP_STUDIO_SUITE", "PanelAutofollow", 10.0
local follow_last_count, follow_last_change, follow_pending, follow_script = -1, 0, false, nil

function FollowScriptPath()
    if follow_script == nil then
        local p = SCRIPT_DIR .. "ZP_sincronizza_aggancio.lua"
        local f = io.open(p, "r")
        if f then f:close(); follow_script = p else follow_script = false end
    end
    return follow_script or nil
end

function FollowEnabled()
    return reaper.GetExtState(FOLLOW_SECTION, FOLLOW_KEY) == "1"
end

function ToggleFollow()
    reaper.SetExtState(FOLLOW_SECTION, FOLLOW_KEY, FollowEnabled() and "0" or "1", true)
    follow_pending = false
    follow_last_count = reaper.GetProjectStateChangeCount(0)
end

function FollowTick()
    if not FollowEnabled() or not FollowScriptPath() then return end
    local count = reaper.GetProjectStateChangeCount(0)
    local now = reaper.time_precise()
    if follow_last_count < 0 then follow_last_count = count return end
    if count ~= follow_last_count then
        follow_last_count = count
        follow_last_change = now
        follow_pending = true
    end
    if follow_pending and now - follow_last_change >= FOLLOW_DELAY and (reaper.GetPlayState() & 4) == 0 then
        follow_pending = false
        _G.ZP_SYNC_QUIET = true
        pcall(dofile, follow_script)
        _G.ZP_SYNC_QUIET = nil
        follow_last_count = reaper.GetProjectStateChangeCount(0)   -- i cambi del sync non contano
    end
end

function CycleTextFlow(delta)
    local tracks = CollectTextFlowTracks()
    if #tracks == 0 then return end
    -- con due o piu' flussi c'e' anche "Tutti" (Leggi tutto)
    if #tracks >= 2 then tracks[#tracks + 1] = {guid=READ_ALL} end

    local current_guid = selected_text_track_guid or ""
    local current_index = 1
    for i, entry in ipairs(tracks) do
        if entry.guid == current_guid then current_index = i break end
    end

    local next_index = ((current_index - 1 + delta) % #tracks) + 1
    SelectTextFlow(tracks[next_index].guid)
end

-- Imposta il flusso letto dal gobbo (guid di una traccia testo, o READ_ALL = Tutti).
function SelectTextFlow(guid)
    selected_text_track_guid = guid
    local entry = guid ~= READ_ALL and FindTextFlowByGuid(guid) or nil
    current_text_track = entry and entry.track or nil
    reaper.SetExtState(settings_section, "read_all", selected_text_track_guid == READ_ALL and "1" or "0", true)
    cached_items = {}
    cached_notes = {}
    cached_headers = {}
    last_track_guid = ""
    last_proj_state = -1
    UpdateItems()
    RecalculateDocumentLayout()
end

function NativeColor(color)
    local r = (color >> 16) & 0xFF
    local g = (color >> 8) & 0xFF
    local b = color & 0xFF
    return reaper.ColorToNative(r, g, b) | 0x1000000
end

function ColorToRGB(color, fallback)
    local use_color = color
    if not use_color or use_color == 0 then use_color = NativeColor(fallback or COLOR_NOTES) end
    local r, g, b = reaper.ColorFromNative(use_color & 0xFFFFFF)
    return (r or 0) / 255, (g or 0) / 255, (b or 0) / 255
end

function GetDisplayedItemColor(item, fallback)
    local color = 0
    if item and reaper.GetDisplayedMediaItemColor2 then
        local take = reaper.GetActiveTake and reaper.GetActiveTake(item) or nil
        local ok, displayed = pcall(reaper.GetDisplayedMediaItemColor2, item, take)
        if ok and displayed and displayed ~= 0 then color = displayed end
    end
    if color == 0 and item and reaper.GetDisplayedMediaItemColor then
        local ok, displayed = pcall(reaper.GetDisplayedMediaItemColor, item)
        if ok and displayed and displayed ~= 0 then color = displayed end
    end
    if color == 0 and item then
        color = reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")
    end
    if color == 0 then
        local track = GetItemTrack and GetItemTrack(item) or nil
        if track then color = reaper.GetTrackColor(track) end
    end
    if color == 0 then color = NativeColor(fallback or COLOR_SUBS) end
    return color
end

function LinearizeColorChannel(c)
    if c <= 0.03928 then return c / 12.92 end
    return ((c + 0.055) / 1.055) ^ 2.4
end

function RelativeLuminance(r, g, b)
    return (0.2126 * LinearizeColorChannel(r)) + (0.7152 * LinearizeColorChannel(g)) + (0.0722 * LinearizeColorChannel(b))
end

function ContrastRatio(l1, l2)
    local hi = math.max(l1, l2)
    local lo = math.min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)
end

function BestTextColorForBackground(r, g, b)
    local lum = RelativeLuminance(r, g, b)
    local black_ratio = ContrastRatio(lum, 0)
    local white_ratio = ContrastRatio(lum, 1)
    if black_ratio >= white_ratio then return 0.02, 0.025, 0.03 end
    return 1.0, 0.98, 0.92
end

-- Testo leggibile su una scheda nota trasparente (alpha) sopra il pannello scuro:
-- il fondo vero e' la miscela, non il colore pieno della nota (prima: nero su oro scuro).
function SetNoteCardTextColor(r, g, b, card_alpha, alpha)
    local base = 0.08
    local a = card_alpha or 0.2
    SetReadableTextColor(r * a + base * (1 - a), g * a + base * (1 - a), b * a + base * (1 - a), alpha)
end

function SetReadableTextColor(r, g, b, alpha)
    local tr, tg, tb = BestTextColorForBackground(r, g, b)
    gfx.set(tr, tg, tb, alpha or 1)
end

function NormalizeName(name)
    return trim(name or ""):lower()
end

function IsCharacterNoteTrack(track)
    if not track then return false end
    local _, ext = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:RythmoBand_NP", "", false)
    if ext == "person_note" then return true end
    local name = GetTrackName(track)
    return name:find(character_note_prefix, 1, true) == 1
end

function GetTrackIndex(track)
    if not track then return nil end
    for i=0, reaper.CountTracks(0)-1 do
        if reaper.GetTrack(0, i) == track then return i end
    end
    return nil
end

function PairedVoiceTrack(note_track)
    local idx = GetTrackIndex(note_track)
    if not idx or idx <= 0 then return nil end
    local previous = reaper.GetTrack(0, idx - 1)
    local _, ext = reaper.GetSetMediaTrackInfo_String(previous, "P_EXT:RythmoBand_NP", "", false)
    if ext == "voice" then return previous end

    local note_name = GetTrackName(note_track)
    if note_name:find(character_note_prefix, 1, true) == 1 then
        local legacy_role = trim(note_name:sub(#character_note_prefix + 1))
        if NormalizeName(GetTrackName(previous)) == NormalizeName(legacy_role) then return previous end
    end
    return nil
end

function FindCharacterNoteTrackForVoiceTrack(voice_track)
    if not voice_track then return nil end
    for i=0, reaper.CountTracks(0)-1 do
        local note_track = reaper.GetTrack(0, i)
        if IsCharacterNoteTrack(note_track) and PairedVoiceTrack(note_track) == voice_track then
            return note_track
        end
    end
    return nil
end

function CharacterNameFromTrack(track)
    local voice_track = PairedVoiceTrack(track)
    local voice_name = GetTrackName(voice_track)
    if voice_name ~= "" then return voice_name end

    local name = GetTrackName(track)
    if name:find(character_note_prefix, 1, true) == 1 then
        return trim(name:sub(#character_note_prefix + 1))
    end
    return name
end

function GetTrackName(track)
    if not track then return "" end
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    return trim(name)
end

function FindRoleTrackOrder(note_track_index, role_key)
    for i=note_track_index-1, 0, -1 do
        local track = reaper.GetTrack(0, i)
        if NormalizeName(GetTrackName(track)) == role_key then return i end
    end
    return note_track_index
end

function BuildCharacterLanes()
    character_lane_by_key = {}
    local roles = {}
    local seen = {}

    for _, note in ipairs(cached_character_notes) do
        if note.key ~= "" and not seen[note.key] then
            seen[note.key] = true
            table.insert(roles, {key=note.key, order=note.track_order or 999999})
        end
    end

    table.sort(roles, function(a, b)
        if a.order == b.order then return a.key < b.key end
        return a.order < b.order
    end)

    for i, role in ipairs(roles) do
        if i > max_character_rows then break end
        character_lane_by_key[role.key] = i
    end
end

function FindTrackByName(name)
    for i=0, reaper.CountTracks(0)-1 do
        local track = reaper.GetTrack(0, i)
        local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if track_name == name or track_name:find(name) then return track end
    end
    return nil
end

function GetItemTrack(item)
    if not item then return nil end
    if reaper.GetMediaItemTrack then return reaper.GetMediaItemTrack(item) end
    for t=0, reaper.CountTracks(0)-1 do
        local track = reaper.GetTrack(0, t)
        for i=0, reaper.CountTrackMediaItems(track)-1 do
            if reaper.GetTrackMediaItem(track, i) == item then return track end
        end
    end
    return nil
end

function ApplySpeakerColorToVoicePair(note_track, native)
    if not note_track then return 0 end
    local changed = 0
    local voice_track = PairedVoiceTrack(note_track)
    if voice_track then
        reaper.SetTrackColor(voice_track, native)
        changed = changed + 1
    end
    reaper.SetTrackColor(note_track, native)
    changed = changed + 1

    for i=0, reaper.CountTrackMediaItems(note_track)-1 do
        local item = reaper.GetTrackMediaItem(note_track, i)
        reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", 0)
    end
    return changed
end

function FindNearestCharacterNote(pos)
    local best_note = nil
    local best_score = nil
    for _, note in ipairs(cached_character_notes) do
        local note_end = note.pos + note.len
        local score = nil
        if pos >= note.pos - NOTE_HOT_MARGIN and pos <= note_end + NOTE_HOT_MARGIN then
            score = 0
        else
            score = math.min(math.abs(pos - note.pos), math.abs(pos - note_end))
        end
        if not best_score or score < best_score then
            best_score = score
            best_note = note
        end
    end
    return best_note, best_score
end

function ApplySpeakerPaletteColor(palette_color)
    local native = NativeColor(palette_color)
    local changed = 0

    reaper.Undo_BeginBlock()
    local colored_tracks = {}
    for i=0, reaper.CountSelectedMediaItems(0)-1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local selected_track = GetItemTrack(item)
        local note_track = IsCharacterNoteTrack(selected_track) and selected_track
            or FindCharacterNoteTrackForVoiceTrack(selected_track)
        local color_key = note_track and tostring(note_track) or tostring(selected_track)
        if selected_track and not colored_tracks[color_key] then
            if note_track then
                changed = changed + ApplySpeakerColorToVoicePair(note_track, native)
                colored_tracks[color_key] = true
            else
                local _, role = reaper.GetSetMediaTrackInfo_String(selected_track, "P_EXT:RythmoBand_NP", "", false)
                if role == "voice" then
                    reaper.SetTrackColor(selected_track, native)
                    changed = changed + 1
                    colored_tracks[color_key] = true
                end
            end
        end
    end

    if changed == 0 then
        local note, distance = FindNearestCharacterNote(GetCurrentProjectPosition())
        if note and (not distance or distance <= 12) then
            changed = changed + ApplySpeakerColorToVoicePair(GetItemTrack(note.item), native)
        end
    end

    reaper.Undo_EndBlock("ZP Studio Suite colore speaker", -1)
    if changed == 0 then
        reaper.ShowMessageBox(T("Seleziona un item sulla traccia VOCE/RB o sulla relativa BB Note Personaggio, oppure porta il cursore/playhead vicino a una nota personaggio."), "ZP Studio Suite", 0)
    end
    reaper.UpdateArrange()
    UpdateItems()
end

function GetOrCreateNotesTrack()
    local track = FindTrackByName(notes_track_name)
    if track then return track end

    local idx = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(idx, true)
    track = reaper.GetTrack(0, idx)
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", notes_track_name, true)
    reaper.SetTrackColor(track, NativeColor(COLOR_NOTES))
    reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
    reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
    return track
end

function IsTrackVisible(track)
    if not track then return false end
    return reaper.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") > 0.5
end

-- Stato delle caselle "Traccia note visibile" e "Tracce gobbo visibili": riletto ogni mezzo
-- secondo e subito dopo un clic sulle caselle, non a ogni fotogramma.
function SidebarTrackVisibility()
    local now = reaper.time_precise()
    if frame_cache.vis_time < 0 or now - frame_cache.vis_time > 0.5 then
        frame_cache.vis_notes = IsTrackVisible(FindTrackByName(notes_track_name))
        frame_cache.vis_flows = AnyTextFlowTrackVisible()
        frame_cache.vis_time = now
    end
    return frame_cache.vis_notes, frame_cache.vis_flows
end

function ApplyNotesTrackLayout(track)
    if not track or notes_track_tcp_layout == "" then return end
    reaper.GetSetMediaTrackInfo_String(track, "P_TCP_LAYOUT", notes_track_tcp_layout, true)
end

function SetTrackVisible(track, visible, select_when_visible)
    if not track then return end
    if select_when_visible == nil then select_when_visible = true end
    local value = visible and 1 or 0
    reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", value)
    reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", value)
    if visible then
        ApplyNotesTrackLayout(track)
        if select_when_visible then reaper.SetOnlyTrackSelected(track) end
    end
    if reaper.TrackList_AdjustWindows then reaper.TrackList_AdjustWindows(false) end
    reaper.UpdateArrange()
    frame_cache.vis_time = -1
end

function ToggleNotesTrackVisibility()
    local track = GetOrCreateNotesTrack()
    if not track then return end
    SetTrackVisible(track, not IsTrackVisible(track))
end

function AnyTextFlowTrackVisible()
    for _, entry in ipairs(CollectTextFlowTracks()) do
        if IsTrackVisible(entry.track) then return true end
    end
    return false
end

function SetTextFlowTracksVisible(visible)
    local value = visible and 1 or 0
    for _, entry in ipairs(CollectTextFlowTracks()) do
        reaper.SetMediaTrackInfo_Value(entry.track, "B_SHOWINTCP", value)
        reaper.SetMediaTrackInfo_Value(entry.track, "B_SHOWINMIXER", value)
    end
    if reaper.TrackList_AdjustWindows then reaper.TrackList_AdjustWindows(false) end
    reaper.UpdateArrange()
    frame_cache.vis_time = -1
end

function ToggleTextFlowTracksVisibility()
    SetTextFlowTracksVisible(not AnyTextFlowTrackVisible())
end

function GetCurrentProjectPosition()
    if (reaper.GetPlayState() & 1) == 1 then
        return reaper.GetPlayPosition()
    end
    return reaper.GetCursorPosition()
end

function GetProjectFPS()
    local fps = 25
    if reaper.TimeMap_curFrameRate then
        fps = reaper.TimeMap_curFrameRate(0)
    end
    if not fps or fps <= 0 then fps = 25 end
    return fps
end

function FormatTimecode(seconds)
    local fps = GetProjectFPS()
    local frame_base = math.max(1, math.floor(fps + 0.5))
    local time_val = math.max(0, (seconds or 0) + timecode_offset)
    local h = math.floor(time_val / 3600)
    local m = math.floor((time_val / 60) % 60)
    local s = math.floor(time_val % 60)
    local f = math.floor(((time_val - math.floor(time_val)) * fps) + 0.0001)

    if f >= frame_base then
        f = 0
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

    return string.format("%02d:%02d:%02d:%02d", h, m, s, f)
end

function FindVideoItemForPosition(pos)
    for _, video in ipairs(cached_video_items) do
        if pos >= video.pos and pos <= video.pos + video.len then return video end
    end
    return nil
end

function GetVideoTimecodeBase(pos)
    local region = FindRegionForPosition and FindRegionForPosition(pos)
    if region then return region.pos end

    local video = FindVideoItemForPosition(pos)
    if video then return video.pos end

    return 0
end

function FormatVideoTimecode(project_seconds)
    local pos = project_seconds or 0
    return FormatTimecode(pos - GetVideoTimecodeBase(pos))
end

function InsertNoteAtCurrentPosition()
    StartInlineNoteEdit(nil)
end

-- Cancella una nota dal pannello (la x sulla scheda), con conferma. Undo la rimette.
function DeleteNote(note)
    if not note or not note.item or not reaper.ValidatePtr(note.item, "MediaItem*") then return end
    local ok = reaper.ShowMessageBox(T("Cancellare questa nota?\n\n") .. FormatVideoTimecode(note.pos) .. "\n" .. note.text, "ZP Studio Suite", 4)
    if ok ~= 6 then return end
    local track = reaper.GetMediaItem_Track(note.item)
    reaper.Undo_BeginBlock()
    reaper.DeleteTrackMediaItem(track, note.item)
    reaper.Undo_EndBlock("ZP Studio Suite cancella nota", -1)
    reaper.UpdateArrange()
    UpdateItems()
end

-- Il bip e' lo stesso del Gobbo di Dubbertools: 1 kHz, un decimo di secondo, attacco e coda morbidi.
-- Il file si crea da solo la prima volta nella cartella Data di REAPER; per suonarlo serve SWS.
function EnsureBeepFile()
    local path = reaper.GetResourcePath() .. "/Data/ZP_bip_1kHz.wav"
    local file = io.open(path, "rb")
    if file then file:close() return path end
    local rate, freq = 48000, 1000
    local count, ramp = math.floor(rate * 0.1), math.floor(rate * 0.004)
    local data = {}
    for i = 0, count - 1 do
        local env = 1
        if i < ramp then env = i / ramp elseif i >= count - ramp then env = (count - 1 - i) / ramp end
        data[#data + 1] = string.pack("<i2", math.floor(32000 * env * math.sin(2 * math.pi * freq * i / rate) + 0.5))
    end
    local body = table.concat(data)
    file = io.open(path, "wb")
    if not file then return nil end
    file:write("RIFF", string.pack("<I4", 36 + #body), "WAVEfmt ",
        string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, rate, rate * 2, 2, 16), "data", string.pack("<I4", #body), body)
    file:close()
    return path
end

function BeepAvailable()
    return type(reaper.CF_CreatePreview) == "function"
end

function PlayBeep()
    if not BeepAvailable() then return false end
    if not beep.source then
        local path = EnsureBeepFile()
        if not path then return false end
        beep.source = reaper.PCM_Source_CreateFromFile(path)
        if not beep.source then return false end
    end
    return pcall(function()
        local preview = reaper.CF_CreatePreview(beep.source)
        reaper.CF_Preview_SetValue(preview, "D_VOLUME", 10 ^ (beep.db / 20))
        reaper.CF_Preview_Play(preview)
    end)
end

function SetBeepEnabled(value)
    if value and not BeepAvailable() then
        reaper.ShowMessageBox(T("Per il bip serve l'estensione SWS."), "ZP Studio Suite", 0)
        value = false
    end
    beep.on = value
    SaveSettings()
    if beep.on then PlayBeep() end
end

function SetBeepVolume(db)
    beep.db = math.max(beep.db_min, math.min(beep.db_max, db))
    SaveSettings()
    PlayBeep()
end

-- Chiamata a ogni frame: suona quando il conto alla rovescia passa a 3 e a 2, solo in riproduzione.
function UpdateCountdownBeep(cue, pos)
    if not beep.on then return end
    if not cue or (reaper.GetPlayState() & 1) ~= 1 then
        beep.last_item, beep.last_n = nil, nil
        return
    end
    local n = math.ceil(cue.pos - pos)
    if cue.item ~= beep.last_item or n ~= beep.last_n then
        beep.last_item, beep.last_n = cue.item, n
        if n == 3 or n == 2 then PlayBeep() end
    end
end

if reaper.atexit then
    reaper.atexit(function()
        if beep.source then pcall(reaper.PCM_Source_Destroy, beep.source) end
    end)
end

function FindUpcomingCue(pos)
    local best = nil
    for _, item in ipairs(cached_items) do
        local delta = item.pos - pos
        if delta >= -0.12 and delta <= TC_ALERT_LEAD then
            if not best or item.pos < best.pos then best = item end
        end
    end
    return best
end

-- Nome del file audio da cui il sync ha creato la battuta (P_EXT:ZP_SYNC_SRCKEY = "percorso|tempo").
-- nil per le battute scritte a mano.
function SyncSourceFileName(item)
    local _, key = reaper.GetSetMediaItemInfo_String(item, "P_EXT:ZP_SYNC_SRCKEY", "", false)
    local path = key and key:match("^(.*)|[^|]*$") or ""
    if path == "" then return nil end
    return path:match("[^/\\]+$") or path
end

function NormalizeSearchText(text) return ZP_CERCA.fold(text) end
function FindSubtitleMatch(query, start_pos)
    if ZP_CERCA.fold(query) == "" then return nil end
    local fallback
    for _, item in ipairs(cached_items) do
        local match_start = ZP_CERCA.find(item.notes, query)
        if match_start then
            local ratio = math.max(0, math.min(1, (match_start - 1) / math.max(1, #tostring(item.notes or ""))))
            item.search_match_pos = item.pos + item.len * ratio
            item.search_match_offset = match_start
            if not fallback then fallback = item end
            if item.pos > (start_pos or 0) + 0.001 then return item end
        end
    end
    return fallback
end

function FindSubtitleMatchPrevious(query, start_pos)
    if ZP_CERCA.fold(query) == "" then return nil end
    local fallback
    for i = #cached_items, 1, -1 do
        local item = cached_items[i]
        local match_start = ZP_CERCA.find(item.notes, query)
        if match_start then
            local ratio = math.max(0, math.min(1, (match_start - 1) / math.max(1, #tostring(item.notes or ""))))
            item.search_match_pos = item.pos + item.len * ratio
            item.search_match_offset = match_start
            if not fallback then fallback = item end
            if item.pos < (start_pos or 0) - 0.001 then return item end
        end
    end
    return fallback
end

function ScheduleSearchResults()
    search_results_dirty = true
    search_results_deadline = reaper.time_precise() + 0.15
    search_results_current = 0
end

function RefreshSearchResults(force)
    if not force and (not search_results_dirty or reaper.time_precise() < search_results_deadline) then return end
    local previous_item = search_results[search_results_current] and search_results[search_results_current].item or nil
    -- con Sostituisci aperto l'elenco mostra solo cio' che verrebbe cambiato (parola intera, accenti)
    search_results, search_results_total = ZP_CERCA.results(cached_items, search_query, 500, search_replace_open and "replace" or nil)
    -- in ordine di timeline secondo il timecode mostrato (punto della parola, non inizio battuta):
    -- con take e marker gli item testo possono essere lunghi e sovrapposti
    table.sort(search_results, function(a, b) return SearchResultPosition(a) < SearchResultPosition(b) end)
    search_results_dirty = false
    search_results_current = 0
    if previous_item then
        for i, result in ipairs(search_results) do
            if result.item == previous_item then search_results_current = i; break end
        end
    end
    if search_results_current == 0 then search_list_scroll = 0 end
end

function SearchResultPosition(result)
    local item = result.item
    local ratio = (result.offset_start - 1) / math.max(1, #tostring(item.notes or ""))
    return item.pos + item.len * math.max(0, math.min(1, ratio))
end

function UpdateSearchResultMessage(result, index)
    if not result then return end
    local pos = SearchResultPosition(result)
    search_message = tostring(index or 1) .. " di " .. tostring(search_results_total) .. " · " .. FormatVideoTimecode(pos)
    search_message_until = reaper.time_precise() + 2.0
end

function KeepSearchResultVisible(index, visible_rows)
    visible_rows = math.max(1, visible_rows or 1)
    if index < search_list_scroll + 1 then search_list_scroll = index - 1 end
    if index > search_list_scroll + visible_rows then search_list_scroll = index - visible_rows end
    search_list_scroll = math.max(0, math.min(search_list_scroll, math.max(0, #search_results - visible_rows)))
end

function SelectSearchResult(index, jump)
    if #search_results == 0 then return nil end
    index = math.max(1, math.min(index, #search_results))
    search_results_current = index
    local result = search_results[index]
    local item = result.item
    item.search_match_pos = SearchResultPosition(result)
    item.search_match_offset = result.offset_start
    KeepSearchResultVisible(index, 8)
    if jump then JumpToSearchMatch(item) end
    UpdateSearchResultMessage(result, index)
    return result
end

function SearchResultIndexForItem(item)
    for i, result in ipairs(search_results) do
        if result.item == item then return i end
    end
    return nil
end

function SelectSubtitleItemAndJump(media_item)
    if not media_item then return end
    local track = reaper.GetMediaItem_Track(media_item)
    local pos = reaper.GetMediaItemInfo_Value(media_item, "D_POSITION")
    reaper.Main_OnCommand(40289, 0) -- Unselect all items
    reaper.SetMediaItemSelected(media_item, true)
    if track then reaper.SetOnlyTrackSelected(track) end
    reaper.SetEditCurPos(pos, true, false)
    reaper.UpdateArrange()
end

function JumpToSearchMatch(item)
    if not item then return end
    search_hit_item = item.item
    search_hit_query = search_query or ""
    search_hit_until = reaper.time_precise() + 3.0
    local target_pos = item.search_match_pos or item.pos
    search_virtual_pos = target_pos
    if studio_edit_mode and studio_edit_sync then
        SelectSubtitleItemAndJump(item.item)
        reaper.SetEditCurPos(target_pos, true, false)
    else
        reaper.SetEditCurPos(target_pos, true, false)
        reaper.UpdateArrange()
    end
    if item.doc_start_y then
        local reading_y = math.max(60, gfx.h * reading_point)
        document_scroll_y = math.max(0, item.doc_start_y - reading_y)
    end
end

function PromptSubtitleSearch()
    if inline_edit then SaveInlineSubtitleEdit() end
    search_panel_open = true
    search_message = ""
    -- si riapre sempre su Trova, con Sostituisci chiuso; la ricerca di prima resta selezionata:
    -- scrivendo la si sostituisce, Invio la ripete
    search_replace_open = false
    search_active_field = "find"
    search_cursor = #(search_query or "") + 1
    search_sel_start = (search_query or "") ~= "" and 1 or nil
    search_sel_end = (search_query or "") ~= "" and search_cursor or nil
    ScheduleSearchResults()
end

function ExecuteSubtitleSearch(direction)
    if inline_edit then SaveInlineSubtitleEdit() end
    local trimmed = trim(search_query or "")
    if trimmed ~= search_query then search_query = trimmed; ScheduleSearchResults() end
    search_cursor = math.max(1, math.min(search_cursor or (#search_query + 1), #search_query + 1))
    if search_query == "" then
        search_message = "Scrivi una parola o frase"
        search_message_until = reaper.time_precise() + 1.8
        return
    end
    RefreshSearchResults(true)

    local pos = (studio_edit_mode and not studio_edit_sync and search_virtual_pos) or GetCurrentProjectPosition()
    if search_replace_open then
        -- con Sostituisci aperto si scorre l'elenco (solo parole intere da sostituire)
        local index = SearchResultIndexNear(pos, direction and direction < 0 and -1 or 1)
        if index then SelectSearchResult(index, true)
        else
            search_results_current = 0
            search_message = "Nessun risultato"
            search_message_until = reaper.time_precise() + 2.0
        end
        return
    end
    local match = direction and direction < 0 and FindSubtitleMatchPrevious(search_query, pos) or FindSubtitleMatch(search_query, pos)
    if not match then
        search_message = "Nessun risultato"
        search_message_until = reaper.time_precise() + 2.0
        search_results_current = 0
        return
    end
    JumpToSearchMatch(match)
    local index = SearchResultIndexForItem(match)
    if index then SelectSearchResult(index, false) end
    if not index then
        search_message = "Nessun risultato"
        search_message_until = reaper.time_precise() + 2.0
    end
end

-- Risultato dell'elenco dopo (dir 1) o prima (dir -1) di pos; al bordo riparte dall'altro capo.
function SearchResultIndexNear(pos, dir)
    if #search_results == 0 then return nil end
    if dir < 0 then
        for i = #search_results, 1, -1 do
            if SearchResultPosition(search_results[i]) < pos - 0.001 then return i end
        end
        return #search_results
    end
    for i, result in ipairs(search_results) do
        if SearchResultPosition(result) > pos + 0.001 then return i end
    end
    return 1
end

-- Sostituisci (una): il primo clic porta alla prossima parola e la mostra; il secondo la cambia
-- e resta li', cosi' si vede il risultato. Tutti: conferma e un solo Undo.
-- Sostituisce solo parole intere e gli accenti contano (ZP_cerca mode "replace").
function ApplySearchReplacement(all)
    if search_query == "" then return end
    if all then
        local all_results = ZP_CERCA.results(cached_items, search_query, math.huge, "replace")
        local total_replacements, matched_items = 0, 0
        for _, result in ipairs(all_results) do
            local _, count = ZP_CERCA.replace(result.item.notes or "", search_query, replace_query, true)
            if count > 0 then total_replacements = total_replacements + count; matched_items = matched_items + 1 end
        end
        if total_replacements == 0 then
            search_message = T("Nessuna parola intera da sostituire")
            search_message_until = reaper.time_precise() + 2.5
            return
        end
        local answer = reaper.ShowMessageBox(string.format(T("Sostituisco %d occorrenze in %d battute?"), total_replacements, matched_items), T("ZP Studio Suite - Sostituisci tutto"), 4)
        if answer ~= 6 then return end
        reaper.Undo_BeginBlock()
        for _, result in ipairs(all_results) do
            local old_text = result.item.notes or ""
            local new_text, count = ZP_CERCA.replace(old_text, search_query, replace_query, true)
            if count > 0 and new_text ~= old_text then
                reaper.GetSetMediaItemInfo_String(result.item.item, "P_NOTES", new_text, true)
                UpdateSubtitleItemName(result.item.item, new_text)
                reaper.UpdateItemInProject(result.item.item)
            end
        end
        reaper.Undo_EndBlock(string.format("ZP Studio Suite: sostituisci '%s' con '%s' (%d)", search_query, replace_query, total_replacements), -1)
        reaper.UpdateArrange()
        UpdateItems()
        search_results_dirty = true
        RefreshSearchResults(true)
        search_results_current = 0
        search_message = string.format("Sostituite %d", total_replacements)
        search_message_until = reaper.time_precise() + 3.0
        return
    end

    RefreshSearchResults(true)
    local result = search_results_current > 0 and search_results[search_results_current] or nil
    if not result then
        -- primo clic: mostra la prossima parola da sostituire, non cambia niente
        ExecuteSubtitleSearch(1)
        if search_results_current > 0 then
            search_message = tostring(search_results_current) .. " di " .. tostring(search_results_total) .. " · di nuovo Sostituisci per cambiarla"
            search_message_until = reaper.time_precise() + 4.0
        end
        return
    end
    local old_text = result.item.notes or ""
    local new_text, count = ZP_CERCA.replace(old_text, search_query, replace_query, false)
    if count == 0 or new_text == old_text then return end
    reaper.Undo_BeginBlock()
    reaper.GetSetMediaItemInfo_String(result.item.item, "P_NOTES", new_text, true)
    UpdateSubtitleItemName(result.item.item, new_text)
    reaper.UpdateItemInProject(result.item.item)
    reaper.Undo_EndBlock(string.format("ZP Studio Suite: sostituisci '%s' con '%s'", search_query, replace_query), -1)
    reaper.UpdateArrange()
    UpdateItems()
    search_results_dirty = true
    RefreshSearchResults(true)
    -- resta sulla parola cambiata: il prossimo clic cerca la successiva
    search_results_current = 0
    search_message = "Sostituita · ne restano " .. tostring(search_results_total)
    search_message_until = reaper.time_precise() + 3.0
end

function IsSearchShortcut(char)
    if char == 6 then return true end
    local is_f = char == 70 or char == 102
    local has_modifier = ((gfx.mouse_cap & 4) == 4) or ((gfx.mouse_cap & 32) == 32)
    return is_f and has_modifier
end

function SearchGetFieldValue()
    return search_active_field == "replace" and replace_query or search_query
end

function SearchSetFieldValue(value)
    if search_active_field == "replace" then replace_query = value else search_query = value end
end

function SearchGetFieldCursor()
    return search_active_field == "replace" and replace_cursor or search_cursor
end

function SearchSetFieldCursor(value)
    if search_active_field == "replace" then replace_cursor = value else search_cursor = value end
end

function SearchSetCursor(pos)
    local value = SearchGetFieldValue() or ""
    SearchSetFieldCursor(math.max(1, math.min(pos or 1, #value + 1)))
    if search_active_field == "replace" then replace_sel_start, replace_sel_end = nil, nil
    else search_sel_start, search_sel_end = nil, nil end
end

function SearchSetSelection(a, b)
    local value = SearchGetFieldValue() or ""
    local max_pos = #value + 1
    a = math.max(1, math.min(a or 1, max_pos))
    b = math.max(1, math.min(b or a, max_pos))
    SearchSetFieldCursor(b)
    local first, last = math.min(a,b), math.max(a,b)
    if a == b then first,last = nil,nil end
    if search_active_field == "replace" then replace_sel_start,replace_sel_end=first,last
    else search_sel_start,search_sel_end=first,last end
end

function SearchSelectionRange()
    local a,b
    if search_active_field == "replace" then a,b=replace_sel_start,replace_sel_end
    else a,b=search_sel_start,search_sel_end end
    if not a or a == b then return nil,nil end
    return math.min(a,b),math.max(a,b)
end

function SearchDeleteSelection()
    local a,b=SearchSelectionRange()
    if not a then return false end
    local value=SearchGetFieldValue() or ""
    SearchSetFieldValue(value:sub(1,a-1)..value:sub(b))
    SearchSetCursor(a)
    return true
end

function SearchInsertText(text)
    text=tostring(text or "")
    if text=="" then return end
    SearchDeleteSelection()
    local value=SearchGetFieldValue() or ""
    local cursor=SearchGetFieldCursor() or (#value+1)
    SearchSetFieldValue(value:sub(1,cursor-1)..text..value:sub(cursor))
    SearchSetFieldCursor(cursor+#text)
    if search_active_field == "find" then ScheduleSearchResults() end
end

function SearchBackspace()
    if SearchDeleteSelection() then
        if search_active_field == "find" then ScheduleSearchResults() end
        return
    end
    local value=SearchGetFieldValue() or ""
    local cursor=SearchGetFieldCursor() or (#value+1)
    if cursor<=1 then return end
    local prev=Utf8PrevCursor(value,cursor)
    SearchSetFieldValue(value:sub(1,prev-1)..value:sub(cursor))
    SearchSetFieldCursor(prev)
    if search_active_field == "find" then ScheduleSearchResults() end
end

function SearchPaste()
    local clip = inline_clipboard
    if reaper.CF_GetClipboard then
        local ok, value = pcall(reaper.CF_GetClipboard, "")
        if ok and value and value ~= "" then clip = value end
    end
    if clip and clip ~= "" then SearchInsertText((clip:gsub("[\r\n]+", " "))) end
end

function ProcessSearchPanelKey(char)
    if not search_panel_open or char <= 0 then return false end
    if IsSearchShortcut(char) then return true end
    if char == 9 then
        if not search_replace_open then search_replace_open = true; replace_input_rect = nil; ScheduleSearchResults(); search_results_deadline = 0 end
        search_active_field = search_active_field == "find" and "replace" or "find"
        return true
    end
    if char == 30064 or char == 1685026670 then
        RefreshSearchResults(true)
        local step = char == 30064 and -1 or 1
        local next_index = search_results_current == 0 and (step > 0 and 1 or #search_results) or search_results_current + step
        if next_index >= 1 and next_index <= #search_results then SelectSearchResult(next_index, true) end
        return true
    end
    if char == 13 then ExecuteSubtitleSearch(1); return true end
    if char == 27 then search_panel_open = false; return true end
    if char == 8 then SearchBackspace(); return true end
    if char == 1 then SearchSetSelection(1, #SearchGetFieldValue() + 1); return true end
    if char == 22 then SearchPaste(); return true end
    if char == 1818584692 then SearchSetCursor(Utf8PrevCursor(SearchGetFieldValue(), SearchGetFieldCursor())); return true end
    if char == 1919379572 then SearchSetCursor(Utf8NextCursor(SearchGetFieldValue(), SearchGetFieldCursor())); return true end
    if char == 1752132965 then SearchSetCursor(1); return true end
    if char == 6647396 then SearchSetCursor(#SearchGetFieldValue() + 1); return true end
    if char >= 32 and char <= 1114111 then
        local ch = TextCharFromCode(char)
        if ch then SearchInsertText(ch) end
        return true
    end
    return false
end

function InitGUI()
    gfx.clear = 0x111111 
    -- toolbar: icona accesa finche' la finestra e' aperta; un altro clic sull'icona la chiude (REAPER 7.03+)
    if reaper.set_action_options then reaper.set_action_options(1 | 4); reaper.atexit(function() reaper.set_action_options(8) end) end
    gfx.init(WINDOW_TITLE, window_w, window_h, window_dock, window_x, window_y)
    gfx.setfont(1, default_font, master_font_size)
    last_saved_window_state = ""
    SaveWindowStateIfChanged()
end

-- =============================================
function WrapText(text, max_w)
    local lines = {}
    text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    for paragraph in (text .. "\n"):gmatch("(.-)\n") do
        local words = {}
        for word in paragraph:gmatch("%S+") do table.insert(words, word) end

        if #words == 0 then
            table.insert(lines, "")
        else
        
        local current_line = ""
        for _, word in ipairs(words) do
            local test_line = current_line == "" and word or current_line .. " " .. word
            local lw, _ = gfx.measurestr(test_line)
            if lw > max_w and current_line ~= "" then
                table.insert(lines, current_line)
                current_line = word
            else
                current_line = test_line
            end
        end
        if current_line ~= "" then table.insert(lines, current_line) end
        end
    end
    if #lines == 0 then table.insert(lines, "") end
    return lines
end

function CountWords(lines)
    local count = 0
    for _, line in ipairs(lines) do
        for _ in line:gmatch("%S+") do count = count + 1 end
    end
    return math.max(1, count)
end

function SetThemeColor(kind, alpha)
    alpha = alpha or 1
    -- SidebarThemeForce: la barra dei comandi resta sempre scura, qualunque sia il tema del testo.
    local theme_mode = SidebarThemeForce or theme_mode
    if SidebarThemeForce and kind == "dim" then kind = "text" end -- etichette leggibili sul fondo scuro
    if theme_mode == "dark" then
        if kind == "bg" then gfx.set(0.045, 0.045, 0.042, alpha)
        elseif kind == "panel" then gfx.set(0.075, 0.075, 0.08, alpha)
        elseif kind == "panel_line" then gfx.set(0.24, 0.24, 0.28, alpha)
        elseif kind == "text" then gfx.set(0.78, 0.76, 0.69, alpha)
        elseif kind == "active" then gfx.set(0.96, 0.91, 0.78, alpha)
        elseif kind == "dim" then gfx.set(0.45, 0.44, 0.40, alpha)
        elseif kind == "guide" then gfx.set(0.88, 0.64, 0.28, alpha)
        elseif kind == "word" then gfx.set(1.0, 0.95, 0.42, alpha)
        end
    elseif theme_mode == "light" then
        if kind == "bg" then gfx.set(1.00, 1.00, 1.00, alpha)
        elseif kind == "panel" then gfx.set(0.95, 0.95, 0.95, alpha)
        elseif kind == "panel_line" then gfx.set(0.72, 0.72, 0.72, alpha)
        elseif kind == "text" then gfx.set(0.02, 0.02, 0.02, alpha)
        elseif kind == "active" then gfx.set(0.00, 0.00, 0.00, alpha)
        elseif kind == "dim" then gfx.set(0.26, 0.26, 0.26, alpha)
        elseif kind == "guide" then gfx.set(0.06, 0.06, 0.06, alpha)
        elseif kind == "word" then gfx.set(0.64, 0.10, 0.00, alpha)
        end
    else
        if kind == "bg" then gfx.set(0.94, 0.93, 0.88, alpha)
        elseif kind == "panel" then gfx.set(0.86, 0.86, 0.78, alpha)
        elseif kind == "panel_line" then gfx.set(0.58, 0.56, 0.50, alpha)
        elseif kind == "text" then gfx.set(0.18, 0.17, 0.15, alpha)
        elseif kind == "active" then gfx.set(0.05, 0.05, 0.045, alpha)
        elseif kind == "dim" then gfx.set(0.42, 0.40, 0.35, alpha)
        elseif kind == "guide" then gfx.set(0.70, 0.38, 0.05, alpha)
        elseif kind == "word" then gfx.set(0.58, 0.18, 0.00, alpha)
        end
    end
end

local SEARCH_EDGE_PUNCT = {
    "’", "‘", "“", "”", "«", "»", "‹", "›", "—", "–", "…", "·", "•", " ",
    " ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " ", "​", "　",
    "、", "。", "，", "．", "！", "？", "：", "；", "（", "）", "［", "］", "｛", "｝",
}

function DrawTextLine(line, x, y, is_active, item, word_counter, base_color_kind, base_alpha)
    local function clean_word(word)
        word = tostring(word or ""):gsub("^%p+", ""):gsub("%p+$", "")
        local changed = true
        while changed do
            changed = false
            for _, punct in ipairs(SEARCH_EDGE_PUNCT) do
                if word:sub(1, #punct) == punct then word = word:sub(#punct + 1); changed = true end
                if word:sub(-#punct) == punct then word = word:sub(1, -#punct - 1); changed = true end
            end
        end
        return NormalizeSearchText(word)
    end

    local function word_is_highlighted(word)
        if item and search_hit_item == item.item and reaper.time_precise() <= search_hit_until then
            local live = trim(search_hit_query or "")
            if live ~= "" and not live:find("%s") then
                if ZP_CERCA.word_matches(clean_word(word), live) then return true end
            end
        end
        local highlights = item and item.highlights or nil
        if not highlights or #highlights == 0 then return false end
        local clean = clean_word(word)
        if clean == "" then return false end
        for _, term in ipairs(highlights) do
            local h = NormalizeSearchText(term)
            if h ~= "" and (clean == h or h:find(clean, 1, true) or clean:find(h, 1, true)) then return true end
        end
        return false
    end

    local target_word = item.reading_state and item.reading_state.word or math.floor((item.total_words or 1) * active_progress) + 1
    local group_radius = item.timed_scroll and 0 or 1
    local cursor_x = x
    local first = true

    for word in line:gmatch("%S+") do
        if not first then
            local sw = gfx.measurestr(" ")
            cursor_x = cursor_x + sw
        end
        first = false

        local current = word_counter + 1
        local highlighted = word_is_highlighted(word)
        local word_w, word_h = gfx.measurestr(word)
        if highlighted then
            gfx.set(1.0, 0.72, 0.10, is_active and 0.50 or 0.34)
            gfx.rect(cursor_x - 3, y - 2, word_w + 6, word_h + 4, 1)
        end

        if word_follow and is_active and current >= target_word and current <= target_word + group_radius then
            SetThemeColor("word", 1)
        else
            SetThemeColor(base_color_kind or "active", base_alpha or 0.72)
        end

        gfx.x = cursor_x
        gfx.y = y
        gfx.drawstr(word)
        cursor_x = cursor_x + word_w
        word_counter = current
    end

    return word_counter
end

local NOTE_FONT, NOTE_LINE_H = 17, 21

function DrawWrappedNoteText(text, x, y, max_w, alpha)
    gfx.setfont(3, "Arial", NOTE_FONT)
    local lines = WrapText(text:gsub("[\r\n]+", " "), max_w)
    local line_h = NOTE_LINE_H
    for i, line in ipairs(lines) do
        gfx.x = x
        gfx.y = y + ((i - 1) * line_h)
        gfx.drawstr(line)
    end
    return #lines * line_h
end

function MeasureWrappedNoteText(text, max_w)
    gfx.setfont(3, "Arial", NOTE_FONT)
    local lines = WrapText((text or ""):gsub("[\r\n]+", " "), max_w)
    return #lines * NOTE_LINE_H
end

function NoteVisualState(note, play_pos)
    local note_end = note.pos + note.len
    local delta = note.pos - play_pos
    local active = play_pos >= note.pos - NOTE_HOT_MARGIN and play_pos <= note_end + NOTE_HOT_MARGIN
    local imminent = delta > 0 and delta <= NOTE_WAKE_LEAD
    local past = play_pos > note_end + NOTE_HOT_MARGIN

    if active then return "active", 1.0 end
    if imminent then return "imminent", 0.44 + ((NOTE_WAKE_LEAD - delta) / NOTE_WAKE_LEAD) * 0.46 end
    if past then return "past", 0.18 end
    return "future", 0.26
end

-- Segna una nota come fatta (bollino OK) o la riapre. Sta nell'item: P_EXT:ZP_NOTE_DONE.
function ToggleNoteDone(note)
    if not note or not note.item or not reaper.ValidatePtr(note.item, "MediaItem*") then return end
    local done = not note.done
    reaper.Undo_BeginBlock()
    reaper.GetSetMediaItemInfo_String(note.item, "P_EXT:ZP_NOTE_DONE", done and "1" or "", true)
    reaper.Undo_EndBlock(done and "ZP Studio Suite: nota fatta (OK)" or "ZP Studio Suite: nota riaperta", -1)
    note.done = done
    UpdateItems()
end

-- Pannello NOTE: prima le note ancora da concludere, poi quelle OK; entrambe in ordine di tempo.
-- Segue da solo la nota corrente (attiva o la prossima) finche' non scorri a mano (5 s di pausa).
-- Clic = porta la timeline alla nota; doppio clic = modifica; bollino OK = fatta / riaperta.
-- Stato tra un giro e l'altro in globali (NotesScroll, NotesUserScrollTime): niente local nuovi.
function DrawNotesPanel(h, play_pos, reading_y)
    if panels_hidden or not notes_panel_open then return end

    local x = 0
    local pad = 12
    local panel_w = NOTES_PANEL_W
    local bar_w = 6
    gfx.set(0.10, 0.095, 0.075, 0.96)
    gfx.rect(x, 0, panel_w, h, 1)

    local clip_top = 42
    local clip_bottom = h - 8
    local max_w = panel_w - (pad * 2) - bar_w
    local now = reaper.time_precise()

    -- misure e nota corrente
    local entries, total_h, current_i, done_n = {}, 0, nil, 0
    local display_notes = {}
    for i, note in ipairs(cached_notes) do display_notes[i] = note end
    table.sort(display_notes, function(a, b)
        if a.done ~= b.done then return not a.done end
        return a.pos < b.pos
    end)
    for i, note in ipairs(display_notes) do
        local card_h = MeasureWrappedNoteText(note.text, max_w) + 38
        entries[i] = { note = note, top = total_h, card_h = card_h }
        total_h = total_h + card_h + 8
        if note.done then done_n = done_n + 1 end
        if not current_i and play_pos <= note.pos + note.len + NOTE_HOT_MARGIN then current_i = i end
    end
    local view_h = math.max(1, clip_bottom - clip_top)
    local max_scroll = math.max(0, total_h - view_h)

    -- rotella sopra il pannello: scorrimento a mano (NotesWheel la mette il ciclo principale)
    local over_panel = gfx.mouse_x >= x and gfx.mouse_x < panel_w and gfx.mouse_y >= clip_top and gfx.mouse_y <= clip_bottom
    local right_down = (gfx.mouse_cap & 2) == 2
    if right_down and not note_context_was_down and over_panel and not inline_edit
        and not (search_panel_open and SearchPanelBottom and gfx.mouse_y <= SearchPanelBottom) then
        -- gfx.showmenu usa gfx.x/gfx.y come ancora: posizionalo dove si trova il puntatore.
        gfx.x = math.max(0, math.min(gfx.mouse_x, gfx.w - 1))
        gfx.y = math.max(0, math.min(gfx.mouse_y, gfx.h - 1))
        if gfx.showmenu(T("Nuova nota")) == 1 then InsertNoteAtCurrentPosition() end
    end
    note_context_was_down = right_down
    if over_panel and (NotesWheel or 0) ~= 0 then
        NotesScroll = (NotesScroll or 0) + (NotesWheel > 0 and -60 or 60)
        NotesUserScrollTime = now
        NotesWheel = 0
    end
    if current_i and now - (NotesUserScrollTime or 0) > 5 and not over_panel then
        local target = entries[current_i].top - 40
        NotesScroll = (NotesScroll or 0) + (target - (NotesScroll or 0)) * 0.25
    end
    NotesScroll = math.max(0, math.min(NotesScroll or 0, max_scroll))

    local mouse_pressed = (gfx.mouse_cap & 1) == 1 and not mouse_was_down
    local clicks_ok = mouse_pressed and over_panel and not inline_edit
        and not (search_panel_open and SearchPanelBottom and gfx.mouse_y <= SearchPanelBottom)
    local clicked_note_card = false

    for i, entry in ipairs(entries) do
        local note = entry.note
        local y = clip_top + 4 + entry.top - NotesScroll
        local card_h = entry.card_h
        if y > clip_bottom then break end
        if y + card_h >= clip_top then
            local state, alpha = NoteVisualState(note, play_pos)
            local is_current = i == current_i

            -- corrente (attiva) quasi piena; le altre trasparenti; fatte attenuate
            local card_alpha = 0.22
            if note.done then card_alpha = 0.08
            elseif state == "active" then card_alpha = 0.92
            elseif is_current or state == "imminent" then card_alpha = 0.40 end
            local text_alpha = note.done and 0.55 or 0.95
            gfx.set(note.r, note.g, note.b, card_alpha)
            gfx.rect(x + 6, y - 4, panel_w - 12 - bar_w, card_h, 1)
            if is_current then
                gfx.set(1.0, 0.70, 0.12, 1)
                gfx.rect(x + 2, y - 4, 4, card_h, 1)
            end

            -- x (cancella) a sinistra, lontana dal bollino OK a destra: niente cancellazioni per sbaglio
            local ok_w, ok_h = 44, 18
            local del_w = 20
            local del_x = x + pad - 2
            local ok_x, ok_y = x + panel_w - 12 - bar_w - ok_w - 4, y - 1

            gfx.setfont(3, "Arial", 14, 'b')
            SetNoteCardTextColor(note.r, note.g, note.b, card_alpha, text_alpha)
            gfx.x, gfx.y = del_x + del_w + 8, y
            gfx.drawstr(FormatVideoTimecode(note.pos))
            -- x: cancella (chiede conferma)
            SetNoteCardTextColor(note.r, note.g, note.b, card_alpha, 0.75)
            gfx.rect(del_x, ok_y, del_w, ok_h, 0)
            gfx.setfont(3, "Arial", 13, 'b')
            local xw = gfx.measurestr("×")
            gfx.x, gfx.y = del_x + math.floor((del_w - xw) / 2), ok_y + 2
            gfx.drawstr("×")
            if note.done then
                gfx.set(0.25, 0.68, 0.36, 1); gfx.rect(ok_x, ok_y, ok_w, ok_h, 1)
                gfx.set(1, 1, 1, 1)
            else
                SetNoteCardTextColor(note.r, note.g, note.b, card_alpha, 0.75)
                gfx.rect(ok_x, ok_y, ok_w, ok_h, 0)
            end
            gfx.setfont(3, "Arial", 12, 'b')
            local label = note.done and "✓ OK" or "OK"
            local lw = gfx.measurestr(label)
            gfx.x, gfx.y = ok_x + math.floor((ok_w - lw) / 2), ok_y + 3
            gfx.drawstr(label)

            SetNoteCardTextColor(note.r, note.g, note.b, card_alpha, text_alpha)
            DrawWrappedNoteText(note.text, x + pad, y + 21, max_w, alpha)

            if clicks_ok and gfx.mouse_y >= math.max(clip_top, y - 4) and gfx.mouse_y <= y - 4 + card_h then
                clicked_note_card = true
                local mx, my = gfx.mouse_x, gfx.mouse_y
                if mx >= ok_x and mx <= ok_x + ok_w and my >= ok_y and my <= ok_y + ok_h then
                    ToggleNoteDone(note)
                elseif mx >= del_x and mx <= del_x + del_w and my >= ok_y and my <= ok_y + ok_h then
                    DeleteNote(note)
                elseif note_last_click_item == note.item and now - (note_last_click_time or 0) < 0.35 then
                    StartInlineNoteEdit(note)   -- doppio clic: modifica
                    note_last_click_item = nil
                else
                    reaper.SetEditCurPos(note.pos, true, false)   -- clic: timeline alla nota
                    reaper.UpdateArrange()
                    note_last_click_item, note_last_click_time = note.item, now
                    NotesUserScrollTime = 0   -- torna a seguire: la nota cliccata diventa la corrente
                end
                clicks_ok = false
            end
        end
    end

    -- Doppio clic nello spazio libero del pannello = nuova nota al cursore/playhead.
    if clicks_ok and not clicked_note_card and gfx.mouse_x < panel_w - bar_w
        and gfx.mouse_y >= clip_top and gfx.mouse_y <= clip_bottom then
        if now - note_empty_click_time < 0.35 then
            note_empty_click_time = 0
            InsertNoteAtCurrentPosition()
        else
            note_empty_click_time = now
        end
    end

    -- intestazione disegnata sopra le schede che scorrono (gfx non ha il ritaglio)
    gfx.set(0.10, 0.095, 0.075, 1)
    gfx.rect(x, 0, panel_w, clip_top, 1)
    gfx.rect(x, clip_bottom, panel_w, h - clip_bottom, 1)
    gfx.setfont(3, "Arial", 15, 'b')
    gfx.set(0.95, 0.84, 0.42, 1)
    gfx.x, gfx.y = x + pad, 14
    gfx.drawstr(T("NOTE"))
    gfx.setfont(3, "Arial", 13)
    gfx.set(0.85, 0.80, 0.68, 1)
    gfx.x, gfx.y = x + pad + 52, 16
    gfx.drawstr(#entries == 0 and "" or (tostring(#entries) .. (done_n > 0 and ("  ·  " .. done_n .. " OK") or "")))

    -- barra di scorrimento
    if max_scroll > 0 then
        local track_x = panel_w - bar_w - 2
        gfx.set(0.22, 0.20, 0.16, 1)
        gfx.rect(track_x, clip_top, bar_w - 2, view_h, 1)
        local thumb_h = math.max(24, view_h * view_h / total_h)
        local thumb_y = clip_top + (view_h - thumb_h) * (NotesScroll / max_scroll)
        gfx.set(0.80, 0.62, 0.25, 1)
        gfx.rect(track_x, thumb_y, bar_w - 2, thumb_h, 1)
    end
    gfx.set(0.55, 0.42, 0.18, 0.75)
    gfx.rect(panel_w - 1, 0, 1, h, 1)

    if #entries == 0 then
        gfx.setfont(3, "Arial", 14)
        gfx.set(0.80, 0.76, 0.66, 1)
        gfx.x, gfx.y = x + pad, clip_top + 10
        gfx.drawstr("Nessuna nota")
    end
end

function UpdateSubtitleItemName(item, text)
    local one_line = trim((text or ""):gsub("[\r\n]+", " / "))
    one_line = one_line:gsub("%s+", " ")
    if #one_line > 160 then
        local finish=157
        while finish>0 and one_line:byte(finish+1)>=128 and one_line:byte(finish+1)<192 do finish=finish-1 end
        one_line=one_line:sub(1,finish).."..."
    end
    reaper.GetSetMediaItemInfo_String(item, "P_NAME", one_line, true)
    reaper.UpdateItemInProject(item)
end

function Utf8PrevCursor(text, cursor)
    text = tostring(text or "")
    cursor = math.max(1, math.min(cursor or (#text + 1), #text + 1))
    if cursor <= 1 then return 1 end
    -- a mano, senza utf8.offset: va in errore se la posizione cade a meta' di una lettera
    -- accentata ("initial position is a continuation byte"). Salta i byte 0x80-0xBF.
    local pos = cursor - 1
    while pos > 1 do
        local b = text:byte(pos)
        if not b or b < 0x80 or b >= 0xC0 then break end
        pos = pos - 1
    end
    return pos
end

function Utf8NextCursor(text, cursor)
    text = tostring(text or "")
    cursor = math.max(1, math.min(cursor or (#text + 1), #text + 1))
    if cursor > #text then return #text + 1 end
    local pos = cursor + 1
    while pos <= #text do
        local b = text:byte(pos)
        if b < 0x80 or b >= 0xC0 then break end
        pos = pos + 1
    end
    return pos
end

function InlineSetCursor(pos)
    if not inline_edit then return end
    inline_edit.cursor = math.max(1, math.min(pos or 1, #(inline_edit.text or "") + 1))
    inline_edit.sel_start = nil
    inline_edit.sel_end = nil
end

function InlineSetSelection(a, b)
    if not inline_edit then return end
    local max_pos = #(inline_edit.text or "") + 1
    a = math.max(1, math.min(a or 1, max_pos))
    b = math.max(1, math.min(b or a, max_pos))
    inline_edit.cursor = b
    if a == b then
        inline_edit.sel_start = nil
        inline_edit.sel_end = nil
    else
        inline_edit.sel_start = math.min(a, b)
        inline_edit.sel_end = math.max(a, b)
    end
end

function InlineSelectionRange()
    if not inline_edit or not inline_edit.sel_start or inline_edit.sel_start == inline_edit.sel_end then return nil, nil end
    return math.min(inline_edit.sel_start, inline_edit.sel_end), math.max(inline_edit.sel_start, inline_edit.sel_end)
end

function InlineSelectedText()
    local a, b = InlineSelectionRange()
    if not a then return "" end
    return (inline_edit.text or ""):sub(a, b - 1)
end

function InlinePushUndo()
    InitInlineCopione(); SyncInlineAnchors()
    if not inline_edit then return end
    inline_edit.undo_stack = inline_edit.undo_stack or {}
    inline_edit.undo_stack[#inline_edit.undo_stack + 1] = {
        text = inline_edit.text or "",
        anchors_raw=ZP_TESTO.serialize_anchors(inline_edit.anchors),
        cursor = inline_edit.cursor or 1,
        sel_start = inline_edit.sel_start,
        sel_end = inline_edit.sel_end,
        highlights = SerializeHighlightTerms(inline_edit.highlights or {}),
        imported_highlights = inline_edit.imported_highlights,
        import_highlights = inline_edit.import_highlights
    }
    if #inline_edit.undo_stack > 80 then table.remove(inline_edit.undo_stack, 1) end
end

function InlineRestoreUndo()
    if not inline_edit or not inline_edit.undo_stack then return end
    local state = table.remove(inline_edit.undo_stack)
    if not state then return end
    inline_edit.text = state.text or ""
    inline_edit.anchors=ZP_TESTO.parse_anchors(state.anchors_raw)
    inline_edit.anchors_text=inline_edit.text
    inline_edit.cursor = state.cursor or (#(inline_edit.text or "") + 1)
    inline_edit.sel_start = state.sel_start
    inline_edit.sel_end = state.sel_end
    inline_edit.highlights = ParseHighlightTerms(state.highlights or "")
    inline_edit.imported_highlights = state.imported_highlights
    inline_edit.import_highlights = state.import_highlights
    inline_edit.desired_x = nil
end

function InlineDeleteSelection()
    local a, b = InlineSelectionRange()
    if not a then return false end
    local source = inline_edit.text or ""
    inline_edit.text = source:sub(1, a - 1) .. source:sub(b)
    InlineSetCursor(a)
    return true
end

function InlineInsertText(text)
    InitInlineCopione()
    if not inline_edit then return end
    if tostring(text or "") == "" then return end
    InlinePushUndo()
    InlineDeleteSelection()
    local source = inline_edit.text or ""
    local cursor = inline_edit.cursor or (#source + 1)
    inline_edit.text = source:sub(1, cursor - 1) .. text .. source:sub(cursor)
    inline_edit.cursor = cursor + #text
end

function InlineBackspace()
    if not inline_edit then return end
    if InlineSelectionRange() then InlinePushUndo(); InlineDeleteSelection(); return end
    local source = inline_edit.text or ""
    local cursor = inline_edit.cursor or (#source + 1)
    if cursor <= 1 then return end
    InlinePushUndo()
    local prev = Utf8PrevCursor(source, cursor)
    inline_edit.text = source:sub(1, prev - 1) .. source:sub(cursor)
    inline_edit.cursor = prev
end

function InlineDelete()
    if not inline_edit then return end
    if InlineSelectionRange() then InlinePushUndo(); InlineDeleteSelection(); return end
    local source = inline_edit.text or ""
    local cursor = inline_edit.cursor or (#source + 1)
    if cursor > #source then return end
    InlinePushUndo()
    local next_pos = Utf8NextCursor(source, cursor)
    inline_edit.text = source:sub(1, cursor - 1) .. source:sub(next_pos)
end

function InlineSplitLines()
    local source = inline_edit and inline_edit.text or ""
    local lines = {}
    local line_start = 1
    while true do
        local nl = source:find("\n", line_start, true)
        if nl then
            table.insert(lines, {text=source:sub(line_start, nl - 1), start=line_start, finish=nl - 1})
            line_start = nl + 1
        else
            table.insert(lines, {text=source:sub(line_start), start=line_start, finish=#source})
            break
        end
    end
    return lines
end

function InlineVisualLines(max_w)
    local source = inline_edit and inline_edit.text or ""
    local visual = {}
    max_w = math.max(40, max_w or 400)

    for _, paragraph in ipairs(InlineSplitLines()) do
        local paragraph_text = source:sub(paragraph.start, paragraph.finish)
        local current_start = nil
        local current_finish = nil
        local current_text = ""

        for rel_start, word in paragraph_text:gmatch("()(%S+)") do
            local word_start = paragraph.start + rel_start - 1
            local word_finish = word_start + #word - 1
            local candidate = current_text == "" and word or (current_text .. " " .. word)
            local candidate_w = gfx.measurestr(candidate)

            if current_text ~= "" and candidate_w > max_w then
                table.insert(visual, {
                    text = source:sub(current_start, current_finish),
                    start = current_start,
                    finish = current_finish
                })
                current_start = word_start
                current_finish = word_finish
                current_text = word
            else
                if not current_start then current_start = word_start end
                current_finish = word_finish
                current_text = candidate
            end
        end

        if current_start then
            table.insert(visual, {
                text = source:sub(current_start, current_finish),
                start = current_start,
                finish = current_finish
            })
        else
            table.insert(visual, {text="", start=paragraph.start, finish=paragraph.start - 1})
        end
    end

    if #visual == 0 then table.insert(visual, {text="", start=1, finish=0}) end
    return visual
end

function InlineCursorFromPoint(px, py)
    if not inline_edit then return end
    local line_h = inline_edit.line_h or (inline_edit.font_size * 1.45)
    local line_index = math.floor((py - inline_edit.text_y) / line_h) + 1
    local lines = InlineVisualLines(inline_edit.text_w or 400)
    line_index = math.max(1, math.min(line_index, #lines))
    local line = lines[line_index]
    local rel_x = math.max(0, px - inline_edit.text_x)
    InlineSetCursor(ZP_TESTO.cursor_in_words(inline_edit.text,line.start,line.finish,rel_x,gfx.measurestr))
end

function InlineCursorAtPoint(px, py)
    local old_start, old_end = inline_edit and inline_edit.sel_start, inline_edit and inline_edit.sel_end
    InlineCursorFromPoint(px, py)
    local cursor = inline_edit and inline_edit.cursor or 1
    if inline_edit then
        inline_edit.sel_start = old_start
        inline_edit.sel_end = old_end
    end
    return cursor
end

function InlineSelectWordAtCursor()
    if not inline_edit then return end
    local text = inline_edit.text or ""
    if text == "" then return end
    local cursor = math.max(1, math.min(inline_edit.cursor or 1, #text + 1))
    local pos = math.min(cursor, #text)
    if text:sub(pos, pos):match("[%s%p]") and pos > 1 then pos = pos - 1 end
    while pos > 1 and text:sub(pos, pos):match("[%s%p]") do pos = pos - 1 end
    local a = pos
    while a > 1 and not text:sub(a - 1, a - 1):match("[%s%p]") do a = a - 1 end
    local b = pos + 1
    while b <= #text and not text:sub(b, b):match("[%s%p]") do b = b + 1 end
    InlineSetSelection(a, b)
end

function InlineCopy()
    local selected = InlineSelectedText()
    if selected == "" then return end
    inline_clipboard = selected
    if reaper.CF_SetClipboard then pcall(reaper.CF_SetClipboard, selected) end
end

function InlineCut()
    InlineCopy()
    InlinePushUndo()
    InlineDeleteSelection()
end

function ParseHighlightTerms(text)
    local terms = {}
    for raw_line in tostring(text or ""):gmatch("[^\n]+") do
        local line = trim(raw_line:gsub("\r", " "))
        if line ~= "" then table.insert(terms, line) end
    end
    return terms
end

function SerializeHighlightTerms(terms)
    local out = {}
    for _, term in ipairs(terms or {}) do
        term = trim(tostring(term or ""):gsub("[\r\n]+", " "))
        if term ~= "" then table.insert(out, term) end
    end
    return table.concat(out, "\n")
end

function InlineMoveVertical(direction)
    if not inline_edit then return end
    local lines = InlineVisualLines(inline_edit.text_w or 400)
    local cursor = inline_edit.cursor or (#(inline_edit.text or "") + 1)
    local current_line = 1
    for i, line in ipairs(lines) do
        if cursor >= line.start and cursor <= line.finish + 1 then current_line = i; break end
    end
    local line = lines[current_line]
    local prefix = inline_edit.text:sub(line.start, cursor - 1)
    local desired_x = inline_edit.desired_x or gfx.measurestr(prefix)
    inline_edit.desired_x = desired_x
    local target = math.max(1, math.min(current_line + direction, #lines))
    local target_line = lines[target]
    local best = target_line.start
    local pos=target_line.start
    while pos<=target_line.finish+1 do
        local tw = gfx.measurestr(inline_edit.text:sub(target_line.start, pos - 1))
        if tw > desired_x then break end
        if pos > #inline_edit.text or (inline_edit.text:byte(pos) or 0) < 128 or (inline_edit.text:byte(pos) or 0) >= 192 then best = pos end
        if pos>=#inline_edit.text+1 then break end
        pos=Utf8NextCursor(inline_edit.text,pos)
    end
    InlineSetCursor(best)
end

function StartInlineSubtitleEdit(item, x, y, w, h, click_x, click_y)
    if not item then return end
    local _, old_text = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    inline_edit = {
        item = item,
        original = (old_text or ""):gsub("\r\n", "\n"):gsub("\r", "\n"),
        text = (old_text or ""):gsub("\r\n", "\n"):gsub("\r", "\n"),
        cursor = #((old_text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")) + 1,
        x = x,
        y = y,
        w = math.max(260, w),
        h = math.max(master_font_size * 3.0, h),
        font_size = master_font_size,
        title = "Modifica battuta",
        undo_stack = {}
    }
    if click_x and click_y then
        gfx.setfont(1,default_font,master_font_size)
        inline_edit.text_x,inline_edit.text_y=x+8,y+4
        inline_edit.text_w,inline_edit.line_h=w,master_font_size*1.55
        InlineCursorFromPoint(click_x,click_y)
        inline_edit.center_cursor=true
        inline_edit.opening_mouse_down=true
    end
    -- Aprire il testo conserva trasporto e posizione della timeline.
end

function StartInlineNoteEdit(note)
    local initial_text = note and note.text or "[NOTA] "
    initial_text = tostring(initial_text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local editor_w = math.min(720, math.max(360, gfx.w - 80))
    local editor_h = math.max(190, math.min(280, gfx.h - 60))
    inline_edit = {
        item = note and note.item or nil,
        mode = note and "note_edit" or "note_new",
        note_position = note and note.pos or GetCurrentProjectPosition(),
        original = initial_text,
        text = initial_text,
        cursor = #initial_text + 1,
        x = math.max(12, (gfx.w - editor_w) * 0.5),
        y = math.max(12, (gfx.h - editor_h) * 0.42),
        w = editor_w,
        h = editor_h,
        font_size = math.max(18, math.min(master_font_size, 28)),
        title = note and "Modifica nota" or "Nuova nota",
        undo_stack = {}
    }
    reaper.OnStopButton()
end

function SaveInlineSubtitleEdit()
    InitInlineCopione(); SyncInlineAnchors()
    if not inline_edit then return end
    local new_text = (inline_edit.text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local mode = inline_edit.mode or "subtitle"
    if mode == "timed_new" and trim(new_text) ~= "" then
        local track = GetOrCreateTextFlowTrack()
        if track then
            local pos = inline_edit.timed_position or GetCurrentProjectPosition()
            local wpm = inline_edit.timed_wpm or timed_scroll_wpm
            local duration = TimedTextDuration(new_text, wpm)
            reaper.Undo_BeginBlock()
            local item = reaper.AddMediaItemToTrack(track)
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
            reaper.SetMediaItemInfo_Value(item, "D_LENGTH", duration)
            reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", NativeColor(COLOR_SUBS))
            reaper.GetSetMediaItemInfo_String(item, "P_NOTES", new_text, true)
            reaper.GetSetMediaItemInfo_String(item, "P_EXT:ZP_TIMED_SCROLL", "1", true)
            reaper.GetSetMediaItemInfo_String(item, "P_EXT:ZP_TIMED_SCROLL_WPM", tostring(wpm), true)
            ApplyInlineMetadata(item)
            UpdateSubtitleItemName(item, new_text)
            reaper.UpdateItemInProject(item)
            reaper.Undo_EndBlock("ZP Studio Suite: inserisci testo temporizzato", -1)
            timed_manual_override = false
            timed_reposition_requested = true
        end
    elseif mode == "note_new" and trim(new_text) ~= "" then
        local track = GetOrCreateNotesTrack()
        if not track then
            reaper.ShowMessageBox(T("Impossibile creare la traccia note."), "ZP Studio Suite", 0)
            return
        end
        reaper.Undo_BeginBlock()
        local item = reaper.AddMediaItemToTrack(track)
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", inline_edit.note_position or GetCurrentProjectPosition())
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", NOTE_DEFAULT_LEN)
        reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", NativeColor(COLOR_NOTES))
        reaper.GetSetMediaItemInfo_String(item, "P_NOTES", new_text, true)
        ApplyInlineMetadata(item)
        reaper.GetSetMediaItemInfo_String(item, "P_NAME", "NOTA", true)
        do -- aggancia la nota alla battuta che ha sotto (o alla piu' vicina)
            local note_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local target = NoteTargetItem(CollectAllTextItems(), note_pos, NOTE_LINK_MAX_DISTANCE)
            if target then SetNoteLink(item, target, note_pos) end
        end
        reaper.UpdateItemInProject(item)
        reaper.Undo_EndBlock("ZP Studio Suite: inserisci nota dal gobbo", -1)
    elseif mode == "note_edit" and inline_edit.item and trim(new_text) ~= "" and (new_text ~= inline_edit.original or InlineHighlightRaw() ~= inline_edit.original_highlights or (inline_edit.timed_existing and inline_edit.timed_wpm~=inline_edit.original_wpm)) then
        reaper.Undo_BeginBlock()
        reaper.GetSetMediaItemInfo_String(inline_edit.item, "P_NOTES", new_text, true)
        ApplyInlineMetadata(inline_edit.item)
        reaper.GetSetMediaItemInfo_String(inline_edit.item, "P_NAME", "NOTA", true)
        reaper.UpdateItemInProject(inline_edit.item)
        reaper.Undo_EndBlock("ZP Studio Suite: modifica nota dal gobbo", -1)
    elseif mode == "subtitle" and inline_edit.item and trim(new_text) ~= "" and (new_text ~= inline_edit.original or InlineHighlightRaw() ~= inline_edit.original_highlights or (inline_edit.timed_existing and inline_edit.timed_wpm~=inline_edit.original_wpm)) then
        reaper.Undo_BeginBlock()
        reaper.GetSetMediaItemInfo_String(inline_edit.item, "P_NOTES", new_text, true)
        ApplyInlineMetadata(inline_edit.item)
        UpdateSubtitleItemName(inline_edit.item, new_text)
        reaper.Undo_EndBlock("ZP Studio Suite: modifica testo inline dal gobbo verticale", -1)
    end
    inline_edit = nil
    reaper.UpdateArrange()
    UpdateItems()
    RecalculateDocumentLayout()
end

function ProcessInlineSubtitleEditKey(char)
    if inline_edit then gfx.setfont(1,default_font,inline_edit.layout_font or math.min(28,inline_edit.font_size or 22)) end
    if not inline_edit or char <= 0 then return false end
    if char == 13 then
        if (gfx.mouse_cap & 8) == 8 then
            InlineInsertText((inline_edit.mode=="note_new" or inline_edit.mode=="note_edit") and "\n" or "\n\n")
        else
            SaveInlineSubtitleEdit()
        end
        return true
    elseif char == 27 then
        inline_edit = nil
        return true
    elseif char == 8 then
        InlineBackspace()
        return true
    elseif char == 1 then
        InlineSetSelection(1, #(inline_edit.text or "") + 1)
        return true
    elseif char == 3 then
        InlineCopy()
        return true
    elseif char == 22 then
        InlinePaste()
        return true
    elseif char == 24 then
        InlineCut()
        return true
    elseif char == 26 or (((gfx.mouse_cap & 4) == 4 or (gfx.mouse_cap & 32) == 32) and (char == 90 or char == 122)) then
        InlineRestoreUndo()
        return true
    elseif char == 5 then
        InlineToggleHighlight()
        return true
    elseif char == 6579564 then
        InlineDelete()
        return true
    elseif char == 1818584692 then
        InlineSetCursor(Utf8PrevCursor(inline_edit.text, inline_edit.cursor))
        inline_edit.desired_x = nil
        return true
    elseif char == 1919379572 then
        InlineSetCursor(Utf8NextCursor(inline_edit.text, inline_edit.cursor))
        inline_edit.desired_x = nil
        return true
    elseif char == 30064 then
        InlineMoveVertical(-1)
        return true
    elseif char == 1685026670 then
        InlineMoveVertical(1)
        return true
    elseif char == 1752132965 then
        InlineSetCursor(1)
        return true
    elseif char == 6647396 then
        InlineSetCursor(#(inline_edit.text or "") + 1)
        return true
    elseif char >= 32 and char <= 1114111 then
        local ch = TextCharFromCode(char)
        if ch then InlineInsertText(ch) end
        return true
    end
    return true
end


function InitInlineCopione()
    local e=inline_edit
    if not e or e.metadata_ready then return end
    e.metadata_ready=true
    local raw=''
    if e.item then
        raw=({reaper.GetSetMediaItemInfo_String(e.item,'P_EXT:RythmoBand_HIGHLIGHT','',false)})[2] or ''
        e.timed_existing=({reaper.GetSetMediaItemInfo_String(e.item,'P_EXT:ZP_TIMED_SCROLL','',false)})[2]=='1'
        e.timed_wpm=tonumber(({reaper.GetSetMediaItemInfo_String(e.item,'P_EXT:ZP_TIMED_SCROLL_WPM','',false)})[2]) or 120
    end
    e.timed_wpm=math.max(40,math.min(240,e.timed_wpm or 120))
    if e.item then e.pause_weight=tonumber(({reaper.GetSetMediaItemInfo_String(e.item,'P_EXT:ZP_TIMED_SCROLL_PAUSE_WEIGHT','',false)})[2]) end
    e.anchors=e.item and ZP_TESTO.parse_anchors(({reaper.GetSetMediaItemInfo_String(e.item,'P_EXT:ZP_GOBBO_ANCHORS','',false)})[2]) or {}
    e.anchors_text=e.text
    e.original_duration=e.item and reaper.GetMediaItemInfo_Value(e.item,'D_LENGTH') or nil
    e.original_wpm=e.timed_wpm
    e.original_highlights=raw
    e.highlights=ParseHighlightTerms(raw)
    e.recalculate=true
end
function InlineHighlightRaw()
    InitInlineCopione()
    local terms={}
    for _,v in ipairs(inline_edit.highlights or {}) do terms[#terms+1]=v end
    if inline_edit.import_highlights then
        for _,v in ipairs(inline_edit.imported_highlights or {}) do terms[#terms+1]=v end
    end
    local out,seen={},{}
    for _,v in ipairs(terms) do if not seen[v] then out[#out+1]=v; seen[v]=true end end
    return SerializeHighlightTerms(out)
end
function SyncInlineAnchors()
    if not inline_edit or not inline_edit.metadata_ready then return end
    local e=inline_edit
    if e.anchors_text~=e.text then
        e.anchors=ZP_TESTO.relocate_anchors(e.anchors_text or e.original,e.text,e.anchors)
        e.anchors_text=e.text
    end
end
function InlineEstimatedDuration(text,wpm)
    local e=inline_edit
    if e and e.timed_existing and e.recalculate==false then return e.original_duration end
    local duration,pauses=TimedTextDuration(text,wpm)
    if e and e.timed_existing and wpm==e.original_wpm and ZP_TESTO.same_words(text,e.original) then
        -- La pausa allunga la durata reale, anche se prima era stata fissata a mano.
        local _,old_pauses,pause_seconds=TimedTextDuration(e.original,wpm)
        duration=math.max(0.2,e.original_duration+(pauses-old_pauses)*pause_seconds)
    end
    return duration
end
function ApplyInlineMetadata(item)
    if inline_edit.text~=inline_edit.original or inline_edit.timed_wpm~=inline_edit.original_wpm then
        reaper.GetSetMediaItemInfo_String(item,'P_EXT:ZP_GOBBO_TIMING','',true)
        reaper.GetSetMediaItemInfo_String(item,'P_EXT:ZP_GOBBO_TIMING_TEXT','',true)
    end
    SyncInlineAnchors()
    reaper.GetSetMediaItemInfo_String(item,'P_EXT:ZP_GOBBO_ANCHORS',ZP_TESTO.serialize_anchors(inline_edit.anchors),true)
    if inline_edit.mode=='timed_new' or inline_edit.timed_existing and inline_edit.recalculate~=false then
        local _,_,pause_seconds=TimedTextDuration(inline_edit.text,inline_edit.timed_wpm)
        local weight=pause_seconds*(inline_edit.timed_wpm or 120)/60
        if inline_edit.timed_existing and ZP_TESTO.same_words(inline_edit.text,inline_edit.original) and inline_edit.timed_wpm==inline_edit.original_wpm then
            local _,_,old_seconds=TimedTextDuration(inline_edit.original,inline_edit.timed_wpm)
            weight=inline_edit.pause_weight or old_seconds*inline_edit.timed_wpm/60
        end
        reaper.GetSetMediaItemInfo_String(item,'P_EXT:ZP_TIMED_SCROLL_PAUSE_WEIGHT',tostring(weight),true)
    end
    reaper.GetSetMediaItemInfo_String(item,'P_EXT:RythmoBand_HIGHLIGHT',InlineHighlightRaw(),true)
    if inline_edit.timed_existing and inline_edit.recalculate~=false and (inline_edit.text~=inline_edit.original or inline_edit.timed_wpm~=inline_edit.original_wpm) then
        reaper.SetMediaItemInfo_Value(item,'D_LENGTH',InlineEstimatedDuration(inline_edit.text,inline_edit.timed_wpm))
        reaper.GetSetMediaItemInfo_String(item,'P_EXT:ZP_TIMED_SCROLL_WPM',tostring(inline_edit.timed_wpm),true)
    end
    reaper.UpdateItemInProject(item)
end
function InlinePaste()
    local text,err=ZP_TESTO.clipboard(reaper,reaper.GetOS())
    if text then if text~='' then InlineInsertText(text) end
    elseif inline_clipboard and inline_clipboard~='' then InlineInsertText(ZP_TESTO.normalize(inline_clipboard))
    else reaper.ShowMessageBox(T('Impossibile leggere gli appunti.')..'\n'..T(err),'ZP Studio Suite',0) end
end
function InlineLoadFile()
    local ok,path=reaper.GetUserFileNameForRead('','ZP - '..T('Carica file… (.docx, .odt, .rtf, .txt, .xlsx)'), '')
    if not ok then return end
    local text,terms
    if path:lower():match('%.xlsx$') then
        -- Copione Excel con i tempi: una battuta per riga, PERSONAGGIO: testo.
        local xlsx=dofile(SCRIPT_DIR..'ZP_Xlsx_Copione.lua')
        local cues,info=xlsx.read(function(name) return ZP_TESTO.zip_member(path,name,reaper.GetOS()) end,{choose=xlsx.menu})
        if cues then text,terms=xlsx.to_text(cues),{} elseif info then terms=info else return end
    else
        text,terms=ZP_TESTO.read_file(path,reaper.GetOS())
    end
    if not text then reaper.ShowMessageBox(T(tostring(terms)),T('Importazione copione'),0); return end
    InitInlineCopione()
    InlineInsertText(text)
    inline_edit.imported_highlights=terms
end
function InlineTransform(fn,selection_only)
    local a,b=InlineSelectionRange()
    if selection_only and not a then return end
    a,b=a or 1,b or (#inline_edit.text+1)
    local transformed=fn(inline_edit.text:sub(a,b-1))
    InlineSetSelection(a,b)
    InlineInsertText(transformed)
    InlineSetSelection(a,a+#transformed)
end
function InlineToggleHighlight()
    if not inline_edit then return end
    InitInlineCopione()
    if InlineSelectedText()=='' then InlineSelectWordAtCursor() end
    local term=trim(InlineSelectedText():gsub('[\r\n]+',' '))
    if term=='' then return end
    InlinePushUndo()
    local terms=inline_edit.highlights; local found=false
    for i=#terms,1,-1 do if ZP_TESTO.lower(terms[i])==ZP_TESTO.lower(term) then table.remove(terms,i); found=true end end
    if not found then terms[#terms+1]=term end
end
function DrawInlineSubtitleEditor()
    if not inline_edit then return end
    InitInlineCopione()
    SyncInlineAnchors()
    local action=ZP_EDITOR.draw(inline_edit,{
        ui=ZP_UI,T=T,font=default_font,lines=InlineVisualLines,stats=ZP_TESTO.stats,
        duration=(inline_edit.timed_existing or inline_edit.mode=='timed_new') and InlineEstimatedDuration or nil,
        selection=InlineSelectionRange,cursor_point=InlineCursorFromPoint,cursor_at=InlineCursorAtPoint,
        set_selection=InlineSetSelection,select_word=InlineSelectWordAtCursor,time=reaper.time_precise,
        pressed=(gfx.mouse_cap&1)==1 and not mouse_was_down,
        released=(gfx.mouse_cap&1)==0 and mouse_was_down
    })
    if action=='paste' then InlinePaste()
    elseif action=='load' then InlineLoadFile()
    elseif action=='clean' then InlineTransform(function(s) return ZP_TESTO.normalize(s,true) end)
    elseif action=='join' then InlineTransform(ZP_TESTO.join_lines)
    elseif action=='highlight' then InlineToggleHighlight()
    elseif action=='slower' then inline_edit.timed_wpm=math.max(40,(inline_edit.timed_wpm or 120)-10)
    elseif action=='faster' then inline_edit.timed_wpm=math.min(240,(inline_edit.timed_wpm or 120)+10)
    elseif action=='tools' then
        gfx.x,gfx.y=gfx.mouse_x,gfx.mouse_y
        local choice=gfx.showmenu(table.concat({T('Separa frasi per respiro'),T('Selezione: minuscolo'),T('Selezione: MAIUSCOLO'),T('Selezione: iniziale maiuscola'),T('Annulla modifica (Ctrl+Z)'),(inline_edit.import_highlights and '!' or '')..T('Importa grassetto/evidenziato')},'|'))
        if choice==1 then InlineTransform(ZP_TESTO.breathe)
        elseif choice==2 then InlineTransform(ZP_TESTO.lower,true)
        elseif choice==3 then InlineTransform(ZP_TESTO.upper,true)
        elseif choice==4 then InlineTransform(ZP_TESTO.sentence_case,true)
        elseif choice==5 then InlineRestoreUndo()
        elseif choice==6 then inline_edit.import_highlights=not inline_edit.import_highlights end
    elseif action=='save' then SaveInlineSubtitleEdit()
    elseif action=='cancel' then inline_edit=nil end
end

local gobbo_word_selection=nil
local gobbo_word_right_down=false
function GobboPickWord(item,x,y,w,h,px,py)
    if not item or px<x or px>x+w or py<y or py>y+h then return nil end
    local plan=item.word_plan or item.reading_plan
    if not plan then return nil end
    local offset
    local row=math.max(1,math.min(#plan.rows,math.floor((py-y)/(master_font_size*1.55))+1))
    local info=plan.rows[row]
    if info and info.first then offset=ZP_TESTO.cursor_in_words(item.notes,info.first,info.last,px-x,gfx.measurestr) end
    if not offset then return nil end
    local event=ZP_TESTO.word_event(plan,offset)
    if not event then return nil end
    local _,guid=reaper.GetSetMediaItemInfo_String(item.item,'GUID','',false)
    return {item=item.item,guid=guid,text=item.notes,first=event.first,last=event.last,x=x,y=y,w=w,h=h}
end
function GobboSelectWord(item,x,y,w,h,px,py)
    local selected=GobboPickWord(item,x,y,w,h,px,py)
    if selected then gobbo_word_selection=selected end
    return selected
end
function GobboWordSelectionValid()
    local s=gobbo_word_selection
    if not s or not reaper.ValidatePtr2(0,s.item,'MediaItem*') then return false end
    local _,guid=reaper.GetSetMediaItemInfo_String(s.item,'GUID','',false)
    local _,text=reaper.GetSetMediaItemInfo_String(s.item,'P_NOTES','',false)
    text=(text or ''):gsub('\r\n','\n'):gsub('\r','\n')
    return guid==s.guid and text==s.text
end
function GobboEditSelectedWord()
    if not GobboWordSelectionValid() then
        gobbo_word_selection=nil
        reaper.ShowMessageBox(T('Il testo è cambiato: seleziona di nuovo la parola.'),T('Gobbo'),0)
        return
    end
    local s=gobbo_word_selection
    StartInlineSubtitleEdit(s.item,s.x,s.y,s.w,s.h)
    InlineSetCursor(s.first)
    inline_edit.center_cursor=true;inline_edit.opening_mouse_down=true
end
function GobboSplitSelectedWord()
    if not GobboWordSelectionValid() then
        gobbo_word_selection=nil
        reaper.ShowMessageBox(T('Il testo è cambiato: seleziona di nuovo la parola.'),T('Gobbo'),0)
        return
    end
    local s=gobbo_word_selection
    local right,result=ZP_TESTO.split_timed_item(reaper,s.item,s.first,s.text,UpdateSubtitleItemName)
    if not right then reaper.ShowMessageBox(T(result),T('Dividi il copione'),0);return end
    gobbo_word_selection=nil
    UpdateItems()
end
function HandleSubtitleEditDoubleClick(item,x,y,w,h)
    if inline_edit or search_panel_open then return false end
    local down=(gfx.mouse_cap&1)~=0
    if down and not mouse_was_down and gfx.mouse_x>=x and gfx.mouse_x<=x+w and gfx.mouse_y>=y and gfx.mouse_y<=y+h then
        local now=reaper.time_precise()
        if last_edit_click_item==item.item and now-last_edit_click_time<=0.35 then
            last_edit_click_item=nil;last_edit_click_time=0
            return GobboSelectWord(item,x,y,w,h,gfx.mouse_x,gfx.mouse_y)~=nil
        end
        last_edit_click_item=item.item;last_edit_click_time=now
    end
    return false
end
-- Battute da unire: quelle selezionate in timeline e quella che segue l'item indicato sulla stessa traccia.
function GobboMergeCandidates(item)
    local selected={}
    for i=0,reaper.CountSelectedMediaItems(0)-1 do
        local it=reaper.GetSelectedMediaItem(0,i)
        if reaper.GetMediaItemNumTakes(it)==0 then selected[#selected+1]=it end
    end
    local track=reaper.GetMediaItem_Track(item)
    local pos=reaper.GetMediaItemInfo_Value(item,'D_POSITION')
    local following,best
    for i=0,reaper.CountTrackMediaItems(track)-1 do
        local it=reaper.GetTrackMediaItem(track,i)
        local p=reaper.GetMediaItemInfo_Value(it,'D_POSITION')
        if it~=item and reaper.GetMediaItemNumTakes(it)==0 and p>pos and (not best or p<best) then best=p;following=it end
    end
    return selected,following
end
function GobboMergeBattute(list)
    local kept,info=ZP_TESTO.merge_text_items(reaper,list,UpdateSubtitleItemName)
    if not kept then reaper.ShowMessageBox(T(info),T('Unisci battute'),0);return end
    gobbo_word_selection=nil
    UpdateItems()
end
function HandleGobboWordAnchorMenu(item,x,y,w,h)
    if inline_edit or search_panel_open or (gfx.mouse_cap&2)==0 or gobbo_word_right_down then return end
    if gfx.mouse_x<x or gfx.mouse_x>x+w or gfx.mouse_y<y or gfx.mouse_y>y+h then return end
    gobbo_word_right_down=true
    -- Dopo il doppio clic il punto rimane quello scelto, anche se il testo continua a scorrere.
    local s=gobbo_word_selection
    if not s or s.item~=item.item or not GobboWordSelectionValid() then
        s=GobboSelectWord(item,x,y,w,h,gfx.mouse_x,gfx.mouse_y)
    end
    if not s then return end
    local target=reaper.GetCursorPosition()
    local _,sync_key=reaper.GetSetMediaItemInfo_String(item.item,'P_EXT:ZP_SYNC_KEY','',false)
    local can_split=item.timed_scroll and sync_key=='' and reaper.GetMediaItemNumTakes(item.item)==0
    gfx.x,gfx.y=gfx.mouse_x,gfx.mouse_y
    local menu=T('Edita testo…')..'|'..(item.timed_scroll and '' or '#')..T('Aggiungi promemoria su questa parola…')..'|'..(can_split and '' or '#')..T('Dividi prima di questa parola')
    local merge_selected,merge_next=GobboMergeCandidates(item.item)
    menu=menu..'||'..(merge_next and '' or '#')..T('Unisci con la battuta successiva')..'|'..(#merge_selected>=2 and '' or '#')..T('Unisci le battute selezionate in timeline')
    if #(item.anchors or {})>0 then menu=menu..'|'..T('Scollega i marker di questo testo') end
    local choice=gfx.showmenu(menu)
    if choice==1 then GobboEditSelectedWord()
    elseif choice==2 and item.timed_scroll then
        if GobboWordSelectionValid() then AddGobboWordAnchor(item,s.first,target) end
    elseif choice==3 and can_split then GobboSplitSelectedWord()
    elseif choice==4 and merge_next then GobboMergeBattute({item.item,merge_next})
    elseif choice==5 and #merge_selected>=2 then GobboMergeBattute(merge_selected)
    elseif choice==6 and #(item.anchors or {})>0 then
        reaper.Undo_BeginBlock()
        reaper.GetSetMediaItemInfo_String(item.item,'P_EXT:ZP_GOBBO_ANCHORS','',true)
        reaper.UpdateItemInProject(item.item)
        reaper.Undo_EndBlock('ZP Gobbo: scollega marker del testo',-1)
        reaper.UpdateArrange();UpdateItems()
    end
end
function DrawGobboWordSelection(item,x,y,line_h)
    local s=gobbo_word_selection
    if not s or s.item~=item.item or s.text~=item.notes then return end
    local event=ZP_TESTO.word_event(item.word_plan or item.reading_plan,s.first)
    if not event then return end
    local row=math.floor(event.row)
    local py=y+row*line_h
    local words={};for word in (item.lines[row+1] or ''):gmatch('%S+') do words[#words+1]=word end
    local col=math.floor((event.row-row)*#words+0.5)
    local prefix=col>0 and table.concat(words,' ',1,col)..' ' or ''
    local px=x+gfx.measurestr(prefix)
    local width=gfx.measurestr(item.notes:sub(event.first,event.last))
    if py>=0 and py<gfx.h then
        gfx.set(0.25,0.65,1,0.28);gfx.rect(px-2,py-2,width+4,line_h,1)
        gfx.set(0.35,0.75,1,1);gfx.rect(px-2,py-2,2,line_h,1)
    end
end

function HandleStudioItemClick(item, x, y, w, h)
    if not item or not studio_edit_mode or inline_edit or search_panel_open then return end
    local mx, my = gfx.mouse_x, gfx.mouse_y
    local hover = mx >= x and mx <= x + w and my >= y and my <= y + h
    local mouse_down = (gfx.mouse_cap & 1) == 1
    if hover and mouse_down and not mouse_was_down then
        -- Il clic seleziona; la navigazione esplicita resta a ricerca, rotella e scrollbar.
        reaper.Main_OnCommand(40289, 0) -- Unselect all items
        reaper.SetMediaItemSelected(item, true)
        reaper.UpdateArrange()
    end
end

function AddGobboWordAnchor(item,offset,target_pos)
    if not item or not item.timed_scroll or not item.reading_plan then return end
    local event
    for _,e in ipairs(item.reading_plan.events) do
        if not e.pause and offset>=e.first and offset<=e.last+1 then event=e;break end
    end
    if not event then return end
    local markers=ZP_TESTO.timeline_markers(reaper)
    for _,a in ipairs(item.anchors or {}) do
        if a.offset==event.first and markers[a.guid] then
            reaper.ShowMessageBox(T('Questa parola ha già un promemoria. Puoi spostare il marker liberamente nella timeline.'),T('Promemoria del copione'),0)
            return
        end
    end
    local anchors={};for _,a in ipairs(item.anchors or {}) do anchors[#anchors+1]={guid=a.guid,offset=a.offset} end
    local word=(item.notes or ''):sub(event.first,event.last)
    local ok,label=reaper.GetUserInputs(T('Promemoria del copione'),1,T('Nome marker:')..',extrawidth=300',T('Gobbo')..' · '..word:gsub(',',' '))
    if not ok then return end
    reaper.Undo_BeginBlock()
    local id=reaper.AddProjectMarker2(0,false,target_pos,0,label,-1,0)
    local guid
    if id and id>=0 then
        for key,m in pairs(ZP_TESTO.timeline_markers(reaper)) do if m.id==id then guid=key;break end end
    end
    if not guid then
        if id and id>=0 then reaper.DeleteProjectMarker(0,id,false) end
        reaper.Undo_EndBlock('ZP Gobbo: marker non creato',-1)
        reaper.ShowMessageBox(T('Impossibile collegare il marker alla parola.'),T('Promemoria del copione'),0)
        return
    end
    anchors[#anchors+1]={guid=guid,offset=event.first}
    reaper.GetSetMediaItemInfo_String(item.item,'P_EXT:ZP_GOBBO_ANCHORS',ZP_TESTO.serialize_anchors(anchors),true)
    reaper.UpdateItemInProject(item.item)
    reaper.Undo_EndBlock('ZP Gobbo: promemoria della parola',-1)
    reaper.UpdateArrange();UpdateItems()
end
function DrawGobboWordAnchors(item,x,y,line_h)
    local plan=item.reading_plan
    if not plan then return end
    gfx.setfont(1,default_font,master_font_size)
    for _,pin in ipairs(plan.reminders or {}) do
        for _,event in ipairs(plan.events) do
            if not event.pause and pin.offset==event.first then
                local row=math.floor(event.row)
                local py=y+row*line_h
                if py>=0 and py<gfx.h then
                    local words={};for word in (item.lines[row+1] or ''):gmatch('%S+') do words[#words+1]=word end
                    local col=math.floor((event.row-row)*#words+0.5)
                    local prefix=col>0 and table.concat(words,' ',1,col)..' ' or ''
                    local px=x+gfx.measurestr(prefix)
                    local width=gfx.measurestr((item.notes or ''):sub(event.first,event.last))
                    gfx.set(1,0.69,0.20,0.95);gfx.rect(px,py+line_h-4,math.max(3,width),2,1)
                    gfx.circle(px,py-3,3,true,true)
                end
                break
            end
        end
    end
end

function DrawCharacterTags(item,x,y,end_y,is_active)
    local note=(item.person_notes or {})[1]
    if not note or y<0 or y>gfx.h-24 then return end
    local bw=speaker_shoulder_w-8
    gfx.set(note.r,note.g,note.b,is_active and 0.30 or 0.15)
    ZP_UI.fill_round(x-speaker_shoulder_w,y,bw,24,4)
    gfx.set(note.r,note.g,note.b,is_active and 1 or 0.55)
    gfx.rect(x-speaker_shoulder_w,y,3,24,1)
    gfx.setfont(3,'Arial',12,'b')
    local label=trim(note.role or note.text or '')
    if gfx.measurestr(label)>bw-14 then
        while #label>0 and gfx.measurestr(label..'…')>bw-14 do label=label:sub(1,Utf8PrevCursor(label,#label+1)-1) end
        label=label..'…'
    end
    SetThemeColor('text',is_active and 1 or 0.7)
    gfx.x,gfx.y=x-speaker_shoulder_w+8,y+5; gfx.drawstr(label)
end

function DrawCharacterUnderline(item, x, y, w, is_active)
    local notes = item.person_notes or {}
    local note = notes[1]
    if not note then return end
    local alpha = is_active and 0.90 or 0.44
    local underline_y = y - 3
    gfx.set(note.r, note.g, note.b, alpha)
    gfx.rect(x, underline_y, math.max(32, w), 3, 1)
    gfx.set(note.r, note.g, note.b, alpha * 0.30)
    gfx.rect(x, underline_y + 3, math.max(32, w), 2, 1)
end

-- =============================================
-- Calcola un layout continuo dall'alto verso il basso (Astraendo dal tempo)
-- Ogni battuta viene piazzata una sotto l'altra come un paragrafo di Word.
-- Memorizziamo l'altezza Y assoluta di dove inizia e dove finisce ogni riga.
function RecalculateDocumentLayout()
    local notes_w = (not panels_hidden and notes_panel_open) and NOTES_PANEL_W or 0
    local spw = not panels_hidden and (sidebar_collapsed and 30 or side_panel_w) or 0
    local w = gfx.w - spw - notes_w
    if w < 100 then w = 600 end
	    
    local available_w = math.max(200, w - speaker_shoulder_w - (document_margin_x * 2))
    gfx.setfont(1, default_font, master_font_size)
    local line_h = master_font_size * 1.55
    local spacing_between_items = master_font_size * 0.45
    
    local top_document_pad = math.max(master_font_size * 2.0, gfx.h * reading_point)
    local bottom_document_pad = math.max(master_font_size * 3.0, gfx.h * (1.0 - reading_point) * 0.75)
    local current_y = top_document_pad
    local last_region_name = nil
    cached_headers = {}
    
    for _, item in ipairs(cached_items) do
        local region = FindRegionForPosition(item.pos)
        local region_name = region and region.name or nil
        if region_name and region_name ~= last_region_name then
            local header_h = master_font_size * 2.3
            table.insert(cached_headers, {y=current_y + (master_font_size * 0.35), text=region_name})
            current_y = current_y + header_h
            last_region_name = region_name
        end

        item.lines = WrapText(item.notes or "", available_w)
        item.reading_plan=item.timed_scroll and ZP_TESTO.reading_plan(item.notes,item.lines,item.pause_weight,item.len,item.timed_wpm,item.timing) or nil
        if item.reading_plan then item.reading_plan.reminders=ZP_TESTO.reminder_markers(item.reading_plan,item.anchors,item.anchor_markers or {}) end
        item.word_plan=item.reading_plan or ZP_TESTO.reading_plan(item.notes,item.lines)
        item.total_words = CountWords(item.lines)
        
        -- Start Y del blocco di testo nel documento virtuale
        item.doc_start_y = current_y
        item.pixel_height = #item.lines * line_h
        
        -- Aggiorna cursore per l'item successivo
        current_y = current_y + item.pixel_height + spacing_between_items
        
        -- End Y del blocco
        item.doc_end_y = current_y
    end
    
    document_total_h = current_y + bottom_document_pad
end

function RangesOverlap(a_start, a_end, b_start, b_end)
    return a_start <= b_end and b_start <= a_end
end

function NoteTouchesTextItem(note, item)
    local note_start = note.pos - NOTE_HOT_MARGIN
    local note_end = note.pos + note.len + NOTE_HOT_MARGIN
    return RangesOverlap(note_start, note_end, item.pos, item.pos + item.len)
end

function CollectCharacterNotesForRange(pos, len)
    local matches = {}
    for _, note in ipairs(cached_character_notes) do
        if NoteTouchesTextItem(note, {pos=pos, len=len}) then
            note.row = character_lane_by_key[note.key] or (max_character_rows + 1)
            table.insert(matches, note)
        end
    end
    table.sort(matches, function(a, b)
        if (a.row or 999) ~= (b.row or 999) then return (a.row or 999) < (b.row or 999) end
        if (a.track_order or 999999) ~= (b.track_order or 999999) then return (a.track_order or 999999) < (b.track_order or 999999) end
        if a.pos == b.pos then return a.text < b.text end
        return a.pos < b.pos
    end)
    if #matches == 0 then return matches end
    -- Regola dura: sulla stessa battuta vince sempre un solo personaggio.
    -- Se c'e' sovrapposizione vera, sara' il tecnico a decidere e annotarla.
    return {matches[1]}
end

function CollectCharacterNotes()
    local notes = {}
    for t=0, reaper.CountTracks(0)-1 do
        local track = reaper.GetTrack(0, t)
        if IsCharacterNoteTrack(track) then
            local role_name = CharacterNameFromTrack(track)
            local role_key = NormalizeName(role_name)
            local track_order = FindRoleTrackOrder(t, role_key)
            local color_track = PairedVoiceTrack(track) or track
            local track_color = reaper.GetTrackColor(color_track)
            if track_color == 0 then track_color = reaper.GetTrackColor(track) end
            for i=0, reaper.CountTrackMediaItems(track)-1 do
                local item = reaper.GetTrackMediaItem(track, i)
                local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local _, text = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
                text = trim(text)
                if text == "" then
                    local _, item_name = reaper.GetSetMediaItemInfo_String(item, "P_NAME", "", false)
                    text = trim(item_name)
                end
                if text == "" then text = role_name end
                if text ~= "" then
                    local color = track_color
                    if color == 0 then color = NativeColor(COLOR_NOTES) end
                    local r, g, b = ColorToRGB(color, COLOR_NOTES)
                    table.insert(notes, { item=item, pos=pos, len=len, text=role_name, note_text=text, role=role_name, key=role_key, track_order=track_order, note_track_order=t, r=r, g=g, b=b, color=color })
                end
            end
        end
    end
    table.sort(notes, function(a, b) return a.pos < b.pos end)
    return notes
end

function CollectRegions()
    local regions = {}
    local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
    local total = num_markers + num_regions
    for i=0, total-1 do
        local ok, is_region, pos, rgn_end, name = reaper.EnumProjectMarkers(i)
        if ok and is_region and name and name ~= "" and rgn_end > pos then
            table.insert(regions, {pos=pos, end_pos=rgn_end, name=name})
        end
    end
    table.sort(regions, function(a, b) return a.pos < b.pos end)
    return regions
end

function FindRegionForPosition(pos)
    for _, region in ipairs(cached_regions) do
        if pos >= region.pos and pos < region.end_pos then return region end
    end
    return nil
end

function CollectVideoItems()
    local videos = {}
    local track = FindTrackByName("VIDEO")
    if track then
        for i=0, reaper.CountTrackMediaItems(track)-1 do
            local item = reaper.GetTrackMediaItem(track, i)
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            if len > 0 then table.insert(videos, {pos=pos, len=len}) end
        end
        table.sort(videos, function(a, b) return a.pos < b.pos end)
    end
    return videos
end

-- ---------------------------------------------------------------------------
-- Note agganciate alla battuta.
-- Ogni nota ricorda nel proprio item a quale battuta appartiene:
--   P_EXT:ZP_NOTE_LINK      GUID dell'item della battuta
--   P_EXT:ZP_NOTE_LINK_OFF  distanza della nota dall'inizio della battuta (secondi)
--   P_EXT:ZP_NOTE_LINK_POS  inizio della battuta all'ultimo controllo
-- Se la battuta si sposta la nota la segue; se la battuta viene cancellata la nota se ne va.
-- Le correzioni non creano punti di Undo propri: l'Undo dello spostamento o della
-- cancellazione della battuta riporta indietro anche la nota.

function CollectAllTextItems()
    local list, by_guid = {}, {}
    for _, entry in ipairs(CollectTextFlowTracks()) do
        for i = 0, reaper.CountTrackMediaItems(entry.track) - 1 do
            local item = reaper.GetTrackMediaItem(entry.track, i)
            local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
            local rec = {
                item = item, guid = guid,
                pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION"),
                len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
            }
            list[#list + 1] = rec
            if guid and guid ~= "" then by_guid[guid] = rec end
        end
    end
    return list, by_guid
end

-- La battuta che contiene la posizione; altrimenti, se max_distance > 0, la piu' vicina entro quel limite.
function NoteTargetItem(list, pos, max_distance)
    local best, best_distance
    for _, rec in ipairs(list) do
        local finish = rec.pos + rec.len
        if pos >= rec.pos - NOTE_LINK_EPSILON and pos <= finish + NOTE_LINK_EPSILON then return rec end
        local distance = pos < rec.pos and (rec.pos - pos) or (pos - finish)
        if not best_distance or distance < best_distance then best, best_distance = rec, distance end
    end
    if best and (max_distance or 0) > 0 and best_distance <= max_distance then return best end
    return nil
end

function SetNoteLink(note_item, rec, note_pos)
    local guid = rec and rec.guid or ""
    reaper.GetSetMediaItemInfo_String(note_item, "P_EXT:ZP_NOTE_LINK", guid, true)
    reaper.GetSetMediaItemInfo_String(note_item, "P_EXT:ZP_NOTE_LINK_OFF", rec and string.format("%.9f", note_pos - rec.pos) or "", true)
    reaper.GetSetMediaItemInfo_String(note_item, "P_EXT:ZP_NOTE_LINK_POS", rec and string.format("%.9f", rec.pos) or "", true)
end

function SyncLinkedNotes()
    local track = FindTrackByName(notes_track_name)
    if not track then return end
    local count = reaper.CountTrackMediaItems(track)
    if count == 0 then return end
    local list, by_guid = CollectAllTextItems()
    local project_guids = nil
    local changed, orphans = false, {}
    for i = 0, count - 1 do
        local note_item = reaper.GetTrackMediaItem(track, i)
        local _, text = reaper.GetSetMediaItemInfo_String(note_item, "P_NOTES", "", false)
        if trim(text) ~= "" then
            local pos = reaper.GetMediaItemInfo_Value(note_item, "D_POSITION")
            local _, guid = reaper.GetSetMediaItemInfo_String(note_item, "P_EXT:ZP_NOTE_LINK", "", false)
            if guid == "" then
                -- nota ancora libera: si aggancia alla battuta che ha sotto, o alla piu' vicina
                local rec = NoteTargetItem(list, pos, NOTE_LINK_MAX_DISTANCE)
                if rec then SetNoteLink(note_item, rec, pos); changed = true end
            else
                local rec = by_guid[guid]
                local _, off_raw = reaper.GetSetMediaItemInfo_String(note_item, "P_EXT:ZP_NOTE_LINK_OFF", "", false)
                local _, known_raw = reaper.GetSetMediaItemInfo_String(note_item, "P_EXT:ZP_NOTE_LINK_POS", "", false)
                local off, known = tonumber(off_raw) or 0, tonumber(known_raw)
                if not rec then
                    if not project_guids then
                        project_guids = {}
                        for k = 0, reaper.CountMediaItems(0) - 1 do
                            local _, g = reaper.GetSetMediaItemInfo_String(reaper.GetMediaItem(0, k), "GUID", "", false)
                            project_guids[g] = true
                        end
                    end
                    if not project_guids[guid] then
                        -- la battuta non esiste piu'. Se nello stesso punto ce n'e' un'altra (item incollato,
                        -- unito o ricreato) la nota passa a quella; altrimenti se ne va con la battuta.
                        local under = NoteTargetItem(list, pos, 0)
                        if under then SetNoteLink(note_item, under, pos) else orphans[#orphans + 1] = note_item end
                        changed = true
                    end
                    -- se l'item esiste ancora ma su una traccia che non e' piu' un flusso di testo, la nota resta dov'e'
                elseif known and math.abs(rec.pos - known) > NOTE_LINK_EPSILON then
                    -- battuta spostata: la nota la segue
                    reaper.SetMediaItemInfo_Value(note_item, "D_POSITION", math.max(0, rec.pos + off))
                    reaper.GetSetMediaItemInfo_String(note_item, "P_EXT:ZP_NOTE_LINK_POS", string.format("%.9f", rec.pos), true)
                    changed = true
                elseif not known or math.abs(pos - (rec.pos + off)) > NOTE_LINK_EPSILON then
                    -- nota spostata a mano: si aggancia alla battuta dove e' stata messa
                    SetNoteLink(note_item, NoteTargetItem(list, pos, NOTE_LINK_MAX_DISTANCE), pos)
                    changed = true
                elseif pos > rec.pos + rec.len + NOTE_LINK_EPSILON then
                    -- battuta divisa o accorciata: la nota passa alla parte che ora la contiene
                    local under = NoteTargetItem(list, pos, 0)
                    if under and under ~= rec then SetNoteLink(note_item, under, pos); changed = true end
                end
            end
        end
    end
    for _, note_item in ipairs(orphans) do
        if reaper.ValidatePtr(note_item, "MediaItem*") then reaper.DeleteTrackMediaItem(track, note_item) end
    end
    if changed then
        reaper.MarkProjectDirty(0)
        reaper.UpdateArrange()
    end
end

function CollectNotes()
    local track = FindTrackByName(notes_track_name)
    local notes = {}
    if track then
        for i=0, reaper.CountTrackMediaItems(track)-1 do
            local item = reaper.GetTrackMediaItem(track, i)
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local _, text = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
            text = trim(text)
            if text ~= "" then
                local color = GetDisplayedItemColor(item, COLOR_NOTES)
                local r, g, b = ColorToRGB(color, COLOR_NOTES)
                local _, done = reaper.GetSetMediaItemInfo_String(item, "P_EXT:ZP_NOTE_DONE", "", false)
                table.insert(notes, { item=item, pos=pos, len=len, text=text, key=NormalizeName(text), r=r, g=g, b=b, color=color, done = done == "1" })
            end
        end
        table.sort(notes, function(a, b) return a.pos < b.pos end)
    end
    return notes
end

-- =============================================
function UpdateItems()
    local gobbo_markers=ZP_TESTO.timeline_markers(reaper)
    local track = GetRythmoTrack()
    cached_regions = CollectRegions()
    cached_video_items = CollectVideoItems()
    SyncLinkedNotes()
    cached_notes = CollectNotes()
    cached_character_notes = CollectCharacterNotes()
    BuildCharacterLanes()
    cached_items = {}
    local flow_tracks = {}
    if selected_text_track_guid == READ_ALL then
        for _, entry in ipairs(CollectTextFlowTracks()) do flow_tracks[#flow_tracks + 1] = entry.track end
    elseif track then
        flow_tracks[1] = track
    end
    for flow_index, track in ipairs(flow_tracks) do
        for i=0, reaper.CountTrackMediaItems(track)-1 do
            local item = reaper.GetTrackMediaItem(track, i)
            local pos   = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local len   = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local person_notes = CollectCharacterNotesForRange(pos, len)
            local has_note = #person_notes > 0

            local color = GetDisplayedItemColor(item, COLOR_SUBS)
            local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
            notes=(notes or ''):gsub('\r\n','\n'):gsub('\r','\n')
            local _, timing_raw=reaper.GetSetMediaItemInfo_String(item,'P_EXT:ZP_GOBBO_TIMING','',false)
            local _, timing_text=reaper.GetSetMediaItemInfo_String(item,'P_EXT:ZP_GOBBO_TIMING_TEXT','',false)
            local timing=timing_text==notes and ZP_TESTO.parse_reading_timing(timing_raw) or nil

            local _, highlight_raw = reaper.GetSetMediaItemInfo_String(item, "P_EXT:RythmoBand_HIGHLIGHT", "", false)
            local _, timed_scroll = reaper.GetSetMediaItemInfo_String(item, "P_EXT:ZP_TIMED_SCROLL", "", false)
            local _, pause_weight = reaper.GetSetMediaItemInfo_String(item, "P_EXT:ZP_TIMED_SCROLL_PAUSE_WEIGHT", "", false)
            local _, timed_wpm = reaper.GetSetMediaItemInfo_String(item, "P_EXT:ZP_TIMED_SCROLL_WPM", "", false)
            local _, anchor_raw = reaper.GetSetMediaItemInfo_String(item, "P_EXT:ZP_GOBBO_ANCHORS", "", false)
            
            local r, g, b = ColorToRGB(color, COLOR_SUBS)
            
            table.insert(cached_items, {item=item, pos=pos, len=len, notes=notes, highlights=ParseHighlightTerms(highlight_raw), timed_scroll=timed_scroll == "1", pause_weight=tonumber(pause_weight) or 4, timed_wpm=tonumber(timed_wpm) or 120, timing=timing, anchors=ZP_TESTO.parse_anchors(anchor_raw), anchor_markers=gobbo_markers, has_note=has_note, person_notes=person_notes, r=r, g=g, b=b, flow=flow_index, track_name=GetTrackName(track), source_file=SyncSourceFileName(item)})
        end
    end
    -- Ordine cronologico rigidissimo! È un copione. A parita' di tempo, l'ordine delle tracce.
    table.sort(cached_items, function(a, b)
        if a.pos ~= b.pos then return a.pos < b.pos end
        return a.flow < b.flow
    end)
    
    RecalculateDocumentLayout()
    if search_panel_open then search_results_dirty=true; search_results_deadline=reaper.time_precise()+0.15 end
end

-- =============================================
function DrawButton(x,y,w,h,label,hover_r,hover_g,hover_b,active)
    if sidebar_clip_top and (y<sidebar_clip_top or y+h>sidebar_clip_bottom) then return false end
    if inline_edit then return false end
    return ZP_UI.draw_button({x=x,y=y,w=w,h=h},label,active,true,(gfx.mouse_cap&1)==0 and mouse_was_down,'neutral')
end

-- Help: apre la guida della suite sulla sezione di questa finestra (via ZP_UI, che
-- usa un indirizzo file:// codificato: con il percorso nudo macOS non apre il #segnalibro).
local function zp_open_help_section(anchor)
    local ok, ui = pcall(dofile, SCRIPT_DIR .. "ZP_UI.lua")
    if ok and type(ui) == "table" and ui.open_help then ui.open_help(anchor) return true end
    return false
end

function OpenSuiteHelp()
    if zp_open_help_section("tool-02") then return end
    local help_path = SCRIPT_DIR .. "help/index.html"
    local f = io.open(help_path, "r")
    if f then
        f:close()
    else
        reaper.ShowMessageBox(T("Help non trovato:\n\n") .. help_path, "ZP Studio Suite", 0)
        return
    end

    local os_name = reaper.GetOS and reaper.GetOS() or ""
    if reaper.CF_ShellExecute then
        reaper.CF_ShellExecute(help_path)
    elseif os_name:match("Win") then
        os.execute('start "" "' .. help_path:gsub('"', '\\"') .. '"')
    elseif os_name:match("OSX") or os_name:match("macOS") then
        os.execute("open " .. string.format("%q", help_path) .. " &")
    else
        os.execute("xdg-open " .. string.format("%q", help_path) .. " >/dev/null 2>&1 &")
    end
end

function GobboAccessibleSpeak(text)
    text = trim((text or ""):gsub("[\r\n]+", " "):gsub("%s+", " "))
    if text == "" then return end
    if type(reaper.osara_outputMessage) == "function" then
        reaper.osara_outputMessage(text)
    else
        reaper.ShowMessageBox(text, "ZP Studio Suite - " .. T("Gobbo"), 0)
    end
end

function GobboAccessibleStatus()
    local lines = {
        T("Stato gobbo."),
        show_timecode and T("Timecode visibile.") or T("Timecode nascosto."),
        theme_mode == "dark" and T("Tema scuro.") or (theme_mode == "light" and T("Tema chiaro.") or T("Tema medio.")),
        full_contrast and T("Contrasto pieno.") or T("Contrasto sfumato."),
        string.format(T("Flusso testi %s."), CurrentTextFlowLabel()),
        word_follow and T("Parola per parola attiva.") or T("Parola per parola spenta."),
        fixed_block_mode and T("Scorrimento continuo spento: testo a scatti, una battuta alla volta.") or T("Scorrimento continuo attivo."),
        countdown_alert and T("Conto alla rovescia attivo.") or T("Conto alla rovescia spento."),
        beep.on and T("Bip attivo.") or T("Bip spento."),
        notes_panel_open and T("Pannello note aperto.") or T("Pannello note chiuso."),
        string.format(T("Corpo testo %s."), tostring(master_font_size))
    }
    return table.concat(lines, " ")
end

function OpenGobboAccessibleMenu()
    local prompt = table.concat({
        T("1 Stato"),
        T("2 Mostra/Nascondi TC"),
        T("3 Flusso precedente"),
        T("4 Flusso successivo"),
        T("5 Parola per parola si/no"),
        T("6 Scorrimento continuo si/no"),
        T("7 Conto alla rovescia si/no"),
        T("8 Pannello note si/no"),
        T("9 Traccia note visibile si/no"),
        T("10 Tracce gobbo visibili si/no"),
        T("11 Pausa nel testo (Shift+Invio)"),
        T("12 Tema"),
        T("13 Contrasto"),
        T("14 Corpo -"),
        T("15 Corpo +"),
        T("16 Help"),
        T("17 Nuovo testo temporizzato"),
        T("18 Carica file…"),
        T("19 Riposiziona sul player"),
        T("20 Fascia di lettura si/no"),
        T("21 Bip prima della battuta si/no"),
        T("22 Volume bip -"),
        T("23 Volume bip +")
    }, ", ")

    local ok, value = reaper.GetUserInputs(
        "ZP Studio Suite - " .. T("Gobbo accessibile"),
        1,
        prompt .. ",extrawidth=640",
        "1"
    )
    if not ok then return end

    local choice = tonumber((value or ""):match("%d+"))
    if not choice then
        GobboAccessibleSpeak(T("Scelta non valida."))
        return
    end

    if choice == 1 then
        GobboAccessibleSpeak(GobboAccessibleStatus())
        return
    elseif choice == 2 then
        show_timecode = not show_timecode
        SaveSettings()
        GobboAccessibleSpeak(show_timecode and T("Timecode visibile.") or T("Timecode nascosto."))
    elseif choice == 3 then
        CycleTextFlow(-1)
        GobboAccessibleSpeak(string.format(T("Flusso testi %s."), CurrentTextFlowLabel()))
    elseif choice == 4 then
        CycleTextFlow(1)
        GobboAccessibleSpeak(string.format(T("Flusso testi %s."), CurrentTextFlowLabel()))
    elseif choice == 5 then
        word_follow = not word_follow
        SaveSettings()
        GobboAccessibleSpeak(word_follow and T("Parola per parola attiva.") or T("Parola per parola spenta."))
    elseif choice == 6 then
        fixed_block_mode = not fixed_block_mode
        SaveSettings()
        GobboAccessibleSpeak(fixed_block_mode and T("Scorrimento continuo spento: testo a scatti, una battuta alla volta.") or T("Scorrimento continuo attivo."))
    elseif choice == 7 then
        countdown_alert = not countdown_alert
        SaveSettings()
        GobboAccessibleSpeak(countdown_alert and T("Conto alla rovescia attivo.") or T("Conto alla rovescia spento."))
    elseif choice == 8 then
        notes_panel_open = not notes_panel_open
        SaveSettings()
        RecalculateDocumentLayout()
        GobboAccessibleSpeak(notes_panel_open and T("Pannello note aperto.") or T("Pannello note chiuso."))
    elseif choice == 9 then
        ToggleNotesTrackVisibility()
        GobboAccessibleSpeak(T("Visibilita' traccia note aggiornata."))
    elseif choice == 10 then
        ToggleTextFlowTracksVisibility()
        GobboAccessibleSpeak(T("Visibilita' tracce gobbo aggiornata."))
    elseif choice == 11 then
        GobboAccessibleSpeak(T("Per aggiungere una pausa, seleziona la parola con doppio clic, scegli Edita testo dal menu destro e premi Shift+Invio."))
    elseif choice == 12 then
        if theme_mode == "dark" then theme_mode = "medium"
        elseif theme_mode == "medium" then theme_mode = "light"
        else theme_mode = "dark" end
        SaveSettings()
        GobboAccessibleSpeak(theme_mode == "dark" and T("Tema scuro.") or (theme_mode == "light" and T("Tema chiaro.") or T("Tema medio.")))
    elseif choice == 13 then
        full_contrast = not full_contrast
        SaveSettings()
        GobboAccessibleSpeak(full_contrast and T("Contrasto pieno.") or T("Contrasto sfumato."))
    elseif choice == 14 then
        master_font_size = math.max(10, master_font_size - 1)
        SaveSettings()
        RecalculateDocumentLayout()
        GobboAccessibleSpeak(string.format(T("Corpo testo %s."), tostring(master_font_size)))
    elseif choice == 15 then
        master_font_size = math.min(60, master_font_size + 1)
        SaveSettings()
        RecalculateDocumentLayout()
        GobboAccessibleSpeak(string.format(T("Corpo testo %s."), tostring(master_font_size)))
    elseif choice == 16 then
        OpenSuiteHelp()
        GobboAccessibleSpeak(T("Apro help ZP Studio Suite."))
    elseif choice == 18 then
        AddTimedGobboTextItem(); InlineLoadFile()
    elseif choice == 19 then
        timed_reposition_requested=true
    elseif choice == 20 then
        focus_zone=not focus_zone; SaveSettings()
    elseif choice == 21 then
        SetBeepEnabled(not beep.on)
        GobboAccessibleSpeak(beep.on and T("Bip attivo.") or T("Bip spento."))
    elseif choice == 22 or choice == 23 then
        SetBeepVolume(beep.db + (choice == 23 and 3 or -3))
        GobboAccessibleSpeak(string.format(T("Volume bip %d dB."), beep.db))
    elseif choice == 17 then
        AddTimedGobboTextItem()
        GobboAccessibleSpeak(T("Incolla il testo; la durata si calcola alla velocità impostata."))
    else
        GobboAccessibleSpeak(T("Scelta non disponibile."))
    end
end

function DrawHelpButton(x, y)
    local w, h = 28, 24
    DrawButton(x, y, w, h, "?", 0.22, 0.38, 0.52, false)

    local mouse_down = (gfx.mouse_cap & 1) == 1
    local hover = gfx.mouse_x >= x and gfx.mouse_x <= x + w and gfx.mouse_y >= y and gfx.mouse_y <= y + h
    if mouse_down and hover and not help_button_down then
        help_button_down = true
        OpenSuiteHelp()
    elseif not mouse_down then
        help_button_down = false
    end
end

function DrawSearchPanel(w, h)
    if not search_panel_open then SearchPanelBottom = nil; return end
    RefreshSearchResults(false)
    local panel_w = math.min(680, math.max(80, w - 16))
    local x = math.max(4, math.min(w - panel_w - 4, math.floor((w - panel_w) / 2)))
    local header_h = search_replace_open and 86 or 56
    local max_panel_h = math.max(0, math.min(560, h - 8, math.max(header_h + 24, math.floor(h * 0.6))))
    local y = math.max(0, math.min(36, h - max_panel_h - 4))
    local row_h = search_replace_open and 74 or 52
    local list_h = math.max(0, max_panel_h - header_h - 20)
    local visible_rows = math.min(8, math.floor(list_h / row_h))
    local overflow_h = search_results_total > #search_results and 24 or 0
    local empty_h = search_results_total == 0 and 28 or 0
    local panel_h = math.min(max_panel_h, header_h + math.min(visible_rows, #search_results) * row_h + overflow_h + empty_h + 12)
    y = math.max(0, math.min(y, h - panel_h - 4))
    local pad = 10

    SearchPanelBottom = y + panel_h -- la finestra Modifica battuta si mette subito sotto
    gfx.set(0.08, 0.075, 0.065, 0.97); gfx.rect(x, y, panel_w, panel_h, 1)
    gfx.set(0.72, 0.50, 0.12, 0.95); gfx.rect(x, y, panel_w, 2, 1)
    gfx.set(0.38, 0.34, 0.26, 0.8); gfx.rect(x, y, panel_w, panel_h, 0)

    gfx.setfont(3, "Arial", 13, 'b'); gfx.set(0.93, 0.90, 0.83, 1)
    gfx.x, gfx.y = x + pad, y + 7; gfx.drawstr(T("Cerca"))
    if DrawButton(x + panel_w - 112, y + 4, 102, 22, search_replace_open and T("Nascondi") or T("Sostituisci…"), 0.34, 0.25, 0.12) then
        search_replace_open = not search_replace_open
        search_active_field = search_replace_open and "replace" or "find"
        ScheduleSearchResults(); search_results_deadline = 0
    end

    local function draw_field(field, label, value, cursor, sel_a, sel_b, rect, row_y, label_w, input_width)
        gfx.setfont(3, "Arial", 13, 'b'); gfx.set(0.93, 0.90, 0.83, 1)
        gfx.x, gfx.y = x + pad, row_y + 5; gfx.drawstr(label)
        local input_x, input_y = x + label_w, row_y
        rect.x, rect.y, rect.w, rect.h = input_x, input_y, input_width, 24
        gfx.set(0.12, 0.11, 0.10, 1); gfx.rect(input_x, input_y, input_width, 24, 1)
        gfx.set(search_active_field == field and 0.82 or 0.42, search_active_field == field and 0.58 or 0.40, 0.13, 1)
        gfx.rect(input_x, input_y, input_width, 24, 0)
        gfx.setfont(3, "Arial", 15)
        gfx.set(value == "" and 0.58 or 0.95, value == "" and 0.55 or 0.92, value == "" and 0.50 or 0.84, 1)
        gfx.x, gfx.y = input_x + 7, input_y + 4
        if sel_a and value ~= "" then
            local before_w = gfx.measurestr(value:sub(1, sel_a - 1))
            local sel_w = gfx.measurestr(value:sub(sel_a, sel_b - 1))
            gfx.set(0.18, 0.44, 0.95, 0.55); gfx.rect(input_x + 7 + before_w, input_y + 3, math.max(2,sel_w), 18, 1)
            gfx.set(0.95,0.92,0.84,1); gfx.x,gfx.y=input_x+7,input_y+4
        end
        gfx.drawstr(value ~= "" and value or (field == "find" and T("Cerca parola/frase...") or T("Testo sostitutivo...")))
        if search_active_field == field and math.floor(reaper.time_precise()*2)%2==0 then
            local caret_w=gfx.measurestr(value:sub(1,cursor-1)); gfx.set(0.95,0.70,0.18,1); gfx.rect(input_x+8+caret_w,input_y+5,2,15,1)
        end
        local down=(gfx.mouse_cap & 1)==1
        if gfx.mouse_x>=input_x and gfx.mouse_x<=input_x+input_width and gfx.mouse_y>=input_y and gfx.mouse_y<=input_y+24 and down and not mouse_was_down then
            search_active_field=field
            local rel_x=math.max(0,gfx.mouse_x-input_x-7); local best=1
            local pos=1
            while pos<=#value do
                local next_pos=Utf8NextCursor(value,pos)
                if rel_x<gfx.measurestr(value:sub(1,pos-1)) then break end
                best=next_pos; pos=next_pos
            end
            local now=reaper.time_precise()
            if now-search_last_click_time<0.35 then SearchSetSelection(1,#value+1) else SearchSetCursor(best) end
            search_last_click_time=now
        end
    end

    local input_y = y + 27
    local action_x = x + panel_w - 138
    local input_w = math.max(48, action_x - (x + 58) - 6)
    draw_field("find", T("Trova"), search_query, search_cursor, search_sel_start, search_sel_end, search_input_rect or {}, input_y, 58, input_w)
    search_input_rect = search_input_rect or {}; search_input_rect.x=x+58; search_input_rect.y=input_y; search_input_rect.w=input_w; search_input_rect.h=24
    if DrawButton(x + panel_w - 138, input_y, 30, 24, "<", 0.34, 0.25, 0.12) then ExecuteSubtitleSearch(-1) end
    if DrawButton(x + panel_w - 104, input_y, 30, 24, ">", 0.34, 0.25, 0.12) then ExecuteSubtitleSearch(1) end
    if DrawButton(x + panel_w - 68, input_y, 26, 24, "X", 0.45, 0.18, 0.14) then search_panel_open = false end

    if search_replace_open then
        local ry=y+57; local bx=x+panel_w-126; local rw=math.max(48,bx-(x+105)-6)
        draw_field("replace", T("Sostituisci con"), replace_query, replace_cursor, replace_sel_start, replace_sel_end, replace_input_rect or {}, ry, 105, rw)
        replace_input_rect=replace_input_rect or {}; replace_input_rect.x=x+105; replace_input_rect.y=ry; replace_input_rect.w=rw; replace_input_rect.h=24
        if DrawButton(bx,ry,62,24,T("Sostituisci"),0.34,0.25,0.12) then ApplySearchReplacement(false) end
        if DrawButton(bx+66,ry,48,24,T("Tutti"),0.34,0.25,0.12) then ApplySearchReplacement(true) end
        gfx.setfont(3,"Arial",13); gfx.set(0.90, 0.86, 0.76, 1); gfx.x=x+pad; gfx.y=ry+27
        gfx.drawstr(T("Sostituisce solo parole intere; gli accenti contano (è non cambia e)."))
    end
    if search_message ~= "" and reaper.time_precise() <= search_message_until then
        gfx.setfont(3,"Arial",13); gfx.set(0.98, 0.90, 0.70, 1); gfx.x=x+125; gfx.y=y+8; gfx.drawstr(search_message,0,x+122+math.max(0,panel_w-240),y+24)
    end

    local list_y=y+header_h; local list_x=x+pad; local list_w=panel_w-pad*2-12
    local rows_visible=math.min(visible_rows,#search_results)
    if search_results_current>0 then KeepSearchResultVisible(search_results_current,math.max(1,rows_visible)) end
    local start_i=search_list_scroll+1
    search_list_rect={x=x,y=list_y,w=panel_w,h=rows_visible*row_h}
    if search_results_total==0 then
        gfx.setfont(3,"Arial",15); gfx.set(0.90, 0.86, 0.78, 1); gfx.x=list_x; gfx.y=list_y+5; gfx.drawstr(T("Nessun risultato"))
    else
        for row=1,rows_visible do
            local i=start_i+row-1; local result=search_results[i]
            if result then
                local ry=list_y+(row-1)*row_h
                if i==search_results_current then gfx.set(0.19,0.25,0.34,0.95) else gfx.set(0.12,0.12,0.13,0.9) end
                gfx.rect(list_x,ry,list_w,row_h-2,1)
                local jump_w = 54
                local jump_x, jump_y = list_x + list_w - jump_w - 4, ry + 3
                gfx.set(0.26, 0.22, 0.14, 0.95); gfx.rect(jump_x, jump_y, jump_w, 19, 1)
                gfx.set(0.88, 0.68, 0.28, 0.95); gfx.rect(jump_x, jump_y, jump_w, 19, 0)
                gfx.setfont(3, "Arial", 11, 'b'); gfx.set(0.98, 0.86, 0.58, 1)
                gfx.x, gfx.y = jump_x + 4, jump_y + 3; gfx.drawstr(T("Vai →"))
                local label=FormatVideoTimecode(SearchResultPosition(result))
                -- il file audio da cui viene la battuta (per il montaggio); se non c'e', la traccia in "Tutti"
                if result.item.source_file then label=label.." · "..result.item.source_file
                elseif selected_text_track_guid==READ_ALL then label=label.." · "..tostring(result.item.track_name or "") end
                gfx.setfont(3,"Arial",14,'b'); gfx.set(0.98, 0.82, 0.45, 1); gfx.x=list_x+6; gfx.y=ry+4; gfx.drawstr(label,0,jump_x-4,ry+21)
                local snippet=result.snippet or ""; local sa=result.snip_a or 1; local sb=result.snip_b or sa
                local left=snippet:sub(1,sa-1); local hit=snippet:sub(sa,sb); local right=snippet:sub(sb+1)
                gfx.setfont(3,"Arial",17); local tx=list_x+6; local ty=ry+24
                gfx.set(0.97, 0.96, 0.93, 1); gfx.x=tx; gfx.y=ty; gfx.drawstr(left,0,tx+list_w-12,ty+22)
                local lw=gfx.measurestr(left); local hw=gfx.measurestr(hit)
                gfx.set(0.98, 0.74, 0.20, 1); if lw<list_w-14 then gfx.rect(tx+lw,ty,math.max(2,math.min(hw,list_w-12-lw)),21,1) end
                gfx.set(0.08, 0.06, 0.02, 1); gfx.x=tx+lw; gfx.y=ty; gfx.drawstr(hit,0,tx+list_w-12,ty+22)
                gfx.set(0.97, 0.96, 0.93, 1); gfx.x=tx+lw+hw; gfx.y=ty; gfx.drawstr(right,0,tx+list_w-12,ty+22)
                if search_replace_open then
                    local original=tostring(result.item.notes or ""):sub(result.offset_start,result.offset_end)
                    local after=ZP_CERCA.replace(original,search_query,replace_query,false)
                    gfx.setfont(3,"Arial",15); gfx.set(0.72, 0.95, 0.72, 1); gfx.x=list_x+6; gfx.y=ry+50
                    gfx.drawstr(original.." → "..after,0,list_x+list_w-5,ry+row_h-2)
                end
                local down=(gfx.mouse_cap & 1)==1
                if gfx.mouse_x>=list_x and gfx.mouse_x<=list_x+list_w and gfx.mouse_y>=ry and gfx.mouse_y<ry+row_h-2 and gfx.mouse_cap==0 and mouse_was_down then
                    SelectSearchResult(i,true)
                end
            end
        end
    end
    if search_results_total>#search_results then
        gfx.setfont(3,"Arial",13); gfx.set(0.88, 0.84, 0.76, 1); gfx.x=list_x+4; gfx.y=list_y+rows_visible*row_h+3
        gfx.drawstr("altri "..tostring(search_results_total-#search_results).."…")
    end
    if rows_visible > 0 then
        local track_x=x+panel_w-8; local track_y=list_y; local track_h=rows_visible*row_h
        local max_scroll=math.max(0,#search_results-rows_visible)
        if max_scroll>0 then
            gfx.set(0.20,0.19,0.18,0.9); gfx.rect(track_x,track_y,4,track_h,1)
            local thumb_h=math.max(14,track_h*rows_visible/#search_results)
            local thumb_y=track_y+(track_h-thumb_h)*(search_list_scroll/max_scroll)
            gfx.set(0.65,0.53,0.32,0.95); gfx.rect(track_x,thumb_y,4,thumb_h,1)
            local mx,my=gfx.mouse_x,gfx.mouse_y; local down=(gfx.mouse_cap & 1)==1
            local over_track=mx>=track_x-5 and mx<=track_x+8 and my>=track_y and my<=track_y+track_h
            if down and not mouse_was_down and over_track then
                if my>=thumb_y and my<=thumb_y+thumb_h then search_scroll_dragging=true; search_scroll_drag_offset=my-thumb_y
                else search_list_scroll=math.floor(math.max(0,math.min(1,(my-track_y)/track_h))*max_scroll); search_scroll_dragging=true; search_scroll_drag_offset=thumb_h/2 end
            end
            if search_scroll_dragging and down then
                local ratio=math.max(0,math.min(1,(my-track_y-search_scroll_drag_offset)/(track_h-thumb_h)))
                search_list_scroll=math.floor(ratio*max_scroll+0.5)
            elseif not down then search_scroll_dragging=false end
        else search_scroll_dragging=false end
    end
end

function DrawSpeakerPalette(x, y, w)
    gfx.setfont(3, "Arial", 13)
    SetThemeColor("dim", 0.95)
    gfx.x, gfx.y = x, y
    gfx.drawstr("Colori speaker")
    y = y + 18

    local sw = 18
    local gap = math.max(2, math.floor((w - (#SPEAKER_PALETTE * sw)) / math.max(1, #SPEAKER_PALETTE - 1)))
    local mx, my = gfx.mouse_x, gfx.mouse_y

    for i, entry in ipairs(SPEAKER_PALETTE) do
        local sx = x + ((i - 1) * (sw + gap))
        local sy = y
        local r = ((entry.color >> 16) & 0xFF) / 255
        local g = ((entry.color >> 8) & 0xFF) / 255
        local b = (entry.color & 0xFF) / 255
        local visible = not sidebar_clip_top or (sy + sw >= sidebar_clip_top and sy <= sidebar_clip_bottom)
        local hover = visible and mx >= sx and mx <= sx + sw and my >= sy and my <= sy + sw
        if sidebar_clip_top and (my < sidebar_clip_top or my > sidebar_clip_bottom) then hover = false end

        if visible then
            gfx.set(r, g, b, hover and 1 or 0.88)
            gfx.rect(sx, sy, sw, sw, 1)
            if hover then gfx.set(1, 1, 1, 1) else SetReadableTextColor(r, g, b, 0.85) end
            gfx.rect(sx, sy, sw, sw, 0)
        end

        if hover and (gfx.mouse_cap == 0) and mouse_was_down then
            ApplySpeakerPaletteColor(entry.color)
        end
    end

    return y + sw + 8
end

-- =============================================
function SidebarCheck(x,y,w,label,checked)
    if inline_edit or sidebar_clip_top and (y<sidebar_clip_top or y+22>sidebar_clip_bottom) then return false end
    return ZP_UI.draw_toggle({x=x,y=y,w=w,h=22},label,checked,true,(gfx.mouse_cap&1)==0 and mouse_was_down)
end

function SidebarLabel(x, y, text)
    if sidebar_clip_top and (y + 16 < sidebar_clip_top or y > sidebar_clip_bottom) then return end
    gfx.setfont(3, "Arial", 13)
    SetThemeColor("dim", 1)
    gfx.x, gfx.y = x, y
    gfx.drawstr(text)
end

-- Titolo di sezione con riga sottile. Con key e' richiudibile (stato ricordato in ExtState).
-- Restituisce la y dove continuare e se la sezione e' aperta.
function SidebarSection(x, y, title, key)
    local pad = 12
    local open = true
    if key then
        SidebarOpen = SidebarOpen or {}
        if SidebarOpen[key] == nil then
            SidebarOpen[key] = reaper.GetExtState(settings_section, "sidebar_open_" .. key) ~= "0"
        end
        open = SidebarOpen[key]
    end
    local visible = not sidebar_clip_top or (y + 22 >= sidebar_clip_top and y <= sidebar_clip_bottom)
    if visible then
        SetThemeColor("panel_line", 1)
        gfx.rect(x + pad, y, side_panel_w - pad * 2, 1, 1)
        gfx.setfont(3, "Arial", 12, 'b')
        SetThemeColor("dim", 1)
        gfx.x, gfx.y = x + pad, y + 6
        gfx.drawstr(title)
        if key then
            local arrow = open and "▾" or "▸"
            local aw = gfx.measurestr(arrow)
            gfx.x = x + side_panel_w - pad - aw
            gfx.drawstr(arrow)
            local mx, my = gfx.mouse_x, gfx.mouse_y
            local hover = mx >= x + pad and mx <= x + side_panel_w - pad and my >= y and my <= y + 22
            if sidebar_clip_top and (my < sidebar_clip_top or my > sidebar_clip_bottom) then hover = false end
            if hover and gfx.mouse_cap == 0 and mouse_was_down then
                open = not open
                SidebarOpen[key] = open
                reaper.SetExtState(settings_section, "sidebar_open_" .. key, open and "1" or "0", true)
            end
        end
    end
    return y + 26, open
end

-- Tendina del flusso testi: scegli al volo una traccia testo o "Tutti".
function ShowTextFlowMenu(mx, my)
    local tracks = CollectTextFlowTracks()
    if #tracks == 0 then return end
    local entries = {}
    if #tracks >= 2 then entries[#entries + 1] = { guid = READ_ALL, name = T("Tutti") } end
    for _, entry in ipairs(tracks) do
        entries[#entries + 1] = { guid = entry.guid, name = TextFlowDisplayName(entry.name) }
    end
    local parts = {}
    for i, entry in ipairs(entries) do
        local label = tostring(entry.name or ""):gsub("|", "/")
        if label:sub(1, 1) == "#" or label:sub(1, 1) == "!" or label:sub(1, 1) == ">" or label:sub(1, 1) == "<" then label = " " .. label end
        parts[i] = ((entry.guid == selected_text_track_guid) and "!" or "") .. label
    end
    gfx.x, gfx.y = mx, my
    local choice = gfx.showmenu(table.concat(parts, "|"))
    if choice and choice > 0 and entries[choice] then SelectTextFlow(entries[choice].guid) end
end

function DrawSidePanel(w, h, tc_position)
    SidebarThemeForce = "dark"
    DrawSidePanelBody(w, h, tc_position)
    SidebarThemeForce = nil
end

function DrawSidePanelBody(w, h, tc_position)
    if panels_hidden then return end
    local x = w - (sidebar_collapsed and 30 or side_panel_w)
    local pad = 12
    local header_h = 44
    local y = header_h + 8 - sidebar_scroll_y
    local clip_top = header_h
    local clip_bottom = h

    SetThemeColor("panel", 0.98)
    gfx.rect(x, 0, side_panel_w, h, 1)
    SetThemeColor("panel_line", 1)
    gfx.rect(x, 0, 1, h, 1)



    if sidebar_collapsed then
        if DrawButton(x, 10, 30, 24, "<", 0.2, 0.3, 0.4, false) then
            sidebar_collapsed = false
            SaveSettings()
            RecalculateDocumentLayout()
        end
        return
    end

    sidebar_clip_top = clip_top
    sidebar_clip_bottom = clip_bottom

        if not sidebar_collapsed then
            -- Barra comandi: in alto cio' che si usa lavorando, poi le regolazioni, in fondo
            -- quello che si imposta una volta (sezioni richiudibili). Funzioni invariate.
            local full_w = side_panel_w - pad * 2
            local half_w = math.floor((full_w - 6) / 2)

            -- LAVORO
            if DrawButton(x + pad, y, full_w, 28, T("Cerca  (Ctrl/⌘+F)"), 0.25, 0.32, 0.42) then
                PromptSubtitleSearch()
            end
            y = y + 34
            if DrawButton(x + pad, y, full_w, 28, T("+ Nota"), 0.36, 0.30, 0.14) then
                InsertNoteAtCurrentPosition()
            end
            y = y + 38
            if DrawButton(x + pad, y, full_w, 28, T("+ Testo temporizzato"), 0.20, 0.42, 0.48) then
                AddTimedGobboTextItem()
            end
            y = y + 32
            if DrawButton(x+pad,y,full_w,26,T('Carica file…'),0.2,0.4,0.5) then
                AddTimedGobboTextItem(); InlineLoadFile()
            end
            y=y+32
            SidebarLabel(x + pad, y + 3, tostring(timed_scroll_wpm) .. " " .. T("parole/min"))
            y = y + 19
            if DrawButton(x + pad + full_w - 112, y, 34, 24, "−", 0.45, 0.20, 0.20) then
                SetTimedScrollSpeed(-10, tc_position); SaveSettings()
            end
            if DrawButton(x + pad + full_w - 36, y, 34, 24, "+", 0.20, 0.45, 0.20) then
                SetTimedScrollSpeed(10, tc_position); SaveSettings()
            end
            y = y + 30
            if DrawButton(x + pad, y, full_w, 25, T("Riposiziona sul player"), 0.22, 0.30, 0.42) then
                timed_reposition_requested = true
            end
            y = y + 31
            if SidebarCheck(x + pad, y, full_w, T("Modifica (Studio/Edit)"), studio_edit_mode) then
                studio_edit_mode = not studio_edit_mode
                if studio_edit_mode then
                    reaper.OnStopButton()
                    fixed_block_mode = false
                end
                SaveSettings()
            end
            y = y + 26
            if studio_edit_mode then
                if SidebarCheck(x + pad + 18, y, full_w - 18, T("Muove la timeline"), studio_edit_sync) then
                    studio_edit_sync = not studio_edit_sync
                    SaveSettings()
                end
                y = y + 26
            end

            -- TESTO
            y = SidebarSection(x, y, T("TESTO"))
            SidebarLabel(x + pad, y + 5, T("Flusso"))
            local flow_label = CurrentTextFlowLabel()
            if #flow_label > 14 then flow_label = flow_label:sub(1, 13) .. "." end
            if DrawButton(x + pad + 58, y, full_w - 58, 26, flow_label .. "  ▾", 0.22, 0.30, 0.42) then
                ShowTextFlowMenu(x + pad + 58, y + 26)
            end
            y = y + 34
            SidebarLabel(x + pad, y + 6, T("Corpo"))
            if DrawButton(x + pad + 58, y, 36, 26, "−", 0.45, 0.20, 0.20) then
                master_font_size = math.max(10, master_font_size - 1)
                SaveSettings()
                RecalculateDocumentLayout()
            end
            gfx.setfont(3, "Arial", 17, 'b')
            SetThemeColor("active", 0.95)
            local font_value = tostring(master_font_size)
            local fw = gfx.measurestr(font_value)
            if y >= (sidebar_clip_top or 0) - 4 then
                gfx.x, gfx.y = x + pad + 58 + 36 + ((full_w - 58 - 72) - fw) / 2, y + 4
                gfx.drawstr(font_value)
            end
            if DrawButton(x + pad + full_w - 36, y, 36, 26, "+", 0.20, 0.45, 0.20) then
                master_font_size = math.min(60, master_font_size + 1)
                SaveSettings()
                RecalculateDocumentLayout()
            end
            y = y + 34
            SidebarLabel(x + pad, y, T("Punto di lettura"))
            y = y + 18
            local seg_w = math.floor((full_w - 8) / 3)
            if DrawButton(x + pad, y, seg_w, 26, T("Alto"), 0.22, 0.30, 0.42, math.abs(reading_point - 0.18) < 0.01) then
                reading_point = 0.18
                SaveSettings()
            end
            if DrawButton(x + pad + seg_w + 4, y, seg_w, 26, T("Terzo"), 0.22, 0.30, 0.42, math.abs(reading_point - 0.34) < 0.01) then
                reading_point = 0.34
                SaveSettings()
            end
            if DrawButton(x + pad + (seg_w + 4) * 2, y, seg_w, 26, T("Centro"), 0.22, 0.30, 0.42, math.abs(reading_point - 0.50) < 0.01) then
                reading_point = 0.50
                SaveSettings()
            end
            y = y + 34

            -- LETTURA
            y = SidebarSection(x, y, T("LETTURA"))
            if SidebarCheck(x+pad,y,full_w,T('Fascia di lettura'),focus_zone) then focus_zone=not focus_zone; SaveSettings() end
            y=y+26
            if SidebarCheck(x + pad, y, full_w, T("Scorrimento continuo"), not fixed_block_mode) then
                fixed_block_mode = not fixed_block_mode
                SaveSettings()
            end
            y = y + 26
            if SidebarCheck(x + pad, y, full_w, T("Parola per parola"), word_follow) then
                word_follow = not word_follow
                SaveSettings()
            end
            y = y + 26
            if SidebarCheck(x + pad, y, full_w, T("Conto alla rovescia"), countdown_alert) then
                countdown_alert = not countdown_alert
                SaveSettings()
            end
            y = y + 26
            if SidebarCheck(x + pad, y, full_w, T("Avviso TC in arrivo"), tc_alert_mode == "box") then
                tc_alert_mode = tc_alert_mode == "box" and "off" or "box"
                SaveSettings()
            end
            y = y + 26
            if SidebarCheck(x + pad, y, full_w, T("Bip prima della battuta"), beep.on) then
                SetBeepEnabled(not beep.on)
            end
            y = y + 26
            if beep.on then
                SidebarLabel(x + pad, y + 6, T("Volume bip"))
                if DrawButton(x + pad + 86, y, 36, 26, "−", 0.45, 0.20, 0.20) then SetBeepVolume(beep.db - 3) end
                gfx.setfont(3, "Arial", 15, 'b')
                SetThemeColor("active", 0.95)
                local beep_value = string.format("%d dB", beep.db)
                local beep_w = gfx.measurestr(beep_value)
                if y >= (sidebar_clip_top or 0) - 4 then
                    gfx.x, gfx.y = x + pad + 86 + 36 + ((full_w - 86 - 72) - beep_w) / 2, y + 5
                    gfx.drawstr(beep_value)
                end
                if DrawButton(x + pad + full_w - 36, y, 36, 26, "+", 0.20, 0.45, 0.20) then SetBeepVolume(beep.db + 3) end
                y = y + 32
            end
            if SidebarCheck(x + pad, y, full_w, T("Mostra timecode"), show_timecode) then
                show_timecode = not show_timecode
                SaveSettings()
            end
            y = y + 30

            -- ASPETTO (richiudibile)
            local open
            y, open = SidebarSection(x, y, T("ASPETTO"), "aspetto")
            if open then
                SidebarLabel(x + pad, y, T("Tema"))
                y = y + 18
                if DrawButton(x + pad, y, seg_w, 26, T("Scuro"), 0.22, 0.22, 0.28, theme_mode == "dark") then
                    theme_mode = "dark"
                    SaveSettings()
                end
                if DrawButton(x + pad + seg_w + 4, y, seg_w, 26, T("Medio"), 0.52, 0.48, 0.35, theme_mode == "medium") then
                    theme_mode = "medium"
                    SaveSettings()
                end
                if DrawButton(x + pad + (seg_w + 4) * 2, y, seg_w, 26, T("Chiaro"), 0.72, 0.72, 0.72, theme_mode == "light") then
                    theme_mode = "light"
                    SaveSettings()
                end
                y = y + 34
                SidebarLabel(x + pad, y, T("Contrasto"))
                y = y + 18
                if DrawButton(x + pad, y, half_w, 26, T("Sfumato"), 0.28, 0.28, 0.34, not full_contrast) then
                    full_contrast = false
                    SaveSettings()
                end
                if DrawButton(x + pad + half_w + 6, y, half_w, 26, T("Pieno"), 0.42, 0.34, 0.18, full_contrast) then
                    full_contrast = true
                    SaveSettings()
                end
                y = y + 36
                y = DrawSpeakerPalette(x + pad, y, full_w)
                y = y + 4
            end

            -- NOTE E TRACCE (richiudibile)
            y, open = SidebarSection(x, y, T("NOTE E TRACCE"), "tracce")
            if open then
                if SidebarCheck(x + pad, y, full_w, T("Pannello note"), notes_panel_open) then
                    notes_panel_open = not notes_panel_open
                    SaveSettings()
                    RecalculateDocumentLayout()
                end
                y = y + 26
                if SidebarCheck(x + pad, y, full_w, T("Segui i tagli"), FollowEnabled()) then
                    if FollowScriptPath() then ToggleFollow() end
                end
                y = y + 26
                local notes_track_visible, flow_tracks_visible = SidebarTrackVisibility()
                if SidebarCheck(x + pad, y, full_w, T("Traccia note visibile"), notes_track_visible) then
                    ToggleNotesTrackVisibility()
                end
                y = y + 26
                if SidebarCheck(x + pad, y, full_w, T("Tracce gobbo visibili"), flow_tracks_visible) then
                    ToggleTextFlowTracksVisibility()
                end
                y = y + 30
            end

            -- ACCESSIBILITA'
            y = y + 6
            if DrawButton(x + pad, y, full_w, 26, T("Menu OSARA"), 0.20, 0.42, 0.50, false) then
                OpenGobboAccessibleMenu()
            end
            y = y + 36
            gfx.setfont(3, "Arial", 11)
            SetThemeColor("dim", 0.9)
            if y >= (sidebar_clip_top or 0) then
                gfx.x, gfx.y = x + pad, y
                ZP_UI.draw_credit(x+pad,y,10)
                gfx.x, gfx.y = x + pad, y + 14
                gfx.drawstr("Paolo Balestri & Nicola Lanci")
            end
            y = y + 36
        
            sidebar_content_h = math.max(header_h, y + sidebar_scroll_y)
            sidebar_clip_top = nil
            sidebar_clip_bottom = nil
        
            local max_scroll = math.max(0, sidebar_content_h - h)
            if max_scroll > 0 then
                local track_x = x + side_panel_w - 5
                local track_y = header_h + 4
                local track_h = math.max(20, h - header_h - 8)
                local thumb_h = math.max(24, track_h * (h / sidebar_content_h))
                local thumb_y = track_y + ((track_h - thumb_h) * (sidebar_scroll_y / max_scroll))
                local over_thumb = gfx.mouse_x >= track_x - 3 and gfx.mouse_x <= track_x + 5 and gfx.mouse_y >= thumb_y and gfx.mouse_y <= thumb_y + thumb_h
                local over_track = gfx.mouse_x >= track_x - 5 and gfx.mouse_x <= track_x + 7 and gfx.mouse_y >= track_y and gfx.mouse_y <= track_y + track_h
                local mouse_down = (gfx.mouse_cap & 1) == 1
                if mouse_down and not mouse_was_down and over_thumb then sidebar_scroll_dragging = true end
                if not mouse_down then sidebar_scroll_dragging = false end
                if sidebar_scroll_dragging then
                    local rel = (gfx.mouse_y - track_y - (thumb_h * 0.5)) / math.max(1, track_h - thumb_h)
                    sidebar_scroll_y = math.max(0, math.min(max_scroll, rel * max_scroll))
                    thumb_y = track_y + ((track_h - thumb_h) * (sidebar_scroll_y / max_scroll))
                elseif mouse_down and not mouse_was_down and over_track then
                    local rel = (gfx.mouse_y - track_y - (thumb_h * 0.5)) / math.max(1, track_h - thumb_h)
                    sidebar_scroll_y = math.max(0, math.min(max_scroll, rel * max_scroll))
                end
                gfx.set(0.12, 0.12, 0.16, 0.90)
                gfx.rect(track_x, track_y, 3, track_h, 1)
                gfx.set(0.58, 0.66, 0.82, (over_thumb or sidebar_scroll_dragging) and 1 or 0.72)
                gfx.rect(track_x - 2, thumb_y, 7, thumb_h, 1)
            else
                sidebar_scroll_dragging = false
            end
        
            SetThemeColor("panel", 1)
            gfx.rect(x, 0, side_panel_w, header_h, 1)
            SetThemeColor("panel_line", 1)
            gfx.rect(x, header_h - 1, side_panel_w, 1, 1)
            gfx.rect(x, 0, 1, h, 1)
    
        
        
            gfx.setfont(3, "Arial", 15, 'b')
            SetThemeColor("text", 0.95)
            gfx.x, gfx.y = x + pad, 12
            gfx.drawstr("GOBBO")
        
        
            DrawHelpButton(x + side_panel_w - pad - 28, 10)
            -- A sinistra di Help: un solo hit target, senza sovrapposizioni.
            if DrawButton(x + side_panel_w - pad - 64, 10, 30, 24, ">", 0.2, 0.3, 0.4, false) then
                sidebar_collapsed = true
                sidebar_scroll_dragging = false
                SaveSettings()
                RecalculateDocumentLayout()
            end
    end
        end
        
        function DrawTimecodeHud(notes_w, tc_position, tc_alert_item)
            -- Avviso TC: nei secondi prima dell'attacco il riquadro lampeggia in giallo.
            -- Con "Mostra timecode" spento il riquadro compare solo durante l'avviso.
            local alert = tc_alert_mode == "box" and tc_alert_item ~= nil
            if not show_timecode and not alert then return end
            local flash = alert and (math.floor(reaper.time_precise() * 4) % 2 == 0)
            local tc_text = FormatVideoTimecode(tc_position or GetCurrentProjectPosition())
            gfx.setfont(3, "Arial", math.max(14, master_font_size - 2), 'b')
            local tw, th = gfx.measurestr(tc_text)
            local x = notes_w + 14
            local y = 12
            gfx.set(0, 0, 0, 1)
            gfx.rect(x - 10, y - 7, tw + 20, th + 14, 1)
            if flash then gfx.set(1, 0.86, 0.18, 1) else gfx.set(0, 0, 0, 1) end
            gfx.rect(x - 8, y - 5, tw + 16, th + 10, 1)
            gfx.set(0.82, 0.82, 0.82, 1)
            gfx.rect(x - 8, y - 5, tw + 16, th + 10, 0)
            if flash then gfx.set(0, 0, 0, 1) else gfx.set(1, 1, 1, 1) end
            gfx.x, gfx.y = x, y
            gfx.drawstr(tc_text)
        end
        
        function ClampDocumentScroll(scroll_y, visible_h)
            local max_scroll = math.max(0, (document_total_h or 0) - math.max(120, visible_h or gfx.h) + 80)
            return math.max(0, math.min(scroll_y or 0, max_scroll)), max_scroll
        end
        
        function ProjectPositionFromDocumentScroll(scroll_y, reading_y)
            if #cached_items == 0 then return nil, nil end
            local doc_y = (scroll_y or 0) + (reading_y or (gfx.h * reading_point))
            local previous = nil
            for _, item in ipairs(cached_items) do
                if doc_y >= item.doc_start_y and doc_y <= item.doc_end_y then
                    local denom = math.max(1, (item.doc_end_y or 0) - (item.doc_start_y or 0))
                    local progress = item.reading_plan and ZP_TESTO.progress_for_row(item.reading_plan,(doc_y-item.doc_start_y)/(master_font_size*1.55)) or math.max(0, math.min(1, (doc_y - item.doc_start_y) / denom))
                    return item.pos + ((item.len or 0) * progress), item.item
                end
                if previous and doc_y > previous.doc_end_y and doc_y < item.doc_start_y then
                    local denom = math.max(1, item.doc_start_y - previous.doc_end_y)
                    local progress = math.max(0, math.min(1, (doc_y - previous.doc_end_y) / denom))
                    local prev_end = previous.pos + previous.len
                    return prev_end + ((item.pos - prev_end) * progress), item.item
                end
                previous = item
            end
            if doc_y < cached_items[1].doc_start_y then return cached_items[1].pos, cached_items[1].item end
            local last = cached_items[#cached_items]
            return last.pos + last.len, last.item
        end
        
        function JumpTimelineFromDocumentScroll(visible_h)
            if not studio_edit_mode or not studio_edit_sync then return end
            local reading_y = gfx.h * reading_point
            local pos, item = ProjectPositionFromDocumentScroll(document_scroll_y, reading_y)
            if not pos then return end
            if item then
                reaper.Main_OnCommand(40289, 0) -- Unselect all items
                reaper.SetMediaItemSelected(item, true)
                local track = reaper.GetMediaItem_Track(item)
                if track then reaper.SetOnlyTrackSelected(track) end
            end
            reaper.SetEditCurPos(pos, true, false)
            search_virtual_pos = pos
            if item then
                search_hit_item = item
                search_hit_until = reaper.time_precise() + 1.5
            end
            reaper.UpdateArrange()
        end
        
function DrawEditScrollbar(notes_w, read_w, visible_h)
    if inline_edit then return end
    if not studio_edit_mode then return end
    local scroll_y, max_scroll = ClampDocumentScroll(document_scroll_y, visible_h)
    document_scroll_y = scroll_y
    if max_scroll <= 0 then return end

    local x = notes_w + read_w - 12
    local y = 54
    local h = math.max(80, visible_h - 92)
    local thumb_h = math.max(38, h * (visible_h / math.max(visible_h, document_total_h or visible_h)))
    local thumb_y = y + (scroll_y / max_scroll) * (h - thumb_h)

    local mouse_down = (gfx.mouse_cap & 1) == 1
    local over_thumb = gfx.mouse_x >= x - 4 and gfx.mouse_x <= x + 8 and gfx.mouse_y >= thumb_y and gfx.mouse_y <= thumb_y + thumb_h
    local over_bar = gfx.mouse_x >= x - 6 and gfx.mouse_x <= x + 10 and gfx.mouse_y >= y and gfx.mouse_y <= y + h

    if mouse_down and not mouse_was_down and over_thumb then
        edit_scroll_dragging = true
    elseif not mouse_down then
        if edit_scroll_dragging or edit_scroll_was_dragging then
            JumpTimelineFromDocumentScroll(visible_h)
        end
        edit_scroll_dragging = false
        edit_scroll_was_dragging = false
    end

    if edit_scroll_dragging then
        edit_scroll_was_dragging = true
        local rel = (gfx.mouse_y - y - (thumb_h * 0.5)) / math.max(1, h - thumb_h)
        document_scroll_y = ClampDocumentScroll(rel * max_scroll, visible_h)
    elseif mouse_down and not mouse_was_down and over_bar then
        local rel = (gfx.mouse_y - y - (thumb_h * 0.5)) / math.max(1, h - thumb_h)
        document_scroll_y = ClampDocumentScroll(rel * max_scroll, visible_h)
        edit_scroll_was_dragging = true
    end

    gfx.set(0.08, 0.08, 0.10, 0.75)
    gfx.rect(x, y, 4, h, 1)
    gfx.set(0.52, 0.76, 0.88, (over_thumb or edit_scroll_dragging) and 0.95 or 0.70)
    gfx.rect(x - 2, thumb_y, 8, thumb_h, 1)
end

-- =============================================
function DrawGUI()
    local char = gfx.getchar()
    if char == -1 then
        reaper.DeleteExtState(gobbo_state_section, gobbo_state_key, false)
        return
    end
    reaper.SetExtState(gobbo_state_section, gobbo_state_key, tostring(reaper.time_precise()), false)
    if inline_edit and ProcessInlineSubtitleEditKey(char) then
        char = 0
    elseif search_panel_open and ProcessSearchPanelKey(char) then
        char = 0
    end
    if char > 0 and (char==12 or ((gfx.mouse_cap&4)~=0 or (gfx.mouse_cap&32)~=0) and (char==76 or char==108)) then
        AddTimedGobboTextItem(); InlineLoadFile(); char=0
    end
    if char > 0 then
        local changed = false
        if char == 9 then
            panels_hidden = not panels_hidden
            RecalculateDocumentLayout()
        elseif char == 27 and timed_manual_override then timed_reposition_requested=true
        elseif char == 43 or char == 61 then SetTimedScrollSpeed(10)
        elseif char == 45 then SetTimedScrollSpeed(-10)
        elseif char == 32 then reaper.Main_OnCommand(40044, 0) -- Transport: Play/stop
        elseif IsSearchShortcut(char) then PromptSubtitleSearch()
        elseif char == 78 or char == 110 then InsertNoteAtCurrentPosition()
        elseif char == 30064 then master_font_size = math.min(60, master_font_size + 1); changed = true
        elseif char == 1685026670 then master_font_size = math.max(10, master_font_size - 1); changed = true end
        
        if changed then
            show_settings_timer = 60
            SaveSettings()
            RecalculateDocumentLayout()
        end
    end
    local wheel = gfx.mouse_wheel or 0
    if inline_edit then inline_edit.wheel=wheel; wheel=0 end
    NotesWheel = wheel -- per il pannello NOTE (scorrimento dell'elenco)
    gfx.mouse_wheel = 0

    local w, h = gfx.w, gfx.h
    SaveWindowStateIfChanged()
    if w ~= last_win_w then
        last_win_w = w
        RecalculateDocumentLayout()
    end

    local spw = not panels_hidden and (sidebar_collapsed and 30 or side_panel_w) or 0
    local over_sidebar = gfx.mouse_x >= w - spw and gfx.mouse_x <= w and gfx.mouse_y >= 0 and gfx.mouse_y <= h
    if wheel ~= 0 and search_panel_open and search_list_rect
        and gfx.mouse_x >= search_list_rect.x and gfx.mouse_x <= search_list_rect.x + search_list_rect.w
        and gfx.mouse_y >= search_list_rect.y and gfx.mouse_y <= search_list_rect.y + search_list_rect.h then
        local visible = math.max(1, math.floor(search_list_rect.h / (search_replace_open and 74 or 52)))
        search_list_scroll = math.max(0, math.min(search_list_scroll + (wheel > 0 and -2 or 2), math.max(0, #search_results - visible)))
        wheel = 0
    elseif wheel ~= 0 and over_sidebar then
        local max_sidebar_scroll = math.max(0, (sidebar_content_h or 0) - h)
        sidebar_scroll_y = math.max(0, math.min(sidebar_scroll_y + (wheel > 0 and -42 or 42), max_sidebar_scroll))
        wheel = 0
    elseif (sidebar_content_h or 0) <= h then
        sidebar_scroll_y = 0
    else
        sidebar_scroll_y = math.max(0, math.min(sidebar_scroll_y, math.max(0, sidebar_content_h - h)))
    end

    FollowTick()
    local proj_state = reaper.GetProjectStateChangeCount(0)
    local project = reaper.EnumProjects(-1)
    if proj_state ~= frame_cache.track_state or project ~= frame_cache.project
        or selected_text_track_guid ~= frame_cache.track_sel
        or (frame_cache.track and not IsValidTrack(frame_cache.track)) then
        frame_cache.track = GetRythmoTrack()
        frame_cache.track_state = proj_state
        frame_cache.project = project
        frame_cache.track_sel = selected_text_track_guid
    end
    local track = frame_cache.track
    local track_guid = selected_text_track_guid == READ_ALL and READ_ALL or (track and reaper.GetTrackGUID(track) or "")

    if proj_state ~= last_proj_state or track_guid ~= last_track_guid then
        last_proj_state = proj_state
        last_track_guid = track_guid
        UpdateItems()
        UpdateWindowTitle()
    end

    local is_playing = (reaper.GetPlayState() & 1) == 1
    local smoothed_play_pos = 0

    if is_playing then
        local raw_pos = reaper.GetPlayPosition()
        local current_time = reaper.time_precise()
        
        if raw_pos ~= last_play_pos_raw then
            last_play_pos_raw = raw_pos
            last_play_pos_time = current_time
        end
        
        local play_rate = reaper.Master_GetPlayRate(0)
        local time_diff = current_time - last_play_pos_time
        
        if time_diff > 0.2 then
             time_diff = 0
             last_play_pos_time = current_time 
             last_play_pos_raw = raw_pos
        end
        
        smoothed_play_pos = raw_pos + (time_diff * play_rate)
    else
        smoothed_play_pos = reaper.GetCursorPosition()
        last_play_pos_raw = -1
    end

    local notes_w = (not panels_hidden and notes_panel_open) and NOTES_PANEL_W or 0
    local read_w = math.max(320, w - spw - notes_w)
    local text_x = notes_w + document_margin_x + speaker_shoulder_w
    local reading_y = h * reading_point
    local tc_alert_item = FindUpcomingCue(smoothed_play_pos)
    UpdateCountdownBeep(tc_alert_item, smoothed_play_pos)

    local teleprompter_bottom = h

    SetThemeColor("bg", 1)
    gfx.rect(notes_w, 0, read_w, teleprompter_bottom, 1)
    DrawNotesPanel(teleprompter_bottom, smoothed_play_pos, reading_y)
    if focus_zone then
        gfx.set(0.4,0.6,0.75,0.055); ZP_UI.fill_round(notes_w+4,reading_y-master_font_size,read_w-8,master_font_size*2,8)
    end

    if #cached_items == 0 then
        gfx.setfont(1, "Arial", 18)
        gfx.set(0.4, 0.4, 0.4, 1)
        local warn_text = T("Seleziona la traccia Copione!")
        local tw, th = gfx.measurestr(warn_text)
        gfx.x = notes_w + ((read_w - tw) / 2)
        gfx.y = (teleprompter_bottom - th) / 2
        gfx.drawstr(warn_text)
    end
    
    -- ===============================================================
    -- MOTORE DI SCROLLING DEL DOCUMENTO "PDF" CONTINUO
    -- ===============================================================
    -- Troviamo dove siamo nel documento in base alla posizione del playhead
    local target_scroll_y = 0
    local found_active = false
    local static_display_item = nil
    local active_timed_scroll_item = nil
    active_progress = 0.0
    
    for i, item in ipairs(cached_items) do
        -- Se il playhead è DENTRO l'item
        if smoothed_play_pos >= item.pos and (smoothed_play_pos < item.pos + item.len or not item.timed_scroll and smoothed_play_pos <= item.pos + item.len) then
            -- Calcoliamo a che percentuale dell'item audio ci troviamo
            local item_progress = (smoothed_play_pos - item.pos) / item.len
            active_progress = item_progress
            item.reading_state=item.reading_plan and ZP_TESTO.reading_state(item.reading_plan,item_progress) or nil
            -- In modalita' fissa il blocco resta fermo sul punto di lettura
            -- per tutta la sua durata. In modalita' scorri il testo attraversa
            -- il punto di lettura come un copione continuo.
            if fixed_block_mode then
                -- Modalita' pagina statica: l'item corrente resta fermo
                -- per tutta la sua durata. La lunghezza dell'item decide
                -- per quanto tempo quel blocco rimane pienamente visibile.
                target_scroll_y = item.doc_start_y - reading_y
                static_display_item = item
            else
                local pixel_progress = item.reading_state and item.reading_state.row*master_font_size*1.55 or item.pixel_height*item_progress
                target_scroll_y = (item.doc_start_y + pixel_progress) - reading_y
            end
            found_active = true
            if item.timed_scroll then active_timed_scroll_item = item.item end
            break
        end
        
        -- Se il playhead si trova nel GAP tra questo item e il SUCCESSIVO
        if not found_active and i < #cached_items then
            local next_item = cached_items[i+1]
            if smoothed_play_pos >= item.pos + item.len and smoothed_play_pos < next_item.pos then
                local gap_dur = next_item.pos - (item.pos + item.len)
                local gap_progress = (smoothed_play_pos - (item.pos + item.len)) / gap_dur
                
                if fixed_block_mode then
                    target_scroll_y = item.doc_start_y - reading_y
                    static_display_item = item
                else
                    -- Interpola lo scroll nello "spazio nero" visivo tra i due blocchi
                    local gap_pixel_dist = next_item.doc_start_y - item.doc_end_y
                    local current_pixel_in_gap = gap_pixel_dist * gap_progress
                    target_scroll_y = (item.doc_end_y + current_pixel_in_gap) - reading_y
                end
                found_active = true
                break
            end
        end
    end
    
    -- Se siamo PRIMA del primo item
    if not found_active and #cached_items > 0 and smoothed_play_pos < cached_items[1].pos then
        -- Mantiene il primo item al centro se non è ancora iniziato
        target_scroll_y = cached_items[1].doc_start_y - reading_y
        if fixed_block_mode then static_display_item = cached_items[1] end
    elseif not found_active and #cached_items > 0 and smoothed_play_pos >= cached_items[#cached_items].pos + cached_items[#cached_items].len then
        -- Scroll fermo sull'ultimo item se superato
        target_scroll_y = (fixed_block_mode and cached_items[#cached_items].doc_start_y or cached_items[#cached_items].doc_end_y) - reading_y
        if fixed_block_mode then static_display_item = cached_items[#cached_items] end
    end

    -- Studio/Edit: la rotella sul testo scorre anche con Sync ON (porta con se' il cursore della
    -- timeline, come la barra). Per 0,6 s dopo l'ultimo scatto il testo non insegue il cursore.
    local over_document = gfx.mouse_x >= notes_w and gfx.mouse_x <= notes_w + read_w and gfx.mouse_y >= 0 and gfx.mouse_y <= teleprompter_bottom
    if active_timed_scroll_item ~= timed_override_item then
        timed_override_item = active_timed_scroll_item
        timed_manual_override = false
    end
    if timed_reposition_requested then
        timed_reposition_requested = false
        timed_manual_override = false
        document_scroll_y = target_scroll_y
    end
    if active_timed_scroll_item and wheel~=0 and over_document and (gfx.mouse_cap&16)~=0 then
        SetTimedScrollSpeed(wheel>0 and 10 or -10,smoothed_play_pos); wheel=0
    end
    if active_timed_scroll_item and wheel ~= 0 and over_document then
        local step = math.max(42, master_font_size * 2.2)
        document_scroll_y = document_scroll_y + (wheel > 0 and -step or step)
        timed_manual_override = true
        wheel = 0
    end
    if active_timed_scroll_item and (edit_scroll_dragging or edit_scroll_was_dragging) then
        timed_manual_override = true
    end
    if active_timed_scroll_item and timed_manual_override then
        -- La rotella e la barra restano libere; il player riprende a seguire il testo
        -- soltanto quando si preme "Riposiziona sul player".
        document_scroll_y = ClampDocumentScroll(document_scroll_y, teleprompter_bottom)
    elseif studio_edit_mode and wheel ~= 0 and over_document then
        EditWheelUntil = reaper.time_precise() + 0.6
    end
    if not (active_timed_scroll_item and timed_manual_override) and studio_edit_mode and (not studio_edit_sync or edit_scroll_dragging or edit_scroll_was_dragging
        or reaper.time_precise() < (EditWheelUntil or 0)) then
        if wheel ~= 0 and over_document then
            local step = math.max(42, master_font_size * 2.2)
            document_scroll_y = document_scroll_y + (wheel > 0 and -step or step)
            if studio_edit_sync then JumpTimelineFromDocumentScroll(teleprompter_bottom) end
        end
        document_scroll_y = ClampDocumentScroll(document_scroll_y, teleprompter_bottom)
    elseif not (active_timed_scroll_item and timed_manual_override) then
        -- Smooth follow camera. In modalita' Fisso il cambio blocco e' diretto:
        -- niente scorrimento interno mentre la battuta e' valida.
        if fixed_block_mode then
            document_scroll_y = target_scroll_y
        else
            document_scroll_y = lerp(document_scroll_y, target_scroll_y, scroll_follow)
        end
        document_scroll_y = ClampDocumentScroll(document_scroll_y, teleprompter_bottom)
    end
    
    -- Disegna finalmente l'intero copione
    local line_h = master_font_size * 1.55
    gfx.setfont(1, default_font, master_font_size)

    for _, header in ipairs(cached_headers) do
        local hy = header.y - document_scroll_y
        if hy > -40 and hy < teleprompter_bottom then
            gfx.set(0.70, 0.48, 0.16, 0.95)
            gfx.rect(text_x, hy + master_font_size + 8, math.max(20, read_w - speaker_shoulder_w - document_margin_x * 2), 2, 1)
            gfx.setfont(3, "Arial", math.max(14, master_font_size), 'b')
            SetThemeColor("guide", 0.95)
            gfx.x, gfx.y = text_x, hy
            gfx.drawstr(header.text)
            gfx.setfont(1, default_font, master_font_size)
        end
    end
    
    for _, item in ipairs(cached_items) do
            -- Calcoliamo la coordinata Y reale sullo schermo per questo blocco.
            -- In Scorri OFF solo l'item centrale resta statico sul punto di
            -- lettura; il resto del copione rimane visibile sopra e sotto.
            local start_py = item.doc_start_y - document_scroll_y
            local end_py = item.doc_end_y - document_scroll_y
            if fixed_block_mode and item == static_display_item then
                local text_h = math.max(line_h, (item.pixel_height or line_h))
                start_py = math.max(12, math.min(reading_y, teleprompter_bottom - text_h - 18))
                end_py = start_py + text_h
            end
            
            -- Culling (non disegna se è fuori dallo schermo, sia sopra che sotto)
            if end_py > 0 and start_py < teleprompter_bottom then
            
            -- In Sfumato accendiamo anche le battute vicine al punto di lettura:
            -- serve prepararsi prima dell'attacco e non perdere subito la riga appena passata.
            local is_active = smoothed_play_pos >= item.pos and (smoothed_play_pos < item.pos + item.len or not item.timed_scroll and smoothed_play_pos <= item.pos + item.len)
            local is_search_hit = search_hit_item == item.item and reaper.time_precise() <= search_hit_until
            local is_sfumato_ready = false
            if not full_contrast then
                is_sfumato_ready = (
                    smoothed_play_pos >= item.pos - sfumato_pre_roll and
                    smoothed_play_pos <= item.pos + item.len + sfumato_post_roll
                )
            end

            if countdown_alert and tc_alert_item and tc_alert_item.item == item.item then
                local countdown = math.ceil(item.pos - smoothed_play_pos)
                local count_text = tostring(countdown)
                gfx.setfont(3, "Arial", math.max(22, master_font_size + 6), 'b')
                local count_w, count_h = gfx.measurestr(count_text)
                local count_center_x = notes_w + math.max(34, document_margin_x * 0.78)
                local count_x = count_center_x - (count_w / 2)
                local count_y = reading_y - (count_h / 2)

                if countdown_alert and countdown >= 1 and countdown <= math.ceil(TC_ALERT_LEAD) then
                    gfx.set(1.0, 0.78, 0.18, 1)
                    gfx.x = count_x
                    gfx.y = count_y
                    gfx.drawstr(count_text)
                end

                gfx.setfont(1, default_font, master_font_size)
            end

            DrawCharacterTags(item, text_x, start_py, end_py, is_active or is_sfumato_ready)
            gfx.setfont(1, default_font, master_font_size)

            if is_search_hit then
                local hit_h = math.max(line_h, end_py - start_py + 10)
                gfx.set(1.0, 0.58, 0.12, 0.22)
                gfx.rect(text_x - 10, start_py - 6, math.max(260, read_w - speaker_shoulder_w - document_margin_x * 2 + 20), hit_h, 1)
                gfx.set(1.0, 0.70, 0.18, 0.95)
                gfx.rect(text_x - 10, start_py - 6, 4, hit_h, 1)
            end
            
            local base_color_kind = "dim"
            local base_alpha = 0.48
            if is_active then
                base_color_kind = "active"
                base_alpha = 1.0
            elseif is_sfumato_ready then
                base_color_kind = "active"
                base_alpha = 0.86
            elseif full_contrast then
                base_color_kind = "text"
                base_alpha = 0.92
            end

            local word_counter = 0
            for i, line in ipairs(item.lines) do
                -- Testo da copione: allineato a sinistra, come un documento.
                word_counter = DrawTextLine(line, text_x, start_py + ((i-1) * line_h), is_active, item, word_counter, base_color_kind, base_alpha)
            end
            DrawCharacterUnderline(item, text_x, end_py - 4, math.max(160, read_w - speaker_shoulder_w - document_margin_x * 2), is_active or is_sfumato_ready)
            local edit_w = math.max(240, notes_w + read_w - text_x - document_margin_x)
            HandleStudioItemClick(item.item, text_x - 8, start_py - 4, edit_w, math.max(line_h, end_py - start_py))
            HandleSubtitleEditDoubleClick(item,text_x,start_py,edit_w,math.max(line_h,end_py-start_py))
            HandleGobboWordAnchorMenu(item,text_x,start_py,edit_w,math.max(line_h,end_py-start_py))
            DrawGobboWordAnchors(item,text_x,start_py,line_h)
            DrawGobboWordSelection(item,text_x,start_py,line_h)
            if inline_edit and inline_edit.item == item.item then
                -- la battuta che stai modificando: cornice e barra a sinistra
                local bx, by, bh = text_x - 12, start_py - 6, math.max(line_h, end_py - start_py) + 8
                inline_edit.block = {y = by, h = bh}
                gfx.set(1.0, 0.70, 0.12, 0.95)
                gfx.rect(bx, by, 5, bh, 1)
                gfx.rect(bx, by, edit_w + 8, bh, 0)
                gfx.rect(bx + 1, by + 1, edit_w + 6, bh - 2, 0)
            end
        end
    end

    -- Guida laterale: indica il punto di lettura senza attraversare il testo.
    SetThemeColor("guide", 0.75)
    local guide_x = notes_w + math.max(8, math.floor(document_margin_x * 0.35))
    gfx.rect(guide_x, reading_y - 18, 4, 36, 1)
    gfx.rect(guide_x - 5, reading_y - 1, 14, 2, 1)
    DrawEditScrollbar(notes_w, read_w, teleprompter_bottom)

    if show_settings_timer > 0 then
        local hud_alpha = math.min(1, show_settings_timer / 20)
        gfx.setfont(2, "Arial", 18, 'b')
        local hud_txt = string.format(T("FONT COPIONE: %d"), master_font_size)
        local tw, th = gfx.measurestr(hud_txt)
        
        gfx.set(0, 0, 0, 0.7 * hud_alpha)
        gfx.rect(10, 10, tw + 20, th + 10, 1)
        gfx.set(1, 1, 1, hud_alpha)
        gfx.x, gfx.y = 20, 15
        gfx.drawstr(hud_txt)
        show_settings_timer = show_settings_timer - 1
    end

    DrawSidePanel(w, h, smoothed_play_pos)
    sidebar_scroll_y = math.max(0, math.min(sidebar_scroll_y, math.max(0, (sidebar_content_h or 0) - h)))
    DrawTimecodeHud(notes_w, smoothed_play_pos, tc_alert_item)
    if active_timed_scroll_item and not inline_edit then
        local pos=reaper.GetMediaItemInfo_Value(active_timed_scroll_item,'D_POSITION')
        local len=reaper.GetMediaItemInfo_Value(active_timed_scroll_item,'D_LENGTH')
        local progress=math.max(0,math.min(1,(smoothed_play_pos-pos)/math.max(0.001,len)))
        gfx.set(0.25,0.35,0.43,0.65); gfx.rect(notes_w+8,h-5,read_w-16,3,1)
        gfx.set(0.35,0.80,0.62,0.95); gfx.rect(notes_w+8,h-5,(read_w-16)*progress,3,1)
        if timed_manual_override then
            local text=T('Scorrimento manuale — Clicca o Esc per tornare sul player')
            if ZP_UI.draw_button({x=notes_w+12,y=80,w=read_w-24,h=30},text,true,true,(gfx.mouse_cap&1)==0 and mouse_was_down,'warning') then timed_reposition_requested=true end
        end
    end


    DrawInlineSubtitleEditor()
    if not inline_edit then DrawSearchPanel(w, h) end

    mouse_was_down = (gfx.mouse_cap & 1) == 1
    if (gfx.mouse_cap&2)==0 then gobbo_word_right_down=false end
    gfx.update()
    reaper.defer(DrawGUI)
end

LoadSettings()
InitGUI()
DrawGUI()
