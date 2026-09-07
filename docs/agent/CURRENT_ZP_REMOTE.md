# CURRENT_ZP_REMOTE — stato canonico del progetto

> Snapshot breve ma completo. Punto di ingresso rapido per un agente (umano o AI) che riprende il progetto ZP Remote dopo una pausa. Se questo file e uno degli altri documenti canonici si contraddicono, vale la gerarchia delle fonti (vedi in fondo): questo file riassume, non sostituisce.

**Data**: 5 settembre 2026.
**Fase corrente**: **DOCUMENTAZIONE COMPLETATA / PRE-FASE 0**. La fase di riallineamento documentale è chiusa: tutta la documentazione canonica di ZP Remote vive ora in `docs/agent/` nel repository `zp-suite`. Nessun codice scritto, nessuna dipendenza installata, nessun commit/push relativo a ZP Remote. **Prossima fase autorizzabile: Fase 0 — Architecture Freeze + Media Feasibility Spike** (non ancora avviata).

---

## Definizione corrente del prodotto

ZP Remote **non è** "telecomando REAPER + gobbo remoto". È:

> una sessione di studio browser-based con controllo DAW, cue/script sincronizzabile e routing media per ruoli differenti, con REAPER come prima DAW profondamente integrata.

Due assi separati: controllo DAW e cue/script non sono un solo prodotto. REAPER è il primo host, non il protocollo.

---

## Decisioni consolidate (non in discussione senza un nuovo giro di riallineamento)

- Ruoli come **bundle di capability**, non blocchi monolitici — REC/STOP è la capability `record`, non un divieto tecnico del browser.
- Modello dati v1: **1 artista registrabile + regia + 0..N observer** (mai "un solo ospite totale").
- **Control plane e media plane separati**, sempre — WebRTC non si usa "perché è remoto", si usa per il trasporto media.
- **DAW Adapter e Media Bridge sono due componenti distinti**, mai fusi.
- Il **REAPER Lua Adapter descrive e governa** la DAW (track, routing, arm/mute/solo, meter numerici, transport, cue, FX) ma **non trasporta mai PCM audio realtime** — niente `AudioAccessor`, niente polling di campioni in Lua.
- **Artist e Observer sono browser-only**: dispositivi del sistema operativo via API standard del browser, nessun virtual cable richiesto. Il protocollo non sa se sotto c'è CoreAudio/WASAPI/PipeWire.
- La pagina **Control è un mixer di contribution** (Program/DAW, Talkback, Aux → Remote Mix → un solo stream WebRTC in v1), non una DAW nel browser. Modello interno aperto a stem separati in futuro.
- Il mix-minus (Program) **si costruisce a monte, nella DAW** — ZP Remote non lo ricostruisce.
- Il microfono Artist via WebRTC è una sorgente **ARTIST RETURN**; la destinazione nella DAW è decisa dalla regia, instradata dal Lua Adapter.
- `BlackHole` **non è un componente architetturale**: è una possibile implementazione macOS del livello astratto `Local Media I/O`, utile soprattutto lato regia.
- **Cue Model**: Script Mode/Dynamic Gobbo Mode sono proprietà del **renderer/client**, non del cue — lo stesso Cue Document può essere visto in modalità diverse da client diversi nello stesso momento.
- "Usare WebRTC/API browser" (in scope v1) ≠ "costruire un motore/protocollo di rete audio proprietario stile SonoBus" (fuori scope per tutte le fasi 0-6).
- Fonti esterne trattate solo come riferimento di studio (SonoBus, AOO) o funzionale/UX (Source-Connect, SessionLinkPRO) — mai codice da incorporare senza una valutazione legale a parte; BlackHole non è un requisito.

---

## Componenti

Control Client · Artist Client · Observer Client · Session Engine · REAPER Lua Adapter · ZP Remote Protocol · Local Media I/O · Media Bridge · Signaling/TURN. Dettagli in `ARCHITETTURA_ZP_REMOTE.md` §2.

## Ruoli

`control`/`director`, `artist`, `observer` — come bundle di capability (`control_daw`, `record`, `transport`, `seek`, `talkback`, `edit_cues`, `receive_script`, `send_artist_audio`, `receive_talkback`, `receive_video`, `send_video`, `receive_artist_audio`, `send_talkback`). Dettagli in `ARCHITETTURA_ZP_REMOTE.md` §3/§4.

## Modello Control / Media

Due diagrammi separati e non fusi:

```
CONTROL: REAPER ↕ REAPER Lua Adapter ↕ ZP Remote Protocol ↕ Session Engine/Control Plane ↕ Web Clients
MEDIA:   REAPER/Local Audio ↕ Local Media I/O ↕ Media Bridge ↕ WebRTC ↕ Artist/Observer
```

Diagramma end-to-end e bozza ASCII della UI "ZP Control Beta" in `ARCHITETTURA_ZP_REMOTE.md` §20.

## Program / Talkback / Aux

La console di regia acquisisce tre sorgenti logiche (Program/DAW, Talkback, Aux/Extra), ciascuna con source selector/meter/gain/mute (Talkback ha anche TALK/PTT), mixate in un Remote Mix inviato come singolo stream WebRTC in v1. Dettagli in `ARCHITETTURA_ZP_REMOTE.md` §10.1.

## Ruolo del Lua Adapter

Governa e descrive la DAW (dati/comandi), mai il trasporto audio. Vive sul control plane. Dettagli in `ARCHITETTURA_ZP_REMOTE.md` §7.

## Ruolo del Media Bridge

