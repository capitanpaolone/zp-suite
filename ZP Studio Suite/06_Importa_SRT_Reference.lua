-- SCORCIATOIA: IMPORTA SRT REFERENCE
-- Linea: ZP Paolo Balestri
-- Suite: ZP Studio Suite for REAPER v1.0.5
-- Distribuzione gratuita.
-- Usa lo stesso motore sicuro di 05_Aggiorna_SRT_Video.lua.

local SCRIPT_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "")
local manager = SCRIPT_DIR .. "05_worker_Gestione_SRT.lua"

_G.RYTHMOBAND_UPDATE_MODE = "reference"
dofile(manager)
_G.RYTHMOBAND_UPDATE_MODE = nil
