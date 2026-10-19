# ZP Suite — memoria anti-regressione

Regole nate da errori veri. Prima di ogni commit: `bash gobbo_ricerca_battuta/test/run_all.sh`
(sintassi Lua, tag ReaPack, JSFX, test). Se una regola cambia, aggiornala qui e annotalo in MEMORIA.md.

## Versioni, sincronizzazione e pubblicazione
Regola di Paolo, 2026-10-18. Vale per tutti gli agenti (Codex, Claude, altri).
1. **Tre copie, un solo contenuto.** GitHub (`master`), repo locale (`zp-suite`) e installazione in REAPER sono
   identiche file per file dopo ogni pubblicazione. Si lavora nel repo e si installa da li': mai il contrario.
2. **Se non si riesce a sincronizzare, si dice.** Casi: push rifiutato, conflitto, rete assente, check GitHub rosso,
   file `-CONFLICT-`, repo locale su un branch diverso da `master` o indietro/avanti rispetto a `origin/master`,
   hash diversi tra le copie. L'agente lo scrive nella PRIMA riga del messaggio finale e in MEMORIA.md, con file e
   motivo. Non riprova in silenzio, non forza, non pubblica a meta'.
3. **La pubblicazione scandisce le versioni.** Numero della Suite = `@version` del 00. Se l'ultima pubblicata e' N,
   la prima modifica a un prodotto distribuito dopo la pubblicazione porta repo locale e installazione a N+1, un
   solo passo, in tutti i punti (`@version`, intestazioni, help, README, CHANGELOG). Le modifiche successive restano
   N+1 fino alla prossima pubblicazione. Pubblicata N+1, la prima modifica dopo porta a N+2, e cosi' via.
   Esempio di Paolo: pubblico 2.6.1, stasera modifico -> 2.6.2 nel repo e in REAPER; pubblico 2.6.2; la modifica
   dopo -> 2.6.3. Questo scatto e' autorizzato da questa regola. I pacchetti singoli (Carver, BUS Chain...)
   scattano solo quando cambiano, come prevede reapack-index. Le modifiche ai soli prodotti in maturazione
   (punto 5) NON fanno scattare la versione.
4. **Pubblicare = via esplicito di Paolo.** Merge/push su `master`, tag e ReaPack partono solo dopo un suo
   "pubblica" nella conversazione corrente. Prima si prepara e si collauda (`run_all.sh`, check).
5. **Prodotti in maturazione (beta).** Quelli non conclusi stanno elencati in `docs/IN_MATURAZIONE.md`: nome, dove
   vivono, perche' non sono nella release, cosa manca. Restano `@noindex` o `--ignore`, fuori dal `@provides`.
   Prima di ogni pubblicazione l'elenco si rilegge e si aggiorna; README e note di rilascio riportano una sezione
   **«Non incluso in questa versione»** con quell'elenco. Un prodotto esce dalla beta solo per decisione di Paolo.
6. **Prima di pubblicare** si aggiornano allo stato reale: questo file, MEMORIA.md, gli help (it/en),
   README (it/en) e CHANGELOG.
7. **Come riferire (gli agenti sono troppo verbosi e le cose importanti sfuggono).** Il messaggio finale inizia con
   UNA riga di esito: `SINCRONIZZATO` oppure `NON SINCRONIZZATO: <motivo>`, piu' la versione (repo / REAPER /
   GitHub). Subito dopo, solo se ce ne sono, `DECISIONI PER PAOLO:` con elenco corto. Il resto (dettagli,
   comandi, test) viene dopo e puo' essere lungo. Mai seppellire un errore o una divergenza nel racconto.

## Pubblicazione e GitHub
- Ogni `.lua`/`.jsfx` nuovo nei pacchetti deve avere `@version`, `@noindex` o stare nel `@provides`
  di un pacchetto. Senza, il controllo GitHub "check" (`reapack-index --check`) fallisce
  (successo il 2026-10-04: 28_Collega_Marker e le bozze). Gli helper hanno `@noindex`.
- `gobbo_ricerca_battuta`, `ZP Lab`, `speech-engine` sono esclusi in `.reapack-index.conf`: non toglierli.
- reapack-index tratta come pacchetto anche un `.txt` nelle cartelle dei pacchetti: un file di dati o di
  licenza distribuito con il @provides del 00 va escluso con `--ignore` in `.reapack-index.conf` (come
  README.txt). Successo il 2026-10-17 con tools/LICENSE-SheetJS-Apache-2.0.txt ("missing tag 'version'").
