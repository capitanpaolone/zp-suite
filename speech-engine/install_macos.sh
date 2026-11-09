#!/bin/bash
# ZP Speech Engine: installazione o aggiornamento del servizio locale di trascrizione (macOS).
#
# Supporta:
#   - MacWhisper (tramite la sua CLI pubblica, se installato in /Applications)
#   - OpenAI Whisper locale (in ambiente isolato Python 3.11 sotto ~/Library/Application Support/ZP)
#
# Uso:
#   bash speech-engine/install_macos.sh [--with-openai-whisper] [--model small|medium|large-v3-turbo|large-v3]
set -euo pipefail

say() { printf '%s\n' "$*"; }
fail() { printf '%s\n' "$*" >&2; exit 1; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "Questo script è per macOS. Su Linux usa: bash speech-engine/install_linux.sh
Su Windows usa: powershell -ExecutionPolicy Bypass -File speech-engine\\install_windows.ps1"
fi

WITH_WHISPER="${ZP_INSTALL_OPENAI_WHISPER:-0}"
WHISPER_MODEL="${ZP_WHISPER_MODEL:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-openai-whisper) WITH_WHISPER=1; shift ;;
    --model) WHISPER_MODEL="${2:-}"; WITH_WHISPER=1; shift 2 ;;
    *) shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="${ZP_SPEECH_SOURCE:-$SCRIPT_DIR}"
INSTALL_ROOT="${ZP_DATA_DIR:-$HOME/Library/Application Support/ZP}"
ENV_DIR="$INSTALL_ROOT/runtimes/speech"
WHISPER_ENV_DIR="$INSTALL_ROOT/runtimes/openai-whisper"
MODELS_DIR="$INSTALL_ROOT/models/whisper"
CONTROL_DIR="$INSTALL_ROOT/control"
LOG_DIR="$INSTALL_ROOT/logs"
PLIST="$HOME/Library/LaunchAgents/com.zp.speech-service.plist"
LABEL="com.zp.speech-service"
PORT="8770"
UID_NUM="$(id -u)"

[[ -f "$SOURCE_DIR/pyproject.toml" ]] || fail "Sorgente ZP Speech Engine non trovato: $SOURCE_DIR
Lancia lo script dalla cartella speech-engine del repo zp-suite, oppure imposta ZP_SPEECH_SOURCE."

# --- 1. Python 3.11+ per il servizio ZP Speech -------------------------------
PY=""
for cand in python3.15 python3.14 python3.13 python3.12 python3.11 \
            "$HOME/.local/bin/python3.14" "$HOME/.local/bin/python3.13" \
            "$HOME/.local/bin/python3.12" "$HOME/.local/bin/python3.11" "$HOME/.local/bin/python3" \
            /opt/homebrew/bin/python3.15 /opt/homebrew/bin/python3.14 /opt/homebrew/bin/python3.13 \
            /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.11 /opt/homebrew/bin/python3 \
            /usr/local/bin/python3 \
            /Library/Frameworks/Python.framework/Versions/Current/bin/python3 python3; do
  if command -v "$cand" >/dev/null 2>&1 && \
     "$cand" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
    PY="$(command -v "$cand")"; break
  fi
done
[[ -n "$PY" ]] || fail "Serve Python 3.11 o piu' recente e non lo trovo.
Installalo da python.org oppure con Homebrew (brew install python), poi rilancia questo script."
say "Python servizio: $PY ($("$PY" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])'))"

# --- 2. Porta 8770: deve essere libera o gia' nostra ------------------------
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

# --- 3. Ambiente Python del servizio e motore -------------------------------
mkdir -p "$INSTALL_ROOT/runtimes" "$MODELS_DIR" "$CONTROL_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"
if [[ -x "$ENV_DIR/bin/python" ]] && \
   ! "$ENV_DIR/bin/python" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
  say "Ambiente esistente con Python troppo vecchio: lo ricreo."
  rm -rf "$ENV_DIR"
fi
[[ -x "$ENV_DIR/bin/python" ]] || "$PY" -m venv "$ENV_DIR"
"$ENV_DIR/bin/python" -m pip install --quiet --upgrade pip
"$ENV_DIR/bin/python" -m pip install --quiet --force-reinstall "$SOURCE_DIR"

# --- 4. Provider: MacWhisper e/o OpenAI Whisper -----------------------------
HAS_MW=0
[[ -d "/Applications/MacWhisper.app" ]] && HAS_MW=1

if [[ "$HAS_MW" == "0" && "$WITH_WHISPER" == "0" && -t 0 ]]; then
  say ""
  say "MacWhisper non e' presente in /Applications."
  read -r -p "Vuoi installare il motore locale OpenAI Whisper (gratuito, open source)? [S/n] " ans
  if [[ -z "$ans" || "$ans" =~ ^[SsYy] ]]; then
    WITH_WHISPER=1
  fi
