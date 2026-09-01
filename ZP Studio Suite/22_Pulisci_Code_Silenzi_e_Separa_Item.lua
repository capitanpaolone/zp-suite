--[[
ZP Studio Suite - Split Silenzi / Voice Cleaner
Versione: v1.0.5

Analizza gli item audio selezionati, rileva porzioni parlate con un gate RMS
smart e permette preview/applicazione non distruttiva fino al comando APPLICA.
]]

local SCRIPT_NAME = "ZP Studio Suite - Split Silenzi / Voice Cleaner"
local PREVIEW_PREFIX = "ZPSS22_PREVIEW"
local SCRIPT_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "")

local function msg(text) reaper.MB(tostring(text or ""), SCRIPT_NAME, 0) end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function db_to_amp(db) return 10 ^ ((db or -60) / 20) end
local function amp_to_db(amp) if not amp or amp <= 0 then return -120 end return 20 * math.log(amp, 10) end
local function fmt_ms(sec) return string.format("%d ms", math.floor((sec or 0) * 1000 + 0.5)) end
local function fmt_ms_off(sec) if not sec or sec <= 0.0001 then return "OFF" end return fmt_ms(sec) end
local function fmt_db(db) return string.format("%.1f dB", db or -120) end
local function fmt_sec(sec) return string.format("%.2f s", sec or 0) end
local function ok_value(v) return v == true or v == 1 end
local AUDIO_MIN_PEAK = 0.000001

local COLORS = {
  bg = {0.055, 0.055, 0.070, 1},
  panel = {0.085, 0.085, 0.115, 1},
  panel2 = {0.105, 0.105, 0.145, 1},
  line = {0.34, 0.33, 0.43, 1},
  text = {0.91, 0.90, 0.86, 1},
  muted = {0.60, 0.60, 0.66, 1},
  title = {0.98, 0.82, 0.42, 1},
  blue = {0.12, 0.32, 0.62, 1},
  cyan = {0.12, 0.62, 0.76, 1},
  green = {0.12, 0.48, 0.28, 1},
  red = {0.52, 0.13, 0.12, 1},
  orange = {0.54, 0.34, 0.10, 1},
  knob_bg = {0.055, 0.060, 0.078, 1}
}

local function setc(c, a) gfx.set(c[1], c[2], c[3], a or c[4] or 1) end
local function in_rect(x, y, w, h) return gfx.mouse_x >= x and gfx.mouse_x <= x + w and gfx.mouse_y >= y and gfx.mouse_y <= y + h end
local function mouse_clicked() return (gfx.mouse_cap & 1) == 0 and state.mouse_was_down end

local PRESETS = {
  {
    name = "VO Smart", threshold_mode = "auto", threshold_db = -50,
    min_silence = 0.350, gate_open = 0.060, gate_hold = 0.160,
    ignore_click = 0, min_segment = 0, merge_gap = 0,
    pre_pad = 0.080, post_pad = 0.160, fade = 0.005
  },
  {
    name = "Gentle", threshold_mode = "auto", threshold_db = -52,
    min_silence = 0.500, gate_open = 0.050, gate_hold = 0.220,
    ignore_click = 0, min_segment = 0, merge_gap = 0,
    pre_pad = 0.120, post_pad = 0.220, fade = 0.005
  },
  {
    name = "Tight", threshold_mode = "auto", threshold_db = -48,
    min_silence = 0.250, gate_open = 0.070, gate_hold = 0.100,
    ignore_click = 0, min_segment = 0, merge_gap = 0,
    pre_pad = 0.050, post_pad = 0.100, fade = 0.005
  },
  {
    name = "Manual", threshold_mode = "manual", threshold_db = -45,
    min_silence = 0.350, gate_open = 0.060, gate_hold = 0.160,
    ignore_click = 0, min_segment = 0, merge_gap = 0,
    pre_pad = 0.080, post_pad = 0.160, fade = 0.005
  }
}

state = {
  mode = 2, -- 1 trim, 2 split, 3 extract
  preset = 1,
  settings = {},
  keep_positions = true,
  rename_parts = true,
  apply_fade = true,
  debug = false,
  gap = 0.50,
  advanced = false,
  analysis = nil,
  last_operation = nil,
  status = "Seleziona item audio e premi ANALIZZA.",
  help_title = "",
  help_text = "",
  scroll_y = 0,
  content_h = 0,
  knob_hover = false,
  drag_key = nil,
  drag_y = 0,
  drag_start = 0,
  last_click_key = nil,
  last_click_time = 0,
  last_mouse_wheel = 0,
  mouse_was_down = false,
  win_w = 1040,
  win_h = 1000
}

local CONTROL_HELP = {
  mode_trim = {"Trim testa/coda", "Rifila solo inizio e fine dell'item, mantenendo tutto tra primo e ultimo parlato."},
  mode_split = {"Split silenzi interni", "Divide il file in piu item quando trova pause abbastanza lunghe."},
  pos_original = {"Posizione originale", "Gli item restano nella loro posizione temporale originale, ma vengono rifilati o splittati."},
  pos_sequence = {"Separa in sequenza", "Opzione Advanced: dopo Applica, mette i take creati uno dopo l'altro usando la distanza impostata."},
  rename = {"Rinomina", "Rinomina gli item creati con suffisso progressivo part-001, part-002, ecc."},
  fade_toggle = {"Fade", "Applica una breve dissolvenza all'inizio e alla fine degli item creati."},
  preset_vo = {"VO Smart", "Preset consigliato per voiceover normale. Buon equilibrio tra pulizia e naturalezza."},
  preset_gentle = {"Gentle", "Piu conservativo. Lascia piu respiro e riduce il rischio di tagli troppo stretti."},
  preset_tight = {"Tight", "Piu aggressivo. Utile quando vuoi tagli rapidi e pause piu corte."},
  preset_manual = {"Manual", "Parte da valori manuali e lascia pieno controllo alla soglia."},
  threshold_auto = {"Auto", "Stima automaticamente la soglia partendo dal rumore di fondo rilevato nell'item."},
  threshold_manual = {"Manuale", "Usa il valore del knob Soglia invece della stima automatica."},
  threshold = {"Soglia", "Livello oltre il quale il segnale viene considerato parlato. Piu bassa rileva piu audio; piu alta rileva meno audio."},
  min_silence = {"Min silence", "Durata minima di una pausa per considerarla un vero silenzio da tagliare."},
  gate_open = {"Gate open", "Tempo minimo sopra soglia necessario per aprire il gate. Evita che click brevi diventino segmenti."},
  gate_hold = {"Gate hold", "Mantiene aperto il gate durante piccoli buchi o pause interne alla frase."},
  pre_roll = {"Pre-roll", "Spazio lasciato prima dell'inizio rilevato della frase."},
  post_roll = {"Post-roll", "Spazio lasciato dopo la fine rilevata della frase."},
  fade_len = {"Fade", "Dissolvenza applicata ai bordi degli item creati per evitare click."},
  ignore_click = {"Ignore click", "Opzione Advanced. OFF non scarta eventi brevi; aumentando il valore ignora click, bump o respiri isolati."},
  min_segment = {"Min segment", "Opzione Advanced. OFF non filtra per durata minima; aumentando il valore scarta segmenti troppo brevi."},
  merge_gap = {"Merge gap", "Opzione Advanced. OFF non fonde segmenti vicini; aumentando il valore unisce pause piu corte del valore scelto."},
  gap = {"Distanza tra file", "Opzione Advanced. Spazio tra i take creati con Separa in sequenza; non agisce con Posizione originale o Advanced chiuso."},
  analyze = {"Analizza", "Legge l'audio e calcola i segmenti senza modificare il progetto."},
  preview = {"Preview", "Crea regioni rosse temporanee nella timeline originale. Disponibile solo con Posizione originale."},
  apply = {"Applica", "Esegue davvero trim/split. L'operazione e annullabile con un solo Undo."},
  clean_preview = {"Pulisci preview", "Rimuove le regioni temporanee create dalla preview."},
  help = {"Help", "Apre la guida del Voice Cleaner."},
  cancel = {"Cancella", "Chiude la finestra e rimuove eventuali regioni preview temporanee."},
  debug = {"Debug", "Mostra in console i dati tecnici della lettura audio. Da lasciare spento nell'uso normale."},
  advanced = {"Advanced", "Mostra o nasconde opzioni fini. Quando e chiuso, queste opzioni non modificano analisi o output."}
}

