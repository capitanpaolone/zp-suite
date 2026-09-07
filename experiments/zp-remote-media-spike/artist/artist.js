// artist/artist.js — EXPERIMENTAL / FASE 0 / NOT PRODUCT CODE
import { DiagLog, formatElapsed, downloadBlob } from "../shared/log.js";
import { getAudioContext, InputChain, MonitorSink } from "../shared/audio-graph.js";
import { InputPanel } from "../shared/input-panel.js";
import { listDevices, fillSelect, requestLabelPermission, supportsSetSinkId } from "../shared/devices.js";
import { Meter } from "../shared/meter.js";
import { Signaling, waitIceGatheringComplete, encodeDescription, decodeDescription } from "../shared/signaling.js";
import { StatsPoller } from "../shared/stats.js";

const $ = (id) => document.getElementById(id);
const log = new DiagLog($("log"));

let ctx = null;
let pc = null;
let statsPoller = null;
let sessionStart = null;
let micPanel = null;
let micSendDest = null;
let monitorSink = null;
let localVideoStream = null;

const ICE_SERVERS = [{ urls: "stun:stun.l.google.com:19302" }];

async function ensureAudioContext() {
  if (!ctx) {
    ctx = getAudioContext(ctx);
    log.info("AudioContext creato", { sampleRate: ctx.sampleRate, state: ctx.state });
  }
  if (ctx.state === "suspended") await ctx.resume();
  return ctx;
}

async function initDeviceLists() {
  await requestLabelPermission();
  const { audioinput, videoinput, audiooutput } = await listDevices();
  fillSelect($("micSelect"), audioinput, { defaultLabel: "Default" });
  fillSelect($("cameraSelect"), videoinput, { defaultLabel: "Nessuna" });
  fillSelect($("outputSelect"), audiooutput, { defaultLabel: "Default" });
  $("outputSupport").textContent = `setSinkId: ${supportsSetSinkId() ? "supportato" : "NON supportato in questo browser"}`;
  log.info(`Dispositivi: ${audioinput.length} audioinput, ${videoinput.length} videoinput, ${audiooutput.length} audiooutput`);
}

navigator.mediaDevices?.addEventListener?.("devicechange", () => {
  log.event("devicechange rilevato — aggiorno elenco dispositivi");
  initDeviceLists();
});

let localMonitorGain = null;
let localMonitorOn = false;

function setupMicPanel() {
  ctx = getAudioContext(ctx); // ctx is already ensured/resumed by the caller before this runs
  micSendDest = ctx.createMediaStreamDestination();
  localMonitorGain = ctx.createGain();
  localMonitorGain.gain.value = 0; // OFF by default — feedback risk in headphones
  localMonitorGain.connect(ctx.destination);

  micPanel = new InputPanel({
    ctx,
    name: "MIC",
    log,
    els: {
      select: $("micSelect"), startBtn: $("micStart"), swapBtn: $("micSwap"),
      aec: $("micAec"), ns: $("micNs"), agc: $("micAgc"),
      gain: $("micGain"), gainReadout: $("micGainReadout"),
      muteBtn: $("micMute"), meterBar: $("micMeter"), meterDb: $("micMeterDb"),
      statusEl: $("micStatus"),
    },
    onReady: (chain) => {
      chain.connectTo(micSendDest);
      // LOCAL MONITOR taps the same fader/mute-gain output, so it reflects
      // exactly what would be sent — separate from the WebRTC path itself.
      chain.muteGain.connect(localMonitorGain);
      log.event("MIC: catena pronta", {
        readyState: chain.stream.getAudioTracks()[0]?.readyState,
        label: chain.stream.getAudioTracks()[0]?.label,
      });
    },
  });

  $("localMonitorToggle").addEventListener("click", () => {
    localMonitorOn = !localMonitorOn;
    const v = localMonitorOn ? Number($("localMonitorVolume").value) : 0;
    localMonitorGain.gain.setTargetAtTime(v, ctx.currentTime, 0.01);
    $("localMonitorToggle").textContent = `LOCAL MONITOR: ${localMonitorOn ? "ON" : "OFF"}`;
    $("localMonitorToggle").classList.toggle("is-active", localMonitorOn);
    log.event(`Local monitor: ${localMonitorOn ? "ON" : "OFF"}`, { volume: v });
  });
  $("localMonitorVolume").addEventListener("input", () => {
    if (!localMonitorOn) return;
    localMonitorGain.gain.setTargetAtTime(Number($("localMonitorVolume").value), ctx.currentTime, 0.01);
  });
}

