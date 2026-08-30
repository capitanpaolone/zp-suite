# NOTICE — attribuzioni e licenze a monte

ZP Suite è distribuita nel suo insieme sotto **GNU GPL versione 3 o successiva**
(testo completo in `LICENSE`).

Alcuni effetti incorporano o derivano da DSP di terzi. Questo file elenca la catena
di provenienza di ciascuno, come dichiarata nell'intestazione dei sorgenti.

---

## ZP BUS Chain — motore ANA (bus color)

- **Chris Johnson / Airwindows** — DSP originale *BussColors4* — licenza MIT
- **chmaha** — port JSFX *Chloe Console Colors* — GPLv3
- **Paolo Balestri** — integrazione e modifiche — GPLv3

Il motore ANA è la riduzione del bus-color a tre caratteri operativi
(CALDO / Lush, CORPO / Punch, APERTO / Holo), collocati prima del limiter.

## ZP Master Pro — stadio Tape Glue

- **Chris Johnson / Airwindows** — DSP originale *ToTape9* — licenza MIT
- **chmaha** — *Oxide & Seek Tape Emulation* (port JSFX) — GPLv3
- **Paolo Balestri** — adattamento nello stadio Tape Glue — GPLv3

## ZP Loudness Meter Multichannel

- **Cockos Incorporated** — effetto originale, Copyright (C) 2021 e successivi — **LGPL**
- **Paolo Balestri** — modifiche v43 / v44 — LGPL

> Questo è l'unico file della Suite con una licenza a monte diversa. Mantiene la sua
> intestazione LGPL: la LGPL consente l'uso all'interno di un'opera GPLv3, ma il file
> in sé resta disponibile alle condizioni con cui è stato ricevuto.

## ZP Oscilloscope 16ch

- **Cockos Incorporated** — scope JSFX di riferimento
- **Paolo Balestri** — riscrittura interfaccia, gestione canali e memoria

## ZP Voiceover Unified Chain — riferimenti di studio

L'espansore downward è ispirato al comportamento del **Tukan DL24**. La catena nel suo
complesso è stata sviluppata studiando plugin di **Stillwell**, **Tukan** e **Geraint
Luff**. Nessun codice di questi autori è incluso: sono riferimenti di progetto, non
componenti.

---

## Materiale di terze parti NON incluso nella Suite

Nella cartella di lavoro dell'autore sono presenti 27 emulazioni di console di **chmaha**
(GPLv3, DSP a monte di Airwindows) usate come materiale di studio. Non fanno parte di
questo repository e non vengono distribuite.

---

Se una attribuzione è incompleta o imprecisa, apri una issue: verrà corretta.
