// studio/studio.js — EXPERIMENTAL / FASE 0 / NOT PRODUCT CODE
import { DiagLog, formatElapsed, downloadBlob } from "../shared/log.js";
import { getAudioContext, MixBus } from "../shared/audio-graph.js";
import { InputPanel } from "../shared/input-panel.js";
import { listDevices, fillSelect, requestLabelPermission } from "../shared/devices.js";
import { Meter } from "../shared/meter.js";
import { Signaling, waitIceGatheringComplete, encodeDescription, decodeDescription } from "../shared/signaling.js";
import { StatsPoller } from "../shared/stats.js";

const $ = (id) => document.getElementById(id);
const log = new DiagLog($("log"));

let ctx = null;
let mixBus = null;
let pc = null;
let statsPoller = null;
let sessionStart = null;

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
  const { audioinput } = await listDevices();
  [$("programSelect"), $("talkbackSelect"), $("auxSelect")].forEach((sel) =>
    fillSelect(sel, audioinput, { defaultLabel: "Default" })
  );
  log.info(`Dispositivi audioinput trovati: ${audioinput.length}`, audioinput.map((d) => d.label || d.deviceId));
}

navigator.mediaDevices?.addEventListener?.("devicechange", () => {
  log.event("devicechange rilevato — aggiorno elenco dispositivi");
  initDeviceLists();
});

// --- Input panels -----------------------------------------------------

let programPanel, talkbackPanel, auxPanel;

function setupPanels() {
  programPanel = new InputPanel({
    ctx,
    name: "PROGRAM",
    log,
    els: {
      select: $("programSelect"), startBtn: $("programStart"), swapBtn: $("programSwap"),
      aec: $("programAec"), ns: $("programNs"), agc: $("programAgc"),
      gain: $("programGain"), gainReadout: $("programGainReadout"),
      muteBtn: $("programMute"), meterBar: $("programMeter"), meterDb: $("programMeterDb"),
      statusEl: $("programStatus"),
    },
    onReady: (chain) => chain.connectTo(mixBus.bus),
  });

  talkbackPanel = new InputPanel({
    ctx,
    name: "TALKBACK",
    log,
    startMuted: true,
    els: {
      select: $("talkbackSelect"), startBtn: $("talkbackStart"), swapBtn: $("talkbackSwap"),
      aec: $("talkbackAec"), ns: $("talkbackNs"), agc: $("talkbackAgc"),
      gain: $("talkbackGain"), gainReadout: $("talkbackGainReadout"),
      muteBtn: $("talkbackMute"), meterBar: $("talkbackMeter"), meterDb: $("talkbackMeterDb"),
      statusEl: $("talkbackStatus"),
    },
    onReady: (chain) => chain.connectTo(mixBus.bus),
  });

  auxPanel = new InputPanel({
    ctx,
    name: "AUX",
    log,
    els: {
      select: $("auxSelect"), startBtn: $("auxStart"), swapBtn: $("auxSwap"),
      aec: $("auxAec"), ns: $("auxNs"), agc: $("auxAgc"),
      gain: $("auxGain"), gainReadout: $("auxGainReadout"),
      muteBtn: $("auxMute"), meterBar: $("auxMeter"), meterDb: $("auxMeterDb"),
      statusEl: $("auxStatus"),
    },
    onReady: (chain) => chain.connectTo(mixBus.bus),
  });

  // TALK / PTT: momentary unmute of the talkback chain while held.
  const talkBtn = $("talkbackTalk");
  const pressTalk = (e) => { e.preventDefault(); if (!talkbackPanel.chain) return; talkbackPanel.chain.setMuted(false); talkBtn.classList.add("is-active"); };
  const releaseTalk = () => { if (!talkbackPanel.chain) return; if (!talkbackPanel.muted) talkbackPanel.chain.setMuted(true); talkBtn.classList.remove("is-active"); };
  talkBtn.addEventListener("pointerdown", pressTalk);
  talkBtn.addEventListener("pointerup", releaseTalk);
  talkBtn.addEventListener("pointerleave", releaseTalk);
  // Note: the persistent MUTE button on Talkback still calls chain.setMuted(true/false)
  // directly, so if the operator hits MUTE while not talking it stays muted; if they hit
  // MUTE=off it stays open without needing to hold TALK — documented as a spike quirk.
}

// --- Remote mix meter ---------------------------------------------------

function setupMixMeter() {
  const meter = new Meter(mixBus.analyser, $("mixMeter"), { dbLabelEl: $("mixMeterDb") });
  meter.start();
}

