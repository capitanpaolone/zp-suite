--[[
ZP Studio Suite for REAPER
22_SRT_Tools.lua
Opens the local offline SRT Tools page in the default browser.
]]

local function join(a, b)
  local sep = package.config:sub(1, 1)
  if a:sub(-1) == sep then return a .. b end
  return a .. sep .. b
end

local resource = reaper.GetResourcePath()
local tool_path = join(join(join(join(resource, "Scripts"), "ZP_Studio_Suite"), "tools"), "srt_tools.html")

local f = io.open(tool_path, "r")
if not f then
  reaper.ShowMessageBox("SRT Tools non trovato:\n\n" .. tool_path, "ZP Studio Suite", 0)
  return
end
f:close()

local osname = reaper.GetOS()
local quoted = string.format("%q", tool_path)
if osname:match("OSX") or osname:match("macOS") then
  os.execute("open " .. quoted .. " &")
elseif osname:match("Win") then
  os.execute('start "" ' .. quoted)
else
  os.execute("xdg-open " .. quoted .. " >/dev/null 2>&1 &")
end
