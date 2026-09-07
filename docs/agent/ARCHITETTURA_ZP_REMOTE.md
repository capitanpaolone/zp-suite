# ARCHITETTURA_ZP_REMOTE

> Documento architetturale canonico di **ZP Remote**. Fase puramente documentale: nessun codice, nessun bridge, nessuna dipendenza installata, nessun file Lua/HTML/JS applicativo toccato.
>
> **Convenzione di lettura**: ogni affermazione porta un tag —
> **[D] Deciso** = confermato da Paolo e non rimesso in discussione qui;
> **[I] Ipotesi** = direzione plausibile, coerente con le decisioni prese, ma non ancora validata tecnicamente;
> **[A] Aperto** = questione che richiede una scelta o un test prima di poter procedere (elenco consolidato in §19).
>
> **Fonti**: il correttivo del 5 settembre 2026 (prima fase di riallineamento: definizione di prodotto/ruoli/capability/plane) e il correttivo del 5 settembre 2026, seconda fase (REAPER Lua Adapter senza PCM realtime, console Program/Talkback/Aux, Cue Model come proprietà del renderer, Local Media I/O come astrazione di piattaforma) hanno entrambi priorità sulle formulazioni precedenti quando in conflitto con esse. `ARCHITETTURA_ZP_STUDIO_SUITE.md` resta la fonte per tutto ciò che riguarda il codice Lua reale della Suite. Non ho ancora potuto leggere i file originali del progetto Telecomando su LaCie (cartella non connessa a questa sessione).
>
> **Revisione 5 settembre 2026 (seconda fase)** — correzioni principali rispetto alla versione precedente di questo documento, tutte incorporate inline con il tag **[D]** nelle sezioni pertinenti:
> - il REAPER Adapter **descrive e governa** la DAW (track, routing, arm/mute/solo, meter come dati numerici, transport, marker/cue, FX) ma **non trasporta mai PCM audio realtime** — non va disegnato attorno ad `AudioAccessor` o al polling di campioni in Lua (§7);
> - Artist e Observer sono **browser-only**: usano i device audio/video esposti dal sistema operativo tramite le API standard del browser, **senza bisogno di virtual cable**; il protocollo non deve sapere se sotto c'è CoreAudio, WASAPI o PipeWire (§9, §11, §13);
> - la pagina Control diventa un piccolo **mixer di contribution** (Program/DAW, Talkback, Aux → Remote Mix → WebRTC), non una DAW nel browser (§10);
> - il microfono dell'Artist, ricevuto via WebRTC, è una sorgente `ARTIST RETURN` lato studio, con destinazione nella DAW decisa dal Lua Adapter/routing locale (§10, §6);
> - BlackHole non è un componente architetturale di ZP Remote: è una possibile implementazione macOS del livello astratto `Local Media I/O`, utile soprattutto lato regia, non un requisito per Artist/Observer (§13, §15);
> - il Cue Model è stato corretto: Script Mode/Dynamic Gobbo Mode sono proprietà del **renderer/client**, non del singolo cue (§12);
> - "usare WebRTC/le API del browser" (in scope v1) è stato disambiguato esplicitamente da "costruire un nostro motore/protocollo di rete audio proprietario stile SonoBus" (fuori scope, §14);
> - `Session Link Pro` e `Source-Connect` sono due prodotti di due aziende diverse (rispettivamente SessionLinkPRO Solutions GmbH e Source Elements) — nella prima stesura di `REFERENCES_ZP_REMOTE.md` erano stati impropriamente accorpati in una sola voce; corretto (vedi `REFERENCES_ZP_REMOTE.md`).

---

## 1. Obiettivo del prodotto

**[D]** ZP Remote non è "telecomando REAPER + gobbo remoto". È:

> una sessione di studio browser-based con controllo DAW, cue/script sincronizzabile e routing media per ruoli differenti, con REAPER come prima DAW profondamente integrata.

- il "controllo DAW" e il "cue/script" sono due assi separati (§12);
- REAPER è **il primo host**, non **il protocollo**: l'architettura resta DAW-agnostic fin dal disegno (§7).

---

## 2. Componenti

**[D]**

