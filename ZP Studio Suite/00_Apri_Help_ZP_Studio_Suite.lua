-- @description ZP Studio Suite
-- @version 2.6.7
-- @author Paolo Balestri
-- @license GPL-3.0-or-later
-- @links
--   Lato Cardioide https://latocardioide.it/strumenti/
-- @about
--   EN — A REAPER toolkit for voiceover and dubbing: teleprompters, SRT handling,
--   accessible reading, project and mixdown preparation, and ZP audio tools. Works
--   with a clean REAPER install. On Windows, Render & Copy requires js_ReaScriptAPI
--   for automatic copying and Sync now. SWS and OSARA are optional.
--   Open 33 Welcome and choose English or Italiano under Suite language. The
--   preference is saved independently from REAPER's language. Guides are included
--   in both languages. Windows screen-reader support uses NVDA Controller Client
--   (LGPL 2.1, NV Access). See README.md for installation and component details.
--
--   IT — Strumenti REAPER per voiceover e doppiaggio: gobbi, gestione SRT,
--   lettura accessibile, preparazione del progetto e del mixdown, strumenti audio ZP.
--   Funziona anche su un REAPER pulito. Su Windows, per la copia automatica e
--   Sincronizza ora in Render & Copy serve js_ReaScriptAPI. SWS e OSARA sono facoltativi.
--   Apri 33 Benvenuto e scegli Italiano o English alla voce Lingua della Suite.
--   La preferenza viene salvata ed è indipendente dalla lingua di REAPER. Le guide
--   sono disponibili in entrambe le lingue. Il supporto screen reader Windows usa
--   NVDA Controller Client (LGPL 2.1, NV Access). Dettagli in README.it.md.
-- @changelog
--   2.6.7 (in preparation; not released)
--   EN — Local REAPER reference updates: safer project-region selection, Voice Minutes 1.0.6, ZP Remote import/export updates, Harmonic Space Carver 2.6.10 and Cue Navigator 1.14. These changes still require release collation and checks.
--   IT — Aggiornamenti dalla REAPER locale: selezione più sicura delle regioni, Report Minuti 1.0.6, aggiornamenti ZP Remote, Harmonic Space Carver 2.6.10 e Cue Navigator 1.14. Da consolidare e collaudare prima della pubblicazione.
--   EN
--   Render & Copy supports automatic copying and Sync now on Windows (js_ReaScriptAPI) and Linux (find and stat).
--   Solo Recorder guide now explains that ZP Remote packages are intended for Dubbertools and distinguishes package delivery from the Web Remote recording controls.
--   Added direct synchronization of the native REAPER pre-roll toolbar indicator when toggled from ZP SOLO Recorder or its web remote.
--   Gobbo speaker colors can be applied from selected voice items and their paired Character Notes items.
--   Italian REAPER language pack keeps the top-level Help label for native macOS menu search.
--   Added Render & Copy, the ZP Remote REAPER tools for Dubbertools, and a Dubbertools link in SOLO Web.
--   Voice Minutes Report exports CSV, and ZP Colors supports items, tracks, markers and regions.
--   IT
--   Render & Copy supporta la copia automatica e Sincronizza ora anche su Windows (js_ReaScriptAPI) e Linux (find e stat).
--   La guida del Solo Recorder spiega che i pacchetti ZP Remote sono destinati a Dubbertools e distingue la consegna pacchetti dal telecomando web di registrazione.
--   Il PRE di ZP SOLO Recorder e del telecomando web aggiorna anche la spia del pre-roll nella toolbar nativa di REAPER.
--   I colori speaker del Gobbo si possono applicare selezionando item voce o note personaggio associate.
--   Il language pack italiano mantiene la voce principale Help per la ricerca nativa nei menu di macOS.
--   Aggiunti Render & Copy, lo strumento REAPER di ZP Remote per Dubbertools e il link in SOLO Web.
--   Report Minuti Voce esporta in CSV. ZP Colori gestisce item, tracce, marker e regioni.
-- @provides
--   [langpack] /REAPER_Italiano/Italiano (ZP).ReaperLangPack > Italiano (ZP).ReaperLangPack
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
--   [main] 34_ZP_Set_Comandi.lua
--   [main] 35_ZP_Colori.lua
--   [main] render_copy/ZP_RenderCopy.lua
--   render_copy/assets/zp_render_copy.png
--   [main] remote/ZP_Remote_Crea_Pacchetto.lua
--   [nomain] remote/zp_remote_character_ids.lua
--   [nomain] remote/zp_remote_json.lua
--   [nomain] remote/zp_remote_importer.lua
--   [nomain] remote/zp_remote_import_logic.lua
--   remote/zp_remote_esporta.py
--   remote/zp_remote_identity.py
--   remote/zp_remote_preflight.py
--   remote/assets/zp_remote_pacchetto.png
--   [data] icons/ZP_RenderCopy.png > toolbar_icons/ZP_RenderCopy.png
--   [data] icons/150/ZP_RenderCopy.png > toolbar_icons/150/ZP_RenderCopy.png
--   [data] icons/200/ZP_RenderCopy.png > toolbar_icons/200/ZP_RenderCopy.png
--   [data] icons/ZP_Remote_Crea_Pacchetto.png > toolbar_icons/ZP_Remote_Crea_Pacchetto.png
--   [data] icons/200/ZP_Remote_Crea_Pacchetto.png > toolbar_icons/200/ZP_Remote_Crea_Pacchetto.png
--   [main] web/ZP_SOLO_Web_Motore.lua
--   [main] colori/ZP_Colori_01_Verde_lime.lua
--   [main] colori/ZP_Colori_02_Crema.lua
--   [main] colori/ZP_Colori_03_Arancio.lua
--   [main] colori/ZP_Colori_04_Rosa.lua
--   [main] colori/ZP_Colori_05_Lilla.lua
--   [main] colori/ZP_Colori_06_Viola.lua
--   [main] colori/ZP_Colori_07_Blu.lua
--   [main] colori/ZP_Colori_08_Azzurro.lua
--   [main] colori/ZP_Colori_09_Acqua.lua
--   [main] colori/ZP_Colori_10_Verde.lua
--   [main] colori/ZP_Colori_11_Giallo.lua
--   [main] colori/ZP_Colori_12_Salmone.lua
--   [main] colori/ZP_Colori_13_Glicine.lua
--   [main] colori/ZP_Colori_14_Celeste.lua
--   [main] colori/ZP_Colori_15_Turchese.lua
--   [main] colori/ZP_Colori_16_Salvia.lua
--   [main] colori/ZP_Colori_17_Bianco.lua
--   [main] colori/ZP_Colori_18_Nero.lua
--   [main] colori/ZP_Colori_19_Grigio.lua
--   [main] colori/ZP_Colori_20_Rosso.lua
--   [main] colori/ZP_Colori_Modo_Item.lua
--   [main] colori/ZP_Colori_Modo_Traccia.lua
--   [main] colori/ZP_Colori_Modo_Tutto.lua
--   [main] colori/ZP_Colori_Modo_Marker.lua
--   [main] colori/ZP_Colori_Modo_Regione.lua
--   [main] colori/ZP_Colori_Auto.lua
--   [main] colori/ZP_Colori_Togli.lua
--   [nomain] 04_worker_Crea_Marker_Item.lua
--   [nomain] 05_worker_Gestione_SRT.lua
--   [nomain] 28_Collega_Marker.lua
--   [nomain] ZP_UI.lua
--   [nomain] ZP_sincronizza_aggancio.lua
--   [nomain] ZP_cerca.lua
--   [nomain] ZP_Colori.lua
--   [nomain] ZP_Agenti.lua
--   [nomain] ZP_Lingua.lua
--   [nomain] lib_RythmoBand_Accessibile.lua
--   web/zp_solo.html
--   lang/en.txt
--   img/lato_cardioide.png
--   help/index.html
--   help/toolbar.html
--   help/solo_recorder.html
--   help/voice_cleaner.html
--   help/pannello_trascrizione.html
--   help/collega_marker.html
--   help/en/index.html
--   help/en/toolbar.html
--   help/en/solo_recorder.html
--   help/en/voice_cleaner.html
--   help/en/pannello_trascrizione.html
--   help/en/collega_marker.html
--   fxchains/ZP_Bus_VoiceChain.RfxChain
--   fxchains/ZP_MasterChain.RfxChain
--   presets/js-ZP Suite_ZP Voce_ZP BUS Chain_jsfx.ini
--   presets/js-ZP Suite_ZP Master_ZP Master Pro_jsfx.ini
--   tools/srt_tools.html
--   tools/LICENSE-SheetJS-Apache-2.0.txt
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
--   [data] icons/ZP_tbC_01.png > toolbar_icons/ZP_tbC_01.png
--   [data] icons/ZP_tbC_02.png > toolbar_icons/ZP_tbC_02.png
--   [data] icons/ZP_tbC_03.png > toolbar_icons/ZP_tbC_03.png
--   [data] icons/ZP_tbC_04.png > toolbar_icons/ZP_tbC_04.png
--   [data] icons/ZP_tbC_05.png > toolbar_icons/ZP_tbC_05.png
--   [data] icons/ZP_tbC_06.png > toolbar_icons/ZP_tbC_06.png
--   [data] icons/ZP_tbC_07.png > toolbar_icons/ZP_tbC_07.png
--   [data] icons/ZP_tbC_08.png > toolbar_icons/ZP_tbC_08.png
--   [data] icons/ZP_tbC_09.png > toolbar_icons/ZP_tbC_09.png
--   [data] icons/ZP_tbC_10.png > toolbar_icons/ZP_tbC_10.png
--   [data] icons/ZP_tbC_11.png > toolbar_icons/ZP_tbC_11.png
--   [data] icons/ZP_tbC_12.png > toolbar_icons/ZP_tbC_12.png
--   [data] icons/ZP_tbC_13.png > toolbar_icons/ZP_tbC_13.png
--   [data] icons/ZP_tbC_14.png > toolbar_icons/ZP_tbC_14.png
--   [data] icons/ZP_tbC_15.png > toolbar_icons/ZP_tbC_15.png
--   [data] icons/ZP_tbC_16.png > toolbar_icons/ZP_tbC_16.png
--   [data] icons/ZP_tbC_17.png > toolbar_icons/ZP_tbC_17.png
--   [data] icons/ZP_tbC_18.png > toolbar_icons/ZP_tbC_18.png
--   [data] icons/ZP_tbC_19.png > toolbar_icons/ZP_tbC_19.png
--   [data] icons/ZP_tbC_20.png > toolbar_icons/ZP_tbC_20.png
--   [data] icons/ZP_tbC_Item.png > toolbar_icons/ZP_tbC_Item.png
--   [data] icons/ZP_tbC_Togli.png > toolbar_icons/ZP_tbC_Togli.png
--   [data] icons/ZP_tbC_Traccia.png > toolbar_icons/ZP_tbC_Traccia.png
--   [data] icons/ZP_tbC_Tutto.png > toolbar_icons/ZP_tbC_Tutto.png
--   [data] icons/ZP_tbC_Marker.png > toolbar_icons/ZP_tbC_Marker.png
--   [data] icons/ZP_tbC_Regione.png > toolbar_icons/ZP_tbC_Regione.png
--   [data] icons/ZP_tbC_Auto.png > toolbar_icons/ZP_tbC_Auto.png
--   [data] icons/200/ZP_tbC_Marker.png > toolbar_icons/200/ZP_tbC_Marker.png
--   [data] icons/200/ZP_tbC_Regione.png > toolbar_icons/200/ZP_tbC_Regione.png
--   [data] icons/200/ZP_tbC_Auto.png > toolbar_icons/200/ZP_tbC_Auto.png
--   [data] icons/200/ZP_tbC_01.png > toolbar_icons/200/ZP_tbC_01.png
--   [data] icons/200/ZP_tbC_02.png > toolbar_icons/200/ZP_tbC_02.png
--   [data] icons/200/ZP_tbC_03.png > toolbar_icons/200/ZP_tbC_03.png
--   [data] icons/200/ZP_tbC_04.png > toolbar_icons/200/ZP_tbC_04.png
--   [data] icons/200/ZP_tbC_05.png > toolbar_icons/200/ZP_tbC_05.png
--   [data] icons/200/ZP_tbC_06.png > toolbar_icons/200/ZP_tbC_06.png
--   [data] icons/200/ZP_tbC_07.png > toolbar_icons/200/ZP_tbC_07.png
--   [data] icons/200/ZP_tbC_08.png > toolbar_icons/200/ZP_tbC_08.png
--   [data] icons/200/ZP_tbC_09.png > toolbar_icons/200/ZP_tbC_09.png
--   [data] icons/200/ZP_tbC_10.png > toolbar_icons/200/ZP_tbC_10.png
--   [data] icons/200/ZP_tbC_11.png > toolbar_icons/200/ZP_tbC_11.png
--   [data] icons/200/ZP_tbC_12.png > toolbar_icons/200/ZP_tbC_12.png
--   [data] icons/200/ZP_tbC_13.png > toolbar_icons/200/ZP_tbC_13.png
--   [data] icons/200/ZP_tbC_14.png > toolbar_icons/200/ZP_tbC_14.png
--   [data] icons/200/ZP_tbC_15.png > toolbar_icons/200/ZP_tbC_15.png
--   [data] icons/200/ZP_tbC_16.png > toolbar_icons/200/ZP_tbC_16.png
--   [data] icons/200/ZP_tbC_17.png > toolbar_icons/200/ZP_tbC_17.png
--   [data] icons/200/ZP_tbC_18.png > toolbar_icons/200/ZP_tbC_18.png
--   [data] icons/200/ZP_tbC_19.png > toolbar_icons/200/ZP_tbC_19.png
--   [data] icons/200/ZP_tbC_20.png > toolbar_icons/200/ZP_tbC_20.png
--   [data] icons/200/ZP_tbC_Item.png > toolbar_icons/200/ZP_tbC_Item.png
--   [data] icons/200/ZP_tbC_Togli.png > toolbar_icons/200/ZP_tbC_Togli.png
--   [data] icons/200/ZP_tbC_Traccia.png > toolbar_icons/200/ZP_tbC_Traccia.png
--   [data] icons/200/ZP_tbC_Tutto.png > toolbar_icons/200/ZP_tbC_Tutto.png
--   [data] icons/ZP_tbB_34_Set_Comandi.png > toolbar_icons/ZP_tbB_34_Set_Comandi.png
--   [data] icons/200/ZP_tbB_34_Set_Comandi.png > toolbar_icons/200/ZP_tbB_34_Set_Comandi.png
--   [data] icons/ZP_tbB_35_Colori.png > toolbar_icons/ZP_tbB_35_Colori.png
--   [data] icons/200/ZP_tbB_35_Colori.png > toolbar_icons/200/ZP_tbB_35_Colori.png

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

-- Rispetta la lingua persistente della Suite anche quando si apre l'azione 00
-- direttamente dalla Action List, senza passare dai pulsanti ? di ZP_UI.
local lang = "it"
local lingua_file = join(script_dir, "ZP_Lingua.lua")
local lingua_ok, lingua = pcall(dofile, lingua_file)
if lingua_ok and type(lingua) == "table" and type(lingua.get_lingua) == "function" then
  local lang_ok, saved_lang = pcall(lingua.get_lingua)
  if lang_ok and saved_lang == "en" then lang = "en" end
end
if lang ~= "it" then
  local localized_path = join(join(join(script_dir, "help"), lang), "index.html")
  local localized_file = io.open(localized_path, "r")
  if localized_file then
    localized_file:close()
    help_path = localized_path
  end
end

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
