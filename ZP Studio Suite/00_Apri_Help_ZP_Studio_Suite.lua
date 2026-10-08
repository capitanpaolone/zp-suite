-- @description ZP Studio Suite
-- @version 2.4.0
-- @author Paolo Balestri
-- @license GPL-3.0-or-later
-- @links
--   Lato Cardioide https://latocardioide.it/strumenti/
-- @about
--   Suite di script per REAPER per voiceover e doppiaggio: gobbo e copione,
--   gestione SRT, lettura accessibile con OSARA, preparazione del mixdown e
--   costruzione della catena audio ZP. Include il supporto screen reader su
--   Windows tramite la libreria NVDA Controller Client (LGPL 2.1, di NV Access).
--
--   Funziona su un REAPER pulito, senza estensioni. SWS, js_ReaScriptAPI e
--   OSARA non sono richiesti: aggiungono funzioni, e quando mancano la suite
--   usa da sola una strada alternativa. Il dettaglio e' in README.txt.
--
--   Dopo l'installazione apri dall'Action List "33 Benvenuto" (si apre anche da
--   solo la prima volta che usi uno strumento ZP): controlla toolbar ed effetti,
--   Cue Navigator del Carver, ZP Speech, SWS, js_ReaScriptAPI, OSARA, marker degli
--   item e interfaccia web, e per ognuno ha il pulsante che lo mette a posto.
-- @changelog
--   29 ZP Trascrizione: tendine Modello e Lingua (anche Altra... per qualsiasi codice, avviso se il
--     modello non conosce la lingua); la riga della tappa dice quanti file vanno trascritti e quanti
--     sono gia' fatti; Abbina con piu' item non apre il Finder e salta quelli gia' abbinati.
--   Trascrivi, Ritrascrivi e Traduci lavorano in background: chiudere la finestra non li ferma, il
--     titolo mostra l'avanzamento e alla fine arriva una notifica di macOS.
--   Traduci (facoltativo): traduce l'SRT con un agente AI col tuo login (Codex) e crea Nome.it.srt
--     con gli stessi tempi; nel Gobbo ogni traduzione e' un flusso in piu' che segue i tagli.
--     Serve ZP Speech aggiornato (bash speech-engine/install_macos.sh).
--   Toolbar ZP con icone nuove: il disegno resta uguale, il bordo diventa verde acqua quando lo
--     strumento e' aperto; un secondo clic sull'icona chiude la finestra. Si applica con 32 Installa.
--   SOLO Recorder: comandi REAPER anche in Mini; cambiando vista la finestra cresce verso il basso.
--   SOLO Web: timeline con regioni, marker e take; tocco per andarci, zoom con - + Tutto, rotella o pizzico.
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
--   [main] 14_Marker_da_Timeline_a_Item.lua
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
--   [main] 29_ZP_Trascrizione.lua
--   [main] 30_ZP_SRT.lua
--   [main] 31_SRT_da_Marker_Audio.lua
--   [main] 32_Installa_Toolbar_ZP.lua
--   [main] 33_Benvenuto_Controllo_Installazione.lua
--   [main] web/ZP_SOLO_Web_Motore.lua
--   [nomain] 04_worker_Crea_Marker_Item.lua
--   [nomain] 05_worker_Gestione_SRT.lua
--   [nomain] 28_Collega_Marker.lua
--   [nomain] ZP_UI.lua
--   [nomain] ZP_sincronizza_aggancio.lua
--   [nomain] ZP_cerca.lua
--   [nomain] lib_RythmoBand_Accessibile.lua
--   web/zp_solo.html
--   help/index.html
--   help/toolbar.html
--   help/solo_recorder.html
--   help/voice_cleaner.html
--   help/pannello_trascrizione.html
--   help/collega_marker.html
--   fxchains/ZP_Bus_VoiceChain.RfxChain
--   fxchains/ZP_MasterChain.RfxChain
--   presets/js-ZP Suite_ZP Voce_ZP BUS Chain_jsfx.ini
--   presets/js-ZP Suite_ZP Master_ZP Master Pro_jsfx.ini
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
--   [data] icons/ZP_tb_14_Marker_TL_Item.png > toolbar_icons/ZP_tb_14_Marker_TL_Item.png
--   [data] icons/ZP_tb_17_Gestore_Progetto.png > toolbar_icons/ZP_tb_17_Gestore_Progetto.png
--   [data] icons/ZP_tb_18_Project_Viewer.png > toolbar_icons/ZP_tb_18_Project_Viewer.png
--   [data] icons/ZP_tb_19_Report_Minuti.png > toolbar_icons/ZP_tb_19_Report_Minuti.png
--   [data] icons/ZP_tb_20_Importa_Cartelle.png > toolbar_icons/ZP_tb_20_Importa_Cartelle.png
--   [data] icons/ZP_tb_22_Voice_Cleaner.png > toolbar_icons/ZP_tb_22_Voice_Cleaner.png
--   [data] icons/ZP_tb_23_Chain_Builder.png > toolbar_icons/ZP_tb_23_Chain_Builder.png
--   [data] icons/ZP_tb_24_Probe_Guard.png > toolbar_icons/ZP_tb_24_Probe_Guard.png
--   [data] icons/ZP_tb_25_SOLO_Recorder.png > toolbar_icons/ZP_tb_25_SOLO_Recorder.png
--   [data] icons/ZP_tb_26_SRT_Tools.png > toolbar_icons/ZP_tb_26_SRT_Tools.png
--   [data] icons/ZP_tb_29_Pannello_Trascrizione.png > toolbar_icons/ZP_tb_29_Pannello_Trascrizione.png
--   [data] icons/ZP_tb_30_ZP_SRT.png > toolbar_icons/ZP_tb_30_ZP_SRT.png
--   [data] icons/ZP_tb_Importa_SRT_1_video.png > toolbar_icons/ZP_tb_Importa_SRT_1_video.png
--   [data] icons/ZP_tb_17_Regioni_Item.png > toolbar_icons/ZP_tb_17_Regioni_Item.png
--   [data] icons/ZP_tb_23_Catena_FX.png > toolbar_icons/ZP_tb_23_Catena_FX.png
--   [data] icons/200/ZP_tb_17_Regioni_Item.png > toolbar_icons/200/ZP_tb_17_Regioni_Item.png
--   [data] icons/200/ZP_tb_23_Catena_FX.png > toolbar_icons/200/ZP_tb_23_Catena_FX.png
--   [data] icons/ZP_tbB_00_Help.png > toolbar_icons/ZP_tbB_00_Help.png
--   [data] icons/ZP_tbB_02_Gobbo_Verticale.png > toolbar_icons/ZP_tbB_02_Gobbo_Verticale.png
--   [data] icons/ZP_tbB_03_Gobbo_Orizzontale.png > toolbar_icons/ZP_tbB_03_Gobbo_Orizzontale.png
--   [data] icons/ZP_tbB_04_Marker.png > toolbar_icons/ZP_tbB_04_Marker.png
--   [data] icons/ZP_tbB_07_Actor_Note.png > toolbar_icons/ZP_tbB_07_Actor_Note.png
--   [data] icons/ZP_tbB_17_Gestore_Progetto.png > toolbar_icons/ZP_tbB_17_Gestore_Progetto.png
--   [data] icons/ZP_tbB_18_Project_Viewer.png > toolbar_icons/ZP_tbB_18_Project_Viewer.png
--   [data] icons/ZP_tbB_19_Report_Minuti.png > toolbar_icons/ZP_tbB_19_Report_Minuti.png
--   [data] icons/ZP_tbB_20_Importa_Cartelle.png > toolbar_icons/ZP_tbB_20_Importa_Cartelle.png
--   [data] icons/ZP_tbB_22_Voice_Cleaner.png > toolbar_icons/ZP_tbB_22_Voice_Cleaner.png
--   [data] icons/ZP_tbB_23_Chain_Builder.png > toolbar_icons/ZP_tbB_23_Chain_Builder.png
--   [data] icons/ZP_tbB_24_Probe_Guard.png > toolbar_icons/ZP_tbB_24_Probe_Guard.png
--   [data] icons/ZP_tbB_29_Trascrizione.png > toolbar_icons/ZP_tbB_29_Trascrizione.png
--   [data] icons/ZP_tbB_30_ZP_SRT.png > toolbar_icons/ZP_tbB_30_ZP_SRT.png
--   [data] icons/ZP_tbB_Video.png > toolbar_icons/ZP_tbB_Video.png
--   [data] icons/ZP_tbB_Video_Sfondo.png > toolbar_icons/ZP_tbB_Video_Sfondo.png
--   [data] icons/200/ZP_tbB_00_Help.png > toolbar_icons/200/ZP_tbB_00_Help.png
--   [data] icons/200/ZP_tbB_02_Gobbo_Verticale.png > toolbar_icons/200/ZP_tbB_02_Gobbo_Verticale.png
--   [data] icons/200/ZP_tbB_03_Gobbo_Orizzontale.png > toolbar_icons/200/ZP_tbB_03_Gobbo_Orizzontale.png
--   [data] icons/200/ZP_tbB_04_Marker.png > toolbar_icons/200/ZP_tbB_04_Marker.png
--   [data] icons/200/ZP_tbB_07_Actor_Note.png > toolbar_icons/200/ZP_tbB_07_Actor_Note.png
--   [data] icons/200/ZP_tbB_17_Gestore_Progetto.png > toolbar_icons/200/ZP_tbB_17_Gestore_Progetto.png
--   [data] icons/200/ZP_tbB_18_Project_Viewer.png > toolbar_icons/200/ZP_tbB_18_Project_Viewer.png
--   [data] icons/200/ZP_tbB_19_Report_Minuti.png > toolbar_icons/200/ZP_tbB_19_Report_Minuti.png
--   [data] icons/200/ZP_tbB_20_Importa_Cartelle.png > toolbar_icons/200/ZP_tbB_20_Importa_Cartelle.png
--   [data] icons/200/ZP_tbB_22_Voice_Cleaner.png > toolbar_icons/200/ZP_tbB_22_Voice_Cleaner.png
--   [data] icons/200/ZP_tbB_23_Chain_Builder.png > toolbar_icons/200/ZP_tbB_23_Chain_Builder.png
--   [data] icons/200/ZP_tbB_24_Probe_Guard.png > toolbar_icons/200/ZP_tbB_24_Probe_Guard.png
--   [data] icons/200/ZP_tbB_29_Trascrizione.png > toolbar_icons/200/ZP_tbB_29_Trascrizione.png
--   [data] icons/200/ZP_tbB_30_ZP_SRT.png > toolbar_icons/200/ZP_tbB_30_ZP_SRT.png
--   [data] icons/200/ZP_tbB_Video.png > toolbar_icons/200/ZP_tbB_Video.png
--   [data] icons/200/ZP_tbB_Video_Sfondo.png > toolbar_icons/200/ZP_tbB_Video_Sfondo.png

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

-- La cartella dello script, qualunque sia il posto in cui e' installato.
-- ReaPack lo mette in Scripts/ZP Suite/ZP Studio Suite, il vecchio installer
-- in Scripts/ZP_Studio_Suite: chiederlo al file stesso funziona sempre.
local script_dir = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or ".")
local help_path = join(join(script_dir, "help"), "index.html")

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

-- Primo avvio: se il Benvenuto non si e' mai aperto, si apre adesso (accanto all'help).
if reaper.GetExtState("ZP_STUDIO_SUITE", "benvenuto_visto") == "" then
  local b = join(script_dir, "33_Benvenuto_Controllo_Installazione.lua")
  local fb = io.open(b, "r")
  if fb and reaper.AddRemoveReaScript then
    fb:close()
    local id = reaper.AddRemoveReaScript(true, 0, b, true)
    if id and id ~= 0 then reaper.Main_OnCommand(id, 0) end
  end
end
