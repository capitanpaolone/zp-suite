# Changelog — ZP Suite

## ZP Studio Suite 2.6.7 — in preparazione

- **Language pack italiano per REAPER 7.86**: in italiano anche le finestre dei pacchetti `.ReaperPkg`, la cartella FX nascosti, il Learn MIDI/OSC di track e send, le nuove opzioni di render e i take marker con durata. Resta completo anche su REAPER 7.82–7.85.
- **Italian language pack for REAPER 7.86**: package (`.ReaperPkg`) windows, the Hidden FX folder, MIDI/OSC Learn for tracks and sends, the new render options and take markers with length are now in Italian. It stays complete on REAPER 7.82–7.85 too.
- **Collega marker (28) e SRT dall'audio (31) con REAPER 7.86**: i marker dell'item portano la durata della battuta e l'SRT riscritto dai marker ha la fine esatta. Con REAPER precedenti il comportamento non cambia.
- **Collega marker (28) and SRT from audio (31) with REAPER 7.86**: item markers carry the cue length and the SRT rewritten from markers has the exact end time. Nothing changes on earlier REAPER versions.
- **Gobbi: unisci battute**: clic destro sul testo → «Unisci con la battuta successiva» o «Unisci le battute selezionate in timeline». Resta il primo item con i testi in fila e la durata fino alla fine dell'ultimo; promemoria e parole evidenziate seguono il testo. Nuova azione **38 ZP Unisci Battute** per farlo sugli item selezionati senza aprire il Gobbo.
- **Teleprompters: join cues**: right-click the text → "Join with the next cue" or "Join the cues selected in the timeline". The first item stays with the texts in a row and its length reaching the end of the last one; reminders and highlighted words follow the text. New action **38 ZP Unisci Battute** does it on the selected items without opening the Teleprompter.
- **ZP Consolidate (37): Numera item**: terzo comando della finestra; rinomina gli item delle tracce selezionate con nome della traccia e numero progressivo, nell'ordine in cui stanno sulla traccia.
- **ZP Consolidate (37): Number items**: third command in the window; renames the items on the selected tracks with the track name and a running number, in track order.
- **Copione in Excel (01, 05, 06)**: dove si sceglie l'SRT/VTT si può scegliere un `.xlsx` con i tempi. Colonne riconosciute dalle intestazioni, battute come `PERSONAGGIO: testo` con la reazione in coda, fine stimata dal successivo inizio; accanto all'Excel resta l'SRT. Con più fogli adatti o più colonne di testo (una per lingua) chiede quale importare. Stesse regole di SRT Tools (26). Nel testo libero dei Gobbi, Carica file… accetta lo stesso `.xlsx` (una battuta per riga). Il menu ZP SRT indica dove si sceglie l'Excel.
- **Importa Video + SRT (01)**: l'importazione registra l'SRT nel progetto senza fermarsi.
- **Excel script (01, 05, 06)**: wherever an SRT/VTT is requested you can pick an `.xlsx` with timecodes. Columns recognised from headers, cues as `CHARACTER: text` with the reaction appended, end estimated from the next start; the SRT is written next to the Excel file. With several suitable sheets or several text columns (one per language) it asks which one to import. Same rules as SRT Tools (26). In the prompters' free text, Load file… accepts the same `.xlsx` (one cue per line). The ZP SRT menu shows where the Excel file is chosen.
- **VTT e reazioni**: la voce `<v Nome>` di un WebVTT diventa `Nome: testo`; i tag di formato spariscono, le reazioni fra parentesi angolari (`<sospira>`) restano nel testo delle battute.
- **VTT and reactions**: a WebVTT `<v Name>` voice becomes `Name: text`; formatting tags are removed, reactions in angle brackets (`<sospira>`) stay in the cue text.
- **ZP BrownSlope Prism 1.0 (ZP Misura)**: analizzatore passivo della pendenza brown. Lo spettro è compensato di 4,5 dB per ottava, con riferimenti a -18 e -24 LUFS, scarto per zona, pendenza residua ed esito Pareggiato / Quasi / No; Calibra lega il riferimento a un proprio file, la vista JSFX espone le letture a OSARA. Il ? apre la sezione nella guida della Suite.
- **ZP BrownSlope Prism 1.0 (ZP Misura)**: passive brown-slope analyzer. The spectrum is compensated by 4.5 dB per octave, with -18 and -24 LUFS references, deviation per zone, residual slope and a Matched / Close / No result; Calibrate ties the reference to your own file, the JSFX view exposes the readings to OSARA. The ? opens its section in the Suite guide.
- **ZP Consolidate (37)**: raccoglie in Media le sorgenti file dei take e gli SRT/VTT registrati nel progetto, preserva montaggio e originali, e gestisce le collisioni scegliendo sovrascrittura o rinomina. Aggiunti modulo SRT condiviso, icona e pulsante toolbar.
- **Benvenuto (33)**: scroll della lista smussato e limitato prima del disegno per evitare salti dovuti ai delta rapidi/inerziali della rotella.
- **SRT di progetto**: trascrizioni e traduzioni sono copiate/registrate in Media e referenziate nel file RPP.
- **ZP Speech su Windows (sperimentale)**: Trascrivi e Traduci (29) girano in background anche su Windows (PowerShell), con elenco modelli via `curl.exe`; il Benvenuto (33) installa ZP Speech con PowerShell e l'installatore si ferma con un errore se un passo non riesce. ZP Remote nel Benvenuto dice che per ora funziona solo su macOS.
- **ZP Speech on Windows (experimental)**: Transcribe and Translate (29) run in the background on Windows too (PowerShell), with the model list read through `curl.exe`; Welcome (33) installs ZP Speech with PowerShell and the installer stops with an error if a step fails. ZP Remote in Welcome says it only works on macOS for now.
- **Language pack italiano e Render Queue**: il suffisso `(delay %ds)` e le voci `sel_regions`/`sel_markers` restano in inglese, come le riconosce REAPER; l'import multicanale rispetta l'ordine degli argomenti. `controlla_langpack.py` verifica qualsiasi pack, anche di terzi.
- **ZP Crea Regioni Export (17)**: riconosce la finestra di render anche con REAPER localizzato.

