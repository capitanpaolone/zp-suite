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

## Harmonic Space Carver: cue e helper
- I cue esistono solo per il Carver: un #HSC cancellato o aggiunto fuori dal Carver si ripristina/toglie
  (decisione di Paolo). Al primo giro su un progetto comanda il Carver: l'helper non cancella mai cue.
- Il progetto si riconosce da puntatore + file (`EnumProjects(-1)`): la stessa scheda puo' contenere un altro progetto.
- Le richieste in ExtState si cancellano dopo l'uso (un helper riavviato non deve rieseguirle).
- Un solo helper: ExtState ZP_HSC/owner, l'ultimo avviato vince.
- Lo stato da sistemare al caricamento (preascolto, migrazioni) va in @serialize + primo @block, non in @init:
  REAPER ricarica i parametri dopo @init.
- Installazione su questo Mac: veri in `Scripts/ZP Suite/ZP Voce/` (cartella di ReaPack); in `Scripts/ZP Suite/`
  solo tre rimandi (helper all'avvio SWS, Mostra tracce voce, Riallinea su Ctrl+\). Non sovrascriverli con i veri.

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

- Ogni array in memoria (`x[i]`) deve avere un indirizzo base assegnato in @init, in una zona libera:
  una variabile mai assegnata vale 0 e scrive sopra la memoria del DSP (Carver: cue sugli stati SVF).
  Per trovare gli array cerca anche i nomi con maiuscole (es. `buf_main_L[`): mappa TUTTA la memoria
  usata prima di scegliere la base (Carver 2.5: 0-15 SVF, 16-6159 oscilloscopio, 8192 cue,
  8320 backup cue, 8400-8431 tabella Partenza, 8440-8442 stato fonti SC, 16384-49151 lookahead).
- gmem del Carver: 72 celle per FX (`base+0..71`), mai oltre `+71` (sarebbe l'FX successivo). `+71` = routing SC (helper).
- Un JSFX non vede pin mapping, invii o folder: solo `num_ch`. Quello che dipende dal routing lo legge l'helper.
  I comandi da tasti/helper passano dalla casella comune 3800-3899 (lo Shared Bus usa fino a ~606).
- GUI JSFX: prima di aggiungere un pannello, mappa le coordinate di TUTTO cio' che e' gia' disegnato
  in quella zona (anche etichette e valori dei knob, che sporgono sopra e sotto il cerchio).
- Senza `ext_noinit=1` REAPER rilancia @init a ogni Play: lo stato da conservare (cue, liste, scelte
  dell'utente) va protetto da una guardia "inizializza una volta sola", non azzerato in @init.

## Marker e testi
- Marker di servizio, mai testo, mai copiati/cancellati dal 14, mai nel gobbo o nell'SRT:
  nome che comincia con `#` (segnaposto) o `!` (azioni), marker del SOLO
  `SOLO_MARK_/OK_/BAD_/ALT_/NOISE_/INSERT_` + numero, senza nome. Regola in 14, aggancio e 31.
- Item vuoti e di testo (note) non hanno take; item generati (video processor) non hanno file.
  Chi conta o raggruppa item (17 Gestore Progetto, 19 Report minuti) usa solo item con take
  e GetMediaSourceFileName non vuoto, mai il semplice "item con lunghezza > 0".
  Opzioni (2026-10-05): 17 "Video" (di serie acceso) e "No muti" (di serie spento, B_MUTE);
  19 "No muti" (modi item/tracce, ExtState ZP_STUDIO_SUITE/Report19_skip_muted). Le opzioni
  nuove partono sempre dal comportamento di prima.
- Marker `#HSC` = cue del Harmonic Space Carver (helper 1.4): servizio, non testo. Il marker comanda
  sul Carver; l'helper cambia l'istantanea solo dopo l'ack del comando 5. Il 17 usa i marker di
  lane 1/2 come sezioni del render: deve ignorare i `#HSC` (fatto in collect_project_markers).
  Chi aggiunge marker di servizio nuovi controlla anche il 17.
- gmem per traccia 4032-4095 (dopo i 56 slot FX da 72 celle): maschere dei cue fuori posto del Carver
  (4032 + 2*fx, fx < 32). Non usarle per altro.
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
