// shared/meter.js — EXPERIMENTAL / FASE 0 / NOT PRODUCT CODE
// Simple peak/RMS meter driven by an AnalyserNode, rendered as a CSS bar.
// Not a calibrated broadcast meter — just enough to see "is this input alive".

export class Meter {
  /**
   * @param {{ stateEl?: Element, silenceThresholdDb?: number }} [opts.stateEl/opts.silenceThresholdDb]
   *   DEBUG PASS 0.1d — forensics probes: optional element that gets a plain
   *   "signal" / "silence" text based on a threshold, so a probe can be read
   *   as a fact ("c'è energia qui" / "qui è muto") without eyeballing a bar.
   */
  constructor(analyserNode, barEl, { minDb = -60, maxDb = 0, dbLabelEl = null, stateEl = null, silenceThresholdDb = -50 } = {}) {
    this.analyser = analyserNode;
    this.analyser.fftSize = 512;
    this.buffer = new Float32Array(this.analyser.fftSize);
    this.barEl = barEl;
    this.dbLabelEl = dbLabelEl;
    this.stateEl = stateEl;
    this.silenceThresholdDb = silenceThresholdDb;
    this.minDb = minDb;
    this.maxDb = maxDb;
    this._raf = null;
    this._running = false;
    this.lastDb = -Infinity;
    this.lastPeakDb = -Infinity;
    this._peakHoldUntil = 0;
  }

  start() {
    if (this._running) return;
    this._running = true;
    const tick = () => {
      if (!this._running) return;
      this.analyser.getFloatTimeDomainData(this.buffer);
      let sumSquares = 0;
      let peak = 0;
      for (let i = 0; i < this.buffer.length; i++) {
        const v = this.buffer[i];
        sumSquares += v * v;
        const abs = Math.abs(v);
        if (abs > peak) peak = abs;
      }
      const rms = Math.sqrt(sumSquares / this.buffer.length);
      const db = rms > 0 ? 20 * Math.log10(rms) : -Infinity;
      const peakDb = peak > 0 ? 20 * Math.log10(peak) : -Infinity;
      this.lastDb = db;
      const now = performance.now();
      if (peakDb >= this.lastPeakDb || now > this._peakHoldUntil) {
        this.lastPeakDb = peakDb;
        this._peakHoldUntil = now + 800;
      }
      if (this.barEl) {
        const pct = clamp01((db - this.minDb) / (this.maxDb - this.minDb));
        this.barEl.style.width = `${(pct * 100).toFixed(1)}%`;
        this.barEl.dataset.db = Number.isFinite(db) ? db.toFixed(1) : "-inf";
        this.barEl.classList.toggle("meter-clip", peakDb > -0.5);
      }
      if (this.dbLabelEl) {
        this.dbLabelEl.textContent = Number.isFinite(db) ? `${db.toFixed(1)} dB` : "-inf";
      }
      if (this.stateEl) {
        const isSignal = Number.isFinite(peakDb) && peakDb > this.silenceThresholdDb;
        this.stateEl.textContent = isSignal ? "signal" : "silence";
        this.stateEl.className = "status-pill " + (isSignal ? "ok" : "warn");
      }
      this._raf = requestAnimationFrame(tick);
    };
    this._raf = requestAnimationFrame(tick);
  }

  stop() {
    this._running = false;
    if (this._raf) cancelAnimationFrame(this._raf);
    this._raf = null;
    if (this.barEl) {
      this.barEl.style.width = "0%";
      this.barEl.dataset.db = "-inf";
      this.barEl.classList.remove("meter-clip");
    }
  }
}

function clamp01(v) {
  return Math.max(0, Math.min(1, v));
}
