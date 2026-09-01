local script_dir = (debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "")
local A = dofile(script_dir .. "lib_RythmoBand_Accessibile.lua")

local items, err = A.collect_items()
if not items then A.speak(err) return end

local pos = A.project_position()
local index, entry = A.find_previous(items, pos)

if not entry then
  A.speak("Non ci sono battute precedenti.")
  return
end

reaper.SetEditCurPos(entry.pos, true, false)
A.speak(A.format_entry("Battuta precedente", index, #items, entry))