fi

if [[ "$WITH_WHISPER" == "1" ]]; then
  say ""
  say "--- Configurazione OpenAI Whisper (ambiente isolato Python 3.11) ---"
  if ! command -v ffmpeg >/dev/null 2>&1 && [[ ! -x /opt/homebrew/bin/ffmpeg && ! -x /usr/local/bin/ffmpeg ]]; then
    fail "Per OpenAI Whisper serve FFmpeg. Installalo con: brew install ffmpeg"
  fi
  WPY=""
  for cand in "$HOME/.local/bin/python3.11" /opt/homebrew/bin/python3.11 \
              /opt/homebrew/opt/python@3.11/bin/python3.11 /usr/local/bin/python3.11 \
              /Library/Frameworks/Python.framework/Versions/3.11/bin/python3 python3.11 \
              "$HOME/.local/bin/python3.12" /opt/homebrew/bin/python3.12 \
              /opt/homebrew/opt/python@3.12/bin/python3.12 python3.12; do
    if command -v "$cand" >/dev/null 2>&1 && \
       "$cand" -c 'import sys; sys.exit(0 if (3, 9) <= sys.version_info[:2] <= (3, 12) else 1)' 2>/dev/null; then
      WPY="$(command -v "$cand")"; break
    fi
  done
  if [[ -z "$WPY" ]] && command -v uv >/dev/null 2>&1; then
    WPY="$(uv python find 3.11 2>/dev/null || true)"
  fi
  [[ -n "$WPY" ]] || fail "Per OpenAI Whisper serve Python 3.11 (o 3.12) per le ruote precompilate di PyTorch/tiktoken.
Installalo con: brew install python@3.11 (oppure da python.org)."
  say "Python per OpenAI Whisper: $WPY ($("$WPY" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])'))"
  [[ -x "$WHISPER_ENV_DIR/bin/python" ]] || "$WPY" -m venv "$WHISPER_ENV_DIR"
  say "Installo PyTorch e openai-whisper nell'ambiente dedicato (puo' richiedere qualche minuto la prima volta)..."
  "$WHISPER_ENV_DIR/bin/python" -m pip install --upgrade pip
  "$WHISPER_ENV_DIR/bin/python" -m pip install openai-whisper

  if [[ -z "$WHISPER_MODEL" && -t 0 ]]; then
    say ""
    say "Scegli il modello OpenAI Whisper da scaricare in $MODELS_DIR:"
    say "  1) small           (~465 MB)  - veloce, ottimo per test e macchine leggere"
    say "  2) large-v3-turbo  (~1550 MB) - consigliato: alta qualita' italiano e veloce"
    say "  3) medium          (~1460 MB) - intermedio"
    say "  4) large-v3        (~2950 MB) - massima precisione, piu' pesante"
    say "  0) Non scaricare ora"
    read -r -p "Scelta [2]: " mchoice
    case "${mchoice:-2}" in
      1) WHISPER_MODEL="small" ;;
      2) WHISPER_MODEL="large-v3-turbo" ;;
      3) WHISPER_MODEL="medium" ;;
      4) WHISPER_MODEL="large-v3" ;;
      *) WHISPER_MODEL="" ;;
    esac
  fi

  if [[ -n "$WHISPER_MODEL" ]]; then
    say "Scarico il modello '$WHISPER_MODEL' in $MODELS_DIR..."
    "$ENV_DIR/bin/zp-speech" download-model "$WHISPER_MODEL"
  fi
fi

# --- 5. LaunchAgent ---------------------------------------------------------
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

# --- 6. Verifica ------------------------------------------------------------
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -fsS --max-time 1 "http://127.0.0.1:$PORT/api/v1/health" >/dev/null 2>&1 && break
  sleep 1
done
if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/api/v1/health" >/dev/null 2>&1; then
  say "Servizio attivo su http://127.0.0.1:$PORT"
else
  say "Il servizio non risponde ancora. Log: $LOG_DIR/speech-service.err.log"
fi
if DOC="$("$ENV_DIR/bin/zp-speech" doctor 2>/dev/null)"; then
  PROV="$(printf '%s' "$DOC" | "$ENV_DIR/bin/python" -c 'import json,sys; d=json.load(sys.stdin); print("%s (%d modelli)" % (d.get("provider","?"), len(d.get("models",[]))))' 2>/dev/null || echo "pronto")"
  say "Motore pronto: $PROV."
else
  say "Nessun motore pronto: apri MacWhisper (con un modello scaricato) oppure rilancia con --with-openai-whisper --model small."
fi