- Gobbi: importazione DOCX/ODT/RTF/TXT, incolla pulito, editor con scroll/Undo e durata temporizzata opzionale; controlli ZP_UI, progresso e riaggancio rapido. Guide IT/EN aggiornate. Pause effettive con Shift+Invio, promemoria tramite marker e divisione alla parola selezionata con conservazione del testo rimanente. Verifiche automatiche superate; collaudo del Gobbo confermato da Paolo il 10 novembre 2026.

Copia di lavoro avviata dal tag `v2.6.6`. Le modifiche e i componenti aggiornati acquisiti dalla REAPER locale sono registrati in `docs/PRE_RELEASE_2.6.7.md` e `docs/PROVENIENZA_2.6.7.md`; questa sezione sarà completata dopo i collaudi.

Le versioni dei singoli effetti sono indipendenti: le trovi nell'intestazione di
ciascun file e nel gestore pacchetti. Questo file registra la storia della Suite
nel suo insieme.

## ZP Studio Suite 2.6.6 — 2026-11-04

- **ZP Render & Copy** estende la copia automatica e Sincronizza ora a Windows (con js_ReaScriptAPI) e Linux (con `find` e `stat`). Mostra in consegna apre il gestore file del sistema.
- **ZP Render & Copy** supports automatic copying and Sync now on Windows (with js_ReaScriptAPI) and Linux (with `find` and `stat`). Show in delivery opens the system file manager.

### Non incluso in questa versione

ZP Montaggio Parlato, ZP BrownSlope Dynamic Guard, ZP BrownSlope Prism e ZP Speech Engine sono in lavorazione.

## ZP Studio Suite 2.6.5 — 2026-11-03

