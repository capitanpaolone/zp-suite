// shared/signaling.js — EXPERIMENTAL / FASE 0 / NOT PRODUCT CODE
//
// Deliberately the simplest signaling that still uses real WebRTC:
//   - Non-trickle ICE: we wait for icegatheringstate === "complete" and
//     exchange one full SDP blob (offer or answer) per step. Slightly
//     slower to connect than trickle ICE, much simpler to eyeball/copy.
//   - Two transports for that one blob, both always active:
//       1) BroadcastChannel — same browser, same machine, auto-relay.
//          Works across two tabs/windows with zero user action.
//       2) Manual copy/paste — always shown in a textarea too, so the
//          exact same code works across two different machines/browsers
//          on a LAN: copy the text from one page, paste it into the other.
//   No server, no external signaling infrastructure, per Fase 0 rules.

const CHANNEL_NAME = "zp-remote-media-spike-room";

export class Signaling {
  constructor({ role, onRemoteMessage, log }) {
    this.role = role; // "studio" | "artist"
    this.log = log;
    this.onRemoteMessage = onRemoteMessage;
    this.channel = "BroadcastChannel" in window ? new BroadcastChannel(CHANNEL_NAME) : null;
    if (this.channel) {
      this.channel.onmessage = (ev) => {
        if (!ev.data || ev.data.from === this.role) return;
        this.log?.info(`Ricevuto via BroadcastChannel: ${ev.data.type}`);
        this.onRemoteMessage?.(ev.data);
      };
    } else {
      this.log?.warn("BroadcastChannel non disponibile: solo modalità manuale (copia/incolla).");
    }
  }

  /** Broadcasts a message to the other tab if same-machine/same-browser. */
  broadcast(type, payload) {
    if (this.channel) {
      this.channel.postMessage({ from: this.role, type, payload });
    }
  }

  close() {
    this.channel?.close();
  }
}

/** Resolves once ICE gathering is complete (or after a safety timeout), so
 * the caller can read pc.localDescription with all host/srflx candidates
 * already embedded — no separate candidate messages to exchange. */
export function waitIceGatheringComplete(pc, timeoutMs = 4000) {
  return new Promise((resolve) => {
    if (pc.iceGatheringState === "complete") return resolve();
    const onChange = () => {
      if (pc.iceGatheringState === "complete") {
        pc.removeEventListener("icegatheringstatechange", onChange);
        clearTimeout(timer);
        resolve();
      }
    };
    pc.addEventListener("icegatheringstatechange", onChange);
    const timer = setTimeout(() => {
      pc.removeEventListener("icegatheringstatechange", onChange);
      resolve(); // proceed with whatever candidates gathered so far
    }, timeoutMs);
  });
}

export function encodeDescription(desc) {
  return btoa(unescape(encodeURIComponent(JSON.stringify(desc))));
}

export function decodeDescription(text) {
  return JSON.parse(decodeURIComponent(escape(atob(text.trim()))));
}