- Ogni file nuovo che NON e' uno script/effetto (cataloghi .txt, .ReaperLangPack, dati) va in `--ignore` nel
  `.reapack-index.conf`, anche se sta nel @provides della 00: altrimenti il check lo prende per un pacchetto senza
  versione (lang/en.txt e REAPER_Italiano, 2026-10-10). Esclusi anche: catalogo, dati_traduzione e template di REAPER_Italiano (il language pack,
  invece, e' nel @provides del 00 con @noindex).
- Un file `[langpack]` nel `@provides` va scritto con target piatto: `[langpack] /REAPER_Italiano/X.ReaperLangPack > X.ReaperLangPack`.
  ReaPack scarta i `..` e installa in `LangPack/<percorso del file>`: senza `>` il pacchetto finiva in
  `LangPack/REAPER_Italiano/` e REAPER non lo mostrava nell'elenco delle lingue (2.6.1, 2026-10-18; corretto in 2.6.2).
  Collaudo sul Mac dopo l'installazione: il file sta direttamente in `<risorse REAPER>/LangPack/` e compare in
  33 Benvenuto > Lingua di REAPER.
- Lingua di REAPER dal 33 Benvenuto (2.6.3, 2026-10-19): `reaper.SNM_SetStringConfigVar("langpack", ...)` restituisce
  `false` e non cambia niente (REAPER 7.80 + SWS 2.14): la 2.6.2 elencava i pack ma la scelta non partiva mai. Non usarlo
  mai piu' per la lingua. REAPER scrive `langpack=<nome file con estensione>`; `<>` = inglese di serie («Load always» su
  English), riga vuota = REAPER chiede la lingua a ogni avvio. La lingua si cambia scrivendo reaper.ini DOPO la chiusura
  di REAPER (helper di riavvio `restart_sh` con `patch`). L'helper aspetta il PID dell'istanza che l'ha lanciato e riapre
  l'app di quell'istanza (da `ps`), non «qualunque REAPER» ne' /Applications/REAPER.app: con una prova portatile aperta
  insieme al REAPER di lavoro riapriva quello sbagliato (collaudo 2026-10-19).
  Su macOS la sezione di reaper.ini e' `[reaper]` in MINUSCOLO: scrivere in fondo una seconda sezione `[REAPER]` fa
  IGNORARE a REAPER la prima e azzera tutte le impostazioni (dispositivo audio, tema, finestre: successo nel collaudo).
  L'helper riconosce la sezione senza badare alle maiuscole e rinuncia se il file risultante avrebbe meno righe; i test
  (`test_benvenuto.lua`, «helper ini») eseguono la shell generata su un ini finto.
  Un collaudo di «installa un pack» deve includere la scelta e il riavvio, non solo la presenza del file in LangPack.
- Un file nuovo distribuito (fxchains, presets, help, icone) va aggiunto al `@provides` del 00
  e il percorso deve esistere (run_all lo controlla).
- Mai push su master, tag o ReaPack senza il via esplicito di Paolo. Lo scatto di versione dopo una
  pubblicazione e' invece automatico: vedi «Versioni, sincronizzazione e pubblicazione» in cima a questo file.
- reapack-index crea una versione solo nel commit dove cambia @version: se dopo il bump aggiungi file o
  modifiche al pacchetto, rialza la versione prima di pubblicare (2.3.0 uscita senza icone, 2026-10-06).

## Harmonic Space Carver: cue e helper
- I cue esistono solo per il Carver: un #HSC cancellato o aggiunto fuori dal Carver si ripristina/toglie
  (decisione di Paolo). Al primo giro su un progetto comanda il Carver: l'helper non cancella mai cue.
- Il progetto si riconosce da puntatore + file (`EnumProjects(-1)`): la stessa scheda puo' contenere un altro progetto.
- Cambio di progetto (scheda o file): l'helper rilegge SUBITO i Carver (rescan) e aspetta HSC.SETTLE prima del
  primo confronto. Con l'elenco dei Carver vecchio (rescan ogni 1 s, sync ogni 0,25 s) il primo giro copiava i cue
  del progetto di prima nei marker e nei cue di quello nuovo (helper 1.9, 2026-10-07; test_hsc_schede.lua).
