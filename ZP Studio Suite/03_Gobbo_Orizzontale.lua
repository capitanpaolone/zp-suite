-- @noindex

--[[
   * ReaScript Name: ZP Studio Suite GUI Nativa
   * Linea: ZP Paolo Balestri
   * Suite: ZP Studio Suite for REAPER v1.0.5
   * Credito idea gobbo: da un'idea di Nicola Lanci.
   * Distribuzione gratuita.
   * Description: Finestra fluida nativa integrata in REAPER (stile HeDa Notes Reader).
	                  v11.1 - Gobbo orizzontale guidato a parole, TC centrale,
	                          zona lettura elastica e indicazione speaker monovoce.
]]

local default_track_name = "Rythmo Band Testi"
local notes_track_name = "Rythmo Band Note"
local gobbo_state_section = "RythmoBand_Gobbo_State"
local gobbo_state_key = "horizontal_ts"
local gobbo_settings_section = "ZP_VoiceOver_Studio_Gobbo_Orizzontale"
local speech_lead_key = "accessibility_speech_lead"
local studio_mode_key = "studio_edit_mode"
local SCRIPT_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "")
local NVDA_BRIDGE_PATH = SCRIPT_DIR .. "ZP_NVDA_Speech.py"
local NVDA_DLL_PATH = SCRIPT_DIR .. "nvdaControllerClient64.dll"
local cached_items = {}
local cached_notes = {}
local cached_character_notes = {}
local cached_regions = {}
local cached_video_items = {}
local last_proj_state = -1
local last_track_guid = ""
local selected_text_track_guid = ""
local current_text_track = nil
local current_text_flow_label = "Nessun testo"
local cached_project_fps = 25
local global_max_y = 0
local tape_origin_pos = 0

-- Impostazioni
local default_font = "Arial"
local master_font_size = 44
local pixels_per_second = 200
local show_settings_timer = 0
local show_timecode = true
local max_character_rows = 1
local alert_strip_h = 58
local attack_x_ratio = 0.34
local word_pre_roll = 5.0
local word_post_roll = 3.0
local horizontal_text_lanes = 2
local smooth_scroll_pos = nil
local character_lane_by_key = {}
local NOTE_WAKE_LEAD = 5.0
local NOTE_HOT_MARGIN = 0.35
local COLOR_SUBS = 0x3498DB
local COLOR_NOTES = 0xF2C94C
local character_note_prefix = "BB Note Personaggio - "

-- === PANNELLO IMPOSTAZIONI ===
local panel_open = false
local panel_anim  = 0.0
local PANEL_H = 110
local panel_anim_speed = 0.18
local mouse_was_down = false
local last_edit_click_time = 0
local last_edit_click_item = nil
local inline_edit = nil
local inline_clipboard = ""
local search_query = ""
local search_hit_item = nil
local search_hit_until = 0
local search_panel_open = false
local search_message = ""
local search_message_until = 0
local search_virtual_pos = nil
local osara_text_enabled = true
local accessibility_speech_lead = 0.0
local studio_edit_mode = false
local osara_last_key = ""
local osara_last_time = 0
local nvda_python_command = nil
local manual_view_pos = nil

-- Variabili per Play Pos Interpolation
local playback_anchor_pos = nil
local playback_anchor_time = 0
local last_play_state = 0

function lerp(a, b, t) return a + (b - a) * t end

function Clamp(value, min_value, max_value)
    if value < min_value then return min_value end
    if value > max_value then return max_value end
    return value
end

function SmoothStep(t)
    t = Clamp(t or 0, 0, 1)
    return t * t * (3 - (2 * t))
end

function OsaraActive()
    return type(reaper.osara_outputMessage) == "function"
end

function FileExists(path)
    local file = io.open(path, "rb")
    if file then file:close() return true end
    return false
end

function IsWindows()
    local os_name = reaper.GetOS and reaper.GetOS() or ""
    return os_name:match("^Win") ~= nil
end

function ShellQuote(value)
    value = tostring(value or "")
    if IsWindows() then
        return '"' .. value:gsub('"', '\\"') .. '"'
    end
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

function NvdaAvailable()
    return IsWindows()
        and FileExists(NVDA_BRIDGE_PATH)
        and FileExists(NVDA_DLL_PATH)
        and type(reaper.ExecProcess) == "function"
end

function NvdaPythonCommand()
    if nvda_python_command then return nvda_python_command end
    nvda_python_command = "py -3"
    return nvda_python_command
end

function NvdaSpeak(text)
    if not NvdaAvailable() then return false end
    text = CleanOsaraText(text)
    if text == "" then return false end
    local command = NvdaPythonCommand() .. " " .. ShellQuote(NVDA_BRIDGE_PATH) .. " --speak " .. ShellQuote(text)
    pcall(reaper.ExecProcess, command, 300)
    return true
end

function AccessibilitySpeechActive()
    return OsaraActive() or NvdaAvailable()
end

function SpeakAccessibilityText(text)
    text = CleanOsaraText(text)
    if text == "" then return end
    if OsaraActive() then
        reaper.osara_outputMessage(text)
    elseif NvdaAvailable() then
        NvdaSpeak(text)
    end
end

function CleanOsaraText(text)
    return trim((text or ""):gsub("[\r\n]+", " "):gsub("%s+", " "))
end

function SetHorizontalScale(value)
    pixels_per_second = math.max(100, math.min(500, math.floor((value or pixels_per_second) + 0.5)))
end

function SetFontSize(value)
    master_font_size = math.max(22, math.min(72, math.floor((value or master_font_size) + 0.5)))
end

function SetAccessibilitySpeechLead(value)
    accessibility_speech_lead = math.max(0, math.min(10, tonumber(value) or 0))
    osara_last_key = ""
    osara_last_time = 0
    reaper.SetExtState(gobbo_settings_section, speech_lead_key, string.format("%.2f", accessibility_speech_lead), true)
end

function SetStudioEditMode(value)
    studio_edit_mode = value and true or false
    reaper.SetExtState(gobbo_settings_section, studio_mode_key, studio_edit_mode and "1" or "0", true)
end

function LoadHorizontalSettings()
    local saved_lead = tonumber(reaper.GetExtState(gobbo_settings_section, speech_lead_key))
    if saved_lead then accessibility_speech_lead = math.max(0, math.min(10, saved_lead)) end
    local saved_studio = reaper.GetExtState(gobbo_settings_section, studio_mode_key)
    if saved_studio == "1" then studio_edit_mode = true
    elseif saved_studio == "0" then studio_edit_mode = false end
end