- **Guida del Solo Recorder**: chiarisce che i pacchetti preparati con ZP Remote sono destinati a Dubbertools e distingue questa consegna dai comandi di registrazione del SOLO Web Remote.
- **Solo Recorder guide**: clarifies that packages prepared with ZP Remote are intended for Dubbertools and distinguishes package delivery from the SOLO Web Remote recording controls.

## ZP Studio Suite 2.6.4 — 2026-11-03

- **Report minuti voce (19)**: esporta in CSV lo storico HTML già presente nel progetto. “Salva questa sessione” crea anche un CSV separato, con progetto, data e modalità nel nome; “Aggiungi allo storico” aggiorna il CSV cumulativo insieme all'HTML.

- **ZP Render & Copy**: copia il risultato del render nella cartella di consegna. La finestra e la toolbar hanno un’icona dedicata e il pulsante di aiuto spiega come impostare le cartelle.
- **ZP Remote**: da REAPER si può creare il pacchetto di una regione per Dubbertools e importare le registrazioni ricevute. Il telecomando web del Solo Recorder ha un collegamento a dubbertools.com.
- **ZP Colori e Gestore Progetto**: selettori per item, tracce, marker e regioni, modalità Auto per la selezione mista e colore effettivo delle regioni nel Gestore.
- **Harmonic Space Carver 2.6.8 e Cue Navigator 1.13**: i cue seguono l’identità dell’item anche se cambia il take. Il navigatore distingue un riferimento mancante da un cue spostato e offre il comando Adotta posizione.
- **SRT Tools**: aggiornato lo strumento offline per preparare e convertire i sottotitoli.
- **Pre-roll**: il comando PRE nel Recorder e nel telecomando web aggiorna la spia della toolbar nativa di REAPER, mantenendo sincronizzato lo stato visivo.
- **Gobbo verticale**: i colori speaker si applicano anche selezionando item della traccia voce o note personaggio associate.
- **Italiano (ZP)**: la voce principale del menu resta *Help* per mantenere attiva la ricerca nativa dei menu su macOS; le voci interne restano tradotte.

### Non incluso in questa versione

ZP Montaggio Parlato, ZP BrownSlope Dynamic Guard, ZP BrownSlope Prism e ZP Speech Engine sono in lavorazione.

## ZP Studio Suite 2.6.3 — 2026-10-19

- **Lingua di REAPER, correzione**: nel 33 Benvenuto la scelta della lingua non aveva effetto. La 2.6.2
  installava bene *Italiano (ZP)* e lo elencava, ma il comando usato per scrivere la scelta
  (`SNM_SetStringConfigVar`) con REAPER aperto restituisce *falso*. Ora la scelta resta in attesa e
  **Riavvia ora** chiude REAPER, scrive la riga `langpack=` in `reaper.ini` e lo riapre.
- **Importa un language pack...**: dal menu della lingua copi nella cartella LangPack un tuo file
  `.ReaperLangPack` (si controlla che sia un language pack) e lo selezioni subito.
- **Cerca altri language pack in ReaPack...**: apre ReaPack sui language pack disponibili.
- Il menu è per macOS; su Windows e Linux il pulsante apre le Preferenze di REAPER (Language).
- **Traduzione italiana di REAPER, molto più completa**: *Italiano (ZP)* passa da circa 7.500 a circa
  17.700 voci tradotte su REAPER 7.82. Menu principali e contestuali e finestre di dialogo sono tradotti
  al 100%, come le spiegazioni delle Preferenze. Le Action restano in inglese, così la ricerca per nome
  nella Action List continua a funzionare; i termini tecnici (item, take, marker, region, track, render,
  FX, send, ...) restano in inglese. Per usare la nuova traduzione riavvia REAPER dopo l'aggiornamento.

### Non incluso in questa versione

36 ZP Montaggio Parlato (prototipo), ZP BrownSlope Dynamic Guard, ZP BrownSlope Prism e ZP Speech Engine.
Sono in lavorazione e non fanno parte del pacchetto ReaPack.