- carver_side: un marker per ogni cue tolto, anche con due cue nello stesso punto.
- Le richieste in ExtState si cancellano dopo l'uso (un helper riavviato non deve rieseguirle).
- Un solo helper: ExtState ZP_HSC/owner, l'ultimo avviato vince.
- gmem del Carver per numero unico (parametro "HSC Slot", assegnato dall'helper fra TUTTI i progetti
  aperti): blocchi da 76 celle da 8310000 (slot 1-900, fino a 8378476; gmem arriva a 8388608).
  Senza numero vale ancora traccia+posizione (4096 + (traccia+2)*4096 + fx*72): due progetti in schede
  li' si scontrano. Chi cerca un Carver in gmem (azioni, helper) legge prima lo slot.
- Correzioni automatiche dell'helper sui marker: MAI in un blocco di undo (Ctrl+Z si incastrerebbe:
  annulli, l'helper rimette, nuovo punto). Undo solo per le azioni chieste da Paolo (Riallinea, Tieni qui).
- Il DSP non scrive sui parametri (forbici Min/Max Duck e crossover): usa i valori effettivi; le forbici
  le applica la GUI quando l'utente muove un valore. Scrivere un parametro dal DSP sporca le automazioni.
- `pdc_delay` si imposta in @init/@slider, non in @block.
- Lo stato da sistemare al caricamento (preascolto, migrazioni) va in @serialize + primo @block, non in @init:
  REAPER ricarica i parametri dopo @init.
- Installazione su questo Mac: veri in `Scripts/ZP Suite/ZP Voce/` (cartella di ReaPack); in `Scripts/ZP Suite/`
  solo tre rimandi (helper all'avvio SWS, Mostra tracce voce, Riallinea su Ctrl+\). Non sovrascriverli con i veri.

## Primo avvio (33 Benvenuto)
- La spunta e' ExtState persistente ZP_STUDIO_SUITE/benvenuto_visto; chi apre il Benvenuto la scrive PRIMA di
  caricare ZP_UI (ZP_UI lo apre se e' vuota). Un pezzo nuovo da installare a mano = una riga nel 33.
- Scripts/__startup.lua e' dell'utente: si scrive solo il blocco tra ZP_BENVENUTO_HSC_INIZIO e _FINE.

## Icone
- Prima di chiedere un'icona nuova (a Codex o altri) controlla che il nome non esista gia' in `ZP Studio Suite/icons`
  e in Data/toolbar_icons: un nome uguale sovrascrive l'icona installata (successo con ZP_tb_23_Chain_Builder, 2026-10-06).
- Icone toolbar: PNG 90x30 (3 stati 30x30) + `200/` a 180x60; stile REAPER #818989 / #939A9A / #1ABC98.

## Help
- Ogni modifica visibile a Paolo aggiorna, nello stesso commit, l'help (`help/index.html` e la pagina
  dedicata: solo_recorder, pannello_trascrizione, toolbar...) e le spiegazioni dentro lo script
  (suggerimenti, guida ?). Prima del commit cerca nell'help le frasi del comportamento vecchio.
- Le copie installate dell'help devono restare uguali al repo.
- help/toolbar.html contiene le icone INCORPORATE (base64): se cambiano le icone della toolbar vanno
  sostituite anche li' (successo con la 2.4.0: guida con le icone vecchie, corretta nella 2.4.1).
- Il menu OSARA del Gobbo (OpenGobboAccessibleMenu) deve usare gli stessi nomi della barra comandi;
  i numeri delle voci non si cambiano (chi usa lo screen reader li ricorda).
- Prima di pubblicare: cercare nelle guide E negli script (suggerimenti, guida ?, menu OSARA) i nomi vecchi.

## Installazione su questo Mac
- **Collaudo come un utente.** Per tutto cio' che viaggia con ReaPack (percorsi, cartelle, @provides, language pack,
  icone, fxchains) l'installazione sul Mac di Paolo si fa passando da ReaPack (Synchronize/Update dal repository
  pubblicato) e si controlla il risultato: dove e' finito davvero il file. Mai copiare a mano un file nella cartella
  di REAPER per far «funzionare» il collaudo: nasconde i bug di percorso. Caso: language pack 2.6.1 (2026-10-18),
  copiato a mano in LangPack/ funzionava; via ReaPack finiva in LangPack/REAPER_Italiano/ e REAPER non lo vedeva.
  Se serve provare prima di pubblicare, si simula il percorso che ReaPack calcolera' (attributo `file=` nell'indice)
  e si dichiara che NON e' un'installazione reale.