local function copy_preset(idx)
  local p = PRESETS[idx or state.preset]
  for k, v in pairs(p) do
    if k ~= "name" then state.settings[k] = v end
  end
end
copy_preset(1)

local function effective_settings()
  local s = {}
  for k, v in pairs(state.settings) do s[k] = v end
  if not state.advanced then
    s.ignore_click = 0
    s.min_segment = 0
    s.merge_gap = 0
  end
  return s
end

local function effective_keep_positions()
  if not state.advanced then return true end
  return state.keep_positions
end

local function effective_gap()
  if not state.advanced then return 0 end
  if state.keep_positions then return 0 end
  return state.gap or 0
end

local function is_valid_audio_item(item)
  if not item or not reaper.ValidatePtr(item, "MediaItem*") then return false end
  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then return false end
  return reaper.GetMediaItemTake_Source(take) ~= nil
end

local function selected_audio_items()
  local items = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    if is_valid_audio_item(item) then items[#items + 1] = item end
  end
  table.sort(items, function(a, b)
    local ta, tb = reaper.GetMediaItem_Track(a), reaper.GetMediaItem_Track(b)
    if ta == tb then return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION") end
    return reaper.GetMediaTrackInfo_Value(ta, "IP_TRACKNUMBER") < reaper.GetMediaTrackInfo_Value(tb, "IP_TRACKNUMBER")
  end)
  return items
end

local function item_name(item)
  local take = reaper.GetActiveTake(item)
  local _, take_name = take and reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  take_name = tostring(take_name or ""):gsub("%s+$", "")
  if take_name ~= "" then return take_name end
  local _, name = reaper.GetSetMediaItemInfo_String(item, "P_NAME", "", false)
  name = tostring(name or ""):gsub("%s+$", "")
  return name ~= "" and name or "voice"
end

local function percentile(values, pct)
  if #values == 0 then return nil end
  table.sort(values)
  local idx = math.floor((#values - 1) * pct + 1.5)
  return values[clamp(idx, 1, #values)]
end

local function source_file_name(src)
  if not src or not reaper.GetMediaSourceFileName then return "" end
  local ok, name = pcall(reaper.GetMediaSourceFileName, src, "")
  if ok and name then return tostring(name) end
  return ""
end

local function open_help()
  local path = SCRIPT_DIR .. "help/voice_cleaner.html"
  if reaper.file_exists and not reaper.file_exists(path) then
    msg("Help non trovato:\n" .. path)
    return
  end
  if reaper.CF_ShellExecute then
    reaper.CF_ShellExecute(path)
    return
  end
  local os_name = reaper.GetOS and reaper.GetOS() or ""
  if reaper.ExecProcess and os_name:match("OSX") then
    reaper.ExecProcess('open "' .. path:gsub('"', '\\"') .. '"', 0)
  else
    msg("Apri manualmente l'help:\n" .. path)
  end
end

local function fallback_windows_from_peaks(item, window_sec, hop_sec, diag)
  if not reaper.GetMediaItemTake_Peaks then
    diag.fallback = "GetMediaItemTake_Peaks non disponibile"
    return {}
  end

  local take = reaper.GetActiveTake(item)
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local peakrate = math.max(20, math.floor(1 / math.max(0.005, hop_sec) + 0.5))
  local samples = math.max(1, math.ceil(item_len * peakrate))
  local channels = math.max(1, diag.channels or 1)
  local buf = reaper.new_array(samples * channels * 2)
  local ok, rv = pcall(reaper.GetMediaItemTake_Peaks, take, peakrate, 0, channels, samples, 0, buf)
  diag.fallback_calls = 1
  diag.fallback_return = tostring(rv)
  if not ok or not rv or rv == 0 then
    diag.fallback = "GetMediaItemTake_Peaks fallito"
    return {}
  end

  local data = buf.table(1, samples * channels * 2)
  local windows = {}
  for i = 0, samples - 1 do
    local peak = 0
    for ch = 1, channels do
      local base = (i * channels * 2) + ((ch - 1) * 2)
      peak = math.max(peak, math.abs(data[base + 1] or 0), math.abs(data[base + 2] or 0))
    end
    local rms = peak * 0.707
    windows[#windows + 1] = {t = item_start + (i / peakrate), rel = i / peakrate, rms = rms, peak = peak}
    diag.max_peak = math.max(diag.max_peak or 0, peak)
    diag.max_rms = math.max(diag.max_rms or 0, rms)
  end
  diag.fallback = "GetMediaItemTake_Peaks OK"
  diag.fallback_ok_calls = 1
  diag.windows = #windows
  diag.calls = diag.calls or 0
  diag.ok_calls = diag.ok_calls or 0
  return windows
end

local function project_sample_rate()
  local sr = 0
  if reaper.GetSetProjectInfo then
    sr = tonumber(reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)) or 0
  end
  if sr <= 0 then sr = 48000 end
  return sr
end

local function get_windows(item, window_sec, hop_sec)
  local take = reaper.GetActiveTake(item)
  local src = take and reaper.GetMediaItemTake_Source(take) or nil
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = item_start + item_len
  local diag = {
    item_name = item_name(item),
    item_start = item_start,
    item_len = item_len,
    item_end = item_end,
    take_valid = take ~= nil,
    source_valid = src ~= nil,
    source_file = source_file_name(src),
    channels = 0,
    accessor_created = false,
    accessor_start = nil,
    accessor_end = nil,
    scan_start = nil,
    scan_end = nil,
    accessor_time_mode = nil,
    read_start = nil,
    read_end = nil,
    project_start = item_start,
    project_end = item_end,
    sample_rate = project_sample_rate(),
    frames = 0,
    calls = 0,
    ok_calls = 0,
    empty_calls = 0,
    max_rms = 0,
    max_peak = 0,
    windows = 0,
    return_values = {}
  }

  if item_len <= 0 then diag.error = "Item length <= 0"; return {}, diag end
  if not take then diag.error = "Take non valido"; return {}, diag end
  if not src then diag.error = "Source non valido"; return {}, diag end

  local channels = math.min(math.max(reaper.GetMediaSourceNumChannels(src) or 1, 1), 2)
  diag.channels = channels
  local accessor = reaper.CreateTakeAudioAccessor(take)
  diag.accessor_created = accessor ~= nil
  if not accessor then
    diag.error = "CreateTakeAudioAccessor fallito"
    local fallback = fallback_windows_from_peaks(item, window_sec, hop_sec, diag)
    return fallback, diag
  end

  diag.accessor_start = reaper.GetAudioAccessorStartTime and reaper.GetAudioAccessorStartTime(accessor) or item_start
  diag.accessor_end = reaper.GetAudioAccessorEndTime and reaper.GetAudioAccessorEndTime(accessor) or item_end
  local accessor_start = diag.accessor_start or 0
  local accessor_end = diag.accessor_end or item_len
  local accessor_len = accessor_end - accessor_start
  local read_base = accessor_start
  local project_base = item_start

  if accessor_start <= 0.001 and math.abs(accessor_len - item_len) < 0.1 then
    diag.accessor_time_mode = "take_relative"
    read_base = accessor_start
  elseif math.abs(accessor_start - item_start) < 0.1 or (accessor_start <= item_start + 0.1 and accessor_end >= item_end - 0.1) then
    diag.accessor_time_mode = "project_absolute"
    read_base = item_start
  elseif math.abs(accessor_len - item_len) < 0.1 then
    diag.accessor_time_mode = "take_relative_len_match"
    read_base = accessor_start
  else
    diag.accessor_time_mode = "unknown"
    read_base = accessor_start
  end

  local read_len = item_len
  if diag.accessor_time_mode == "take_relative" or diag.accessor_time_mode == "take_relative_len_match" then
    read_len = math.min(item_len, math.max(0, accessor_end - read_base))
  elseif diag.accessor_time_mode == "project_absolute" then
    read_len = math.min(item_len, math.max(0, accessor_end - read_base))
  else
    read_len = math.min(item_len, math.max(0, accessor_end - read_base))
  end

  diag.scan_start = project_base
  diag.scan_end = project_base + read_len
  diag.read_start = read_base
  diag.read_end = read_base + read_len
  diag.project_start = project_base
  diag.project_end = project_base + read_len

  if read_len <= 0 then
    diag.error = string.format("Accessor senza range leggibile: mode %s, read %.3f-%.3f, item %.3f-%.3f, accessor %.3f-%.3f", tostring(diag.accessor_time_mode), diag.read_start or -1, diag.read_end or -1, item_start, item_end, accessor_start, accessor_end)
    reaper.DestroyAudioAccessor(accessor)
    local fallback = fallback_windows_from_peaks(item, window_sec, hop_sec, diag)
    return fallback, diag
  end

  local sr = diag.sample_rate
  local frames = math.max(2, math.floor(window_sec * sr + 0.5))
  local hop_frames = math.max(1, math.floor(hop_sec * sr + 0.5))
  local hop_actual = hop_frames / sr
  local buf = reaper.new_array(frames * channels)
  local windows = {}
  local rel = 0
  diag.frames = frames

  while rel < read_len do
    local request_frames = frames
    if rel + window_sec > read_len then request_frames = math.max(1, math.floor((read_len - rel) * sr + 0.5)) end
    buf.clear()
    diag.calls = diag.calls + 1
    local read_time = read_base + rel
    local project_time = project_base + rel
    local ok = reaper.GetAudioAccessorSamples(accessor, sr, channels, read_time, request_frames, buf)
    if #diag.return_values < 8 then diag.return_values[#diag.return_values + 1] = tostring(ok) end
    if ok_value(ok) then
      diag.ok_calls = diag.ok_calls + 1
      local samples = buf.table(1, request_frames * channels)
      local sums = {}
      for ch = 1, channels do sums[ch] = 0 end
      local peak = 0
      local nonzero = false
      for i = 0, request_frames - 1 do
        local base = i * channels
        for ch = 1, channels do
          local v = samples[base + ch] or 0
          local av = math.abs(v)
          if av > peak then peak = av end
          sums[ch] = sums[ch] + v * v
          if av > 0 then nonzero = true end
        end
      end
      local rms = 0
      for ch = 1, channels do rms = math.max(rms, math.sqrt(sums[ch] / request_frames)) end
      diag.max_peak = math.max(diag.max_peak, peak)
      diag.max_rms = math.max(diag.max_rms, rms)
      if not nonzero then diag.empty_calls = diag.empty_calls + 1 end
      windows[#windows + 1] = {t = project_time, rel = rel, rms = rms, peak = peak}
    end
    rel = rel + hop_actual
  end

  reaper.DestroyAudioAccessor(accessor)
  diag.windows = #windows
  if #windows == 0 then
    diag.error = string.format("samples ok: %d/%d, returns: %s", diag.ok_calls, diag.calls, table.concat(diag.return_values, ", "))
    local fallback = fallback_windows_from_peaks(item, window_sec, hop_sec, diag)
    return fallback, diag
  elseif diag.max_peak <= AUDIO_MIN_PEAK then
    diag.warning = "Campioni letti ma tutti a zero: item muto, source offline o range errato"
    local fallback = fallback_windows_from_peaks(item, window_sec, hop_sec, diag)
    if #fallback > 0 and (diag.max_peak or 0) > AUDIO_MIN_PEAK then return fallback, diag end
  end
  return windows, diag
end

local function estimate_noise(windows)
  local rms_values, peak_values = {}, {}
  for _, w in ipairs(windows) do
    rms_values[#rms_values + 1] = w.rms
    peak_values[#peak_values + 1] = w.peak
  end
  local p10 = percentile(rms_values, 0.10) or 0
  local p20 = percentile(rms_values, 0.20) or p10
  local peak_low = percentile(peak_values, 0.20) or 0
  return math.max(p10, p20 * 0.75, peak_low * 0.35)
end

local function normalize_segments(raw, item_start, item_end, settings)
  if #raw == 0 then return {} end
  table.sort(raw, function(a, b) return a.start < b.start end)
  local min_segment = settings.min_segment or 0
  local merge_gap = settings.merge_gap or 0

  local filtered = {}
  for _, seg in ipairs(raw) do
    if min_segment <= 0 or seg.stop - seg.start >= min_segment then filtered[#filtered + 1] = seg end
  end

  local merged = {}
  for _, seg in ipairs(filtered) do
    local last = merged[#merged]
    if last and merge_gap > 0 and seg.start - last.stop <= merge_gap then
      last.stop = math.max(last.stop, seg.stop)
    else
      merged[#merged + 1] = {start = seg.start, stop = seg.stop}
    end
  end

  local padded = {}
  for _, seg in ipairs(merged) do
    local s = clamp(seg.start - settings.pre_pad, item_start, item_end)
    local e = clamp(seg.stop + settings.post_pad, item_start, item_end)
    if e > s and (min_segment <= 0 or e - s >= min_segment) then padded[#padded + 1] = {start = s, stop = e} end
  end
  return padded
end

local function detect_segments(item, settings)
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = item_start + item_len
  if item_len < 0.05 then return {}, {warning = "Item troppo corto", audio_ok = false, audio_diag = {windows = 0, max_peak = 0, max_rms = 0, error = "Item troppo corto"}} end

  local windows, audio_diag = get_windows(item, 0.015, 0.0075)
  local audio_ok = #windows > 0 and ((audio_diag.ok_calls or 0) > 0 or (audio_diag.fallback_ok_calls or 0) > 0) and (audio_diag.max_peak or 0) > AUDIO_MIN_PEAK
  if not audio_ok then
    local warning = audio_diag and (audio_diag.error or audio_diag.warning) or "Audio non leggibile"
    if #windows > 0 and (audio_diag.max_peak or 0) <= AUDIO_MIN_PEAK then
      warning = "Audio read FAIL/ZERO: campioni tutti a zero"
    end
    return {}, {
      warning = warning,
      audio_ok = false,
      audio_diag = audio_diag
    }
  end

  local noise_amp = estimate_noise(windows)
  local noise_db = amp_to_db(noise_amp)
  local threshold_db = settings.threshold_db
  if settings.threshold_mode == "auto" then threshold_db = clamp(noise_db + 12, -65, -34) end
  local open_amp = db_to_amp(threshold_db)
  local close_amp = db_to_amp(threshold_db - 6)
  local peak_open_amp = db_to_amp(threshold_db + 5)

  local raw = {}
  local gate_open = false
  local candidate_start = nil
  local candidate_time = 0
  local below_time = 0
  local last_voice = nil
  local prev_t = nil
  local seg_start = nil
  local ignore_click = settings.ignore_click or 0

  for _, win in ipairs(windows) do
    local dt = prev_t and math.max(0.001, win.t - prev_t) or settings.hop_sec or 0.0075
    prev_t = win.t
    local loud = win.rms >= open_amp or win.peak >= peak_open_amp
    local quiet = win.rms < close_amp and win.peak < peak_open_amp

    if gate_open then
      if quiet then
        below_time = below_time + dt
        if below_time >= math.max(settings.min_silence, settings.gate_hold) then
          local stop_t = last_voice or win.t
          if ignore_click <= 0 or stop_t - seg_start >= ignore_click then raw[#raw + 1] = {start = seg_start, stop = stop_t} end
          gate_open, candidate_start, candidate_time, below_time, last_voice, seg_start = false, nil, 0, 0, nil, nil
        end
      else
        below_time = 0
        last_voice = win.t + 0.015
      end
    elseif loud then
      if not candidate_start then candidate_start = win.t; candidate_time = 0 end
      candidate_time = candidate_time + dt
      if candidate_time >= settings.gate_open then
        gate_open = true
        seg_start = candidate_start
        last_voice = win.t + 0.015
        below_time = 0
      end
    elseif candidate_start then
      if (ignore_click > 0 and win.t - candidate_start <= ignore_click) or candidate_time < settings.gate_open then
        candidate_start, candidate_time = nil, 0
      end
    end
  end

  if gate_open and seg_start and last_voice and (ignore_click <= 0 or last_voice - seg_start >= ignore_click) then
    raw[#raw + 1] = {start = seg_start, stop = last_voice}
  end

  local segments = normalize_segments(raw, item_start, item_end, settings)
  local speech = 0
  for _, seg in ipairs(segments) do speech = speech + (seg.stop - seg.start) end
  return segments, {
    threshold_db = threshold_db,
    noise_db = noise_db,
    audio_ok = audio_ok,
    audio_diag = audio_diag,
    raw_count = #raw,
    speech = speech,
    item_len = item_len,
    warning = (#segments == 0 and "Nessun parlato rilevato") or nil
  }
end

local function trim_item_to_time(item, new_start, new_end)
  if not item or not reaper.ValidatePtr(item, "MediaItem*") or new_end <= new_start then return false end
  local take = reaper.GetActiveTake(item)
  local old_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local old_end = old_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local playrate = take and reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
  if not playrate or playrate == 0 then playrate = 1 end
  new_start = clamp(new_start, old_start, old_end)
  new_end = clamp(new_end, old_start, old_end)
  if new_end <= new_start then return false end
  local delta = new_start - old_start
  if take and delta ~= 0 then
    local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
    reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", offs + delta * playrate)
  end
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_start)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", new_end - new_start)
  return true
end

local function duplicate_item(item)
  local track = reaper.GetMediaItem_Track(item)
  local _, chunk = reaper.GetItemStateChunk(item, "", false)
  if not chunk or chunk == "" then return nil end
  local new_item = reaper.AddMediaItemToTrack(track)
  if not new_item then return nil end
  reaper.SetItemStateChunk(new_item, chunk, false)
  return new_item
end

local function apply_fade(item)
  if not state.apply_fade then return end
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local fade = math.min(state.settings.fade or 0, len * 0.25)
  reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", fade)
  reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", fade)
end

local function rename_part(item, base, idx)
  if not state.rename_parts then return end
  local name = string.format("%s_part-%03d", base:gsub("%s+$", ""), idx)
  reaper.GetSetMediaItemInfo_String(item, "P_NAME", name, true)
  local take = reaper.GetActiveTake(item)
  if take then reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true) end
end

local function select_only(items)
  reaper.Main_OnCommand(40289, 0)
  for _, item in ipairs(items) do
    if item and reaper.ValidatePtr(item, "MediaItem*") then reaper.SetMediaItemSelected(item, true) end
  end
end

local function analyze()
  local items = selected_audio_items()
  if #items == 0 then state.status = "Nessun item audio selezionato."; state.analysis = nil; return end
  local settings = effective_settings()
  local results = {items = {}, total_len = 0, total_speech = 0, thresholds = {}, noise_floors = {}, warnings = {}, segment_count = 0, silence_count = 0, audio_ok = false, audio_failures = 0, audio_windows = 0, max_peak = 0, max_rms = 0, audio_line = "", audio_mode = "?", threshold_avg = nil, noise_avg = nil}
  for _, item in ipairs(items) do
    local segments, info = detect_segments(item, settings)
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    results.total_len = results.total_len + item_len
    results.total_speech = results.total_speech + (info.speech or 0)
    if info.threshold_db then results.thresholds[#results.thresholds + 1] = info.threshold_db end
    if info.noise_db then results.noise_floors[#results.noise_floors + 1] = info.noise_db end
    if info.warning then results.warnings[#results.warnings + 1] = item_name(item) .. ": " .. info.warning end
    local diag = info.audio_diag or {}
    if info.audio_ok then results.audio_ok = true else results.audio_failures = results.audio_failures + 1 end
    results.audio_windows = results.audio_windows + (diag.windows or 0)
    results.max_peak = math.max(results.max_peak, diag.max_peak or 0)
    results.max_rms = math.max(results.max_rms, diag.max_rms or 0)
    results.segment_count = results.segment_count + #segments
    results.silence_count = results.silence_count + math.max(0, #segments - 1)
    results.items[#results.items + 1] = {item = item, name = item_name(item), pos = item_pos, len = item_len, segments = segments, info = info}
  end
  results.audio_ok = results.audio_failures == 0 and results.audio_windows > 0 and results.max_peak > AUDIO_MIN_PEAK
  local first_diag = results.items[1] and results.items[1].info and results.items[1].info.audio_diag or {}
  local mode_label = first_diag.accessor_time_mode or "?"
  results.audio_mode = mode_label
  local avg = 0
  for _, v in ipairs(results.thresholds) do avg = avg + v end
  if #results.thresholds > 0 then results.threshold_avg = avg / #results.thresholds end
  avg = 0
  for _, v in ipairs(results.noise_floors) do avg = avg + v end
  if #results.noise_floors > 0 then results.noise_avg = avg / #results.noise_floors end
  if results.audio_ok then
    results.audio_line = string.format("Audio OK - %s - peak %s", mode_label, fmt_db(amp_to_db(results.max_peak)))
  elseif results.audio_windows > 0 and results.max_peak <= AUDIO_MIN_PEAK then
    results.audio_line = string.format("Audio FAIL/ZERO - %s - peak %s", mode_label, fmt_db(amp_to_db(results.max_peak)))
  else
    local diag = first_diag
    results.audio_line = string.format(
      "Audio read: FAIL (%s), accessor %s-%s, item %.3f-%.3f, samples ok: %d/%d",
      mode_label,
      diag.accessor_start and string.format("%.3f", diag.accessor_start) or "?",
      diag.accessor_end and string.format("%.3f", diag.accessor_end) or "?",
      diag.item_start or 0,
      diag.item_end or 0,
      diag.ok_calls or 0,
      diag.calls or 0
    )
  end
  if state.debug then
    reaper.ShowConsoleMsg("\n[ZPSS22 Voice Cleaner]\n")
    for _, res in ipairs(results.items) do
      local d = res.info.audio_diag or {}
      reaper.ShowConsoleMsg(string.format(
        "%s\n  item %.3f-%.3f len %.3f\n  take=%s source=%s file=%s channels=%s\n  accessor=%s %.3f-%.3f mode=%s\n  read %.3f-%.3f project %.3f-%.3f\n  sr=%s frames=%s calls ok/total=%s/%s empty=%s windows=%s\n  max peak=%s max RMS=%s fallback=%s error=%s\n",
        res.name,
        d.item_start or res.pos or 0,
        d.item_end or ((res.pos or 0) + (res.len or 0)),
        d.item_len or res.len or 0,
        d.take_valid and "si" or "no",
        d.source_valid and "si" or "no",
        d.source_file or "",
        tostring(d.channels or "?"),
        d.accessor_created and "si" or "no",
        d.accessor_start or -1,
        d.accessor_end or -1,
        tostring(d.accessor_time_mode or "?"),
        d.read_start or -1,
        d.read_end or -1,
        d.project_start or -1,
        d.project_end or -1,
        tostring(d.sample_rate or "?"),
        tostring(d.frames or "?"),
        tostring(d.ok_calls or 0),
        tostring(d.calls or 0),
        tostring(d.empty_calls or 0),
        tostring(d.windows or 0),
        fmt_db(amp_to_db(d.max_peak or 0)),
        fmt_db(amp_to_db(d.max_rms or 0)),
        tostring(d.fallback or ""),
        tostring(d.error or d.warning or "")
      ))
      reaper.ShowConsoleMsg(string.format(
        "AUDIOACCESSOR TEST:\n  mode = %s\n  read_time first = %.3f\n  read_time last = %.3f\n  project_time first = %.3f\n  project_time last = %.3f\n  calls = %s\n  ok_calls = %s\n  windows = %s\n  max_peak_db = %s\n  max_rms_db = %s\n",
        tostring(d.accessor_time_mode or "?"),
        d.read_start or -1,
        d.read_end or -1,
        d.project_start or -1,
        d.project_end or -1,
        tostring(d.calls or 0),
        tostring(d.ok_calls or 0),
        tostring(d.windows or 0),
        fmt_db(amp_to_db(d.max_peak or 0)),
        fmt_db(amp_to_db(d.max_rms or 0))
      ))
    end
  end
  state.analysis = results
  state.last_operation = nil
  state.status = string.format("Analisi completata: %d segmenti su %d item.", results.segment_count, #results.items)
end

local function cleanup_preview()
  local _, markers, regions = reaper.CountProjectMarkers(0)
  for i = markers + regions - 1, 0, -1 do
    local ok, isrgn, pos, rgnend, name, idx = reaper.EnumProjectMarkers(i)
    if ok and tostring(name or ""):find(PREVIEW_PREFIX, 1, true) == 1 then reaper.DeleteProjectMarker(0, idx, isrgn) end
  end
end

local function count_preview_regions()
  local count = 0
  local _, markers, regions = reaper.CountProjectMarkers(0)
  for i = markers + regions - 1, 0, -1 do
    local ok, _, _, _, name = reaper.EnumProjectMarkers(i)
    if ok and tostring(name or ""):find(PREVIEW_PREFIX, 1, true) == 1 then count = count + 1 end
  end
  return count
end

local function preview()
  if not state.analysis then analyze() end
  if not state.analysis or not state.analysis.audio_ok or state.analysis.segment_count == 0 then state.status = "Preview non disponibile: audio non letto o nessun segmento valido."; return end
  if not effective_keep_positions() then state.status = "Preview disponibile solo con Posizione originale."; return end
  reaper.Undo_BeginBlock()
  cleanup_preview()
  local preview_color = reaper.ColorToNative(255, 0, 0) + 0x1000000
  local n = 0
  for _, res in ipairs(state.analysis.items) do
    for i, seg in ipairs(res.segments) do
      n = n + 1
      reaper.AddProjectMarker2(0, true, seg.start, seg.stop, string.format("%s %03d %s", PREVIEW_PREFIX, i, res.name), -1, preview_color)
    end
  end
  reaper.Undo_EndBlock("ZP Studio Suite preview split silenzi", -1)
  reaper.UpdateArrange()
  state.status = "Preview creata con regioni temporanee ZPSS22_PREVIEW."
end

local function apply()
  if not state.analysis then analyze() end
  if not state.analysis or not state.analysis.audio_ok or state.analysis.segment_count == 0 then state.status = "APPLICA bloccato: audio non letto o nessun segmento valido."; return end
  local analysis = state.analysis
  local keep_positions = effective_keep_positions()
  local gap = effective_gap()

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  cleanup_preview()

  local created_items = {}
  for _, res in ipairs(analysis.items) do
    if res.item and reaper.ValidatePtr(res.item, "MediaItem*") then
      if state.mode == 1 then
        local first, last = res.segments[1], res.segments[#res.segments]
        if first and last and trim_item_to_time(res.item, first.start, last.stop) then
          apply_fade(res.item)
          created_items[#created_items + 1] = res.item
        end
      else
        local per_item = {}
        for i, seg in ipairs(res.segments) do
          local new_item = duplicate_item(res.item)
          if new_item and trim_item_to_time(new_item, seg.start, seg.stop) then
            apply_fade(new_item)
            rename_part(new_item, res.name, i)
            per_item[#per_item + 1] = new_item
            created_items[#created_items + 1] = new_item
          elseif new_item then
            reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(new_item), new_item)
          end
        end
        if #per_item > 0 then reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(res.item), res.item) end
      end
    end
  end

  if not keep_positions then
    table.sort(created_items, function(a, b)
      local ta, tb = reaper.GetMediaItem_Track(a), reaper.GetMediaItem_Track(b)
      if ta == tb then return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION") end
      return reaper.GetMediaTrackInfo_Value(ta, "IP_TRACKNUMBER") < reaper.GetMediaTrackInfo_Value(tb, "IP_TRACKNUMBER")
    end)
    local cursors = {}
    for _, item in ipairs(created_items) do
      local tr = reaper.GetMediaItem_Track(item)
      local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      if cursors[tr] then reaper.SetMediaItemInfo_Value(item, "D_POSITION", cursors[tr]) end
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      cursors[tr] = pos + len + gap
    end
  end

  select_only(created_items)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("ZP Studio Suite - Split Silenzi / Voice Cleaner", -1)
  state.last_operation = {
    items = #analysis.items,
    created = #created_items,
    speech = analysis.total_speech,
    gap = gap,
    fade = state.settings.fade,
    preset = PRESETS[state.preset].name,
    threshold_avg = analysis.threshold_avg,
    segment_count = analysis.segment_count,
    mode = state.mode
  }
  state.analysis = nil
  state.status = string.format("Applicato: %d item finali creati/selezionati.", #created_items)
end

local function rect(x, y, w, h, color) setc(color); gfx.rect(x, y, w, h, 1); setc(COLORS.line); gfx.rect(x, y, w, h, 0) end
local function label(text, x, y, size, color, bold)
  gfx.setfont(1, "Arial", size or 14, bold and "b" or "")
  setc(color or COLORS.text)
  gfx.x, gfx.y = x, y
  gfx.drawstr(tostring(text or ""))
end

local function set_help(help_key, disabled_reason)
  local h = CONTROL_HELP[help_key or ""]
  if h then
    state.help_title = h[1]
    state.help_text = h[2] .. (disabled_reason and (" " .. disabled_reason) or "")
  elseif disabled_reason then
    state.help_title = "Controllo non disponibile"
    state.help_text = disabled_reason
  end
end

local function centered_label(text, x, y, w, size, color, bold)
  gfx.setfont(1, "Arial", size or 14, bold and "b" or "")
  local tw = gfx.measurestr(tostring(text or ""))
  label(text, x + math.floor((w - tw) * 0.5), y, size, color, bold)
end

local function panel(x, y, w, h, title, subtitle)
  rect(x, y, w, h, COLORS.panel)
  label(title, x + 16, y + 12, 17, COLORS.title, true)
  if subtitle and subtitle ~= "" then label(subtitle, x + 16, y + 36, 14, COLORS.muted) end
end

local function status_pill(x, y, w, h, text, ok)
  local c = ok == nil and COLORS.orange or (ok and COLORS.green or COLORS.red)
  setc(c, 0.95); gfx.rect(x, y, w, h, 1)
  setc(COLORS.line, 0.9); gfx.rect(x, y, w, h, 0)
  centered_label(text, x, y + math.floor((h - 16) * 0.5), w, 16, COLORS.text, true)
end

local function button(x, y, w, h, text, active, style, enabled, disabled_reason, help_key)
  enabled = enabled ~= false
  local over = in_rect(x, y, w, h)
  local hover = enabled and over
  if over then set_help(help_key, enabled and nil or disabled_reason) end
  local c = active and COLORS.blue or (style == "danger" and COLORS.red or style == "go" and COLORS.green or style == "warn" and COLORS.orange or COLORS.panel2)
  if not enabled then
    setc(COLORS.knob_bg, 0.95)
  elseif hover then
    gfx.set(math.min(1, c[1] + 0.10), math.min(1, c[2] + 0.10), math.min(1, c[3] + 0.12), 1)
  else
    setc(c, 1)
  end
  gfx.rect(x, y, w, h, 1)
  setc(COLORS.line, enabled and 1 or 0.28); gfx.rect(x, y, w, h, 0)
  centered_label(text, x, y + math.floor((h - 16) / 2), w, 16, enabled and COLORS.text or COLORS.muted, true)
  return enabled and hover and mouse_clicked()
end

local function get_value(key)
  if key == "gap" then return state.gap end
  return state.settings[key]
end

local function set_value(key, value, minv, maxv, step)
  value = clamp(value, minv, maxv)
  if step and step > 0 then value = math.floor((value / step) + 0.5) * step end
  if key == "gap" then state.gap = value else state.settings[key] = value end
  state.analysis = nil
  state.last_operation = nil
end

local function knob(x, y, r, text, key, minv, maxv, step, default, formatter, color, enabled, disabled_reason, help_key)
  enabled = enabled ~= false
  local cx, cy = x + r, y + r + 20
  local box_w, box_h = r * 2, r * 2 + 56
  local hover = in_rect(x, y, box_w, box_h)
  if hover then state.knob_hover = true; set_help(help_key, enabled and nil or disabled_reason) end

  local value = get_value(key) or default or minv
  local norm = (value - minv) / (maxv - minv)
  norm = clamp(norm, 0, 1)
  local start_ang = math.rad(135)
  local end_ang = math.rad(405)
  local val_ang = start_ang + (end_ang - start_ang) * norm
  local kc = color or COLORS.cyan
  local alpha = enabled and 1 or 0.38

  centered_label(text, x - 10, y, box_w + 20, 14, COLORS.muted)
  setc(COLORS.knob_bg, alpha); gfx.circle(cx, cy, r, 1, 1)
  setc(COLORS.line, hover and alpha or 0.85 * alpha); gfx.circle(cx, cy, r, 0, 1)
  for rr = r - 3, r - 1 do
    setc(COLORS.line, 0.55 * alpha); gfx.arc(cx, cy, rr, start_ang, end_ang, 1)
    setc(kc, (hover and 1 or 0.88) * alpha); gfx.arc(cx, cy, rr, start_ang, val_ang, 1)
  end
  local ix = cx + math.cos(val_ang) * (r - 8)
  local iy = cy + math.sin(val_ang) * (r - 8)
  setc(kc, alpha); gfx.line(cx, cy, ix, iy, 1)
  setc(COLORS.panel2, alpha); gfx.circle(cx, cy, math.max(5, r * 0.18), 1, 1)
  setc(COLORS.line, alpha); gfx.circle(cx, cy, math.max(5, r * 0.18), 0, 1)

  local vtext = formatter and formatter(value) or tostring(value)
  centered_label(vtext, x - 10, y + r * 2 + 30, box_w + 20, 16, enabled and COLORS.text or COLORS.muted, true)

  local left_down = (gfx.mouse_cap & 1) == 1
  local right_down = (gfx.mouse_cap & 2) == 2
  local wheel_delta = (gfx.mouse_wheel or 0) - (state.last_mouse_wheel or 0)
  if not enabled then return end
  if hover and right_down then
    set_value(key, default, minv, maxv, step)
  elseif hover and mouse_clicked() then
    local now = reaper.time_precise and reaper.time_precise() or os.clock()
    if state.last_click_key == key and now - (state.last_click_time or 0) < 0.35 then
      set_value(key, default, minv, maxv, step)
      state.last_click_key = nil
    else
      state.last_click_key = key
      state.last_click_time = now
    end
  elseif hover and wheel_delta ~= 0 then
    local mult = ((gfx.mouse_cap & 8) == 8) and 0.2 or 1
    local dir = wheel_delta > 0 and 1 or -1
    set_value(key, value + dir * step * mult, minv, maxv, step)
  end

  if left_down and hover and not state.drag_key then
    state.drag_key = key
    state.drag_y = gfx.mouse_y
    state.drag_start = value
  elseif not left_down and state.drag_key == key then
    state.drag_key = nil
  end
  if left_down and state.drag_key == key then
    local fine = ((gfx.mouse_cap & 8) == 8) and 0.2 or 1
    local delta = (state.drag_y - gfx.mouse_y) * step * fine
    if math.abs(delta) >= step * 0.25 then set_value(key, state.drag_start + delta, minv, maxv, step) end
  end
end

local function draw_gui()
  local char = gfx.getchar()
  if char == -1 then cleanup_preview(); return end
  state.help_title = ""
  state.help_text = ""
  state.knob_hover = false
  gfx.set(0, 0, 0, 1)
  gfx.rect(0, 0, gfx.w, gfx.h, 1)
  setc(COLORS.bg); gfx.rect(0, 0, gfx.w, gfx.h, 1)

  local x, y = 22, 18
  label("ZP Studio Suite - Split Silenzi / Voice Cleaner", x, y, 25, COLORS.title, true)
  label("Taglia pause, prepara take voiceover e controlla prima di applicare.", x + 2, y + 32, 15, COLORS.muted)
  local audio_ok = state.analysis and state.analysis.audio_ok
  local pill_text = state.analysis and (audio_ok and "Audio OK" or "Audio FAIL") or "In attesa"
  status_pill(gfx.w - 174, y + 2, 140, 30, pill_text, audio_ok)

  local header_h = 64
  local footer_h = 132
  local footer_y = math.max(header_h + 96, gfx.h - footer_h)
  local visible_h = math.max(80, footer_y - header_h - 8)
  local content_y = header_h - state.scroll_y

  local content_top = content_y + 8
  y = content_top
  panel(x, y, 996, 88, "Modalita - cosa deve produrre Applica", "")
  if button(x + 16, y + 46, 240, 30, "Trim testa/coda", state.mode == 1, nil, true, nil, "mode_trim") then state.mode = 1; state.analysis = nil; state.last_operation = nil end
  if button(x + 270, y + 46, 270, 30, "Split silenzi interni", state.mode == 2, nil, true, nil, "mode_split") then state.mode = 2; state.analysis = nil; state.last_operation = nil end
  if button(x + 804, y + 46, 86, 30, state.rename_parts and "Rinomina" or "No nome", state.rename_parts, nil, true, nil, "rename") then state.rename_parts = not state.rename_parts end
  if button(x + 902, y + 46, 78, 30, state.apply_fade and "Fade" or "No fade", state.apply_fade, nil, true, nil, "fade_toggle") then state.apply_fade = not state.apply_fade end

  y = y + 102
  panel(x, y, 996, 76, "Preset - scegli punto di partenza", "")
  for i, p in ipairs(PRESETS) do
    local helps = {"preset_vo", "preset_gentle", "preset_tight", "preset_manual"}
    if button(x + 16 + ((i - 1) * 118), y + 38, 108, 30, p.name, state.preset == i, nil, true, nil, helps[i]) then state.preset = i; copy_preset(i); state.analysis = nil; state.last_operation = nil end
  end
  if button(x + 520, y + 38, 94, 30, "Auto", state.settings.threshold_mode == "auto", nil, true, nil, "threshold_auto") then state.settings.threshold_mode = "auto"; state.analysis = nil; state.last_operation = nil end
  if button(x + 624, y + 38, 104, 30, "Manuale", state.settings.threshold_mode == "manual", nil, true, nil, "threshold_manual") then state.settings.threshold_mode = "manual"; state.analysis = nil; state.last_operation = nil end
  if button(x + 852, y + 38, 136, 30, state.debug and "Debug ON" or "Debug OFF", state.debug, state.debug and "warn" or nil, true, nil, "debug") then state.debug = not state.debug end

  y = y + 90
  panel(x, y, 486, 188, "Detection", "Soglia e tempi che decidono quando una frase e' parlato.")
  local p = PRESETS[state.preset]
  knob(x + 28, y + 58, 34, "Soglia", "threshold_db", -80, -20, 1, p.threshold_db, fmt_db, COLORS.orange, true, nil, "threshold")
  knob(x + 132, y + 58, 34, "Min silence", "min_silence", 0.05, 2.0, 0.05, p.min_silence, fmt_ms, COLORS.cyan, true, nil, "min_silence")
  knob(x + 248, y + 58, 34, "Gate open", "gate_open", 0.01, 0.5, 0.01, p.gate_open, fmt_ms, COLORS.green, true, nil, "gate_open")
  knob(x + 360, y + 58, 34, "Gate hold", "gate_hold", 0.0, 1.0, 0.02, p.gate_hold, fmt_ms, COLORS.green, true, nil, "gate_hold")

  panel(x + 510, y, 486, 188, "Margini", "Respiro prima/dopo le frasi e dissolvenza sugli item creati.")
  knob(x + 548, y + 58, 34, "Pre-roll", "pre_pad", 0, 0.6, 0.01, p.pre_pad, fmt_ms, COLORS.cyan, true, nil, "pre_roll")
  knob(x + 690, y + 58, 34, "Post-roll", "post_pad", 0, 0.8, 0.01, p.post_pad, fmt_ms, COLORS.cyan, true, nil, "post_roll")
  knob(x + 832, y + 58, 34, "Fade", "fade", 0, 0.05, 0.001, p.fade, fmt_ms, COLORS.orange, true, nil, "fade_len")

  y = y + 202
  local advanced_summary = "Opzioni split e segmenti."
  panel(x, y, 996, state.advanced and 212 or 72, "Opzioni avanzate / Output", advanced_summary)
  if button(x + 880, y + 18, 100, 30, state.advanced and "Chiudi" or "Apri", state.advanced, nil, true, nil, "advanced") then
    state.advanced = not state.advanced
    state.analysis = nil
    state.last_operation = nil
    state.status = "Opzioni avanzate cambiate: premi ANALIZZA per aggiornare."
  end
  if state.advanced then
    local out_x, out_y = x + 500, y + 26
    label("Rifinitura detector", x + 16, y + 58, 15, COLORS.title, true)
    knob(x + 40, y + 88, 32, "Ignore click", "ignore_click", 0, 0.5, 0.01, p.ignore_click, fmt_ms_off, COLORS.orange, true, nil, "ignore_click")
    knob(x + 178, y + 88, 32, "Min segment", "min_segment", 0, 2.0, 0.05, p.min_segment, fmt_ms_off, COLORS.cyan, true, nil, "min_segment")
    knob(x + 316, y + 88, 32, "Merge gap", "merge_gap", 0, 1.0, 0.02, p.merge_gap, fmt_ms_off, COLORS.green, true, nil, "merge_gap")
    label("Output / distanza tra file", out_x, out_y, 15, COLORS.title, true)
    if button(out_x, out_y + 26, 184, 30, "Posizione originale", state.keep_positions, nil, true, nil, "pos_original") then state.keep_positions = true end
    if button(out_x + 200, out_y + 26, 190, 30, "Separa in sequenza", not state.keep_positions, nil, true, nil, "pos_sequence") then state.keep_positions = false end
    knob(out_x + 164, out_y + 66, 30, "Distanza tra file", "gap", 0, 10, 0.1, 0.5, fmt_sec, COLORS.blue, not state.keep_positions, "La distanza si usa solo quando gli item vengono separati in sequenza.", "gap")
  end

  y = y + (state.advanced and 226 or 86)
  panel(x, y, 996, 132, "Risultati", "Riepilogo dell'analisi o dell'ultima applicazione.")
  local a = state.analysis
  if a then
    local r1, r2, r3 = y + 58, y + 84, y + 110
    label("Item: " .. #a.items, x + 16, r1, 15)
    label("Segmenti: " .. a.segment_count, x + 140, r1, 15)
    label("Silenzi: " .. a.silence_count, x + 300, r1, 15)
    label("Durata: " .. fmt_sec(a.total_len), x + 456, r1, 15)
    label("Parlato: " .. fmt_sec(a.total_speech), x + 632, r1, 15)
    label("Soglia: " .. fmt_db(a.threshold_avg), x + 16, r2, 15)
    label("Noise: " .. fmt_db(a.noise_avg), x + 170, r2, 15)
    label("Peak: " .. fmt_db(amp_to_db(a.max_peak)), x + 328, r2, 15)
    label("RMS: " .. fmt_db(amp_to_db(a.max_rms)), x + 482, r2, 15)
    label("Mode: " .. tostring(a.audio_mode or "?"), x + 632, r2, 15)
    label(a.audio_line or "", x + 16, r3, 15, a.audio_ok and COLORS.green or COLORS.red, true)
    local warn = a.warnings[1] or "Nessun avviso."
    label(warn, x + 340, r3, 15, a.warnings[1] and COLORS.orange or COLORS.muted)
  elseif state.last_operation then
    local op = state.last_operation
    label("Ultima operazione:", x + 16, y + 58, 15, COLORS.title, true)
    label(string.format("%d item analizzati - %d segmenti creati - parlato %s", op.items or 0, op.created or 0, fmt_sec(op.speech)), x + 180, y + 58, 15)
    label(string.format("Distanza %s - fade %s - preset %s - soglia %s", fmt_sec(op.gap), fmt_ms(op.fade), tostring(op.preset or "?"), fmt_db(op.threshold_avg)), x + 16, y + 86, 15)
    label(state.status, x + 16, y + 112, 15, COLORS.green)
  else
    label("Premi ANALIZZA per calcolare soglia, silenzi e segmenti senza modificare il progetto.", x + 16, y + 62, 15, COLORS.muted)
  end

  state.content_h = (y + 146) - content_top
  local max_scroll = math.max(0, state.content_h - visible_h)
  state.scroll_y = clamp(state.scroll_y, 0, max_scroll)

  -- Ridisegna l'header sopra al contenuto scrollato.
  setc(COLORS.bg, 1); gfx.rect(0, 0, gfx.w, header_h, 1)
  label("ZP Studio Suite - Split Silenzi / Voice Cleaner", x, 18, 25, COLORS.title, true)
  label("Taglia pause, prepara take voiceover e controlla prima di applicare.", x + 2, 50, 15, COLORS.muted)
  status_pill(gfx.w - 174, 20, 140, 30, pill_text, audio_ok)

  -- Footer opaco e fisso.
  setc(COLORS.bg, 1); gfx.rect(0, footer_y - 8, gfx.w, gfx.h - footer_y + 8, 1)
  rect(x, footer_y, 996, 58, COLORS.panel)

  y = footer_y + 72
  local has_audio_items = #selected_audio_items() > 0
  local valid_analysis = state.analysis and state.analysis.audio_ok and state.analysis.segment_count > 0
  local keep_positions = effective_keep_positions()
  local can_preview = valid_analysis and keep_positions
  local can_apply = valid_analysis
  local preview_count = count_preview_regions()
  local preview_reason = "Fai prima ANALIZZA."
  if state.analysis and state.analysis.segment_count == 0 then preview_reason = "Nessun segmento valido."
  elseif valid_analysis and not keep_positions then preview_reason = "Preview disponibile solo con Posizione originale. Con Separa in sequenza il risultato viene riposizionato dopo Applica." end
  if button(x, y, 150, 38, "ANALIZZA", false, "warn", has_audio_items, "Seleziona almeno un item audio.", "analyze") then analyze() end
  if button(x + 164, y, 140, 38, "PREVIEW", false, nil, can_preview, preview_reason, "preview") then preview() end
  if button(x + 318, y, 140, 38, "APPLICA", false, "go", can_apply, "Non ci sono segmenti validi da applicare.", "apply") then apply() end
  if button(x + 472, y, 154, 38, "PULISCI PREVIEW", false, nil, preview_count > 0, "Nessuna regione preview da rimuovere.", "clean_preview") then cleanup_preview(); state.status = "Preview rimossa." end
  if button(x + 640, y, 90, 38, "HELP", false, nil, true, nil, "help") then open_help() end
  if button(x + 744, y, 120, 38, "CANCELLA", false, "danger", true, nil, "cancel") then cleanup_preview(); gfx.quit(); return end

  if state.help_title ~= "" then
    label(state.help_title, x + 14, footer_y + 10, 15, COLORS.title, true)
    label(state.help_text, x + 180, footer_y + 10, 15, COLORS.text)
  else
    label("Help contestuale", x + 14, footer_y + 10, 15, COLORS.title, true)
    label(state.status, x + 180, footer_y + 10, 15, COLORS.muted)
  end
  local wheel_delta = (gfx.mouse_wheel or 0) - (state.last_mouse_wheel or 0)
  if wheel_delta ~= 0 and not state.knob_hover then
    state.scroll_y = clamp(state.scroll_y - (wheel_delta > 0 and 55 or -55), 0, max_scroll)
  end

  state.mouse_was_down = (gfx.mouse_cap & 1) == 1
  state.last_mouse_wheel = gfx.mouse_wheel or 0
  gfx.update()
  reaper.defer(draw_gui)
end

gfx.init(SCRIPT_NAME, state.win_w, state.win_h, 0, 120, 120)
draw_gui()
