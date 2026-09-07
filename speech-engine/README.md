# ZP Speech Engine — contract foundation

This directory currently contains **only ZP Speech API/Schema v1**. Providers,
HTTP services and REAPER integrations are deliberately outside Phase 0.

## Stable contract

- `schema_version` is the integer `1`.
- `api_version` is the string `v1`.
- Documents are discriminated by `kind`: `transcript`,
  `provider_capabilities`, `error`, or `search_result`.
- All times are integer milliseconds.
- Every interval is half-open: `[start_ms, end_ms)`, with `start_ms < end_ms`.
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