- Prima di sovrascrivere una copia in `REAPER/Scripts/ZP Suite/...`, verifica che sia uguale
  a `git show HEAD:<file>`; se e' diversa, fermati e chiedi. La 00 installata e' quella pubblicata.
- Mai modificare direttamente le copie installate in REAPER: si lavora nel repo e si installa. Prima di
  installare o pubblicare, confronto a tre (installato / HEAD / working tree) di tutti i file distribuiti:
  il 2026-10-17 `tools/srt_tools.html` installato aveva l'importazione Excel (SheetJS) che nel repo non
  c'era; reinstallare l'avrebbe cancellata. Se l'installato e' diverso da tutto, si riporta nel repo.
- Librerie di terzi incorporate (es. SheetJS in srt_tools.html): attribuzione e licenza in NOTICE.md.
- Mai toccare `reaper-kb.ini` / `reaper.ini` con REAPER aperto (`pgrep -x REAPER`), sempre con backup.
- `reaper-menu.ini`: unica eccezione decisa da Paolo (2026-10-06, "mai dire mai") e' il 32, che scrive SOLO la
  sezione della toolbar "ZP Studio Suite" (backup accanto) e chiede di riavviare. REAPER riscrive il file solo
  quando si modificano menu/toolbar (non ad avvio o chiusura): fino al riavvio niente Customize toolbars.
  L'Import di REAPER non porta il nome della toolbar se la si importa in un'altra toolbar.
- I file .ini di REAPER (reaper-menu.ini & co.) si leggono RIGA PER RIGA, sezione per sezione. Un pattern su tutto
  il testo tipo `\n%[sezione%]\n(.-)\n%f[%[]` consuma la riga vuota fra due sezioni e salta una sezione si' e una
  no: il 32 vedeva libere toolbar piene (trovato il 2026-10-09 aggiungendo ZP Colori; test_installa_toolbar).
  Stesso errore nel 33 (toolbar_slot): diceva "Floating toolbar 23" invece della 32; e cercava solo icone `ZP_tb_`,
  non le nuove `ZP_tbB_`. Ora M.menu_sections (riga per riga). Chi legge reaper-menu.ini usa quella.
- Mai `git stash` in questo repo: c'e' uno stash vecchio di Paolo (stagekeeper-wip) e con file `git add -N` lo stash
  non si crea e `stash pop` prova ad applicare quello vecchio (2026-10-09, fermato senza danni).
- Il 32 scrive la toolbar "ZP Studio Suite" e, SOLO se chiesta dal 33 (ExtState ZP_STUDIO_SUITE/toolbar_colori=1) o gia'
  presente, "ZP Colori" (pick_slot con il titolo). Di serie i colori sono nella finestrella 35. Pulsanti di ZP Colori =
  script in colori/ che leggono dal proprio nome cosa fare: non rinominarli (il 32 e la toolbar li cercano per nome).
- Backup in `gobbo_ricerca_battuta/backup/` prima di modifiche grosse; ogni cambio in MEMORIA.md.

## REAPER (cose verificate, non intuitive)
- `utf8.offset(s, n, i)` va in errore se i cade a meta' di una lettera UTF-8 (crash Backspace nel Gobbo, 2026-10-07):
  per muovere il cursore usare Utf8PrevCursor/Utf8NextCursor dei Gobbi (scorrono i byte a mano).
- Lua: una funzione locale (es. `set_color` in ZP_UI) esiste solo DOPO la riga che la definisce; usata prima diventa
  una globale nil e lo script si ferma ('attempt to call a nil value', firma UI.draw_credit, 2026-10-09). Controllo:
  `luac -l -p file.lua | grep 'GETTABUP.*_ENV "nome"'` non deve trovare helper locali.
