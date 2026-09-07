# ROADMAP_ZP_REMOTE — sequenza di fasi di ZP Remote

> Documento canonico della roadmap di ZP Remote (rinominato da `Roadmap-progetto.md`; nessun contenuto tecnico modificato in questa rinomina — fasi, obiettivi e ordine restano quelli della seconda riscrittura). Vive in `docs/agent/` accanto a `ARCHITETTURA_ZP_REMOTE.md`, `CURRENT_ZP_REMOTE.md` e `REFERENCES_ZP_REMOTE.md`.
>
> Seconda riscrittura (5 settembre 2026), dopo la seconda fase di riallineamento architetturale (vedi `ARCHITETTURA_ZP_REMOTE.md`). **Nessuna fase è stata avviata.** Sostituisce la versione precedente di questo file — se il file originale nella cartella del progetto Telecomando (LaCie, archivio storico in sola lettura) dice qualcosa di diverso, questo file in `docs/agent/` è quello canonico e vivo.
>
> **Disambiguazione esplicita fra Fase 0 e Fase 1** (richiesta esplicitamente, perché le due fasi toccano entrambe "REAPER" e vanno tenute separate): la **Fase 0 valida il percorso media** — browser↔WebRTC↔Media Bridge↔Local Media I/O↔DAW come flusso audio, senza nessun protocollo di controllo. La **Fase 1 costruisce il REAPER Lua Adapter** — il modello di controllo/dati (track, routing, meter numerici, cue, comandi), **senza trasportare audio**. Se un compito sembra poter stare in entrambe, la domanda da farsi è: "sto misurando un flusso audio reale?" → Fase 0; "sto normalizzando dati/stato del progetto?" → Fase 1.

---

## Fase 0 — Architecture Freeze + Media Feasibility Spike

**Obiettivo**: congelare l'architettura descritta in `ARCHITETTURA_ZP_REMOTE.md` (nessuna modifica strutturale non pianificata durante l'implementazione) e validare per davvero, con un prototipo minimo e usa-e-getta, il percorso media reale.

