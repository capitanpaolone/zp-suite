-- @description ZP Studio Suite
-- @version 1.1.0
-- @author Paolo Balestri
-- @license GPL-3.0-or-later
-- @links
--   Lato Cardioide https://latocardioide.it/strumenti/
-- @about
--   Suite di script per REAPER per voiceover e doppiaggio: gobbo e copione,
--   gestione SRT, lettura accessibile con OSARA, preparazione del mixdown e
--   costruzione della catena audio ZP. Include il supporto screen reader su
--   Windows tramite la libreria NVDA Controller Client (LGPL 2.1, di NV Access).
-- @changelog
--   Probe Guard: pannello di stato con spia, contatore riordini e apertura del log.
--   Pulizia: corretto un falso positivo che poteva togliere una voce della versione nuova.
--   Nuovo: 27 Pulisci installazione precedente, per chi arriva dal vecchio installer.
--   Toolbar pronta: quattordici pulsanti con le icone della suite.
--   Icone della toolbar consegnate nella cartella giusta di REAPER.
--   Prima pubblicazione su ReaPack.
--   SRT Tools rinumerato a 26, SOLO Recorder a 25.
-- @provides
--   [main] 01_Importa_Video_SRT.lua
--   [main] 02_Gobbo_Verticale.lua
--   [main] 03_Gobbo_Orizzontale.lua
--   [main] 04_Crea_Marker_Item.lua
--   [main] 05_Aggiorna_SRT_Video.lua
--   [main] 06_Importa_SRT_Reference.lua
--   [main] 07_Note_Personaggio.lua
--   [main] 08_Esporta_SRT.lua
--   [main] 09_OSARA_Battuta_Corrente.lua
--   [main] 10_OSARA_Battuta_Successiva.lua
--   [main] 11_OSARA_Battuta_Precedente.lua
--   [main] 12_OSARA_Lettura_Automatica.lua
--   [main] 13_Info_Item_SRT.lua
--   [main] 17_Crea_Regioni_Export_da_Item_Nominati.lua
--   [main] 18_Project_Viewer.lua
--   [main] 19_Report_Minuti_Voce.lua
--   [main] 20_Importa_Cartelle_Video_Mixdown.lua
--   [main] 22_Pulisci_Code_Silenzi_e_Separa_Item.lua
--   [main] 23_ZP_Chain_Builder.lua
--   [main] 24_ZP_Probe_Guard.lua
--   [main] 25_ZP_SOLO_Recorder.lua
--   [main] 26_SRT_Tools.lua
--   [main] 27_Pulisci_Installazione_Precedente.lua
--   [nomain] 04_worker_Crea_Marker_Item.lua
--   [nomain] 05_worker_Gestione_SRT.lua
--   [nomain] ZP_UI.lua
--   [nomain] lib_RythmoBand_Accessibile.lua
--   help/index.html
--   help/voice_cleaner.html
--   tools/srt_tools.html
--   toolbar/ZP_StudioSuite.ReaperMenu
--   ZP_NVDA_Speech.py
--   nvdaControllerClient64.dll
--   README.txt
--   VideoProcessor_Project_Timecode_Overlay.txt
--   RB Voice Track.RTrackTemplate
--   SRT Track.RTrackTemplate
--   [data] icons/ZP_tb_00_Help.png > toolbar_icons/ZP_tb_00_Help.png
--   [data] icons/ZP_tb_01_Import_Video_SRT.png > toolbar_icons/ZP_tb_01_Import_Video_SRT.png
--   [data] icons/ZP_tb_02_Gobbo_Verticale.png > toolbar_icons/ZP_tb_02_Gobbo_Verticale.png
--   [data] icons/ZP_tb_03_Gobbo_Orizzontale.png > toolbar_icons/ZP_tb_03_Gobbo_Orizzontale.png
--   [data] icons/ZP_tb_04_Marker_Item.png > toolbar_icons/ZP_tb_04_Marker_Item.png
--   [data] icons/ZP_tb_05_Gestione_SRT.png > toolbar_icons/ZP_tb_05_Gestione_SRT.png
--   [data] icons/ZP_tb_06_Import_SRT_Reference.png > toolbar_icons/ZP_tb_06_Import_SRT_Reference.png
--   [data] icons/ZP_tb_07_Actor_Note.png > toolbar_icons/ZP_tb_07_Actor_Note.png
--   [data] icons/ZP_tb_08_Export_SRT.png > toolbar_icons/ZP_tb_08_Export_SRT.png
--   [data] icons/ZP_tb_09_OSARA_Corrente.png > toolbar_icons/ZP_tb_09_OSARA_Corrente.png
--   [data] icons/ZP_tb_10_OSARA_Successiva.png > toolbar_icons/ZP_tb_10_OSARA_Successiva.png
--   [data] icons/ZP_tb_11_OSARA_Precedente.png > toolbar_icons/ZP_tb_11_OSARA_Precedente.png
--   [data] icons/ZP_tb_12_OSARA_Auto.png > toolbar_icons/ZP_tb_12_OSARA_Auto.png
--   [data] icons/ZP_tb_13_Info_Item_SRT.png > toolbar_icons/ZP_tb_13_Info_Item_SRT.png
--   [data] icons/ZP_tb_17_Gestore_Progetto.png > toolbar_icons/ZP_tb_17_Gestore_Progetto.png
--   [data] icons/ZP_tb_18_Project_Viewer.png > toolbar_icons/ZP_tb_18_Project_Viewer.png
--   [data] icons/ZP_tb_19_Report_Minuti.png > toolbar_icons/ZP_tb_19_Report_Minuti.png
--   [data] icons/ZP_tb_20_Importa_Cartelle.png > toolbar_icons/ZP_tb_20_Importa_Cartelle.png
--   [data] icons/ZP_tb_22_Voice_Cleaner.png > toolbar_icons/ZP_tb_22_Voice_Cleaner.png
--   [data] icons/ZP_tb_23_Chain_Builder.png > toolbar_icons/ZP_tb_23_Chain_Builder.png
--   [data] icons/ZP_tb_24_Probe_Guard.png > toolbar_icons/ZP_tb_24_Probe_Guard.png
--   [data] icons/ZP_tb_25_SOLO_Recorder.png > toolbar_icons/ZP_tb_25_SOLO_Recorder.png
--   [data] icons/ZP_tb_26_SRT_Tools.png > toolbar_icons/ZP_tb_26_SRT_Tools.png

--[[
ZP Studio Suite for REAPER
00_Apri_Help_ZP_Studio_Suite.lua
Opens the local help file in the default browser.
]]

local function join(a, b)
  local sep = package.config:sub(1,1)
  if a:sub(-1) == sep then return a .. b end
  return a .. sep .. b
end

local resource = reaper.GetResourcePath()
local help_path = join(join(join(resource, "Scripts"), "ZP_Studio_Suite"), "help")
help_path = join(help_path, "index.html")

local f = io.open(help_path, "r")
if not f then
  reaper.ShowMessageBox("Help non trovato:\n\n" .. help_path, "ZP Studio Suite", 0)
  return
end
f:close()

local osname = reaper.GetOS()
local quoted = string.format("%q", help_path)
if osname:match("OSX") or osname:match("macOS") then
  os.execute("open " .. quoted .. " &")
elseif osname:match("Win") then
  os.execute('start "" ' .. quoted)
else
  os.execute("xdg-open " .. quoted .. " >/dev/null 2>&1 &")
end
