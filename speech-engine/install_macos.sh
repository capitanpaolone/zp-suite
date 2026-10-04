#!/bin/bash
# ZP Speech Engine: installazione o aggiornamento del servizio locale di trascrizione.
#
# Solo macOS: usa MacWhisper come motore e un LaunchAgent per tenere il servizio
# su 127.0.0.1:8770, dove lo trovano REAPER (29 ZP Trascrizione) e le app ZP.
# Si lancia dalla cartella del repo, anche su un altro Mac dopo un git clone:
#
#   bash speech-engine/install_macos.sh
#
# Rilanciarlo aggiorna il motore e riavvia il servizio. Non ferma mai processi
# che non sono suoi.
set -euo pipefail

say() { printf '%s\n' "$*"; }
fail() { printf '%s\n' "$*" >&2; exit 1; }

# --- 1. Solo macOS ----------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "ZP Speech per ora funziona solo su macOS (motore MacWhisper, servizio LaunchAgent).

Su Windows o Linux la Suite funziona lo stesso, senza trascrizione automatica:
  1. crea l'SRT con il tuo Whisper (per esempio whisper.cpp o Subtitle Edit),
     con lo stesso nome del WAV e accanto al file;
  2. in REAPER apri 29 ZP Trascrizione e usa \"Abbina da...\": da li' in poi
     marker, Gobbo e Segui i tagli funzionano come su Mac."
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="${ZP_SPEECH_SOURCE:-$SCRIPT_DIR}"
INSTALL_ROOT="$HOME/Library/Application Support/ZP"
ENV_DIR="$INSTALL_ROOT/runtimes/speech"
CONTROL_DIR="$INSTALL_ROOT/control"
LOG_DIR="$INSTALL_ROOT/logs"
PLIST="$HOME/Library/LaunchAgents/com.zp.speech-service.plist"
LABEL="com.zp.speech-service"
PORT="8770"
UID_NUM="$(id -u)"

[[ -f "$SOURCE_DIR/pyproject.toml" ]] || fail "Sorgente ZP Speech Engine non trovato: $SOURCE_DIR
Lancia lo script dalla cartella speech-engine del repo zp-suite, oppure imposta ZP_SPEECH_SOURCE."

# --- 2. Python 3.11 o piu' recente (quello di serie su macOS e' spesso 3.9) ---
PY=""
for cand in python3.14 python3.13 python3.12 python3.11 \
            /opt/homebrew/bin/python3 /usr/local/bin/python3 \
            /Library/Frameworks/Python.framework/Versions/Current/bin/python3 python3; do
  if command -v "$cand" >/dev/null 2>&1 && \
     "$cand" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
    PY="$(command -v "$cand")"; break
  fi
done
[[ -n "$PY" ]] || fail "Serve Python 3.11 o piu' recente e non lo trovo.
Installalo da python.org oppure con Homebrew (brew install python), poi rilancia questo script."
say "Python: $PY ($("$PY" -c 'import sys; print("%d.%d" % sys.version_info[:2])'))"

# --- 3. MacWhisper: il servizio parte anche senza, ma non puo' trascrivere -----
if [[ ! -d "/Applications/MacWhisper.app" ]]; then
  say "ATTENZIONE: MacWhisper non e' in /Applications. Il servizio verra' installato,"
  say "ma per trascrivere serve MacWhisper (con la sua CLI) installato e aperto."
fi

# --- 4. Porta 8770: deve essere libera o gia' nostra ------------------------
RESTART=0
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  HEALTH="$(curl -fsS --max-time 2 "http://127.0.0.1:$PORT/api/v1/health" 2>/dev/null || true)"
  if [[ "$HEALTH" == *'"engine":"zp-speech-service-v1"'* ]]; then
    RESTART=1
  else
    fail "La porta 127.0.0.1:$PORT e' occupata da un programma che non e' ZP Speech.
Non fermo niente: verifica chi la usa (lsof -nP -iTCP:$PORT) e rilancia."
  fi
fi

# --- 5. Ambiente Python separato e motore -----------------------------------
mkdir -p "$INSTALL_ROOT/runtimes" "$CONTROL_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"
if [[ -x "$ENV_DIR/bin/python" ]] && \
   ! "$ENV_DIR/bin/python" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
  say "Ambiente esistente con Python troppo vecchio: lo ricreo."
  rm -rf "$ENV_DIR"
fi
[[ -x "$ENV_DIR/bin/python" ]] || "$PY" -m venv "$ENV_DIR"
"$ENV_DIR/bin/python" -m pip install --quiet --upgrade pip
"$ENV_DIR/bin/python" -m pip install --quiet --force-reinstall "$SOURCE_DIR"

# --- 6. LaunchAgent ---------------------------------------------------------
INSTALL_ROOT="$INSTALL_ROOT" ENV_DIR="$ENV_DIR" CONTROL_DIR="$CONTROL_DIR" LOG_DIR="$LOG_DIR" \
PLIST="$PLIST" LABEL="$LABEL" "$PY" - <<'PY'
import os
import plistlib
from pathlib import Path

env_dir = Path(os.environ["ENV_DIR"])
document = {
    "Label": os.environ["LABEL"],
    "ProgramArguments": [str(env_dir / "bin/zp-speech"), "serve"],
    "WorkingDirectory": os.environ["INSTALL_ROOT"],
    "RunAtLoad": True,
    "KeepAlive": False,
    "ProcessType": "Background",
    "EnvironmentVariables": {
        "ZP_CONTROL_DIR": os.environ["CONTROL_DIR"],
        "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    },
    "StandardOutPath": str(Path(os.environ["LOG_DIR"]) / "speech-service.out.log"),
    "StandardErrorPath": str(Path(os.environ["LOG_DIR"]) / "speech-service.err.log"),
}
Path(os.environ["PLIST"]).write_bytes(plistlib.dumps(document, fmt=plistlib.FMT_XML, sort_keys=True))
PY

if [[ "$RESTART" == "1" ]] || launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$UID_NUM/$LABEL"
  say "ZP Speech aggiornato e riavviato."
else
  launchctl bootstrap "gui/$UID_NUM" "$PLIST"
  say "ZP Speech installato e avviato."
fi

# --- 7. Verifica ------------------------------------------------------------
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -fsS --max-time 1 "http://127.0.0.1:$PORT/api/v1/health" >/dev/null 2>&1 && break
  sleep 1
done
if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/api/v1/health" >/dev/null 2>&1; then
  say "Servizio attivo su http://127.0.0.1:$PORT"
else
  say "Il servizio non risponde ancora. Log: $LOG_DIR/speech-service.err.log"
fi
if "$ENV_DIR/bin/zp-speech" doctor >/dev/null 2>&1; then
  say "MacWhisper: pronto."
else
  say "MacWhisper: non pronto (installalo e aprilo una volta, poi riprova una trascrizione)."
fi