function setupMonitor() {
  ctx = getAudioContext(ctx); // ctx is already ensured/resumed by the caller before this runs
  monitorSink = new MonitorSink(ctx, $("remoteAudioSink"));
  // Post-gain meter: what should actually reach the output device.
  const meter = new Meter(monitorSink.analyser, $("remoteMeter"), { dbLabelEl: $("remoteMeterDb") });
  meter.start();

  // DEBUG PASS 0.1d — probe 3 e 4, indipendenti da quale remote track
  // arriverà: vivono sui nodi propri di MonitorSink, non sul track remoto.
  // Probe 3 (REMOTE_POST_GAIN): stesso nodo del meter "Output playback" sopra,
  // esposto anche con etichetta signal/silence per la sezione forensics.
  const postGainProbe = new Meter(monitorSink.analyser, $("probePostGain"), { dbLabelEl: $("probePostGainDb"), stateEl: $("probePostGainState") });
  postGainProbe.start();
  // Probe 4 (REMOTE_PLAYBACK_DEST): NON lo stesso nodo — ri-crea un source
  // dal MediaStream REALE (monitorSink.dest.stream) che è quello davvero
  // assegnato a audioElement.srcObject. Chiude il cerchio: se questo mostra
  // "silence" ma il probe 3 mostra "signal", il problema è nella creazione
  // di MediaStreamAudioDestinationNode.stream o nell'assegnazione stessa,
  // non nel gain a monte.
  const playbackDestSource = ctx.createMediaStreamSource(monitorSink.dest.stream);
  const playbackDestAnalyser = ctx.createAnalyser();
  playbackDestSource.connect(playbackDestAnalyser);
  const playbackDestProbe = new Meter(playbackDestAnalyser, $("probePlaybackDest"), { dbLabelEl: $("probePlaybackDestDb"), stateEl: $("probePlaybackDestState") });
  playbackDestProbe.start();

  $("remoteVolume").addEventListener("input", () => monitorSink.setVolume(Number($("remoteVolume").value)));
  $("outputSelect").addEventListener("change", async () => {
    const ok = await monitorSink.setOutputDevice($("outputSelect").value);
    log.event(`setSinkId(${$("outputSelect").value || "default"}) → ${ok ? "ok" : "non supportato/errore"}`);
    logSinkDiagnostics("dopo cambio output");
  });
}

// DEBUG PASS 0.1d — punto 6 dell'incarico: non assumere che il device giusto
// sia davvero selezionato. Logga tutto ciò che è ispezionabile lato output.
function logSinkDiagnostics(context) {
  const el = $("remoteAudioSink");
  const selectedOption = $("outputSelect").selectedOptions?.[0];
  log.info(`Sink diagnostics (${context})`, {
    deviceLabelSelezionato: selectedOption ? selectedOption.textContent : null,
    sinkIdRichiesto: $("outputSelect").value || "default",
    sinkIdEffettivo: typeof el.sinkId !== "undefined" ? el.sinkId : "non esposto da questo browser",
    volume: el.volume,
    muted: el.muted,
    paused: el.paused,
    readyState: el.readyState,
    srcObjectPresente: !!el.srcObject,
  });
}
$("btnInspectSink").addEventListener("click", () => logSinkDiagnostics("richiesta manuale"));

