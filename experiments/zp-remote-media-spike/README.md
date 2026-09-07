# ZP Remote — Media Spike

> **EXPERIMENTAL / FASE 0 / NOT PRODUCT CODE.** Questo non è ZP Studio Suite, non entra in ReaPack, non collega REAPER, non implementa il Session Engine, non è un mockup grafico definitivo. Serve solo a rispondere sperimentalmente alle domande della Fase 0 — Architecture Freeze + Media Feasibility Spike (vedi `docs/agent/ROADMAP_ZP_REMOTE.md`). Cancellabile in blocco senza impatto sul prodotto: vive in `experiments/`, fuori da `ZP Studio Suite/`.

Riferimenti architetturali: `docs/agent/ARCHITETTURA_ZP_REMOTE.md` (in particolare §5 Control Plane, §6 Media Plane, §10.1 Console audio, §14 WebRTC), `docs/agent/CURRENT_ZP_REMOTE.md`.

## Cosa fa

Due pagine web statiche, senza framework, senza build step, senza dipendenze da installare:

- **`studio/`** — endpoint Studio/Control: acquisisce PROGRAM, TALKBACK, AUX come tre sorgenti indipendenti, le somma in Web Audio in un **Remote Mix**, e invia quel mix come un solo track audio via WebRTC. Riceve il microfono remoto dell'Artist come **Artist Return**.
- **`artist/`** — endpoint Artist: sceglie mic/camera/output di sistema via API browser standard (nessun cavo virtuale), invia il proprio microfono via WebRTC, riceve il Remote Mix dello Studio.

Entrambe usano **WebRTC reale** (`RTCPeerConnection`, `getUserMedia`), non una simulazione.

## Come avviarlo

```bash
cd experiments/zp-remote-media-spike
python3 server.py
```

Poi apri in Chrome/Chromium:

- `http://localhost:8743/studio/`
- `http://localhost:8743/artist/`

Due tab dello stesso browser sulla stessa macchina bastano per il primo test. Per due dispositivi in LAN, sostituisci `localhost` con l'IP LAN della macchina che fa da Studio (es. `http://192.168.1.23:8743/artist/` sul dispositivo remoto) — vedi "Limiti" sotto per gli avvertimenti su `getUserMedia` fuori da `localhost`.

## Segnalazione (signaling)

Nessun server di signaling dedicato: per questo spike sono attivi contemporaneamente due canali, entrambi minimi:

1. **BroadcastChannel** — se le due pagine sono nello stesso browser sulla stessa macchina, offerta/risposta si scambiano da sole, automaticamente.
2. **Copia/incolla manuale** — sempre visibile in entrambe le pagine: copia il testo dell'offerta dallo Studio, incollalo nell'Artist; copia la risposta dall'Artist, incollala nello Studio. Funziona anche fra due macchine diverse in LAN.

ICE non-trickle: si attende la fine della raccolta candidati prima di mostrare/inviare l'SDP (connessione leggermente più lenta, scambio più semplice da leggere/incollare a mano).

## Flusso di test — Full Duplex base (debug pass 0.1c, correzione transceiver applicata)

1. Avvia il server, apri Studio e Artist in due schede.
2. Su Artist, avvia il MIC. Su Studio, attiva il **TEST TONE 440 Hz**.
3. Su Studio premi "Crea offerta"; se il BroadcastChannel non basta, scambia manualmente offerta/risposta.
4. Verifica **connectionState/ice = connected su entrambe**, poi guarda i log: deve comparire `ontrack ricevuto: kind=audio` **su entrambe le pagine** (prima della correzione 0.1c mancava su Studio).
5. Verifica il tono udibile su Artist e il meter "Artist Return" su Studio.
6. Spegni il tono, prova Program, poi Talkback/Aux.
7. Esporta log e stats da entrambe le pagine.

## Test A/B/C/D — forensics del grafo audio (debug pass 0.1d)

Da usare se il full duplex base risulta `RTP FULL DUPLEX PASS / AUDIO END-TO-END FAIL` (pacchetti/ontrack/energia RTP presenti, ma niente di udibile) — per trovare esattamente dove sparisce il segnale fra il `MediaStreamTrack` remoto e l'uscita fisica.

