# Traccia — pagina ZP Suite su Lato Cardioide

Brief operativo per la stesura della pagina. Contiene il taglio, la struttura,
i fatti tecnici verificati e i vincoli. I fatti qui dentro sono stati letti dai
sorgenti e dal repository: **non vanno reinventati né arricchiti a memoria**.

---

## 1. Cosa produrre

Una pagina dedicata alla ZP Suite su **latocardioide.it**, coerente con la struttura
del sito esistente (build statica da `studio/scripts/build_public_site.py` verso
`public-preview/`). La pagina va creata nel formato sorgente che il sito già usa per
le altre pagine interne, non inventando un formato nuovo: **prima leggere una pagina
interna esistente e replicarne l'impianto**.

---

## 2. Contesto e confine — leggere prima di scrivere

**Lato Cardioide è un giornale di bordo sul lavoro vocale, non un portfolio.**
È esplicitamente distinto da paolobalestri.it. Questa pagina non deve diventare una
pagina prodotto: niente linguaggio di vendita, niente "scopri", "potenzia", "la
soluzione definitiva", niente elenco di benefici. Il registro è quello di chi racconta
attrezzi che si è costruito, non di chi li piazza.

**La ZP Suite** è una raccolta di undici effetti JSFX per REAPER scritti da Paolo,
dedicati a voiceover, doppiaggio, podcast e broadcast. Sono gratuiti, GPLv3, e da oggi
distribuiti tramite ReaPack.

---

## 3. Taglio e voce

**Ibrido: racconto + catalogo.** Si apre con il perché, si chiude con il come si
installano. Il catalogo sta in mezzo, non in cima.

Prima persona, italiano, frasi piene. Nessun elenco puntato nell'apertura: i punti
elenco cominciano solo dal catalogo. Tono sobrio e concreto, lo stesso degli articoli
già pubblicati sul sito — **andarli a leggere per calibrare la voce prima di scrivere**.

---

## 4. Struttura della pagina

### 4.1 Apertura — perché esistono (2-3 paragrafi)

Il nucleo del racconto, da sviluppare senza inventare aneddoti:

- Il voiceover e il doppiaggio hanno problemi che i plugin generalisti non conoscono.
  Il respiro fra due frasi, che un ducker normale interpreta come silenzio e riempie di
  musica. Il livello che non deve solo "suonare bene" ma cadere dentro una finestra di
  consegna precisa e diversa per ogni committente. Due microfoni in dialogo con rumori
  di fondo diversi fra loro.
- Il secondo motivo è l'accessibilità. Lavorare in REAPER con un lettore di schermo
  significa che un meter grafico non esiste: se un valore vive solo nei pixel, per chi
  usa OSARA quel valore non c'è. Da qui la doppia vista GUI/JSFX presente in ogni
  plugin e i parametri di sola lettura che esistono apposta perché un lettore di schermo
  possa annunciarli. **Non è un adattamento aggiunto dopo: è un vincolo che ha dato
  forma all'architettura.** Questo è il punto più caratteristico dell'intero progetto
  e merita spazio.

### 4.2 Come sono fatti (1-2 paragrafi)

Tre livelli, spiegati in prosa:

- **Moduli atomici** — un compressore, un gate, un limiter: poche centinaia di righe
  ciascuno, leggibili.
- **Catene** — gli stessi moduli fusi in un unico plugin che copre tutto il percorso del
  segnale, fino a quasi seimila righe.
- **L'infrastruttura** — la parte più insolita: i plugin si riconoscono fra loro
  attraverso una memoria condivisa, e uno di essi misura il risultato reale della catena
  e lo confronta con il profilo di consegna scelto. Il sistema dice dove sta il problema
  invece di correggerlo di nascosto. Questa scelta — indicare, non intervenire — va
  detta esplicitamente perché è una posizione, non un dettaglio.

### 4.3 Il catalogo — tre sezioni

Speculare alla struttura del repository. Una riga per effetto, **senza numeri di
versione** (vedi regole al punto 6). I testi qui sotto sono verificati: si possono
accorciare o riscrivere nel tono, non contraddire.

**ZP Voce**

- **ZP Voiceover Unified Chain** — catena completa per la voce: gain d'ingresso con
  cattura automatica del livello, gate/expander, tre compressori in serie, controllo
  della pendenza spettrale, limiter e controllo automatico del livello finale. Sei
  profili di partenza, ogni modulo accendibile singolarmente.
- **ZP BUS Chain** — la stessa catena portata sul bus, più un motore di colorazione da
  console ridotto a tre caratteri operativi: caldo, corpo, aperto.
- **ZP Spoken Finish** — exciter e de-exciter armonico. Aggiunge o toglie calore e
  presenza; ha un profilo normale e uno da trailer cinematografico.
- **ZP Harmonic Space Carver** — crea spazio fra voce e musica. Tre meccanismi insieme:
  scavo dinamico multibanda, ducker, e un motore che riconosce le pause e i respiri del
  parlato, così la musica non risale dentro l'inspirazione fra due frasi.
