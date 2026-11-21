-- @noindex
-- @description ZP Clean & Paint — Restauro CoreML, Riverniciatura e Voice Morphing RVC per REAPER 7
-- @version 1.0.1
-- @author Paolo Balestri / Antigravity
-- @about
--   Pannello operativo offline (zero CPU/RAM a riposo) collegato a ZP Voice Model Lab:
--   - Modalità SOLO CLEAN: De-Reverb + Bandwidth Extension CoreML (per interviste/ospiti)
--   - Modalità SOLO PAINT: Voice Morphing RVC v2 con Pitch e Formanti (per doppiaggio personaggi)
--   - Modalità CLEAN + PAINT: Pulizia + Riverniciatura completa sulla tua voce (LoZio.pth)
--   Supporta Preascolto Rapido 4s, salvataggio Preset e inserimento su Fixed Item Lanes (REAPER 7) o Nuova Take.
-- Provenienza ZP: Suite 2.6.8 beta; acquisito dal progetto motore locale il 2026-11-21.
-- Il motore ZP Voice Model Lab resta esterno, in sviluppo e non viene distribuito dalla Suite.

local IS_WIN = (reaper.GetOS():match("Win") ~= nil)

local function resolve_lab_root()
  local appdata = os.getenv("APPDATA") or ""
  if appdata ~= "" then
    local ptr = io.open(appdata .. "/ZP_Clean_Paint/lab_root_path.txt", "r")
    if ptr then
      local p = ptr:read("*l")
      ptr:close()
      if p then p = p:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[/\\]+$", "") end
      if p and p ~= "" then return p end
    end
  end
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""
  if home ~= "" then
    local ptr = io.open(home .. "/Library/Application Support/ZP_Clean_Paint/lab_root_path.txt", "r")
    if ptr then
      local p = ptr:read("*l")
      ptr:close()
      if p then p = p:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[/\\]+$", "") end
      if p and p ~= "" then return p end
    end
  end
  local script_src = debug.getinfo(1, "S").source or ""
  if script_src:sub(1, 1) == "@" then script_src = script_src:sub(2) end
  local script_dir = script_src:match("^(.*)[/\\][^/\\]+$") or "."
  -- Se lo script è dentro reaper_scripts/ o nella root del progetto
  local f1 = io.open(script_dir .. "/zp_clean_paint_webapp.py", "r")
  if f1 then f1:close(); return script_dir end
  local parent_dir = script_dir:match("^(.*)[/\\][^/\\]+$")
  if parent_dir then
    local f2 = io.open(parent_dir .. "/zp_clean_paint_webapp.py", "r")
    if f2 then f2:close(); return parent_dir end
  end
  return nil
end

local LAB_ROOT = resolve_lab_root()
if not LAB_ROOT or LAB_ROOT == "" then
  reaper.MB(
    "Motore ZP Clean & Paint non configurato.\n\nImposta il percorso di ZP Voice Model Lab in lab_root_path.txt dentro ZP_Clean_Paint.",
    "ZP Clean & Paint (beta)",
    0
  )
  return
end
local PYTHON_BIN = IS_WIN
  and (LAB_ROOT .. "/engines/rvc_local/.venv/Scripts/python.exe")
  or  (LAB_ROOT .. "/engines/rvc_local/.venv/bin/python")
local CLI_SCRIPT = LAB_ROOT .. "/engines/rvc_local/zp_clean_paint_cli.py"
local PRESETS_PATH = LAB_ROOT .. "/data/paint_presets.json"
local PREVIEW_WAV = LAB_ROOT .. "/data/outputs/_reaper_preview_4s.wav"

