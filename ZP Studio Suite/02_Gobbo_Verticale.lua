--[[
   * ReaScript Name: ZP Studio Suite Teleprompter Nativo
   * Linea: ZP Paolo Balestri
   * Suite: ZP Studio Suite for REAPER v1.0.5
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
local cached_items = {}
local cached_notes = {}
local cached_character_notes = {}
local cached_regions = {}
local cached_video_items = {}
local cached_headers = {}
local character_lane_by_key = {}
local last_proj_state = -1
local last_track_guid = ""
local selected_text_track_guid = ""
local current_text_track = nil
local last_win_w = 0
local active_media_item = nil

local document_total_h = 0
local document_scroll_y = 0

-- Impostazioni Font e Finestra
local default_font = "Arial"
local master_font_size = 16
local show_settings_timer = 0
local document_margin_x = 54
local speaker_shoulder_w = 78
local scroll_follow = 0.045
local side_panel_w = 190
local theme_mode = "medium"
local full_contrast = false
local sfumato_pre_roll = 5.0
local sfumato_post_roll = 3.0
local word_follow = false
local fixed_block_mode = false
local notes_panel_open = true
local tc_alert_mode = "off"
local countdown_alert = true
local max_character_rows = 1
local reading_point = 0.34
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
local panel_open = false
local panel_anim  = 0.0
local PANEL_H = 96
local panel_anim_speed = 0.18
local mouse_was_down = false
local last_edit_click_time = 0
local last_edit_click_item = nil
local inline_edit = nil
local inline_clipboard = ""
local search_query = ""
local search_cursor = 1
local search_sel_start = nil
local search_sel_end = nil
local search_input_rect = nil
local search_last_click_time = 0
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
local COLOR_SUBS_HOT = 0xD84D7A
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
local NOTE_PIXELS_PER_SECOND = 46
local NOTES_PANEL_W = 210
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
    reaper.SetExtState(settings_section, "theme_mode", theme_mode, true)
    reaper.SetExtState(settings_section, "full_contrast", bool_to_state(full_contrast), true)
    reaper.SetExtState(settings_section, "word_follow", bool_to_state(word_follow), true)
    reaper.SetExtState(settings_section, "fixed_block_mode", bool_to_state(fixed_block_mode), true)
    reaper.SetExtState(settings_section, "notes_panel_open", bool_to_state(notes_panel_open), true)
    reaper.SetExtState(settings_section, "tc_alert_mode", tc_alert_mode, true)
    reaper.SetExtState(settings_section, "countdown_alert", bool_to_state(countdown_alert), true)
    reaper.SetExtState(settings_section, "max_character_rows", tostring(max_character_rows), true)
    reaper.SetExtState(settings_section, "reading_point", tostring(reading_point), true)
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
    local saved_theme = reaper.GetExtState(settings_section, "theme_mode")
    if saved_theme == "dark" or saved_theme == "medium" or saved_theme == "light" then
        theme_mode = saved_theme
    end

    full_contrast = state_to_bool(reaper.GetExtState(settings_section, "full_contrast"), full_contrast)
    word_follow = state_to_bool(reaper.GetExtState(settings_section, "word_follow"), word_follow)
    fixed_block_mode = state_to_bool(reaper.GetExtState(settings_section, "fixed_block_mode"), fixed_block_mode)
    notes_panel_open = state_to_bool(reaper.GetExtState(settings_section, "notes_panel_open"), notes_panel_open)
    show_timecode = state_to_bool(reaper.GetExtState(settings_section, "show_timecode"), show_timecode)
    countdown_alert = state_to_bool(reaper.GetExtState(settings_section, "countdown_alert"), countdown_alert)
    studio_edit_mode = state_to_bool(reaper.GetExtState(settings_section, "studio_edit_mode"), studio_edit_mode)
    studio_edit_sync = state_to_bool(reaper.GetExtState(settings_section, "studio_edit_sync"), studio_edit_sync)
    local saved_tc_alert = reaper.GetExtState(settings_section, "tc_alert_mode")
    if saved_tc_alert == "off" or saved_tc_alert == "side" or saved_tc_alert == "line" then
        tc_alert_mode = saved_tc_alert == "side" and "line" or saved_tc_alert
    end
    max_character_rows = 1

    master_font_size = math.max(10, math.min(60, tonumber(reaper.GetExtState(settings_section, "master_font_size")) or master_font_size))
    document_margin_x = math.max(20, math.min(180, tonumber(reaper.GetExtState(settings_section, "document_margin_x")) or document_margin_x))
    scroll_follow = math.max(0.010, math.min(0.120, tonumber(reaper.GetExtState(settings_section, "scroll_follow")) or scroll_follow))

    local saved_reading = tonumber(reaper.GetExtState(settings_section, "reading_point"))
    if saved_reading then reading_point = math.max(0.12, math.min(0.65, saved_reading)) end

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

    local state = table.concat({
        tostring(math.floor(w + 0.5)),
        tostring(math.floor(h + 0.5)),
        tostring(math.floor(x + 0.5)),
        tostring(math.floor(y + 0.5)),
        tostring(dock)
    }, ",")

    if state ~= last_saved_window_state then
        window_w = math.floor(w + 0.5)
        window_h = math.floor(h + 0.5)
        window_x = math.floor(x + 0.5)
        window_y = math.floor(y + 0.5)
        window_dock = dock
        last_saved_window_state = state
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

function AddEmptyGobboTextItem()
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    local track = GetOrCreateTextFlowTrack()
    if not track then
        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock("ZP Studio Suite: aggiungi testo gobbo", -1)
        return
    end

    selected_text_track_guid = reaper.GetTrackGUID(track)
    SetTrackVisible(track, true, true)

    local pos = GetCurrentProjectPosition()
    local ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local len = 5.0
    if ts_start and ts_end and ts_end - ts_start > 0.2 then
        pos = ts_start
        len = ts_end - ts_start
    end

    local item = reaper.AddMediaItemToTrack(track)
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", math.max(0.2, len))
    reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", NativeColor(COLOR_SUBS))
    reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "TESTO", true)
    UpdateSubtitleItemName(item, "TESTO")

    reaper.Main_OnCommand(40289, 0)
    reaper.SetMediaItemSelected(item, true)
    reaper.SetEditCurPos(pos, true, false)
    active_media_item = item

    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ZP Studio Suite: aggiungi testo gobbo", -1)
    reaper.UpdateArrange()
    UpdateItems()
    RecalculateDocumentLayout()
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
    local entry = CurrentTextFlowEntry()
    if not entry then return "Nessun testo" end
    return TextFlowDisplayName(entry.name)
end

function CycleTextFlow(delta)
    local tracks = CollectTextFlowTracks()
    if #tracks == 0 then return end

    local current_guid = selected_text_track_guid or ""
    local current_index = 1
    for i, entry in ipairs(tracks) do
        if entry.guid == current_guid then current_index = i break end
    end

    local next_index = ((current_index - 1 + delta) % #tracks) + 1
    selected_text_track_guid = tracks[next_index].guid
    current_text_track = tracks[next_index].track
    active_media_item = nil
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

function SetReadableTextColor(r, g, b, alpha)
    local tr, tg, tb = BestTextColorForBackground(r, g, b)
    gfx.set(tr, tg, tb, alpha or 1)
end

function NormalizeName(name)
    return trim(name or ""):lower()
end

function IsVoiceTrackName(name)
    local n = NormalizeName(name)
    if n == "" then return false end
    if n:find(NormalizeName(default_track_name), 1, true) then return false end
    if n:find(NormalizeName(notes_track_name), 1, true) then return false end
    if n:find("video", 1, true) then return false end
    if n == "master" then return false end
    return true
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

function GetPreferredCharacterName()
    local selected = reaper.GetSelectedTrack(0, 0)
    local selected_name = GetTrackName(selected)
    if IsVoiceTrackName(selected_name) then return NormalizeName(selected_name) end

    for i=0, reaper.CountTracks(0)-1 do
        local track = reaper.GetTrack(0, i)
        if reaper.GetMediaTrackInfo_Value(track, "I_RECARM") > 0 then
            local name = GetTrackName(track)
            if IsVoiceTrackName(name) then return NormalizeName(name) end
        end
    end
    return ""
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

function IsCharacterNoteItem(item)
    return IsCharacterNoteTrack(GetItemTrack(item))
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
        if IsCharacterNoteItem(item) then
            local note_track = GetItemTrack(item)
            local key = tostring(note_track)
            if not colored_tracks[key] then
                changed = changed + ApplySpeakerColorToVoicePair(note_track, native)
                colored_tracks[key] = true
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
        reaper.ShowMessageBox("Seleziona un item sulla traccia VOCE/RB, oppure porta il cursore/playhead vicino a uno speaker item.", "ZP Studio Suite", 0)
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
end

function ToggleNotesTrackVisibility()
    local track = GetOrCreateNotesTrack()
    if not track then return end
    SetTrackVisible(track, not IsTrackVisible(track))
end

function NotesTrackLabel()
    local track = FindTrackByName(notes_track_name)
    if IsTrackVisible(track) then return "Track Note View VIS" end
    return "Track Note View NASC"
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
end

function ToggleTextFlowTracksVisibility()
    SetTextFlowTracksVisible(not AnyTextFlowTrackVisible())
end

function TextFlowTracksLabel()
    if AnyTextFlowTrackVisible() then return "Track Gobbo VIS" end
    return "Track Gobbo NASC"
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

function FindItemAtPosition(pos)
    for _, entry in ipairs(cached_items) do
        if pos >= entry.pos and pos <= entry.pos + entry.len then
            return entry.item
        end
    end
    return nil
end

function EditCurrentText()
    local item = active_media_item or FindItemAtPosition(GetCurrentProjectPosition())
    if not item then
        reaper.ShowMessageBox("Nessuna battuta sotto il cursore/playhead.", "ZP Studio Suite", 0)
        return
    end

    local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    local edit_text = notes:gsub("[\r\n]+", " / ")
    local ok, new_text = reaper.GetUserInputs("Modifica battuta corrente", 1, "Testo:,extrawidth=700", edit_text)
    if not ok then return end

    new_text = new_text:gsub("%s*/%s*", "\n")
    reaper.Undo_BeginBlock()
    reaper.GetSetMediaItemInfo_String(item, "P_NOTES", new_text, true)
    reaper.Undo_EndBlock("ZP Studio Suite modifica testo", -1)
    reaper.UpdateArrange()
    UpdateItems()
end

function InsertNoteAtCurrentPosition()
    StartInlineNoteEdit(nil)
end

function FindNearestNote(pos)
    local best_note = nil
    local best_score = nil
    for _, note in ipairs(cached_notes) do
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

function EditNearestNote()
    local note, distance = FindNearestNote(GetCurrentProjectPosition())
    if not note or (distance and distance > 12) then
        reaper.ShowMessageBox("Nessuna nota vicina al playhead/cursore.", "ZP Studio Suite", 0)
        return
    end

    StartInlineNoteEdit(note)
end

function DeleteNearestNote()
    local note, distance = FindNearestNote(GetCurrentProjectPosition())
    if not note or (distance and distance > 12) then
        reaper.ShowMessageBox("Nessuna nota vicina al playhead/cursore.", "ZP Studio Suite", 0)
        return
    end

    local ok = reaper.ShowMessageBox("Cancellare la nota vicina?\n\n" .. note.text, "ZP Studio Suite", 4)
    if ok ~= 6 then return end

    local track = reaper.GetMediaItem_Track(note.item)
    reaper.Undo_BeginBlock()
    reaper.DeleteTrackMediaItem(track, note.item)
    reaper.Undo_EndBlock("ZP Studio Suite cancella nota", -1)
    reaper.UpdateArrange()
    UpdateItems()
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

function NormalizeSearchText(text)
    return tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n"):lower()
end

function IsSearchWordChar(ch)
    if ch == "" then return false end
    return ch:match("[%w_]") ~= nil
end

function IsExactSearchBoundary(text, start_pos, end_pos)
    local before = start_pos > 1 and text:sub(start_pos - 1, start_pos - 1) or ""
    local after = end_pos <= #text and text:sub(end_pos, end_pos) or ""
    return not IsSearchWordChar(before) and not IsSearchWordChar(after)
end

function FindExactSearchInText(text, query)
    local haystack = NormalizeSearchText(text)
    local needle = NormalizeSearchText(query)
    if needle == "" then return nil end

    local from = 1
    while true do
        local s, e = haystack:find(needle, from, true)
        if not s then return nil end
        if needle:find("%s") or IsExactSearchBoundary(haystack, s, e + 1) then
            return s, e
        end
        from = s + 1
    end
end

function FindSubtitleMatch(query, start_pos)
    local needle = NormalizeSearchText(query)
    if needle == "" then return nil end

    local fallback = nil
    for _, item in ipairs(cached_items) do
        local match_start = FindExactSearchInText(item.notes, needle)
        if match_start then
            local ratio = math.max(0, math.min(1, (match_start - 1) / math.max(1, #NormalizeSearchText(item.notes))))
            item.search_match_pos = item.pos + (item.len * ratio)
            if not fallback then fallback = item end
            if item.pos > (start_pos or 0) + 0.001 then
                return item
            end
        end
    end
    return fallback
end

function FindSubtitleMatchPrevious(query, start_pos)
    local needle = NormalizeSearchText(query)
    if needle == "" then return nil end

    local fallback = nil
    for i = #cached_items, 1, -1 do
        local item = cached_items[i]
        local match_start = FindExactSearchInText(item.notes, needle)
        if match_start then
            local ratio = math.max(0, math.min(1, (match_start - 1) / math.max(1, #NormalizeSearchText(item.notes))))
            item.search_match_pos = item.pos + (item.len * ratio)
            if not fallback then fallback = item end
            if item.pos < (start_pos or 0) - 0.001 then
                return item
            end
        end
    end
    return fallback
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
    search_cursor = #(search_query or "") + 1
    search_sel_start = nil
    search_sel_end = nil
end

function ExecuteSubtitleSearch(direction)
    if inline_edit then SaveInlineSubtitleEdit() end
    search_query = trim(search_query or "")
    search_cursor = math.max(1, math.min(search_cursor or (#search_query + 1), #search_query + 1))
    if search_query == "" then
        search_message = "Scrivi una parola o frase"
        search_message_until = reaper.time_precise() + 1.8
        return
    end

    local pos = (studio_edit_mode and not studio_edit_sync and search_virtual_pos) or GetCurrentProjectPosition()
    local match = direction and direction < 0 and FindSubtitleMatchPrevious(search_query, pos) or FindSubtitleMatch(search_query, pos)
    if not match then
        search_message = "Nessun risultato"
        search_message_until = reaper.time_precise() + 2.0
        return
    end
    JumpToSearchMatch(match)
    search_message = FormatVideoTimecode(match.search_match_pos or match.pos)
    search_message_until = reaper.time_precise() + 2.0
end

function IsSearchShortcut(char)
    if char == 6 then return true end
    local is_f = char == 70 or char == 102
    local has_modifier = ((gfx.mouse_cap & 4) == 4) or ((gfx.mouse_cap & 32) == 32)
    return is_f and has_modifier
end

function SearchSetCursor(pos)
    search_cursor = math.max(1, math.min(pos or 1, #(search_query or "") + 1))
    search_sel_start = nil
    search_sel_end = nil
end

function SearchSetSelection(a, b)
    local max_pos = #(search_query or "") + 1
    a = math.max(1, math.min(a or 1, max_pos))
    b = math.max(1, math.min(b or a, max_pos))
    search_cursor = b
    if a == b then
        search_sel_start, search_sel_end = nil, nil
    else
        search_sel_start, search_sel_end = math.min(a, b), math.max(a, b)
    end
end

function SearchSelectionRange()
    if not search_sel_start or search_sel_start == search_sel_end then return nil, nil end
    return math.min(search_sel_start, search_sel_end), math.max(search_sel_start, search_sel_end)
end

function SearchDeleteSelection()
    local a, b = SearchSelectionRange()
    if not a then return false end
    search_query = (search_query or ""):sub(1, a - 1) .. (search_query or ""):sub(b)
    SearchSetCursor(a)
    return true
end

function SearchInsertText(text)
    text = tostring(text or "")
    if text == "" then return end
    SearchDeleteSelection()
    local source = search_query or ""
    local cursor = search_cursor or (#source + 1)
    search_query = source:sub(1, cursor - 1) .. text .. source:sub(cursor)
    search_cursor = cursor + #text
end

function SearchBackspace()
    if SearchDeleteSelection() then return end
    local source = search_query or ""
    local cursor = search_cursor or (#source + 1)
    if cursor <= 1 then return end
    local prev = Utf8PrevCursor(source, cursor)
    search_query = source:sub(1, prev - 1) .. source:sub(cursor)
    search_cursor = prev
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
    if char == 13 then ExecuteSubtitleSearch(1); return true end
    if char == 27 then search_panel_open = false; return true end
    if char == 8 then SearchBackspace(); return true end
    if char == 1 then SearchSetSelection(1, #(search_query or "") + 1); return true end
    if char == 22 then SearchPaste(); return true end
    if char == 1818584692 then SearchSetCursor(Utf8PrevCursor(search_query, search_cursor)); return true end
    if char == 1919379572 then SearchSetCursor(Utf8NextCursor(search_query, search_cursor)); return true end
    if char == 1752132965 then SearchSetCursor(1); return true end
    if char == 6647396 then SearchSetCursor(#(search_query or "") + 1); return true end
    if char >= 32 and char <= 1114111 then
        local ch = TextCharFromCode(char)
        if ch then SearchInsertText(ch) end
        return true
    end
    return false
end

function CycleTCAlertMode()
    tc_alert_mode = "off"
    SaveSettings()
end

function TCAlertLabel()
    return "TC Gobbo OFF"
end

function CountdownAlertLabel()
    return countdown_alert and "Countdown ON" or "Countdown OFF"
end

function InitGUI()
    gfx.clear = 0x111111 
    gfx.init("ZP Studio Suite v1.0.5 - Gobbo", window_w, window_h, window_dock, window_x, window_y)
    gfx.setfont(1, default_font, master_font_size)
    last_saved_window_state = ""
    SaveWindowStateIfChanged()
end

-- =============================================
function WrapText(text, max_w)
    local lines = {}
    for paragraph in text:gmatch("([^\r\n]+)") do
        local words = {}
        for word in paragraph:gmatch("%S+") do table.insert(words, word) end
        
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

function DrawTextLine(line, x, y, is_active, item, word_counter, base_color_kind, base_alpha)
    local function clean_word(word)
        return NormalizeSearchText(tostring(word or ""):gsub("^%p+", ""):gsub("%p+$", ""))
    end

    local function word_is_highlighted(word)
        if item and search_hit_item == item.item and reaper.time_precise() <= search_hit_until then
            local live = trim(search_hit_query or "")
            if live ~= "" and not live:find("%s") then
                if clean_word(word) == NormalizeSearchText(live) then return true end
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

    local target_word = math.floor((item.total_words or 1) * active_progress) + 1
    local group_radius = 1
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

function DrawWrappedNoteText(text, x, y, max_w, alpha)
    gfx.setfont(3, "Arial", 14)
    local lines = WrapText(text:gsub("[\r\n]+", " "), max_w)
    local line_h = 17
    for i, line in ipairs(lines) do
        gfx.x = x
        gfx.y = y + ((i - 1) * line_h)
        gfx.drawstr(line)
    end
    return #lines * line_h
end

function MeasureWrappedNoteText(text, max_w)
    gfx.setfont(3, "Arial", 14)
    local lines = WrapText((text or ""):gsub("[\r\n]+", " "), max_w)
    return #lines * 17
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

function DrawNotesPanel(h, play_pos, reading_y)
    if not notes_panel_open then return end

    local x = 0
    local pad = 12
    local panel_w = NOTES_PANEL_W
    gfx.set(0.10, 0.095, 0.075, 0.96)
    gfx.rect(x, 0, panel_w, h, 1)
    gfx.set(0.55, 0.42, 0.18, 0.75)
    gfx.rect(panel_w - 1, 0, 1, h, 1)

    gfx.setfont(3, "Arial", 15, 'b')
    gfx.set(0.95, 0.84, 0.42, 1)
    gfx.x, gfx.y = x + pad, 14
    gfx.drawstr("NOTE")

    local clip_top = 42
    local clip_bottom = h - 8
    local shown = 0
    local max_w = panel_w - (pad * 2)
    local entries = {}

    for _, note in ipairs(cached_notes) do
        local text_h = MeasureWrappedNoteText(note.text, max_w)
        local card_h = text_h + 34
        local raw_y = (reading_y or (h * reading_point)) + ((note.pos - play_pos) * NOTE_PIXELS_PER_SECOND) - 18
        if raw_y + card_h >= clip_top and raw_y <= clip_bottom then
            table.insert(entries, {note=note, y=raw_y, card_h=card_h, text_h=text_h})
        end
    end

    table.sort(entries, function(a, b) return a.y < b.y end)

    local last_bottom = clip_top - 8
    for _, entry in ipairs(entries) do
        local note = entry.note
        local y = math.max(entry.y, last_bottom + 8)
        local card_h = entry.card_h
        if y > clip_bottom then break end
        if y + card_h >= clip_top then
            local state, alpha = NoteVisualState(note, play_pos)

            if state == "active" then
                gfx.set(note.r, note.g, note.b, 0.56)
                gfx.rect(x + 6, y - 4, panel_w - 12, card_h, 1)
            elseif state == "imminent" then
                gfx.set(note.r, note.g, note.b, 0.20 + alpha * 0.20)
                gfx.rect(x + 6, y - 4, panel_w - 12, card_h, 1)
            elseif state == "past" then
                gfx.set(note.r, note.g, note.b, 0.16)
                gfx.rect(x + 6, y - 4, panel_w - 12, card_h, 1)
            else
                gfx.set(note.r, note.g, note.b, 0.18)
                gfx.rect(x + 6, y - 4, panel_w - 12, card_h, 1)
            end

            local tc = FormatVideoTimecode(note.pos)
            gfx.setfont(3, "Arial", 12, 'b')
            SetReadableTextColor(note.r, note.g, note.b, math.max(0.62, alpha))
            gfx.x, gfx.y = x + pad, y
            gfx.drawstr(tc)

            y = y + 17
            SetReadableTextColor(note.r, note.g, note.b, math.max(0.62, alpha))
            DrawWrappedNoteText(note.text, x + pad, y, max_w, alpha)
            shown = shown + 1
        end
        last_bottom = y + card_h
    end

    if shown == 0 then
        gfx.setfont(3, "Arial", 13)
        gfx.set(0.60, 0.56, 0.46, 0.8)
        gfx.x, gfx.y = x + pad, clip_top + 10
        gfx.drawstr("Nessuna nota nel quadro")
    end
end

function TruncateText(text, max_chars)
    local out = tostring(text or "")
    if #out > max_chars then return out:sub(1, max_chars - 3) .. "..." end
    return out
end

function UpdateSubtitleItemName(item, text)
    local one_line = trim((text or ""):gsub("[\r\n]+", " / "))
    one_line = one_line:gsub("%s+", " ")
    if #one_line > 160 then one_line = one_line:sub(1, 157) .. "..." end
    reaper.GetSetMediaItemInfo_String(item, "P_NAME", one_line, true)
    reaper.UpdateItemInProject(item)
end

function EditSubtitleItemText(item)
    if not item then return end
    local _, old_text = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    local edit_text = (old_text or ""):gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\n", " \\n ")
    local ok, new_text = reaper.GetUserInputs(
        "Edit testo gobbo",
        1,
        "Testo (usa \\n per andare a capo):,extrawidth=700",
        edit_text
    )
    if not ok then return end
    new_text = trim((new_text or ""):gsub("%s*\\n%s*", "\n"))
    if new_text == "" or new_text == old_text then return end

    reaper.Undo_BeginBlock()
    reaper.GetSetMediaItemInfo_String(item, "P_NOTES", new_text, true)
    UpdateSubtitleItemName(item, new_text)
    reaper.Undo_EndBlock("Edit testo dal gobbo verticale", -1)
    reaper.UpdateArrange()
    UpdateItems()
    RecalculateDocumentLayout()
end

function Utf8Backspace(text)
    text = tostring(text or "")
    if text == "" then return "" end
    if utf8 and utf8.offset then
        local byte = utf8.offset(text, -1)
        if byte then return text:sub(1, byte - 1) end
    end
    return text:sub(1, -2)
end

function Utf8PrevCursor(text, cursor)
    text = tostring(text or "")
    cursor = math.max(1, math.min(cursor or (#text + 1), #text + 1))
    if cursor <= 1 then return 1 end
    if utf8 and utf8.offset then
        local byte = utf8.offset(text, -1, cursor - 1)
        if byte then return byte end
    end
    return cursor - 1
end

function Utf8NextCursor(text, cursor)
    text = tostring(text or "")
    cursor = math.max(1, math.min(cursor or (#text + 1), #text + 1))
    if cursor > #text then return #text + 1 end
    if utf8 and utf8.offset then
        local byte = utf8.offset(text, 2, cursor)
        if byte then return byte end
    end
    return cursor + 1
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
    if not inline_edit then return end
    inline_edit.undo_stack = inline_edit.undo_stack or {}
    inline_edit.undo_stack[#inline_edit.undo_stack + 1] = {
        text = inline_edit.text or "",
        cursor = inline_edit.cursor or 1,
        sel_start = inline_edit.sel_start,
        sel_end = inline_edit.sel_end
    }
    if #inline_edit.undo_stack > 80 then table.remove(inline_edit.undo_stack, 1) end
end

function InlineRestoreUndo()
    if not inline_edit or not inline_edit.undo_stack then return end
    local state = table.remove(inline_edit.undo_stack)
    if not state then return end
    inline_edit.text = state.text or ""
    inline_edit.cursor = state.cursor or (#(inline_edit.text or "") + 1)
    inline_edit.sel_start = state.sel_start
    inline_edit.sel_end = state.sel_end
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
    local cursor = line.start
    local best_pos = line.start
    for pos = line.start, line.finish + 1 do
        local part = inline_edit.text:sub(line.start, pos - 1)
        local tw = gfx.measurestr(part)
        if rel_x < tw then break end
        best_pos = pos
    end
    cursor = best_pos
    InlineSetCursor(cursor)
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

function InlinePaste()
    local clip = inline_clipboard
    if reaper.CF_GetClipboard then
        local ok, value = pcall(reaper.CF_GetClipboard, "")
        if ok and value and value ~= "" then clip = value end
    end
    if clip and clip ~= "" then InlineInsertText((clip:gsub("\r\n", "\n"):gsub("\r", "\n"))) end
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

function ToggleItemHighlight(item, selected_text)
    if not item then return end
    local term = trim(tostring(selected_text or ""):gsub("[\r\n]+", " "))
    if term == "" then return end
    local _, raw = reaper.GetSetMediaItemInfo_String(item, "P_EXT:RythmoBand_HIGHLIGHT", "", false)
    local terms = ParseHighlightTerms(raw)
    local key = NormalizeSearchText(term)
    local removed = false
    for i = #terms, 1, -1 do
        if NormalizeSearchText(terms[i]) == key then
            table.remove(terms, i)
            removed = true
        end
    end
    if not removed then table.insert(terms, term) end
    reaper.GetSetMediaItemInfo_String(item, "P_EXT:RythmoBand_HIGHLIGHT", SerializeHighlightTerms(terms), true)
    reaper.UpdateItemInProject(item)
    return not removed
end

function InlineToggleHighlight()
    if not inline_edit or not inline_edit.item then return end
    local selected = InlineSelectedText()
    if selected == "" then
        InlineSelectWordAtCursor()
        selected = InlineSelectedText()
    end
    local enabled = ToggleItemHighlight(inline_edit.item, selected)
    inline_edit.highlights = ParseHighlightTerms(({reaper.GetSetMediaItemInfo_String(inline_edit.item, "P_EXT:RythmoBand_HIGHLIGHT", "", false)})[2])
    UpdateItems()
    RecalculateDocumentLayout()
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
    for pos = target_line.start, target_line.finish + 1 do
        local tw = gfx.measurestr(inline_edit.text:sub(target_line.start, pos - 1))
        if tw > desired_x then break end
        best = pos
    end
    InlineSetCursor(best)
end

function StartInlineSubtitleEdit(item, x, y, w, h)
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
    reaper.OnStopButton()
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
    if not inline_edit then return end
    local new_text = trim(inline_edit.text or "")
    local mode = inline_edit.mode or "subtitle"
    if mode == "note_new" and new_text ~= "" then
        local track = GetOrCreateNotesTrack()
        if not track then
            reaper.ShowMessageBox("Impossibile creare la traccia note.", "ZP Studio Suite", 0)
            return
        end
        reaper.Undo_BeginBlock()
        local item = reaper.AddMediaItemToTrack(track)
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", inline_edit.note_position or GetCurrentProjectPosition())
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", NOTE_DEFAULT_LEN)
        reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", NativeColor(COLOR_NOTES))
        reaper.GetSetMediaItemInfo_String(item, "P_NOTES", new_text, true)
        reaper.GetSetMediaItemInfo_String(item, "P_NAME", "NOTA", true)
        reaper.UpdateItemInProject(item)
        reaper.Undo_EndBlock("ZP Studio Suite: inserisci nota dal gobbo", -1)
    elseif mode == "note_edit" and inline_edit.item and new_text ~= "" and new_text ~= inline_edit.original then
        reaper.Undo_BeginBlock()
        reaper.GetSetMediaItemInfo_String(inline_edit.item, "P_NOTES", new_text, true)
        reaper.GetSetMediaItemInfo_String(inline_edit.item, "P_NAME", "NOTA", true)
        reaper.UpdateItemInProject(inline_edit.item)
        reaper.Undo_EndBlock("ZP Studio Suite: modifica nota dal gobbo", -1)
    elseif mode == "subtitle" and inline_edit.item and new_text ~= "" and new_text ~= inline_edit.original then
        reaper.Undo_BeginBlock()
        reaper.GetSetMediaItemInfo_String(inline_edit.item, "P_NOTES", new_text, true)
        UpdateSubtitleItemName(inline_edit.item, new_text)
        reaper.Undo_EndBlock("ZP Studio Suite: modifica testo inline dal gobbo verticale", -1)
    end
    inline_edit = nil
    reaper.UpdateArrange()
    UpdateItems()
    RecalculateDocumentLayout()
end

function ProcessInlineSubtitleEditKey(char)
    if not inline_edit or char <= 0 then return false end
    if char == 13 then
        if (gfx.mouse_cap & 8) == 8 then
            InlineInsertText("\n")
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

function DrawInlineSubtitleEditor()
    if not inline_edit then return end
    local pad = 12
    local x = inline_edit.x
    local y = math.max(6, inline_edit.y)
    local w = math.min(inline_edit.w, gfx.w - x - 8)
    local line_h = inline_edit.font_size * 1.45
    inline_edit.line_h = line_h
    gfx.setfont(1, default_font, inline_edit.font_size)
    local title_h = inline_edit.title and 28 or 0
    local footer_h = 40
    local text_w = math.max(80, w - (pad * 2))
    inline_edit.text_w = text_w
    local lines = InlineVisualLines(text_w)
    local h = math.max(inline_edit.h, (#lines * line_h) + (pad * 2) + title_h + footer_h)
    if y + h > gfx.h - 8 then y = math.max(6, gfx.h - h - 8) end
    inline_edit.text_x = x + pad
    inline_edit.text_y = y + pad + title_h

    gfx.set(0.02, 0.02, 0.018, 0.96)
    gfx.rect(x, y, w, h, 1)
    gfx.set(1.0, 0.78, 0.18, 0.92)
    gfx.rect(x, y, w, 3, 1)
    if inline_edit.title then
        gfx.setfont(3, "Arial", 17, 'b')
        gfx.set(1.0, 0.82, 0.35, 1)
        gfx.x, gfx.y = x + pad, y + 10
        gfx.drawstr(inline_edit.title)
    end
    gfx.set(0.96, 0.91, 0.78, 1)
    for i, line in ipairs(lines) do
        gfx.x = x + pad
        gfx.y = inline_edit.text_y + ((i - 1) * line_h)
        local sel_a, sel_b = InlineSelectionRange()
        if sel_a then
            local a = math.max(sel_a, line.start)
            local b = math.min(sel_b, line.finish + 1)
            if a < b then
                local before_w = gfx.measurestr((inline_edit.text or ""):sub(line.start, a - 1))
                local sel_w = gfx.measurestr((inline_edit.text or ""):sub(a, b - 1))
                gfx.set(0.18, 0.44, 0.95, 0.55)
                gfx.rect(x + pad + before_w, inline_edit.text_y + ((i - 1) * line_h) - 2, math.max(2, sel_w), line_h, 1)
                gfx.set(0.96, 0.91, 0.78, 1)
            end
        end
        gfx.drawstr(line.text)
    end

    if (gfx.mouse_cap & 1) == 1 and not mouse_was_down then
        local text_bottom = inline_edit.text_y + (#lines * line_h)
        if gfx.mouse_x >= x + pad and gfx.mouse_x <= x + w - pad and gfx.mouse_y >= inline_edit.text_y and gfx.mouse_y <= text_bottom then
            local now = reaper.time_precise()
            InlineCursorFromPoint(gfx.mouse_x, gfx.mouse_y)
            if inline_edit.last_click_time and now - inline_edit.last_click_time < 0.35 then
                InlineSelectWordAtCursor()
            else
                inline_edit.drag_anchor = inline_edit.cursor
                inline_edit.dragging = true
            end
            inline_edit.last_click_time = now
        else
            inline_edit.dragging = false
        end
    end
    if (gfx.mouse_cap & 1) == 1 and inline_edit.dragging then
        local cursor = InlineCursorAtPoint(gfx.mouse_x, gfx.mouse_y)
        InlineSetSelection(inline_edit.drag_anchor or cursor, cursor)
    elseif (gfx.mouse_cap & 1) == 0 then
        inline_edit.dragging = false
    end

    local cursor = inline_edit.cursor or (#(inline_edit.text or "") + 1)
    local cursor_line = lines[#lines]
    local cursor_line_index = #lines
    for i, line in ipairs(lines) do
        if cursor >= line.start and cursor <= line.finish + 1 then
            cursor_line = line
            cursor_line_index = i
            break
        end
    end
    local cw = gfx.measurestr(inline_edit.text:sub(cursor_line.start, cursor - 1))
    local cursor_on = (math.floor(reaper.time_precise() * 2) % 2) == 0
    if cursor_on then
        gfx.set(1.0, 0.78, 0.18, 1)
        gfx.rect(x + pad + cw + 2, inline_edit.text_y + ((cursor_line_index - 1) * line_h), 2, line_h * 0.9, 1)
    end
    local button_y = y + h - 34
    local cancel_w, save_w = 92, 92
    if DrawButton(x + w - pad - cancel_w - save_w - 8, button_y, cancel_w, 24, "Annulla", 0.42, 0.20, 0.18) then
        inline_edit = nil
        return
    end
    if DrawButton(x + w - pad - save_w, button_y, save_w, 24, "Salva", 0.20, 0.48, 0.40, true) then
        SaveInlineSubtitleEdit()
        return
    end
    gfx.setfont(3, "Arial", 12)
    gfx.set(0.72, 0.66, 0.54, 0.96)
    gfx.x = x + pad
    gfx.y = button_y + 5
    gfx.drawstr("Invio salva  |  Shift+Invio accapo  |  Esc annulla")
end

function HandleSubtitleEditDoubleClick(item, x, y, w, h)
    local mx, my = gfx.mouse_x, gfx.mouse_y
    local hover = item and mx >= x and mx <= x + w and my >= y and my <= y + h
    local mouse_down = (gfx.mouse_cap & 1) == 1
    if hover and mouse_down and not mouse_was_down then
        local now = reaper.time_precise()
        if last_edit_click_item == item and now - last_edit_click_time <= 0.35 then
            last_edit_click_time = 0
            last_edit_click_item = nil
            StartInlineSubtitleEdit(item, x, y, w, h)
            return true
        end
        last_edit_click_time = now
        last_edit_click_item = item
    end
    return false
end

function HandleStudioItemClick(item, x, y, w, h)
    if not studio_edit_mode or inline_edit or search_panel_open then return end
    local mx, my = gfx.mouse_x, gfx.mouse_y
    local hover = item and mx >= x and mx <= x + w and my >= y and my <= y + h
    local mouse_down = (gfx.mouse_cap & 1) == 1
    if hover and mouse_down and not mouse_was_down then
        if studio_edit_sync then
            SelectSubtitleItemAndJump(item)
        else
            search_virtual_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            search_hit_item = item
            search_hit_until = reaper.time_precise() + 2.0
        end
    end
end

function DrawVerticalText(text, x, y, max_h, r, g, b, alpha)
    text = tostring(text or "")
    if text == "" then return end
    gfx.setfont(3, "Arial", 15, 'b')
    local _, ch_h = gfx.measurestr("M")
    local step = math.max(12, ch_h - 1)
    local max_chars = math.max(1, math.floor(max_h / step))
    if #text > max_chars then text = text:sub(1, max_chars) end
    if theme_mode == "dark" then
        gfx.set(1.0, 0.98, 0.92, alpha or 1)
    else
        gfx.set(0.035, 0.035, 0.032, alpha or 1)
    end
    for i=1, #text do
        local ch = text:sub(i, i)
        local tw = gfx.measurestr(ch)
        gfx.x = x + (18 - tw) / 2
        gfx.y = y + ((i - 1) * step)
        gfx.drawstr(ch)
    end
end

function DrawCharacterTags(item, x, y, end_y, is_active)
    local notes = item.person_notes or {}
    if #notes == 0 then return end
    local note = notes[1]
    if not note then return end

    local item_h = math.max(18, (end_y or (y + master_font_size)) - y)
    local shoulder_right = x - 8
    local bar_x = shoulder_right - 14
    local tag_w = 26
    local alpha = is_active and 0.95 or 0.42
    gfx.set(note.r, note.g, note.b, 0.16 + alpha * 0.22)
    gfx.rect(bar_x - tag_w + 2, y, tag_w, item_h, 1)
    gfx.set(note.r, note.g, note.b, alpha)
    gfx.rect(bar_x, y, 3, item_h, 1)
    gfx.rect(bar_x - tag_w + 2, y, tag_w + 5, 2, 1)
    gfx.rect(bar_x - tag_w + 2, y + item_h - 2, tag_w + 5, 2, 1)

    local label = trim(note.text or note.role or "")
    if label ~= "" and item_h >= 34 then
        DrawVerticalText(label, bar_x - tag_w + 6, y + 5, item_h - 10, note.r, note.g, note.b, math.min(0.95, alpha + 0.08))
    end
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
    local notes_w = notes_panel_open and 210 or 0
    local w = gfx.w - side_panel_w - notes_w
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
                table.insert(notes, { item=item, pos=pos, len=len, text=text, key=NormalizeName(text), r=r, g=g, b=b, color=color })
            end
        end
        table.sort(notes, function(a, b) return a.pos < b.pos end)
    end
    return notes
end

-- =============================================
function UpdateItems()
    local track = GetRythmoTrack()
    cached_regions = CollectRegions()
    cached_video_items = CollectVideoItems()
    cached_notes = CollectNotes()
    cached_character_notes = CollectCharacterNotes()
    BuildCharacterLanes()
    cached_items = {}
    if track then
        for i=0, reaper.CountTrackMediaItems(track)-1 do
            local item = reaper.GetTrackMediaItem(track, i)
            local pos   = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local len   = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local person_notes = CollectCharacterNotesForRange(pos, len)
            local has_note = #person_notes > 0

            local color = GetDisplayedItemColor(item, COLOR_SUBS)
            local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
            local _, highlight_raw = reaper.GetSetMediaItemInfo_String(item, "P_EXT:RythmoBand_HIGHLIGHT", "", false)
            
            local r, g, b = ColorToRGB(color, COLOR_SUBS)
            
            table.insert(cached_items, {item=item, pos=pos, len=len, notes=notes, highlights=ParseHighlightTerms(highlight_raw), has_note=has_note, person_notes=person_notes, r=r, g=g, b=b})
        end
        -- Ordine cronologico rigidissimo! È un copione.
        table.sort(cached_items, function(a, b) return a.pos < b.pos end)
    end
    
    RecalculateDocumentLayout()
end

-- =============================================
function DrawButton(x, y, w, h, label, hover_r, hover_g, hover_b, active)
    if sidebar_clip_top and (y + h < sidebar_clip_top or y > sidebar_clip_bottom) then
        return false
    end
    local mx, my = gfx.mouse_x, gfx.mouse_y
    local hover = (mx >= x and mx <= x+w and my >= y and my <= y+h)
    if sidebar_clip_top and (my < sidebar_clip_top or my > sidebar_clip_bottom) then hover = false end

    if active then
        if hover then gfx.set(0.18, 0.34, 0.62, 1)
        else gfx.set(0.10, 0.24, 0.50, 1) end
    elseif hover then
        gfx.set(hover_r or 0.3, hover_g or 0.3, hover_b or 0.5, 1)
    else
        gfx.set(0.18, 0.18, 0.25, 1)
    end
    gfx.rect(x, y, w, h, 1)

    if active then gfx.set(0.90, 0.90, 1.00, 1)
    else gfx.set(0.4, 0.4, 0.6, 1) end
    gfx.rect(x, y, w, h, 0)
    
    gfx.setfont(3, "Arial", 16, 'b')
    local tw, th = gfx.measurestr(label)
    gfx.x = x + (w - tw) / 2
    gfx.y = y + (h - th) / 2
    if active or hover then gfx.set(1, 1, 1, 1) else gfx.set(0.75, 0.75, 0.85, 1) end
    gfx.drawstr(label)
    
    return hover and (gfx.mouse_cap == 0) and mouse_was_down
end

function OpenSuiteHelp()
    local help_path = SCRIPT_DIR .. "help/index.html"
    local f = io.open(help_path, "r")
    if f then
        f:close()
    else
        reaper.ShowMessageBox("Help non trovato:\n\n" .. help_path, "ZP Studio Suite", 0)
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
        reaper.ShowMessageBox(text, "ZP Studio Suite - Gobbo", 0)
    end
end

function GobboAccessibleStatus()
    local lines = {
        "Stato gobbo.",
        "Timecode " .. (show_timecode and "visibile" or "nascosto") .. ".",
        "Tema " .. (theme_mode == "dark" and "scuro" or (theme_mode == "light" and "chiaro" or "medio")) .. ".",
        "Contrasto " .. (full_contrast and "pieno" or "sfumato") .. ".",
        "Flusso testi " .. CurrentTextFlowLabel() .. ".",
        "Parole " .. (word_follow and "attive" or "spente") .. ".",
        "Scorrimento " .. (fixed_block_mode and "fermo" or "attivo") .. ".",
        "Countdown " .. (countdown_alert and "attivo" or "spento") .. ".",
        "Pannello note " .. (notes_panel_open and "aperto" or "chiuso") .. ".",
        "Corpo testo " .. tostring(master_font_size) .. "."
    }
    return table.concat(lines, " ")
end

function OpenGobboAccessibleMenu()
    local prompt = table.concat({
        "1 Stato",
        "2 Mostra/Nascondi TC",
        "3 Flusso precedente",
        "4 Flusso successivo",
        "5 Parole ON/OFF",
        "6 Scorri ON/OFF",
        "7 Countdown ON/OFF",
        "8 Note ON/OFF",
        "9 Track Note VIS/NASC",
        "10 Track Gobbo VIS/NASC",
        "11 Aggiungi Track Gobbo",
        "12 Tema",
        "13 Contrasto",
        "14 Corpo -",
        "15 Corpo +",
        "16 Help"
    }, ", ")

    local ok, value = reaper.GetUserInputs(
        "ZP Studio Suite - Gobbo accessibile",
        1,
        prompt .. ",extrawidth=640",
        "1"
    )
    if not ok then return end

    local choice = tonumber((value or ""):match("%d+"))
    if not choice then
        GobboAccessibleSpeak("Scelta non valida.")
        return
    end

    if choice == 1 then
        GobboAccessibleSpeak(GobboAccessibleStatus())
        return
    elseif choice == 2 then
        show_timecode = not show_timecode
        SaveSettings()
        GobboAccessibleSpeak("Timecode " .. (show_timecode and "visibile." or "nascosto."))
    elseif choice == 3 then
        CycleTextFlow(-1)
        GobboAccessibleSpeak("Flusso testi " .. CurrentTextFlowLabel() .. ".")
    elseif choice == 4 then
        CycleTextFlow(1)
        GobboAccessibleSpeak("Flusso testi " .. CurrentTextFlowLabel() .. ".")
    elseif choice == 5 then
        word_follow = not word_follow
        SaveSettings()
        GobboAccessibleSpeak("Parole " .. (word_follow and "attive." or "spente."))
    elseif choice == 6 then
        fixed_block_mode = not fixed_block_mode
        SaveSettings()
        GobboAccessibleSpeak("Scorrimento " .. (fixed_block_mode and "fermo." or "attivo."))
    elseif choice == 7 then
        countdown_alert = not countdown_alert
        SaveSettings()
        GobboAccessibleSpeak("Countdown " .. (countdown_alert and "attivo." or "spento."))
    elseif choice == 8 then
        notes_panel_open = not notes_panel_open
        SaveSettings()
        RecalculateDocumentLayout()
        GobboAccessibleSpeak("Pannello note " .. (notes_panel_open and "aperto." or "chiuso."))
    elseif choice == 9 then
        ToggleNotesTrackVisibility()
        GobboAccessibleSpeak("Visibilita' traccia note aggiornata.")
    elseif choice == 10 then
        ToggleTextFlowTracksVisibility()
        GobboAccessibleSpeak("Visibilita' tracce gobbo aggiornata.")
    elseif choice == 11 then
        AddEmptyGobboTextItem()
        GobboAccessibleSpeak("Traccia gobbo vuota pronta.")
    elseif choice == 12 then
        if theme_mode == "dark" then theme_mode = "medium"
        elseif theme_mode == "medium" then theme_mode = "light"
        else theme_mode = "dark" end
        SaveSettings()
        GobboAccessibleSpeak("Tema " .. (theme_mode == "dark" and "scuro." or (theme_mode == "light" and "chiaro." or "medio.")))
    elseif choice == 13 then
        full_contrast = not full_contrast
        SaveSettings()
        GobboAccessibleSpeak("Contrasto " .. (full_contrast and "pieno." or "sfumato."))
    elseif choice == 14 then
        master_font_size = math.max(10, master_font_size - 1)
        SaveSettings()
        RecalculateDocumentLayout()
        GobboAccessibleSpeak("Corpo testo " .. tostring(master_font_size) .. ".")
    elseif choice == 15 then
        master_font_size = math.min(60, master_font_size + 1)
        SaveSettings()
        RecalculateDocumentLayout()
        GobboAccessibleSpeak("Corpo testo " .. tostring(master_font_size) .. ".")
    elseif choice == 16 then
        OpenSuiteHelp()
        GobboAccessibleSpeak("Apro help ZP Studio Suite.")
    else
        GobboAccessibleSpeak("Scelta non disponibile.")
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
    if not search_panel_open then return end
    local panel_w = math.min(560, math.max(330, w - 80))
    local panel_h = 62
    local x = math.floor((w - panel_w) / 2)
    local y = 36
    local pad = 10

    gfx.set(0.08, 0.075, 0.065, 0.96)
    gfx.rect(x, y, panel_w, panel_h, 1)
    gfx.set(0.72, 0.50, 0.12, 0.95)
    gfx.rect(x, y, panel_w, 2, 1)
    gfx.set(0.38, 0.34, 0.26, 0.8)
    gfx.rect(x, y, panel_w, panel_h, 0)

    gfx.setfont(3, "Arial", 13, 'b')
    gfx.set(0.78, 0.73, 0.62, 1)
    gfx.x, gfx.y = x + pad, y + 8
    gfx.drawstr("Trova")

    local input_x = x + 58
    local input_y = y + 24
    local input_w = panel_w - 206
    search_input_rect = {x=input_x, y=input_y, w=input_w, h=24}
    gfx.set(0.12, 0.11, 0.10, 1)
    gfx.rect(input_x, input_y, input_w, 24, 1)
    gfx.set(0.82, 0.58, 0.13, 1)
    gfx.rect(input_x, input_y, input_w, 24, 0)

    gfx.setfont(3, "Arial", 15)
    local shown = search_query ~= "" and search_query or "Cerca parola/frase..."
    gfx.x, gfx.y = input_x + 8, input_y + 4
    if search_query == "" then gfx.set(0.58, 0.55, 0.50, 0.9) else gfx.set(0.95, 0.92, 0.84, 1) end
    local sel_a, sel_b = SearchSelectionRange()
    if sel_a and search_query ~= "" then
        local before_w = gfx.measurestr((search_query or ""):sub(1, sel_a - 1))
        local sel_w = gfx.measurestr((search_query or ""):sub(sel_a, sel_b - 1))
        gfx.set(0.18, 0.44, 0.95, 0.55)
        gfx.rect(input_x + 8 + before_w, input_y + 3, math.max(2, sel_w), 18, 1)
        gfx.set(0.95, 0.92, 0.84, 1)
        gfx.x, gfx.y = input_x + 8, input_y + 4
    end
    gfx.drawstr(shown)
    if math.floor(reaper.time_precise() * 2) % 2 == 0 then
        local tw = gfx.measurestr((search_query or ""):sub(1, (search_cursor or (#(search_query or "") + 1)) - 1))
        gfx.set(0.95, 0.70, 0.18, 1)
        gfx.rect(input_x + 9 + tw, input_y + 5, 2, 15, 1)
    end

    local mouse_down = (gfx.mouse_cap & 1) == 1
    local over_input = gfx.mouse_x >= input_x and gfx.mouse_x <= input_x + input_w and gfx.mouse_y >= input_y and gfx.mouse_y <= input_y + 24
    if over_input and mouse_down and not mouse_was_down then
        local rel_x = math.max(0, gfx.mouse_x - input_x - 8)
        local best = 1
        for pos = 1, #(search_query or "") + 1 do
            local tw = gfx.measurestr((search_query or ""):sub(1, pos - 1))
            if rel_x < tw then break end
            best = pos
        end
        local now = reaper.time_precise()
        if search_last_click_time and now - search_last_click_time < 0.35 then
            SearchSetSelection(1, #(search_query or "") + 1)
        else
            SearchSetCursor(best)
        end
        search_last_click_time = now
    end

    if DrawButton(x + panel_w - 138, input_y, 30, 24, "<", 0.34, 0.25, 0.12) then ExecuteSubtitleSearch(-1) end
    if DrawButton(x + panel_w - 104, input_y, 30, 24, ">", 0.34, 0.25, 0.12) then ExecuteSubtitleSearch(1) end
    if DrawButton(x + panel_w - 68, input_y, 26, 24, "X", 0.45, 0.18, 0.14) then search_panel_open = false end

    if search_message ~= "" and reaper.time_precise() <= search_message_until then
        gfx.setfont(3, "Arial", 12)
        gfx.set(0.86, 0.78, 0.58, 0.95)
        gfx.x, gfx.y = x + panel_w - 140, y + 8
        gfx.drawstr(search_message)
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
function DrawSettingsPanel(w, h)
    local panel_y = h - (PANEL_H * panel_anim)
    
    gfx.set(0.08, 0.08, 0.14, 0.97)
    gfx.rect(0, panel_y, w, PANEL_H, 1)
    gfx.set(0.3, 0.3, 0.7, panel_anim)
    gfx.rect(0, panel_y, w, 2, 1)
    
    local alpha = panel_anim
    if alpha < 0.05 then return panel_y end

    gfx.setfont(3, "Arial", 15, 'b')
    gfx.set(0.5, 0.5, 0.8, alpha)
    gfx.x, gfx.y = 14, panel_y + 8
    gfx.drawstr("IMPOSTAZIONI GOBBO")
    
    gfx.set(0.25, 0.25, 0.4, alpha)
    gfx.line(0, panel_y + 32, w, panel_y + 32)
    
    local row_y = panel_y + 40
    local col1_x = 14
    local changed = false
    
    -- === SEZIONE MAX FONT ===
    gfx.setfont(3, "Arial", 14, 'b')
    gfx.set(0.6, 0.7, 1.0, alpha)
    gfx.x, gfx.y = col1_x, row_y
    gfx.drawstr("CORPO TESTO")
    
    gfx.setfont(3, "Arial", 20, 'b')
    gfx.set(1, 1, 1, alpha)
    local font_val = string.format("%d", master_font_size)
    gfx.x, gfx.y = col1_x + 120, row_y - 3
    gfx.drawstr(font_val)
    
    local b_fm = DrawButton(col1_x,       row_y + 22, 40, 28, "-", 0.6, 0.2, 0.2)
    local b_fv = DrawButton(col1_x + 46,  row_y + 22, 74, 28, tostring(master_font_size), 0.2, 0.3, 0.5, true)
    local b_fp = DrawButton(col1_x + 126, row_y + 22, 40, 28, "+", 0.2, 0.5, 0.2)
	    
    if b_fm then master_font_size = math.max(10, master_font_size - 1); changed = true end
    if b_fp then master_font_size = math.min(60, master_font_size + 1); changed = true end
    if b_fv then show_settings_timer = 60 end
    
    if changed then 
        show_settings_timer = 60 
        SaveSettings()
        RecalculateDocumentLayout() 
    end
    
    return panel_y
end

function DrawSidePanel(w, h, tc_position, tc_alert_item, tc_alert_flash)
    local x = w - side_panel_w
    local pad = 12
    local header_h = 88
    local y = header_h - sidebar_scroll_y
    local clip_top = header_h
    local clip_bottom = h

    SetThemeColor("panel", 0.98)
    gfx.rect(x, 0, side_panel_w, h, 1)
    SetThemeColor("panel_line", 1)
    gfx.rect(x, 0, 1, h, 1)

    sidebar_clip_top = clip_top
    sidebar_clip_bottom = clip_bottom

    local tc_label = show_timecode and "Nascondi TC" or "Mostra TC"
    if DrawButton(x + pad, y, side_panel_w - pad * 2, 24, tc_label, 0.25, 0.32, 0.42, show_timecode) then
        show_timecode = not show_timecode
        SaveSettings()
    end

    y = y + 32
    if DrawButton(x + pad, y, side_panel_w - pad * 2, 24, "OSARA Menu", 0.20, 0.42, 0.50, false) then
        OpenGobboAccessibleMenu()
    end

    y = y + 36
    gfx.setfont(3, "Arial", 13)
    SetThemeColor("dim", 0.95)
    gfx.x, gfx.y = x + pad, y
    local theme_name = theme_mode == "dark" and "Scuro" or (theme_mode == "light" and "Chiaro" or "Medio")
    gfx.drawstr("Tema: " .. theme_name)
    y = y + 18

    if DrawButton(x + pad, y, 50, 26, "Scuro", 0.22, 0.22, 0.28, theme_mode == "dark") then
        theme_mode = "dark"
        SaveSettings()
    end
    if DrawButton(x + pad + 55, y, 54, 26, "Medio", 0.52, 0.48, 0.35, theme_mode == "medium") then
        theme_mode = "medium"
        SaveSettings()
    end
    if DrawButton(x + pad + 114, y, 54, 26, "Chiaro", 0.72, 0.72, 0.72, theme_mode == "light") then
        theme_mode = "light"
        SaveSettings()
    end

    y = y + 46
    SetThemeColor("dim", 0.95)
    gfx.x, gfx.y = x + pad, y
    gfx.drawstr("Contrasto: " .. (full_contrast and "Pieno" or "Sfumato"))
    y = y + 18

    if DrawButton(x + pad, y, 76, 26, "Sfumato", 0.28, 0.28, 0.34, not full_contrast) then
        full_contrast = false
        SaveSettings()
    end
    if DrawButton(x + pad + 84, y, 76, 26, "Pieno", 0.42, 0.34, 0.18, full_contrast) then
        full_contrast = true
        SaveSettings()
    end

    y = y + 46
    gfx.setfont(3, "Arial", 12)
    SetThemeColor("dim", 0.95)
    gfx.x, gfx.y = x + pad, y
    gfx.drawstr("Flusso testi")
    local flow_y = y + 17
    if DrawButton(x + pad, flow_y, 28, 24, "<", 0.22, 0.30, 0.42) then CycleTextFlow(-1) end
    if DrawButton(x + side_panel_w - pad - 28, flow_y, 28, 24, ">", 0.22, 0.30, 0.42) then CycleTextFlow(1) end
    gfx.setfont(3, "Arial", 13, 'b')
    SetThemeColor("active", 0.95)
    local flow_label = CurrentTextFlowLabel()
    if #flow_label > 16 then flow_label = flow_label:sub(1, 15) .. "." end
    local flow_tw, flow_th = gfx.measurestr(flow_label)
    gfx.x = x + pad + 34 + (((side_panel_w - pad * 2) - 68) - flow_tw) / 2
    gfx.y = flow_y + (24 - flow_th) / 2
    gfx.drawstr(flow_label)

    y = y + 51
    SetThemeColor("dim", 0.95)
    gfx.x, gfx.y = x + pad, y
    gfx.drawstr("Punto lettura")
    y = y + 18

    if DrawButton(x + pad, y, 48, 26, "Alto", 0.22, 0.30, 0.42, math.abs(reading_point - 0.18) < 0.01) then
        reading_point = 0.18
        SaveSettings()
    end
    if DrawButton(x + pad + 54, y, 58, 26, "Medio", 0.22, 0.30, 0.42, math.abs(reading_point - 0.34) < 0.01) then
        reading_point = 0.34
        SaveSettings()
    end
    if DrawButton(x + pad + 118, y, 48, 26, "Centro", 0.22, 0.30, 0.42, math.abs(reading_point - 0.50) < 0.01) then
        reading_point = 0.50
        SaveSettings()
    end

    y = y + 46
    local word_label = word_follow and "Parole ON" or "Parole OFF"
    if DrawButton(x + pad, y, side_panel_w - pad * 2, 28, word_label, 0.36, 0.29, 0.12, word_follow) then
        word_follow = not word_follow
        SaveSettings()
    end

    y = y + 34
    local fixed_label = fixed_block_mode and "Scorri OFF" or "Scorri ON"
    if DrawButton(x + pad, y, side_panel_w - pad * 2, 28, fixed_label, 0.22, 0.38, 0.52, not fixed_block_mode) then
        fixed_block_mode = not fixed_block_mode
        SaveSettings()
    end

    y = y + 34
    if DrawButton(x + pad, y, side_panel_w - pad * 2, 28, CountdownAlertLabel(), 0.38, 0.31, 0.10, countdown_alert) then
        countdown_alert = not countdown_alert
        SaveSettings()
    end

    y = y + 34
    local notes_label = notes_panel_open and "Note ON" or "Note OFF"
    if DrawButton(x + pad, y, side_panel_w - pad * 2, 28, notes_label, 0.38, 0.31, 0.10, notes_panel_open) then
        notes_panel_open = not notes_panel_open
        SaveSettings()
        RecalculateDocumentLayout()
    end

    y = y + 34
    if DrawButton(x + pad, y, side_panel_w - pad * 2, 28, NotesTrackLabel(), 0.30, 0.30, 0.38, IsTrackVisible(FindTrackByName(notes_track_name))) then
        ToggleNotesTrackVisibility()
    end

    y = y + 34
    if DrawButton(x + pad, y, side_panel_w - pad * 2, 28, TextFlowTracksLabel(), 0.30, 0.30, 0.38, AnyTextFlowTrackVisible()) then
        ToggleTextFlowTracksVisibility()
    end

    y = y + 34
    if DrawButton(x + pad, y, side_panel_w - pad * 2, 28, "+ Track Gobbo", 0.20, 0.48, 0.40) then
        AddEmptyGobboTextItem()
    end

    y = y + 38
    y = DrawSpeakerPalette(x + pad, y, side_panel_w - pad * 2)

    y = y + 24
    SetThemeColor("dim", 0.95)
    gfx.x, gfx.y = x + pad, y
    gfx.drawstr("Corpo")
    gfx.setfont(3, "Arial", 20, 'b')
    SetThemeColor("active", 0.95)
    local font_value = tostring(master_font_size)
    local fw = gfx.measurestr(font_value)
    gfx.x, gfx.y = x + side_panel_w - pad - fw, y - 4
    gfx.drawstr(font_value)
    y = y + 20

    if DrawButton(x + pad, y, 42, 28, "-", 0.45, 0.20, 0.20) then
        master_font_size = math.max(10, master_font_size - 1)
        SaveSettings()
        RecalculateDocumentLayout()
    end
    if DrawButton(x + pad + 48, y, 74, 28, tostring(master_font_size), 0.22, 0.30, 0.42, true) then
        -- Solo display: il valore si cambia con -/+.
    end
    if DrawButton(x + pad + 128, y, 42, 28, "+", 0.20, 0.45, 0.20) then
        master_font_size = math.min(60, master_font_size + 1)
        SaveSettings()
        RecalculateDocumentLayout()
    end

    y = y + 42
    SetThemeColor("dim", 0.95)
    gfx.setfont(3, "Arial", 13)
    gfx.x, gfx.y = x + pad, y
    gfx.drawstr("Comandi")
    y = y + 18

    local studio_label = studio_edit_mode and "Studio/Edit ON" or "Studio/Edit OFF"
    if DrawButton(x + pad, y, side_panel_w - pad * 2, 24, studio_label, 0.20, 0.48, 0.40, studio_edit_mode) then
        studio_edit_mode = not studio_edit_mode
        if studio_edit_mode then
            reaper.OnStopButton()
            fixed_block_mode = false
        end
        SaveSettings()
    end
    y = y + 30

    if studio_edit_mode then
        local sync_label = studio_edit_sync and "Sync ON" or "Sync OFF"
        if DrawButton(x + pad, y, side_panel_w - pad * 2, 24, sync_label, 0.20, 0.38, 0.58, studio_edit_sync) then
            studio_edit_sync = not studio_edit_sync
            SaveSettings()
        end
        y = y + 30
    end

    if DrawButton(x + pad, y, side_panel_w - pad * 2, 24, "Cerca", 0.25, 0.32, 0.42) then
        PromptSubtitleSearch()
    end
    y = y + 30
    if DrawButton(x + pad, y, side_panel_w - pad * 2, 24, "Nota", 0.36, 0.30, 0.14) then
        InsertNoteAtCurrentPosition()
    end
    y = y + 30
    if DrawButton(x + pad, y, side_panel_w - pad * 2, 24, "MOD NOTE", 0.38, 0.31, 0.10) then
        EditNearestNote()
    end
    y = y + 30
    if DrawButton(x + pad, y, side_panel_w - pad * 2, 24, "DEL NOTE", 0.48, 0.18, 0.14) then
        DeleteNearestNote()
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

    gfx.setfont(3, "Arial", 12)
    SetThemeColor("active", 0.95)
    gfx.x, gfx.y = x + pad, 31
    gfx.drawstr("ZP Studio Suite v1.0.5")
    gfx.x, gfx.y = x + pad, 45
    gfx.drawstr("Paolo Balestri & Nicola Lanci")

    DrawHelpButton(x + side_panel_w - pad - 28, 10)
end

function DrawTimecodeHud(notes_w, tc_position)
    if not show_timecode then return end
    local tc_text = FormatVideoTimecode(tc_position or GetCurrentProjectPosition())
    gfx.setfont(3, "Arial", math.max(14, master_font_size - 2), 'b')
    local tw, th = gfx.measurestr(tc_text)
    local x = notes_w + 14
    local y = 12
    gfx.set(0, 0, 0, 1)
    gfx.rect(x - 10, y - 7, tw + 20, th + 14, 1)
    gfx.set(0, 0, 0, 1)
    gfx.rect(x - 8, y - 5, tw + 16, th + 10, 1)
    gfx.set(0.82, 0.82, 0.82, 1)
    gfx.rect(x - 8, y - 5, tw + 16, th + 10, 0)
    gfx.set(1, 1, 1, 1)
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
            local progress = math.max(0, math.min(1, (doc_y - item.doc_start_y) / denom))
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
    if char > 0 then
        local changed = false
        if char == 9 then panel_open = not panel_open
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
    gfx.mouse_wheel = 0

    local w, h = gfx.w, gfx.h
    SaveWindowStateIfChanged()
    if w ~= last_win_w then
        last_win_w = w
        RecalculateDocumentLayout()
    end

    local over_sidebar = gfx.mouse_x >= w - side_panel_w and gfx.mouse_x <= w and gfx.mouse_y >= 0 and gfx.mouse_y <= h
    if wheel ~= 0 and over_sidebar then
        local max_sidebar_scroll = math.max(0, (sidebar_content_h or 0) - h)
        sidebar_scroll_y = math.max(0, math.min(sidebar_scroll_y + (wheel > 0 and -42 or 42), max_sidebar_scroll))
        wheel = 0
    elseif (sidebar_content_h or 0) <= h then
        sidebar_scroll_y = 0
    else
        sidebar_scroll_y = math.max(0, math.min(sidebar_scroll_y, math.max(0, sidebar_content_h - h)))
    end

    local track = GetRythmoTrack()
    local track_guid = track and reaper.GetTrackGUID(track) or ""
    local proj_state = reaper.GetProjectStateChangeCount(0)

    if proj_state ~= last_proj_state or track_guid ~= last_track_guid then
        last_proj_state = proj_state
        last_track_guid = track_guid
        UpdateItems()
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

    local notes_w = notes_panel_open and NOTES_PANEL_W or 0
    local read_w = math.max(320, w - side_panel_w - notes_w)
    local text_x = notes_w + document_margin_x + speaker_shoulder_w
    local reading_y = h * reading_point
    local tc_alert_item = FindUpcomingCue(smoothed_play_pos)
    local tc_alert_flash = tc_alert_item and (math.floor(reaper.time_precise() * 4) % 2 == 0)

    local panel_target = panel_open and 1.0 or 0.0
    panel_anim = lerp(panel_anim, panel_target, panel_anim_speed)
    if math.abs(panel_anim - panel_target) < 0.001 then panel_anim = panel_target end

    local teleprompter_bottom = h - (PANEL_H * panel_anim)

    SetThemeColor("bg", 1)
    gfx.rect(notes_w, 0, read_w, teleprompter_bottom, 1)
    DrawNotesPanel(teleprompter_bottom, smoothed_play_pos, reading_y)

    if #cached_items == 0 then
        gfx.setfont(1, "Arial", 18)
        gfx.set(0.4, 0.4, 0.4, 1)
        local warn_text = "Seleziona la traccia Copione!"
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
    active_media_item = nil
    active_progress = 0.0
    
    for i, item in ipairs(cached_items) do
        -- Se il playhead è DENTRO l'item
        if smoothed_play_pos >= item.pos and smoothed_play_pos <= item.pos + item.len then
            -- Calcoliamo a che percentuale dell'item audio ci troviamo
            local item_progress = (smoothed_play_pos - item.pos) / item.len
            active_progress = item_progress
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
                local pixel_progress = item.pixel_height * item_progress
                target_scroll_y = (item.doc_start_y + pixel_progress) - reading_y
            end
            found_active = true
            active_media_item = item.item
            break
        end
        
        -- Se il playhead si trova nel GAP tra questo item e il SUCCESSIVO
        if not found_active and i < #cached_items then
            local next_item = cached_items[i+1]
            if smoothed_play_pos > item.pos + item.len and smoothed_play_pos < next_item.pos then
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
    elseif not found_active and #cached_items > 0 and smoothed_play_pos > cached_items[#cached_items].pos + cached_items[#cached_items].len then
        -- Scroll fermo sull'ultimo item se superato
        target_scroll_y = (fixed_block_mode and cached_items[#cached_items].doc_start_y or cached_items[#cached_items].doc_end_y) - reading_y
        if fixed_block_mode then static_display_item = cached_items[#cached_items] end
    end

    if studio_edit_mode and (not studio_edit_sync or edit_scroll_dragging or edit_scroll_was_dragging) then
        local over_document = gfx.mouse_x >= notes_w and gfx.mouse_x <= notes_w + read_w and gfx.mouse_y >= 0 and gfx.mouse_y <= teleprompter_bottom
        if wheel ~= 0 and over_document then
            local step = math.max(42, master_font_size * 2.2)
            document_scroll_y = document_scroll_y + (wheel > 0 and -step or step)
            if studio_edit_sync then JumpTimelineFromDocumentScroll(teleprompter_bottom) end
        end
        document_scroll_y = ClampDocumentScroll(document_scroll_y, teleprompter_bottom)
    else
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
            local is_active = (smoothed_play_pos >= item.pos and smoothed_play_pos <= item.pos + item.len)
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
            
            if is_active then
                SetThemeColor("active", 1.0)
            elseif is_sfumato_ready then
                SetThemeColor("active", 0.86)
            elseif full_contrast then
                SetThemeColor("text", 0.92)
            else
                SetThemeColor("dim", 0.48)
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
            HandleSubtitleEditDoubleClick(item.item, text_x - 8, start_py - 4, edit_w, math.max(line_h, end_py - start_py))
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
        local hud_txt = string.format("FONT COPIONE: %d", master_font_size)
        local tw, th = gfx.measurestr(hud_txt)
        
        gfx.set(0, 0, 0, 0.7 * hud_alpha)
        gfx.rect(10, 10, tw + 20, th + 10, 1)
        gfx.set(1, 1, 1, hud_alpha)
        gfx.x, gfx.y = 20, 15
        gfx.drawstr(hud_txt)
        show_settings_timer = show_settings_timer - 1
    end

    if panel_anim > 0.01 then DrawSettingsPanel(w, h) end
    DrawSidePanel(w, h, smoothed_play_pos, tc_alert_item, tc_alert_flash)
    sidebar_scroll_y = math.max(0, math.min(sidebar_scroll_y, math.max(0, (sidebar_content_h or 0) - h)))
    DrawTimecodeHud(notes_w, smoothed_play_pos)
    DrawInlineSubtitleEditor()
    DrawSearchPanel(w, h)

    mouse_was_down = (gfx.mouse_cap & 1) == 1
    gfx.update()
    reaper.defer(DrawGUI)
end

LoadSettings()
InitGUI()
DrawGUI()