**Da verificare concretamente**:
- input/output audio e camera dal browser remoto (`getUserMedia` e simili);
- Chrome/Chromium come target primario;
- WebRTC bidirezionale (artist↔studio);
- acquisizione **simultanea** di Program, Talkback, Aux lato Control (§10.1 di `ARCHITETTURA_ZP_REMOTE.md`);
- un mixer Web Audio minimo (Program/Talkback/Aux → Remote Mix);
- Remote Mix effettivamente inviato via WebRTC;
- Artist Return ricevuto e misurato lato studio;
- sample rate differenti e clock differenti fra browser/OS/DAW;
- device switching a sessione avviata;
- stabilità di sessione nel tempo;
- echo/feedback (in particolare fra Program in cuffia e mic aperto, sia lato regia sia lato artista);
- il raccordo reale fra DAW e sistema media (come il Program esce dalla DAW, come l'Artist Return rientra) — tramite un metodo di Local Media I/O, non ancora tramite il Lua Adapter (quello è Fase 1).

**Il primo test può essere su macOS**, ma non deve rendere BlackHole (o qualunque altra soluzione di piattaforma) parte del protocollo — resta un dettaglio di implementazione del Local Media I/O (`ARCHITETTURA_ZP_REMOTE.md` §13/§15).

**Done quando**: sappiamo concretamente, con numeri reali (non stime), come si comporta il percorso media nei due sensi, abbiamo una risposta a "Opus basta per una registrazione professionale?", e abbiamo scelto — con motivazioni e limiti espliciti — il meccanismo di Local Media I/O per il primo test.

**Non fa parte di questa fase**: il REAPER Lua Adapter, il protocollo di controllo, sessioni/ruoli, UI definitiva — solo il tubo audio e il piccolo mixer che lo alimenta, nel modo più semplice che basta a misurare.

---

## Fase 1 — REAPER Lua Adapter v0

**Obiettivo**: esporre il modello DAW normalizzato e il controllo/routing (`ARCHITETTURA_ZP_REMOTE.md` §7): track, canali, send/receive, hardware output, routing, arm/mute/solo, volume/pan, meter (numerici), transport, marker/regioni, cue, FX/parametri pertinenti, workflow di alto livello (SOLO Recorder incluso).

**Nessun PCM realtime trasportato via Lua** — vincolo esplicito, non un dettaglio da rivedere in corsa. Include anche la scelta del meccanismo di trasporto fra il processo Lua e il resto del sistema (bridge companion, OSC↔WebSocket, altro — punto aperto §7/§19 di `ARCHITETTURA_ZP_REMOTE.md`).

**Non include**: refactoring della ZP Studio Suite — l'adapter legge/scrive lo stato via le convenzioni esistenti (item, `P_NOTES`, `P_EXT:*`, marker/lane) così come sono oggi.

---

## Fase 2 — ZP Control Beta

**Obiettivo**: prima UI funzionante di regia, collegata realmente al Lua Adapter (Fase 1) e al mixer validato in Fase 0: Program / Talkback / Aux / Remote Send / Artist Return + transport REAPER essenziale (vedi la bozza ASCII in `ARCHITETTURA_ZP_REMOTE.md` §20.4). Ancora nessun Artist/Observer reale — solo la console di regia.

---

## Fase 3 — Web Service / Session Engine

**Obiettivo**: account/utente, login, sessioni, token, role/capability, signaling (`ARCHITETTURA_ZP_REMOTE.md` §3/§4/§8/§16). Qui si decide anche dove gira il Session Engine e il modello di sicurezza.

---

## Fase 4 — Artist + Observer

**Obiettivo**: client browser-only (nessun virtual cable), input/output/camera, WebRTC, talkback/return, per Artist e Observer (`ARCHITETTURA_ZP_REMOTE.md` §9/§11) — costruito sopra quanto validato in Fase 0, non da zero.

---

## Fase 5 — Cue / Script / Gobbo

**Obiettivo**: Cue Model completo (`ARCHITETTURA_ZP_REMOTE.md` §12) con Script Mode e Dynamic Gobbo Mode come proprietà del client/renderer, video, e le funzioni editoriali autorizzate (`edit_cues`, per chi ha la capability).

---

## Fase 6 — Hardening multipiattaforma

**Obiettivo**: macOS/Windows/Linux (incluse le rispettive implementazioni di Local Media I/O), TURN (self-hosted vs. gestito), reconnect, recovery dispositivi, sicurezza, diagnostica, sessioni lunghe.

---

## Futuro (fuori perimetro per tutte le fasi 0-6)

- adapter per altre DAW (VST3/AU/AAX/estensione/helper nativo);
- stem separati (Program/Talkback/Aux come tracce WebRTC indipendenti, invece di un solo Remote Mix) e matrici Artist Mix/Observer Mix più ricche;
- più artisti registrabili contemporaneamente;
- double-ended recording / registrazione locale con upload successivo, se la Fase 0 mostra che serve;
- un eventuale motore audio/networking proprietario stile SonoBus — esplicitamente non prima, esplicitamente non "un'opzione fra le altre" nelle fasi 0-6.

---

*Numerazione e nomi delle fasi seguono la struttura indicata da Paolo nella seconda fase di riallineamento del 5 settembre 2026. Rispetto alla riscrittura precedente di questo file, i cambiamenti sono: Fase 0 ora si chiama esplicitamente "Architecture Freeze + Media Feasibility Spike" e include il mixer Program/Talkback/Aux fra le cose da validare; Fase 1 è ridenominata "REAPER Lua Adapter v0" con il vincolo esplicito "niente PCM via Lua"; è comparsa una Fase 2 "ZP Control Beta" dedicata alla console di regia prima del resto; il vecchio "Session Engine" diventa "Web Service / Session Engine" con account/login esplicito; "Cue/Script + Video + Observer" si è diviso in Fase 4 "Artist + Observer" e Fase 5 "Cue / Script / Gobbo"; l'Hardening è ora esplicitamente multipiattaforma. Rinominato da `Roadmap-progetto.md` a `ROADMAP_ZP_REMOTE.md` e consolidato in `docs/agent/` nella terza fase di riallineamento (chiusura della fase documentale, 5 settembre 2026) — nessuna fase, obiettivo o contenuto tecnico modificato in questa rinomina.*