// --- LOCAL TEST TONE / TEST OUTPUT (PHYSICAL OUTPUT probe, debug 0.1d) ----
// Stesso monitorSink/audioElement/sink usato per il Remote Mix — MAI passa
// da WebRTC. Funziona anche PRIMA di qualunque connessione (crea ctx e
// monitorSink al volo se non esistono già), così è utilizzabile come Test A
// standalone: "se questo non si sente, il problema è nell'output locale,
// non in WebRTC" — prima ancora di toccare Studio.
let localTestToneOsc = null;
let localTestToneGain = null;

$("localTestToneToggle").addEventListener("click", async () => {
  await ensureAudioContext();
  if (!monitorSink) setupMonitor();
  if (localTestToneOsc) {
    localTestToneOsc.stop();
    localTestToneOsc.disconnect();
    localTestToneOsc = null;
    $("localTestToneToggle").textContent = "LOCAL TEST TONE / TEST OUTPUT: OFF";
    $("localTestToneToggle").classList.remove("is-active");
    log.event("Local test tone / test output (Artist): OFF");
    return;
  }
  if (!localTestToneGain) {
    localTestToneGain = ctx.createGain();
    localTestToneGain.gain.value = Number($("localTestToneVolume").value);
    $("localTestToneVolume").addEventListener("input", () => {
      localTestToneGain.gain.setTargetAtTime(Number($("localTestToneVolume").value), ctx.currentTime, 0.01);
    });
  }
  localTestToneOsc = ctx.createOscillator();
  localTestToneOsc.type = "sine";
  localTestToneOsc.frequency.value = 440;
  localTestToneOsc.connect(localTestToneGain);
  localTestToneGain.connect(monitorSink.gain);
  localTestToneOsc.start();
  $("localTestToneToggle").textContent = "LOCAL TEST TONE / TEST OUTPUT: ON";
  $("localTestToneToggle").classList.add("is-active");
  log.event("Local test tone / test output (Artist): ON — stesso monitorSink/audioElement/sink del Remote Mix, NON passa da WebRTC. Se non lo senti, il problema è nell'output locale (sink/volume/hardware/OS), non in WebRTC.", { level: localTestToneGain.gain.value });
  await tryPlayMonitor();
  logSinkDiagnostics("dopo attivazione local test tone");
});

function setPlaybackState(text, ok) {
  const el = $("playbackState");
  el.textContent = `playback: ${text}`;
  el.className = "status-pill " + (ok === true ? "ok" : ok === false ? "danger" : "warn");
}

async function tryPlayMonitor() {
  if (!monitorSink) return;
  log.info("Tentativo audioElement.play()…", {
    paused: monitorSink.audioEl.paused,
    srcObjectSet: !!monitorSink.audioEl.srcObject,
    ctxState: ctx.state,
  });
  const ok = await monitorSink.play();
  if (ok) {
    setPlaybackState("attivo", true);
    log.event("audioElement.play() riuscito — se non senti nulla, il problema è a valle (sink/volume/hardware), non qui.");
  } else {
    setPlaybackState("BLOCCATO — clicca 'Abilita audio'", false);
    log.error("audioElement.play() fallito (probabile blocco autoplay del browser). Serve un click esplicito dell'utente: usa 'Abilita audio'.");
  }
  return ok;
}

$("btnEnableAudio").addEventListener("click", async () => {
  await ensureAudioContext();
  log.event(`Abilita audio: ctx.state → ${ctx.state}`);
  await tryPlayMonitor();
});

// --- Camera (optional, video only, not routed through Web Audio) ---------

async function maybeGetCameraStream() {
  if (!$("cameraEnable").checked) return null;
  const deviceId = $("cameraSelect").value || undefined;
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      video: deviceId ? { deviceId: { exact: deviceId } } : true,
    });
    localVideoStream = stream;
    $("localVideoPreview").srcObject = stream;
    log.event("Camera avviata", { label: stream.getVideoTracks()[0]?.label });
    return stream;
  } catch (e) {
    log.error("getUserMedia video fallita", { message: e.message, name: e.name });
    return null;
  }
}

