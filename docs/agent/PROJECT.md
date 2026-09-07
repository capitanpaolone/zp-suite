# PROJECT.md — Architettura e Scopo della ZP Suite

## 1. Scopo del Progetto
La **ZP Suite** è un ecosistema professionale integrato per Cockos REAPER dedicato a:
- Doppiaggio, voiceover, audiolibri e narrazione professionale;
- Gestione integrata di copioni, sottotitoli SRT, gobbi su schermo e marker;
- Catena audio analogica/dinamica e mastering per la voce recitata;
- Accessibilità completa per attori e fonici non vedenti tramite screen reader (OSARA / NVDA).

## 2. Componenti della Suite

### A. Gli 11 Effetti Audio JSFX (Eletti e Distribuiti)
Gli 11 effetti risiedono nelle categorie ufficiali ReaPack:

#### Categoria `ZP Voce`
- **`ZP Voiceover Unified Chain.jsfx`**: Catena vocale all-in-one con gate dinamico, equalizzazione adattiva, compressione dual-stage e limiter di picco.
- **`ZP BUS Chain.jsfx`**: Processore di bus voce analogico con saturazione controllata, curve Brown Noise e trimming dinamico.
- **`ZP Spoken Finish.jsfx`**: Processore per presenza armonica e corpo spettrale (controllo VOG - Voice of God e finitura articolazione).
- **`ZP Harmonic Space Carver.jsfx`**: Intaglio frequenziale dinamico per scavare spazio spettrale alle voci su basi musicali ed effetti sonori.
- **`ZP Stagekeeper Dialogue Director.jsfx`**: Automixer intelligente per la gestione del campo sonoro e bilanciamento dialoghi a più voci.
- **`ZP Subliminal Presence Layer White.jsfx`**: Generatore di trama a bassissimo livello per dare consistenza organica al silenzio di fondo e stacchi voce.

#### Categoria `ZP Master`
- **`ZP Master Pro.jsfx`**: Processore di mastering finale per parlato con matrice di colla (Glue Matrix), limiter a inter-sample peak e controllo loudness.
- **`ZP Reference Tone Mirror EQ Pro.jsfx`**: Equalizzatore per cattura e clonazione del profilo timbrico rispetto a una traccia reference.

#### Categoria `ZP Misura`
- **`ZP Loudness Meter Multichannel.jsfx`**: Meter multicanale per standard broadcast (EBU R128, ITU-R BS.1770, LUFS integrato, short-term e true peak).
- **`ZP Oscilloscope 16ch.jsfx`**: Oscilloscopio multicanale a 16 canali per controllo fase, allineamento e transitori.
- **`ZP Voice-Music Probe.jsfx`**: Sonda ausiliaria di campionamento segnale per il controllo del bilanciamento voce/musica.

#### Incubatore `ZP Lab` (Escluso da ReaPack)
- **`ZP BrownSlope Dynamic Guard.jsfx`**: Algoritmo sperimentale di protezione dinamica su pendenza Brown Noise (versione Assist in validazione interna).

---

### B. ZP Studio Suite (Script ReaScript Lua)
Situati in `ZP Studio Suite/`, comprendono **25 azioni numerate** (da 00 a 27, con gli slot 15, 16 e 21 attualmente liberi), 2 worker ausiliari e 2 librerie di supporto:

