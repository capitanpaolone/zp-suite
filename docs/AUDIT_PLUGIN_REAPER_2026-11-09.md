# Audit plugin ZP: tag 2.6.6, REAPER locale e candidata 2.6.7

Data: 2026-11-09. Confronto read-only tra il tag immutabile `v2.6.6`, `/Users/paolob/Library/Application Support/REAPER/Effects/ZP Suite/` e il checkout locale `zp-suite-2.6.7`.

## Esito breve

- Nessun duplicato JSFX nel pacchetto pubblicato 2.6.6 o nella cartella ZP installata in REAPER: nomi file, `desc:` e hash SHA-256 sono univoci all’interno dei rispettivi insiemi.
- Il pacchetto pubblico contiene 11 JSFX. Nella REAPER ci sono 13 JSFX ZP: gli stessi 11 più i due prototipi ZP Lab, esclusi dal ReaPack e non inclusi nella 2.6.7 attuale.
- Un solo plugin JSFX cambia dalla 2.6.6 alla 2.6.7 candidata: Harmonic Space Carver, da 2.6.8 a 2.6.10. Il suo Cue Navigator, script Lua associato ma non un JSFX, passa da 1.13 a 1.14. Entrambi sono già copiati nella candidata.
- Non risulta un nuovo plugin JSFX installato in REAPER che manchi dal sorgente 2.6.6 o dalla candidata.

## JSFX inclusi nel pacchetto 2.6.6

| Componente | Tag 2.6.6 | REAPER locale | Stato nella candidata 2.6.7 |
|---|---:|---:|---|
| ZP Master Pro | 2.46 | 2.46 | Invariato |
| ZP Reference Tone Mirror EQ Pro | 0.063 | 0.063 | Invariato |
| ZP Loudness Meter Multichannel | 44.0.2 | 44.0.2 | Invariato |
| ZP Oscilloscope 16ch | 12.1 | 12.1 | Invariato |
| ZP Voice-Music Probe | 1.2 | 1.2 | Invariato |
| ZP BUS Chain | 1.3.1 | 1.3.1 | Invariato |
| ZP Harmonic Space Carver | 2.6.8 | 2.6.10 | **Aggiornato a 2.6.10** |
| ZP Spoken Finish | 3.10.0 | 3.10.0 | Invariato |
| ZP Stagekeeper Dialogue Director | 2.5.1 | 2.5.1 | Invariato |
| ZP Subliminal Presence Layer White | 3.2.2 | 3.2.2 | Invariato |
| ZP Voiceover Unified Chain | 4.1.7 | 4.1.7 | Invariato |

Il Cue Navigator associato al Carver è uno script Lua separato: `@version 1.13` nel tag e `@version 1.14` nella REAPER; la 1.14 è già nella candidata.

## Presenti in REAPER ma esclusi dalla release

- `ZP Lab/ZP BrownSlope Dynamic Guard.jsfx` — senza `@version`; escluso da `.reapack-index.conf` e registrato come prodotto in maturazione.
- `ZP Lab/ZP BrownSlope Prism.jsfx` — senza `@version`; escluso da `.reapack-index.conf` e registrato come prodotto in maturazione.

Questi due non entrano nella 2.6.7 salvo decisione esplicita di Paolo di far uscire i prodotti dalla maturazione.

## File storici nel repository

Il repository conserva quattro JSFX sotto `gobbo_ricerca_battuta/backup/`: Harmonic Space Carver 2.4.3, 2.4.6 e 2.6.4, più Stagekeeper 2.3.1. La cartella `gobbo_ricerca_battuta` è esclusa dall’indice ReaPack: sono snapshot storici di backup, non duplicati installati o distribuiti.

## Metodo e limiti

Il confronto ha verificato i percorsi e le versioni negli header, i `desc:` e gli SHA-256. Nessun file è stato modificato durante l’audit e non sono stati eseguiti test o collaudi audio. La versione installata è considerata riferimento beta da Paolo; il suo numero da solo non prova la provenienza di download del singolo file.