async function swapCamera() {
  if (!pc) { log.warn("Nessuna connessione attiva: lo swap camera richiede una sessione già connessa."); return; }
  const sender = pc.getSenders().find((s) => s.track && s.track.kind === "video");
  if (!sender) { log.warn("Nessun sender video attivo (camera non abilitata all'avvio)."); return; }
  const deviceId = $("cameraSelect").value || undefined;
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ video: deviceId ? { deviceId: { exact: deviceId } } : true });
    const newTrack = stream.getVideoTracks()[0];
    await sender.replaceTrack(newTrack);
    localVideoStream?.getTracks().forEach((t) => t.stop());
    localVideoStream = stream;
    $("localVideoPreview").srcObject = stream;
    log.event("Camera cambiata via RTCRtpSender.replaceTrack()", { label: newTrack.label });
  } catch (e) {
    log.error("Swap camera fallito", { message: e.message });
  }
}
$("cameraSelect").addEventListener("change", () => { if (pc) swapCamera(); });

// --- WebRTC ----------------------------------------------------------------

function createPeerConnection() {
  const conn = new RTCPeerConnection({ iceServers: ICE_SERVERS });
  conn.ontrack = handleRemoteTrack;
  conn.onconnectionstatechange = () => {
    $("pcState").textContent = conn.connectionState;
    log.event(`connectionState → ${conn.connectionState}`);
  };
  conn.oniceconnectionstatechange = () => {
    $("iceState").textContent = `ice: ${conn.iceConnectionState}`;
    log.event(`iceConnectionState → ${conn.iceConnectionState}`);
  };
  return conn;
}

let remoteInMeter = null;