local function readable_file(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end
if not readable_file(CLI_SCRIPT) or not readable_file(PYTHON_BIN) or not readable_file(PRESETS_PATH) then
  reaper.MB(
    "Il motore Clean & Paint è configurato ma incompleto.\n\nServono CLI, Python dell'ambiente locale e paint_presets.json. La beta 2.6.8 resta in sviluppo.",
    "ZP Clean & Paint (beta)",
    0
  )
  return
end

-- Stato UI
local state = {
  mode = "both",              -- "clean" | "paint" | "both"
  clean_model = "htdemucs_bwe_restore",
  voice_model = "LoZio.pth",
  index_file = "added_IVF1590_Flat_nprobe_1_LoZio_v2.index",
  pitch = 0,                  -- semitoni (-6 .. +6)
  formant = 1.00,             -- 0.80 .. 1.20
  index_rate = 0.70,
  protect = 0.40,
  target_dest = "lane",       -- "lane" (Fixed Item Lane 2) | "take" (Nuova Take sull'Item)
  preset_idx = 1,
  presets = {
    { id = "paolo_studio_u87", name = "Paolo Studio U87 (Clean + Paint)", mode = "both", clean_model = "htdemucs_bwe_restore", voice_model = "LoZio.pth", pitch = 0, formant = 1.00 },
    { id = "char_ispettore_ruvido", name = "Personaggio: Ispettore Ruvido", mode = "paint", clean_model = "htdemucs_bwe_restore", voice_model = "LoZio.pth", pitch = -2, formant = 0.88 },
    { id = "char_ragazzo_giovane", name = "Personaggio: Ragazzo Giovane", mode = "paint", clean_model = "htdemucs_bwe_restore", voice_model = "LoZio.pth", pitch = 3, formant = 1.12 },
    { id = "ospite_podcast_bwe", name = "Ospite Remoto (Solo Clean + Alte)", mode = "clean", clean_model = "htdemucs_bwe_restore", voice_model = "LoZio.pth", pitch = 0, formant = 1.00 },
  },
  status_msg = "Pronto. Seleziona un Item in REAPER (Zero CPU/GPU occupate a riposo).",
  busy = false,
  prev_mouse_cap = 0,
}

local function sh_quote(s)
  if IS_WIN then
    return '"' .. tostring(s):gsub('"', '\\"') .. '"'
  end
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function apply_preset(idx)
  local p = state.presets[idx]
  if not p then return end
  state.preset_idx = idx
  state.mode = p.mode
  state.clean_model = p.clean_model
  state.voice_model = p.voice_model
  state.pitch = p.pitch
  state.formant = p.formant
  state.status_msg = "Preset caricato: " .. p.name
end

-- Recupera informazioni sul primo item selezionato
local function get_selected_item_info()
  local item = reaper.GetSelectedMediaItem(0, 0)
  if not item then return nil, "Nessun Item selezionato nella timeline!" end
  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then return nil, "L'item selezionato non contiene una take audio." end
  local src = reaper.GetMediaItemTake_Source(take)
  local src_file = reaper.GetMediaSourceFileName(src, "")
  if not src_file or src_file == "" then return nil, "File sorgente non trovato per la take attiva." end

  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local start_offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local playrate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local track = reaper.GetMediaItem_Track(item)

  return {
    item = item,
    take = take,
    track = track,
    src_file = src_file,
    item_pos = item_pos,
    item_len = item_len,
    start_offs = start_offs,
    playrate = playrate,
  }, nil
end

local function get_output_dir_for_item(src_file)
  local _, proj_fn = reaper.EnumProjects(-1, "")
  if proj_fn and proj_fn ~= "" then
    local proj_dir = proj_fn:match("^(.*)[/\\][^/\\]+$")
    if proj_dir and proj_dir ~= "" then
      return proj_dir .. "/ZP_Clean_Paint_Audio"
    end
  end
  local src_dir = src_file:match("^(.*)[/\\][^/\\]+$")
  if src_dir and src_dir ~= "" then
    return src_dir .. "/ZP_Clean_Paint_Audio"
  end
  return LAB_ROOT .. "/data/outputs"
end

local function basename_no_ext(path)
  local name = path:match("[^/\\]+$") or "item"
  return name:gsub("%.[^%.]+$", "")
end

-- Esegue Preascolto 4s
local function run_preview_4s()
  local info, err = get_selected_item_info()
  if not info then
    state.status_msg = "ERRORE: " .. err
    return
  end

  state.status_msg = "Calcolo Preascolto 4s in corso..."
  gfx.update()

  local preview_dur = math.min(4.0, info.item_len)
  local cmd = string.format(
    "%s %s --input %s --output %s --mode %s --clean-model %s --voice-model %s --index-file %s --pitch %d --formant %.2f --index-rate %.2f --protect %.2f --start-sec %.4f --duration-sec %.4f 2>&1",
    sh_quote(PYTHON_BIN),
    sh_quote(CLI_SCRIPT),
    sh_quote(info.src_file),
    sh_quote(PREVIEW_WAV),
    sh_quote(state.mode),
    sh_quote(state.clean_model),
    sh_quote(state.voice_model),
    sh_quote(state.index_file),
    state.pitch,
    state.formant,
    state.index_rate,
    state.protect,
    info.start_offs,
    preview_dur
  )

  local out = reaper.ExecProcess(cmd, 120000) or ""
  local f = io.open(PREVIEW_WAV, "rb")
  if not f then
    state.status_msg = "Errore Preascolto: vedi console ReaScript."
    reaper.ShowConsoleMsg(out .. "\n")
    return
  end
  f:close()

  -- Riproduce subito il preascolto in cuffia tramite afplay (non blocca REAPER)
  os.execute("afplay " .. sh_quote(PREVIEW_WAV) .. " &")
  state.status_msg = string.format("Preascolto 4s in riproduzione (Pitch %+d st, Formanti %.2fx)!", state.pitch, state.formant)
end

-- Inserisce il file processato in Fixed Item Lane 2 oppure come Nuova Take
local function insert_processed_audio(info, out_wav, label_tag)
  reaper.Undo_BeginBlock()

  if state.target_dest == "lane" then
    local track = info.track
    -- Attiva Fixed Item Lanes sulla traccia (I_FREEMODE = 2 in REAPER 7)
    local freemode = reaper.GetMediaTrackInfo_Value(track, "I_FREEMODE")
    if freemode ~= 2 then
      reaper.SetMediaTrackInfo_Value(track, "I_FREEMODE", 2)
    end
    local num_lanes = reaper.GetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES")
    if num_lanes < 2 then
      reaper.SetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES", 2)
    end

    -- Assicura che l'item originale stia sulla Lane 0 (prima corsia)
    reaper.SetMediaItemInfo_Value(info.item, "I_FIXEDLANE", 0)

    -- Crea il nuovo item nella Lane 1 (seconda corsia) esattamente sotto l'originale
    local new_item = reaper.AddMediaItemToTrack(track)
    reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", info.item_pos)
    reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", info.item_len)
    reaper.SetMediaItemInfo_Value(new_item, "I_FIXEDLANE", 1)

    local new_take = reaper.AddTakeToMediaItem(new_item)
    local pcm_src = reaper.PCM_Source_CreateFromFile(out_wav)
    reaper.SetMediaItemTake_Source(new_take, pcm_src)
    reaper.SetMediaItemTakeInfo_Value(new_take, "D_STARTOFFS", 0.0)
    reaper.GetSetMediaItemTakeInfo_String(new_take, "P_NAME", label_tag, true)

    -- Attiva l'ascolto sulla Lane 2 (indice 1)
    reaper.SetMediaTrackInfo_Value(track, "C_LANEPLAYS:1", 1)
    reaper.SetMediaTrackInfo_Value(track, "C_LANEPLAYS:0", 0)
  else
    -- Modalità Take classica sopra lo stesso Item
    local new_take = reaper.AddTakeToMediaItem(info.item)
    local pcm_src = reaper.PCM_Source_CreateFromFile(out_wav)
    reaper.SetMediaItemTake_Source(new_take, pcm_src)
    reaper.SetMediaItemTakeInfo_Value(new_take, "D_STARTOFFS", 0.0)
    reaper.GetSetMediaItemTakeInfo_String(new_take, "P_NAME", label_tag, true)
    reaper.SetActiveTake(new_take)
  end

  reaper.Main_OnCommand(40047, 0) -- Build any missing peaks
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("ZP Clean & Paint: " .. label_tag, -1)
end

local function run_apply_selected_items()
  local count = reaper.CountSelectedMediaItems(0)
  if count == 0 then
    state.status_msg = "Seleziona almeno un Item audio nella timeline!"
    return
  end

  -- Raccoglie tutti gli item selezionati prima di iniziare
  local items_list = {}
  for i = 0, count - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local tk = it and reaper.GetActiveTake(it)
    if tk and not reaper.TakeIsMIDI(tk) then
      local src = reaper.GetMediaItemTake_Source(tk)
      local src_file = reaper.GetMediaSourceFileName(src, "")
      if src_file and src_file ~= "" then
        items_list[#items_list + 1] = {
          item = it,
          take = tk,
          track = reaper.GetMediaItem_Track(it),
          src_file = src_file,
          item_pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION"),
          item_len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH"),
          start_offs = reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS"),
        }
      end
    end
  end

  if #items_list == 0 then
    state.status_msg = "Nessun item audio valido selezionato."
    return
  end

  for idx, info in ipairs(items_list) do
    state.status_msg = string.format("Elaborazione %d/%d in corso...", idx, #items_list)
    gfx.update()

    local out_dir = get_output_dir_for_item(info.src_file)
    local stem = basename_no_ext(info.src_file)
    local ts = os.date("%H%M%S")
    local tag_short = state.mode == "clean" and "ZP-Clean"
      or (state.mode == "paint" and string.format("ZP-Paint_%+dst", state.pitch))
      or string.format("ZP-CleanPaint_%+dst", state.pitch)
    local out_wav = string.format("%s/%s_%s_%s_%d.wav", out_dir, stem, tag_short, ts, idx)

    local cmd = string.format(
      "%s %s --input %s --output %s --mode %s --clean-model %s --voice-model %s --index-file %s --pitch %d --formant %.2f --index-rate %.2f --protect %.2f --start-sec %.4f --duration-sec %.4f 2>&1",
      sh_quote(PYTHON_BIN),
      sh_quote(CLI_SCRIPT),
      sh_quote(info.src_file),
      sh_quote(out_wav),
      sh_quote(state.mode),
      sh_quote(state.clean_model),
      sh_quote(state.voice_model),
      sh_quote(state.index_file),
      state.pitch,
      state.formant,
      state.index_rate,
      state.protect,
      info.start_offs,
      info.item_len
    )

    local out = reaper.ExecProcess(cmd, 300000) or ""
    local f = io.open(out_wav, "rb")
    if f then
      f:close()
      local label = string.format("[%s] %s", tag_short, stem)
      insert_processed_audio(info, out_wav, label)
    else
      reaper.ShowConsoleMsg("Errore ZP Clean & Paint:\n" .. out .. "\n")
      state.status_msg = "Errore durante l'elaborazione (vedi console REAPER)."
      return
    end
  end

  state.status_msg = string.format("Completato! %d item inseriti in %s (RAM/GPU liberata: 0 MB).",
    #items_list, state.target_dest == "lane" and "Fixed Lane 2" or "Nuova Take")
end

-- Helper disegno GUI
local function set_color(r, g, b, a)
  gfx.set(r / 255, g / 255, b / 255, a or 1.0)
end

local function draw_box(x, y, w, h, r, g, b, fill)
  set_color(r, g, b, 1.0)
  gfx.rect(x, y, w, h, fill and 1 or 0)
end

local function mouse_in(x, y, w, h)
  return gfx.mouse_x >= x and gfx.mouse_x <= x + w and gfx.mouse_y >= y and gfx.mouse_y <= y + h
end

local function draw_button(x, y, w, h, label, bg_r, bg_g, bg_b, fg_r, fg_g, fg_b, active_border)
  local hover = mouse_in(x, y, w, h)
  local boost = hover and 18 or 0
  draw_box(x, y, w, h, math.min(255, bg_r + boost), math.min(255, bg_g + boost), math.min(255, bg_b + boost), true)
  if active_border then
    draw_box(x, y, w, h, 245, 175, 45, false)
    draw_box(x + 1, y + 1, w - 2, h - 2, 245, 175, 45, false)
  else
    draw_box(x, y, w, h, 75, 82, 95, false)
  end
  gfx.setfont(1, "Helvetica", 13, string.byte("b"))
  set_color(fg_r, fg_g, fg_b, 1.0)
  local tw, th = gfx.measurestr(label)
  gfx.x = x + (w - tw) * 0.5
  gfx.y = y + (h - th) * 0.5
  gfx.drawstr(label)
  local clicked = hover and (gfx.mouse_cap & 1 == 1) and (state.prev_mouse_cap & 1 == 0)
  return clicked
end

local function loop()
  if gfx.getchar() < 0 then return end

  -- Sfondo principale
  draw_box(0, 0, gfx.w, gfx.h, 28, 31, 36, true)

  -- Header
  draw_box(0, 0, gfx.w, 38, 38, 43, 51, true)
  gfx.setfont(1, "Helvetica", 15, string.byte("b"))
  set_color(245, 185, 55)
  gfx.x, gfx.y = 14, 10
  gfx.drawstr("ZP CLEAN & PAINT v1.0")

  gfx.setfont(1, "Helvetica", 12, 0)
  set_color(95, 220, 145)
  gfx.x, gfx.y = gfx.w - 195, 12
  gfx.drawstr("● Motore Spento a Riposo (0 MB)")

  local y = 50
  -- 1. Selettore Preset + Pulsante [+ Salva]
  gfx.setfont(1, "Helvetica", 12, string.byte("b"))
  set_color(180, 188, 200)
  gfx.x, gfx.y = 14, y
  gfx.drawstr("1. PRESET TAVOLOZZA (Clicca per scorrere o salva nuovo):")
  y = y + 20

  local p_label = state.presets[state.preset_idx].name .. "  ▾"
  if draw_button(14, y, gfx.w - 116, 30, p_label, 44, 50, 60, 240, 244, 250, false) then
    local next_idx = (state.preset_idx % #state.presets) + 1
    apply_preset(next_idx)
  end
  if draw_button(gfx.w - 96, y, 82, 30, "+ Salva", 65, 52, 28, 250, 205, 95, false) then
    local ok, new_name = reaper.GetUserInputs("Salva Preset ZP Clean & Paint", 1, "Nome Preset Personaggio:,extrawidth=120", "Personaggio Custom")
    if ok and new_name and new_name ~= "" then
      local new_id = "custom_" .. tostring(os.time())
      state.presets[#state.presets + 1] = {
        id = new_id,
        name = new_name,
        mode = state.mode,
        clean_model = state.clean_model,
        voice_model = state.voice_model,
        pitch = state.pitch,
        formant = state.formant,
      }
      state.preset_idx = #state.presets
      state.status_msg = "Salvato preset: " .. new_name
    end
  end
  y = y + 42

  -- 2. Scelta Modalità (CLEAN / PAINT / CLEAN+PAINT)
  gfx.setfont(1, "Helvetica", 12, string.byte("b"))
  set_color(180, 188, 200)
  gfx.x, gfx.y = 14, y
  gfx.drawstr("2. MODALITA' OPERATIVA:")
  y = y + 20

  local bw = math.floor((gfx.w - 40) / 3)
  if draw_button(14, y, bw, 34, "SOLO CLEAN", 32, 65, 62, 160, 245, 225, state.mode == "clean") then
    state.mode = "clean"
  end
  if draw_button(14 + bw + 6, y, bw, 34, "SOLO PAINT", 58, 42, 78, 220, 185, 255, state.mode == "paint") then
    state.mode = "paint"
  end
  if draw_button(14 + (bw + 6) * 2, y, bw, 34, "CLEAN + PAINT", 75, 58, 28, 255, 215, 120, state.mode == "both") then
    state.mode = "both"
  end
  y = y + 46

  -- 3. Modello Clean
  gfx.setfont(1, "Helvetica", 12, string.byte("b"))
  set_color(140, 215, 200)
  gfx.x, gfx.y = 14, y
  gfx.drawstr("STADIO 1 CLEAN (CoreML):")
  local cm_label = state.clean_model == "htdemucs_bwe_restore"
    and "htdemucs_bwe_restore (De-Reverb + Alte Freq BWE)"
    or "htdemucs_denoise_dereverb (Solo Pulizia Pura)"
  if draw_button(180, y - 5, gfx.w - 194, 26, cm_label, 36, 46, 52, 210, 235, 230, false) then
    if state.clean_model == "htdemucs_bwe_restore" then
      state.clean_model = "htdemucs_denoise_dereverb"
    else
      state.clean_model = "htdemucs_bwe_restore"
    end
  end
  y = y + 34

  -- 4. Controlli Paint (Pitch & Formanti)
  gfx.setfont(1, "Helvetica", 12, string.byte("b"))
  set_color(210, 175, 250)
  gfx.x, gfx.y = 14, y
  gfx.drawstr("STADIO 2 PAINT — Pitch (F0) & Formanti (Gola):")
  y = y + 22

  -- Pitch [- / valore / +]
  if draw_button(14, y, 36, 28, "-", 48, 52, 62, 240, 240, 240, false) then
    state.pitch = math.max(-12, state.pitch - 1)
  end
  draw_box(54, y, 120, 28, 34, 38, 46, true)
  gfx.x, gfx.y = 66, y + 7
  set_color(240, 240, 245)
  gfx.drawstr(string.format("Pitch: %+d st", state.pitch))
  if draw_button(178, y, 36, 28, "+", 48, 52, 62, 240, 240, 240, false) then
    state.pitch = math.min(12, state.pitch + 1)
  end

  -- Formanti [- / valore / +]
  if draw_button(232, y, 36, 28, "-", 48, 52, 62, 240, 240, 240, false) then
    state.formant = math.max(0.80, math.floor((state.formant - 0.02) * 100 + 0.5) / 100)
  end
  draw_box(272, y, 145, 28, 34, 38, 46, true)
  gfx.x, gfx.y = 282, y + 7
  set_color(240, 240, 245)
  gfx.drawstr(string.format("Formanti: %.2fx", state.formant))
  if draw_button(421, y, 36, 28, "+", 48, 52, 62, 240, 240, 240, false) then
    state.formant = math.min(1.20, math.floor((state.formant + 0.02) * 100 + 0.5) / 100)
  end
  y = y + 40

  -- 5. Destinazione REAPER (Fixed Lane 2 vs Nuova Take)
  gfx.setfont(1, "Helvetica", 12, string.byte("b"))
  set_color(180, 188, 200)
  gfx.x, gfx.y = 14, y + 5
  gfx.drawstr("DESTINAZIONE IN REAPER:")
  local dest_label = state.target_dest == "lane"
    and "Fixed Item Lane 2 (REAPER 7)"
    or "Nuova Take sull'Item (T)"
  if draw_button(195, y, gfx.w - 209, 28, dest_label, 44, 50, 60, 245, 210, 120, false) then
    state.target_dest = (state.target_dest == "lane") and "take" or "lane"
  end
  y = y + 42

  -- 6. Pulsanti PREASCOLTO 4s e APPLICA SULL'ITEM
  if draw_button(14, y, 175, 40, "PREASCOLTO 4s", 45, 55, 68, 250, 205, 95, false) then
    run_preview_4s()
  end
  if draw_button(198, y, gfx.w - 212, 40, "APPLICA SULL'ITEM SELEZIONATO", 215, 145, 25, 20, 22, 25, true) then
    run_apply_selected_items()
  end
  y = y + 50

  -- Barra di stato in basso
  draw_box(14, y, gfx.w - 28, 30, 20, 22, 26, true)
  gfx.setfont(1, "Helvetica", 12, 0)
  set_color(130, 230, 165)
  gfx.x, gfx.y = 22, y + 8
  gfx.drawstr(state.status_msg)

  state.prev_mouse_cap = gfx.mouse_cap
  gfx.update()
  reaper.defer(loop)
end

gfx.init("ZP Clean & Paint — REAPER 7", 472, 345, 0, 220, 180)
loop()