// --- AudioContext state watchdog (visible, not just logged) --------------

function startAudioCtxWatchdog() {
  setInterval(() => {
    if (!ctx) return;
    const el = $("audioCtxState");
    el.textContent = `audio: ${ctx.state}`;
    el.className = "status-pill " + (ctx.state === "running" ? "ok" : "danger");
  }, 500);
}

$("btnEnableAudio").addEventListener("click", async () => {
  await ensureAudioContext();
  log.event(`Riattiva audio: ctx.state → ${ctx.state}`);
});

// --- TEST TONE 440 Hz, iniettato direttamente nel Remote Mix -------------
// Diagnostico: bypassa DAW/Apollo/microfoni/routing fisico. Se questo si
// sente lato Artist, il tubo Studio→Artist (Web Audio → WebRTC → playback)
// funziona; se non si sente, il problema è in quel tubo, non nell'hardware.

let testToneOsc = null;
let testToneGain = null;

function setupTestTone() {
  testToneGain = ctx.createGain();
  testToneGain.gain.value = Number($("testToneLevel").value);
  $("testToneLevel").addEventListener("input", () => {
    const v = Number($("testToneLevel").value);
    $("testToneLevelReadout").textContent = v.toFixed(2);
    testToneGain.gain.setTargetAtTime(v, ctx.currentTime, 0.01);
  });
  $("testToneToggle").addEventListener("click", () => {
    if (testToneOsc) {
      testToneOsc.stop();
      testToneOsc.disconnect();
      testToneOsc = null;
      $("testToneToggle").textContent = "TEST TONE 440 Hz: OFF";
      $("testToneToggle").classList.remove("is-active");
      log.event("Test tone: OFF");
      return;
    }
    testToneOsc = ctx.createOscillator();
    testToneOsc.type = "sine";
    testToneOsc.frequency.value = 440;
    testToneOsc.connect(testToneGain);
    testToneGain.connect(mixBus.bus);
    testToneOsc.start();
    $("testToneToggle").textContent = "TEST TONE 440 Hz: ON";
    $("testToneToggle").classList.add("is-active");
    log.event("Test tone: ON (440 Hz sine → Remote Mix)", { level: testToneGain.gain.value });
  });
}

// --- LOCAL TEST TONE (PHYSICAL OUTPUT probe, debug pass 0.1d) ------------
// Va dritto a ctx.destination, non passa MAI da WebRTC/Remote Mix. Serve a
// isolare il monitor locale dello Studio (output di sistema/browser) da
// tutto il resto: se anche questo non si sente, il problema non è nel
// grafo WebRTC/Web Audio ricevente ma nell'uscita audio locale della
// macchina/scheda/tab.

let localTestToneOsc = null;
let localTestToneGain = null;

function setupLocalTestTone() {
  localTestToneGain = ctx.createGain();
  localTestToneGain.gain.value = Number($("localTestToneLevel").value);
  $("localTestToneLevel").addEventListener("input", () => {
    const v = Number($("localTestToneLevel").value);
    localTestToneGain.gain.setTargetAtTime(v, ctx.currentTime, 0.01);
  });
  $("localTestToneToggle").addEventListener("click", () => {
    if (localTestToneOsc) {
      localTestToneOsc.stop();
      localTestToneOsc.disconnect();
      localTestToneOsc = null;
      $("localTestToneToggle").textContent = "LOCAL TEST TONE (Studio, NON passa da WebRTC): OFF";
      $("localTestToneToggle").classList.remove("is-active");
      log.event("Local test tone (Studio, diretto a ctx.destination): OFF");
      return;
    }
    localTestToneOsc = ctx.createOscillator();
    localTestToneOsc.type = "sine";
    localTestToneOsc.frequency.value = 440;
    localTestToneOsc.connect(localTestToneGain);
    localTestToneGain.connect(ctx.destination);
    localTestToneOsc.start();
    $("localTestToneToggle").textContent = "LOCAL TEST TONE (Studio, NON passa da WebRTC): ON";
    $("localTestToneToggle").classList.add("is-active");
    log.event("Local test tone (Studio, diretto a ctx.destination, NON passa da WebRTC): ON — se non lo senti, il problema è nel monitor locale dello Studio, non in WebRTC/Web Audio ricevente.", { level: localTestToneGain.gain.value });
  });
}

// --- Artist Return (received track) -------------------------------------

let returnChainGain = null;

