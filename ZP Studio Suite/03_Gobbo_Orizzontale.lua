-- @noindex

--[[
   * ReaScript Name: ZP Studio Suite GUI Nativa
   * Linea: ZP Paolo Balestri
   * Suite: ZP Studio Suite for REAPER (versione dinamica dal 00)
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
local ZP_UI = dofile(SCRIPT_DIR .. 'ZP_UI.lua')
local ZP_TESTO = dofile(SCRIPT_DIR .. 'ZP_Testo_Copione.lua')
local ZP_EDITOR = dofile(SCRIPT_DIR .. 'ZP_Editor_Copione.lua')
local TimedTextDuration
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
local READ_ALL = "ALL"   -- flusso virtuale "Tutti" (Leggi tutto): tutte le tracce testo insieme
local WINDOW_TITLE = ("ZP Studio Suite " .. ZP_UI.suite_version() .. " - ") .. T("Gobbo Orizzontale")
local current_text_track = nil
local current_text_flow_label = T("Nessun testo")
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
local horizontal_text_lanes = 2
local smooth_scroll_pos = nil
local character_lane_by_key = {}
local NOTE_WAKE_LEAD = 5.0
-- Note agganciate alla battuta (vedi SyncLinkedNotes); stessa logica del Gobbo Verticale
local NOTE_LINK_MAX_DISTANCE = 10.0   -- oltre questa distanza da ogni battuta la nota resta libera
local NOTE_LINK_EPSILON = 0.0005
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
local search_results, search_results_total = {}, 0
local search_results_dirty, search_results_deadline = true, 0
local search_results_current, search_results_scroll = 0, 0
local search_results_rect = nil
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
    if reaper.GetExtState(gobbo_settings_section, "read_all") == "1" then selected_text_track_guid = READ_ALL end
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
    -- toolbar: icona accesa finche' la finestra e' aperta; un altro clic sull'icona la chiude (REAPER 7.03+)
    if reaper.set_action_options then reaper.set_action_options(1 | 4); reaper.atexit(function() reaper.set_action_options(8) end) end
    gfx.init(WINDOW_TITLE, 1100, 300, 0, 100, 100)
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
    local lane_slot_height = master_font_size * 1.35 + 20
    tape_origin_pos = cached_items[1] and cached_items[1].pos or 0

    for _, item in ipairs(cached_items) do
        item.font_size = master_font_size
        gfx.setfont(1, default_font, item.font_size, 'b')
        
        local display_text = (item.notes or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
        item.speaker_prefix, item.read_text = ExtractSpeakerPrefix(display_text)
        item.reading_plan=item.timed_scroll and ZP_TESTO.reading_plan(item.notes,nil,item.pause_weight,item.len,item.timed_wpm,item.timing) or nil
        if item.reading_plan then item.reading_plan.reminders=ZP_TESTO.reminder_markers(item.reading_plan,item.anchors,item.anchor_markers or {}) end
        item.word_plan=item.reading_plan or ZP_TESTO.reading_plan(item.notes,nil)
        item.reading_prefix_words=item.speaker_prefix~="" and #SplitWords(item.speaker_prefix) or 0
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
        local scroll_distance = math.max(item.timed_scroll and 2 or 80, item.text_w + 70)
        local scroll_duration = math.max(0.20, item.len or 0)
        item.scroll_pps = item.timed_scroll and math.max(2, scroll_distance / scroll_duration)
            or math.max(80, scroll_distance / scroll_duration)
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
    if selected_text_track_guid == READ_ALL then
        -- Leggi tutto: i testi nuovi vanno nella traccia principale, la lettura le prende tutte
        local exact = FindTrackByName(default_track_name)
        if exact and IsTextFlowTrackName(GetTrackName(exact)) then return exact end
        local tracks = CollectTextFlowTracks()
        return tracks[1] and tracks[1].track or nil
    end
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

function FollowLabel()
    if not FollowScriptPath() then return T("Segui: manca script") end
    return FollowEnabled() and T("Segui tagli ON") or T("Segui tagli OFF")
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

-- Help: apre la guida della suite sulla sezione di questa finestra (via ZP_UI, che
-- usa un indirizzo file:// codificato: con il percorso nudo macOS non apre il #segnalibro).
local function zp_open_help_section(anchor)
    local ok, ui = pcall(dofile, SCRIPT_DIR .. "ZP_UI.lua")
    if ok and type(ui) == "table" and ui.open_help then ui.open_help(anchor) return true end
    return false
end

-- Imposta il flusso letto (guid di una traccia testo, o READ_ALL = Tutti).
function SelectTextFlow(guid)
    selected_text_track_guid = guid
    reaper.SetExtState(gobbo_settings_section, "read_all", selected_text_track_guid == READ_ALL and "1" or "0", true)
    current_text_track = nil
    active_media_item = nil
    cached_items = {}
    cached_notes = {}
    last_track_guid = ""
    last_proj_state = -1
    UpdateItems()
end

-- Nome del file audio da cui il sync ha creato la battuta (P_EXT:ZP_SYNC_SRCKEY = "percorso|tempo").
-- nil per le battute scritte a mano.
function SyncSourceFileName(item)
    local _, key = reaper.GetSetMediaItemInfo_String(item, "P_EXT:ZP_SYNC_SRCKEY", "", false)
    local path = key and key:match("^(.*)|[^|]*$") or ""
    if path == "" then return nil end
    return path:match("[^/\\]+$") or path
end

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

function JumpToSearchMatch(item)
    if not item then return end
    search_hit_item = item.item
    search_hit_until = reaper.time_precise() + 3.0
    local target_pos = item.search_match_pos or item.pos
    search_virtual_pos = target_pos
    if studio_edit_mode then
        SelectSubtitleItemAndJump(item.item)
        reaper.SetEditCurPos(target_pos, true, false)
    else
        manual_view_pos = target_pos
        smooth_scroll_pos = target_pos
        playback_anchor_pos = nil
    end
end

function ScheduleSearchResults()
    search_results_dirty=true
    search_results_deadline=reaper.time_precise()+0.15
    search_results_current=0
end

function RefreshSearchResults(force)
    if not force and (not search_results_dirty or reaper.time_precise()<search_results_deadline) then return end
    local previous=search_results[search_results_current] and search_results[search_results_current].item or nil
    search_results,search_results_total=ZP_CERCA.results(cached_items,search_query,500)
    search_results_dirty=false; search_results_current=0
    if previous then for i,result in ipairs(search_results) do if result.item==previous then search_results_current=i; break end end end
    if search_results_current==0 then search_results_scroll=0 end
end

function SearchResultPosition(result)
    local item=result.item
    local ratio=(result.offset_start-1)/math.max(1,#tostring(item.notes or ""))
    return item.pos+item.len*math.max(0,math.min(1,ratio))
end

function SearchResultIndexForItem(item)
    for i,result in ipairs(search_results) do if result.item==item then return i end end
end

function SelectSearchResult(index, jump)
    if #search_results==0 then return end
    index=math.max(1,math.min(index,#search_results)); search_results_current=index
    local result=search_results[index]; local item=result.item
    item.search_match_pos=SearchResultPosition(result); item.search_match_offset=result.offset_start
    if index<=search_results_scroll then search_results_scroll=index-1 end
    local visible=search_results_rect and math.max(1,math.floor(search_results_rect.h/40)) or 1
    if index>search_results_scroll+visible then search_results_scroll=index-visible end
    search_results_scroll=math.max(0,math.min(search_results_scroll,math.max(0,#search_results-visible)))
    if jump then JumpToSearchMatch(item) end
    search_message=tostring(index).." di "..tostring(search_results_total).." · "..FormatVideoTimecode(SearchResultPosition(result))
    search_message_until=reaper.time_precise()+2.0
end

function PromptSubtitleSearch()
    search_panel_open = true
    search_message = ""
    if search_query == "" and search_panel_open then search_query = "" end
    ScheduleSearchResults()
end

function ExecuteSubtitleSearch(direction)
    search_query = trim(search_query or "")
    if search_query == "" then
        search_message = "Scrivi una parola o frase"
        search_message_until = reaper.time_precise() + 1.8
        return
    end
    RefreshSearchResults(true)

    local pos = (not studio_edit_mode and search_virtual_pos) or reaper.GetCursorPosition()
    local match = direction and direction < 0 and FindSubtitleMatchPrevious(search_query, pos) or FindSubtitleMatch(search_query, pos)
    if not match then
        search_message = "Nessun risultato"
        search_message_until = reaper.time_precise() + 2.0
        search_results_current=0
        return
    end
    JumpToSearchMatch(match)
    local index=SearchResultIndexForItem(match)
    if index then SelectSearchResult(index,false) end
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
    if char==30064 or char==1685026670 then
        RefreshSearchResults(true)
        local step=char==30064 and -1 or 1
        local next_index=search_results_current==0 and (step>0 and 1 or #search_results) or search_results_current+step
        if next_index>=1 and next_index<=#search_results then SelectSearchResult(next_index,true) end
        return true
    end
    if char == 13 then ExecuteSubtitleSearch(1); return true end
    if char == 27 then search_panel_open = false; return true end
    if char == 8 then search_query = Utf8Backspace(search_query); ScheduleSearchResults(); return true end
    if char >= 32 and char <= 1114111 then
        local ch = TextCharFromCode(char)
        if ch then search_query = (search_query or "") .. ch; ScheduleSearchResults() end
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
    local gobbo_markers=ZP_TESTO.timeline_markers(reaper)
    local track = GetRythmoTrack()
    current_text_track = track
    current_text_flow_label = track and TextFlowDisplayName(GetTrackName(track)) or "Nessun testo"
    if selected_text_track_guid == READ_ALL then current_text_flow_label = "Tutti" end

    cached_project_fps = GetProjectFPS()
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
            local person_notes = CollectCharacterNotesForRange(pos, len)
            
            local r, g, b = ColorToRGB(color, COLOR_SUBS)
            
            table.insert(cached_items, {item=item, pos=pos, len=len, notes=notes, highlights=ParseHighlightTerms(highlight_raw), timed_scroll=timed_scroll == "1", pause_weight=tonumber(pause_weight) or 4, timed_wpm=tonumber(timed_wpm) or 120, timing=timing, anchors=ZP_TESTO.parse_anchors(anchor_raw), anchor_markers=gobbo_markers, person_notes=person_notes, r=r, g=g, b=b, flow=flow_index, track_name=GetTrackName(track), source_file=SyncSourceFileName(item)})
        end
    end
    -- in ordine di tempo; a parita' di tempo, l'ordine delle tracce
    table.sort(cached_items, function(a, b)
        if a.pos ~= b.pos then return a.pos < b.pos end
        return a.flow < b.flow
    end)
    
    RecalculateLayout()
    if search_panel_open then search_results_dirty=true; search_results_deadline=reaper.time_precise()+0.15 end
end

-- =============================================
function DrawButton(x,y,w,h,label,hover_r,hover_g,hover_b,active)
    if inline_edit then return false end
    return ZP_UI.draw_button({x=x,y=y,w=w,h=h},label,active,true,(gfx.mouse_cap&1)==0 and mouse_was_down,'neutral')
end

function DrawSearchPanel(w, h)
    if not search_panel_open then return end
    RefreshSearchResults(false)
    local panel_w=math.min(680,math.max(180,w-16))
    local x=math.max(4,math.min(w-panel_w-4,math.floor((w-panel_w)/2)))
    local header_h=58; local row_h=52
    local max_h=math.max(0,math.min(560,h-8,math.max(header_h+24,math.floor(h*0.6))))
    local available=math.max(0,max_h-header_h-20)
    local visible=math.min(8,math.floor(available/row_h))
    local overflow=search_results_total>#search_results and 24 or 0
    local empty=search_results_total==0 and 28 or 0
    local panel_h=math.min(max_h,header_h+math.min(visible,#search_results)*row_h+overflow+empty+10)
    local y=math.max(0,math.min(12,h-panel_h-4))
    local pad=10; local input_x=x+58; local input_y=y+22
    local input_w=math.max(40,panel_w-206)
    gfx.set(0.08,0.075,0.065,0.97); gfx.rect(x,y,panel_w,panel_h,1)
    gfx.set(0.72,0.50,0.12,0.95); gfx.rect(x,y,panel_w,2,1)
    gfx.set(0.38,0.34,0.26,0.85); gfx.rect(x,y,panel_w,panel_h,0)
    gfx.setfont(3,"Arial",13,'b'); gfx.set(0.93, 0.90, 0.83, 1); gfx.x,gfx.y=x+pad,y+7; gfx.drawstr(T("Trova"))
    gfx.set(0.12,0.11,0.10,1); gfx.rect(input_x,input_y,input_w,24,1)
    gfx.set(0.82,0.58,0.13,1); gfx.rect(input_x,input_y,input_w,24,0)
    gfx.setfont(3,"Arial",15); local shown=search_query~="" and search_query or T("Cerca parola/frase...")
    gfx.x,gfx.y=input_x+8,input_y+4
    if search_query=="" then gfx.set(0.58,0.55,0.50,0.9) else gfx.set(0.95,0.92,0.84,1) end
    gfx.drawstr(shown)
    if math.floor(reaper.time_precise()*2)%2==0 then
        local tw=gfx.measurestr(search_query or ""); gfx.set(0.95,0.70,0.18,1); gfx.rect(input_x+9+tw,input_y+5,2,15,1)
    end
    if DrawButton(x+panel_w-138,input_y,30,24,"<",0.34,0.25,0.12) then ExecuteSubtitleSearch(-1) end
    if DrawButton(x+panel_w-104,input_y,30,24,">",0.34,0.25,0.12) then ExecuteSubtitleSearch(1) end
    if DrawButton(x+panel_w-68,input_y,26,24,"X",0.45,0.18,0.14) then search_panel_open=false end
    if search_message~="" and reaper.time_precise()<=search_message_until then
        gfx.setfont(3,"Arial",13); gfx.set(0.98, 0.90, 0.70, 1); gfx.x,gfx.y=x+125,y+6; gfx.drawstr(search_message)
    end
    local list_y=y+header_h; local list_x=x+pad; local list_w=panel_w-pad*2-12
    local shown_rows=math.min(visible,#search_results)
    if search_results_current>0 then
        if search_results_current<=search_results_scroll then search_results_scroll=search_results_current-1 end
        if search_results_current>search_results_scroll+math.max(1,shown_rows) then search_results_scroll=search_results_current-math.max(1,shown_rows) end
    end
    search_results_rect={x=x,y=list_y,w=panel_w,h=shown_rows*row_h}
    if search_results_total==0 then
        gfx.setfont(3,"Arial",15); gfx.set(0.90, 0.86, 0.78, 1); gfx.x,gfx.y=list_x,list_y+5; gfx.drawstr(T("Nessun risultato"))
    else
        for row=1,shown_rows do
            local i=search_results_scroll+row; local result=search_results[i]
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
                gfx.setfont(3,"Arial",14,'b'); gfx.set(0.98, 0.82, 0.45, 1); gfx.x,gfx.y=list_x+6,ry+4; gfx.drawstr(label,0,jump_x-4,ry+21)
                local snip=result.snippet or ""; local a,b=result.snip_a or 1,result.snip_b or 1
                local left,hit,right=snip:sub(1,a-1),snip:sub(a,b),snip:sub(b+1)
                local tx,ty=list_x+6,ry+24; gfx.setfont(3,"Arial",17);
                gfx.set(0.97, 0.96, 0.93, 1); gfx.x,gfx.y=tx,ty; gfx.drawstr(left,0,tx+list_w-12,ty+22); local lw=gfx.measurestr(left); local hw=gfx.measurestr(hit)
                gfx.set(0.98, 0.74, 0.20, 1); if lw<list_w-14 then gfx.rect(tx+lw,ty,math.max(2,math.min(hw,list_w-12-lw)),21,1) end
                gfx.set(0.08, 0.06, 0.02, 1); gfx.x,gfx.y=tx+lw,ty; gfx.drawstr(hit,0,tx+list_w-12,ty+22)
                gfx.set(0.97, 0.96, 0.93, 1); gfx.x,gfx.y=tx+lw+hw,ty; gfx.drawstr(right,0,tx+list_w-12,ty+22)
                if gfx.mouse_x>=list_x and gfx.mouse_x<=list_x+list_w and gfx.mouse_y>=ry and gfx.mouse_y<ry+row_h-2 and gfx.mouse_cap==0 and mouse_was_down then SelectSearchResult(i,true) end
            end
        end
    end
    if overflow>0 then gfx.setfont(3,"Arial",13); gfx.set(0.88, 0.84, 0.76, 1); gfx.x,gfx.y=list_x+4,list_y+shown_rows*row_h+3; gfx.drawstr(string.format(T("altri %s…"), tostring(search_results_total-#search_results))) end
    local wheel=gfx.mouse_wheel or 0; gfx.mouse_wheel=0
    if wheel~=0 and search_results_rect and gfx.mouse_x>=search_results_rect.x and gfx.mouse_x<=search_results_rect.x+search_results_rect.w and gfx.mouse_y>=search_results_rect.y and gfx.mouse_y<=search_results_rect.y+search_results_rect.h then
        search_results_scroll=math.max(0,math.min(search_results_scroll+(wheel>0 and -2 or 2),math.max(0,#search_results-shown_rows)))
    end
    if shown_rows>0 and #search_results>shown_rows then
        local track_x=x+panel_w-8; local track_h=shown_rows*row_h; local thumb_h=math.max(14,track_h*shown_rows/#search_results)
        local max_scroll=#search_results-shown_rows
        gfx.set(0.2,0.19,0.18,0.9); gfx.rect(track_x,list_y,4,track_h,1)
        local thumb_y=list_y+(track_h-thumb_h)*search_results_scroll/max_scroll
        gfx.set(0.65,0.53,0.32,0.95); gfx.rect(track_x,thumb_y,4,thumb_h,1)
        if gfx.mouse_cap==0 and mouse_was_down and gfx.mouse_x>=track_x-5 and gfx.mouse_x<=track_x+8 and gfx.mouse_y>=list_y and gfx.mouse_y<=list_y+track_h then
            search_results_scroll=math.floor(math.max(0,math.min(1,(gfx.mouse_y-list_y)/track_h))*max_scroll)
        end
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
    if #one_line > 160 then
        local finish=157
        while finish>0 and one_line:byte(finish+1)>=128 and one_line:byte(finish+1)<192 do finish=finish-1 end
        one_line=one_line:sub(1,finish).."..."
    end
    reaper.GetSetMediaItemInfo_String(item, "P_NAME", one_line, true)
    reaper.UpdateItemInProject(item)
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
    InlinePushUndo()
    InlineDeleteSelection()
    local source = inline_edit.text or ""
    local cursor = inline_edit.cursor or (#source + 1)
    inline_edit.text = source:sub(1, cursor - 1) .. text .. source:sub(cursor)
    inline_edit.cursor = cursor + #text
end

function InlineBackspace()
    if not inline_edit then return end
    InitInlineCopione()
    InlinePushUndo()
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
    InitInlineCopione()
    InlinePushUndo()
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
        w = math.max(300, w),
        h = math.max(master_font_size * 2.0, h),
        font_size = math.max(22, math.min(master_font_size, 46))
    }
    if click_x then
        gfx.setfont(1,default_font,master_font_size,'b')
        local source=inline_edit.text
        local prefix=ExtractSpeakerPrefix(source)
        local first,last,rel=1,#source,math.max(0,click_x-(x+12))
        if prefix~='' then
            local colon=source:find(':',1,true)
            local prefix_width=gfx.measurestr(prefix..' ')
            if rel>=prefix_width then first=colon+1;rel=rel-prefix_width else last=colon end
        end
        InlineSetCursor(ZP_TESTO.cursor_in_words(source,first,last,rel,gfx.measurestr))
        inline_edit.center_cursor=true
        inline_edit.opening_mouse_down=true
    end
    -- Aprire il testo conserva trasporto e posizione della timeline.
end

function SaveInlineSubtitleEdit()
    InitInlineCopione(); SyncInlineAnchors()
    if not inline_edit then return end
    if inline_edit.mode=='timed_new' then
        local text=inline_edit.text or ''
        if trim(text)=='' then inline_edit=nil; return end
        reaper.Undo_BeginBlock()
        local track=GetRythmoTrack()
        if not track then
            reaper.InsertTrackAtIndex(reaper.CountTracks(0),true)
            track=reaper.GetTrack(0,reaper.CountTracks(0)-1)
            reaper.GetSetMediaTrackInfo_String(track,'P_NAME',default_track_name,true)
        end
        local item=reaper.AddMediaItemToTrack(track)
        reaper.SetMediaItemInfo_Value(item,'D_POSITION',reaper.GetCursorPosition())
        local duration=TimedTextDuration(text,inline_edit.timed_wpm)
        reaper.SetMediaItemInfo_Value(item,'D_LENGTH',duration)
        reaper.GetSetMediaItemInfo_String(item,'P_NOTES',text,true)
        reaper.GetSetMediaItemInfo_String(item,'P_EXT:ZP_TIMED_SCROLL','1',true)
        reaper.GetSetMediaItemInfo_String(item,'P_EXT:ZP_TIMED_SCROLL_WPM',tostring(inline_edit.timed_wpm or 120),true)
        ApplyInlineMetadata(item); UpdateSubtitleItemName(item,text)
        reaper.Undo_EndBlock('ZP: importa copione temporizzato',-1)
        inline_edit=nil; reaper.UpdateArrange(); UpdateItems(); return
    end
    if not inline_edit.item then return end
    local new_text = (inline_edit.text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    if trim(new_text) ~= "" and (new_text ~= inline_edit.original or InlineHighlightRaw() ~= inline_edit.original_highlights or (inline_edit.timed_existing and inline_edit.timed_wpm~=inline_edit.original_wpm)) then
        reaper.Undo_BeginBlock()
        reaper.GetSetMediaItemInfo_String(inline_edit.item, "P_NOTES", new_text, true)
        ApplyInlineMetadata(inline_edit.item)
        UpdateSubtitleItemName(inline_edit.item, new_text)
        reaper.UpdateItemInProject(inline_edit.item)
        reaper.Undo_EndBlock("ZP Studio Suite: modifica testo inline dal gobbo orizzontale", -1)
        UpdateItems()
        last_proj_state = reaper.GetProjectStateChangeCount(0)
    end
    inline_edit = nil
end

function ProcessInlineSubtitleEditKey(char)
    if inline_edit then gfx.setfont(1,default_font,inline_edit.layout_font or math.min(28,inline_edit.font_size or 22)) end
    if not inline_edit or char <= 0 then return false end
    if char == 13 then
        if (gfx.mouse_cap & 8) == 8 then
            InlineInsertText("\n\n")
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
    elseif char == 26 then
        InlineRestoreUndo()
        return true
    elseif char == 24 then
        InlinePushUndo()
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


TimedTextDuration = function(text,wpm)
    local words,pauses=ZP_TESTO.stats(text)
    local lines=0
    for line in tostring(text):gmatch('[^\n]+') do if line:match('%S') then lines=lines+1 end end
    local rate=math.max(40,math.min(240,wpm or 120))
    local pause_seconds=math.max(1,words)/math.max(1,lines)*60/rate
    return math.max(5,words*60/rate)+pauses*pause_seconds,pauses,pause_seconds
end
function AddTimedGobboTextItem()
    inline_edit={mode='timed_new',text='',original='',cursor=1,font_size=22,timed_wpm=120,title=T('Nuovo testo temporizzato')}
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
    local first,last,rel=1,#item.notes,math.max(0,px-x)
    if item.speaker_prefix~='' then
        local colon=item.notes:find(':',1,true)
        if colon then
            if rel>=(item.prefix_w or 0) then first=colon+1;rel=rel-(item.prefix_w or 0) else last=colon end
        end
    end
    offset=ZP_TESTO.cursor_in_words(item.notes,first,last,rel,gfx.measurestr)
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
    local index=event.word-(item.reading_prefix_words or 0)
    local px,width=x,item.prefix_w or 0
    if index>0 then px=x+(item.prefix_w or 0)+(item.word_x[index] or 0);width=item.word_w[index] or 4 end
    gfx.set(0.25,0.65,1,0.28);gfx.rect(px-2,y-2,width+4,line_h,1)
    gfx.set(0.35,0.75,1,1);gfx.rect(px-2,y-2,2,line_h,1)
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
    gfx.drawstr(T("IMPOSTAZIONI GOBBO ORIZZONTALE"))

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
    gfx.drawstr(T("SCALA / VELOCITA"))
    
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
    gfx.drawstr(T("CORPO TESTO"))
    
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
        gfx.drawstr(T("ANTICIPO VOCE"))

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
        gfx.drawstr(T("Solo OSARA/NVDA, max 10 s"))
    end
    
    if changed then 
        show_settings_timer = 60 
        RecalculateLayout() 
    end
    
    return panel_y
end

-- Tendina del flusso testi (come nel Gobbo verticale): una traccia testo o "Tutti".
function ShowTextFlowMenu(mx, my)
    local tracks = CollectTextFlowTracks()
    if #tracks == 0 then return end
    local entries = {}
    if #tracks >= 2 then entries[#entries + 1] = { guid = READ_ALL, name = T("Tutti") } end
    for _, entry in ipairs(tracks) do
        entries[#entries + 1] = { guid = entry.guid, name = TextFlowDisplayName(entry.name) }
    end
    local current = CurrentTextFlowEntry()
    local current_guid = selected_text_track_guid == READ_ALL and READ_ALL or (current and current.guid or "")
    local parts = {}
    for i, entry in ipairs(entries) do
        local label = tostring(entry.name or ""):gsub("|", "/")
        if label:find("^[#!<>]") then label = " " .. label end
        parts[i] = ((entry.guid == current_guid) and "!" or "") .. label
    end
    gfx.x, gfx.y = mx, my
    local choice = gfx.showmenu(table.concat(parts, "|"))
    if choice and choice > 0 and entries[choice] then SelectTextFlow(entries[choice].guid) end
end

function DrawAlertStrip(w, strip_h, play_pos, attack_x)
    gfx.set(0.075, 0.07, 0.055, 1)
    gfx.rect(0, 0, w, strip_h, 1)
    gfx.set(0.45, 0.34, 0.15, 0.85)
    gfx.rect(0, strip_h - 1, w, 1, 1)

    gfx.setfont(3, "Arial", 15, 'b')
    gfx.set(0.95, 0.82, 0.40, 1)
    gfx.x, gfx.y = 12, 8
    gfx.drawstr(T("GOBBO ORIZZONTALE"))

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
    local suite_label = ("ZP Studio Suite " .. ZP_UI.suite_version())
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
    if max_label_w>280 then ZP_UI.draw_credit(label_x,8,11) else gfx.drawstr(label) end

    local studio_label = studio_edit_mode and T("Studio/Edit ON") or T("Studio/Edit OFF")
    if DrawButton(w - 282, 29, 138, 24, studio_label, 0.20, 0.48, 0.40, studio_edit_mode) then
        SetStudioEditMode(not studio_edit_mode)
    end
    if DrawButton(w - 138, 29, 28, 24, "?", 0.22, 0.30, 0.42) then zp_open_help_section("tool-03") end

    if w>=740 and DrawButton(w-108,29,96,24,T('Carica file…'),0.2,0.4,0.5) then
        AddTimedGobboTextItem(); InlineLoadFile()
    end
    local flow_label = CurrentTextFlowLabel()
    if #flow_label > 20 then flow_label = flow_label:sub(1, 19) .. "." end
    -- flusso a tendina: un clic apre l'elenco delle tracce testo e "Tutti"
    gfx.setfont(3, "Arial", 16, 'b')
    local flow_text = T("Testi:") .. " " .. flow_label .. "  ▾"
    local flow_w = math.max(120, gfx.measurestr(flow_text) + 20)
    if DrawButton(12, 30, flow_w, 22, flow_text, 0.22, 0.30, 0.42) then ShowTextFlowMenu(12, 52) end
    -- Segui i tagli: accanto al flusso, solo se c'e' spazio prima di Studio/Edit
    local follow_x = 12 + flow_w + 14
    if follow_x + 120 < w - 290 then
        if DrawButton(follow_x, 30, 120, 22, FollowLabel(), 0.22, 0.38, 0.52, FollowEnabled()) then
            if FollowScriptPath() then ToggleFollow() end
        end
    end

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
    if item.reading_plan and (play_pos or item.pos)>=item.pos and (play_pos or item.pos)<item.pos+item.len then
        local p=((play_pos or item.pos)-item.pos)/math.max(0.001,item.len)
        local state=ZP_TESTO.reading_state(item.reading_plan,p)
        item.reading_state=state
        local phase=math.max(0,state.word_phase-(item.reading_prefix_words or 0))
        local index=math.min(#item.word_x,math.floor(phase)+1)
        local start=item.word_x[index] or 0
        local next_x=item.word_x[index+1] or start+(item.word_w[index] or 0)
        local offset=start+(next_x-start)*math.min(1,phase-(index-1))
        if state.paused then
            local previous=math.max(0,state.word-(item.reading_prefix_words or 0))
            offset=previous>0 and (item.word_x[previous] or 0)+(item.word_w[previous] or 0) or 0
        end
        return reading_x-(item.prefix_w or 0)-offset
    end
    item.reading_state=nil
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
        -- larghezze gia' misurate da RecalculateLayout con lo stesso font
        local known_w = words == item.words and item.word_w or nil
        for word_index, word in ipairs(words) do
            local word_w = known_w and known_w[word_index] or gfx.measurestr(word)

            local word_center = cursor_x + (word_w * 0.5)
            local dist = word_center - reading_x
            local spectrum = 0
            if dist >= 0 and dist <= right_glow then
                spectrum = 1 - (dist / right_glow)
            elseif dist < 0 and math.abs(dist) <= left_glow then
                spectrum = 1 - (math.abs(dist) / left_glow)
            end

            if item.reading_state and item.reading_state.paused and word_index>item.reading_state.word-(item.reading_prefix_words or 0) then spectrum=0 end
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

    local is_active = smoothed_play_pos >= item.pos and (smoothed_play_pos < item.pos + item.len or not item.timed_scroll and smoothed_play_pos <= item.pos + item.len)
    return {
        item = item,
        start_px = start_px,
        end_px = end_px,
        bg_w = bg_w,
        is_active = is_active,
        alpha = WordModeAlpha(item, smoothed_play_pos),
        item_y = group_start_y + item.y_offs,
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
    local text_y=item_y+(box_h-text_h)/2
    HandleSubtitleEditDoubleClick(item,job.start_px,text_y,job.bg_w,text_h)
    HandleGobboWordAnchorMenu(item,job.start_px,text_y,job.bg_w,text_h)
    DrawGobboWordSelection(item,job.start_px,text_y,item.line_h)
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
    if char > 0 and (char==12 or ((gfx.mouse_cap&4)~=0 or (gfx.mouse_cap&32)~=0) and (char==76 or char==108)) then
        AddTimedGobboTextItem(); InlineLoadFile(); char=0
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

    if inline_edit then inline_edit.wheel=gfx.mouse_wheel or 0; gfx.mouse_wheel=0 end
    FollowTick()
    local track = IsValidTrack(current_text_track) and current_text_track or GetRythmoTrack()
    if not IsValidTrack(track) then
        current_text_track = nil
        track = nil
    end
    local track_guid = selected_text_track_guid == READ_ALL and READ_ALL or (track and reaper.GetTrackGUID(track) or "")
    local proj_state = reaper.GetProjectStateChangeCount(0)

    if proj_state ~= last_proj_state or track_guid ~= last_track_guid then
        last_proj_state = proj_state
        last_track_guid = track_guid
        UpdateItems()
        UpdateWindowTitle()
    end

    local smoothed_play_pos = GetContinuousPlayPosition()
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
        local warn_text = T("Seleziona la traccia testi per ZP Studio Suite!")
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
        local hud_txt = string.format(T("SCALA: %d px/s | CORPO: %d | ANTICIPO VOCE: %.1fs"), pixels_per_second, master_font_size, accessibility_speech_lead)
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
    if not inline_edit then
        for _,item in ipairs(cached_items) do
            if item.timed_scroll and smoothed_play_pos>=item.pos and smoothed_play_pos<item.pos+item.len then
                local p=math.max(0,math.min(1,(smoothed_play_pos-item.pos)/math.max(0.001,item.len)))
                gfx.set(0.35,0.8,0.62,0.95); gfx.rect(8,band_y+band_h-4,(w-16)*p,3,1); break
            end
        end
    end
    DrawInlineSubtitleEditor()
    if not inline_edit then DrawSearchPanel(w, h) end

    mouse_was_down = (gfx.mouse_cap & 1) == 1
    if (gfx.mouse_cap&2)==0 then gobbo_word_right_down=false end
    gfx.update()
    reaper.defer(DrawGUI)
end

LoadHorizontalSettings()
InitGUI()
DrawGUI()
