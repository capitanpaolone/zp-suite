// shared/audio-graph.js — EXPERIMENTAL / FASE 0 / NOT PRODUCT CODE
// Small Web Audio helpers for a mixer chain:
//   getUserMedia stream -> source -> [analyser tap for meter]
//                                 -> fader gain -> mute gain -> (mix bus | destination)
//
// One AudioContext per page (Studio / Artist), shared across all chains on
// that page so they can be summed into a single mix bus when needed.

export function getAudioContext(existing) {
  if (existing && existing.state !== "closed") return existing;
  const Ctx = window.AudioContext || window.webkitAudioContext;
  return new Ctx();
}

export class InputChain {
  /**
   * @param {AudioContext} ctx
   * @param {MediaStream} stream
   * @param {{ defaultGain?: number, startMuted?: boolean }} opts
   */
  constructor(ctx, stream, opts = {}) {
    this.ctx = ctx;
    this.stream = stream;
    this.source = ctx.createMediaStreamSource(stream);
    this.analyser = ctx.createAnalyser();
    this.fader = ctx.createGain();
    this.fader.gain.value = opts.defaultGain ?? 1;
    this.muteGain = ctx.createGain();
    this.muteGain.gain.value = opts.startMuted ? 0 : 1;

    // Meter tap: independent of fader/mute, so you can see mic activity
    // even while muted or faded down.
    this.source.connect(this.analyser);

    // Signal path to whatever this chain gets connected to downstream.
    this.source.connect(this.fader);
    this.fader.connect(this.muteGain);
  }

  connectTo(destinationNode) {
    this.muteGain.connect(destinationNode);
    this._connectedTo = destinationNode;
    return this;
  }

  setGain(value) {
    this.fader.gain.setTargetAtTime(value, this.ctx.currentTime, 0.01);
  }

  setMuted(muted) {
    this.muteGain.gain.setTargetAtTime(muted ? 0 : 1, this.ctx.currentTime, 0.01);
  }

  /** Replace the underlying MediaStream (e.g. device switch) without
   * touching whatever this chain is connected to downstream. */
  replaceStream(newStream) {
    try {
      this.source.disconnect();
    } catch (e) { /* already disconnected */ }
    this.stream.getTracks().forEach((t) => t.stop());
    this.stream = newStream;
    this.source = this.ctx.createMediaStreamSource(newStream);
    this.source.connect(this.analyser);
    this.source.connect(this.fader);
  }

  dispose() {
    try { this.source.disconnect(); } catch (e) {}
    try { this.fader.disconnect(); } catch (e) {}
    try { this.muteGain.disconnect(); } catch (e) {}
    this.stream.getTracks().forEach((t) => t.stop());
  }
}

export class MixBus {
  constructor(ctx) {
    this.ctx = ctx;
    this.bus = ctx.createGain();
    this.bus.gain.value = 1;
    this.analyser = ctx.createAnalyser();
    this.bus.connect(this.analyser);
    this.destination = ctx.createMediaStreamDestination();
    this.bus.connect(this.destination);
  }

  get outputTrack() {
    return this.destination.stream.getAudioTracks()[0];
  }

  get outputStream() {
    return this.destination.stream;
  }
}

/** Builds a hidden <audio> sink fed from a Web Audio node, so we can both
 * apply gain/metering in Web Audio AND pick an output device via
 * HTMLMediaElement.setSinkId() (which AudioContext.destination does not
 * support in all browsers). */
export class MonitorSink {
  constructor(ctx, audioEl) {
    this.ctx = ctx;
    this.audioEl = audioEl;
    this.gain = ctx.createGain();
    this.gain.gain.value = 1;
    this.analyser = ctx.createAnalyser();
    this.gain.connect(this.analyser);
    this.dest = ctx.createMediaStreamDestination();
    this.gain.connect(this.dest);
    this.audioEl.srcObject = this.dest.stream;
    this.audioEl.autoplay = true;
  }

  connectSource(node) {
    node.connect(this.gain);
  }

  setVolume(v) {
    this.gain.gain.setTargetAtTime(v, this.ctx.currentTime, 0.01);
  }

  async play() {
    try {
      await this.audioEl.play();
      return true;
    } catch (e) {
      return false;
    }
  }

  async setOutputDevice(deviceId) {
    if (typeof this.audioEl.setSinkId !== "function") return false;
    try {
      await this.audioEl.setSinkId(deviceId || "default");
      return true;
    } catch (e) {
      return false;
    }
  }
}
