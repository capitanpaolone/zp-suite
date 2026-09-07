// shared/log.js — EXPERIMENTAL / FASE 0 / NOT PRODUCT CODE
// Minimal diagnostics logger: timestamped entries in a scroll panel + an
// in-memory buffer that can be exported as text or JSON at the end of a run.

export class DiagLog {
  constructor(el) {
    this.el = el; // container element to append log lines into
    this.entries = []; // { t: ms since start, iso, level, msg, data }
    this.startedAt = Date.now();
  }

  _write(level, msg, data) {
    const now = Date.now();
    const entry = {
      t: now - this.startedAt,
      iso: new Date(now).toISOString(),
      level,
      msg,
      data: data !== undefined ? data : null,
    };
    this.entries.push(entry);
    if (this.el) {
      const line = document.createElement("div");
      line.className = `log-line log-${level}`;
      const secs = (entry.t / 1000).toFixed(2);
      line.textContent = `[+${secs}s] ${msg}${data !== undefined && data !== null ? " " + safeStringify(data) : ""}`;
      this.el.appendChild(line);
      this.el.scrollTop = this.el.scrollHeight;
    }
    const consoleFn = level === "error" ? console.error : level === "warn" ? console.warn : console.log;
    consoleFn(`[zp-remote-spike +${(entry.t / 1000).toFixed(2)}s] ${msg}`, data ?? "");
  }

  info(msg, data) { this._write("info", msg, data); }
  warn(msg, data) { this._write("warn", msg, data); }
  error(msg, data) { this._write("error", msg, data); }
  event(msg, data) { this._write("event", msg, data); }

  elapsedSeconds() {
    return (Date.now() - this.startedAt) / 1000;
  }

  exportText() {
    return this.entries
      .map((e) => `[${e.iso}] (+${(e.t / 1000).toFixed(2)}s) [${e.level.toUpperCase()}] ${e.msg}${e.data !== null ? " " + safeStringify(e.data) : ""}`)
      .join("\n");
  }

  exportJSON() {
    return JSON.stringify({ startedAt: new Date(this.startedAt).toISOString(), entries: this.entries }, null, 2);
  }

  downloadText(filename) {
    downloadBlob(this.exportText(), filename, "text/plain");
  }

  downloadJSON(filename) {
    downloadBlob(this.exportJSON(), filename, "application/json");
  }
}

function safeStringify(data) {
  try {
    return typeof data === "string" ? data : JSON.stringify(data);
  } catch (e) {
    return String(data);
  }
}

export function downloadBlob(content, filename, mime) {
  const blob = new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}

export function formatElapsed(ms) {
  const total = Math.floor(ms / 1000);
  const h = String(Math.floor(total / 3600)).padStart(2, "0");
  const m = String(Math.floor((total % 3600) / 60)).padStart(2, "0");
  const s = String(total % 60).padStart(2, "0");
  return `${h}:${m}:${s}`;
}
