-- Simulazione dell'helper Cue Navigator con un REAPER finto: piu' progetti in schede e cambio di scheda.
-- Lancio dalla radice del repo:  lua gobbo_ricerca_battuta/test/test_hsc_schede.lua [file helper]
-- Il Carver finto fa quello che fa il JSFX in quick_service: scrive i suoi cue in gmem e applica il comando 5.
local HELPER = arg and arg[1] or "ZP Voce/ZP Harmonic Space Carver Cue Navigator.lua"
local fails = 0
local function check(name, cond) if not cond then fails = fails + 1; print("FAIL " .. name) end end

local MAGIC, MB, SLOT_BASE, SLOT_STRIDE = 905243, 3800, 8310000, 76
local gmem, ext, now, state_count = {}, {}, 0, 0
local projects, active = {}, nil

local function new_project(name, slot, cues, markers)
  local p = { name = name, file = "/progetti/" .. name .. ".RPP", tracks = {}, markers = {}, next_num = 1 }
  p.master = { proj = p, fx = {} }
  local t = { proj = p, fx = {} }
  if slot then t.fx[1] = { slot = slot, cues = cues or {} } end
  p.tracks[1] = t
  for _, pos in ipairs(markers or {}) do
    p.markers[#p.markers + 1] = { num = p.next_num, pos = pos, name = "#HSC", color = 0 }; p.next_num = p.next_num + 1
  end
  projects[#projects + 1] = p
  return p
end
local function P(proj) return (proj == 0 or proj == nil) and active or proj end
local function carvers_of(p)
  local out = {}
  for _, t in ipairs(p.tracks) do for _, fx in ipairs(t.fx) do out[#out + 1] = fx end end
  return out
end

-- Carver finto (tutti i progetti girano: "Run background projects" acceso, il caso peggiore)
local function carver_tick()
  for _, p in ipairs(projects) do
    for _, c in ipairs(carvers_of(p)) do
      local base = SLOT_BASE + c.slot * SLOT_STRIDE
      local seq = gmem[MB + 3] or 0
      if seq ~= (c.seen or 0) then
        c.seen = seq
        if gmem[MB] == base and math.floor((gmem[MB + 1] or 0) + 0.5) == 5 then
          local n, list = math.floor(gmem[MB + 10] + 0.5), {}
          for i = 1, n do if gmem[MB + 10 + i] >= 0 then list[#list + 1] = gmem[MB + 10 + i] end end
          table.sort(list); c.cues = list
          gmem[MB + 4] = seq
        end
      end
      gmem[base + 69] = MAGIC; gmem[base + 4] = #c.cues
      for i = 0, 63 do gmem[base + 5 + i] = c.cues[i + 1] or -1 end
    end
  end
end

reaper = {
  gmem_attach = function() end,
  gmem_read = function(i) return gmem[i] or 0 end,
  gmem_write = function(i, v) gmem[i] = v end,
  time_precise = function() return now end,
  defer = function() end,
  GetExtState = function(s, k) return ext[s .. "/" .. k] or "" end,
  SetExtState = function(s, k, v) ext[s .. "/" .. k] = v end,
  DeleteExtState = function(s, k) ext[s .. "/" .. k] = nil end,
  GetProjExtState = function() return 0, "" end,
  SetProjExtState = function() end,
  GetProjectStateChangeCount = function() return state_count end,
  EnumProjects = function(i)
    if i == -1 then return active, active.file end
    local p = projects[i + 1]; if p then return p, p.file end
  end,
  GetMasterTrack = function(proj) return P(proj).master end,
  CountTracks = function(proj) return #P(proj).tracks end,
  GetTrack = function(proj, i) return P(proj).tracks[i + 1] end,
  GetParentTrack = function() return nil end,
  GetTrackNumSends = function() return 0 end,
  GetMediaTrackInfo_Value = function(_, k) if k == "I_NCHAN" then return 2 end return 0 end,
  CountTrackMediaItems = function() return 0 end,
  TrackFX_GetCount = function(t) return #t.fx end,
  TrackFX_GetFXName = function() return true, "JS: ZP Harmonic Space Carver Ducker" end,
  TrackFX_GetNumParams = function() return 1 end,
  TrackFX_GetParamName = function() return true, "HSC Slot" end,
  TrackFX_GetParam = function(t, fx) return t.fx[fx + 1].slot end,
  TrackFX_SetParam = function(t, fx, _, v) t.fx[fx + 1].slot = v end,
  TrackFX_GetPinMappings = function() return 0 end,
  EnumProjectMarkers3 = function(proj, i)
    local m = P(proj).markers[i + 1]
    if not m then return 0 end
    return i + 1, false, m.pos, 0, m.name, m.num, m.color
  end,
  AddProjectMarker2 = function(proj, _, pos, _, name, _, color)
    local p = P(proj)
    local m = { num = p.next_num, pos = pos, name = name, color = color }
    p.next_num = p.next_num + 1; p.markers[#p.markers + 1] = m; state_count = state_count + 1
    table.sort(p.markers, function(a, b) return a.pos < b.pos end)
    return m.num
  end,
  DeleteProjectMarker = function(proj, num)
    local p = P(proj)
    for i, m in ipairs(p.markers) do if m.num == num then table.remove(p.markers, i); state_count = state_count + 1; return true end end
  end,
  SetProjectMarker3 = function(proj, num, _, pos, _, name, color)
    for _, m in ipairs(P(proj).markers) do if m.num == num then m.pos, m.name, m.color = pos, name, color end end
  end,
  ColorToNative = function(r, g, b) return r + g * 256 + b * 65536 end,
  PreventUIRefresh = function() end, UpdateTimeline = function() end,
  GetPlayState = function() return 0 end, GetCursorPosition = function() return 0 end,
  SetEditCurPos2 = function() end, GetMousePosition = function() return 0, 0 end,
  TrackCtl_SetToolTip = function() end,
  Undo_BeginBlock2 = function() end, Undo_EndBlock2 = function() end,
}

local function marks(p) local o = {} for _, m in ipairs(p.markers) do o[#o + 1] = string.format("%g", m.pos) end table.sort(o) return table.concat(o, ",") end
local function cues(p) local o = {} for _, c in ipairs(carvers_of(p)) do for _, t in ipairs(c.cues) do o[#o + 1] = string.format("%g", t) end end table.sort(o) return table.concat(o, ",") end

-- Il cambio di scheda cade in un punto qualsiasi fra due riletture dei Carver (ogni 1 s): si prova ogni 0,05 s.
local function scenario(offset)
  gmem, ext, now, state_count, projects = {}, {}, 0, 0, {}
  local A = new_project("A", 1, { 10, 20 }, { 10, 20 })
  local B = new_project("B", 2, { 50 }, { 50 })
  local C = new_project("C", nil, nil, {})
  active = A
  HSC_SYNC_SIM = true
  local sim = dofile(HELPER)
  local function step(dt) now = now + (dt or 0.3); carver_tick(); sim.run_once() end
  local tag = string.format(" [cambio a +%.2f s]", offset)
  for _ = 1, 8 do step() end
  check("A: marker e cue al loro posto" .. tag, marks(A) == "10,20" and cues(A) == "10,20")
  -- scheda A -> C (senza Carver): i cue di A non entrano in C
  now = now + offset; active = C
  for _ = 1, 40 do step(0.033) end
  check("C senza Carver: nessun marker da A (" .. marks(C) .. ")" .. tag, marks(C) == "")
  -- scheda A -> B diretta: B tiene marker e cue suoi
  active = A; for _ = 1, 8 do step() end
  now = now + offset; active = B
  for _ = 1, 40 do step(0.033) end
  check("B: tiene i suoi marker (" .. marks(B) .. ")" .. tag, marks(B) == "50")
  check("B: tiene i suoi cue (" .. cues(B) .. ")" .. tag, cues(B) == "50")
  check("A: intatto (" .. marks(A) .. " / " .. cues(A) .. ")" .. tag, marks(A) == "10,20" and cues(A) == "10,20")
  return B, step
end

for k = 0, 20 do scenario(k * 0.05) end

-- ELIMINA nel Carver (piu' cue): l'helper toglie i marker
local B, step = scenario(0)
carvers_of(B)[1].cues = { 50, 60, 70 }; for _ = 1, 6 do step() end
check("B: cue aggiunti -> marker", marks(B) == "50,60,70")
carvers_of(B)[1].cues = { 60 }; for _ = 1, 6 do step() end
check("B: ELIMINA di due cue -> due marker tolti (" .. marks(B) .. ")", marks(B) == "60" and cues(B) == "60")
-- due cue nello stesso punto (marker doppi): ELIMINA li toglie entrambi
carvers_of(B)[1].cues = { 60, 80, 80 }; for _ = 1, 6 do step() end
check("B: due cue nello stesso punto -> due marker", marks(B) == "60,80,80")
carvers_of(B)[1].cues = { 60 }; for _ = 1, 6 do step() end
check("B: ELIMINA dei due cue doppi -> marker tolti (" .. marks(B) .. ")", marks(B) == "60" and cues(B) == "60")
-- un #HSC cancellato a mano torna (regola di Paolo, invariata)
table.remove(B.markers, 1); state_count = state_count + 1; for _ = 1, 4 do step() end
check("B: marker cancellato a mano torna", marks(B) == "60" and cues(B) == "60")

print(fails == 0 and "TUTTI OK" or (fails .. " FALLITI"))