function GetContinuousPlayPosition()
    local play_state = reaper.GetPlayState()
    local is_playing = (play_state & 1) == 1
    local now = reaper.time_precise()

    if not is_playing then
        playback_anchor_pos = nil
        last_play_state = play_state
        smooth_scroll_pos = manual_view_pos or reaper.GetCursorPosition()
        return smooth_scroll_pos, false
    end

    local raw_pos = reaper.GetPlayPosition()
    local play_rate = reaper.Master_GetPlayRate(0)
    if not play_rate or play_rate <= 0 then play_rate = 1 end

    if not playback_anchor_pos or (last_play_state & 1) ~= 1 then
        playback_anchor_pos = raw_pos
        playback_anchor_time = now
        last_play_state = play_state
        smooth_scroll_pos = raw_pos
        return raw_pos, true
    end

    local predicted = playback_anchor_pos + ((now - playback_anchor_time) * play_rate)
    local drift = math.abs(raw_pos - predicted)

    -- Aggancia di nuovo solo quando c'e' un vero salto/seek, non sui micro-gradini audio/UI.
    if drift > 0.08 then
        playback_anchor_pos = raw_pos
        playback_anchor_time = now
        predicted = raw_pos
    end

    last_play_state = play_state
    smooth_scroll_pos = predicted
    return predicted, true
end

function InitGUI()
    gfx.clear = 0x111111 
    gfx.init("ZP Studio Suite v1.0.5 - Gobbo Orizzontale", 1100, 300, 0, 100, 100)
    gfx.setfont(1, default_font, master_font_size, 'b')
end

function trim(s)
    local out = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return out
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
    if color == 0 then color = NativeColor(fallback or COLOR_NOTES) end
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

function FindTrackByName(name)
    for i=0, reaper.CountTracks(0)-1 do
        local track = reaper.GetTrack(0, i)
        local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if track_name == name or track_name:find(name) then return track end
    end
    return nil
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

function PairedVoiceTrack(note_track)
    local idx = GetTrackIndex(note_track)
    if not idx or idx <= 0 or idx == 999999 then return nil end
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
    if not IsValidTrack(track) then return "" end
    if not track then return "" end
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    return trim(name)
end

function IsValidTrack(track)
    if not track then return false end
    if reaper.ValidatePtr2 then return reaper.ValidatePtr2(0, track, "MediaTrack*") end
    return true
end

function IsTextFlowTrackName(name)
    return (name or ""):find(default_track_name, 1, true) == 1
end

function CollectTextFlowTracks()
    local tracks = {}
    for i=0, reaper.CountTracks(0)-1 do
        local track = reaper.GetTrack(0, i)
        local name = GetTrackName(track)
        if IsTextFlowTrackName(name) then
            table.insert(tracks, {track=track, name=name, guid=reaper.GetTrackGUID(track), index=i})
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

