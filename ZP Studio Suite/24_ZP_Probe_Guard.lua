-- ZP PROBE GUARD
-- Mantiene Voice e Music Probe come ultimo FX dei rispettivi BUS. Nessuna modifica audio/routing.
-- Allineato alla pulizia completa e heartbeat autonomo del Guard (2026-06-24).

local _, _, section_id, command_id = reaper.get_action_context()
local NEEDLE = "zp voice-music probe"
local GUARD_MAGIC = 905024
local GUARD_SLOT_MAGIC = 90
local GUARD_SLOT_TIME = 91
local GUARD_SLOT_STATE = 92
local last_check = 0

local function lower(s) return tostring(s or ""):lower() end

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

local function guard()
  local now = reaper.time_precise()
  if now - last_check >= 1 then
    last_check = now
    local function keep_last(track)
      if not track then return false end
      local probe = find_probe(track)
      local last = reaper.TrackFX_GetCount(track) - 1
      if probe >= 0 and probe ~= last then
        reaper.TrackFX_CopyToTrack(track, probe, track, last, true)
      end
      return probe >= 0
    end
    local vo_ok = keep_last(find_role_track("VO_BUS", "zp vo"))
    local music_ok = keep_last(find_role_track("MUSIC_BUS", "zp music"))
    -- Il Guard non simula heartbeat: pulisce soltanto firme rimaste da Probe rimosse.
    if reaper.gmem_attach and reaper.gmem_write then
      reaper.gmem_attach("ZPVoiceoverSharedBus")

      -- Heartbeat proprio del Probe Guard. Non simula la telemetria dei plugin:
      -- segnala soltanto al Chain Builder che questo script è realmente attivo.
      reaper.gmem_write(GUARD_SLOT_MAGIC, GUARD_MAGIC)
      reaper.gmem_write(GUARD_SLOT_TIME, now)
      reaper.gmem_write(GUARD_SLOT_STATE, 1)

      if not vo_ok then
        reaper.gmem_write(50, 0)
        reaper.gmem_write(51, 0)
        reaper.gmem_write(52, 0)
      end
      if not music_ok then
        reaper.gmem_write(60, 0)
        reaper.gmem_write(61, 0)
        reaper.gmem_write(62, 0)
      end
    end
  end
  reaper.defer(guard)
end

local function stop()
  if reaper.gmem_attach and reaper.gmem_write then
    reaper.gmem_attach("ZPVoiceoverSharedBus")
    reaper.gmem_write(GUARD_SLOT_MAGIC, 0)
    reaper.gmem_write(GUARD_SLOT_TIME, 0)
    reaper.gmem_write(GUARD_SLOT_STATE, 0)
  end
  reaper.SetToggleCommandState(section_id, command_id, 0)
  reaper.RefreshToolbar2(section_id, command_id)
end

reaper.SetToggleCommandState(section_id, command_id, 1)
reaper.RefreshToolbar2(section_id, command_id)
reaper.atexit(stop)
guard()