- **Test A — Output Artist locale**: su Artist premi **LOCAL TEST TONE / TEST OUTPUT** (funziona anche senza alcuna connessione WebRTC attiva). Se non lo senti: STOP, il problema è nell'output locale (sink/volume/OS), non in WebRTC — non ha senso procedere oltre finché questo non si sente.
- **Test B — Direct WebRTC playback**: imposta su Artist il menu "Modalità playback" su **DIRECT MEDIA ELEMENT** PRIMA di accettare l'offerta, poi ripeti il test con il TEST TONE di Studio. Se si sente: il trasporto WebRTC e l'output fisico sono confermati, il problema (se c'è) è nel grafo Web Audio.
- **Test C — Web Audio playback**: stesso test, ma con "Modalità playback" su **WEB AUDIO PATH** (il default). Se Direct funziona e Web Audio no, il bug è nel grafo — guarda i 4 probe (REMOTE_RTP_INPUT / REMOTE_POST_SOURCE / REMOTE_POST_GAIN / REMOTE_PLAYBACK_DEST) per vedere in quale dei quattro il segnale passa da "signal" a "silence".
- **Test D — Artist Return**: parla nel mic dell'Artist con la sessione connessa e guarda, lato Studio, i 3 probe (ARTIST_RTP_INPUT / ARTIST_POST_SOURCE / ARTIST_RETURN) e lo stats "inbound: audioLevel / totalAudioEnergy" — se crescono con la voce, quella direzione è confermata a livello di grafo anche se il monitor fisico dello Studio non è ancora configurato (usa il bottone "LOCAL TEST TONE (Studio)" per isolare quello, separatamente).

Tre gate distinti da non confondere: **NETWORK** (pacchetti/energia RTP, sezione stats), **AUDIO GRAPH** (RMS/peak/signal-silence dei probe), **PHYSICAL OUTPUT** (Local Test Tone + ascolto umano). `connected` o `packets > 0` non equivalgono ad audio OK.

### Diagnostica aggiunta nei debug pass 0.1b/0.1c/0.1d

- **TEST TONE 440 Hz** (Studio, dentro il Remote Mix via WebRTC) e **LOCAL TEST TONE** (Studio E Artist, diretto all'uscita locale, NON passa da WebRTC) — due strumenti distinti, non confonderli.
- **LOCAL MONITOR** (Artist, mic in cuffia, OFF di default): conferma che il mic selezionato produce davvero campioni.
- **Indicatore "audio: ..."** e bottone "Abilita/Riattiva audio": stato dell'AudioContext e recupero da blocco autoplay.
- **Indicatore "playback: ..."** (Artist): stato esplicito del tentativo di `play()`.
- **4 probe lato Artist / 3 probe lato Studio** (RMS, peak, signal/silence) in punti reali e distinti del grafo Web Audio — vedi Test C/D sopra.
- **Modalità playback DIRECT MEDIA ELEMENT vs WEB AUDIO PATH** (Artist): bypassa o meno il grafo Web Audio, per isolare dove sparisce il segnale.
- **Diagnostica sink esplicita** (Artist, bottone "Ispeziona output"): device label, sinkId richiesto vs effettivo, volume/muted/paused/readyState dell'`<audio>`.
- **Stats WebRTC**: ora includono anche packets/bytes espliciti e, dove il browser li espone, `audioLevel`/`totalAudioEnergy` — la prova che l'RTP trasmesso contiene energia audio reale, non solo che è stato inviato.
- **Compatibilità browser**: Chrome è il browser di riferimento della Fase 0.1. Nota, non ancora indagata: Brave con Shields disabilitati non ha avviato correttamente il microfono in un test manuale — da verificare in un incarico successivo, non in questo.

## Cosa NON fa (deliberatamente, per restare nel perimetro Fase 0)

- Non si collega a REAPER, non parla Lua, non usa `AudioAccessor`.
- Non implementa login/account/Session Engine.
- Non installa né richiede BlackHole o altri driver — se non hai abbastanza dispositivi fisici/virtuali per il test multi-input, lo spike lo segnala come limite, non lo aggira installando qualcosa.
- Non implementa stem WebRTC separati (Program/Talkback/Aux restano un solo Remote Mix in v1, come da `ARCHITETTURA_ZP_REMOTE.md` §10.1).
- Non implementa gobbo, Observer completo, EQ/compressor, o altre funzioni di prodotto.

## Limiti noti dello spike (non del prodotto)

- Nessun TURN configurato: su reti con NAT simmetrico/restrittivo la connessione fra due macchine diverse potrebbe non stabilirsi — è un limite noto dello spike, non una scoperta architetturale.
- `getUserMedia` richiede un "secure context": funziona su `localhost` e su `https://`; su un IP LAN semplice (`http://192.168.x.x`) alcuni browser lo bloccano o lo permettono solo con flag speciali — se il test cross-device fallisce per questo motivo, va registrato come limite del trasporto di test, non del WebRTC in sé.
- Video: implementato in modo minimo (nessun controllo qualità/risoluzione), l'audio ha sempre priorità.