- **Control Client** (§10) — browser di regia, locale o autorizzato remoto; include il mixer di contribution Program/Talkback/Aux.
- **Artist Client** (§9) — pagina web per l'artista, browser-only, nessuna installazione ZP-specifica, nessun virtual cable.
- **Observer Client** (§11) — cliente/direttore/produttore/fonico/ospite occasionale, browser-only come l'Artist.
- **Session Engine** (§8) — sessioni, ruoli/capability, token, account/login, registry partecipanti, signaling applicativo.
- **REAPER Lua Adapter** (§7) — lato Lua/ReaScript, **descrive e governa** lo stato/routing del progetto REAPER; non trasporta audio.
- **ZP Remote Protocol** — linguaggio comune fra adapter, Session Engine e client (stato, comandi, cue, capability) sul control plane (§5).
- **Local Media I/O** (§13/§15) — livello astratto di instradamento audio locale sulla macchina di regia (Program dalla DAW verso il Media Bridge, Artist Return dal Media Bridge verso la DAW, eventuali sorgenti esterne). Implementazioni concrete: dettaglio di piattaforma (BlackHole/Aggregate Device su macOS, equivalenti WASAPI su Windows, PipeWire su Linux).
- **Media Bridge** — instrada l'audio/video reale fra Local Media I/O e WebRTC (§6/§14).
- **Signaling/TURN** (§17) — bootstrap delle connessioni WebRTC e attraversamento NAT.

**[D] Il DAW Adapter e il Media Bridge sono due componenti distinti e non vanno fusi**: il primo parla il protocollo di controllo (dati, comandi, numeri), il secondo trasporta l'audio reale. Vedi i due diagrammi separati in §20.

---

## 3. Ruoli di sessione

**[D]** Almeno questi tre ruoli, modellati come insiemi di capability (§4), non come blocchi monolitici:

### `control` / `director` — Regia autorizzata
Capability tipiche: `control_daw`, `record`, `transport`, `seek`, `talkback`, `receive_video`, `receive_artist_audio`, eventualmente `edit_cues`.

### `artist`
Capability tipiche: `receive_script`, `send_artist_audio`, `receive_talkback`, `receive_video`, controlli locali (font/volume/device).
Non deve avere: `control_daw`, `record`, `edit_project`.

### `observer`
Per cliente, direttore, produttore, fonico, ospite occasionale. Capability configurabili: `receive_artist_audio`, `send_talkback`, `receive_video`, `send_video`. Non deve ricevere obbligatoriamente: gobbo/copione, controllo DAW.

**[D]** v1 non significa un solo partecipante totale: **una sola sorgente artista registrabile attiva per sessione**, ma il modello dati resta aperto a **1 artista registrabile + regia + 0..N observer**.

---

## 4. Capabilities

**[D]** I ruoli in §3 sono bundle nominati di default di capability, non entità a sé. REC/STOP non sono vietati tecnologicamente al browser: sono vietati a chi non ha la capability `record`.

| Capability | Significato | Bundle tipico |
|---|---|---|
| `control_daw` | comandi generali sulla DAW (arm/mute/solo/monitor, mixer/FX) | control |
| `record` | avvio/stop registrazione | control |
| `transport` | play/stop/pause | control |
| `seek` | spostare il cursore/playhead | control |
| `talkback` | inviare talkback verso l'artista | control |
| `edit_cues` | modificare cue/copione | control (eventuale) |
| `receive_script` | ricevere il Cue Document | artist (e control, se vuole vedere il copione) |
| `send_artist_audio` | inviare il proprio microfono verso lo studio (WebRTC) | artist |
| `receive_talkback` | ricevere il talkback della regia | artist |
| `receive_video` | ricevere video | control, artist, observer (configurabile) |
| `send_video` | inviare video | observer (configurabile), eventualmente artist |
| `receive_artist_audio` | ricevere il mix/monitor dell'artista | control, observer (configurabile) |
| `send_talkback` | inviare talkback | control, observer (configurabile) |

---

## 5. Control Plane

**[D]** Canale semantico separato dal media plane, per: stato transport, stato tracce, **meter come dati numerici** (non audio, §7), cue/script, marker/regioni, timeline, session state, permissions/capabilities, comandi, signaling applicativo per il WebRTC.

```
CONTROL:
REAPER
  ↕
REAPER Lua Adapter
  ↕
ZP Remote Protocol
  ↕
Session Engine / Control Plane
  ↕
Web Clients (Control / Artist* / Observer*)
```
\* Artist/Observer ricevono sul control plane solo ciò che le loro capability permettono (cue, stato sessione) — non arm/mute/solo/routing.

**[I]** Tecnologia preferita: WebSocket/WSS. Non ancora validata (Fase 1). **Non usare WebRTC per il control plane solo perché il collegamento è remoto** — resta a semantica separata dal media plane qualunque sia la tecnologia scelta.

---

## 6. Media Plane

**[D]**

