# ZP Suite — memoria anti-regressione

Regole nate da errori veri. Prima di ogni commit: `bash gobbo_ricerca_battuta/test/run_all.sh`
(sintassi Lua, tag ReaPack, JSFX, test). Se una regola cambia, aggiornala qui e annotalo in MEMORIA.md.

## Pubblicazione e GitHub
- Ogni `.lua`/`.jsfx` nuovo nei pacchetti deve avere `@version`, `@noindex` o stare nel `@provides`
  di un pacchetto. Senza, il controllo GitHub "check" (`reapack-index --check`) fallisce
  (successo il 2026-10-04: 28_Collega_Marker e le bozze). Gli helper hanno `@noindex`.
- `gobbo_ricerca_battuta`, `ZP Lab`, `speech-engine` sono esclusi in `.reapack-index.conf`: non toglierli.
- Un file nuovo distribuito (fxchains, presets, help, icone) va aggiunto al `@provides` del 00
  e il percorso deve esistere (run_all lo controlla).
- Mai push su master, tag, bump di versione o ReaPack senza richiesta esplicita di Paolo.

## Help
- Ogni modifica visibile a Paolo aggiorna, nello stesso commit, l'help (`help/index.html` e la pagina
  dedicata: solo_recorder, pannello_trascrizione, toolbar...) e le spiegazioni dentro lo script
  (suggerimenti, guida ?). Prima del commit cerca nell'help le frasi del comportamento vecchio.
- Le copie installate dell'help devono restare uguali al repo.

## Installazione su questo Mac
- Prima di sovrascrivere una copia in `REAPER/Scripts/ZP Suite/...`, verifica che sia uguale
  a `git show HEAD:<file>`; se e' diversa, fermati e chiedi. La 00 installata e' quella pubblicata.
- Mai toccare `reaper-kb.ini` / `reaper-menu.ini` / `reaper.ini` con REAPER aperto (`pgrep -x REAPER`),
  sempre con backup.
- Backup in `gobbo_ricerca_battuta/backup/` prima di modifiche grosse; ogni cambio in MEMORIA.md.

## REAPER (cose verificate, non intuitive)
- 40850 = "Item: Show notes for items" (NON le note del progetto). Le note del progetto non hanno
  un'azione nativa: con SWS `_S&M_SHOWNOTESHELP`, senza SWS 40021 Project settings.
- `TrackFX_AddByName` non carica `.RfxChain`: blocco FXCHAIN in una traccia temporanea + `TrackFX_CopyToTrack`.
- I preset JSFX sono legati al PERCORSO del JSFX (`presets/js-<cartella>_<file>_jsfx.ini`):
  dopo il passaggio a ReaPack i preset del vecchio installer non valgono piu'. Li distribuisce la 32.
- Il glue SI porta dietro i take marker (con tempi da rileggere): per rileggere usare Ritrascrivi della 29.
- I take marker stanno nel progetto, non nel WAV. Tempo timeline = pos + (src - startoffs) / playrate.
- Un solo `gfx` per script: per aprire un altro strumento senza chiudere la finestra lancialo come
  azione (`Main_OnCommand` con l'ID da reaper-kb.ini), e passa i parametri via ExtState, non `_G`.
- `JS_Dialog_BrowseForFolder` restituisce 1/0/-1: in Lua 0 e' VERO, controllare `rv == 1`.
- macOS: `open "file#ancora"` non funziona; usare l'URL file:// codificato (`UI.help_url`).
- Messaggi: niente `ShowConsoleMsg` salvo errori gravi; preferire finestre che restano aperte
  e si chiudono a mano ai `MB` bloccanti; OSARA (`osara_outputMessage`) per l'accessibilita'.

## JSFX / EEL2
- Niente notazione scientifica (`1e-30`): calcolare la costante in @init.
- Assegnazioni dentro `?:` sempre tra parentesi. `slider_show` vuole la maschera `2^(n-1)`.

## Marker e testi
- Marker di servizio, mai testo, mai copiati/cancellati dal 14, mai nel gobbo o nell'SRT:
  nome che comincia con `#` (segnaposto) o `!` (azioni), marker del SOLO
  `SOLO_MARK_/OK_/BAD_/ALT_/NOISE_/INSERT_` + numero, senza nome. Regola in 14, aggancio e 31.
- L'SRT di Trascrivi sta accanto al WAV apposta (lo cerca Abbina). Gli SRT di consegna (08, 31)
  vanno nella cartella scelta, mai tra i media.

## SOLO Recorder
- Lucchetto REC spento di default (chiave ExtState `rec_lock2`). Nascondi 5s / Parcheggia tolti.
- Il SOLO richiede `ZP_UI.lua` con `draw_knob`: ZP_UI e SOLO si aggiornano insieme.
- Dopo modifiche alla pulsantiera: simulazione fuori REAPER (nessun comando fuori finestra o sovrapposto).

## Riferimenti per confronti (anti-regressione)
- ZP Stagekeeper Dialogue Director 2.3.1 (ultima pubblicata prima della 2.5.0):
  `gobbo_ricerca_battuta/backup/ZP Stagekeeper Dialogue Director 2.3.1.jsfx`. Se la 2.5.x
  peggiora qualcosa, confrontare con questa.