// DEBUG PASS 0.1b: same root cause as the Studio side (see studio.js) —
// event.streams can be empty because addTransceiver() was used without an
// explicit `streams` option, so no msid is negotiated. Never trust
// event.streams; always build the MediaStream from event.track directly.
function handleRemoteTrack(event) {
  const track = event.track;
  const stream = event.streams[0] || new MediaStream([track]);
  log.event(`ontrack ricevuto: kind=${track.kind}`, {
    id: track.id,
    readyState: track.readyState,
    muted: track.muted,
    enabled: track.enabled,
    streamsFromEvent: event.streams.length,
    usedFallbackStream: event.streams.length === 0,
  });
  track.addEventListener("mute", () => log.warn(`Remote track ${track.kind} → mute event (silenzio dalla sorgente)`));
  track.addEventListener("unmute", () => log.event(`Remote track ${track.kind} → unmute event (segnale presente)`));
  track.addEventListener("ended", () => log.warn(`Remote track ${track.kind} → ended`));

  if (track.kind === "audio" && monitorSink) {
    const mode = $("playbackMode").value;
    log.info(`AudioContext state al momento dell'ontrack: ${ctx.state}. Modalità playback: ${mode}`);

    if (mode === "direct") {
      // DEBUG PASS 0.1d — Test B (DIRECT MEDIA ELEMENT): bypassa
      // completamente il grafo Web Audio. monitorSink normalmente possiede
      // audioEl.srcObject (= monitorSink.dest.stream); qui lo sovrascriviamo
      // deliberatamente con lo stream remoto grezzo, per isolare se il
      // problema è nel grafo Web Audio o a valle di esso.
      $("remoteAudioSink").srcObject = stream;
      log.event("Modalità DIRECT MEDIA ELEMENT: remote MediaStream assegnato direttamente a audioElement.srcObject — Web Audio bypassato per questo track.");
      tryPlayMonitor();
      logSinkDiagnostics("dopo ontrack (DIRECT MEDIA ELEMENT)");
      return;
    }

    // WEB AUDIO PATH (default) — struttura invariata, con due probe in più.
    const source = ctx.createMediaStreamSource(stream);
    // Pre-gain tap: "Remote stream ricevuto", independent from whatever
    // the local monitor volume/gain is doing downstream. Riusato anche come
    // probe 1 (REMOTE_RTP_INPUT) della sezione forensics 0.1d.
    const preAnalyser = ctx.createAnalyser();
    source.connect(preAnalyser);
    remoteInMeter = new Meter(preAnalyser, $("remoteInMeter"), { dbLabelEl: $("remoteInMeterDb") });
    remoteInMeter.start();
    const probeRtpInput = new Meter(preAnalyser, $("probeRtpInput"), { dbLabelEl: $("probeRtpInputDb"), stateEl: $("probeRtpInputState") });
    probeRtpInput.start();

    // Probe 2 (REMOTE_POST_SOURCE): passthrough di unità dedicato, secondo
    // punto di misura reale e distinto prima di entrare in monitorSink.gain.
    const postSource = ctx.createGain();
    postSource.gain.value = 1;
    source.connect(postSource);
    const postSourceAnalyser = ctx.createAnalyser();
    postSource.connect(postSourceAnalyser);
    const probePostSource = new Meter(postSourceAnalyser, $("probePostSource"), { dbLabelEl: $("probePostSourceDb"), stateEl: $("probePostSourceState") });
    probePostSource.start();

    monitorSink.connectSource(postSource);
    log.event("audioElement.srcObject assegnato a monitorSink.dest.stream (impostato alla creazione del MonitorSink). Probe 0.1d attivi: REMOTE_RTP_INPUT, REMOTE_POST_SOURCE, REMOTE_POST_GAIN, REMOTE_PLAYBACK_DEST.", {
      srcObjectSet: !!monitorSink.audioEl.srcObject,
      paused: monitorSink.audioEl.paused,
    });
    tryPlayMonitor();
    logSinkDiagnostics("dopo ontrack (WEB AUDIO PATH)");
  }
}

async function onReadyClick() {
  await ensureAudioContext();
  if (!micPanel) setupMicPanel();
  if (!monitorSink) setupMonitor();
  if (pc) { log.warn("Peer connection già esistente."); return; }

  const offerText = $("remoteOfferBox").value;
  if (!offerText.trim()) {
    log.info("In attesa dell'offerta (incolla manualmente o attendi il BroadcastChannel)…");
    return;
  }
  await acceptOffer(offerText);
}

