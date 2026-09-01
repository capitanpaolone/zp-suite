local script_dir = (debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "")
local A = dofile(script_dir .. "lib_RythmoBand_Accessibile.lua")

local items, err = A.collect_items()
if not items then A.speak(err) return end

local pos = A.project_position()
local index, entry = A.find_current(items, pos)

if not entry then
  index, entry = A.find_next(items, pos)
  if entry then
    A.speak(A.format_entry("Nessuna battuta corrente. Prossima battuta", index, #items, entry))
  else
    A.speak("Nessuna battuta corrente. Sei oltre l'ultima battuta.")
  end
  return
end

A.speak(A.format_entry("Battuta corrente", index, #items, entry))