```
MEDIA:
REAPER / Local Audio
  ↕
Local Media I/O
  ↕
Media Bridge
  ↕
WebRTC
  ↕
Artist / Observer
```

WebRTC trasporta: microfono artista → studio, ritorno audio/talkback studio → artista, eventuale observer ↔ artista, video, eventuali stream aggiuntivi. Non usato per il control plane.

**[D] Remote Return**: il microfono dell'Artist ricevuto via WebRTC deve essere disponibile lato studio come sorgente **`ARTIST RETURN`**. Dove instradarlo nella DAW è una scelta concettualmente della regia (§10); per REAPER, l'instradamento effettivo è governato dal Lua Adapter/routing locale (§7) — il Media Bridge consegna il segnale, il Lua Adapter/regia decide dove va.

**[D] Program dalla DAW**: il Program (mix-minus) **si costruisce a monte, dentro la DAW** — ZP Remote riceve un Program già corretto e non costruisce mix-minus per conto proprio. Il Program arriva al browser/Media Bridge tramite un metodo di **Local Media I/O** (§13): loopback della scheda audio, virtual audio device, Local Media Bridge, o altro metodo disponibile sul sistema. Il metodo esatto è responsabilità del setup locale, non del protocollo.

**[A]** Per collegamenti sullo stesso computer/LAN stretta, resta da validare (Fase 0) se serva un percorso più semplice del WebRTC per il solo media locale, o se WebRTC uniforme sia comunque la scelta giusta.

---

## 7. REAPER Adapter (e concetto di DAW Adapter)

**[D]** Confine architetturale esplicito e DAW-agnostic:

```
DAW → DAW Adapter → ZP Remote Protocol → Session / Media Bridge → Browser Clients
```

Regola vincolante: **l'HTML non deve conoscere la struttura interna del progetto REAPER**, e **il Lua non deve conoscere la struttura dell'HTML**.

**[D] Cosa deve poter esporre il Lua Adapter** (modello della DAW, non audio):
- track;
- numero di canali delle track;
- send/receive;
- hardware output dove applicabile;
- routing;
- arm/mute/solo;
- volume/pan;
- **meter** (valori numerici — RMS/peak periodici, non campioni audio);
- transport;
- marker/regioni;
- cue (Cue Document, §12);
- FX/parametri pertinenti (nomi leggibili via `TrackFX_GetParamName`, esclusi gli slider di solo-stato-GUI — nota tecnica già raccolta in precedenza);
- workflow di alto livello della ZP Suite/SOLO Recorder (`nextTake`, arm esclusivo, ecc. — §10).

**[D] IMPORTANTE — cosa il Lua Adapter NON fa**: "esporre tutti i canali" **non significa trasmettere via Lua il PCM realtime di tutte le track**. Il Lua **governa e descrive** la DAW e può **configurare** routing/send (ad es. creare o modificare una send verso un bus dedicato al Media Bridge); il **trasporto dell'audio reale resta responsabilità del Media Bridge / Local Media I/O** (§6/§13), non del Lua Adapter. Di conseguenza: **non progettare il media transport attorno ad `AudioAccessor` o al polling di campioni audio in Lua** — sarebbe sia lento sia concettualmente sbagliato (il Lua Adapter vive sul control plane, non sul media plane, §2).

Per REAPER, il primo adapter è Lua/ReaScript **[D]**, perché offre l'accesso più profondo oggi disponibile al progetto (livello di dettaglio mappato in `ARCHITETTURA_ZP_STUDIO_SUITE.md`). In futuro, un'altra DAW potrebbe usare VST3, AU, AAX, un'estensione nativa, un helper/bridge nativo o un'altra API specifica **[A] — non decidere ora quale**. Il protocollo e il sito non devono dipendere dal fatto che oggi l'adapter sia Lua.

**Materiale grezzo già disponibile nella Suite** (dettagli in `ARCHITETTURA_ZP_STUDIO_SUITE.md`): il modello cue (item + `P_NOTES` + `P_EXT:RythmoBand_*`), la gerarchia di lane per marker/regioni, `P_EXT:ZP_CHAIN_ROLE` come precedente di registro di ruolo per track, le operazioni di alto livello di `25_ZP_SOLO_Recorder.lua`.

**[A]** Meccanismo di trasporto fra il processo REAPER/Lua e il resto del sistema (bridge companion locale con WebSocket proprio, ponte OSC↔WebSocket come già ipotizzato nel progetto Telecomando, o altro): da validare in Fase 1. **Questo è compito della Fase 1, non della Fase 0** — vedi nota di disambiguazione in `ROADMAP_ZP_REMOTE.md`.

