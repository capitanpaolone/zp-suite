# 33 Benvenuto — controllo installazione

Stato: realizzato il 2026-10-06 (proposta accettata da Paolo). Non ancora pubblicato.

## Perche'
ReaPack installa i file e non mostra niente: un utente nuovo non sa che deve lanciare il 32, avviare il
Cue Navigator a ogni apertura di REAPER, installare ZP Speech, le estensioni facoltative, l'interfaccia web.

## Come funziona
- `ZP Studio Suite/33_Benvenuto_Controllo_Installazione.lua` ([main] nel @provides del 00): una riga per
  pezzo con spia (verde pronto, rossa da fare, grigio-azzurra facoltativo assente, grigia non serve) e i
  pulsanti che lo sistemano. Ricontrolla ogni secondo.
- Primo avvio: ExtState persistente `ZP_STUDIO_SUITE/benvenuto_visto`. Se e' vuota, la prima libreria
  ZP_UI caricata da uno strumento (o il 00) apre il 33 (AddRemoveReaScript + Main_OnCommand) e la segna.
  Il 33 la segna PRIMA di caricare ZP_UI (altrimenti si aprirebbe due volte).
- Pezzi: toolbar ed effetti (MenuSets/ZP_StudioSuite.ReaperMenu + catene in FXChains; importata se
  reaper-menu.ini contiene `ZP_tb_`) -> Installa = lancia il 32; Cue Navigator (solo se il Carver c'e':
  file in Scripts/ZP Suite/ZP Voce o Scripts/ZP Suite) acceso = ExtState ZP_HSC/owner, all'avvio = blocco
  segnato in Scripts/__startup.lua oppure azione di avvio SWS (S&M.ini GlobalStartupAction -> kb.ini) ->
  Avvia ora / A ogni apertura (scrive solo il blocco tra ZP_BENVENUTO_HSC_INIZIO e _FINE); ZP Speech (Mac,
  CLI in ~/Library/Application Support/ZP/runtimes/speech) -> link a speech-engine su GitHub; SWS
  (CF_GetSWSVersion), js_ReaScriptAPI (JS_ReaScriptAPI_Version, apre ReaPack Browse), OSARA
  (osara_outputMessage), interfaccia web (csurf HTTP in reaper.ini, apre Preferenze 40016).
- Logica pura testata in `gobbo_ricerca_battuta/test/test_benvenuto.lua` (17 casi).
