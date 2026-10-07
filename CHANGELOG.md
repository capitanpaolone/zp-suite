# Changelog — ZP Suite

Le versioni dei singoli effetti sono indipendenti: le trovi nell'intestazione di
ciascun file e nel gestore pacchetti. Questo file registra la storia della Suite
nel suo insieme.

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
