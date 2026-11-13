-- @noindex
-- Provenienza ZP:
--   Proprietà: ZP Remote / azione standalone per l’ID di progetto.
--   Origine: progetto ZP Remote (ZP_Solo_Recorder_WebRemote/reaper), copiato il 2026-11-13; preparazione Suite 2.6.7.
--   Versione interna: non dichiarata separatamente; incluso nel pacchetto.

-- Assegna una sola volta l'identità ZP Remote al progetto REAPER aperto.
-- L'ID è salvato dentro il .RPP e resta valido dopo rinomina o spostamento.
local r = reaper
local _, path = r.EnumProjects(-1, "")
if not path or path == "" then
  r.MB("Salva il progetto REAPER prima di assegnare l'ID ZP Remote.", "ZP Remote", 0)
  return
end

local found, existing = r.GetProjExtState(0, "ZP_REMOTE", "PROJECT_ID")
if found > 0 and existing ~= "" then
  r.MB("Questo progetto ha già l'ID ZP Remote:\n" .. existing .. "\n\nNon viene modificato.", "ZP Remote", 0)
  return
end

local ok, supplied = r.GetUserInputs(
  "Identità ZP Remote", 1,
  "ID di un pacchetto già inviato (vuoto = nuovo ID):,extrawidth=160",
  ""
)
if not ok then return end
local id = supplied:match("^%s*(.-)%s*$")
if id == "" then
  id = r.genGuid("")
else
  local compact = id:match("^%{(%x+)%}$")
  local standard = id:match("^%{%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x%}$")
  if not (compact and #compact == 32) and not standard then
    r.MB("ID non valido. Copia il campo project.guid dal manifest del pacchetto esistente.", "ZP Remote", 0)
    return
  end
end

id = id:upper()
local confirm = r.MB(
  "Salvare questo ID nel progetto REAPER?\n\n" .. id ..
  "\n\nSe il lavoro è già stato inviato, usa il suo ID esistente: un ID nuovo non corrisponde alle vecchie consegne.",
  "ZP Remote", 4
)
if confirm ~= 6 then return end

r.SetProjExtState(0, "ZP_REMOTE", "PROJECT_ID", id)
r.MarkProjectDirty(0)
r.Main_SaveProject(0, false)
local saved, check = r.GetProjExtState(0, "ZP_REMOTE", "PROJECT_ID")
if saved <= 0 or check ~= id then
  r.MB("REAPER non ha confermato il salvataggio dell'ID. Non esportare ancora.", "ZP Remote", 0)
  return
end
r.MB("ID ZP Remote salvato nel progetto:\n" .. id, "ZP Remote", 0)