- **ZP Stagekeeper Dialogue Director** — automixer per dialogo a due canali, con gate che
  può lavorare su soglia fissa o sulla differenza dal rumore di fondo — utile quando i
  due microfoni hanno fondi diversi.
- **ZP Subliminal Presence Layer White** — layer di presenza calibrato su ciò che
  sopravvive alla codifica lossy. Tre controlli in tutto.

**ZP Master**

- **ZP Master Pro** — processore di master: saturazione a nastro, compressione di
  collante, controllo tonale dinamico e limiter con lookahead. In più il metering di
  loudness e un motore che confronta il risultato con sette profili di consegna
  (voiceover, ADR, e-learning, podcast, spot, radio).
- **ZP Reference Tone Mirror EQ Pro** — equalizzatore di matching: prende un segnale di
  riferimento, ne cattura la curva e la specchia sul segnale da lavorare. È anche un
  banco di misura, con modalità per ascoltare solo l'intervento.

**ZP Misura** *(nessuno dei tre modifica il segnale)*

- **ZP Loudness Meter Multichannel** — LUFS integrato, breve e momentaneo secondo lo
  standard ITU-R BS.1770, gamma di loudness, true peak, fino a 64 canali.
- **ZP Oscilloscope 16ch** — oscilloscopio a sedici canali con nomi di traccia
  modificabili.
- **ZP Voice-Music Probe** — telemetria passiva: misura il risultato reale del bus e lo
  pubblica agli altri plugin. Va messo come ultimo effetto della catena.

### 4.4 Come si installano

ReaPack, in tre passaggi. In REAPER: *Extensions → ReaPack → Import repositories*,
incollare l'indirizzo, poi *Browse packages* e cercare `ZP`.

L'indirizzo da mostrare in un blocco copiabile:

```
https://github.com/capitanpaolone/zp-suite/raw/master/index.xml
```

> **Attenzione:** al momento della stesura la pipeline ReaPack non è ancora attiva
> (l'`index.xml` viene generato in una fase successiva). Verificare che l'indirizzo
> risponda prima di pubblicare la pagina. Se non risponde ancora, tenere la sezione
> ma segnalarla come in arrivo, senza promettere una data.

### 4.5 Chiusura

Gratuiti, GPLv3, codice pubblico. Link al repository. Una riga sul fatto che alcuni
effetti incorporano DSP di altri autori (Airwindows, chmaha, Cockos) e che le
attribuzioni stanno nel `NOTICE.md` del repository — è una cosa di cui essere espliciti,
non da nascondere.

---

## 5. Materiale già sul sito da collegare

Sul sito esistono già **articoli usciti mano a mano durante il lavoro sugli script Lua**.
Vanno cercati, letti e collegati dalla pagina: sono il giornale di bordo di cui questa
pagina è il punto d'arrivo, e sono ciò che la rende un pezzo di laboratorio invece che
una scheda prodotto.

Dove ha senso, citarli nel corpo del testo — non solo in un elenco "vedi anche" in fondo.

---

## 6. Regole ferree

1. **Nessun numero di versione in pagina.** Né degli effetti né della Suite. La pagina
   descrive cosa fa ogni cosa; i numeri vivono su GitHub e in ReaPack, dove si aggiornano
   da soli. Una pagina senza versioni non invecchia e non va risincronizzata a ogni
   rilascio.
2. **Nessun dato tecnico inventato.** Se un fatto non è in questa traccia, non va scritto.
   Niente numeri di parametri, soglie, latenze o percentuali dedotti.
3. **Niente linguaggio commerciale.** Vedi punto 2 del contesto.
4. **Niente screenshot inventati o mockup.** Se servono immagini, chiedere a Paolo.

---

## 7. Vincoli grafici

Il sito ha una direzione già decisa: **"Rivista"** — editoriale, calda, tipografica.

- **Carattere:** Georgia ovunque.
- **Palette "Temperata":** carta avorio neutro `#F2F0EA`, inchiostro freddo `#1F2B35`,
  accento ruggine `#8F4630`, ottone `#A08A6A`, filetti grigi `#CFCCC3`.
  Filetti e ornamenti in acciaio `#8F9490`, non in ottone.
- **Il meter è il segno ricorrente del sito**: si usa come marcatore di sezione. Le tre
  categorie del catalogo sono il posto naturale per usarlo.
- **Testata:** sulle pagine interne va il banner ridotto a 560 px; sotto i 720 px di
  larghezza si passa al lockup compatto. Seguire quello che fanno già le altre pagine
  interne invece di reimpostarlo.

---

## 8. Verifica prima di consegnare

- [ ] La pagina si costruisce con la build esistente senza errori.
- [ ] L'impianto è quello delle altre pagine interne (testata, marcatori, filetti).
- [ ] Nessun numero di versione compare in pagina.
- [ ] Ogni affermazione tecnica è rintracciabile in questa traccia.
- [ ] Gli articoli esistenti sui Lua sono cercati e collegati.
- [ ] L'indirizzo ReaPack è stato provato davvero.
- [ ] Il testo regge la lettura ad alta voce: è un giornale di bordo, non una brochure.