## ZP Studio Suite 2.6.2 — 2026-10-18

- **Traduzione italiana di REAPER, correzione**: con la 2.6.1 il language pack *Italiano (ZP)* veniva
  installato in una sottocartella di LangPack e REAPER non lo vedeva nell'elenco delle lingue. Ora va
  direttamente in LangPack. Dopo l'aggiornamento scegli *Italiano (ZP)* nel 33 Benvenuto, alla voce
  *Lingua di REAPER*.
- **Gestore Progetto (17)**: **Salva** applica alle rispettive regioni i nomi ancora in bozza, crea solo
  le regioni mancanti per quei nomi e salva il progetto. Chiudendo con nomi in bozza, **Sì** li applica
  e salva prima di uscire; **No** torna al Gestore.

### Non incluso in questa versione

36 ZP Montaggio Parlato (prototipo), ZP BrownSlope Dynamic Guard, ZP BrownSlope Prism e ZP Speech Engine.
Sono in lavorazione e non fanno parte del pacchetto ReaPack.

## ZP Studio Suite 2.6.1 — 2026-10-18

- **Traduzione italiana di REAPER**: il language pack *Italiano (ZP)* viene installato insieme alla Suite
  nella cartella LangPack di REAPER. Si sceglie dalle preferenze di REAPER, alla voce della lingua. Sono
  tradotti menu, finestre di dialogo e aiuto delle Preferenze; le Action restano in inglese.

## ZP Studio Suite 2.6.0 — 2026-10-17

- **Guide nella lingua della Suite**: anche *00 Apri Help* apre la guida italiana o inglese scelta nel
  33 Benvenuto. README su GitHub in inglese (`README.md`) e in italiano (`README.it.md`).
- **SOLO Recorder**: il pulsantino **S** sul REC mette in solo la traccia di registrazione (in Telecomando
  la prima traccia armata); il picco del meter IN è una barretta azzurra.
- **Gobbi**: il pannello note mostra prima le note aperte, poi quelle concluse; doppio clic nello spazio
  libero o tasto destro aggiunge una nota; ogni risultato di *Cerca* ha il pulsante **Vai →**.
- **Gestore Progetto (17)**: una barra in fondo alla finestra spiega il pulsante su cui passi con il mouse.
- **Voice Cleaner (22)**: pannello *Revisione manuale* per ascoltare e decidere ogni segmento (Play, zoom,
  Approva o Scarta segmento, Approva tutti); **ASCOLTA**, **PULISCI MARKER** e una memoria della
  calibrazione con nome. APPLICA usa solo i segmenti approvati.
- **Report minuti voce (19)** e **Chain Builder (23)**: gli esiti restano nella loro finestra.
- **SRT Tools (26)**: legge i file Excel XLS e XLSX, con scelta di foglio e colonne (inizio, fine, testo,
  personaggio, reazione). Include SheetJS (Apache-2.0, testo della licenza accanto alla pagina).
- **Plugin**: Harmonic Space Carver 2.6.7 con Cue Navigator 1.12 (un clic sull'avviso rosso
  *CUE FUORI POSTO* riporta tutti i cue sulla loro voce) e ZP BUS Chain 1.3.1 (interruttori Brown Guard
  DYN ed EQ separati). Guide aggiornate per Carver, Voice Cleaner, BUS Chain e Gestore Progetto.

## ZP Studio Suite 2.5.0 — 2026-10-10

- **ZP Colori (35)**: finestrella *clicca e colora*. Scegli il modo (**Item**, **Traccia** o **Tutto**),
  selezioni e clicchi uno dei 20 colori; **Togli colore** li toglie. Si apre e si chiude dal pulsante
  tavolozza della toolbar ZP e si può agganciare. La stessa cosa come toolbar sempre a vista,
  facoltativa, si installa dal 33 Benvenuto.
