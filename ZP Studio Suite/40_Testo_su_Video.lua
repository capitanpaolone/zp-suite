-- @noindex
-- ZP Studio Suite: TESTO SU VIDEO (modulo; lo usano 40_Testo_su_Video e i due Gobbo) (copione Excel senza timecode)
-- Legge un .xlsx a blocchi (colonna "File name" + una colonna di testo per lingua, senza tempi) e crea
-- UN item di testo per ogni video/audio gia' in timeline: stessa posizione e stessa durata del media,
-- sulla traccia "Rythmo Band Testi" del Gobbo. Il testo e' una battuta per riga.
-- Abbinamento: nome del blocco = nome dell'item (senza estensione, senza distinzione di maiuscole).
-- Nessun abbinamento "per somiglianza": un nome che e' prefisso di un altro (es. "Clip01" e "Clip01_alt") resta una cosa distinta.
-- Se ci sono item selezionati lavora solo su quelli, altrimenti su tutti. Rilanciandolo, gli item di testo
-- creati prima dallo stesso nome vengono sostituiti (niente doppioni). Un solo passo di Undo.

local SCRIPT_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "")
local VIDEO = dofile(SCRIPT_DIR .. "ZP_Testo_su_Video.lua")

local ok, path = reaper.GetUserFileNameForRead("", "ZP - Copione Excel a blocchi (senza timecode)", ".xlsx")
if not ok or path == "" then return end
if not path:lower():match("%.xlsx$") then
  reaper.ShowMessageBox("Serve un file Excel .xlsx.", "ZP Studio Suite - Testo su video", 0)
  return
end
VIDEO.run(path)
