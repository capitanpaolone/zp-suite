-- @noindex

-- ZP Studio Suite for REAPER
-- Pulsante della toolbar "ZP Colori". Cosa fa lo dice il nome di questo file
-- (colore, modo o Togli); la logica e' in ../ZP_Colori.lua.
local path = debug.getinfo(1, "S").source:sub(2)
local dir = path:match("^(.*)[/\\]colori[/\\][^/\\]+$") or "."
dofile(dir .. "/ZP_Colori.lua").button(path)
