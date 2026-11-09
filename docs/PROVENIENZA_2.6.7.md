# Provenienza dei file acquisiti per ZP Studio Suite 2.6.7

Acquisizione: 2026-11-09 dall’installazione REAPER locale. La base del pacchetto installato è 2.6.6; alcuni file comprendono modifiche beta locali. Versioni interne e @version dei componenti restano indipendenti dal numero della Suite.

Lo snapshot byte per byte precedente alla copia è conservato in `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/2026-11-09_Pre-release-2.6.7_from-REAPER/` con `MANIFEST.md` e SHA-256.

| File nel repository | Proprietà / pacchetto d’origine | Versione interna rilevata |
|---|---|---|
| `ZP Studio Suite/17_Crea_Regioni_Export_da_Item_Nominati.lua` | Suite 2.6.6 locale / Gestore Progetto | 1.0.5 |
| `ZP Studio Suite/19_Report_Minuti_Voce.lua` | Suite 2.6.6 locale / Report Minuti Voce | 1.0.6 |
| `ZP Studio Suite/33_Benvenuto_Controllo_Installazione.lua` | Suite 2.6.6 locale / Benvenuto | Segue la versione del pacchetto principale |
| `ZP Studio Suite/remote/ZP_Remote_Crea_Pacchetto.lua` | Suite 2.6.6 locale / ZP Remote | 1.0 |
| `ZP Studio Suite/remote/zp_remote_import_logic.lua` | Suite 2.6.6 locale / helper ZP Remote | Non dichiarata; `@noindex` |
| `ZP Studio Suite/remote/zp_remote_importer.lua` | Suite 2.6.6 locale / helper ZP Remote | Non dichiarata separatamente |
| `ZP Studio Suite/remote/zp_remote_preflight.py` | Suite 2.6.6 locale / helper ZP Remote | Non dichiarata separatamente |
| `ZP Studio Suite/help/index.html`, `help/en/index.html`, `lang/en.txt` | Suite 2.6.6 locale | Risorse del pacchetto |
| `ZP Voce/ZP Harmonic Space Carver Cue Navigator.lua` | Harmonic Space Carver 2.6.10 locale | 1.14 |
| `ZP Voce/ZP Harmonic Space Carver.jsfx` | Harmonic Space Carver 2.6.10 locale | 2.6.10 |

La versione d’origine descrive il pacchetto installato da cui proviene il file; non certifica da sola quando il singolo file sia stato scaricato o se sia stato modificato localmente. Per questo la cattura è datata e hashata, e la destinazione 2.6.7 è esplicita.

## Correzione GUI Harmonic Space Carver — 2026-11-09

Versione candidata 2.6.10 mantenuta; Helper 1.14 invariato. Intervento richiesto da Paolo sulla grafica precedente, con sistemazione C/S/M/L, etichette Rampa/Personalizza e Voice Ret. Corretta anche la parentesi mancante in @block: nessuna variazione agli algoritmi DSP o allo stato dei cue. Sorgente e installazione REAPER allineati. Snapshot e diff: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Harmonic Space Carver/2026-11-09_HSC-2.6.10-GUI-Candidate`. Verifiche statiche delle sezioni e dei delimitatori; nessun collaudo runtime in questa fase.

## Tempi HSC per marker — 2026-11-09

Su richiesta di Paolo, la memoria per marker ora comprende Rampa e durata Custom, con richiamo nei pomelli e tempi usati dal cue in riproduzione. Layout conservato; @sample byte identico. Aggiornati JSFX e helper candidati (2.6.10 / 1.14), formato seriale 2611 con migrazione dai precedenti. Installati nel REAPER principale. Snapshot, diff e hash: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Harmonic Space Carver/2026-11-09_HSC-Marker-Timings-Candidate`. Sintassi Lua e struttura JSFX controllate staticamente; nessun collaudo runtime in questa fase.

## Gobbo (testo temporizzato) e ZP Speech — 2026-11-09

- **Gobbo Verticale e Orizzontale (`02_Gobbo_Verticale.lua`, `03_Gobbo_Orizzontale.lua`)**: integrata la funzione `+ Testo temporizzato` (`+ Timed text`), WPM configurabile, calcolo durata item con righe vuote e parole, riposizionamento su player, e aggiornamento documentazione (`help/index.html`, `help/en/index.html`, `lang/en.txt`).
- **ZP Speech Engine**: collaudato con provider locale `OpenAIWhisperProvider` in ambiente dedicato Python 3.11 su macOS, CLI `models`, `download-model`, `doctor --engine`, test coverage 98.45% (203 passati), basedpyright strict, ty, ruff, wheel. Script `29_ZP_Trascrizione.lua` e `33_Benvenuto_Controllo_Installazione.lua` allineati e verificati.
- **Battezzatura a 2.6.7**: `00_Apri_Help_ZP_Studio_Suite.lua` aggiornato a `@version 2.6.7`; allineata l'installazione locale REAPER (`/Users/paolob/Library/Application Support/REAPER`) con snapshot di backup precauzionale in `REAPER/ZP_StudioSuite_Backups/pre_2.6.7_alignment_2026-11-09`.