- **ZP Set Comandi (34)**: set di scorciatoie da tastiera (montaggio video, abitudini Pro Tools o Logic,
  i tuoi). Ogni set ha la sua pagina con tutte le scorciatoie scritte per esteso; Salva, Importa,
  Rinomina, Archivia; prima di ogni cambio i tasti in uso vanno nel set *Backup automatico*. Cambia solo
  i tasti (script e toolbar restano) e vale dal riavvio di REAPER. *Spiega con l'AI*, a richiesta,
  descrive un set in poche righe.
- **Inglese**: nel 33 Benvenuto scegli la lingua della Suite (italiano / English) e, a parte, quella di
  REAPER (originale o un language pack installato). Finestre, messaggi e guide in inglese; la pagina web
  del SOLO ha IT / EN.
- **Funzioni AI** (Traduci, Spiega con l'AI) con l'agente che hai sul Mac: Codex, Claude, Qwen, OpenCode o
  Ollama in locale (niente esce dal Mac). Prima di partire dicono quale agente usano e dove va il testo.
  Serve ZP Speech aggiornato (`bash speech-engine/install_macos.sh`).
- Firma **Lato Cardioide** nelle finestre e nelle guide; toolbar ZP con i pulsanti *ZP Colori* e
  *Set Comandi*; il Benvenuto scorre quando la finestra è bassa.
- **Plugin** (BUS Chain 1.3.0, Harmonic Space Carver 2.6.6, Spoken Finish 3.10.0, Stagekeeper 2.5.1,
  Subliminal Presence Layer 3.2.2, Voiceover Unified Chain 4.1.7, Master Pro 2.46, Reference Tone Mirror
  EQ 0.063, Loudness Meter 44.0.2, Oscilloscope 12.1, Voice-Music Probe 1.2): il pulsante **?** apre la
  sezione del plugin nella guida (con il Cue Navigator 1.11 acceso); testi di aiuto in italiano o
  inglese secondo la lingua della Suite; descrizione bilingue con i crediti Lato Cardioide.

## ZP Studio Suite 2.4.1 — 2026-10-08

- Guida della toolbar con le icone nuove, l'installazione con *32 Installa* e riavvio di REAPER, e il
  bordo che diventa verde acqua quando lo strumento è aperto (un secondo clic lo chiude).
- Menu OSARA del Gobbo con gli stessi nomi della barra comandi (Parola per parola, Scorrimento
  continuo, Conto alla rovescia, Pannello note, Tracce visibili, Nuova battuta); i numeri delle voci
  restano quelli di prima.

## ZP Studio Suite 2.4.0 — 2026-10-08

- 29 ZP Trascrizione: tendine **Modello** e **Lingua** (italiano, inglese, francese, tedesco,
  spagnolo, portoghese, cinese, giapponese, coreano, russo, automatica, o *Altra…* per qualsiasi
  codice; avviso se Parakeet non conosce la lingua). La riga della tappa dice «5 selezionati: 3 da
  trascrivere, 2 già fatti». Abbina con più item non apre il Finder e salta quelli già abbinati.
  Ogni file ricorda con che modello e lingua è stato trascritto.
- Trascrivi, Ritrascrivi e Traduci lavorano **in background**: chiudere la finestra non li ferma, il
  titolo mostra l'avanzamento e alla fine arriva una notifica di macOS. Un file che non riesce non
  ferma gli altri.
- **Traduci** (facoltativo): l'SRT accanto al file viene tradotto da un agente AI con il tuo login
  (Codex) in `Nome.it.srt`, con gli stessi tempi; se l'agente cambia le battute il file non viene
  scritto. Nel Gobbo ogni traduzione è un flusso in più («Kevin · IT») agganciato agli stessi marker:
  segue i tagli e la ricerca trova le frasi tradotte. Serve ZP Speech aggiornato
  (`bash speech-engine/install_macos.sh`).
- Toolbar ZP con icone nuove: il disegno resta uguale e il bordo diventa verde acqua quando lo
  strumento è aperto; un secondo clic sull'icona chiude la finestra. Si applica con 32 Installa.
- SOLO Recorder: i comandi REAPER anche in Mini; cambiando vista la finestra cresce verso il basso.
- SOLO Web: timeline con regioni, marker e take della traccia armata; un tocco porta il cursore,
  zoom con − + *Tutto*, rotella, pizzico o trascinamento, e la vista segue la testina.

## ZP Studio Suite 2.3.7 — 2026-10-08

- Gobbo, ricerca: trova le parole dall'inizio (`ved` trova *vedere*), senza badare a maiuscole e
  accenti; tra virgolette cerca la parola esatta. Sotto il campo c'e' l'elenco dei risultati in
  ordine di timeline, con timecode e file audio di ogni battuta; clic, frecce, `<` e `>` portano
  alla battuta.
- Gobbo verticale, Sostituisci: cambia solo parole intere e gli accenti contano (`è` non tocca
  *e*). Un clic mostra la parola, il secondo la cambia e resta li'; Tutti chiede conferma e si
  annulla con un solo Undo.
- Gobbo verticale: Modifica battuta si apre sotto Cerca e la battuta in modifica e' segnata nel
  copione. Il pannello note elenca tutte le note ed e' scorrevole: clic porta la timeline, doppio
  clic modifica, bollino OK per segnarle fatte o riaprirle, x a sinistra per cancellarle. In
  Modifica la rotella scorre il testo. La barra comandi e' divisa in blocchi, con caselle e il
  flusso testi a tendina.
- Gobbo orizzontale: flusso testi a tendina.

## ZP Harmonic Space Carver 2.6.5, Cue Navigator 1.10, ZP Studio Suite 2.3.6 — 2026-10-07

### ZP Harmonic Space Carver 2.6.5
- ELIMINA nella fila dei cue: clic su un punto per sceglierlo, Cmd/Ctrl+clic per aggiungerne
  altri, Shift+clic per un intervallo; toglie i cue e i loro marker `#HSC`, UNDO li rimette.
- GUI Advanced in tre colonne: VOCE con LIVELLI sotto, CARVER con BANDE, VCA con il meter VCA,
  GLUE e USCITA. Min Duck (giallo) e Max Duck (arancio) stanno accanto al meter VCA, collegati
  alle loro linee; il pomello Glue sta con il suo meter.

### Cue Navigator 1.10
- Ogni progetto aperto in una scheda tiene i suoi cue e i suoi marker `#HSC`: al cambio di scheda
  l'helper rilegge subito i Carver di quel progetto.

### ZP Studio Suite 2.3.6
- Marker degli item protetti: trascinando sopra un take marker prendi l'item, Shift+trascina sposta
  il marker. Lo imposta 32 Installa; nel 33 Benvenuto la riga "Marker degli item" ha Proteggi e
  Ripristina standard.

## ZP Studio Suite 2.0.0 — 2026-10-04

- Trascrizione con whisper (29 ZP Trascrizione), gobbo che segue i tagli, Ritrascrivi.
- ZP SRT (30), SRT dall'audio (31), Info item SRT e Esporta SRT rinnovati.
- Marker: 04 e 14 uniti; marker di servizio mai trattati come testo.
- 32 Installa toolbar ed effetti (toolbar, catene di effetti, preset).
- SOLO Recorder: pulsantiera a zone, pomelli, guida rapida, Telecomando, lucchetto REC.
- Chain Builder: BUS Chain con preset Voiceover, Master Pro con Flat -19.
- Report minuti voce: report della sola sessione.
- ZP Stagekeeper Dialogue Director 2.5.0 (la 2.3.1 resta come riferimento in
  `gobbo_ricerca_battuta/backup/`).

## ZP Harmonic Space Carver 2.6.4, ZP Studio Suite 2.0.1 — 2026-10-05

### ZP Harmonic Space Carver 2.6.4 (con Cue Navigator 1.9 e azioni ZP HSC)
- GUI nell'ordine del segnale (Voce, Carver, VCA, Bande, VCA/Glue, Uscita, Livelli), un solo motore:
  Simple mostra i controlli principali dell'Advanced; SCORE / FLAT / VOCAL sono punti di partenza.
- Sidechain da tre fonti (3/4, 5/6, 7/8) legate al routing vero, con spia per fonte.
- Anticipo (lookahead compensato), Knee, Apertura del cue, Min/Max Duck a forbice; vista DOCK.
- Quick return cues: funzionano in ogni vista e a finestra chiusa; marker `#HSC` sul righello
  (lane 4) che si spostano liberamente ma si aggiungono e tolgono solo dal Carver; ogni cue e'
  ancorato alla voce che ha sotto e diventa rosso se la voce si sposta (RIALLINEA / TIENI QUI).
- Helper "ZP Harmonic Space Carver Cue Navigator" (da avviare all'apertura di REAPER) e azioni
  da tastiera: Cue aggiungi o togli, Successivo, Precedente, Annulla, Riallinea, Mostra tracce voce.
- Ogni Carver ha un numero unico: piu' progetti aperti in schede non si mescolano.
- Preascolto segnalato e spento alla riapertura; livelli sempre sull'uscita vera.
- Dettagli e revisione: `docs/PROGETTO_Harmonic_Carver_2.6_cue_marker.md`, `docs/DEBUG_Harmonic_Carver_2.6.md`.

### ZP Studio Suite 2.0.1
- 17 Gestore Progetto: niente regioni da item di testo o vuoti; pulsanti Video e No muti.
- 19 Report minuti voce: pulsante No muti.

## Non rilasciato

### Corretto
- Quattro effetti non entravano nell'indice ReaPack: Reference Tone Mirror EQ Pro,
  Oscilloscope 16ch, Harmonic Space Carver e Subliminal Presence Layer White.
  Causa: `reapack-index` riconosce come tag anche `author:` e `version:` scritti
  senza chiocciola nell'intestazione JSFX storica, e le righe di commento indentate
  che li seguivano li rendevano multilinea. Entrambi i tag devono stare su una riga
  sola. Le vecchie righe sono state rinominate in `// Autore:` e `// Versione:`:
  l'informazione resta leggibile, il conflitto sparisce.
- Stessa correzione applicata anche a Loudness Meter e Stagekeeper, che passavano
  per caso ma avevano lo stesso difetto latente.

### Aggiunto
- Repository unico per gli 11 effetti della Suite, in tre categorie: ZP Voce, ZP Master, ZP Misura.
- `LICENSE` (GPLv3) e `NOTICE.md` con la catena di attribuzioni del DSP di terzi.

### Corretto
- **ZP Voice-Music Probe**: la copia in uso nella cartella di lavoro era precedente a
  quella distribuita e non conteneva il fix *v1.1 Role Switch* (cambio ruolo
  VOICE/MUSIC a trasporto fermo, da GUI e da Chain Builder). Eletta come fonte la
  versione corretta.

### Aggiunto
- Pipeline ReaPack: `.reapack-index.conf` e due workflow GitHub Actions.
  `check` valida i pacchetti a ogni push e su ogni pull request; `deploy` rigenera
  `index.xml` a ogni push su master e lo ricommitta da solo.
- `index.xml` iniziale con il nome "ZP Suite" — e' il nome che ReaPack mostra.
  Da qui in avanti il file lo mantiene la CI: non va modificato a mano.

### Modificato
- Rinominati sette file per togliere la versione dal nome: con ReaPack il nome del file
  e' l'identita' del pacchetto e non puo' piu' cambiare dopo la pubblicazione. La versione
  vive ora solo in `@version` e nella riga `desc:`, dove puo' crescere liberamente.
  Rinomina fatta con `git mv`: la storia dei file e' conservata.
- `ZP Subliminal Presence Layer White` mantiene "White": e' un descrittore del tipo di
  layer, non un numero di versione.

### Compatibilita'
- I file gia' installati in `Effects/ZP_Paolo Balestri JSFX/` restano dove sono e non
  vengono toccati: i progetti REAPER esistenti continuano a trovarli. I pacchetti ReaPack
  si installano in una cartella propria, quindi le due serie convivono senza collisioni.

### Note
- Import iniziale con i nomi file storici. La rinomina che toglie la versione dal nome
  avviene nel passo successivo, con `git mv`, prima della prima pubblicazione.

## ZP Studio Suite 2.1.0 — 2026-10-06

### SOLO Recorder
- Testata a icone uguale in Mini, Compact ed Expanded: salva (staccato), annulla, ripeti; Sessione SOLO o
  Telecomando; regioni take, effetti, video; viste; toolbar; nascondi REAPER; versione web; guida; puntina.
- Meter IN dall'ingresso vero della scheda e RIT dal master, in dB da -60 a 0, con picco trattenuto.
- Pre-roll di REAPER: PRE sul bordo del REC lo accende, i secondi (1-5) stanno nella toolbar.
- PAUSA fra STOP e PLAY, anche durante il REC; PLAY durante il REC mette in pausa come in REAPER.
- Marker con la bandierina e il nome scritto in una casella del pannello (Invio).
- In Telecomando la traccia da armare si sceglie dal menu dell'ingresso; navigatore anche in Compact.

### SOLO Web (prototipo)
- Il SOLO nel browser (Mac, iPad, telefono) attraverso l'interfaccia web di REAPER: trasporto con pausa,
  pre-roll, meter, marker, salva/annulla/ripeti. Si apre dal globo in testata del SOLO, che prepara la
  pagina e accende il motore `ZP_SOLO_Web_Motore`.

## ZP Studio Suite 2.2.0 — 2026-10-06

- 33 Benvenuto: controllo dell'installazione. Una spia per pezzo (toolbar ed effetti, Cue Navigator del
  Harmonic Space Carver e il suo avvio con REAPER, ZP Speech, SWS, js_ReaScriptAPI, OSARA, interfaccia web)
  e il pulsante che lo sistema. Si apre da solo la prima volta che si usa uno strumento ZP; poi dall'Action
  List o dall'help.

## ZP Studio Suite 2.3.1 — 2026-10-06

- 32 Installa toolbar: toolbar ZP con le icone di REAPER (piu' due icone ZP nello stesso stile, anche per
  schermi Retina), i pulsanti della finestra video (anche dai progetti
  in sottofondo) e l'ordine della toolbar di lavoro.
- 33 Benvenuto: ZP Speech si installa con un clic (il Terminale scarica da GitHub e installa); se mancano
  Python 3.11+ o MacWhisper la riga lo dice e porta a scaricarli.

## ZP Studio Suite 2.3.2 — 2026-10-06

- 33 Benvenuto: la toolbar ZP in tre momenti chiari: da installare (Installa), da importare (Importa apre
  Customize toolbars e copia il percorso del file), pronta (dice in quale toolbar e' e la apre).
- 32 Installa toolbar: consiglia una Floating toolbar fra 1 e 16, quelle del menu View > Toolbars.

## ZP Studio Suite 2.3.4 — 2026-10-06

- 32 Installa toolbar: la toolbar "ZP Studio Suite" entra direttamente fra le toolbar di REAPER, col suo nome
  (Switch toolbar o View > Toolbars, dopo un riavvio): nella toolbar che si chiama gia' cosi', altrimenti nella
  prima libera fra 1 e 16. Le altre toolbar restano come sono; accanto a reaper-menu.ini resta un backup.
- 33 Benvenuto: toolbar da installare, da riavviare, pronta (dice in quale toolbar e' e la apre).

## ZP Studio Suite 2.3.5 — 2026-10-06

- SOLO Web: pulsante Condividi con il link per aprire il SOLO da un altro dispositivo della stessa rete (iPad,
  telefono, altro computer), con Copia e QR; Wi-Fi e cavo insieme. Il globo del SOLO Recorder copia il link.
