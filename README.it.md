# ZP Suite

Una raccolta gratuita e open source di strumenti per REAPER, pensata per voiceover, doppiaggio, podcast, e-learning e broadcast. Riunisce copione e gobbi, gestione SRT, preparazione del progetto, accessibilità e strumenti audio ZP.

**Preferisci l’inglese?** Leggi il [README in English](README.md). La Suite è disponibile in italiano e in inglese.

## Scegliere la lingua

Dopo l’installazione o un aggiornamento, apri **33 Benvenuto** dalla Action List di REAPER. Alla voce **Lingua della Suite**, scegli **Italiano** o **English**. La scelta viene salvata ed è indipendente dalla lingua di REAPER. I pulsanti `?` aprono la guida nella lingua selezionata.

## Installazione con ReaPack

1. In REAPER, scegli **Extensions → ReaPack → Import repositories**.
2. Aggiungi questo indirizzo del repository:

   `https://github.com/capitanpaolone/zp-suite/raw/master/index.xml`

3. Scegli **Extensions → ReaPack → Browse packages**, cerca **ZP** e installa **ZP Studio Suite** e gli effetti ZP che ti servono.
4. Sincronizza i pacchetti per ricevere gli aggiornamenti.

La Suite funziona anche con un’installazione pulita di REAPER. SWS, js_ReaScriptAPI e OSARA sono facoltativi: aggiungono funzioni quando disponibili.

## Contenuto

- **ZP Studio Suite** — gobbi, import/export e reference SRT, strumenti di progetto, preparazione mixdown, report minuti voce, Voice Cleaner e flussi accessibili.
- **ZP Voce** — catene vocali, strumenti per dialoghi e gestione voce/musica.
- **ZP Master** — strumenti per mastering e confronto timbrico.
- **ZP Misura** — loudness meter, oscilloscopio, sonde passive del segnale e ZP BrownSlope Prism, analizzatore passivo della pendenza brown.

La 2.6.6 estende la copia automatica e Sincronizza ora di Render & Copy a Windows (serve js_ReaScriptAPI) e Linux (servono find e stat). La 2.6.5 aggiorna la guida del Solo Recorder per chiarire il collegamento tra i pacchetti creati con ZP Remote e Dubbertools. La 2.6.4 ha aggiunto Render & Copy, il collegamento Dubbertools in SOLO Web e il tool REAPER di ZP Remote per esportare pacchetti e importare consegne. Per l’export ZP Remote servono Python 3 e ffmpeg.


La 2.6.7 distribuisce **ZP Magic Voice LAB 1.2.0-lab3**, l’unica versione corretta, come effetto separato della categoria **ZP Voce**. **ZP Magic Voice 1.2.0** senza suffisso LAB è un prototipo archiviato ed escluso dal pacchetto. Per installarlo, seleziona ZP Magic Voice LAB in ReaPack insieme a ZP Studio Suite. [Guida pratica](ZP%20Studio%20Suite/help/magic_voice_lab.html).

La versione 2.6.8 include: **Fissa negli item** trasferirà solo i marker selezionati sulla timeline; quelli operativi, come i cue `#HSC` di Harmonic Space Carver, resteranno al loro posto. Include inoltre **ZP Magic Voice LAB 1.2.3** (rotori DRC `FREQ` centro + `OCT` ottave retrocompatibili, monitor reali continui su `DRC`, `DYN EQ` `±5 / ±12 dB` e `DYN BAL` `±6 / ±12 dB`, delta globale lampeggiante con auto-off a 30 s, `D·MOLLA` esteso per singolo stadio, suggerimenti su blocchi da 4 s di parlato attivo, tema solo cromatico `CHIARO / SCURO` e controlli DRC sempre visibili), **ZP BrownSlope Prism 1.1** (corridoio verde `±1,5 / ±3 dB`, riempimento differenziale caldo/freddo, traccia `Live`, barre bipolari per zona, livella pendenza e tema Scuro/Chiaro), **ZP Loudness Meter Multichannel 45.0** (GUI vertical-first anti-deriva con `TARGET` libero + `SEGUI QUI` / `LOCK NOW`, fascia verde `±LU`, nastro `DERIVA 60s` congelato in pausa, peak-hold reale, 4 viste responsive incluso embedded TCP/MCP con `LUFS-I`/`TP` e tema Scuro/Chiaro) e lo **storico scorrevole** nel pannello `STATO` di **ZP Render & Copy**.

La ZP Studio Suite 2.6.7 aggiunge ZP Consolidate, che raccoglie in Media le sorgenti dei take e gli SRT/VTT registrati nel progetto senza convertire i media. L’elenco completo delle modifiche è nel [changelog](CHANGELOG.md).

## Beta in questa versione

- **ZP Clean & Paint (BETA)**: ReaPack installa le action REAPER. Il motore ZP Voice Model Lab, l'ambiente Python, i preset e i modelli restano esterni; servono installazione e percorso configurato.
- **ZP Montaggio Parlato (BETA)**: richiede ZP Studio Suite e ZP Speech dal 33 Benvenuto; la versione corrente è collaudata su macOS. PDF: `pdftotext` (Poppler). Incolla: SWS.
- **ZP BrownSlope Dynamic Guard (BETA)** e **ZP Click & Attack Softener (BETA)**: effetti separati, da provare su sessioni e copie di lavoro. Il Cue Navigator serve solo per il pulsante `?` e la guida.

ZP Speech (il motore di trascrizione usato da Trascrivi, 29) non è nel pacchetto ReaPack: si installa dal Benvenuto (33), che lo scarica da GitHub. Su macOS usa MacWhisper o OpenAI Whisper; su Windows e Linux usa OpenAI Whisper locale ed è ancora **sperimentale**.

## Guide e sorgenti

- [Guida italiana della Suite](ZP%20Studio%20Suite/help/index.html)
- [Guida dei pacchetti BETA](ZP%20Studio%20Suite/help/lab.html)
- [English Suite guide](ZP%20Studio%20Suite/help/en/index.html)
- [Lato Cardioide — Strumenti](https://latocardioide.it/strumenti/)
- [Indice del repository ReaPack](https://github.com/capitanpaolone/zp-suite/raw/master/index.xml)

La descrizione del pacchetto ReaPack e le note di rilascio sono in italiano e in inglese. Il README principale di GitHub è in inglese; chi preferisce l’italiano può scegliere questo file e impostare la lingua della Suite da **33 Benvenuto**.

## Licenze

La maggior parte dei componenti è GPL-3.0-or-later; alcuni meter derivati da REAPER sono LGPL-2.1-or-later. Vedi [LICENSE](LICENSE), [LICENSE-LGPL-2.1.txt](LICENSE-LGPL-2.1.txt) e [NOTICE.md](NOTICE.md).
