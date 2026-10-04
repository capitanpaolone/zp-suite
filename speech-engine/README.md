# ZP Speech Engine — contract foundation

## Installazione (macOS)

Dalla radice del repo, su questo Mac o su un altro dopo `git clone`:

```bash
bash speech-engine/install_macos.sh
```

Serve Python 3.11 o più recente (quello di serie su macOS è spesso 3.9: lo script lo
cerca da sé e, se manca, dice cosa installare) e MacWhisper per trascrivere. Rilanciarlo
aggiorna il motore e riavvia il servizio su `127.0.0.1:8770`.

Su Windows e Linux lo script si ferma subito e spiega l'alternativa: SRT creato con il
proprio Whisper, accanto al WAV con lo stesso nome, poi «Abbina da…» nella 29.

This directory contains ZP Speech API/Schema v1, the MacWhisper provider adapter,
the singleton loopback service, and its CLI client for REAPER and ZP applications.

## Stable contract

- `schema_version` is the integer `1`.
- `api_version` is the string `v1`.
- Documents are discriminated by `kind`: `transcript`,
  `provider_capabilities`, `error`, or `search_result`.
- All times are integer milliseconds.
- Every interval is half-open: `[start_ms, end_ms)`, with `start_ms < end_ms`.
- Word timestamps always imply segment timestamps.
- Persistent transcripts and search matches contain source time only. Project
  time, item/take GUIDs and track data belong to a future REAPER resolution
  result, never to the persistent transcript.

## Source identity v1

`source_id` has the form `sha256:<lowercase digest>` and is derived from the
exact bytes of the root source file. For a render-index source it is derived
from the exact rendered audio bytes. A path is optional metadata and is never
the identity.

This intentionally treats two different containers/encodings as different v1
sources even when they sound alike. A future canonical-audio identity may be
added without silently changing the meaning of v1 identifiers.

## Validation layers

The bundled JSON Schema Draft 2020-12 validates the public wire shape. The
Python validator additionally checks semantic invariants such as temporal
ordering, positive intervals, word containment, source identity consistency,
and capability consistency.

## Local verification

```bash
uv sync --extra dev
uv run pytest
```

## Phase 1: MacWhisper adapter

The local provider uses only MacWhisper's public CLI at
`/Applications/MacWhisper.app/Contents/MacOS/mw` (or `mw` on `PATH`). It never reads or
writes MacWhisper's private SQLite database and does not use `--persist`.

```console
zp-speech doctor
zp-speech transcribe recording.wav --engine macwhisper --language it --format json
zp-speech transcribe recording.wav --format srt --output recording.srt
```

Capabilities are deliberately conservative and reflect real checks with MacWhisper 14.8.1:
WAV input, JSON/SRT/TXT output, segment and word timestamps, automatic language selection,
and streaming were observed. Speaker labels were not present even with `--speakers` and a
two-voice sample, so diarization is reported as unavailable. MacWhisper's raw JSON does not
identify the automatically detected language; with `--language auto`, the normalized document
therefore preserves `auto` rather than inventing a language.

## Shared local service

`zp-speech serve` starts the provider in one process and accepts local jobs over HTTP. It binds only to loopback and defaults to the fixed port `8770`; it does not choose another port when that port is occupied.

```console
zp-speech serve
curl http://127.0.0.1:8770/api/v1/health
```

Initial API:

- `GET /api/v1/health` — service identity and API version, without calling the provider.
- `GET /api/v1/capabilities` — MacWhisper version, installed models and verified features.
- `POST /api/v1/transcriptions` — enqueue a WAV file by absolute local path; returns a job ID.
- `GET /api/v1/jobs/{job_id}` — poll `queued`, `running`, `succeeded`, or `failed`; successful results are ZP Speech v1 transcript documents.

Provider jobs run one at a time, with at most eight outstanding jobs and a bounded in-memory job history. An OS lock prevents a second service process, even if another port is requested. The API rejects non-loopback Host/Origin headers. Jobs and results are currently process-local: restarting the service interrupts work and clears job history. ZP Tools provides the LaunchAgent installer; it is installed and started on the current macOS profile.

The shared-client command waits for a service job and writes normalized JSON or SRT:

```console
zp-speech request recording.wav --format srt --output recording.srt
```

`ZP Studio Suite/26_SRT_Tools.lua` offers this path alongside the existing offline SRT Tools. ZP Shorts `auto` uses the service first and falls back only to whisper.cpp. The legacy `macwhisper` backend name is routed through the shared queue too; no production Shorts path starts a second MacWhisper transcription. Persistent job recovery, cancellation of a running MacWhisper process, and shared transcript caching remain future work.