async function acceptOffer(offerText) {
  if (pc) { log.warn("Offerta già accettata in questa sessione."); return; }
  await ensureAudioContext();
  if (!micPanel) setupMicPanel();
  if (!monitorSink) setupMonitor();

  pc = createPeerConnection();

  const cameraStream = await maybeGetCameraStream();

  let desc;
  try {
    desc = decodeDescription(offerText);
  } catch (e) {
    log.error("Offerta non decodificabile", { message: e.message });
    return;
  }
  await pc.setRemoteDescription(desc);
  log.event("Offerta remota applicata.");

  // Attach mic (from Web Audio mix-send destination, so mute silences the
  // transmitted track without silencing the local meter tap) to the audio
  // transceiver, and camera (if any) to the video transceiver.
  //
  // DEBUG PASS 0.1b — "primo sospetto" (mic avviato dopo la negoziazione):
  // il sender riceve QUI il track di micSendDest — che esiste ed è "live"
  // dal momento in cui è stato creato in setupMicPanel(), a prescindere da
  // se/quando l'utente ha già premuto "Avvia" sul microfono. Quando in
  // seguito InputPanel.start() collega la vera catena del microfono a
  // questo stesso nodo (onReady → chain.connectTo(micSendDest)), il track
  // già in volo su WebRTC inizia a portare audio reale: NESSUN
  // replaceTrack() aggiuntivo, NESSUNA rinegoziazione. È per questo che
  // "mic avviato prima" e "mic avviato dopo" la negoziazione sono
  // equivalenti in questo spike — la strategia sender/transceiver non
  // cambia in nessuno dei due casi. Questa parte del ragionamento era corretta.
  //
  // CAUSA REALE CONFERMATA (dai log/stats del test dal vivo): quello che
  // mancava non era il track, ma la DIREZIONE del transceiver. Quando
  // l'answerer (Artist) elabora un'offerta remota, per ogni m= section
  // senza un transceiver già esistente il browser ne crea uno con
  // `direction` di default "recvonly" — NON "sendrecv" — anche se
  // l'offerente (Studio) aveva dichiarato sendrecv. `replaceTrack()` collega
  // un track al sender ma NON tocca `.direction`: se non lo si alza
  // esplicitamente a "sendrecv" PRIMA di createAnswer(), la risposta SDP
  // dichiara comunque "recvonly", e quel m= line resta di fatto
  // send-disabilitato per tutta la sessione — nessun errore, nessuna
  // eccezione, semplicemente RTP non parte mai in quella direzione.
  // Prova nei dati reali: nello stats export di Studio, `inbound` è null in
  // TUTTI i 175 campioni; nello stats export di Artist, `outbound` è null in
  // TUTTI i 168 campioni (simmetrico, stesso transceiver); il log di Studio
  // non contiene NESSUNA riga "ontrack ricevuto" per l'audio, perché
  // l'answer di Artist dichiarava recvonly e quindi Studio non riceveva mai
  // il segnale "il remoto sta inviando" che fa scattare ontrack.
  // Il ramo video sotto (poche righe più giù) faceva già la cosa giusta
  // (`videoTransceiver.direction = "sendrecv"` dopo il replaceTrack) — il
  // bug era che il ramo audio non replicava lo stesso passaggio. Fix minimo:
  // alzare esplicitamente la direzione anche per l'audio, prima di
  // createAnswer().
  const audioTransceiver = pc.getTransceivers().find((t) => t.receiver.track.kind === "audio");
  const micTrackForSender = micSendDest.stream.getAudioTracks()[0];
  const audioDirectionBeforeFix = audioTransceiver.direction;
  await audioTransceiver.sender.replaceTrack(micTrackForSender);
  audioTransceiver.direction = "sendrecv";
  log.event("Sender audio Artist→Studio collegato a micSendDest (prima ancora che il microfono reale sia avviato)", {
    trackId: micTrackForSender.id,
    readyState: micTrackForSender.readyState,
    micGiaAvviato: !!micPanel.chain,
    transceiverDirectionAutoCreata: audioDirectionBeforeFix,
    transceiverDirectionDopoFix: audioTransceiver.direction,
    transceiverCurrentDirection: audioTransceiver.currentDirection,
  });

  if (cameraStream) {
    const videoTransceiver = pc.getTransceivers().find((t) => t.receiver.track.kind === "video");
    if (videoTransceiver) {
      await videoTransceiver.sender.replaceTrack(cameraStream.getVideoTracks()[0]);
      videoTransceiver.direction = "sendrecv";
    }
  }

  const answer = await pc.createAnswer();
  await pc.setLocalDescription(answer);
  log.info("Risposta creata, attendo fine raccolta ICE (non-trickle)…");
  await waitIceGatheringComplete(pc);
  const encoded = encodeDescription(pc.localDescription);
  $("localAnswerBox").value = encoded;
  log.info(`Risposta pronta (${encoded.length} caratteri). Copiala nella pagina Studio, o attendi il BroadcastChannel.`);
  signaling.broadcast("answer", encoded);

  sessionStart = Date.now();
  startSessionTimer();

  statsPoller = new StatsPoller(pc, { onSample: renderStatsSnapshot, role: "artist" });
  statsPoller.start();
}

