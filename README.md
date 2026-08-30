# ZP Suite

Effetti JSFX per REAPER dedicati a voiceover, doppiaggio, podcast e broadcast.
Sviluppati da **Paolo Balestri** — [latocardioide.it](https://latocardioide.it) ·
social@paolobalestri.com

Ogni plugin ha una doppia vista: **GUI** grafica e **JSFX** a lista parametri.
La vista JSFX è il canale con cui OSARA legge i controlli, e diversi effetti espongono
grandezze di sola lettura (`[Read]`) proprio perché un lettore di schermo possa
annunciarle. L'accessibilità è un requisito di progetto, non un'aggiunta.

## Installazione

*(disponibile dalla Fase 3 — ReaPack)*

In REAPER: **Extensions → ReaPack → Import repositories**, e incolla:

```
https://github.com/capitanpaolone/zp-suite/raw/master/index.xml
```

Poi **Extensions → ReaPack → Browse packages**, cerca `ZP` e installa quello che serve.
Gli aggiornamenti arrivano da lì, con changelog e possibilità di tornare indietro.

## Cosa c'è dentro

### ZP Voce

| Effetto | Cosa fa |
|---|---|
| **ZP Voiceover Unified Chain** | Catena completa per la voce: Input Smart → Gate/Expander → 1175 → LA2 → MajorTom → Brown Guard → Limiter/Clipper → Output auto-trim → Safety Limiter. Sei profili di partenza, moduli accendibili singolarmente. |
| **ZP BUS Chain** | La stessa catena sul bus, più il motore ANA di colorazione console (CALDO / CORPO / APERTO). |
| **ZP Spoken Finish** | Exciter e de-exciter armonico: pari e dispari da −100 a +100 %. Profili Voice Base e Extreme Trailer (Voice of God, Cinema Air). Limiter true-peak. |
| **ZP Harmonic Space Carver** | Spazio fra voce e musica: carving dinamico multibanda, ducker VCA e Speech State Engine che riconosce pause e respiri. |
| **ZP Stagekeeper Dialogue Director** | Automixer per dialogo a due canali, gate con trigger assoluto o delta sul rumore di fondo, tilt EQ e solo per lato. |
| **ZP Subliminal Presence Layer** | Layer di presenza calibrato su cosa sopravvive alla codifica lossy. Tre controlli. |

### ZP Master

| Effetto | Cosa fa |
|---|---|
| **ZP Master Pro** | Processore di master: Tape Glue → Glue Matrix Compressor → Tone Guard → Lookahead Limiter, più metering LUFS/LRA/RMS/TP, auto-trim e Target Engine con sette profili di consegna. |
| **ZP Reference Tone Mirror EQ Pro** | EQ di matching su un segnale di riferimento, con stadio armonico, AGC e strumenti diagnostici (Delta EQ, Delta Harm, Null Hunter). |

### ZP Misura

| Effetto | Cosa fa |
|---|---|
| **ZP Loudness Meter Multichannel** | LUFS-I/S/M secondo ITU-R BS.1770, LRA, True Peak con oversampling, RMS-M, fino a 64 canali. |
| **ZP Oscilloscope 16ch** | Oscilloscopio a 16 canali con nomi di traccia editabili e quattro modalità canale. |
| **ZP Voice-Music Probe** | Telemetria passiva: misura RMS, peak, crest, densità, brillantezza e attività di parlato senza toccare il segnale. Va messo come ultimo FX del bus. |

## ZP Shared Bus

Gli effetti si riconoscono fra loro attraverso una memoria condivisa
(`gmem=ZPVoiceoverSharedBus`). Ogni plugin pubblica un battito con la propria identità;
Master Pro li legge tutti e mostra lo stato della catena. Il Probe pubblica le metriche
che il Target Engine confronta con il profilo di consegna scelto.

È diagnostica: nessun plugin modifica i parametri di un altro.

Slot: `10` catena · `20` Space Carver · `30` Spoken Finish · `40` Master Pro ·
`50` Probe voce · `60` Probe musica.

## Licenza

GPLv3 o successiva — vedi [`LICENSE`](LICENSE).
Le attribuzioni del DSP di terzi sono in [`NOTICE.md`](NOTICE.md).