Instrada l'audio/video reale fra Local Media I/O e WebRTC. Vive sul media plane, separato dal Lua Adapter. Dettagli in `ARCHITETTURA_ZP_REMOTE.md` §6.

## Ruolo del Local Media I/O

Livello astratto di instradamento audio locale sulla macchina di regia (Program in uscita verso il Media Bridge, Artist Return in ingresso verso la DAW, eventuali sorgenti esterne). Implementazioni concrete = dettaglio di piattaforma (BlackHole su macOS, equivalenti WASAPI/PipeWire altrove). Non richiesto per Artist/Observer. Dettagli in `ARCHITETTURA_ZP_REMOTE.md` §13/§15.

---

## Stato della roadmap

Nessuna fase avviata. Sequenza corrente (`ROADMAP_ZP_REMOTE.md`):

0. Architecture Freeze + Media Feasibility Spike
1. REAPER Lua Adapter v0
2. ZP Control Beta
3. Web Service / Session Engine
4. Artist + Observer
5. Cue / Script / Gobbo
6. Hardening multipiattaforma
Futuro: adapter altre DAW, stem separati, più artisti, double-ended recording, eventuale motore proprietario.

**Fase 0 e Fase 1 non si sovrappongono**: Fase 0 valida il flusso audio (media plane), Fase 1 costruisce il modello di controllo REAPER (control plane, senza audio).

---

## Questioni ancora aperte (elenco completo in `ARCHITETTURA_ZP_REMOTE.md` §19)

Tecnologia del control plane · percorso media più semplice per LAN stretta · meccanismo di trasporto Lua↔resto del sistema · dove gira il Session Engine · numero massimo di observer in v1 · configurazione Local Media I/O per piattaforma · adeguatezza di Opus per registrazione professionale · modello di sicurezza/autenticazione (incluso account/login) · TURN self-hosted vs. gestito · comportamento di failure/reconnect, sample rate/clock differenti, cambio dispositivo · implementazione tecnica del mixer Program/Talkback/Aux · meccanismo esatto di consegna del Program per piattaforma. Inoltre: la licenza esatta di AOO (git.iem.at) non è stata verificata con certezza (`REFERENCES_ZP_REMOTE.md`).

**Chiuso in questa fase**: esiste un workspace separato, `~/Documents/ZP/zp-telecomando-reaper/` (non un archivio storico su LaCie, ma una cartella attiva con proprio `AGENTS.md`/`PROJECT_STATE.md`/`Roadmap-progetto.md`), la cui `Analisi-progetto-telecomando-remoto.md` (4 settembre 2026) proponeva una "Strada C" per l'audio Artist in v1 (videochiamata esterna Meet/Teams + cavo virtuale BlackHole, per evitare un motore WebRTC proprio). Paolo ha confermato che questa strada è superata: il WebRTC nativo del browser resta il meccanismo v1 per l'audio Artist/Observer (`ARCHITETTURA_ZP_REMOTE.md` §14). Quel workspace resta materiale di riferimento/confronto, non toccato e non consolidato in `zp-suite` in questa fase.

---

## File canonici da leggere prima di lavorare (in ordine di priorità)

1. `DECISIONS.md`, `LESSONS.md`, `PROJECT.md`, `CURRENT.md` — Suite (se il lavoro tocca REAPER/Lua).
2. `ARCHITETTURA_ZP_STUDIO_SUITE.md` — mappa tecnica della Suite reale (cue model, marker/lane, ExtState, duplicazioni già note).
3. `ARCHITETTURA_ZP_REMOTE.md` — architettura completa di ZP Remote (questo file ne è solo il riassunto).
4. `ROADMAP_ZP_REMOTE.md` — sequenza di fasi.
5. `REFERENCES_ZP_REMOTE.md` — riferimenti esterni con licenza.
6. Codice reale — arbitro finale quando documentazione e implementazione divergono.

Tutti e cinque i documenti ZP Remote/Suite canonici vivono in `docs/agent/` in questo repository (`zp-suite`); la vecchia cartella LaCie del progetto "Telecomando" resta solo archivio storico di confronto, non sorgente corrente.

## Cosa NON è ancora stato implementato

Tutto. In particolare, esplicitamente:

- **Nessun codice ZP Remote** è stato scritto (nessun bridge, nessun server, nessuna pagina web applicativa).
- **Nessun Media Bridge** è stato implementato.
- **Nessun REAPER Lua Adapter per ZP Remote** è stato implementato (distinto dagli script esistenti della ZP Studio Suite, che restano quelli descritti in `ARCHITETTURA_ZP_STUDIO_SUITE.md` e non sono stati toccati).
- **Nessun Web Service / Session Engine** è stato implementato.
- **Nessun client Artist o Observer** è stato implementato.
- Nessuna modifica alla ZP Studio Suite, nessuna dipendenza installata.
- Il prototipo `ZP_Solo_Recorder_WebRemote` esiste solo come UI-only, non collegato a REAPER (fatto registrato in precedenza, da verificare de visu prima di riusarlo in Fase 2).

**Prossima fase autorizzabile**: Fase 0 — Architecture Freeze + Media Feasibility Spike (`ROADMAP_ZP_REMOTE.md`). Non ancora avviata.

---

*Documento prodotto da Claude (Cowork) il 5 settembre 2026, al termine della terza fase di riallineamento documentale di ZP Remote (chiusura della fase documentale, consolidamento in `docs/agent/`). `AGENTS.md` è stato aggiornato in questa fase per referenziare questo documento e gli altri documenti canonici di ZP Remote.*