const signaling = new Signaling({
  role: "artist",
  log,
  onRemoteMessage: (msg) => {
    if (msg.type === "offer") {
      $("remoteOfferBox").value = msg.payload;
      acceptOffer(msg.payload);
    }
  },
});

$("btnReady").addEventListener("click", onReadyClick);
$("btnAcceptOffer").addEventListener("click", () => acceptOffer($("remoteOfferBox").value));

// --- Stats rendering ---------------------------------------------------

function renderStatsSnapshot(s) {
  const nd = "n/d";
  $("statConn").textContent = s.connectionState;
  $("statIce").textContent = s.iceConnectionState;
  $("statCodecOut").textContent = s.outbound?.codec || nd;
  $("statCodecIn").textContent = s.inbound?.codec || nd;
  $("statBitrateOut").textContent = s.outbound?.bitrateKbps != null ? `${s.outbound.bitrateKbps} kbps` : nd;
  $("statBitrateIn").textContent = s.inbound?.bitrateKbps != null ? `${s.inbound.bitrateKbps} kbps` : nd;
  $("statPktOut").textContent = s.outbound?.packetsSent != null ? `${s.outbound.packetsSent} pkt / ${s.outbound.bytesSent} B` : nd;
  $("statPktIn").textContent = s.inbound?.packetsReceived != null ? `${s.inbound.packetsReceived} pkt / ${s.inbound.bytesReceived} B` : nd;
  $("statEnergyOut").textContent = s.outbound?.sourceAudioLevel != null || s.outbound?.sourceTotalAudioEnergy != null
    ? `level ${s.outbound.sourceAudioLevel ?? nd} / energy ${s.outbound.sourceTotalAudioEnergy ?? nd}` : nd;
  $("statEnergyIn").textContent = s.inbound?.audioLevel != null || s.inbound?.totalAudioEnergy != null
    ? `level ${s.inbound.audioLevel ?? nd} / energy ${s.inbound.totalAudioEnergy ?? nd}` : nd;
  $("statJitter").textContent = s.inbound?.jitter != null ? `${(s.inbound.jitter * 1000).toFixed(1)} ms` : nd;
  $("statLoss").textContent = s.inbound?.packetsLost != null ? String(s.inbound.packetsLost) : nd;
  $("statRtt").textContent = s.candidatePair?.currentRoundTripTime != null ? `${(s.candidatePair.currentRoundTripTime * 1000).toFixed(1)} ms` : nd;
  $("statPair").textContent = s.candidatePair ? `${s.candidatePair.localType || "?"} ↔ ${s.candidatePair.remoteType || "?"}` : nd;
}

function startSessionTimer() {
  setInterval(() => {
    if (!sessionStart) return;
    $("sessionTimer").textContent = formatElapsed(Date.now() - sessionStart);
  }, 500);
}

$("btnExportLogTxt").addEventListener("click", () => log.downloadText("zp-remote-spike-artist-log.txt"));
$("btnExportLogJson").addEventListener("click", () => log.downloadJSON("zp-remote-spike-artist-log.json"));
$("btnExportStatsJson").addEventListener("click", () => {
  if (!statsPoller) { log.warn("Nessuna sessione WebRTC attiva: nessuno stats da esportare."); return; }
  downloadBlob(statsPoller.exportJSON(), "zp-remote-spike-artist-stats.json", "application/json");
});

function startAudioCtxWatchdog() {
  setInterval(() => {
    if (!ctx) return;
    const el = $("audioCtxState");
    el.textContent = `audio: ${ctx.state}`;
    el.className = "status-pill " + (ctx.state === "running" ? "ok" : "danger");
  }, 500);
}

(async function boot() {
  log.info("Pagina Artist caricata.");
  await initDeviceLists();
  setPlaybackState("in attesa", null);
  startAudioCtxWatchdog();
  document.body.addEventListener("click", () => ensureAudioContext(), { once: true, capture: true });
})();
