-- Collaudo "a secco" delle finestre della Suite: un REAPER finto (reaper.* e gfx.* che rispondono
-- con valori neutri) apre uno script, gli fa disegnare N giri e raccoglie gli errori.
-- Trova i crash al disegno (funzioni nil, testi nil in drawstr, format sbagliati) in italiano e
-- in inglese, senza toccare il REAPER vero. Non sostituisce la prova in REAPER: i valori finti
-- possono dare falsi allarmi (da leggere a mano).
-- Uso, dalla radice del repo:  lua gobbo_ricerca_battuta/test/fumo_finestre.lua it|en script.lua [giri]

local lang, script, frames = arg[1] or "it", arg[2], tonumber(arg[3]) or 40
assert(script, "uso: fumo_finestre.lua it|en percorso_script.lua [giri]")
local tmp = os.getenv("ZP_FUMO_RES") or "/tmp/zp_fumo_res"
os.execute("mkdir -p '" .. tmp .. "'")

local ext = { ["ZP_STUDIO_SUITE/lingua"] = lang, ["ZP_STUDIO_SUITE/benvenuto_visto"] = "1" }
local deferred, frame = nil, 0

local R = {
  GetResourcePath = function() return tmp end,
  GetExePath = function() return "/Applications" end,
  GetOS = function() return "macOS-arm64" end,
  GetAppVersion = function() return "7.82/macOS-arm64" end,
  GetExtState = function(s, k) return ext[s .. "/" .. k] or "" end,
  HasExtState = function(s, k) return ext[s .. "/" .. k] ~= nil end,
  SetExtState = function(s, k, v) ext[s .. "/" .. k] = tostring(v) end,
  DeleteExtState = function(s, k) ext[s .. "/" .. k] = nil end,
  GetProjExtState = function() return 0, "" end,
  SetProjExtState = function() return 0 end,
  defer = function(f) deferred = f end,
  atexit = function() end,
  time_precise = function() return os.clock() + frame * 0.05 end,
  get_action_context = function()
    local full = script:match("^/") and script or ((os.getenv("PWD") or ".") .. "/" .. script)
    return false, full, 0, 0, 0, 0, 0
  end,
  GetSet_LoopTimeRange = function() return 0, 0 end,
  GetSet_LoopTimeRange2 = function() return 0, 0 end,
  GetProjectName = function() return "" end,
  GetProjectPath = function() return tmp end,
  EnumProjects = function() return nil, "" end,
  GetSetProjectInfo_String = function() return false, "" end,
  GetTrackName = function() return true, "Traccia" end,
  GetSetMediaTrackInfo_String = function() return false, "" end,
  GetSetMediaItemInfo_String = function() return false, "" end,
  GetSetMediaItemTakeInfo_String = function() return false, "" end,
  GetTakeName = function() return "" end,
  GetMediaSourceFileName = function() return "" end,
  EnumProjectMarkers = function() return 0 end,
  EnumProjectMarkers3 = function() return 0 end,
  CountProjectMarkers = function() return 0, 0, 0 end,
  GetPlayState = function() return 0 end,
  GetCursorPosition = function() return 0 end,
  GetPlayPosition = function() return 0 end,
  format_timestr_pos = function() return "0:00.000" end,
  format_timestr = function() return "0:00.000" end,
  NamedCommandLookup = function() return 0 end,
  ReverseNamedCommandLookup = function() return nil end,
  GetToggleCommandState = function() return 0 end,
  get_config_var_string = function() return false, "" end,
  GetInputChannelName = function() return "In 1" end,
  GetMousePosition = function() return 0, 0 end,
  EnumerateFiles = function() return nil end,
  EnumerateSubdirectories = function() return nil end,
  file_exists = function() return false end,
  APIExists = function() return false end,
  ShowConsoleMsg = function(s) io.stderr:write("[console] " .. tostring(s)) end,
  MB = function() return 2 end, ShowMessageBox = function() return 2 end,
  GetUserInputs = function() return false, "" end,
  CF_GetSWSVersion = nil, JS_Window_Find = nil, osara_outputMessage = nil,
}
reaper = setmetatable(R, { __index = function(_, k)
  -- estensioni (SWS, JS, OSARA...) assenti come su un REAPER pulito; il resto risponde 0
  if k:match("^CF_") or k:match("^JS_") or k:match("^SNM_") or k:match("^BR_") or k:match("^NF_")
    or k:match("^ImGui") or k:match("^osara") or k:match("^ULT_") then return nil end
  return function() return 0 end
end })

local G = { w = 900, h = 700, x = 0, y = 0, mouse_x = -1, mouse_y = -1, mouse_cap = 0, mouse_wheel = 0,
  mouse_hwheel = 0, texth = 14, r = 1, g = 1, b = 1, a = 1, dest = -1 }
local function chk(name, ...)
  return ...
end
G.init = function(title) assert(type(title) == "string", "gfx.init: titolo non stringa"); return 1 end
G.quit = function() end
G.update = function() end
G.dock = function() return 0, 0, 0, 900, 700 end
-- a ogni giro il mouse (senza clic) passa su un punto diverso di una griglia 12x10 sulla finestra:
-- cosi' scattano anche i disegni al passaggio del mouse (suggerimenti, evidenziati)
G.getchar = function()
  frame = frame + 1
  if frame > frames then return -1 end
  local i = frame - 1
  G.mouse_x = 20 + (i % 12) * math.floor((G.w - 40) / 11)
  G.mouse_y = 20 + (math.floor(i / 12) % 10) * math.floor((G.h - 40) / 9)
  return 0
end
G.setfont = function() end
G.set = function(r, g, b) assert(type(r) == "number", "gfx.set: colore non numerico") end
G.measurestr = function(s)
  assert(type(s) == "string" or type(s) == "number", "gfx.measurestr: argomento " .. type(s))
  return #tostring(s) * 7, 14
end
G.drawstr = function(s)
  assert(type(s) == "string" or type(s) == "number", "gfx.drawstr: argomento " .. type(s))
  G.x = G.x + #tostring(s) * 7
end
G.showmenu = function(s) assert(type(s) == "string", "gfx.showmenu: argomento " .. type(s)); return 0 end
G.loadimg = function() return -1 end
G.getimgdim = function() return 0, 0 end
G.setimgdim = function() end
for _, n in ipairs({ "rect", "roundrect", "circle", "line", "triangle", "blit", "gradrect", "lineto", "arc",
  "drawchar", "printf", "muladdrect", "setpixel", "getpixel", "drawnumber", "setcursor", "clienttoscreen", "screentoclient" }) do
  G[n] = G[n] or function() return 0, 0 end
end
gfx = setmetatable(G, { __index = function(_, k) return function() return 0 end end })

local ok, err = xpcall(function() dofile(script) end, debug.traceback)
local n = 0
while ok and deferred and n < frames do
  local f = deferred
  deferred = nil
  n = n + 1
  ok, err = xpcall(f, debug.traceback)
end
if ok then
  print(string.format("OK    %-3s %s (%d giri)", lang, script, n))
else
  print(string.format("ERR   %-3s %s al giro %d\n%s", lang, script, n, tostring(err):gsub("\n", "\n      ")))
  os.exit(1)
end
