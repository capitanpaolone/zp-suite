local script_dir = (debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "")
local A = dofile(script_dir .. "lib_RythmoBand_Accessibile.lua")

local _, _, section_id, command_id = reaper.get_action_context()
local state_key = "auto_read_enabled"
local last_key = "auto_read_last_index"
local section = "RythmoBand_Accessibile"

local currently_on = reaper.GetExtState(section, state_key) == "1"

if currently_on then
  reaper.SetExtState(section, state_key, "0", false)
  if command_id and command_id ~= 0 then
    reaper.SetToggleCommandState(section_id, command_id, 0)
    reaper.RefreshToolbar2(section_id, command_id)
  end
  A.speak("Lettura automatica ZP Studio Suite disattivata.")
  return
end

reaper.SetExtState(section, state_key, "1", false)
reaper.SetExtState(section, last_key, "", false)
if command_id and command_id ~= 0 then
  reaper.SetToggleCommandState(section_id, command_id, 1)
  reaper.RefreshToolbar2(section_id, command_id)
end
A.speak("Lettura automatica ZP Studio Suite attivata.")

local function loop()
  if reaper.GetExtState(section, state_key) ~= "1" then
    if command_id and command_id ~= 0 then
      reaper.SetToggleCommandState(section_id, command_id, 0)
      reaper.RefreshToolbar2(section_id, command_id)
    end
    return
  end

  local items = A.collect_items()
  if items then
    local pos = A.project_position()
    local index, entry = A.find_current(items, pos)
    local last_index = reaper.GetExtState(section, last_key)
    if entry and tostring(index) ~= last_index then
      reaper.SetExtState(section, last_key, tostring(index), false)
      A.speak(A.format_entry("Battuta", index, #items, entry))
    end
  end

  reaper.defer(loop)
end

reaper.defer(loop)