| Azione | File Lua | Scopo Operativo |
|---|---|---|
| **00** | `00_Apri_Help_ZP_Studio_Suite.lua` | Apertura help ipertestuale contestuale integrato. |
| **01** | `01_Importa_Video_SRT.lua` | Importazione video e traccia sottotitoli sincronizzata. |
| **02** | `02_Gobbo_Verticale.lua` | Interfaccia gobbo elettronico a scorrimento verticale per recitazione. |
| **03** | `03_Gobbo_Orizzontale.lua` | Visualizzatore orizzontale a nastro scorrevole. |
| **04** | `04_Crea_Marker_Item.lua` | Generazione marker di timeline partendo dai cue degli item. |
| **05** | `05_Aggiorna_SRT_Video.lua` | Sincronizzazione e re-export dei sottotitoli modificati. |
| **06** | `06_Importa_SRT_Reference.lua` | Importazione testo di riferimento per confronto battute. |
| **07** | `07_Note_Personaggio.lua` | Visualizzatore e annotatore note di regia/carattere personaggio. |
| **08** | `08_Esporta_SRT.lua` | Esportazione standard SubRip con preservazione timecode. |
| **09** | `09_OSARA_Battuta_Corrente.lua` | Sintesi vocale accessibile: legge solo la battuta corrente. |
| **10** | `10_OSARA_Battuta_Successiva.lua` | Sintesi vocale accessibile: anticipa la battuta successiva. |
| **11** | `11_OSARA_Battuta_Precedente.lua` | Sintesi vocale accessibile: riascolto battuta precedente. |
| **12** | `12_OSARA_Lettura_Automatica.lua` | Lettura automatica a cursore fermo durante lo scrub/rec. |
| **13** | `13_Info_Item_SRT.lua` | Ispezione rapida metadati dell'item sottotitolo selezionato. |
| **14** | `14_Marker_da_Timeline_a_Item.lua` | Trasferimento marker da timeline globale a take marker solidali con l'item. |
| **17** | `17_Crea_Regioni_Export_da_Item_Nominati.lua` | Gestore Progetto: generazione regioni e preparazione render per sezione. |
| **18** | `18_Project_Viewer.lua` | Vista gerarchica marker e regioni con navigazione rapida. |
| **19** | `19_Report_Minuti_Voce.lua` | Calcolo statistico minuti effettivi di parlato per consuntivi e fatturazione. |
| **20** | `20_Importa_Cartelle_Video_Mixdown.lua` | Importazione massiva e posizionamento risorse audio/video. |
| **22** | `22_Pulisci_Code_Silenzi_e_Separa_Item.lua` | Trimming automatico respiri, silenzi e separazione sillabica. |
| **23** | `23_ZP_Chain_Builder.lua` | Generatore guidato e cablaggio automatico routing delle tracce voce. |
| **24** | `24_ZP_Probe_Guard.lua` | Demone/guardia che garantisce le probe Voice-Music sempre in fondo ai bus. |
| **25** | `25_ZP_SOLO_Recorder.lua` | Banco di registrazione assistito (interfaccia Mini/Expanded, togli-take, ritorno). |
| **26** | `26_SRT_Tools.lua` | Strumenti offline per conversione e merge di formati sottotitolo. |
| **27** | `27_Pulisci_Installazione_Precedente.lua` | Bonifica sicura di vecchi pacchetti e file legacy obsoleti. |

#### File di supporto e librerie interne
- **Worker dedicati**: `04_worker_Crea_Marker_Item.lua`, `05_worker_Gestione_SRT.lua`.
- **Librerie UI e accessibilità**: `ZP_UI.lua`, `lib_RythmoBand_Accessibile.lua`.
- **Moduli bridging**: `ZP_NVDA_Speech.py`, `nvdaControllerClient64.dll`.
- **Template di traccia**: `RB Voice Track.RTrackTemplate`, `SRT Track.RTrackTemplate`.
- **Video Processor**: `VideoProcessor_Project_Timecode_Overlay.txt`.

*(Gli slot 15, 16 e 21 sono numerazioni libere riservate ad espansioni future).*

---

## 3. Relazioni Funzionali e Routing Audio

```
TRACCIA VOCE (Item microfonico)
   │
   ▼
[22_Pulisci_Code...] ──> [04/14 Marker e Gobbo (02/03/OSARA)]
   │
   ▼
[ZP Voiceover Unified Chain]
   │
   ▼
BUS VOCE (Submix) ──> [ZP BUS Chain] ──> [ZP Spoken Finish] ──> [ZP Harmonic Space Carver]
   │                                                                        ▲
   │ (Sidechain inviata alla base)                                          │ (Probe)
   ▼                                                                        │
BUS MUSICA / EFFETTI ───────────────────────────────────────────────────────┘
   │
   ▼ [24_ZP_Probe_Guard controlla la presenza in fondo ai bus]
MASTER BUS ──> [ZP Master Pro] ──> [ZP Loudness Meter Multichannel]
```

- **Infrastruttura di Routing**: `23_ZP_Chain_Builder.lua` istanzia e collega i canali audio (canali 1-2 audio primario, canali 3-4 sidechain/probe).
- **Integrità della Catena**: `24_ZP_Probe_Guard.lua` monitora che nessun plugin inserito manualmente finisca dopo la sonda di misura, garantendo letture corrette del bilanciamento.
