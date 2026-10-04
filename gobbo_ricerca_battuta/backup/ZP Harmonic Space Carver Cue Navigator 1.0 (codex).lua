-- @description ZP Harmonic Space Carver Cue Navigator (background helper)
-- @version 1.0
-- @author Paolo Balestri / Codex
-- @about Keeps the Carver previous/current/next cue buttons connected to the REAPER edit/play cursor.
local GMEM_NAME = "ZPVoiceoverSharedBus"
local MAGIC = 905243
local BASE_START = 4096
local TRACK_STRIDE = 4096
local FX_STRIDE = 72
local MAX_BASE = 8300000
local last_seq = {}
reaper.gmem_attach(GMEM_NAME)

local function read_cues(base)
  local n = math.max(0, math.min(64, math.floor(reaper.gmem_read(base + 4) + 0.5)))
  local cues = {}
  for i = 0, n - 1 do
    local t = reaper.gmem_read(base + 5 + i)
    if t >= 0 then cues[#cues + 1] = {time = t, index = i} end
  end
  table.sort(cues, function(a,b) return a.time < b.time end)
  return cues
end

local function seek(time)
  local playing = (reaper.GetPlayState() & 1) == 1
  reaper.SetEditCurPos2(0, time, true, playing)
end

local function handle(base)
  if reaper.gmem_read(base + 69) ~= MAGIC then return end
  local seq = math.floor(reaper.gmem_read(base + 1) + 0.5)
  local ack = math.floor(reaper.gmem_read(base + 3) + 0.5)
  if seq == ack or seq == last_seq[base] then return end
  local cmd = math.floor(reaper.gmem_read(base) + 0.5)
  local cues = read_cues(base)
  local selected = -1
  local target = nil
  if cmd == 1 or cmd == 2 then
    local now = ((reaper.GetPlayState() & 1) == 1) and reaper.GetPlayPosition2() or reaper.GetCursorPosition()
    if cmd == 1 then
      for _, cue in ipairs(cues) do
        if cue.time < now - 0.001 then selected = cue.index; target = cue.time else break end
      end
    else
      for _, cue in ipairs(cues) do
        if cue.time > now + 0.001 then selected = cue.index; target = cue.time; break end
      end
    end
  elseif cmd == 3 then
    selected = math.floor(reaper.gmem_read(base + 2) + 0.5)
    for _, cue in ipairs(cues) do
      if cue.index == selected then target = cue.time; break end
    end
  end
  reaper.gmem_write(base + 2, selected)
  if target then seek(target) end
  reaper.gmem_write(base + 3, seq)
  last_seq[base] = seq
end

local function scan_track(track, track_index)
  local n = reaper.TrackFX_GetCount(track)
  for fx = 0, n - 1 do
    local ok, name = reaper.TrackFX_GetFXName(track, fx, "")
    if ok and name and name:lower():find("harmonic space carver", 1, true) then
      local base = BASE_START + ((track_index + 2) * TRACK_STRIDE) + (fx * FX_STRIDE)
      if base >= 0 and base < MAX_BASE then handle(base) end
    end
  end
end

local function run()
  scan_track(reaper.GetMasterTrack(0), -1)
  local n = reaper.CountTracks(0)
  for i = 0, n - 1 do scan_track(reaper.GetTrack(0, i), i) end
  reaper.defer(run)
end
run()
