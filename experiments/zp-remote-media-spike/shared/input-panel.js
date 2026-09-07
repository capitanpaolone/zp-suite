// shared/input-panel.js — EXPERIMENTAL / FASE 0 / NOT PRODUCT CODE
// One reusable "logical source" panel: device select, AEC/NS/AGC checkboxes,
// start/swap-device buttons, gain fader, mute, meter. Used for PROGRAM,
// TALKBACK and AUX on the Studio page, and for MIC on the Artist page.

import { InputChain } from "./audio-graph.js";
import { Meter } from "./meter.js";
import { listDevices, fillSelect } from "./devices.js";

export class InputPanel {
  /**
   * @param {object} opts
   * @param {AudioContext} opts.ctx
   * @param {string} opts.name - human label used only in logs ("PROGRAM", "TALKBACK", ...)
   * @param {object} opts.els - DOM refs: select, startBtn, swapBtn, gain, muteBtn, meterBar, aec, ns, agc, statusEl
   * @param {import("./log.js").DiagLog} opts.log
   * @param {boolean} [opts.startMuted]
   */
  constructor({ ctx, name, els, log, startMuted = false, onReady }) {
    this.ctx = ctx;
    this.name = name;
    this.els = els;
    this.log = log;
    this.chain = null;
    this.meter = null;
    this.startMuted = startMuted;
    this.muted = startMuted;
    this.onReady = onReady;

    this.els.gain?.addEventListener("input", () => {
      const v = Number(this.els.gain.value);
      this.chain?.setGain(v);
      if (this.els.gainReadout) this.els.gainReadout.textContent = `${v.toFixed(2)}x`;
    });

    this.els.muteBtn?.addEventListener("click", () => {
      this.setMuted(!this.muted);
    });

    this.els.startBtn?.addEventListener("click", () => this.start());
    this.els.swapBtn?.addEventListener("click", () => this.start(true));
  }

  _constraints() {
    const deviceId = this.els.select?.value || undefined;
    return {
      deviceId: deviceId ? { exact: deviceId } : undefined,
      echoCancellation: !!this.els.aec?.checked,
      noiseSuppression: !!this.els.ns?.checked,
      autoGainControl: !!this.els.agc?.checked,
    };
  }

  async start(isSwap = false) {
    this._setStatus("apertura sorgente…");
    let stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: this._constraints() });
    } catch (e) {
      this.log.error(`${this.name}: getUserMedia fallita`, { message: e.message, name: e.name });
      this._setStatus(`errore: ${e.name}`);
      return false;
    }

    const track = stream.getAudioTracks()[0];
    const settings = track.getSettings ? track.getSettings() : {};
    // DEBUG PASS 0.1d, richiesta esplicita: distinguere sempre "constraint
    // richiesto" (quello che questo pannello ha chiesto a getUserMedia) da
    // "setting effettivamente applicato dal browser" (quello che il track
    // riporta con getSettings() — l'unica fonte affidabile per sampleRate,
    // channelCount, echoCancellation/noiseSuppression/autoGainControl,
    // latency e, dove esposto, voiceIsolation).
    this.log.event(`${this.name}: sorgente ${isSwap ? "cambiata" : "avviata"}`, {
      label: track.label,
      constraintRichiesto: this._constraints(),
      settingApplicatoDalBrowser: settings,
    });

    if (isSwap && this.chain) {
      this.chain.replaceStream(stream);
    } else {
      this.chain = new InputChain(this.ctx, stream, {
        defaultGain: this.els.gain ? Number(this.els.gain.value) : 1,
        startMuted: this.startMuted,
      });
      this.meter = new Meter(this.chain.analyser, this.els.meterBar, { dbLabelEl: this.els.meterDb });
      this.meter.start();
      this.muted = this.startMuted;
      this.onReady?.(this.chain);
    }

    this._setStatus(`attivo: ${track.label || "(senza nome)"}`);
    await this._refreshDeviceList();
    return true;
  }

  setMuted(muted) {
    this.muted = muted;
    this.chain?.setMuted(muted);
    if (this.els.muteBtn) {
      this.els.muteBtn.classList.toggle("is-active", muted);
      this.els.muteBtn.textContent = muted ? "MUTED" : "MUTE";
    }
  }

  connectTo(destinationNode) {
    this.chain?.connectTo(destinationNode);
  }

  async _refreshDeviceList() {
    if (!this.els.select) return;
    const { audioinput } = await listDevices();
    fillSelect(this.els.select, audioinput, { defaultLabel: "Default" });
  }

  _setStatus(text) {
    if (this.els.statusEl) this.els.statusEl.textContent = text;
  }

  dispose() {
    this.meter?.stop();
    this.chain?.dispose();
  }
}