---

## 8. Session Engine

**[D]** Responsabilità: ciclo di vita della sessione, **account/utente e login**, emissione/validazione dei token di accesso, assegnazione ruoli/capability ai partecipanti, registro dei partecipanti (1 artista registrabile + regia + 0..N observer, §3), relay del signaling applicativo per il WebRTC, verifica delle capability **lato server** prima di inoltrare un comando all'adapter REAPER.

**[A]** Dove gira esattamente e come si relaziona col servizio di signaling/TURN (§17): materia della Fase 3 (Web Service / Session Engine).

---

## 9. Artist Client

**[D]** Pagina web, **browser-only**: nessuna installazione di software specifico ZP, **nessun virtual cable richiesto**. Usa i dispositivi esposti dal sistema operativo (input audio, output audio, camera) tramite le API standard del browser (`getUserMedia` e simili) — il sistema operativo può essere macOS, Windows o Linux, e **il protocollo ZP Remote non deve sapere se sotto ci sono CoreAudio, WASAPI o PipeWire**.

Può: vedere il proprio copione/gobbo (Cue Model, §12), ricevere audio di regia/talkback, eventualmente ricevere video, scegliere il proprio dispositivo microfono, vedere il livello del proprio microfono, controllare volume cuffia/local monitoring dove tecnicamente appropriato, inviare il proprio microfono verso lo studio via WebRTC.

Non controlla la DAW, non vede necessariamente mixer/track, non riceve funzioni editoriali di regia né comandi distruttivi — vincolo di capability (§4), non limite tecnico del browser.

**[D]** L'Artist Client non è il "gobbo remoto" travestito da client: il gobbo/script è una delle sue facce (Cue Model, §12); le altre sono audio in ingresso/uscita, device selection, monitoring locale.

---

## 10. Control Client

**[D]** Browser locale o remoto autorizzato — stesso computer, iPad/tablet, altro computer della LAN, eventualmente remoto. Espone, secondo le capability (§4): transport, REC/STOP/PLAY, arm/mute/solo/monitor, tracce, meter, navigazione timeline, marker/regioni, funzioni derivate da SOLO Recorder, gobbo, eventuali controlli mixer/FX.

### 10.1 Console audio di regia (Program / Talkback / Aux)

**[D]** La pagina Control deve poter acquisire almeno **tre sorgenti logiche**:

- **PROGRAM / DAW**: feed dalla DAW. Il mix-minus si costruisce **a monte, nella DAW** — ZP Remote riceve un Program già corretto (§6). Arriva al browser/Media Bridge tramite Local Media I/O (§13).
- **TALKBACK**: microfono della regia. Sorgente separata, con almeno: source selector, meter, gain, mute, pulsante TALK/PTT.
- **AUX / EXTRA**: sorgente opzionale aggiuntiva (player, altra applicazione, ospite, altra uscita DAW, qualunque input disponibile). Almeno: source selector, meter, gain, mute.

**[D] La pagina Control è un piccolo mixer di contribution, non una DAW completa**:

```
PROGRAM ──┐
TALKBACK ─┼──► REMOTE MIX ──► WebRTC
AUX ──────┘
```

Per la v1 esce **una sola traccia WebRTC già mixata** — non è necessario mandare Program/Talkback/Aux come tre stem indipendenti, ma **il modello interno resta aperto** a questa possibilità futura. Con gli Observer si potrà avere in futuro `ARTIST MIX`/`OBSERVER MIX` con matrici sorgente/destinazione semplici, **senza trasformare ZP Remote in ipDTL o in una seconda DAW**.

### 10.2 Remote Send / Artist Return

**[D]** Il Remote Mix (§10.1) è ciò che esce verso l'Artist via WebRTC (Remote Send). Il microfono dell'Artist, ricevuto via WebRTC, arriva come sorgente **`ARTIST RETURN`** (§6): la pagina Control deve poter scegliere concettualmente **dove instradarlo nella DAW**; per REAPER questa scelta è governata dal Lua Adapter/routing locale (§7).

### 10.3 Operazioni di alto livello (SOLO Recorder)

**[D]** Le funzioni derivate da SOLO Recorder restano **operazioni di alto livello invocate** (`nextTake`, non la sequenza STOP → aspetta → trova ultimo item → +5s → arm → REC ricostruita nel browser). Le garanzie critiche (arm esclusivo, preroll, finalize recording, take region, insert/retake/alternate, undo/togli take) restano vicino a REAPER/DAW Adapter (§7).

---

## 11. Observer

