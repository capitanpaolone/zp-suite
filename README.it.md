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
- **ZP Misura** — loudness meter, oscilloscopio e sonde passive del segnale.

La 2.6.6 estende la copia automatica e Sincronizza ora di Render & Copy a Windows (serve js_ReaScriptAPI) e Linux (servono find e stat). La 2.6.5 aggiorna la guida del Solo Recorder per chiarire il collegamento tra i pacchetti creati con ZP Remote e Dubbertools. La 2.6.4 ha aggiunto Render & Copy, il collegamento Dubbertools in SOLO Web e il tool REAPER di ZP Remote per esportare pacchetti e importare consegne. Per l’export ZP Remote servono Python 3 e ffmpeg.


La ZP Studio Suite 2.6.7 è in preparazione e non è pubblicata. Il checkout candidato usa aggiornamenti provenienti dall’installazione REAPER locale; vedi `docs/PRE_RELEASE_2.6.7.md` e `docs/PROVENIENZA_2.6.7.md`.

## Non incluso in questa versione

ZP Montaggio Parlato (prototipo), ZP BrownSlope Dynamic Guard, ZP BrownSlope Prism e ZP Speech Engine sono ancora in lavorazione e non fanno parte di questa versione ReaPack.

## Guide e sorgenti

- [Guida italiana della Suite](ZP%20Studio%20Suite/help/index.html)
- [English Suite guide](ZP%20Studio%20Suite/help/en/index.html)
- [Lato Cardioide — Strumenti](https://latocardioide.it/strumenti/)
- [Indice del repository ReaPack](https://github.com/capitanpaolone/zp-suite/raw/master/index.xml)

La descrizione del pacchetto ReaPack e le note di rilascio sono in italiano e in inglese. Il README principale di GitHub è in inglese; chi preferisce l’italiano può scegliere questo file e impostare la lingua della Suite da **33 Benvenuto**.

## Licenze

La maggior parte dei componenti è GPL-3.0-or-later; alcuni meter derivati da REAPER sono LGPL-2.1-or-later. Vedi [LICENSE](LICENSE), [LICENSE-LGPL-2.1.txt](LICENSE-LGPL-2.1.txt) e [NOTICE.md](NOTICE.md).
