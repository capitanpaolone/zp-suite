// shared/stats.js — EXPERIMENTAL / FASE 0 / NOT PRODUCT CODE
// Polls RTCPeerConnection.getStats() and turns it into a small, readable
// snapshot: codec, bitrate (computed from byte deltas between polls),
// jitter, packet loss, round-trip time. Nothing here is invented — every
// field comes directly from a WebRTC stats report, or is null if the
// browser did not expose it.

export class StatsPoller {
  /**
   * @param {string} [opts.role] - "studio" | "artist", stamped into every
   *   sample so an exported JSON is unambiguous about which page it came
   *   from once outbound/inbound files sit side by side.
   */
  constructor(pc, { intervalMs = 1000, onSample, role = null } = {}) {
    this.pc = pc;
    this.intervalMs = intervalMs;
    this.onSample = onSample;
    this.role = role;
    this._timer = null;
    this._prev = null; // previous raw stats map, for delta calculations
    this.samples = []; // history, for export
  }

  start() {
    if (this._timer) return;
    this._timer = setInterval(() => this._poll(), this.intervalMs);
    this._poll();
  }

  stop() {
    if (this._timer) clearInterval(this._timer);
    this._timer = null;
  }

  async _poll() {
    if (!this.pc || this.pc.connectionState === "closed") return;
    let report;
    try {
      report = await this.pc.getStats();
    } catch (e) {
      return;
    }
    const now = performance.now();
    const stats = {};
    report.forEach((v) => (stats[v.id] = v));

    const snapshot = {
      t: Date.now(),
      role: this.role,
      connectionState: this.pc.connectionState,
      iceConnectionState: this.pc.iceConnectionState,
      outbound: null,
      inbound: null,
      candidatePair: null,
    };

      if (s.type === "outbound-rtp" && s.kind === "audio") {
        const codec = s.codecId ? stats[s.codecId] : null;
        // DEBUG PASS 0.1d: packets/bytes sent tell us RTP left the machine,
        // NOT that it carried real audio energy — a track producing digital
        // silence (all-zero samples) is transmitted identically to one with
        // real signal. audioLevel/totalAudioEnergy come from the linked
        // "media-source" stats report (the local capture, before encoding),
        // when the browser exposes it — that is the actual proof of content.
        const mediaSource = s.mediaSourceId ? stats[s.mediaSourceId] : null;
        const prev = this._prev && this._prev[s.id];
        const bitrate = prev && prev.bytesSent != null
          ? computeBitrate(s.bytesSent, prev.bytesSent, now, this._prevT)
          : null;
        snapshot.outbound = {
          codec: codec ? `${codec.mimeType} ${codec.clockRate}Hz${codec.channels ? "/" + codec.channels + "ch" : ""}` : null,
          bytesSent: s.bytesSent ?? null,
          packetsSent: s.packetsSent ?? null,
          bitrateKbps: bitrate,
          sourceAudioLevel: mediaSource?.audioLevel ?? null,
          sourceTotalAudioEnergy: mediaSource?.totalAudioEnergy ?? null,
          sourceTotalSamplesDuration: mediaSource?.totalSamplesDuration ?? null,
        };
      }
      if (s.type === "inbound-rtp" && s.kind === "audio") {
        const codec = s.codecId ? stats[s.codecId] : null;
        const prev = this._prev && this._prev[s.id];
        const bitrate = prev && prev.bytesReceived != null
          ? computeBitrate(s.bytesReceived, prev.bytesReceived, now, this._prevT)
          : null;
        snapshot.inbound = {
          codec: codec ? `${codec.mimeType} ${codec.clockRate}Hz${codec.channels ? "/" + codec.channels + "ch" : ""}` : null,
          bytesReceived: s.bytesReceived ?? null,
          packetsReceived: s.packetsReceived ?? null,
          packetsLost: s.packetsLost ?? null,
          jitter: s.jitter ?? null,
          bitrateKbps: bitrate,
          // DEBUG PASS 0.1d: stessa logica dell'outbound sopra, ma questi
          // campi sono direttamente sul report inbound-rtp quando esposti.
          audioLevel: s.audioLevel ?? null,
          totalAudioEnergy: s.totalAudioEnergy ?? null,
          totalSamplesReceived: s.totalSamplesReceived ?? null,
          totalSamplesDuration: s.totalSamplesDuration ?? null,
        };
      }
      if (s.type === "candidate-pair" && s.state === "succeeded" && (s.nominated === undefined || s.nominated)) {
        snapshot.candidatePair = {
          currentRoundTripTime: s.currentRoundTripTime ?? null,
          availableOutgoingBitrateKbps: s.availableOutgoingBitrate ? Math.round(s.availableOutgoingBitrate / 1000) : null,
          localCandidateId: s.localCandidateId ?? null,
          remoteCandidateId: s.remoteCandidateId ?? null,
        };
        const local = stats[s.localCandidateId];
        const remote = stats[s.remoteCandidateId];
        if (local) snapshot.candidatePair.localType = local.candidateType;
        if (remote) snapshot.candidatePair.remoteType = remote.candidateType;
      }
    }

    this._prev = {};
    for (const s of report.values()) {
      if (s.type === "outbound-rtp" || s.type === "inbound-rtp") this._prev[s.id] = s;
    }
    this._prevT = now;

    this.samples.push(snapshot);
    if (this.onSample) this.onSample(snapshot);
  }

  exportJSON() {
    return JSON.stringify(this.samples, null, 2);
  }
}

function computeBitrate(curBytes, prevBytes, curT, prevT) {
  const deltaBytes = curBytes - prevBytes;
  const deltaSeconds = (curT - prevT) / 1000;
  if (deltaSeconds <= 0) return null;
  return Math.round(((deltaBytes * 8) / deltaSeconds) / 1000);
}