// DEBUG PASS 0.1b: event.streams[0] is NOT reliable here. addTransceiver()
// was used (not addTrack()) without an explicit `streams` option, so no
// msid is negotiated in the SDP and event.streams can arrive EMPTY on the
// remote end. Relying on `const [stream] = event.streams` then makes
// `stream` undefined, and createMediaStreamSource(undefined) throws
// synchronously inside this handler — silently, since ontrack has no
// caller watching for exceptions. That kills the whole Artist Return setup
// for that track while WebRTC keeps transporting packets underneath,
// exactly matching "packets flow but nothing is audible". Fix: always
// build the MediaStream from the track itself, never trust event.streams.
//
// Nota dai log/stats reali del test 0.1: in quel test questo handler non ha
// mai potuto sbagliare, perché non è mai stato chiamato affatto — Studio
// non ha registrato nessun "ontrack ricevuto" per l'audio in tutta la
// sessione. La causa di QUELLO era altrove (vedi artist.js, acceptOffer():
// il transceiver audio dell'Artist restava "recvonly" perché mai alzato
// esplicitamente a sendrecv, quindi Artist non trasmetteva affatto). Con
// quel bug corretto, questo ontrack INIZIERÀ a scattare per davvero lato
// Studio, ed è a quel punto che il fix event.streams qui sotto diventa
// concretamente necessario e non solo difensivo.
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

  if (track.kind === "audio") {
    log.info(`AudioContext state al momento dell'ontrack: ${ctx.state}`);
    // DEBUG PASS 0.1d — tre probe reali e distinti lungo il percorso, per
    // trovare campione per campione dove sparisce il segnale, invece di
    // fidarsi di un solo meter combinato:
    //   source (ARTIST_RTP_INPUT) -> postSource passthrough (ARTIST_POST_SOURCE)
    //   -> gain di monitor (ARTIST_RETURN, è quello che va a ctx.destination)
    const source = ctx.createMediaStreamSource(stream);
    const rtpInputAnalyser = ctx.createAnalyser();
    source.connect(rtpInputAnalyser);
    const probeRtpInput = new Meter(rtpInputAnalyser, $("probeRtpInput"), { dbLabelEl: $("probeRtpInputDb"), stateEl: $("probeRtpInputState") });
    probeRtpInput.start();

    const postSource = ctx.createGain(); // passthrough di unità, serve solo a dare un secondo punto di misura reale e distinto
    postSource.gain.value = 1;
    source.connect(postSource);
    const postSourceAnalyser = ctx.createAnalyser();
    postSource.connect(postSourceAnalyser);
    const probePostSource = new Meter(postSourceAnalyser, $("probePostSource"), { dbLabelEl: $("probePostSourceDb"), stateEl: $("probePostSourceState") });
    probePostSource.start();

    const analyser = ctx.createAnalyser(); // meter "Artist Return" storico, invariato
    const gain = ctx.createGain();
    gain.gain.value = Number($("returnGain").value);
    postSource.connect(analyser);
    postSource.connect(gain);
    gain.connect(ctx.destination);
    returnChainGain = gain;
    const meter = new Meter(analyser, $("returnMeter"), { dbLabelEl: $("returnMeterDb") });
    meter.start();

    const returnAnalyser = ctx.createAnalyser(); // ARTIST_RETURN: esattamente il nodo collegato a ctx.destination
    gain.connect(returnAnalyser);
    const probeArtistReturn = new Meter(returnAnalyser, $("probeArtistReturn"), { dbLabelEl: $("probeArtistReturnDb"), stateEl: $("probeArtistReturnState") });
    probeArtistReturn.start();

    log.event("Artist Return collegato a ctx.destination (Web Audio, nessun elemento <audio> — non serve play() esplicito, ma l'AudioContext deve essere 'running'). Probe 0.1d attivi: ARTIST_RTP_INPUT, ARTIST_POST_SOURCE, ARTIST_RETURN.");

    $("returnGain").addEventListener("input", () => {
      gain.gain.setTargetAtTime(Number($("returnGain").value), ctx.currentTime, 0.01);
    });
    let muted = false;
    $("returnMute").addEventListener("click", () => {
      muted = !muted;
      gain.gain.setTargetAtTime(muted ? 0 : Number($("returnGain").value), ctx.currentTime, 0.01);
      $("returnMute").classList.toggle("is-active", muted);
    });
  } else if (track.kind === "video") {
    $("remoteVideo").srcObject = stream;
  }
}

