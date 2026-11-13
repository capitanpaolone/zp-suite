-- @noindex
-- Provenienza ZP:
--   Proprietà: ZP Remote / azione standalone di importazione consegna.
--   Origine: progetto ZP Remote (ZP_Solo_Recorder_WebRemote/reaper), copiato il 2026-11-13; preparazione Suite 2.6.7.
--   Versione interna: non dichiarata separatamente; incluso nel pacchetto.

-- Azione standalone; la finestra ZP Remote usa lo stesso modulo senza messaggi modali.
local script_path=debug.getinfo(1,"S").source:sub(2)
local script_dir=script_path:match("^(.*[/\\])") or ""
local importer=dofile(script_dir.."zp_remote_importer.lua")
local ok,result=importer.run({
  confirm=function(message) return reaper.MB(message,"ZP Remote — conferma import",1)==1 end,
  onProgress=function(message) reaper.ShowConsoleMsg("ZP Remote: "..tostring(message).."\n") end
})
if not ok then
  reaper.MB(tostring(result),"ZP Remote — import bloccato",0)
elseif result then
  reaper.MB(result.message,"ZP Remote",0)
end
