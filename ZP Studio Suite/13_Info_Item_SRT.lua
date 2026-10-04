-- @noindex

-- INFO ITEM SRT RYTHMOBAND
-- Linea: ZP Paolo Balestri
-- Suite: ZP Studio Suite for REAPER
-- Distribuzione gratuita.
--
-- Finestra di sola lettura sull'item selezionato: da dove viene il testo (SRT importato,
-- marker dell'audio agganciato, scritto a mano), posizione, durata e testo.
-- Resta aperta e si aggiorna da sola quando selezioni un altro item: si esplora la
-- timeline senza riaprirla. La chiudi tu (Chiudi, Esc o la X). Non modifica niente.

local TITLE = "ZP Studio Suite - Info item SRT"
local sep = package.config:sub(1, 1)
local here = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or ".")
local ok_ui, UI = pcall(dofile, here .. sep .. "ZP_UI.lua")
if not ok_ui then
  reaper.ShowMessageBox("Non trovo ZP_UI.lua accanto allo script.", TITLE, 0)
  return
end

local function trim(s)
  local out = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return out
end

local function file_exists(path)
  if not path or path == "" then return false end
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function basename(path)
  return (path or ""):match("[^/\\]+$") or (path or "")
end

local function get_item_string(item, key)
  local _, value = reaper.GetSetMediaItemInfo_String(item, key, "", false)
  return trim(value)
end

local function get_track_name(track)
  if not track then return "" end
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  return trim(name)
end

local function format_time(seconds)
  if reaper.format_timestr_pos then
    return reaper.format_timestr_pos(seconds or 0, "", 5)
  end
  return string.format("%.3f", seconds or 0)
end

