# FASE 0 — Media Feasibility Spike — Report

> Report sperimentale della Fase 0.0 (ricognizione) e Fase 0.1 (media spike browser↔browser) di ZP Remote. Riferimenti: `ARCHITETTURA_ZP_REMOTE.md` (§5 Control Plane, §6 Media Plane, §10.1 Console audio, §14 WebRTC), `ROADMAP_ZP_REMOTE.md` (Fase 0), `CURRENT_ZP_REMOTE.md`. Codice sperimentale in `experiments/zp-remote-media-spike/` (README lì per le istruzioni d'uso).
>
> **Stato di questo report**: la Fase 0.0 è completa. La Fase 0.1 è stata eseguita dal vivo da Paolo tre volte: primo giro (0.1a/0.1b) — connesso, pacchetti scambiati, ma il transceiver audio dell'Artist restava `recvonly` invece di `sendrecv`, quindi Artist non trasmetteva affatto a livello di trasporto; corretto. Secondo giro (0.1c) — dopo la correzione, RTP bidirezionale confermato reale su entrambe le direzioni (`ontrack`, pacchetti, codec Opus, `unmute`), ma **nessun audio realmente udibile**: verdetto `RTP FULL DUPLEX PASS / AUDIO END-TO-END FAIL`. Terzo giro (0.1d, appena concluso a livello di codice, test dal vivo ancora da eseguire) — rilettura punto-per-punto di entrambi i grafi Web Audio: nessuna connessione mancante trovata (a differenza del bug 0.1b, questa volta il codice risulta topologicamente corretto), quindi aggiunti probe reali a 3-4 punti distinti per lato, una modalità di bypass Web Audio, e toni di test locali indipendenti da WebRTC, per isolare a runtime dove il segnale sparisce. Nessun numero in questo report è inventato: dove non c'è una misura reale, è scritto esplicitamente "non misurato", non un valore plausibile.

---

## 1. Fase 0.0 — Ricognizione read-only del prototipo esistente

Cartella ispezionata: `~/Documents/ZP/zp-telecomando-reaper/` (non l'archivio LaCie — quello resta un volume distinto, `/Volumes/DISCO LACIE`, ora anch'esso raggiungibile su richiesta di Paolo ma non ispezionato in questa fase perché fuori perimetro).

| Componente | Stato | Riutilizzabile? | Fase ZP Remote potenziale | Note |
|---|---|---|---|---|
| `Telecomando originale reaper.html` + `REAPER control_files/main.js` (Web Remote nativo Cockos) | Completo, funzionante (è il prodotto REAPER stesso) | Riferimento (non codice da copiare — è di Cockos) | Fase 1 (Lua Adapter) | Polling HTTP puro (`TRANSPORT`, `TRACK`, `NTRACK`), nessun WebSocket/WebRTC, nessun audio/video, autenticazione solo password web server REAPER |
| `Web Remote Control Documentation.pdf`, `REAPER Config Variables.pdf` | Documentazione ufficiale Cockos | Riferimento | Fase 1 | Utili per le variabili/stato esposti nativamente da REAPER |
| `Video Processor Documentation.pdf` | Documentazione ufficiale Cockos | Non pertinente per ora | — | Riguarda effetti video su clip, non streaming esterno — confermata la valutazione già fatta nell'analisi storica del 4 settembre |
| `WebRemoteInterface*.zip`, `ReaperWRB_2.2.2.zip`, `ultraschall_api5.zip` | Non più presenti in locale (archiviati esternamente per liberare spazio, solo citati in `Analisi-progetto-telecomando-remoto.md`) | Non verificabile ora | — | `PROJECT_STATE.md` conferma l'archiviazione (~14.6 MB liberati da Sync) |
| `ZP_Solo_Recorder_WebRemote/app/` (`index.html`, `app.js`, `styles.css`, `manifest.json`) | UI-only: nessuna rete, REC/STOP/SAVE simulati con un timer locale, nessuna chiamata a REAPER | Riutilizzabile **come riferimento visivo/UX**, non come codice diretto | Fase 2 — ZP Control Beta (solo linguaggio visivo) | **Attenzione al nome**: questo è il "ZP Solo Recorder *Web Remote*" (interfaccia di controllo remoto), un artefatto diverso da `25_ZP_SOLO_Recorder.lua` della ZP Studio Suite — stesso dominio (registrazione solista) ma due cose distinte, da non confondere in Fase 2 |
| `ZP_Solo_Recorder_WebRemote/docs/design-direction.md` | Documento di direzione UX/visiva | Riutilizzabile come riferimento | Fase 2 | Palette dark/graphite, modalità Mini/Compact/Expanded, regola "azioni pericolose richiedono conferma": pattern validi anche per ZP Control Beta |
| `ZP_Solo_Recorder_WebRemote/reference-notes/`, `assets/` | Vuote | Non pertinente | — | Nessun contenuto da valutare |
| `AGENTS.md` (workspace `zp-telecomando-reaper`) | Proprio di quel workspace, distinto da `zp-suite/AGENTS.md` | Non pertinente come punto di ingresso (superato) | — | Regola isolata utile: "non inizializzare Git senza approvazione" — non in conflitto con `zp-suite` |
| `PROJECT_STATE.md` (workspace `zp-telecomando-reaper`) | Snapshot del 5 settembre di quel workspace | Riferimento storico | — | Sovrapposto/superato da `CURRENT_ZP_REMOTE.md` |
| `Roadmap-progetto.md` (workspace `zp-telecomando-reaper`) | Roadmap a 6 fasi, numerazione e scope diversi da `ROADMAP_ZP_REMOTE.md` | Superato architetturalmente | — | Costruita attorno alla "Strada C" (Meet/Teams + BlackHole), già segnata come superata |
| `Analisi-progetto-telecomando-remoto.md` | Analisi tecnica dettagliata del 4 settembre | Misto: superato (sezione audio, Strada C) + riferimento (framing "Livello 1/Livello 2", idea di separare la logica REAPER-side dal rendering client-side per il Gobbo) | Fase 5 (Cue/Gobbo) per l'idea di separazione logica/rendering | Contraddizione già chiusa nella nota di consolidamento in `ARCHITETTURA_ZP_REMOTE.md` §14 |
| `0400000000402_....webp` | Immagine isolata | Non pertinente | — | Nessuna indicazione di rilevanza architetturale |
| Esperimenti OSC/WebSocket/WebRTC preesistenti | **Nessuno trovato** | — | — | `app.js` del prototipo non contiene alcuna chiamata di rete: la Fase 0.1 è il primo codice di rete reale di tutta questa linea di lavoro |

**Conflitto tecnico grave?** Nessuno oltre a quello già risolto (Strada C vs. WebRTC nativo, chiuso da Paolo nel turno precedente). Si procede quindi automaticamente alla Fase 0.1, come da istruzioni.

---

## 2. Fase 0.1 — Cosa è stato costruito

Codice in `experiments/zp-remote-media-spike/` (16 file, vanilla JS/HTML/CSS, nessuna dipendenza da installare, nessun framework, nessun build step):

- **`studio/`**: acquisisce PROGRAM, TALKBACK, AUX come tre `InputPanel` indipendenti (device select, checkbox AEC/NS/AGC, gain, mute, meter live da `AnalyserNode`); TALKBACK parte muto con pulsante TALK/PTT a pressione; le tre catene confluiscono in un `MixBus` (Web Audio) che produce un solo `MediaStreamTrack` — il Remote Mix — assegnato al sender audio via `RTCRtpSender.replaceTrack()`. Riceve il track audio/video dell'Artist (`ontrack`) e lo tratta come **Artist Return** (meter, mute locale, gain di monitor).
- **`artist/`**: mic con `InputPanel` dedicato, instradato via Web Audio verso una `MediaStreamAudioDestinationNode` propria (così il mute silenzia l'invio senza silenziare il meter locale); camera opzionale (decisa prima della connessione, cambiabile a sessione attiva via `replaceTrack()` sul sender video); selezione output via `HTMLMediaElement.setSinkId()` quando supportato dal browser; riceve il Remote Mix e lo instrada su un `MonitorSink` (Web Audio + `<audio>` nascosto) per meter + volume + scelta output.
- **Signaling**: nessun server dedicato. Due canali sempre attivi in parallelo — `BroadcastChannel` (auto, stessa macchina/stesso browser) e copia/incolla manuale (funziona anche fra macchine diverse in LAN). ICE non-trickle: si attende `icegatheringstate === "complete"` prima di scambiare l'SDP, per tenere lo scambio a un solo blocco di testo per direzione.
- **Stats**: `RTCPeerConnection.getStats()` interrogato ogni secondo (`shared/stats.js`), con calcolo del bitrate dai delta di byte fra due poll, codec risolto da `codecId`, jitter/packet-loss/RTT letti direttamente dai report `inbound-rtp`/`candidate-pair`. Esportabile in JSON.
- **Log/diagnostica**: pannello log con timestamp relativi alla sessione, timer di sessione, export log in `.txt`/`.json`.
- **Un dettaglio architetturale emerso costruendo lo spike**, utile anche oltre la Fase 0: **Program/Talkback/Aux e il microfono Artist non richiedono mai `RTCRtpSender.replaceTrack()` per cambiare dispositivo**, perché passano tutti attraverso un nodo Web Audio (`MixBus`/`MediaStreamAudioDestinationNode`) la cui identità di `MediaStreamTrack` resta stabile: si scambia solo la sorgente a monte. `replaceTrack()` resta necessario solo per la camera (video), che non passa da Web Audio. È un indizio concreto per la futura decisione sugli stem separati: se in futuro Program/Talkback/Aux diventassero stem WebRTC indipendenti invece di un unico Remote Mix, *allora* ciascuno avrebbe bisogno del proprio sender e quindi di `replaceTrack()` per il cambio dispositivo — un costo in più da tenere presente quando si valuterà quella evoluzione (`ARCHITETTURA_ZP_REMOTE.md` §10.1, "aperto a stem separati in futuro").

### Verifiche statiche effettuate (queste sì, eseguite realmente)

- `node --check` su tutti i 9 moduli JS: **nessun errore di sintassi**.
- Server locale (`server.py`, libreria standard Python, nessuna dipendenza) avviato e interrogato con `curl`: `studio/index.html`, `studio/studio.js`, `artist/index.html`, `artist/artist.js`, `shared/audio-graph.js` rispondono tutti `HTTP 200` con il contenuto atteso.

---

## 3. Perché non è stato eseguito un test live con dispositivi audio reali

Motivo tecnico preciso, non una scelta di comodo: il server locale (`server.py`) è stato avviato con successo, ma **il processo non sopravvive oltre la singola chiamata shell di questo ambiente** — ogni chiamata allo strumento che opera sul Mac di Paolo è una shell nuova, e i processi in background lanciati al suo interno (anche con `nohup`/`disown`) vengono terminati quando quella chiamata finisce, per come è isolato questo ambiente. Verificato empiricamente: il processo compariva con un PID subito dopo l'avvio, ma un secondo dopo `ps aux` non lo trovava più.

Di conseguenza non è stato possibile tenere il server acceso abbastanza a lungo da aprire due schede del browser reale, concedere i permessi di microfono/camera (che richiedono comunque un click umano su un prompt nativo del sistema operativo/browser — non qualcosa che va automatizzato alla cieca) e raccogliere `getStats()` reali.

**Cosa è realmente pronto**: tutto il codice, verificato staticamente come sopra. **Cosa manca**: l'esecuzione dal vivo, che richiede che il server resti acceso in un terminale reale (quello di Paolo, non una chiamata isolata di questo ambiente).

### Come completare la Fase 0.1 (per Paolo, o per un turno successivo con Paolo presente)

1. Aprire Terminale su Mac, `cd` in `zp-suite/experiments/zp-remote-media-spike`, eseguire `python3 server.py` e lasciarlo acceso.
2. Aprire `http://localhost:8743/studio/` e `http://localhost:8743/artist/` in due schede Chrome/Chromium (o due dispositivi in LAN, sostituendo `localhost` con l'IP LAN).
3. Concedere i permessi di microfono (e camera, se si vuole testare anche quella).
4. Seguire il flusso in `experiments/zp-remote-media-spike/README.md` §"Flusso di test consigliato".
5. Esportare log e stats con i pulsanti a fondo pagina, e passarmeli (o lasciarli nella cartella) perché io li integri in questo report con numeri reali.

---

## 4. Dati WebRTC misurati

**Nessuno.** Non essendo stata eseguita una sessione live, non ci sono browser/versione, sistema operativo, dispositivi selezionati, sample rate, codec negoziato, bitrate, RTT, jitter, packet loss, comportamento echo cancellation/AGC/NS reali da riportare. Compilarli ora sarebbe inventare risultati non misurati — esplicitamente vietato dall'incarico.

## 5. Comportamento multi-input

Non testato dal vivo. Il codice supporta strutturalmente l'apertura di tre `getUserMedia` indipendenti (anche sullo stesso `deviceId` ripetuto tre volte, per testare il limite "stesso dispositivo aperto tre volte") — se il browser lo permetta davvero, sulla macchina di Paolo, con l'hardware/i dispositivi virtuali realmente disponibili, resta da verificare.

## 6. Clock e sample rate

Non testato dal vivo — nessuna osservazione reale su resampling, drift, drop/click con Program e Talkback da dispositivi diversi.

## 7. Comportamento device switching, problemi browser, limiti

Non testato dal vivo. Il meccanismo implementato (vedi §2, nota su `replaceTrack()`) è pronto per essere osservato in pratica.

## 8. Cosa questo implica per il futuro Local Media I/O

Ancora nulla di nuovo rispetto a `ARCHITETTURA_ZP_REMOTE.md` §13/§15 — nessuna decisione presa, perché nessun dato reale la sosterrebbe ancora. Resta valida l'impostazione già scritta: PROGRAM da REAPER → Media Bridge e ARTIST RETURN → REAPER sono il prossimo problema, non affrontato in questo spike.

## 9. Decisioni che possiamo prendere ora

Nessuna nuova decisione architetturale. L'unica cosa confermata è che **il codice del media plane più piccolo possibile, con WebRTC reale, Web Audio reale, tre sorgenti logiche miscelate in un solo Remote Mix, è scrivibile senza incontrare blocchi strutturali** — questo di per sé è un'informazione utile (nessun ostacolo API-level è emerso scrivendo il codice), ma non sostituisce la misura reale richiesta dal gate di uscita della Fase 0.1.

## 10. Questioni rimaste aperte

Tutte quelle elencate nell'incarico originale (browser/versione, dispositivi, sample rate, latenza, jitter/loss, codec, bitrate, echo cancellation/AGC/NS onorati o meno, cambio dispositivo a sessione attiva, mute/unmute, riconnessione, comportamento con tre input contemporanei) restano aperte fino all'esecuzione live descritta in §3.

## 11. Verdetto

**Nessuno dei tre verdetti richiesti (GO / GO WITH LIMITATIONS / NO-GO) è determinabile onestamente da questo report**, perché nessuno dei due si basa su dati misurati — richiederebbe di scegliere un verdetto sulla fiducia, esattamente quello che l'incarico ha vietato esplicitamente ("non inventare risultati non misurati").

**Stato al termine del primo giro** (prima del debug pass 0.1b): connessione stabilita, trasporto WebRTC confermato reale (pacchetti, codec Opus 48 kHz, `setSinkId()`), ma audio non ancora udibile — vedi sotto per la causa più probabile e la correzione applicata. Il gate di uscita della Fase 0.1 resta da riverificare con un nuovo test dal vivo.

---

## Debug pass 0.1b — audio path

> Incarico di correzione mirata, sulla base del test reale eseguito da Paolo: connessione WebRTC stabilita, pacchetti audio scambiati, codec Opus negoziato, ma nessun audio effettivamente udibile end-to-end. Nessuna modifica architetturale, nessuna nuova decisione — solo diagnosi e correzione minima dello spike.

### Bug trovati (causa più probabile — questa volta confermata sui log/stats reali del test di Paolo, non solo per lettura del codice)

Prima di correggere qualunque cosa, sono stati letti i 6 file esportati dal test reale (`log_nogit/`: `*-studio-log.txt/.json`, `*-artist-log.txt/.json`, `*-studio-stats.json` 175 campioni, `*-artist-stats.json` 168 campioni). Questi dati, non ipotesi, sono la base della diagnosi che segue.

**Evidenza reale, nell'ordine in cui è stata trovata:**

| Osservazione nei dati reali | File | Cosa implica |
|---|---|---|
| `inbound` è `null` in **tutti i 175 campioni** stats di Studio | `zp-remote-spike-studio-stats.json` | Studio non ha mai ricevuto un solo pacchetto RTP audio dall'Artist, per l'intera sessione — non "audio silenzioso", proprio nessun report `inbound-rtp` |
| `outbound` è `null` in **tutti i 168 campioni** stats di Artist | `zp-remote-spike-artist-stats.json` | Simmetrico al punto sopra: il sender audio dell'Artist non ha mai prodotto un report `outbound-rtp` — il trasporto non ha mai trasmesso nulla in quella direzione, non solo silenzio digitale |
| **Zero** righe "ontrack ricevuto" nel log di Studio, per l'intera sessione | `zp-remote-spike-studio-log.txt` | L'evento `ontrack` non è mai scattato lato Studio per il track audio dell'Artist — non un'eccezione silenziosa dentro l'handler, proprio nessuna chiamata |
| Il log dell'Artist mostra invece `ontrack ricevuto: kind=audio` subito dopo aver applicato l'offerta | `zp-remote-spike-artist-log.txt/.json` | L'Artist riceve regolarmente il Remote Mix di Studio — la direzione Studio→Artist funziona fin da subito |
| `outbound` (Studio→Artist) sano per tutta la sessione: Opus 48kHz, 609851 byte, 8799 pacchetti, ~24 kbps | `zp-remote-spike-studio-stats.json` | Il trasporto WebRTC in sé funziona: il problema è specifico alla direzione Artist→Studio, non un problema generale di rete/ICE |

Queste tre osservazioni (inbound Studio sempre assente, outbound Artist sempre assente, ontrack Studio mai scattato) sono **lo stesso fenomeno visto da tre angolazioni diverse**, e puntano a una causa a livello di negoziazione SDP, non a un bug applicativo nel post-processing del track — perché un report `inbound-rtp`/`outbound-rtp` esiste (o non esiste) indipendentemente da qualunque eccezione JavaScript nell'handler `ontrack`.

**Causa primaria confermata — il transceiver audio dell'Artist restava `recvonly`, mai alzato a `sendrecv`.**

In `artist.js`, `acceptOffer()` collega il microfono così (codice prima della correzione):

```js
const audioTransceiver = pc.getTransceivers().find((t) => t.receiver.track.kind === "audio");
const micTrackForSender = micSendDest.stream.getAudioTracks()[0];
await audioTransceiver.sender.replaceTrack(micTrackForSender);
// createAnswer() veniva chiamato subito dopo, senza mai toccare .direction
```

Quando l'Artist (answerer) processa l'offerta remota di Studio con `setRemoteDescription()`, per ogni m-line senza un transceiver già esistente il browser ne crea uno nuovo con `direction` di default **`"recvonly"`** — anche se l'offerente (Studio) aveva dichiarato `sendrecv`. `RTCRtpSender.replaceTrack()` collega un track al sender ma **non modifica `.direction`**: se l'app non lo alza esplicitamente a `"sendrecv"` prima di `createAnswer()`, la risposta SDP dichiara comunque `recvonly` — e quel m-line resta di fatto disabilitato-in-invio per tutta la sessione. Nessun errore, nessuna eccezione: `replaceTrack()` ha successo, il microfono/local monitor funzionano perfettamente lato locale, ma RTP non parte mai in quella direzione.

La riga poco più sotto nello stesso file, per la **camera**, faceva già la cosa giusta:

```js
await videoTransceiver.sender.replaceTrack(cameraStream.getVideoTracks()[0]);
videoTransceiver.direction = "sendrecv";   // <-- questa riga mancava per l'audio
```

Il bug era quindi un'incoerenza tra i due rami (video corretto, audio no) — non un problema architetturale, un dettaglio dimenticato in un punto solo. Questo spiega esattamente tutte e tre le osservazioni della tabella: Studio non riceve nulla (Artist non trasmette mai), Artist non produce `outbound-rtp` (la sua stessa direzione negoziata esclude l'invio), e `ontrack` non scatta mai lato Studio (l'answer dell'Artist dichiara `recvonly`, quindi Studio non riceve mai il segnale "il remoto sta inviando" che fa scattare `ontrack`).

**Bug secondario, reale ma non ancora esercitato da questo test — `event.streams` vuoto in `ontrack`.**

Sia `studio.js` che `artist.js` costruiscono il `RTCPeerConnection` con `addTransceiver("audio"/"video", {...})` **senza** l'opzione `streams`, quindi nessun `msid` viene negoziato nell'SDP per quel m-line — `RTCTrackEvent.streams` può arrivare **vuoto** (`[]`) lato remoto. Il codice originale faceva `const [stream] = event.streams` seguito da `ctx.createMediaStreamSource(stream)`, che lancia un `TypeError` sincrono se `stream` è `undefined` — dentro un handler che nessuno intercetta. In *questo* test non è la causa dei sintomi osservati (perché, come sopra, `ontrack` lato Studio non è mai scattato affatto — l'eccezione non ha mai avuto modo di verificarsi), ma è un bug reale e latente: **appena la causa primaria viene corretta, `ontrack` inizierà a scattare per davvero lato Studio**, ed è a quel punto che questo secondo bug diventerebbe concretamente rilevante. Corretto comunque, in via preventiva, per lo stesso motivo per cui era già stato identificato: robustezza minima richiesta per interpretare correttamente il prossimo test.

**Bug terziario (ipotesi, non ancora confermata/esclusa) — `audioElement.play()` senza gestione visibile dell'errore, lato Artist.**

`MonitorSink.play()` convertiva un eventuale `NotAllowedError` (blocco autoplay) in un semplice `return false`, senza loggarlo né mostrarlo in UI. Non emerge dai log di questo test (l'Artist riceveva già audio da Studio e l'esito di `play()` non era ancora loggato nella versione di codice usata nel test), ma resta un punto cieco plausibile per il prossimo giro — ora reso visibile con logging esplicito e indicatore UI (vedi sotto).

### Modifiche minime apportate

Tutte contenute in `experiments/zp-remote-media-spike/` — nessun'altra parte del repository toccata.

0. **`artist/artist.js`, `acceptOffer()` — IL FIX PRINCIPALE.** Aggiunta una riga sola, subito dopo `replaceTrack()` e prima di `createAnswer()`: `audioTransceiver.direction = "sendrecv";` — la stessa cosa che il ramo video faceva già. Log arricchito per mostrare la direzione auto-creata dal browser prima del fix (`transceiverDirectionAutoCreata`) e quella effettiva dopo (`transceiverDirectionDopoFix`), così un prossimo test la conferma da solo senza dover rileggere il codice.
1. **`studio/studio.js` e `artist/artist.js`** — `handleRemoteTrack()` non fa più affidamento su `event.streams`: costruisce sempre lo stream con `event.streams[0] || new MediaStream([event.track])`. Aggiunto logging esplicito su ogni `ontrack`: `readyState`, `muted`, `enabled` del track, numero di stream ricevuti, se è stato usato il fallback, più listener su `mute`/`unmute`/`ended` del track remoto.
2. **`artist/artist.js`** — `tryPlayMonitor()` ora logga esito e causa di `audioElement.play()` in modo esplicito e aggiorna un indicatore visibile in UI (`playback: attivo` / `playback: BLOCCATO`); aggiunto un bottone "Abilita audio" che rilancia `ctx.resume()` + `play()` da un click reale, per i casi in cui l'autoplay resti bloccato anche dopo il fix del bug primario.
3. **Indicatore di stato AudioContext** (`audio: running/suspended`) aggiunto in entrambe le pagine, con bottone "Riattiva/Abilita audio" — prima lo stato dell'AudioContext non era mai visibile.
4. **TEST TONE 440 Hz** (Studio): oscillatore Web Audio iniettabile direttamente nel Remote Mix, ON/OFF, livello basso di default — per isolare il tubo Studio→Artist da DAW/microfoni/routing fisico durante il prossimo test.
5. **LOCAL MONITOR** (Artist, OFF di default, volume basso): conferma indipendente che il microfono selezionato produce campioni reali.
6. **Meter separati lato Artist**: "Remote stream ricevuto" (pre-gain, subito dopo `ontrack`) e "Output playback" (post-gain locale) — prima esisteva un solo meter combinato, che non permetteva di distinguere "non arriva nulla" da "arriva ma si perde dopo".
7. **Log esplicito sender/transceiver** in entrambe le pagine al momento dell'offerta/risposta: conferma via log che il sender audio è collegato al track stabile (mix bus / `micSendDest`) prima ancora che Program/Talkback/Aux o il microfono siano stati avviati — vedi "Strategia sender/transceiver" più sotto.
8. **Stats UI**: etichette esplicite "outbound = ... verso l'altra pagina" / "inbound = ... ricevuto da questa pagina", valori mancanti mostrati come `n/d` invece di `-` per non farli leggere come zero. Ogni sample esportato ora porta anche `role: "studio"|"artist"`.
9. **`README.md`**: nuovo ordine di test consigliato (vedi sotto) e descrizione delle diagnostiche aggiunte.

### Strategia sender/transceiver (confermata, non cambiata nell'architettura — con un tassello aggiunto)

- **Program/Talkback/Aux (Studio) e microfono (Artist) non passano mai da `RTCRtpSender.replaceTrack()` per il cambio o l'avvio a sessione già negoziata**, perché ciascuno confluisce in un nodo Web Audio stabile (`MixBus`/`MediaStreamAudioDestinationNode` per lo Studio, `micSendDest` per l'Artist) la cui identità di `MediaStreamTrack` non cambia mai. Il sender viene collegato a quel track stabile **una sola volta**, al momento della creazione dell'offerta/risposta — prima ancora che una qualunque sorgente reale sia stata avviata. Avviare una sorgente prima o dopo la negoziazione è quindi equivalente: cambia solo quando il grafo Web Audio inizia a produrre segnale reale invece di silenzio, non la topologia WebRTC. **Questa parte era corretta ed è confermata dai dati.**
- **`replaceTrack()` resta necessario solo per la camera** (video), che non passa da Web Audio: lo swap camera a sessione attiva lo usa esplicitamente (`artist.js`, `swapCamera()`).
- **Tassello che mancava, ora aggiunto**: collegare un track al sender con `replaceTrack()` non è sufficiente perché quel track venga davvero trasmesso — bisogna anche che `transceiver.direction` includa `"send"`. Sul lato che crea l'offerta (Studio), questo è naturale perché il transceiver viene creato esplicitamente dall'app con la direzione voluta (`addTransceiver("audio", { direction: "sendrecv" })`). Sul lato che risponde (Artist), il transceiver viene creato *automaticamente* dal browser processando l'offerta remota, con `direction` di default `"recvonly"` — e va alzato esplicitamente a `"sendrecv"` **prima** di `createAnswer()`, altrimenti resta di fatto in sola ricezione. Regola pratica per questo spike (e utile oltre): ogni volta che un sender viene collegato a un track su un transceiver **creato automaticamente lato answerer**, verificare/impostare `.direction` esplicitamente, non fidarsi del default.
- Nessuna rinegoziazione (`createOffer`/`setLocalDescription` una seconda volta) è richiesta in nessuno dei casi sopra: il fix è impostare `.direction` all'interno dello stesso ciclo di negoziazione iniziale, prima della prima `createAnswer()` — non una rinegoziazione successiva.

### Cosa viene ora misurato/diagnosticato che prima non lo era

- Stato dell'AudioContext in tempo reale (entrambe le pagine).
- Esito esplicito di `audioElement.play()` e causa del fallimento, se presente (Artist).
- Se `ontrack` ha ricevuto uno stream valido dall'evento o ha dovuto usare il fallback.
- `readyState`/`muted`/`enabled` di ogni track remoto ricevuto, ed eventi `mute`/`unmute`/`ended` successivi.
- Livello del segnale in due punti distinti del percorso di ricezione Artist (pre-gain e post-gain), non più uno solo.
- Segnale di test (440 Hz) indipendente da qualunque dispositivo fisico, per isolare il tubo Studio→Artist.
- Conferma via log che il sender è collegato al track stabile prima dell'avvio delle sorgenti reali.

### Cosa resta da provare manualmente

Tutto quanto elencato nelle sezioni 4-10 di questo report **va ripetuto da capo** con il codice corretto, seguendo il nuovo ordine in `README.md`: in particolare, se il TEST TONE si sente lato Artist, il bug primario è risolto e si può passare a Program/Talkback/Aux reali; se non si sente ma il meter "Remote stream ricevuto" si muove, resta da indagare il bug secondario (autoplay) con l'aiuto del nuovo indicatore "playback:"; se anche quel meter resta piatto, il problema è ancora a monte e va riaperto un nuovo giro di diagnosi mirata sul trasporto stesso.

---

## Debug pass 0.1c — Full Duplex Verification (risultato del test dal vivo)

Test eseguito da Paolo su Chrome dopo la correzione del transceiver (0.1b). Verdetto dichiarato da Paolo sulla base dell'osservazione diretta:

**`RTP FULL DUPLEX PASS / AUDIO END-TO-END FAIL`**

Confermato realmente:
- `outbound-rtp` e `inbound-rtp` audio presenti e attivi in entrambe le direzioni (Studio→Artist e Artist→Studio), pacchetti/byte in crescita.
- `ontrack kind=audio` presente sui log di entrambe le pagine (il bug 0.1b — direzione `recvonly` non alzata — risulta quindi corretto: Studio ora riceve il segnale di negoziazione che prima mancava del tutto).
- Le remote track arrivano a `unmute`.
- Codec Opus 48 kHz, packet loss osservato 0.
- Lato Artist: `AudioContext` è `running`, `audioElement.play()` restituisce successo.

Non confermato: **Paolo non sente né il Test Tone 440 Hz su Artist né l'Artist Return su Studio.** Il trasporto WebRTC bidirezionale funziona; l'audio non arriva fisicamente alle orecchie. Non è quindi un problema di HTTP/signaling/ICE (già escluso in 0.1a/0.1b/0.1c) — l'incarico successivo (0.1d) è stato mirato esclusivamente a isolare dove, fra il `MediaStreamTrack` remoto e l'uscita fisica, il segnale sparisce.

---

## Debug pass 0.1d — Audio Graph Forensics

### Grafo reale trovato nel codice PRIMA di queste modifiche

**Studio ← Artist Return** (`studio.js`, `handleRemoteTrack`): `remoteTrack` → `new MediaStream([track])` (fallback già in vigore da 0.1b) → `ctx.createMediaStreamSource(stream)` (`source`) → `source.connect(analyser)` (meter "Artist Return") **e** `source.connect(gain)` → `gain.connect(ctx.destination)`. Nessun elemento `<audio>` in questo percorso: l'uscita è l'`AudioContext.destination` del tab Studio (il device di output di sistema di quel tab, non selezionabile con `setSinkId()` in questo spike).

**Artist ← Remote Mix** (`artist.js`, `handleRemoteTrack` + `MonitorSink` in `audio-graph.js`): `remoteTrack` → `new MediaStream([track])` → `ctx.createMediaStreamSource(stream)` (`source`) → `source.connect(preAnalyser)` (meter "Remote stream ricevuto") **e** `monitorSink.connectSource(source)` cioè `source.connect(monitorSink.gain)` → `monitorSink.gain.connect(monitorSink.analyser)` (meter "Output playback") **e** `monitorSink.gain.connect(monitorSink.dest)` (un `MediaStreamAudioDestinationNode`) → `monitorSink.dest.stream` assegnato a `audioElement.srcObject` **alla creazione di `MonitorSink`** (prima ancora che `ontrack` scattasse) → `audioElement.play()`.

### Connessione/nodo mancante trovato?

**No.** A differenza del bug 0.1b (una riga di codice mancante, dimostrabile e netta), la rilettura punto-per-punto di entrambi i grafi non ha trovato nessun `.connect()` mancante, nessun nodo scollegato, nessuna assegnazione `srcObject` mai eseguita: topologicamente entrambi i percorsi arrivano da `ontrack` fino al nodo/elemento finale. Questo è un dato in sé: **il bug (se di grafo si tratta) non è visibile per lettura statica del codice** — motivo per cui l'incarico ha richiesto probe reali a runtime invece di un'altra correzione "a occhio". Le cause plausibili restano, in ordine di probabilità, tutte esterne al grafo Web Audio così come scritto: routing dell'output fisico (tab audio mutato, device di sistema sbagliato, volume del tab a zero), contenuto realmente silenzioso nel track anche se "unmuted" (silenzio digitale trasmesso correttamente), o un comportamento del browser non riproducibile dalla sola lettura del codice.

### Modifiche applicate (diagnostica, non funzionalità permanenti)

Tutte in `experiments/zp-remote-media-spike/`, nessun'altra parte del repository toccata:

1. **`shared/meter.js`**: `Meter` accetta ora un `stateEl` opzionale che mostra testualmente `signal`/`silence` in base a una soglia di picco (-50 dB di default) — per leggere un probe come un fatto, non un grafico da interpretare a occhio.
2. **`shared/stats.js`**: cattura, dove il browser li espone, `audioLevel`/`totalAudioEnergy`/`totalSamplesDuration` sull'`inbound-rtp`, e gli equivalenti dal report `media-source` collegato per l'`outbound-rtp` (`sourceAudioLevel`/`sourceTotalAudioEnergy`). Packets/bytes grezzi ora sempre visibili in UI, non solo il bitrate calcolato.
3. **`shared/input-panel.js`**: il log di avvio/cambio sorgente ora riporta esplicitamente `constraintRichiesto` (cosa è stato chiesto a `getUserMedia`) separato da `settingApplicatoDalBrowser` (`track.getSettings()` reale) — vale per Program/Talkback/Aux e per il microfono Artist.
4. **`studio/studio.js` + `studio/index.html`**: 3 probe reali e distinti sul percorso Artist Return — **ARTIST_RTP_INPUT** (subito dopo `createMediaStreamSource`), **ARTIST_POST_SOURCE** (dopo un nodo passthrough di unità dedicato, inserito solo per avere un secondo punto di misura reale), **ARTIST_RETURN** (uscita del gain di monitor, il nodo esatto collegato a `ctx.destination`). Aggiunto **LOCAL TEST TONE (Studio)**: oscillatore diretto a `ctx.destination`, non passa mai da WebRTC — isola il monitor locale dello Studio da tutto il resto.
5. **`artist/artist.js` + `artist/index.html`**: 4 probe reali e distinti — **REMOTE_RTP_INPUT** (subito dopo `createMediaStreamSource`), **REMOTE_POST_SOURCE** (dopo un passthrough dedicato), **REMOTE_POST_GAIN** (uscita di `monitorSink.gain`, stesso punto del meter "Output playback"), **REMOTE_PLAYBACK_DEST** (ri-letto creando un nuovo `MediaStreamAudioSourceNode` dal `MediaStream` REALE — `monitorSink.dest.stream` — cioè esattamente ciò che è assegnato a `audioElement.srcObject`, per chiudere davvero il cerchio invece di fidarsi che debba per forza coincidere con il nodo a monte). Aggiunto **LOCAL TEST TONE / TEST OUTPUT**: stesso `monitorSink`/`audioElement`/sink usato per il Remote Mix, non passa da WebRTC, funziona anche senza connessione attiva. Aggiunta **modalità playback selezionabile** (`DIRECT MEDIA ELEMENT` vs `WEB AUDIO PATH`, di default invariato) e un bottone **"Ispeziona output"** che logga device label/sinkId richiesto ed effettivo/volume/muted/paused/readyState dell'elemento audio.
6. **Stats UI (entrambe le pagine)**: nuove righe "packets/bytes" espliciti e "audioLevel / totalAudioEnergy", con nota esplicita che pacchetti > 0 non prova contenuto audio.
7. **`README.md`**: nuova sequenza di test A/B/C/D e descrizione dei tre gate distinti (NETWORK / AUDIO GRAPH / PHYSICAL OUTPUT).

### Supporto `totalAudioEnergy`/`audioLevel`

Il codice li richiede sempre; se il browser di Paolo non li espone su un dato report, i campi restano `null` → mostrati come "n/d" in UI, mai come zero. Da confermare con l'export reale se Chrome li popola per questi report specifici (`inbound-rtp` e `media-source` collegato all'`outbound-rtp`) nella versione installata.

### Sequenza esatta dei quattro test (da eseguire da Paolo, in ordine)

- **Test A — Output Artist locale**: bottone "LOCAL TEST TONE / TEST OUTPUT" su Artist, anche senza connessione attiva. Non udibile → STOP, problema nell'output locale (sink/volume/OS), non in WebRTC.
- **Test B — Direct WebRTC playback**: "Modalità playback" su Artist = `DIRECT MEDIA ELEMENT`, poi Test Tone di Studio via WebRTC. Udibile → trasporto WebRTC e output fisico confermati.
- **Test C — Web Audio playback**: stesso test, "Modalità playback" = `WEB AUDIO PATH`. Se B è udibile e C no → bug nel grafo Web Audio, individuabile guardando in quale dei 4 probe REMOTE_* il segnale passa da "signal" a "silence".
- **Test D — Artist Return**: voce nel mic Artist a sessione connessa, guardare i 3 probe ARTIST_* lato Studio e lo stats "inbound: audioLevel/totalAudioEnergy".

### Criterio per sapere dove sparisce il segnale

Il primo probe, nell'ordine del percorso, che mostra "silence" mentre il precedente mostra "signal" è il punto esatto di rottura. Studio→Artist: `Test Tone/Remote Mix` → `outbound Studio` (stats) → `inbound Artist` (stats) → `REMOTE_RTP_INPUT` → `REMOTE_POST_SOURCE` → `REMOTE_POST_GAIN` → `REMOTE_PLAYBACK_DEST` → uscita fisica (Test A). Artist→Studio: `Artist Mic` (meter locale) → `outbound Artist` (stats) → `inbound Studio` (stats) → `ARTIST_RTP_INPUT` → `ARTIST_POST_SOURCE` → `ARTIST_RETURN` → uscita fisica (Local Test Tone Studio).

### Nota Brave (non indagata in questo incarico)

Osservazione di Paolo, solo annotata: Brave con Shields disabilitati non ha avviato correttamente il microfono in un test manuale. Chrome resta il browser di riferimento della Fase 0.1; compatibilità Brave da verificare in un incarico successivo.

---

*Report prodotto da Claude (Cowork) il 5 settembre 2026, Fase 0.0 (ricognizione), Fase 0.1 (costruzione + verifica statica), debug pass 0.1b (diagnosi e correzione del percorso audio), debug pass 0.1c (verifica full duplex dal vivo: RTP confermato, audio fisico non confermato) e debug pass 0.1d (audio graph forensics: nessuna connessione mancante trovata nel codice, probe e test A/B/C/D aggiunti per isolare il punto di rottura a runtime) di ZP Remote. Nessun codice REAPER/Lua toccato, nessuna modifica alla ZP Studio Suite, nessuna modifica al prototipo `ZP_Solo_Recorder_WebRemote`, nessuna installazione di driver audio, nessun deploy, nessun commit/push. `CURRENT_ZP_REMOTE.md` non è stato aggiornato: né in 0.1c né in 0.1d si è raggiunto un `FULL DUPLEX PASS` o un `GO WITH LIMITATIONS` — il verdetto attuale resta `FAIL — DEBUG REQUIRED` in attesa dei test A/B/C/D dal vivo.*
