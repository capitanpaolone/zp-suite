-- @noindex
local path = debug.getinfo(1, "S").source:sub(2)
local dir = path:match("^(.*)[/\\]colori[/\\][^/\\]+$") or "."
dofile(dir .. "/ZP_Colori.lua").button(path)