**[D]** Per cliente, direttore, produttore, fonico, ospite occasionale. Capability configurabili: `receive_artist_audio`, `send_talkback`, `receive_video`, `send_video`. Non riceve obbligatoriamente gobbo/copione né controllo DAW.

**[D]** Come l'Artist Client (§9), è **browser-only**: nessun virtual cable richiesto, usa i device esposti dal sistema via API standard del browser.

**[A]** Numero massimo di observer supportati in v1: limite implementativo (Fase 3/4), non strutturale — il modello dati resta 1 artista + regia + 0..N observer.

---

## 12. Cue Model

**[D]** Il browser non deve reimplementare le convenzioni SRT della Suite (sarebbe un quarto parser indipendente, `ARCHITETTURA_ZP_STUDIO_SUITE.md` §2/§13). Il REAPER Adapter (§7) produce un **Cue Document** normalizzato dal modello dati reale della Suite (item, `P_NOTES`, `P_EXT:RythmoBand_*`, track testi, regioni, video, personaggi/note), e il browser lo consuma.

**[D] Correzione**: **Script Mode e Dynamic Gobbo Mode sono proprietà del renderer/client, non del singolo cue.** Un identico Cue Document deve poter essere mostrato **contemporaneamente**, da client differenti, in modalità diverse (un Control Client potrebbe guardarlo in Dynamic Gobbo Mode per seguire la sincronizzazione, mentre l'Artist lo legge in Script Mode per ripassare). Il cue porta solo il **timing oggettivo, se esiste** (start/duration, opzionale) — non un flag che dichiara come va renderizzato:

- **Script Mode** (proprietà del client): il testo si legge come copione/documento. Il timing può esistere sul cue ma il renderer sceglie di non farlo governare la visualizzazione. L'artista legge, scorre, cerca, ingrandisce/riduce, usa il documento anche quando il timecode non è significativo per lui.
- **Dynamic Gobbo Mode** (proprietà del client): lo stesso cue, nello stesso momento, viene sincronizzato alla timeline da un altro client — start/end, play position, video/timeline, regioni/sezioni governano evidenziazione e scorrimento **in quel client**.

Schema corretto (il campo `timing` è dato oggettivo del cue, mai un interruttore di modalità):

```json
{
  "id": "item-guid-o-indice",
  "text": "Battuta del personaggio.",
  "timing": {
    "start": 12.480,
    "duration": 2.150
  },
  "character_ref": "voce1",
  "section_ref": { "lane1": "Sezione A", "lane2": null },
  "source": { "srt_path": "...", "srt_file": "...", "cue_index": 42 },
  "highlights": ["termine1", "termine2"]
}
```

`timing` può essere assente per un cue puramente testuale (senza corrispondenza a un item temporizzato); quando presente, è **descrittivo** (dov'è il cue nel progetto), e sta al singolo client/renderer decidere se e come usarlo per governare lo scorrimento. `character_ref` collega al modello Actor/Personaggio (`07_Note_Personaggio.lua`); `section_ref` alla gerarchia di lane.

**[D] Non tradurre meccanicamente il Gobbo Lua in JavaScript.** Nel sistema web le responsabilità vanno separate:
- **REAPER Adapter**: conosce track testi, cue, note, personaggi, regioni, video, modifiche del progetto, eventuali comandi di editing.
- **Browser**: conosce layout, scroll, reading point, **modalità script/dynamic come stato del client**, font, highlight, fullscreen, preferenze locali.

---

## 13. External Media Ingress (via Local Media I/O)

**[D]** `Local Media I/O` è il livello astratto di instradamento audio **locale sulla macchina di regia**, con almeno due usi:

1. **Program in uscita**: portare il Program/DAW (§6, §10.1) dalla DAW al Media Bridge/browser Control.
2. **Ingresso di sorgenti esterne** ("External Media Ingress"): una risorsa esterna (una videochiamata, un player, un'altra applicazione, un ospite non-ZP, qualunque applicazione che produca audio sul computer — **solo esempi, mai dipendenze nominate**) entra come sorgente AUX (§10.1) o come input diretto DAW:

```
External App → Virtual Audio Device (Local Media I/O) → ZP Media Bridge / DAW
```

**[D]** `BlackHole` (o equivalente) **non è un componente architetturale di ZP Remote**: è solo una possibile soluzione **macOS** per il Local Media I/O. Analogamente possono esistere soluzioni Windows (loopback WASAPI o virtual cable equivalenti) o Linux (PipeWire) — sono **dettagli di piattaforma**, non parte del protocollo. Il virtual audio è utile **soprattutto lato regia**, per collegare DAW/applicazioni locali al Media Bridge — **non è un requisito per Artist/Observer**, che sono browser-only (§9, §11).

**[I]** Su macOS, BlackHole (GPLv3 — `REFERENCES_ZP_REMOTE.md`) resta il primo candidato concreto. Possibili modalità, da validare in Fase 0: input diretto REAPER, I/O del Media Bridge, build multicanale, Aggregate/Multi-Output Device, più endpoint virtuali.

**[D]** Non si progetta oggi un driver CoreAudio proprio, se un driver esterno maturo risolve il problema.

**[D] Internal Media ed External Media devono coesistere**, non essere una scelta esclusiva:
- **Internal Media**: ZP gestisce direttamente artist mic, talkback, observer, video (via WebRTC).
- **External Media**: una risorsa esterna si collega localmente tramite Local Media I/O; ZP continua a gestire ciò che gli compete — DAW, cue, session, permissions, eventuale artist WebRTC, routing.

---

## 14. WebRTC

**[D]** Trasporto per: microfono artista → studio, ritorno audio/talkback studio → artista, eventuale observer ↔ artista, video, eventuali stream aggiuntivi. Non usato per il control plane.

**[D] Disambiguazione esplicita, perché è un errore facile da fare**: "usare WebRTC" (le API native del browser — `getUserMedia`, `RTCPeerConnection`) **è core della v1**. "Costruire un nostro motore/protocollo di rete audio proprietario" (stile SonoBus — networking P2P custom, codec/jitter buffer proprietari) **è fuori scope**: non è "un'opzione fra le altre", è esplicitamente fuori perimetro per tutte le fasi 0-6 della roadmap, un'eventualità da considerare solo se il modello attuale mostrerà limiti reali.

**[I]** Riferimenti architetturali (studio, non codice da copiare — `REFERENCES_ZP_REMOTE.md`): SonoBus (networking P2P, Opus/PCM, signaling separato dal media, JUCE/AOO), SessionLinkPRO (SessionLinkPRO Solutions GmbH — registrazione professionale "far end" **via browser**, quindi il riferimento funzionale più vicino a ciò che vogliamo per l'Artist Client) e Source-Connect (Source Elements — riferimento funzionale/UX del settore doppiaggio, prodotto diverso da SessionLinkPRO, aziende diverse). Vedi `REFERENCES_ZP_REMOTE.md` per la correzione: nella prima stesura questi ultimi due erano stati impropriamente accorpati in una voce sola.

**[D]** Qualità **asimmetrica**: Artist → Studio privilegia la qualità registrabile più alta realisticamente ottenibile; Studio → Artist può privilegiare stabilità, intelligibilità e latenza.

**[A]** Non si dà per scontato che Opus sia sufficiente per una registrazione professionale — va testato in Fase 0. Resta aperta una futura possibilità di registrazione locale/double-ended con upload, PCM, o altro trasporto ad alta qualità — non implementata ora.

**[D] Nota di consolidamento (terza fase di riallineamento, 5 settembre 2026)**: un'analisi tecnica precedente (`Analisi-progetto-telecomando-remoto.md`, datata 4 settembre 2026, nel workspace separato `~/Documents/ZP/zp-telecomando-reaper/`) aveva proposto una "Strada C" per l'audio Artist in v1: delegare la videochiamata a uno strumento esterno (Meet/Teams o simile) e portarne l'audio in REAPER con un cavo audio virtuale (es. BlackHole), esplicitamente per evitare di costruire un proprio motore WebRTC in v1. **Questa strada è superata**: Paolo ha confermato che il WebRTC nativo del browser resta il meccanismo v1 per l'audio Artist/Observer, come descritto in questo paragrafo. Il resto di quell'analisi (bridge REAPER, riscrittura del Gobbo in HTML, struttura a due livelli Controller/Specchio) resta materiale di riferimento storico, non in contraddizione con l'architettura corrente — solo il punto sull'audio va considerato superato.

---

## 15. Local Media I/O (virtual audio)

**[D]** Vedi §13: `Local Media I/O` è il nome del livello astratto; BlackHole (macOS), soluzioni WASAPI-loopback (Windows) o PipeWire (Linux) sono dettagli implementativi di piattaforma, non parte del protocollo ZP Remote. Non richiesto per Artist/Observer (browser-only, §9/§11). Non va confuso con WebRTC (ruoli diversi — routing locale vs. trasporto di rete).

---

## 16. Sicurezza/autenticazione

**[A]** Non ancora deciso nel dettaglio — punti da affrontare prima della Fase 3 (Web Service / Session Engine, che ora include esplicitamente account/login, §8):
- modello di account/utente e login;
- link di accesso per sessione/partecipante (token-scoped);
- verifica delle capability **lato server**, non solo nascondendo controlli nella UI;
- cifratura del trasporto: WSS per il control plane, DTLS-SRTP nativo di WebRTC per il media plane;
- scadenza/revoca dei token di sessione.

---

## 17. TURN/signaling

**[D]** Il signaling applicativo (bootstrap SDP/ICE) passa dal control plane, gestito dal Session Engine (§5, §8).

**[D]** Paolo si è già dichiarato disposto a gestire un piccolo servizio sempre acceso per signaling/TURN.

**[A]** Self-hosted (es. coturn) vs. gestito da terzi, e dimensionamento: da decidere in Fase 0 (fattibilità) e Fase 6 (Hardening).

---

## 18. Failure/reconnect

**[A]** Punti minimi da coprire prima della Fase 6 (Hardening):
- artista disconnesso a metà registrazione: la cattura avviene lato REAPER/Media Bridge locale, non nel browser artista — una caduta di rete non dovrebbe far perdere l'audio già catturato fino all'istante della caduta, **da verificare concretamente in Fase 0**;
- riconnessione del control plane con re-sincronizzazione di sessione/capability;
- scadenza token durante una sessione attiva;
- **sample rate e clock differenti fra browser/OS/DAW**, e cambio dispositivo a sessione avviata — entrambi esplicitamente nella checklist della Fase 0 (Media Feasibility Spike);
- diagnostica/logging di rete (jitter, packet loss) — in scope Fase 6.

---

## 19. Punti ancora da validare (elenco consolidato)

1. Tecnologia esatta del control plane (WebSocket/WSS vs. alternative) — §5.
2. Se serva un percorso media più semplice del WebRTC per lo stesso computer/LAN stretta — §6.
3. Meccanismo di trasporto fra il processo REAPER/Lua e il resto del sistema — §7 (Fase 1, non Fase 0).
4. Dove gira il Session Engine e come si relaziona col servizio di signaling/TURN — §8.
5. Numero massimo di observer supportati in v1 — §11.
6. Configurazione Local Media I/O esatta per piattaforma (BlackHole/Aggregate su macOS, equivalenti Windows/Linux) — §13.
7. Se Opus sia adeguato per l'audio artist→studio professionale, o serva altro (PCM, double-ended recording) — §14.
8. Modello di sicurezza/autenticazione, incluso account/login — §16.
9. Self-hosted vs. gestito per TURN, dimensionamento — §17.
10. Comportamento di failure/reconnect, sample rate/clock differenti, cambio dispositivo — §18.
11. **Implementazione tecnica del mixer Program/Talkback/Aux → Remote Mix** (Web Audio API graph o equivalente) lato Control Client — §10.1.
12. **Meccanismo esatto di consegna del Program** dalla DAW al Media Bridge per piattaforma — §6/§13.

**Fase 0 (Architecture Freeze + Media Feasibility Spike) risponde ai punti 2, 6, 7, 10, 11, 12. La Fase 1 (REAPER Lua Adapter v0) risponde al punto 3. Le due fasi non si sovrappongono**: la Fase 0 valida il percorso media (browser↔WebRTC↔Media Bridge↔DAW come flusso audio), la Fase 1 costruisce il modello di controllo REAPER↔protocollo (dati, non audio) — vedi nota di disambiguazione in `ROADMAP_ZP_REMOTE.md`.

---

## 20. Diagrammi architetturali

### 20.1 Control plane

```
REAPER
  ↕
REAPER Lua Adapter
  ↕
ZP Remote Protocol
  ↕
Session Engine / Control Plane
  ↕
Web Clients
```

### 20.2 Media plane

```
REAPER / Local Audio
  ↕
Local Media I/O
  ↕
Media Bridge
  ↕
WebRTC
  ↕
Artist / Observer
```

### 20.3 Vista end-to-end (i due plane affiancati, con i punti di contatto)

```
                         ┌───────────────────────────┐
                         │          REAPER            │
                         │  (progetto, track, FX,     │
                         │   marker/regioni, cue)      │
                         └──────────────┬──────────────┘
                                        │  (routing locale / send)
                    ┌───────────────────┼───────────────────┐
                    │  CONTROL PLANE    │     MEDIA PLANE    │
                    │                   │                    │
          ┌─────────▼─────────┐   ┌─────▼──────────┐
          │ REAPER Lua Adapter │   │  Local Media I/O │
          │ (stato, comandi,   │   │ (Program out,    │
          │  meter numerici,   │   │  Artist Return in)│
          │  NIENTE PCM)       │   └─────┬──────────┘
          └─────────┬─────────┘         │
                    │                    │
          ┌─────────▼─────────┐   ┌─────▼──────────┐
          │  ZP Remote Protocol│   │  Media Bridge   │
          └─────────┬─────────┘   └─────┬──────────┘
                    │                    │
          ┌─────────▼─────────┐         │
          │ Session Engine /   │         │
          │ Control Plane      │         │
          │ (ruoli, capability,│         │
          │  token, signaling) │         │
          └─────────┬─────────┘         │
                    │                    │
                    │           ┌────────▼────────┐
                    │           │     WebRTC       │
                    │           └────────┬────────┘
                    │                    │
          ┌─────────▼────────────────────▼─────────┐
          │              Web Clients                 │
          │  Control (mixer P/T/A + comandi)          │
          │  Artist  (script/gobbo + mic + talkback)  │
          │  Observer (audio/video secondo capability) │
          └────────────────────────────────────────────┘
```

Nota: le due colonne (Control Plane / Media Plane) sono concettualmente separate per tutta la loro altezza — si incontrano solo ai due estremi (dentro REAPER/Local Audio in alto, dentro i Web Clients in basso), mai al centro. È la rappresentazione grafica della regola "DAW Adapter e Media Bridge non si fondono" (§2).

### 20.4 Prima bozza ASCII — ZP Control Beta

> Non è un mockup grafico definitivo: serve solo a fissare la logica operativa prima di svilupparla (i campi/pulsanti elencati da Paolo: stato connessione REAPER, stato Artist, Program/DAW, Talkback, Aux, meter, gain, mute/TALK, Remote Send, Artist Return, destinazione Artist Return verso la DAW, transport REAPER, piccolo elenco track/meter).

```
┌──────────────────────────────────────────────────────────────────────┐
│  ZP CONTROL — BETA                    REAPER: ●CONNESSO  Artist: ●ON │
├──────────────────────────────────────────────────────────────────────┤
│  TRANSPORT REAPER                                                    │
│   [|<]  [PLAY]  [STOP]  [●REC]     00:12:34.567     ARM: ●           │
├──────────────────────────────────────────────────────────────────────┤
│  CONSOLE                                                              │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                     │
│  │ PROGRAM/DAW │ │  TALKBACK   │ │  AUX/EXTRA  │                     │
│  │ src:[DAW-Out]│ │ src:[Mic-1] │ │ src:[Player]│                     │
│  │ meter |███░░|│ │ meter |██░░░|│ │ meter |░░░░░|│                    │
│  │ gain  [——●—] │ │ gain  [—●——] │ │ gain  [●————]│                    │
│  │ [MUTE]       │ │ [MUTE][TALK]│ │ [MUTE]       │                     │
│  └─────────────┘ └─────────────┘ └─────────────┘                     │
│         └──────────────┴──────────────┘                              │
│                     ▼                                                │
│           REMOTE MIX  |████░░| → [REMOTE SEND: ●ON]  → WebRTC        │
├──────────────────────────────────────────────────────────────────────┤
│  ARTIST RETURN                                                       │
│   src: Artist mic (WebRTC)   meter |███░░|                           │
│   destinazione in DAW: [Track: VO_MAIN ▾]     [ROUTE]                │
├──────────────────────────────────────────────────────────────────────┤
│  TRACCE / METER (REAPER)                                             │
│   VO_MAIN     arm:● mute:○ solo:○  |██████░░░░|  -6.2 dB             │
│   VO_INSERTS  arm:○ mute:○ solo:○  |░░░░░░░░░░|  -inf                │
│   REF/VIDEO   arm:○ mute:● solo:○  |███░░░░░░░|  -14.0 dB            │
└──────────────────────────────────────────────────────────────────────┘
```

---

*Documento prodotto da Claude (Cowork) il 5 settembre 2026, consolidato in `docs/agent/` come documento architetturale canonico di ZP Remote nella terza fase di riallineamento (chiusura della fase documentale, richiesta prima della Fase 0). Va letto insieme a `ARCHITETTURA_ZP_STUDIO_SUITE.md`, `REFERENCES_ZP_REMOTE.md`, `ROADMAP_ZP_REMOTE.md` e `docs/agent/CURRENT_ZP_REMOTE.md` (stato sintetico). Nessun codice scritto, nessuna dipendenza installata, nessun file applicativo toccato, nessun commit/push.*
