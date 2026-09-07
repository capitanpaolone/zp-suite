# MacWhisper 14.8.1 regression fixtures

These are unedited public-CLI outputs captured on 2026-09-07 from harmless, synthetic Italian
speech generated with the macOS `Alice` and `Eddy` system voices. The source sentences were
written for this test suite. JSON and SRT were produced with `mw transcribe`, `--language it`,
and the selected `whisperkit:openai_whisper-large-v3-v20240930` model. `two-speakers.json` was
also run with `--speakers`; no speaker field was emitted. No `--persist` option was used.

Fixtures contain no source paths, user identifiers, database content, or private recordings.
