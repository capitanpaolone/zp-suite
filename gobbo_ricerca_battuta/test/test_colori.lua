-- Verifica del flusso: modo -> selezione -> clic colore.
local Pure = dofile("ZP Studio Suite/ZP_Colori.lua")
local fails = 0
local function check(name, ok)
  print((ok and "ok   " or "FAIL ") .. name)
  if not ok then fails = fails + 1 end
end
check("palette di 20 colori", #Pure.PALETTE == 20 and Pure.color_file(7) == "ZP_Colori_07_Blu.lua")
check("Auto è il modo iniziale", Pure.valid_mode("") == "auto")
check("Auto registrato anche come azione REAPER persistente",
  Pure.mode_ids_from_kb('SCR 260 0 RSabc "Custom: ZP_Colori_Auto.lua" "ZP Suite/ZP Studio Suite/colori/ZP_Colori_Auto.lua"').auto == "_RSabc")

local ext = { modo = "item", autocolor = "1", auto_generation = "3" }
local commands, toggles = {}, {}
for i, mode in ipairs(Pure.MODES) do
  ext["cmd_" .. mode] = "_RS" .. mode
  commands["_RS" .. mode] = 100 + i
end
local current_command = commands._RSauto
local track = { color = 0 }
local item1, item2 = { color = 0, track = track }, { color = 0, track = track }
track.items = { item1, item2 }
local marker = { region = false, selected = false, color = 0, index = 1 }
local region = { region = true, selected = false, color = 0, index = 2 }
local items, tracks = {}, {}
local paints, undos, timeline_redraws, item_updates = 0, 0, 0, 0
reaper = {
  GetExtState = function(_, key) return ext[key] or "" end,
  SetExtState = function(_, key, value) ext[key] = value end,
  GetResourcePath = function() return "/missing" end,
  NamedCommandLookup = function(id) return commands[id] or 0 end,
  SetToggleCommandState = function(_, cmd, state) toggles[cmd] = state end,
  RefreshToolbar2 = function() end,
  get_action_context = function() return true, "", 0, current_command end,
  ReverseNamedCommandLookup = function(cmd)
    for id, num in pairs(commands) do if num == cmd then return id:sub(2) end end
  end,
  EnumProjects = function() return "project", "" end,
  CountSelectedMediaItems = function() return #items end,
  GetSelectedMediaItem = function(_, i) return items[i + 1] end,
  CountSelectedTracks = function() return #tracks end,
  GetSelectedTrack = function(_, i) return tracks[i + 1] end,
  GetMediaItem_Track = function(item) return item.track end,
  CountTrackMediaItems = function(t) return #t.items end,
  GetTrackMediaItem = function(t, i) return t.items[i + 1] end,
  GetNumRegionsOrMarkers = function() return 2 end,
  GetRegionOrMarker = function(_, i) return ({ marker, region })[i + 1] end,
  GetRegionOrMarkerInfo_Value = function(_, obj, key)
    if key == "B_ISREGION" then return obj.region and 1 or 0 end
    if key == "B_UISEL" then return obj.selected and 1 or 0 end
    if key == "I_INDEX" then return obj.index end
    if key == "I_CUSTOMCOLOR" then return obj.color end
  end,
  SetRegionOrMarkerInfo_Value = function(_, obj, _, value) obj.color = value; paints = paints + 1 end,
  GetMediaItemInfo_Value = function(obj) return obj.color end,
  SetMediaItemInfo_Value = function(obj, _, value) obj.color = value; paints = paints + 1 end,
  GetMediaTrackInfo_Value = function(obj) return obj.color end,
  SetMediaTrackInfo_Value = function(obj, _, value) obj.color = value; paints = paints + 1 end,
  CountTakes = function() return 0 end,
  ColorToNative = function(r, g, b) return r + g * 256 + b * 65536 end,
  Undo_BeginBlock = function() undos = undos + 1 end,
  PreventUIRefresh = function() end,
  UpdateArrange = function() end,
  UpdateTimeline = function() timeline_redraws = timeline_redraws + 1 end,
  UpdateItemInProject = function() item_updates = item_updates + 1 end,
  Undo_EndBlock = function() end,
  GetMousePosition = function() return 0, 0 end,
  TrackCtl_SetToolTip = function() end,
  time_precise = function() return 0 end,
  defer = function() error("Auto non deve avviare un monitor") end,
}
local C = dofile("ZP Studio Suite/ZP_Colori.lua")
local function only_lit(mode)
  for _, m in ipairs(C.MODES) do
    if toggles[commands[ext["cmd_" .. m]]] ~= (m == mode and 1 or 0) then return false end
  end
  return true
end
C.refresh_buttons()
check("migrazione spegne il vecchio monitor e accende solo Auto", C.get_mode() == "auto"
  and ext.autocolor == "0" and ext.auto_generation == "4" and only_lit("auto"))
C.set_mode("marker")
marker.selected, items[1] = true, item1
check("selezionare non colora", only_lit("marker") and paints == 0)
C.color(1)
check("Marker colora e ridisegna il righello al clic", marker.color ~= 0 and item1.color == 0
  and undos == 1 and timeline_redraws == 1)
C.set_mode("regione")
region.selected = true
local before = paints
C.color(2)
check("Regione colora solo la regione", paints == before + 1 and region.color ~= 0 and only_lit("regione"))
C.set_mode("item")
before = paints
C.color(3)
check("Item colora e aggiorna l'item al clic", paints == before + 1 and item1.color ~= 0
  and item_updates == 1 and only_lit("item"))
C.set_mode("traccia")
tracks[1] = track
before = paints
C.color(4)
check("Traccia colora solo la traccia", paints == before + 1 and track.color ~= 0 and only_lit("traccia"))
C.set_mode("tutto")
before = paints
C.color(5)
check("Tutto colora traccia e tutti i suoi item", paints == before + 3 and item2.color ~= 0 and only_lit("tutto"))
current_command = commands._RSauto
C.button("colori/ZP_Colori_Auto.lua")
check("Auto è acceso senza monitor", only_lit("auto") and ext.autocolor == "0")
before = paints
C.color(6)
check("Auto colora item, marker e regione solo al clic", paints == before + 3 and track.color ~= item1.color)
C.button("colori/ZP_Colori_Auto.lua")
check("secondo clic Auto resta acceso", only_lit("auto"))
ext.autocolor = "1" -- simula una vecchia finestrella ancora in memoria
C.color(7)
check("un nuovo clic colore arresta il vecchio monitor", ext.autocolor == "0")

reaper = nil -- carica solo la logica pura dell'installer
local T = dofile("ZP Studio Suite/32_Installa_Toolbar_ZP.lua")
local txt = T.menu_text(T.LAYOUT_COLORI, setmetatable({}, { __index = function() return "_RSx" end }), T.TITLE_COLORI, nil, 5)
check("toolbar con sei modi, 20 colori e Togli", select(2, txt:gsub("\nitem_", "")) == 29
  and txt:find("icon_0=ZP_tbC_Auto.png", 1, true)
  and txt:find("icon_5=ZP_tbC_Regione.png", 1, true)
  and txt:find("icon_7=ZP_tbC_01.png", 1, true)
  and txt:find("icon_28=ZP_tbC_Togli.png", 1, true))
for _, e in ipairs(T.LAYOUT_COLORI) do
  if e ~= "-" then
    local script = io.open("ZP Studio Suite/" .. e[1], "rb")
    local icon = io.open("ZP Studio Suite/icons/" .. e[3], "rb")
    check("script e icona " .. e[1], script ~= nil and icon ~= nil)
    if script then script:close() end
    if icon then icon:close() end
  end
end
reaper = nil
print(fails == 0 and "\nTUTTI OK" or ("\nFALLITI: " .. fails))
os.exit(fails == 0 and 0 or 1)
