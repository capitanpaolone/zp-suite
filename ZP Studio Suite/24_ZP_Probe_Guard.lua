-- @noindex

-- ZP PROBE GUARD
-- Mantiene Voice e Music Probe come ultimo FX dei rispettivi BUS. Nessuna modifica audio/routing.
-- Allineato alla pulizia completa e heartbeat autonomo del Guard (2026-06-24).
-- 2026-09-02: pannello di stato e log delle azioni.
--   La finestra E' il Guard: aperta = attivo, chiusa = fermo.

local _, _, section_id, command_id = reaper.get_action_context()
local NEEDLE = "zp voice-music probe"
local GUARD_MAGIC = 905024
local GUARD_SLOT_MAGIC = 90
local GUARD_SLOT_TIME = 91
local GUARD_SLOT_STATE = 92
local last_check = 0

local sep = package.config:sub(1, 1)
local LOG_PATH = reaper.GetResourcePath() .. sep .. "ZP_ProbeGuard.log"

-- stato mostrato nel pannello
local vista = {
  vo_bus = "cerco…", vo_probe = "—",
  music_bus = "cerco…", music_probe = "—",
  interventi = 0,
  ultimo = "nessuno",
}

local function lower(s) return tostring(s or ""):lower() end

local function log(riga)
  local f = io.open(LOG_PATH, "a")
  if not f then return end
  f:write(os.date("%Y-%m-%d %H:%M:%S") .. "  " .. riga .. "\n")
  f:close()
end

local function apri_log()
  if not io.open(LOG_PATH, "r") then
    log("Log creato (nessun intervento finora).")
  end
  if reaper.CF_ShellExecute then
    reaper.CF_ShellExecute(LOG_PATH)
  elseif sep == "\\" then
    os.execute('start "" "' .. LOG_PATH .. '"')
  else
    os.execute('open "' .. LOG_PATH .. '" 2>/dev/null || xdg-open "' .. LOG_PATH .. '" 2>/dev/null &')
  end
end