-- Sezioni da mostrare per l'item: { {title, { {label, value}, ... }, text = "..."}, ... }
local function describe(item, count)
  local track = reaper.GetMediaItemTrack(item)
  local take = reaper.GetActiveTake(item)
  local src = take and reaper.GetMediaItemTake_Source(take)
  local src_path = src and reaper.GetMediaSourceFileName(src, "") or ""
  local item_name = get_item_string(item, "P_NAME")
  local text = get_item_string(item, "P_NOTES")
  local sections = {}

  local gen = {
    { "Traccia", get_track_name(track) ~= "" and get_track_name(track) or "(senza nome)" },
    { "Item", item_name ~= "" and item_name or (src_path ~= "" and basename(src_path) or "(senza nome)") },
    { "Posizione", format_time(reaper.GetMediaItemInfo_Value(item, "D_POSITION")) },
    { "Durata", format_time(reaper.GetMediaItemInfo_Value(item, "D_LENGTH")) },
  }
  if count > 1 then table.insert(gen, 1, { "Selezionati", tostring(count) .. " item (mostro il primo)" }) end
  sections[#sections + 1] = { "Item", gen }

  local srt_path = get_item_string(item, "P_EXT:RythmoBand_SRT_PATH")
  local srt_file = get_item_string(item, "P_EXT:RythmoBand_SRT_FILE")
  local srt_cue = get_item_string(item, "P_EXT:RythmoBand_SRT_CUE")
  local sync_key = get_item_string(item, "P_EXT:ZP_SYNC_KEY")
  if srt_file == "" and srt_path ~= "" then srt_file = basename(srt_path) end

  local origin = {}
  if src_path ~= "" then
    -- item audio: i suoi testi stanno nei marker, non qui
    local markers = take and reaper.GetNumTakeMarkers(take) or 0
    local sidecar = src_path:gsub("%.[^./\\]+$", "") .. ".srt"
    origin[#origin + 1] = { "Tipo", "item audio (non e' un item di testo)" }
    origin[#origin + 1] = { "File", basename(src_path) }
    origin[#origin + 1] = { "Marker delle battute", tostring(markers) }
    origin[#origin + 1] = { "SRT accanto al file", file_exists(sidecar) and "presente" or "no" }
    origin[#origin + 1] = { "", markers > 0 and "I testi sono nel gobbo, sulle tracce Rythmo Band Testi."
      or "Per avere i testi: 29 ZP Trascrizione (Trascrivi o Abbina da...)." }
  elseif sync_key ~= "" then
    origin[#origin + 1] = { "Tipo", "testo agganciato a un marker dell'audio" }
    origin[#origin + 1] = { "", "Segue tagli e spostamenti dell'audio (29, Segui i tagli)." }
    if reaper.GetMediaItemInfo_Value(item, "B_MUTE") == 1 then
      origin[#origin + 1] = { "Stato", "in mute: il suo marker non c'e' piu', ma l'avevi corretto a mano" }
    end
  elseif srt_path ~= "" or srt_file ~= "" or srt_cue ~= "" then
    origin[#origin + 1] = { "Tipo", "importato da SRT" }
    origin[#origin + 1] = { "File", srt_file ~= "" and srt_file or "(non salvato)" }
    origin[#origin + 1] = { "Cue", srt_cue ~= "" and srt_cue or "(non salvata)" }
    if srt_path ~= "" then
      origin[#origin + 1] = { "Percorso", srt_path }
      origin[#origin + 1] = { "Stato file", file_exists(srt_path) and "trovato" or "non trovato" }
    end
  else
    origin[#origin + 1] = { "Tipo", "testo senza origine registrata" }
    origin[#origin + 1] = { "", "Scritto a mano, o importato prima che la Suite salvasse l'origine (per averla: Importa / Sostituisci testi)." }
  end
  sections[#sections + 1] = { "Origine", origin }
  sections.text = (src_path == "") and (text ~= "" and text or "(vuoto)") or nil
  return sections
end

local function summary_for_osara(sections)
  local parts = {}
  for _, sec in ipairs(sections) do
    for _, kv in ipairs(sec[2]) do parts[#parts + 1] = (kv[1] ~= "" and (kv[1] .. ": ") or "") .. kv[2] end
  end
  if sections.text then parts[#parts + 1] = "Testo: " .. sections.text end
  return table.concat(parts, ". ")
end

local last_item, last_count, sections = nil, -1, nil
local last_down = false

local function refresh()
  local count = reaper.CountSelectedMediaItems(0)
  local item = count > 0 and reaper.GetSelectedMediaItem(0, 0) or nil
  if item == last_item and count == last_count and sections then return end
  last_item, last_count = item, count
  sections = item and describe(item, count) or nil
  if reaper.osara_outputMessage then
    reaper.osara_outputMessage(sections and summary_for_osara(sections) or "Nessun item selezionato.")
  end
end

local function draw_lines(lines, x, y, lh)
  for i, l in ipairs(lines) do
    gfx.x, gfx.y = x, y + (i - 1) * lh
    gfx.drawstr(l)
  end
  return y + #lines * lh
end

gfx.init(TITLE, 620, 520, 0)

local function loop()
  local ch = gfx.getchar()
  if ch < 0 or ch == 27 then gfx.quit() return end
  local down = (gfx.mouse_cap & 1) == 1
  local clicked = down and not last_down
  last_down = down

  refresh()
  UI.fill_background()
  UI.draw_header({ title = "Info item SRT", credit = "ZP Studio Suite - 13",
    description = "Seleziona un item: la finestra si aggiorna da sola. Sola lettura." })
  UI.draw_help_button({ x = gfx.w - 54, y = 16, w = 34, h = 28 }, clicked, "tool-13")

  local x, y, w = 22, 92, gfx.w - 44
  if not sections then
    gfx.setfont(1, "Arial", 16)
    UI.set_color(UI.colors.muted)
    gfx.x, gfx.y = x, y
    gfx.drawstr("Nessun item selezionato.")
  else
    for _, sec in ipairs(sections) do
      gfx.setfont(1, "Arial", 15, string.byte("b"))
      UI.set_color(UI.colors.title)
      gfx.x, gfx.y = x, y
      gfx.drawstr(sec[1])
      y = y + 24
      for _, kv in ipairs(sec[2]) do
        local lw = 0
        if kv[1] ~= "" then
          gfx.setfont(1, "Arial", 14)
          UI.set_color(UI.colors.muted)
          gfx.x, gfx.y = x, y
          gfx.drawstr(kv[1])
          lw = 150
        end
        gfx.setfont(1, "Arial", 15)
        UI.set_color(UI.colors.text)
        y = draw_lines(UI.wrap_text(kv[2], w - lw), x + lw, y, 20) + 2
      end
      y = y + 12
    end
    if sections.text then
      gfx.setfont(1, "Arial", 15, string.byte("b"))
      UI.set_color(UI.colors.title)
      gfx.x, gfx.y = x, y
      gfx.drawstr("Testo")
      y = y + 26
      gfx.setfont(1, "Arial", 18)
      UI.set_color(UI.colors.text)
      draw_lines(UI.wrap_text(sections.text, w), x, y, 24)
    end
  end

  if UI.draw_button({ x = gfx.w - 22 - 110, y = gfx.h - 22 - 34, w = 110, h = 34 }, "Chiudi", false, true, clicked, "tab") then
    gfx.quit()
    return
  end

  gfx.update()
  reaper.defer(loop)
end

loop()