function TextFlowDisplayName(name)
    name = trim(name or "")
    if name == default_track_name then return "Principale" end
    if name:find(default_track_name, 1, true) == 1 then
        local suffix = trim(name:sub(#default_track_name + 1))
        if suffix ~= "" then return suffix end
    end
    return name ~= "" and name or "Nessuno"
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

function GetTrackIndex(track)
    if not track then return 999999 end
    for i=0, reaper.CountTracks(0)-1 do
        if reaper.GetTrack(0, i) == track then return i end
    end
    return 999999
end

function FindRoleTrackOrder(note_track_index, role_key)
    for i=note_track_index-1, 0, -1 do
        local track = reaper.GetTrack(0, i)
        local name = GetTrackName(track)
        if NormalizeName(name) == role_key then return i end
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

function GetProjectFPS()
    local fps = 25
    if reaper.TimeMap_curFrameRate then fps = reaper.TimeMap_curFrameRate(0) end
    if not fps or fps <= 0 then fps = 25 end
    return fps
end

function FormatTimecode(seconds)
    local fps = cached_project_fps or 25
    local frame_base = math.max(1, math.floor(fps + 0.5))
    local time_val = math.max(0, seconds or 0)
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

function FindVideoItemForPosition(pos)
    for _, video in ipairs(cached_video_items) do
        if pos >= video.pos and pos <= video.pos + video.len then return video end
    end
    return nil
end

function FormatVideoTimecode(project_seconds)
    local pos = project_seconds or 0
    local region = FindRegionForPosition(pos)
    if region then return FormatTimecode(pos - region.pos) end
    local video = FindVideoItemForPosition(pos)
    if video then return FormatTimecode(pos - video.pos) end
    return FormatTimecode(pos)
end

function CollectNotes()
    local notes = {}
    local track = FindTrackByName(notes_track_name)
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
                table.insert(notes, {pos=pos, len=len, text=text, key=NormalizeName(text), r=r, g=g, b=b, color=color})
            end
        end
        table.sort(notes, function(a, b) return a.pos < b.pos end)
    end
    return notes
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
                    table.insert(notes, {pos=pos, len=len, text=role_name, note_text=text, role=role_name, key=role_key, track_order=track_order, note_track_order=t, r=r, g=g, b=b, color=color})
                end
            end
        end
    end
    table.sort(notes, function(a, b) return a.pos < b.pos end)
    return notes
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

function SplitWords(text)
    local words = {}
    for word in (text or ""):gmatch("%S+") do table.insert(words, word) end
    if #words == 0 then table.insert(words, "") end
    return words
end

function ExtractSpeakerPrefix(text)
    local clean = trim(text or "")
    local colon_pos = clean:find(":", 1, true)
    if not colon_pos or colon_pos < 2 or colon_pos > 28 then return "", clean end

    local prefix = trim(clean:sub(1, colon_pos))
    local body = trim(clean:sub(colon_pos + 1))
    if body == "" then return "", clean end
    return prefix, body
end

-- =============================================
function RecalculateLayout()
    local text_line_h = master_font_size * 1.15
    local lane_slot_height = master_font_size * 1.35 + 20
    tape_origin_pos = cached_items[1] and cached_items[1].pos or 0

    for _, item in ipairs(cached_items) do
        item.font_size = master_font_size
        gfx.setfont(1, default_font, item.font_size, 'b')
        
        local display_text = (item.notes or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
        local measure_text = display_text:gsub("[\r\n]+", " ")
        item.speaker_prefix, item.read_text = ExtractSpeakerPrefix(display_text)
        local prefix_w = item.speaker_prefix ~= "" and gfx.measurestr(item.speaker_prefix .. " ") or 0
        local tw, _ = gfx.measurestr(item.read_text)
        item.words = SplitWords(item.read_text)
        item.total_words = math.max(1, #item.words)
        item.word_x = {}
        item.word_w = {}
        local cursor_x = 0
        local space_w = gfx.measurestr(" ")
        for i, word in ipairs(item.words) do
            item.word_x[i] = cursor_x
            local ww = gfx.measurestr(word)
            item.word_w[i] = ww
            cursor_x = cursor_x + ww + space_w
        end
        item.prefix_w = prefix_w
        item.text_w = prefix_w + math.max(tw, math.max(0, cursor_x - space_w))
        local natural_w = item.text_w + 72
        item.box_w = math.max(120, natural_w)
        item.tape_w = math.max(80, item.text_w + 42)
        local scroll_distance = math.max(80, item.text_w + 70)
        local scroll_duration = math.max(0.20, item.len or 0)
        item.scroll_pps = math.max(80, scroll_distance / scroll_duration)
        item.line_h = item.font_size * 1.15
        item.lines = { item.read_text }
        item.line_words = { item.words }
        item.box_h = item.line_h + 18
        lane_slot_height = math.max(lane_slot_height, item.box_h + 10)

        local timeline_x = (item.pos - tape_origin_pos) * pixels_per_second
        -- Il gobbo orizzontale deve restare agganciato al timecode:
        -- se spingiamo avanti il titolo successivo per evitare sovrapposizioni,
        -- la lettura slitta rispetto al verticale e all'audio.
        item.tape_x = timeline_x
    end

    local max_h = 0
    local lane_ends = {}
    for lane = 1, horizontal_text_lanes do lane_ends[lane] = -math.huge end

    for _, item in ipairs(cached_items) do
        local item_start = (item.tape_x or 0) - 18
        local item_end = item_start + (item.tape_w or item.box_w or 120) + 18
        local best_lane = 1
        local best_end = lane_ends[1] or -math.huge

        for lane = 1, horizontal_text_lanes do
            if item_start >= (lane_ends[lane] or -math.huge) then
                best_lane = lane
                best_end = lane_ends[lane]
                break
            end
            if (lane_ends[lane] or math.huge) < best_end then
                best_lane = lane
                best_end = lane_ends[lane]
            end
        end

        item.lane = best_lane
        item.y_offs = (best_lane - 1) * lane_slot_height
        lane_ends[best_lane] = item_end

        local item_bottom = item.y_offs + item.box_h
        if item_bottom > max_h then max_h = item_bottom end
    end
    
    global_max_y = max_h
end

function GetRythmoTrack()
    local selected = FindTextFlowByGuid(selected_text_track_guid)
    if selected then return selected.track end

    local exact = FindTrackByName(default_track_name)
    if exact and IsTextFlowTrackName(GetTrackName(exact)) then return exact end

    local tracks = CollectTextFlowTracks()
    if #tracks > 0 then return tracks[1].track end
    return nil
end

function CurrentTextFlowEntry()
    local track = GetRythmoTrack()
    if not IsValidTrack(track) then return nil end
    return {track=track, name=GetTrackName(track), guid=reaper.GetTrackGUID(track)}
end

function CurrentTextFlowLabel()
    return current_text_flow_label or "Nessun testo"
end

function CycleTextFlow(delta)
    local tracks = CollectTextFlowTracks()
    if #tracks == 0 then return end

    local current = CurrentTextFlowEntry()
    local current_guid = current and current.guid or ""
    local current_index = 1
    for i, entry in ipairs(tracks) do
        if entry.guid == current_guid then current_index = i break end
    end

    local next_index = ((current_index - 1 + delta) % #tracks) + 1
    selected_text_track_guid = tracks[next_index].guid
    current_text_track = nil
    active_media_item = nil
    cached_items = {}
    cached_notes = {}
    last_track_guid = ""
    last_proj_state = -1
    UpdateItems()
end

function NormalizeSearchText(text)
    return tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n"):lower()
end

function FindSubtitleMatch(query, start_pos)
    local needle = NormalizeSearchText(query)
    if needle == "" then return nil end

    local fallback = nil
    for _, item in ipairs(cached_items) do
        local haystack = NormalizeSearchText(item.notes)
        if haystack:find(needle, 1, true) then
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
        local haystack = NormalizeSearchText(item.notes)
        if haystack:find(needle, 1, true) then
            if not fallback then fallback = item end
            if item.pos < (start_pos or 0) - 0.001 then
                return item
            end
        end
    end
    return fallback
end

function JumpToSearchMatch(item)
    if not item then return end
    search_hit_item = item.item
    search_hit_until = reaper.time_precise() + 3.0
    search_virtual_pos = item.pos
    if studio_edit_mode then
        SelectSubtitleItemAndJump(item.item)
    else
        manual_view_pos = item.pos
        smooth_scroll_pos = item.pos
        playback_anchor_pos = nil
    end
end

function PromptSubtitleSearch()
    search_panel_open = true
    search_message = ""
    if search_query == "" and search_panel_open then search_query = "" end
end

function ExecuteSubtitleSearch(direction)
    search_query = trim(search_query or "")
    if search_query == "" then
        search_message = "Scrivi una parola o frase"
        search_message_until = reaper.time_precise() + 1.8
        return
    end

    local pos = (not studio_edit_mode and search_virtual_pos) or reaper.GetCursorPosition()
    local match = direction and direction < 0 and FindSubtitleMatchPrevious(search_query, pos) or FindSubtitleMatch(search_query, pos)
    if not match then
        search_message = "Nessun risultato"
        search_message_until = reaper.time_precise() + 2.0
        return
    end
    JumpToSearchMatch(match)
    search_message = FormatVideoTimecode(match.pos)
    search_message_until = reaper.time_precise() + 2.0
end

function IsSearchShortcut(char)
    if char == 6 then return true end
    local is_f = char == 70 or char == 102
    local has_modifier = ((gfx.mouse_cap & 4) == 4) or ((gfx.mouse_cap & 32) == 32)
    return is_f and has_modifier
end

function ProcessSearchPanelKey(char)
    if not search_panel_open or char <= 0 then return false end
    if IsSearchShortcut(char) then return true end
    if char == 13 then ExecuteSubtitleSearch(1); return true end
    if char == 27 then search_panel_open = false; return true end
    if char == 8 then search_query = Utf8Backspace(search_query); return true end
    if char >= 32 and char <= 1114111 then
        local ch = TextCharFromCode(char)
        if ch then search_query = (search_query or "") .. ch end
        return true
    end
    return false
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
        if a.row ~= b.row then return a.row < b.row end
        if (a.track_order or 999999) ~= (b.track_order or 999999) then return (a.track_order or 999999) < (b.track_order or 999999) end
        if a.pos == b.pos then return a.text < b.text end
        return a.pos < b.pos
    end)
    if #matches == 0 then return matches end
    -- Regola dura: se piu' segnaposto toccano la stessa battuta, vince quello della traccia piu' alta.
    return {matches[1]}
end

-- =============================================
function UpdateItems()
    local track = GetRythmoTrack()
    current_text_track = track
    current_text_flow_label = track and TextFlowDisplayName(GetTrackName(track)) or "Nessun testo"

    cached_project_fps = GetProjectFPS()
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
            local color = GetDisplayedItemColor(item, COLOR_SUBS)
            local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
            local _, highlight_raw = reaper.GetSetMediaItemInfo_String(item, "P_EXT:RythmoBand_HIGHLIGHT", "", false)
            local person_notes = CollectCharacterNotesForRange(pos, len)
            
            local r, g, b = ColorToRGB(color, COLOR_SUBS)
            
            table.insert(cached_items, {item=item, pos=pos, len=len, notes=notes, highlights=ParseHighlightTerms(highlight_raw), person_notes=person_notes, r=r, g=g, b=b})
        end
        table.sort(cached_items, function(a, b) return a.pos < b.pos end)
    end
    
    RecalculateLayout()
end

function RefreshCachedSubtitleItem(item, new_text)
    for _, cached in ipairs(cached_items) do
        if cached.item == item then
            cached.notes = new_text
            RecalculateLayout()
            return true
        end
    end
    return false
end

-- =============================================
function DrawButton(x, y, w, h, label, hover_r, hover_g, hover_b, active)
    local mx, my = gfx.mouse_x, gfx.mouse_y
    local hover = (mx >= x and mx <= x+w and my >= y and my <= y+h)
    
    if active then gfx.set(0.13, 0.42, 0.72, 1)
    elseif hover then gfx.set(hover_r or 0.3, hover_g or 0.3, hover_b or 0.5, 1)
    else gfx.set(0.18, 0.18, 0.25, 1) end
    gfx.rect(x, y, w, h, 1)
    
    gfx.set(0.4, 0.4, 0.6, 1)
    gfx.rect(x, y, w, h, 0)
    
    gfx.setfont(3, "Arial", 16, 'b')
    local tw, th = gfx.measurestr(label)
    gfx.x = x + (w - tw) / 2
    gfx.y = y + (h - th) / 2
    if hover then gfx.set(1, 1, 1, 1) else gfx.set(0.75, 0.75, 0.85, 1) end
    gfx.drawstr(label)
    
    return hover and (gfx.mouse_cap == 0) and mouse_was_down
end

function DrawSearchPanel(w, h)
    if not search_panel_open then return end
    local panel_w = math.min(560, math.max(330, w - 80))
    local panel_h = 58
    local x = math.floor((w - panel_w) / 2)
    local y = 12
    local pad = 10

    gfx.set(0.08, 0.075, 0.065, 0.97)
    gfx.rect(x, y, panel_w, panel_h, 1)
    gfx.set(0.72, 0.50, 0.12, 0.95)
    gfx.rect(x, y, panel_w, 2, 1)
    gfx.set(0.38, 0.34, 0.26, 0.85)
    gfx.rect(x, y, panel_w, panel_h, 0)

    gfx.setfont(3, "Arial", 13, 'b')
    gfx.set(0.78, 0.73, 0.62, 1)
    gfx.x, gfx.y = x + pad, y + 7
    gfx.drawstr("Trova")

    local input_x = x + 58
    local input_y = y + 22
    local input_w = panel_w - 206
    gfx.set(0.12, 0.11, 0.10, 1)
    gfx.rect(input_x, input_y, input_w, 24, 1)
    gfx.set(0.82, 0.58, 0.13, 1)
    gfx.rect(input_x, input_y, input_w, 24, 0)

    gfx.setfont(3, "Arial", 15)
    local shown = search_query ~= "" and search_query or "Cerca parola/frase..."
    gfx.x, gfx.y = input_x + 8, input_y + 4
    if search_query == "" then gfx.set(0.58, 0.55, 0.50, 0.9) else gfx.set(0.95, 0.92, 0.84, 1) end
    gfx.drawstr(shown)
    if math.floor(reaper.time_precise() * 2) % 2 == 0 then
        local tw = gfx.measurestr(search_query or "")
        gfx.set(0.95, 0.70, 0.18, 1)
        gfx.rect(input_x + 9 + tw, input_y + 5, 2, 15, 1)
    end

    if DrawButton(x + panel_w - 138, input_y, 30, 24, "<", 0.34, 0.25, 0.12) then ExecuteSubtitleSearch(-1) end
    if DrawButton(x + panel_w - 104, input_y, 30, 24, ">", 0.34, 0.25, 0.12) then ExecuteSubtitleSearch(1) end
    if DrawButton(x + panel_w - 68, input_y, 26, 24, "X", 0.45, 0.18, 0.14) then search_panel_open = false end

    if search_message ~= "" and reaper.time_precise() <= search_message_until then
        gfx.setfont(3, "Arial", 12)
        gfx.set(0.86, 0.78, 0.58, 0.95)
        gfx.x, gfx.y = x + panel_w - 140, y + 7
        gfx.drawstr(search_message)
    end
end

function SelectSubtitleItemAndJump(media_item)
    if not media_item then return end
    local track = reaper.GetMediaItem_Track(media_item)
    local pos = reaper.GetMediaItemInfo_Value(media_item, "D_POSITION")
    reaper.Main_OnCommand(40289, 0) -- Unselect all items
    reaper.SetMediaItemSelected(media_item, true)
    if track then reaper.SetOnlyTrackSelected(track) end
    reaper.SetEditCurPos(pos, true, false)
    manual_view_pos = nil
    playback_anchor_pos = nil
    smooth_scroll_pos = pos
    reaper.UpdateArrange()
end

function UpdateSubtitleItemName(item, text)
    local one_line = tostring(text or ""):gsub("[\r\n]+", " / ")
    one_line = one_line:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    if #one_line > 160 then one_line = one_line:sub(1, 157) .. "..." end
    reaper.GetSetMediaItemInfo_String(item, "P_NAME", one_line, true)
    reaper.UpdateItemInProject(item)
end

function EditSubtitleItemText(item)
    if not item then return end
    local _, current = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    local edit_text = (current or ""):gsub("\r", ""):gsub("\n", "\\n")
    local ok, values = reaper.GetUserInputs("Edit testo gobbo", 1, "Testo (usa \\n per andare a capo):,extrawidth=700", edit_text)
    if not ok then return end
    local new_text = (values or ""):gsub("\\n", "\n")
    new_text = new_text:match("^%s*(.-)%s*$") or ""
    if new_text == "" or new_text == current then return end

    reaper.Undo_BeginBlock()
    reaper.GetSetMediaItemInfo_String(item, "P_NOTES", new_text, true)
    UpdateSubtitleItemName(item, new_text)
    reaper.Undo_EndBlock("ZP Studio Suite: modifica testo dal gobbo orizzontale", -1)

    UpdateItems()
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
    InlineDeleteSelection()
    local source = inline_edit.text or ""
    local cursor = inline_edit.cursor or (#source + 1)
    inline_edit.text = source:sub(1, cursor - 1) .. text .. source:sub(cursor)
    inline_edit.cursor = cursor + #text
end

function InlineBackspace()
    if not inline_edit then return end
    if InlineDeleteSelection() then return end
    local source = inline_edit.text or ""
    local cursor = inline_edit.cursor or (#source + 1)
    if cursor <= 1 then return end
    local prev = Utf8PrevCursor(source, cursor)
    inline_edit.text = source:sub(1, prev - 1) .. source:sub(cursor)
    inline_edit.cursor = prev
end

function InlineDelete()
    if not inline_edit then return end
    if InlineDeleteSelection() then return end
    local source = inline_edit.text or ""
    local cursor = inline_edit.cursor or (#source + 1)
    if cursor > #source then return end
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
    local line_h = inline_edit.line_h or (inline_edit.font_size * 1.18)
    local line_index = math.floor((py - inline_edit.text_y) / line_h) + 1
    local lines = InlineVisualLines(inline_edit.text_w or 400)
    line_index = math.max(1, math.min(line_index, #lines))
    local line = lines[line_index]
    local rel_x = math.max(0, px - inline_edit.text_x)
    local best_pos = line.start
    for pos = line.start, line.finish + 1 do
        local part = inline_edit.text:sub(line.start, pos - 1)
        local tw = gfx.measurestr(part)
        if rel_x < tw then break end
        best_pos = pos
    end
    InlineSetCursor(best_pos)
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
    ToggleItemHighlight(inline_edit.item, selected)
    UpdateItems()
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
        w = math.max(300, w),
        h = math.max(master_font_size * 2.0, h),
        font_size = math.max(22, math.min(master_font_size, 46))
    }
    reaper.OnStopButton()
end

function SaveInlineSubtitleEdit()
    if not inline_edit or not inline_edit.item then return end
    local new_text = trim(inline_edit.text or "")
    if new_text ~= "" and new_text ~= inline_edit.original then
        reaper.Undo_BeginBlock()
        reaper.GetSetMediaItemInfo_String(inline_edit.item, "P_NOTES", new_text, true)
        UpdateSubtitleItemName(inline_edit.item, new_text)
        reaper.UpdateItemInProject(inline_edit.item)
        reaper.Undo_EndBlock("ZP Studio Suite: modifica testo inline dal gobbo orizzontale", -1)
        if not RefreshCachedSubtitleItem(inline_edit.item, new_text) then UpdateItems() end
        last_proj_state = reaper.GetProjectStateChangeCount(0)
    end
    inline_edit = nil
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
    local x = math.max(8, math.min(inline_edit.x, gfx.w - 320))
    local y = math.max(alert_strip_h + 8, inline_edit.y)
    local w = math.min(inline_edit.w, gfx.w - x - 8)
    local line_h = inline_edit.font_size * 1.18
    inline_edit.line_h = line_h
    gfx.setfont(1, default_font, inline_edit.font_size, 'b')
    local text_w = math.max(80, w - (pad * 2))
    inline_edit.text_w = text_w
    local lines = InlineVisualLines(text_w)
    local h = math.max(inline_edit.h, (#lines * line_h) + (pad * 2) + 20)
    if y + h > gfx.h - 8 then y = math.max(alert_strip_h + 8, gfx.h - h - 8) end
    inline_edit.text_x = x + pad
    inline_edit.text_y = y + pad

    gfx.set(0.02, 0.02, 0.025, 0.97)
    gfx.rect(x, y, w, h, 1)
    gfx.set(1.0, 0.78, 0.18, 0.92)
    gfx.rect(x, y, w, 3, 1)
    gfx.set(0.96, 0.91, 0.78, 1)
    for i, line in ipairs(lines) do
        gfx.x = x + pad
        gfx.y = y + pad + ((i - 1) * line_h)
        local sel_a, sel_b = InlineSelectionRange()
        if sel_a then
            local a = math.max(sel_a, line.start)
            local b = math.min(sel_b, line.finish + 1)
            if a < b then
                local before_w = gfx.measurestr((inline_edit.text or ""):sub(line.start, a - 1))
                local sel_w = gfx.measurestr((inline_edit.text or ""):sub(a, b - 1))
                gfx.set(0.18, 0.44, 0.95, 0.55)
                gfx.rect(x + pad + before_w, y + pad + ((i - 1) * line_h) - 2, math.max(2, sel_w), line_h, 1)
                gfx.set(0.96, 0.91, 0.78, 1)
            end
        end
        gfx.drawstr(line.text)
    end

    if (gfx.mouse_cap & 1) == 1 and not mouse_was_down then
        if gfx.mouse_x >= x and gfx.mouse_x <= x + w and gfx.mouse_y >= y and gfx.mouse_y <= y + h then
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
    if (math.floor(reaper.time_precise() * 2) % 2) == 0 then
        gfx.set(1.0, 0.78, 0.18, 1)
        gfx.rect(x + pad + cw + 2, y + pad + ((cursor_line_index - 1) * line_h), 2, line_h * 0.9, 1)
    end
    gfx.setfont(3, "Arial", 12)
    gfx.set(0.84, 0.70, 0.38, 0.88)
    gfx.x = x + pad
    gfx.y = y + h - 17
    gfx.drawstr("Invio salva  |  Shift+Invio accapo  |  Ctrl+E evidenzia  |  Esc annulla")
end

function HandleSubtitleEditDoubleClick(item, x, y, w, h)
    local mx, my = gfx.mouse_x, gfx.mouse_y
    local hover = (mx >= x and mx <= x + w and my >= y and my <= y + h)
    local mouse_down = (gfx.mouse_cap & 1) == 1
    if hover and mouse_down and not mouse_was_down then
        local now = reaper.time_precise()
        if last_edit_click_item == item and (now - last_edit_click_time) < 0.35 then
            last_edit_click_time = 0
            last_edit_click_item = nil
            StartInlineSubtitleEdit(item, x, y, w, h)
        else
            last_edit_click_time = now
            last_edit_click_item = item
        end
    end
end

function HandleStudioItemClick(item, x, y, w, h)
    if not studio_edit_mode or inline_edit or search_panel_open then return end
    local mx, my = gfx.mouse_x, gfx.mouse_y
    local hover = (mx >= x and mx <= x + w and my >= y and my <= y + h)
    local mouse_down = (gfx.mouse_cap & 1) == 1
    if hover and mouse_down and not mouse_was_down then
        SelectSubtitleItemAndJump(item)
    end
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
    gfx.drawstr("IMPOSTAZIONI GOBBO ORIZZONTALE")

    gfx.set(0.25, 0.25, 0.4, alpha)
    gfx.line(0, panel_y + 32, w, panel_y + 32)
    
    local row_y = panel_y + 40
    local col1_x = 14
    local col2_x = 300
    local col3_x = 560
    local changed = false

    -- === SCALA: velocita, larghezza item e corpo testo insieme ===
    gfx.setfont(3, "Arial", 14, 'b')
    gfx.set(0.6, 0.7, 1.0, alpha)
    gfx.x, gfx.y = col1_x, row_y
    gfx.drawstr("SCALA / VELOCITA")
    
    gfx.setfont(3, "Arial", 20, 'b')
    gfx.set(1, 1, 1, alpha)
    local zoom_val = string.format("%d", pixels_per_second)
    gfx.x, gfx.y = col1_x + 132, row_y - 3
    gfx.drawstr(zoom_val)
    
    local b_zm = DrawButton(col1_x,      row_y + 22, 32, 28, "-", 0.6, 0.2, 0.2)
    local b_zp = DrawButton(col1_x + 36, row_y + 22, 32, 28, "+", 0.2, 0.5, 0.2)
    local b_z1 = DrawButton(col1_x + 80, row_y + 22, 38, 28, "150", 0.2, 0.3, 0.5)
    local b_z2 = DrawButton(col1_x + 122,row_y + 22, 38, 28, "200", 0.2, 0.3, 0.5)
    local b_z3 = DrawButton(col1_x + 164,row_y + 22, 38, 28, "350", 0.2, 0.3, 0.5)
    
    if b_zm then SetHorizontalScale(pixels_per_second - 25); changed = true end
    if b_zp then SetHorizontalScale(pixels_per_second + 25); changed = true end
    if b_z1 then SetHorizontalScale(150); changed = true end
    if b_z2 then SetHorizontalScale(200); changed = true end
    if b_z3 then SetHorizontalScale(350); changed = true end

    -- === CORPO RISULTANTE ===
    gfx.setfont(3, "Arial", 14, 'b')
    gfx.set(0.6, 0.7, 1.0, alpha)
    gfx.x, gfx.y = col2_x, row_y
    gfx.drawstr("CORPO TESTO")
    
    gfx.setfont(3, "Arial", 20, 'b')
    gfx.set(1, 1, 1, alpha)
    local font_val = string.format("%d", master_font_size)
    gfx.x, gfx.y = col2_x + 106, row_y - 3
    gfx.drawstr(font_val)

    local b_fm = DrawButton(col2_x,      row_y + 22, 32, 28, "-", 0.6, 0.2, 0.2)
    local b_fp = DrawButton(col2_x + 36, row_y + 22, 32, 28, "+", 0.2, 0.5, 0.2)
    local b_f1 = DrawButton(col2_x + 80, row_y + 22, 38, 28, "32", 0.2, 0.3, 0.5)
    local b_f2 = DrawButton(col2_x + 122,row_y + 22, 38, 28, "44", 0.2, 0.3, 0.5)
    local b_f3 = DrawButton(col2_x + 164,row_y + 22, 38, 28, "56", 0.2, 0.3, 0.5)

    if b_fm then SetFontSize(master_font_size - 2); changed = true end
    if b_fp then SetFontSize(master_font_size + 2); changed = true end
    if b_f1 then SetFontSize(32); changed = true end
    if b_f2 then SetFontSize(44); changed = true end
    if b_f3 then SetFontSize(56); changed = true end

    if col3_x + 190 < w then
        gfx.setfont(3, "Arial", 14, 'b')
        gfx.set(0.6, 0.7, 1.0, alpha)
        gfx.x, gfx.y = col3_x, row_y
        gfx.drawstr("ANTICIPO VOCE")

        gfx.setfont(3, "Arial", 20, 'b')
        gfx.set(1, 1, 1, alpha)
        local lead_val = string.format("%.1fs", accessibility_speech_lead)
        gfx.x, gfx.y = col3_x + 132, row_y - 3
        gfx.drawstr(lead_val)

        local b_lm = DrawButton(col3_x,      row_y + 22, 32, 28, "-", 0.6, 0.2, 0.2)
        local b_lp = DrawButton(col3_x + 36, row_y + 22, 32, 28, "+", 0.2, 0.5, 0.2)
        local b_l0 = DrawButton(col3_x + 80, row_y + 22, 38, 28, "0", 0.2, 0.3, 0.5)
        local b_l3 = DrawButton(col3_x + 122,row_y + 22, 38, 28, "3", 0.2, 0.3, 0.5)
        local b_l5 = DrawButton(col3_x + 164,row_y + 22, 38, 28, "5", 0.2, 0.3, 0.5)
        local b_l10 = DrawButton(col3_x + 206,row_y + 22, 44, 28, "10", 0.2, 0.3, 0.5)

        if b_lm then SetAccessibilitySpeechLead(accessibility_speech_lead - 0.5) end
        if b_lp then SetAccessibilitySpeechLead(accessibility_speech_lead + 0.5) end
        if b_l0 then SetAccessibilitySpeechLead(0) end
        if b_l3 then SetAccessibilitySpeechLead(3) end
        if b_l5 then SetAccessibilitySpeechLead(5) end
        if b_l10 then SetAccessibilitySpeechLead(10) end

        gfx.setfont(3, "Arial", 12)
        gfx.set(0.78, 0.80, 0.92, alpha * 0.85)
        gfx.x, gfx.y = col3_x, row_y + 54
        gfx.drawstr("Solo OSARA/NVDA, max 10 s")
    end
    
    if changed then 
        show_settings_timer = 60 
        RecalculateLayout() 
    end
    
    return panel_y
end

function DrawAlertStrip(w, strip_h, play_pos, attack_x)
    gfx.set(0.075, 0.07, 0.055, 1)
    gfx.rect(0, 0, w, strip_h, 1)
    gfx.set(0.45, 0.34, 0.15, 0.85)
    gfx.rect(0, strip_h - 1, w, 1, 1)

    gfx.setfont(3, "Arial", 15, 'b')
    gfx.set(0.95, 0.82, 0.40, 1)
    gfx.x, gfx.y = 12, 8
    gfx.drawstr("GOBBO ORIZZONTALE")

    local tc_box_x, tc_box_w = nil, 0
    if show_timecode then
        local tc = FormatVideoTimecode(play_pos)
        gfx.setfont(3, "Arial", 20, 'b')
        local tw = gfx.measurestr(tc)
        tc_box_w = tw + 28
        tc_box_x = math.floor((attack_x or (w / 2)) - (tc_box_w / 2))
        if tc_box_x < 150 then tc_box_x = 150 end
        if tc_box_x + tc_box_w > w - 12 then tc_box_x = w - tc_box_w - 12 end
    end

    gfx.setfont(3, "Arial", 11)
    gfx.set(0.56, 0.72, 0.86, 1)
    local suite_label = "ZP Studio Suite v1.0.5"
    local credit_label = " - Paolo Balestri & Nicola Lanci"
    local label = suite_label .. credit_label
    local label_x = 190
    local max_label_w = (tc_box_x and (tc_box_x - label_x - 12)) or (w - label_x - 320)
    if max_label_w < 120 then label = suite_label end
    if max_label_w < 70 then
        label = ""
    elseif gfx.measurestr(label) > max_label_w then
        label = suite_label
        while #label > 8 and gfx.measurestr(label .. ".") > max_label_w do
            label = label:sub(1, -2)
        end
        label = label .. "."
    end
    gfx.x, gfx.y = label_x, 10
    gfx.drawstr(label)

    local studio_label = studio_edit_mode and "Studio/Edit ON" or "Studio/Edit OFF"
    if DrawButton(w - 282, 29, 138, 24, studio_label, 0.20, 0.48, 0.40, studio_edit_mode) then
        SetStudioEditMode(not studio_edit_mode)
    end

    local flow_label = CurrentTextFlowLabel()
    if #flow_label > 20 then flow_label = flow_label:sub(1, 19) .. "." end
    if DrawButton(12, 30, 26, 22, "<", 0.22, 0.30, 0.42) then CycleTextFlow(-1) end
    if DrawButton(42, 30, 26, 22, ">", 0.22, 0.30, 0.42) then CycleTextFlow(1) end
    gfx.setfont(3, "Arial", 13, 'b')
    gfx.set(0.80, 0.86, 1.0, 1)
    gfx.x, gfx.y = 76, 34
    gfx.drawstr("Testi: " .. flow_label)

    if show_timecode then
        local tc = FormatVideoTimecode(play_pos)
        gfx.setfont(3, "Arial", 20, 'b')
        local tw, th = gfx.measurestr(tc)
        local box_w = tc_box_w
        local box_h = 34
        local box_x = tc_box_x
        local box_y = 10
        gfx.set(0, 0, 0, 1)
        gfx.rect(box_x, box_y, box_w, box_h, 1)
        gfx.set(1, 1, 1, 1)
        gfx.x = box_x + 14
        gfx.y = box_y + ((box_h - th) / 2)
        gfx.drawstr(tc)
    end

    local note_x = show_timecode and math.max(190, math.floor((attack_x or (w / 2)) + 90)) or 190
    local note_w = w - note_x - 12
    if note_w < 120 then return end

    local drawn = 0
    for _, note in ipairs(cached_notes) do
        if drawn >= max_character_rows then break end
        local note_end = note.pos + note.len
        local delta = note.pos - play_pos
        local active = play_pos >= note.pos - 0.35 and play_pos <= note_end + 0.35
        local imminent = delta > 0 and delta <= NOTE_WAKE_LEAD

        if active or imminent then
            local alpha = active and 1.0 or (0.38 + ((NOTE_WAKE_LEAD - delta) / NOTE_WAKE_LEAD) * 0.45)
            local card_x = note_x + (drawn * 240)
            local card_w = math.min(230, note_x + note_w - card_x)
            if card_w < 90 then break end

            if active then gfx.set(note.r, note.g, note.b, 0.82)
            else gfx.set(note.r, note.g, note.b, 0.45) end
            gfx.rect(card_x, 8, card_w, strip_h - 16, 1)

            gfx.setfont(3, "Arial", 11, 'b')
            SetReadableTextColor(note.r, note.g, note.b, alpha)
            gfx.x, gfx.y = card_x + 8, 11
            gfx.drawstr(FormatVideoTimecode(note.pos))

            gfx.setfont(3, "Arial", 14, 'b')
            SetReadableTextColor(note.r, note.g, note.b, math.min(1, alpha + 0.20))
            local text = note.text:gsub("[\r\n]+", " ")
            if #text > 42 then text = text:sub(1, 39) .. "..." end
            gfx.x, gfx.y = card_x + 8, 28
            gfx.drawstr(text)

            drawn = drawn + 1
        end
    end
end

function GetWordModeX(item, play_pos, w, reading_x)
    local speed = item.scroll_pps or pixels_per_second
    return reading_x - (((play_pos or item.pos) - item.pos) * speed)
end

function WordModeAlpha(item, play_pos)
    return 1.0
end

function DrawWordModeText(item, x, y, is_active, reading_x, r, g, b, alpha)
    local words = item.words or SplitWords(item.read_text or (item.lines and item.lines[1]) or "")
    local space_w = gfx.measurestr(" ")
    local line_h = item.line_h or (item.font_size * 1.15)
    local char_w = math.max(8, gfx.measurestr("M") * 0.68)
    local left_glow = char_w * 30
    local right_glow = char_w * 70

    for line_index, line in ipairs(item.lines or {item.read_text or ""}) do
        local line_y = y + ((line_index - 1) * line_h)
        local cursor_x = x
        if line_index == 1 then
            local prefix = item.speaker_prefix or ""
            if prefix ~= "" then
                gfx.set(r, g, b, math.min(0.24, alpha * 0.26))
                gfx.x = cursor_x
                gfx.y = line_y
                gfx.drawstr(prefix)
                cursor_x = cursor_x + gfx.measurestr(prefix .. " ")
            end
        end

        local words = item.line_words and item.line_words[line_index] or SplitWords(line)
        for _, word in ipairs(words) do
            local word_w = gfx.measurestr(word)

            local word_center = cursor_x + (word_w * 0.5)
            local dist = word_center - reading_x
            local spectrum = 0
            if dist >= 0 and dist <= right_glow then
                spectrum = 1 - (dist / right_glow)
            elseif dist < 0 and math.abs(dist) <= left_glow then
                spectrum = 1 - (math.abs(dist) / left_glow)
            end

            local word_alpha = math.max(0.30, alpha * (0.42 + (0.52 * spectrum)))
            local base = 0.78 + (0.20 * spectrum)
            gfx.set(base, base, base, word_alpha)
            gfx.x = cursor_x
            gfx.y = line_y
            gfx.drawstr(word)
            cursor_x = cursor_x + word_w + space_w
        end
    end
end

function BuildHorizontalDrawJob(item, smoothed_play_pos, window_w, attack_x, group_start_y)
    local start_px = GetWordModeX(item, smoothed_play_pos, window_w, attack_x)
    if not start_px then return nil end

    local bg_w = item.tape_w or math.max(80, (item.text_w or item.box_w) + 42)
    local end_px = start_px + bg_w
    if end_px <= -20 or start_px >= window_w + 20 then return nil end

    local is_active = (smoothed_play_pos >= item.pos and smoothed_play_pos <= item.pos + item.len)
    local distance = 0
    if smoothed_play_pos < item.pos then
        distance = item.pos - smoothed_play_pos
    elseif smoothed_play_pos > item.pos + item.len then
        distance = smoothed_play_pos - (item.pos + item.len)
    end

    return {
        item = item,
        start_px = start_px,
        end_px = end_px,
        bg_w = bg_w,
        is_active = is_active,
        alpha = WordModeAlpha(item, smoothed_play_pos),
        item_y = group_start_y + item.y_offs,
        priority = (is_active and 100000 or 0) - distance,
    }
end

function SortHorizontalJobs(jobs)
    table.sort(jobs, function(a, b) return a.start_px < b.start_px end)
    return jobs
end

function DrawHorizontalItemJob(job, attack_x)
    local item = job.item
    local is_active = job.is_active
    local alpha = job.alpha
    local primary_note = item.person_notes and item.person_notes[1] or nil

    local item_r = math.min(1, item.r * 0.90 + 0.05)
    local item_g = math.min(1, item.g * 0.90 + 0.05)
    local item_b = math.min(1, item.b * 0.90 + 0.05)
    if primary_note then
        item_r = math.min(1, primary_note.r * 0.85 + 0.06)
        item_g = math.min(1, primary_note.g * 0.85 + 0.06)
        item_b = math.min(1, primary_note.b * 0.85 + 0.06)
    end

    local item_y = job.item_y
    local num_lines = math.max(1, #item.lines)
    local box_h = item.box_h or (item.line_h + 18)
    local is_search_hit = search_hit_item == item.item and reaper.time_precise() <= search_hit_until

    if is_search_hit then gfx.set(1.0, 0.50, 0.10, 0.18 * alpha)
    else gfx.set(0.02, 0.02, 0.02, 0.16) end
    gfx.rect(job.start_px - 12, item_y, job.bg_w, box_h, 1)
    if is_search_hit then
        gfx.set(1.0, 0.70, 0.16, 0.95 * alpha)
        gfx.rect(job.start_px - 12, item_y, 4, box_h, 1)
    end
    if primary_note then
        gfx.set(primary_note.r, primary_note.g, primary_note.b, 0.045)
        gfx.rect(job.start_px - 12, item_y + box_h - 5, job.bg_w, 3, 1)
    end

    gfx.setfont(1, default_font, item.font_size, 'b')
    gfx.set(item_r, item_g, item_b, alpha)

    local text_h = num_lines * (item.line_h or master_font_size * 1.15)
    DrawWordModeText(item, job.start_px, item_y + (box_h - text_h) / 2, is_active, attack_x, item_r, item_g, item_b, alpha)
    HandleStudioItemClick(item.item, job.start_px - 12, item_y, job.bg_w, box_h)
    HandleSubtitleEditDoubleClick(item.item, job.start_px - 12, item_y, job.bg_w, box_h)
end

function FindOsaraCueAtPosition(play_pos)
    local best = nil
    local best_delta = math.huge
    for _, item in ipairs(cached_items) do
        local item_end = item.pos + item.len
        if play_pos >= item.pos - 0.15 and play_pos <= item_end + 0.15 then
            local delta = math.abs(play_pos - item.pos)
            if delta < best_delta then
                best = item
                best_delta = delta
            end
        end
    end
    return best
end

function BuildOsaraCueMessage(item)
    if not item then return "" end
    local speaker = ""
    local primary_note = item.person_notes and item.person_notes[1] or nil
    if primary_note and trim(primary_note.role or primary_note.text or "") ~= "" then
        speaker = trim(primary_note.role or primary_note.text)
    elseif trim(item.speaker_prefix or "") ~= "" then
        speaker = trim((item.speaker_prefix or ""):gsub(":%s*$", ""))
    end

    local text = CleanOsaraText(item.read_text or item.notes or "")
    if text == "" then return "" end
    if speaker ~= "" then return speaker .. ". " .. text end
    return text
end

function UpdateOsaraTextFlow(play_pos)
    if not osara_text_enabled or not AccessibilitySpeechActive() or inline_edit or search_panel_open then return end

    local speech_pos = (play_pos or 0) + (accessibility_speech_lead or 0)
    local item = FindOsaraCueAtPosition(speech_pos)
    if not item then return end

    local key = tostring(item.item) .. "|" .. tostring(item.pos) .. "|" .. tostring(item.len)
    local now = reaper.time_precise()
    if key == osara_last_key and (now - osara_last_time) < 30 then return end

    local message = BuildOsaraCueMessage(item)
    if message == "" then return end
    osara_last_key = key
    osara_last_time = now
    SpeakAccessibilityText(message)
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
        elseif char == 61 or char == 43 then SetHorizontalScale(pixels_per_second + 25); changed = true
        elseif char == 45 or char == 95 then SetHorizontalScale(pixels_per_second - 25); changed = true end
        
        if changed then
            show_settings_timer = 60
            RecalculateLayout()
        end
    end

    local track = IsValidTrack(current_text_track) and current_text_track or GetRythmoTrack()
    if not IsValidTrack(track) then
        current_text_track = nil
        track = nil
    end
    local track_guid = track and reaper.GetTrackGUID(track) or ""
    local proj_state = reaper.GetProjectStateChangeCount(0)

    if proj_state ~= last_proj_state or track_guid ~= last_track_guid then
        last_proj_state = proj_state
        last_track_guid = track_guid
        UpdateItems()
    end

    local smoothed_play_pos, is_playing = GetContinuousPlayPosition()
    UpdateOsaraTextFlow(smoothed_play_pos)

    local w, h = gfx.w, gfx.h
    local attack_x = w * attack_x_ratio
    local band_y = alert_strip_h

    local panel_target = panel_open and 1.0 or 0.0
    panel_anim = lerp(panel_anim, panel_target, panel_anim_speed)
    if math.abs(panel_anim - panel_target) < 0.001 then panel_anim = panel_target end

    local band_h = h - band_y - (PANEL_H * panel_anim)
    if band_h < 80 then band_h = 80 end

    gfx.set(0.05, 0.05, 0.05, 1) 
    gfx.rect(0, band_y, w, band_h, 1)
    DrawAlertStrip(w, alert_strip_h, smoothed_play_pos, attack_x)

    if #cached_items == 0 then
        gfx.setfont(1, "Arial", 24, 'b')
        gfx.set(0.4, 0.4, 0.4, 1)
        local warn_text = "Seleziona la traccia testi per ZP Studio Suite!"
        local tw, th = gfx.measurestr(warn_text)
        gfx.x = (w - tw) / 2
        gfx.y = band_y + ((band_h - th) / 2)
        gfx.drawstr(warn_text)
    end
    
    local group_start_y = band_y + ((band_h - global_max_y) / 2)
    if group_start_y < band_y + 10 then group_start_y = band_y + 10 end
    
    local draw_jobs = {}
    for _, item in ipairs(cached_items) do
        local job = BuildHorizontalDrawJob(item, smoothed_play_pos, w, attack_x, group_start_y)
        if job then table.insert(draw_jobs, job) end
    end
    for _, job in ipairs(SortHorizontalJobs(draw_jobs)) do
        DrawHorizontalItemJob(job, attack_x)
    end
    -- Linee guida: lettura a sinistra, anticipo verso il centro.
    local preview_x = attack_x + ((w * 0.50 - attack_x) * 0.66)
    gfx.set(0.0, 0.62, 1.0, 0.10)
    gfx.rect(preview_x - 1, band_y, 2, band_h, 1)
    gfx.set(0.0, 0.62, 1.0, 0.22)
    gfx.rect(attack_x - 1, band_y, 2, band_h, 1)

    if show_settings_timer > 0 then
        local hud_alpha = math.min(1, show_settings_timer / 20)
        gfx.setfont(2, "Arial", 18, 'b')
        local hud_txt = string.format("SCALA: %d px/s | CORPO: %d | ANTICIPO VOCE: %.1fs", pixels_per_second, master_font_size, accessibility_speech_lead)
        local tw, th = gfx.measurestr(hud_txt)
        
        gfx.set(0, 0, 0, 0.7 * hud_alpha)
        gfx.rect(10, 10, tw + 20, th + 10, 1)
        gfx.set(1, 1, 1, hud_alpha)
        gfx.x, gfx.y = 20, 15
        gfx.drawstr(hud_txt)
        show_settings_timer = show_settings_timer - 1
    end

    gfx.setfont(3, "Arial", 14, 0)
    local hint = panel_open and "▼ TAB" or "⚙ TAB"
    local hint_col = panel_open and 0.5 or 0.35
    gfx.set(hint_col, hint_col, hint_col + 0.2, 0.8)
    gfx.x, gfx.y = w - 125, 8
    gfx.drawstr(hint)

    if panel_anim > 0.01 then DrawSettingsPanel(w, h) end
    DrawInlineSubtitleEditor()
    DrawSearchPanel(w, h)

    mouse_was_down = (gfx.mouse_cap & 1) == 1
    gfx.update()
    reaper.defer(DrawGUI)
end

LoadHorizontalSettings()
InitGUI()
DrawGUI()