// --- WebRTC setup ---------------------------------------------------------

function createPeerConnection() {
  const conn = new RTCPeerConnection({ iceServers: ICE_SERVERS });
  conn.addTransceiver("audio", { direction: "sendrecv" });
  conn.addTransceiver("video", { direction: "recvonly" });
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

async function onConnectClick() {
  await ensureAudioContext();
  if (pc) { log.warn("Peer connection già esistente — ignoro nuovo click."); return; }

  pc = createPeerConnection();
  const mixTrack = mixBus.outputTrack;
  // Attach the Remote Mix track (Program+Talkback+Aux summed in Web Audio)
  // to the audio transceiver's sender explicitly. mixBus.outputTrack exists
  // from the moment MixBus was built at page load (boot()), so this works
  // identically whether Program/Talkback/Aux are already open or not yet —
  // same reasoning as the Artist mic side, see the comment in artist.js.
  const audioTransceiver = pc.getTransceivers().find((t) => t.receiver.track.kind === "audio");
  await audioTransceiver.sender.replaceTrack(mixTrack);
  log.event("Sender audio Studio→Artist collegato al Remote Mix", {
    trackId: mixTrack.id,
    readyState: mixTrack.readyState,
    programAvviato: !!programPanel.chain,
    talkbackAvviato: !!talkbackPanel.chain,
    auxAvviato: !!auxPanel.chain,
    transceiverDirection: audioTransceiver.direction,
  });

  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  log.info("Offerta creata, attendo fine raccolta ICE (non-trickle)…");
  await waitIceGatheringComplete(pc);
  const encoded = encodeDescription(pc.localDescription);
  $("localOfferBox").value = encoded;
  log.info(`Offerta pronta (${encoded.length} caratteri). Copiala nella pagina Artist, o attendi il BroadcastChannel se stessa macchina.`);

  signaling.broadcast("offer", encoded);

  sessionStart = Date.now();
  startSessionTimer();

  statsPoller = new StatsPoller(pc, { onSample: renderStatsSnapshot, role: "studio" });
  statsPoller.start();
}

async function onApplyAnswer() {
  const text = $("remoteAnswerBox").value;
  if (!text.trim()) { log.warn("Nessuna risposta da applicare."); return; }
  try {
    const desc = decodeDescription(text);
    await pc.setRemoteDescription(desc);
    log.event("Risposta remota applicata. In attesa di connessione ICE…");
  } catch (e) {
    log.error("Impossibile applicare la risposta", { message: e.message });
  }
}

const signaling = new Signaling({
  role: "studio",
  log,
  onRemoteMessage: (msg) => {
    if (msg.type === "answer") {
      $("remoteAnswerBox").value = msg.payload;
      onApplyAnswer();
    }
  },
});

// --- Stats rendering -------------------------------------------------------

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

// --- Session timer -----------------------------------------------------

function startSessionTimer() {
  setInterval(() => {
    if (!sessionStart) return;
    $("sessionTimer").textContent = formatElapsed(Date.now() - sessionStart);
  }, 500);
}

// --- Export buttons ------------------------------------------------------

$("btnExportLogTxt").addEventListener("click", () => log.downloadText("zp-remote-spike-studio-log.txt"));
$("btnExportLogJson").addEventListener("click", () => log.downloadJSON("zp-remote-spike-studio-log.json"));
$("btnExportStatsJson").addEventListener("click", () => {
  if (!statsPoller) { log.warn("Nessuna sessione WebRTC attiva: nessuno stats da esportare."); return; }
  downloadBlob(statsPoller.exportJSON(), "zp-remote-spike-studio-stats.json", "application/json");
});

$("btnConnect").addEventListener("click", onConnectClick);
$("btnApplyAnswer").addEventListener("click", onApplyAnswer);

// --- Boot ----------------------------------------------------------------

(async function boot() {
  log.info("Pagina Studio caricata.");
  await initDeviceLists();
  // Costruito subito (l'AudioContext parte "suspended" finché un gesto utente
  // non lo risveglia): così Program/Talkback/Aux si possono avviare e
  // controllare anche prima di premere "Crea offerta".
  ctx = getAudioContext(ctx);
  mixBus = new MixBus(ctx);
  setupPanels();
  setupMixMeter();
  setupTestTone();
  setupLocalTestTone();
  startAudioCtxWatchdog();
  document.body.addEventListener("click", () => { if (ctx.state === "suspended") ctx.resume(); }, { once: true, capture: true });
})();
