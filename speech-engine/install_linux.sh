#!/bin/bash
# ZP Speech Engine: installazione o aggiornamento per Linux (OpenAI Whisper locale).
#
# Uso:
#   bash speech-engine/install_linux.sh [--model small|medium|large-v3-turbo|large-v3]
set -euo pipefail

say() { printf '%s\n' "$*"; }
fail() { printf '%s\n' "$*" >&2; exit 1; }

if [[ "$(uname -s)" != "Linux" ]]; then
  fail "Questo script è per Linux. Su macOS usa: bash speech-engine/install_macos.sh"
fi

WHISPER_MODEL="${ZP_WHISPER_MODEL:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) WHISPER_MODEL="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="${ZP_SPEECH_SOURCE:-$SCRIPT_DIR}"
INSTALL_ROOT="${ZP_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zp}"
ENV_DIR="$INSTALL_ROOT/runtimes/speech"
WHISPER_ENV_DIR="$INSTALL_ROOT/runtimes/openai-whisper"
MODELS_DIR="$INSTALL_ROOT/models/whisper"
CONTROL_DIR="$INSTALL_ROOT/control"
LOG_DIR="$INSTALL_ROOT/logs"
SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE_NAME="zp-speech-service.service"
PORT="8770"

[[ -f "$SOURCE_DIR/pyproject.toml" ]] || fail "Sorgente ZP Speech Engine non trovato: $SOURCE_DIR"

command -v ffmpeg >/dev/null 2>&1 || fail "Serve FFmpeg per OpenAI Whisper. Installalo col gestore pacchetti (es. sudo apt install ffmpeg)."

PY=""
for cand in python3.14 python3.13 python3.12 python3.11 "$HOME/.local/bin/python3.11" "$HOME/.local/bin/python3" python3; do
  if command -v "$cand" >/dev/null 2>&1 && \
     "$cand" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
    PY="$(command -v "$cand")"; break
  fi
done
[[ -n "$PY" ]] || fail "Serve Python 3.11+ (con modulo venv). Installalo (es. sudo apt install python3 python3-venv) e rilancia."
say "Python servizio: $PY ($("$PY" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])'))"

WPY=""
for cand in python3.11 "$HOME/.local/bin/python3.11" python3.12 "$HOME/.local/bin/python3.12" "$PY"; do
  if command -v "$cand" >/dev/null 2>&1 && \
     "$cand" -c 'import sys; sys.exit(0 if (3, 9) <= sys.version_info[:2] <= (3, 12) else 1)' 2>/dev/null; then
    WPY="$(command -v "$cand")"; break
  fi
done
[[ -n "$WPY" ]] || WPY="$PY"
say "Python OpenAI Whisper: $WPY"

mkdir -p "$INSTALL_ROOT/runtimes" "$MODELS_DIR" "$CONTROL_DIR" "$LOG_DIR"
[[ -x "$ENV_DIR/bin/python" ]] || "$PY" -m venv "$ENV_DIR"
"$ENV_DIR/bin/python" -m pip install --quiet --upgrade pip
"$ENV_DIR/bin/python" -m pip install --quiet --force-reinstall "$SOURCE_DIR"

[[ -x "$WHISPER_ENV_DIR/bin/python" ]] || "$WPY" -m venv "$WHISPER_ENV_DIR"
say "Installo PyTorch e openai-whisper nell'ambiente dedicato..."
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
  read -r -p "Scelta [1]: " mchoice
  case "${mchoice:-1}" in
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

if command -v systemctl >/dev/null 2>&1 && systemctl --user status >/dev/null 2>&1; then
  mkdir -p "$SYSTEMD_DIR"
  cat > "$SYSTEMD_DIR/$SERVICE_NAME" <<EOF
[Unit]
Description=ZP Speech Local Service

[Service]
Type=simple
WorkingDirectory=$INSTALL_ROOT
Environment="ZP_CONTROL_DIR=$CONTROL_DIR"
ExecStart=$ENV_DIR/bin/zp-speech serve
StandardOutput=append:$LOG_DIR/speech-service.out.log
StandardError=append:$LOG_DIR/speech-service.err.log
Restart=on-failure

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now "$SERVICE_NAME"
  systemctl --user restart "$SERVICE_NAME"
else
  nohup "$ENV_DIR/bin/zp-speech" serve >"$LOG_DIR/speech-service.out.log" 2>"$LOG_DIR/speech-service.err.log" &
fi

for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -fsS --max-time 1 "http://127.0.0.1:$PORT/api/v1/health" >/dev/null 2>&1 && break
  sleep 1
done
if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/api/v1/health" >/dev/null 2>&1; then
  say "Servizio attivo su http://127.0.0.1:$PORT"
fi
if "$ENV_DIR/bin/zp-speech" doctor >/dev/null 2>&1; then
  say "OpenAI Whisper: pronto."
else
  say "OpenAI Whisper: installato (scarica almeno un modello con: $ENV_DIR/bin/zp-speech download-model small)."
fi