local function find_role_track(role, fallback_name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, track_role = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:ZP_CHAIN_ROLE", "", false)
    if track_role == role then return track end
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if lower(name):find(fallback_name, 1, true) then return track end
  end
end

local function find_probe(track)
  for i = 0, reaper.TrackFX_GetCount(track) - 1 do
    local _, name = reaper.TrackFX_GetFXName(track, i, "")
    if lower(name):find(NEEDLE, 1, true) then return i end
  end
  return -1
end

-- ─────────────────────────── pannello ───────────────────────────

local W, H = 340, 168
gfx.init("ZP Probe Guard", W, H, 0, 200, 200)

local BTN = { x = 232, y = 132, w = 92, h = 24 }
local mouse_giu = false

local function riga(y, etichetta, valore, acceso)
  gfx.set(0.62, 0.66, 0.70)
  gfx.x, gfx.y = 14, y
  gfx.drawstr(etichetta)
  if acceso == true then gfx.set(0.30, 0.78, 0.42)
  elseif acceso == false then gfx.set(0.85, 0.55, 0.25)
  else gfx.set(0.80, 0.82, 0.84) end
  gfx.x, gfx.y = 140, y
  gfx.drawstr(valore)
end

local function disegna()
  gfx.set(0.09, 0.10, 0.12); gfx.rect(0, 0, gfx.w, gfx.h, true)

  gfx.set(0.30, 0.78, 0.42)
  gfx.circle(20, 20, 5, true, true)
  gfx.set(0.90, 0.92, 0.94)
  gfx.x, gfx.y = 34, 13
  gfx.drawstr("ZP Probe Guard — attivo")

  gfx.set(0.20, 0.22, 0.25)
  gfx.line(12, 36, gfx.w - 12, 36)

  riga(48,  "VO BUS",        vista.vo_bus,       vista.vo_bus ~= "non trovato")
  riga(68,  "Voice Probe",   vista.vo_probe,     vista.vo_probe == "ultima")
  riga(90,  "Music BUS",     vista.music_bus,    vista.music_bus ~= "non trovato")
  riga(110, "Music Probe",   vista.music_probe,  vista.music_probe == "ultima")

  gfx.set(0.55, 0.58, 0.62)
  gfx.x, gfx.y = 14, 138
  gfx.drawstr("Riordini: " .. tostring(vista.interventi))

  local sopra = gfx.mouse_x >= BTN.x and gfx.mouse_x <= BTN.x + BTN.w
               and gfx.mouse_y >= BTN.y and gfx.mouse_y <= BTN.y + BTN.h
  if sopra then gfx.set(0.24, 0.27, 0.31) else gfx.set(0.17, 0.19, 0.22) end
  gfx.rect(BTN.x, BTN.y, BTN.w, BTN.h, true)
  gfx.set(0.80, 0.83, 0.86)
  gfx.rect(BTN.x, BTN.y, BTN.w, BTN.h, false)
  gfx.x, gfx.y = BTN.x + 16, BTN.y + 5
  gfx.drawstr("Apri log")

  gfx.update()
end

-- ─────────────────────────── guardia ───────────────────────────

local function keep_last(track, etichetta)
  if not track then return false, "non trovato", "—" end
  local probe = find_probe(track)
  local last = reaper.TrackFX_GetCount(track) - 1
  if probe < 0 then return false, "presente", "assente" end
  if probe ~= last then
    reaper.TrackFX_CopyToTrack(track, probe, track, last, true)
    vista.interventi = vista.interventi + 1
    vista.ultimo = os.date("%H:%M:%S")
    log(etichetta .. ": Probe era in posizione " .. probe .. " di " .. last .. ", rimessa in fondo.")
    return true, "presente", "rimessa in fondo"
  end
  return true, "presente", "ultima"
end

local function guard()
  local now = reaper.time_precise()
  if now - last_check >= 1 then
    last_check = now

    local vo_ok, vo_bus, vo_probe = keep_last(find_role_track("VO_BUS", "zp vo"), "VO BUS")
    local music_ok, m_bus, m_probe = keep_last(find_role_track("MUSIC_BUS", "zp music"), "Music BUS")
    vista.vo_bus, vista.vo_probe = vo_bus, vo_probe
    vista.music_bus, vista.music_probe = m_bus, m_probe

    if reaper.gmem_attach and reaper.gmem_write then
      reaper.gmem_attach("ZPVoiceoverSharedBus")

      -- Heartbeat proprio del Probe Guard. Non simula la telemetria dei plugin:
      -- segnala soltanto al Chain Builder che questo script è realmente attivo.
      reaper.gmem_write(GUARD_SLOT_MAGIC, GUARD_MAGIC)
      reaper.gmem_write(GUARD_SLOT_TIME, now)
      reaper.gmem_write(GUARD_SLOT_STATE, 1)

      if not vo_ok then
        reaper.gmem_write(50, 0); reaper.gmem_write(51, 0); reaper.gmem_write(52, 0)
      end
      if not music_ok then
        reaper.gmem_write(60, 0); reaper.gmem_write(61, 0); reaper.gmem_write(62, 0)
      end
    end
  end

  local tasto = gfx.getchar()
  if tasto == -1 or tasto == 27 then gfx.quit(); return end

  if gfx.mouse_cap & 1 == 1 then
    if not mouse_giu then
      mouse_giu = true
      if gfx.mouse_x >= BTN.x and gfx.mouse_x <= BTN.x + BTN.w
         and gfx.mouse_y >= BTN.y and gfx.mouse_y <= BTN.y + BTN.h then
        apri_log()
      end
    end
  else
    mouse_giu = false
  end

  disegna()
  reaper.defer(guard)
end

local function stop()
  if reaper.gmem_attach and reaper.gmem_write then
    reaper.gmem_attach("ZPVoiceoverSharedBus")
    reaper.gmem_write(GUARD_SLOT_MAGIC, 0)
    reaper.gmem_write(GUARD_SLOT_TIME, 0)
    reaper.gmem_write(GUARD_SLOT_STATE, 0)
  end
  log("Probe Guard fermato. Riordini in questa sessione: " .. tostring(vista.interventi) .. ".")
  reaper.SetToggleCommandState(section_id, command_id, 0)
  reaper.RefreshToolbar2(section_id, command_id)
end

reaper.SetToggleCommandState(section_id, command_id, 1)
reaper.RefreshToolbar2(section_id, command_id)
reaper.atexit(stop)
log("Probe Guard avviato.")
guard()
