# ZP Speech Engine — contract foundation

This directory contains ZP Speech API/Schema v1 and the Phase 1 MacWhisper provider adapter.
HTTP services and REAPER integrations remain deliberately out of scope.

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
