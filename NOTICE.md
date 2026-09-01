# NOTICE — attribuzioni e licenze a monte

ZP Suite è distribuita nel suo insieme sotto **GNU GPL versione 3 o successiva**
(testo completo in `LICENSE`). Due effetti e una libreria di terzi restano sotto
**LGPL 2.1**, la licenza con cui sono stati ricevuti: il testo integrale è in
`LICENSE-LGPL-2.1.txt`.

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

> Insieme a ZP Oscilloscope 16ch, questo è uno dei due file della Suite con una licenza
> a monte diversa. Entrambi mantengono la loro intestazione LGPL: la LGPL consente l'uso
> all'interno di un'opera GPLv3, ma i file in sé restano disponibili alle condizioni con
> cui sono stati ricevuti.

## ZP Oscilloscope 16ch

- **Cockos Incorporated** — effetto originale `analysis/gfxscope`,
  Copyright (C) 2007 — **LGPL**
- **Paolo Balestri** — riscrittura interfaccia, gestione canali e memoria — LGPL

## ZP Voiceover Unified Chain — riferimenti di studio

L'espansore downward è ispirato al comportamento del **Tukan DL24**. La catena nel suo
complesso è stata sviluppata studiando plugin di **Stillwell**, **Tukan** e **Geraint
Luff**. Nessun codice di questi autori è incluso: sono riferimenti di progetto, non
componenti.

## ZP Studio Suite — supporto screen reader su Windows

- **NV Access Limited e contributori** — *NVDA Controller Client API* — **LGPL 2.1**
- File incluso: `ZP Studio Suite/nvdaControllerClient64.dll`
- Libreria originale, non modificata. Testo della licenza in `LICENSE-LGPL-2.1.txt`.
- Sorgente e documentazione:
  https://github.com/nvaccess/nvda/tree/master/extras/controllerClient

Fornisce parlato e braille agli script della Suite attraverso NVDA. Gli script
Lua della Suite sono distribuiti sotto GPLv3 come il resto del repository; il
DLL resta alle condizioni con cui è stato ricevuto.

---

## Materiale di terze parti NON incluso nella Suite

Nella cartella di lavoro dell'autore sono presenti 27 emulazioni di console di **chmaha**
(GPLv3, DSP a monte di Airwindows) usate come materiale di studio. Non fanno parte di
questo repository e non vengono distribuite.

---

Se una attribuzione è incompleta o imprecisa, apri una issue: verrà corretta.
