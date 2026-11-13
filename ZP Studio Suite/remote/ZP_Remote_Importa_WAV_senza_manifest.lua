-- @noindex
-- Provenienza ZP:
--   Proprietà: ZP Remote / azione standalone di recupero WAV senza manifest.
--   Origine: progetto ZP Remote (ZP_Solo_Recorder_WebRemote/reaper), copiato il 2026-11-13; preparazione Suite 2.6.7.
--   Versione interna: non dichiarata separatamente; incluso nel pacchetto.

-- Azione standalone: inserisce WAV senza consegna.json in nuove tracce, al cursore di edit. Non verifica nulla: il tecnico controlla.
local script_path=debug.getinfo(1,"S").source:sub(2)
local script_dir=script_path:match("^(.*[/\\])") or ""
local recupero=dofile(script_dir.."zp_remote_recupero.lua")
local ok,result=recupero.run({
  confirm=function(message) return reaper.MB(message,"ZP Remote — recupero WAV",1)==1 end,
  onProgress=function(message) reaper.ShowConsoleMsg("ZP Remote: "..tostring(message).."\n") end
})
if not ok then
  reaper.MB(tostring(result),"ZP Remote — recupero bloccato",0)
elseif result then
  reaper.MB(result.message,"ZP Remote — recupero WAV",0)
end