- `gfx.setclip` NON esiste (inventata da Codex nel Passo 2 ricerca, crash all'apertura del pannello, 2026-10-07). Per tagliare il testo:
  `gfx.drawstr(s, 0, right, bottom)` (clip a gfx.x,gfx.y,right,bottom). Controlla ogni funzione gfx/reaper nuova sulla documentazione.
- 40850 = "Item: Show notes for items" (NON le note del progetto). Le note del progetto non hanno
  un'azione nativa: con SWS `_S&M_SHOWNOTESHELP`, senza SWS 40021 Project settings.
- `TrackFX_AddByName` non carica `.RfxChain`: blocco FXCHAIN in una traccia temporanea + `TrackFX_CopyToTrack`.
- I preset JSFX sono legati al PERCORSO del JSFX (`presets/js-<cartella>_<file>_jsfx.ini`):
  dopo il passaggio a ReaPack i preset del vecchio installer non valgono piu'. Li distribuisce la 32.
- Il glue SI porta dietro i take marker (con tempi da rileggere): per rileggere usare Ritrascrivi della 29.
- I take marker stanno nel progetto, non nel WAV. Tempo timeline = pos + (src - startoffs) / playrate.
- Un solo `gfx` per script: per aprire un altro strumento senza chiudere la finestra lancialo come
  azione (`Main_OnCommand` con l'ID da reaper-kb.ini), e passa i parametri via ExtState, non `_G`.
- Mouse modifiers: si cambiano con `SetMouseModifier`/`GetMouseModifier` (mai scrivendo reaper-mouse.ini). Il nome
  dell'azione per esteso NON viene accettato (diventa "0 m" = No action): servono i codici. Take marker, left drag
  (MM_CTX_ITEMTAKEMARKER, REAPER 7.82): 0 No action, 1 Move, 2 Move ignoring snap, 3/4 start position, 5/6 end
  position, 7/8 Copy. Per i take marker non esiste "Pass through to item": No action lascia prendere l'item
  (provato da Paolo). GetMouseModifier restituisce "0" per No action. Si prova in REAPER aperto con
  `REAPER -nonewinst script.lua` (esegue lo script nell'istanza aperta).
- `JS_Dialog_BrowseForFolder` restituisce 1/0/-1: in Lua 0 e' VERO, controllare `rv == 1`.
- macOS: `open "file#ancora"` non funziona; usare l'URL file:// codificato (`UI.help_url`).
- Messaggi: niente `ShowConsoleMsg` salvo errori gravi; preferire finestre che restano aperte
  e si chiudono a mano ai `MB` bloccanti; OSARA (`osara_outputMessage`) per l'accessibilita'.

## JSFX / EEL2
- Dopo ogni modifica a un JSFX: run_all controlla le parentesi (test/parentesi_jsfx.py). Sostituzioni automatiche nel codice
  EEL2: espressione esatta, mai pattern con parentesi facoltative (una regex si e' mangiata la '(' di un corpo funzione, 2026-10-10).
- Funzioni usate in @gfx: definirle in @init o all'inizio di @gfx, MAI in @sample/@block (lo Stagekeeper l'aveva in fondo a
  @sample, 2026-10-10). Le funzioni definite in @init valgono ovunque.
- Niente notazione scientifica (`1e-30`): calcolare la costante in @init.
- Assegnazioni dentro `?:` sempre tra parentesi. `slider_show` vuole la maschera `2^(n-1)`.

- Ogni array in memoria (`x[i]`) deve avere un indirizzo base assegnato in @init, in una zona libera:
  una variabile mai assegnata vale 0 e scrive sopra la memoria del DSP (Carver: cue sugli stati SVF).
  Per trovare gli array cerca anche i nomi con maiuscole (es. `buf_main_L[`): mappa TUTTA la memoria
  usata prima di scegliere la base (Carver 2.6.5: 0-15 SVF, 16-6159 oscilloscopio, 8192 cue,
  8320 backup cue, 8400-8431 tabella Partenza, 8440-8442 stato fonti SC, 8460-8523 selezione ELIMINA,
  16384-49151 lookahead).
- gmem del Carver: 72 celle per FX (`base+0..71`), mai oltre `+71` (sarebbe l'FX successivo). `+71` = routing SC (helper).
- Mappa gmem complessiva (options:gmem=ZPVoiceoverSharedBus):
  - 0..606: Shared Bus telemetria / profili (Probe, BUS Chain, Spoken Finish, Unified Chain, Master Pro)
  - 3800..3899: casella comune comandi HSC Carver (3800 destinatario, 3801 comando, 3802 pos, 3803 seq, 3804 ack)
  - 3900..3919: casella PONTE HELP / LINGUA (3900 ponte vivo / heartbeat incrementale, 3901 lingua 0=IT 1=EN, 3902 req_plugin 1..11, 3903 req_seq, 3904 ack_seq, 3905 ack_status; 3906..3919 riserva)
  - 4032..4095: maschere cue per-traccia Carver
  - 4096..8300000: istanze Carver per traccia/posizione (4096 + (traccia+2)*4096 + fx*72)
  - 8310000..8378476: slot Carver unici assegnati dall'helper (slot 1-900)
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
- Abbina dalla strada 29 non apre mai il Finder per item: un file glued ha marker ma nessun SRT
  accanto (nome nuovo) e la tappa 1 risulta fatta; il 28 decide prima dei marker (`decide`), poi cerca
  il file, e gli item saltati li elenca nella riga di stato (2026-10-06, test_collega_marker).
- Abbina > SRT accanto non tocca mai item gia' abbinati (niente domanda per item): per rifarli c'e' Ritrascrivi.
  Con SRT esterno la domanda 'sostituisci?' e' una sola per tutta la selezione (decisione di Paolo).
- L'SRT di Trascrivi sta accanto al WAV apposta (lo cerca Abbina). Gli SRT di consegna (08, 31)
  vanno nella cartella scelta, mai tra i media.

## SOLO Recorder
- Lucchetto REC spento di default (chiave ExtState `rec_lock2`). Nascondi 5s / Parcheggia tolti.
- Il SOLO richiede `ZP_UI.lua` con `draw_knob`: ZP_UI e SOLO si aggiornano insieme.
- Dopo modifiche alla pulsantiera: simulazione fuori REAPER (nessun comando fuori finestra o sovrapposto).
- 25_ZP_SOLO_Recorder.lua e' al limite di 200 variabili locali nel blocco principale: funzioni nuove in tabelle (es. WEB.*).
- Meter IN = ingresso vero della scheda (`GetInputActivityLevel`, che restituisce GIA' dB, -150 = silenzio: mai
  math.abs / amp_db sopra), non `Track_GetPeakInfo` della traccia (quello e' ampiezza); meter sempre in dB
  (in lineare una voce a -30 dB riempie il 3% e sembra morta).
- `gfx.showmenu`: separatori e intestazioni di sottomenu (`>`) non contano nell'indice restituito.
- Un pulsante che apre la guida ? e lo stesso pulsante ridisegnato dalla guida: il clic di apertura non va passato alla guida
  nello stesso giro (si richiuderebbe subito).
- Testata del SOLO: solo celle-icona 28x24 in pillole (docs/PROGETTO_SOLO_testata_iconcine.md); niente pulsanti a scritta.
  Per vedere il disegno fuori REAPER: gfx finto che scrive SVG, poi `qlmanage -t` per il PNG.
- Il pre-roll e' quello di REAPER: bit 2 del config `preroll`, durata `prerollmeas` in MISURE (convertire dai secondi
  al tempo del cursore a ogni REC). Nessun conto alla rovescia interno. Servono le funzioni SNM_* di SWS.
- Casella di testo in una finestra gfx: mentre ha il fuoco prende TUTTI i tasti (barra e ? compresi), svuotando la coda di getchar.

## Interfaccia web di REAPER (ZP SOLO Web)
- `/_/SET/EXTSTATE/sez/chiave/valore`: REAPER decodifica gia' l'URL; lo script non deve decodificare di nuovo.
- `/_/GET/EXTSTATE/...` codifica nel valore `\t`, `\n`, `\\`: decodificare in un solo passaggio.
- La pagina non fa logica: comandi e controlli stanno nel motore (docs/PROGETTO_SOLO_Web.md).

## Riferimenti per confronti (anti-regressione)
- ZP Stagekeeper Dialogue Director 2.3.1 (ultima pubblicata prima della 2.5.0):
  `gobbo_ricerca_battuta/backup/ZP Stagekeeper Dialogue Director 2.3.1.jsfx`. Se la 2.5.x
  peggiora qualcosa, confrontare con questa.
