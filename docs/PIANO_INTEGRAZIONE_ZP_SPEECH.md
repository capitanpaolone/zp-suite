# ZP Speech — stato e piano d’integrazione

Aggiornato: 2026-11-09. Documento di memoria operativa per la preparazione della Suite 2.6.7. Non certifica ancora una release né dichiara supporto multipiattaforma. La sezione «Stato verificato» descrive la baseline ereditata dalla 2.6.6; implementazione e collaudo della 2.6.7 sono in «Avanzamento implementato».

## Stato verificato nel candidato 2.6.7

- Il worktree `zp-suite-2.6.7` è sul ramo locale `release/2.6.7`, derivato dal tag pubblicato `v2.6.6`.
- La Suite 2.6.6 contiene il client REAPER di ZP Speech e il pulsante d’installazione nel Benvenuto, ma `speech-engine/` è esclusa dall’indice ReaPack e compare ancora in `docs/IN_MATURAZIONE.md`.
- Il pulsante del Benvenuto scarica oggi `speech-engine/` dal ramo mobile GitHub `master`; il runtime installato non è quindi vincolato alla versione della Suite.
- `install_macos.sh` richiede macOS e Python >=3.11, crea un virtualenv ZP, installa il servizio e lo avvia come LaunchAgent sulla porta loopback 8770. Non installa MacWhisper né i suoi modelli.
- Il solo provider di trascrizione implementato è `MacWhisperProvider`. `SpeechService` lo crea direttamente e `/api/v1/capabilities` descrive quel provider. Windows e Linux sono fuori dal supporto attuale.
- Il Benvenuto controlla l’esistenza del binario `zp-speech` e dell’app `MacWhisper.app`; non verifica che il servizio risponda, che la CLI sia utilizzabile o che ci sia un modello pronto.
- `M.find_python` in `ZP Studio Suite/33_Benvenuto_Controllo_Installazione.lua` cerca solo alcuni percorsi fissi (3.14, 3.13, 3.12, 3.11) e prova ad aprire il file con `io.open`; non interroga la versione dell’interprete né scandisce il `PATH` di REAPER.
- Nel controllo del Mac sono risultati presenti Python 3.11 in `~/.local/bin` e Python 3.14 in un percorso Homebrew. Il Benvenuto continua a non rilevare Python: la causa non è ancora provata e va riprodotta dall’interno di REAPER, dato che il percorso Homebrew dovrebbe corrispondere a uno dei candidati codificati.
- Sul Mac il comando ZP Speech e il LaunchAgent risultano installati/attivi. La diagnostica lanciata da Codex non è conclusiva: la sandbox ha impedito l’accesso al socket locale di MacWhisper e al servizio loopback. Non interpretare quell’errore come prova di guasto nell’uso normale di REAPER.

## Provider alternativo studiato

Il repository ufficiale [openai/whisper](https://github.com/openai/whisper) è una possibile implementazione locale alternativa a MacWhisper. Non è un servizio generico già installato: ZP deve aggiungere un adattatore dedicato.

Secondo il README upstream, Whisper richiede Python (compatibilità attesa dichiarata 3.8–3.11), PyTorch, `tiktoken` e FFmpeg; in alcuni casi `tiktoken` può richiedere Rust per la build. L’API Python `transcribe` consente `word_timestamps=True`. Il caricamento di un modello assente ne avvia il download. Per il prototipo scegliere Python 3.11 e mantenere installazione di runtime e pesi fuori dal pacchetto ReaPack.

## Piano

### Fase 0 — debug riproducibile sul Mac

Raccogliere dal contesto REAPER, non solo dal Terminale:

1. versione e architettura di macOS e REAPER;
2. `PATH` visto dal processo REAPER;
3. esito del controllo `io.open` per ogni percorso Python candidato e risultato di `python --version` lanciato sullo stesso candidato;
4. percorso, versione e codice d’uscita di `zp-speech doctor`;
5. stato LaunchAgent e risposte HTTP locali `/api/v1/health` e `/api/v1/capabilities`;
6. versione/risposta della CLI `mw`, modelli installati e presenza/versione FFmpeg;
7. una trascrizione breve di un WAV di prova, con esito e log dell’errore ma senza condividere audio privato.

Usare questo report per spiegare prima il mancato rilevamento Python e l’attuale fallimento MacWhisper. Non installare o aggiornare dipendenze durante la raccolta della baseline.

### Fase 1 — base ZP Speech per 2.6.7

- Distribuire il codice del motore nel tag della Suite e sostituire il download da `master` con il riferimento esatto alla release.
- Rendere Python detection una prova d’esecuzione/versione, includendo i candidati noti e il `PATH` di REAPER; mostrare il percorso trovato e il motivo di un eventuale rifiuto.
- Far distinguere al Benvenuto: runtime installato, servizio raggiungibile, provider pronto e modello disponibile.
- Mantenere l’installazione del motore opzionale e documentare esplicitamente il requisito MacWhisper per il provider attuale.

### Fase 2 — prototipo OpenAI Whisper, inizialmente macOS

- Aggiungere `OpenAIWhisperProvider` dietro al contratto `SpeechProvider`; normalizzare segmenti, parole, lingua e metadati nel contratto ZP v1.
- Rilevare separatamente interprete compatibile, import PyTorch/Whisper, FFmpeg e modelli disponibili; restituire errori diagnostici specifici.
- Usare un ambiente Python separato per PyTorch/Whisper, basato su Python 3.11, per non appesantire o destabilizzare il virtualenv leggero del servizio.
- Conservare i modelli in una directory condivisa ZP, evitare duplicati per app e non scaricarli senza scelta esplicita. Mostrare modello, destinazione, avanzamento, dimensione e spazio richiesto quando disponibili.
- Aggiungere selezione esplicita (`auto`, `macwhisper`, `openai-whisper`) e provider capabilities; in `auto` indicare chiaramente il motore effettivamente scelto. Diarizzazione non supportata va dichiarata, non simulata.
- Provare prima un modello leggero con un WAV italiano noto; poi segmenti/SRT e word timing, timeout, file non valido, assenza rete, modello mancante e memoria/prestazioni.

### Fase 3 — decisione di release e sistemi non Mac

- Includere OpenAI Whisper nella 2.6.7 solo se l’installazione pulita, il rilevamento e il collaudo end-to-end passano sul Mac di riferimento; altrimenti mantenere il provider in beta e pianificarlo per la 2.6.8.
- MacWhisper resta solo macOS. Non dichiarare Windows/Linux supportati sulla sola base dell’implementazione Python: servono prove separate su installazione, ruote PyTorch, FFmpeg, modelli, percorso, prestazioni e regressioni REAPER su ogni sistema.

## Criteri minimi di via libera

- Un singolo report diagnostico distingue correttamente Python assente, incompatibile e presente ma non avviabile da REAPER.
- Il servizio risponde al controllo salute; il provider e almeno un modello sono dichiarati pronti solo dopo una verifica reale.
- Un WAV di riferimento produce transcript ZP valido e SRT con tempi coerenti; i tempi parola sono dichiarati solo se realmente forniti.
- Installazione, aggiornamento e scelta del modello sono versionati, ripetibili e non scaricano silenziosamente modelli pesanti.
- La release non promette supporto Windows/Linux finché le rispettive prove non sono documentate.

## Vincoli di lavoro

- Non modificare MacWhisper o il suo database privato; usare solo la CLI pubblica.
- Non incorporare pesi Whisper/PyTorch nel repository o in ReaPack.
- Prima del rilascio aggiornare `docs/IN_MATURAZIONE.md`, help, README e changelog con lo stato realmente collaudato.
- Nessun commit, push, tag o pubblicazione senza richiesta esplicita di Paolo.

## Avanzamento implementato (2026-11-09)

### 1. Baseline Fase 0 verificata fuori sandbox sul Mac di riferimento
- Servizio HTTP `http://127.0.0.1:8770/api/v1/health` attivo (`zp-speech-service-v1`).
- `zp-speech doctor` e `/api/v1/capabilities` operativi (`EXIT:0`): **MacWhisper 15.10** rilevato con 3 modelli (`whisperkit:openai_whisper-large-v3-v20240930`, `whisperkit:openai_whisper-small`, `parakeet-pro:nvidia_parakeet-v3_494MB`).
- Interpreti Python rilevati sul Mac: `/opt/homebrew/bin/python3` (3.15.2), `/opt/homebrew/bin/python3.14` (3.14.8, usato dal venv del servizio), `~/.local/bin/python3.11` (3.11.16 `uv` aarch64); FFmpeg 9.0.1 in `/opt/homebrew/bin/ffmpeg`.

### 2. Moduli implementati nel candidato 2.6.7
- **`speech-engine/src/zp_speech/providers/openai_whisper.py`**:
  - Adattatore `OpenAIWhisperProvider` conforme al contratto ZP Speech v1 (segmenti e `word_timestamps=True` con conversione secondi $\rightarrow$ ms interi e clamping half-open `[start_ms, end_ms)`).
  - Isolamento dell'ambiente Python di Whisper (`<ZP_ROOT>/runtimes/openai-whisper`) separato dal venv leggero del servizio (`<ZP_ROOT>/runtimes/speech`).
  - Gestione modelli in directory condivisa `<ZP_ROOT>/models/whisper`, senza download impliciti in fase di trascrizione; comandi espliciti `zp-speech models` e `zp-speech download-model <modello>` con controllo preventivo dello spazio disco.
  - Percorsi dati multipiattaforma (`zp_data_root`: `~/Library/Application Support/ZP` su macOS, `%LOCALAPPDATA%\ZP` su Windows, `${XDG_DATA_HOME:-~/.local/share}/zp` su Linux).
- **`speech-engine/src/zp_speech/providers/__init__.py`**, **`service.py`**, **`cli.py`**, **`client.py`**:
  - Selezione provider `auto | macwhisper | openai-whisper` (`detect_provider`): su macOS in modalità `auto` usa MacWhisper se pronto, altrimenti ripiega su OpenAI Whisper; su Windows e Linux usa OpenAI Whisper.
  - Sblocco multipiattaforma di `SingletonLock` in `service.py` (`fcntl` su POSIX, `msvcrt` su Windows) e risoluzione dinamica del provider per job.
- **Installatori per i 3 sistemi operativi**:
  - `speech-engine/install_macos.sh` aggiornato con supporto opzionale `--with-openai-whisper` e `--model <nome>`.
  - `speech-engine/install_linux.sh` creato (venv servizio + venv `openai-whisper`, scelta modello, unità `systemd --user` con fallback background).
  - `speech-engine/install_windows.ps1` creato (verifica Python 3.11+ e FFmpeg, creazione venv, scelta modello e avvio servizio in background).
- **Integrazione Lua REAPER (`33_Benvenuto` e `29_ZP_Trascrizione`)**:
  - `33_Benvenuto_Controllo_Installazione.lua`: `M.find_python` esteso a Python 3.15, `~/.local/bin` e `PATH`; URL di download agganciato al tag della versione della Suite (`M.speech_archive_url`) con uso diretto di `speech-engine/` locale se presente e fallback a `master`; stato distinto (`M.speech_state`) tra runtime installato e motore/modello pronto; pulsante **Whisper locale** e supporto avvio installatore su macOS, Windows e Linux.
  - `29_ZP_Trascrizione.lua`: `M.speech_cli_path` e `speech_ready()` resi multipiattaforma.

### 3. Collaudo eseguito il 2026-11-09 (Mac di riferimento, Apple Silicon)

Eseguito su richiesta di Paolo. Risultati reali, non stime.

**Python (`speech-engine/`, venv di sviluppo Python 3.11.16 fuori dal repo):**
- `pytest --cov=zp_speech --cov-branch`: **203 test passati**, copertura totale line+branch **98,45%** (soglia `fail_under = 95`). `cli.py` e `client.py` al 100%, `service.py` al 99%.
- `ruff check src tests` e `ruff format --check src tests`: OK. `basedpyright` (strict): 0 errori. `ty check`: OK.
- `python -m build --wheel`: OK (`zp_speech_engine-0.0.0-py3-none-any.whl`, con schema JSON, `openai_whisper.py`, `service.py` ed entry point).
- Baseline misurata sul tag `v2.6.6` per confronto: copertura 68%, 34 errori basedpyright, 4 diagnostiche ty, 5 file non formattati. Il debito su `service.py`/`client.py`/`translate.py` era quindi preesistente.
- Correzioni fatte per arrivare al verde (nessun cambio di contratto pubblico):
  - esportato `canonical_model_stem` da `zp_speech.providers`: senza questo export `tests/test_openai_whisper.py` non veniva nemmeno raccolto;
  - ordinamento import e formattazione Ruff; `contextlib.suppress` in `_unlock`;
  - tipizzazione strict: narrowing/cast in `client.py`, `translate.py` (`parse_answer`, `codex_models`), `openai_whisper.py` (probe, filtro parole vuote `_is_blank_word`); alias pubblico `default_runner` in `macwhisper.py` (resta anche `_run`); `SpeechHTTPServer` tipizzato in `service.py` al posto dei `type: ignore`;
  - due piccoli irrobustimenti: `codex_models` restituisce `[]` se il catalogo non è un oggetto JSON (prima andava in eccezione), e il client non va più in eccezione se `error` nel job fallito è una stringa;
  - nuovi test: `tests/test_service.py` (lock singleton, validazione richieste, coda/eviction, server HTTP reale su loopback con controlli Host/Origin, `serve`), `tests/test_client.py` (polling, errori HTTP, timeout) e casi CLI `serve`, `request`, `explain-keys`, `--engine openai-whisper`.

**Lua (dalla radice di `zp-suite-2.6.7/`, Lua 5.5.1):**
- `test_benvenuto.lua`: 74 asserzioni OK, exit 0. `test_trascrizione.lua`: 33 asserzioni OK, exit 0.
- `luac -p` OK su `33_Benvenuto_Controllo_Installazione.lua` e `29_ZP_Trascrizione.lua`.

**End-to-end sul Mac (MacWhisper + OpenAI Whisper):**
- `bash speech-engine/install_macos.sh --with-openai-whisper --model small`: OK. Venv OpenAI Whisper su `~/.local/bin/python3.11` (3.11.16) con `openai-whisper 20250625` e `torch 2.15.0`; `small.pt` (483.617.219 byte, SHA-256 `9ecf7799…11e794`, uguale al checksum ufficiale) in `~/Library/Application Support/ZP/models/whisper`. Il venv del servizio esistente (Python 3.14.8) è stato riusato; LaunchAgent riavviato, `/api/v1/health` OK.
- `zp-speech models`: `installed = ["openai-whisper:small"]`.
- `zp-speech doctor --engine macwhisper`: MacWhisper 15.10, 3 modelli. `--engine openai-whisper`: versione 20250625, `openai-whisper:small`, `word_timestamps=true`. `--engine auto`: sceglie **macwhisper** (MacWhisper pronto), come previsto.
- WAV di prova da `say -v Alice --data-format=LEI16@16000` (7,69 s, mono 16 kHz) in cartella temporanea:
  - `transcribe --engine openai-whisper --format json`: testo corretto («Buongiorno a tutti, questa è una prova di trascrizione per ZP Studio Suite. Il microfono è acceso e la registrazione procede bene.»), circa 9 s su CPU. Documento valido contro lo schema JSON e il validatore semantico ZP v1: `model = openai-whisper:small`, `language = it`, `word_timestamps = true`, 2 segmenti, 22 parole con confidenza, tutte contenute nei segmenti; `source_id` uguale allo SHA-256 del WAV.
  - `--format srt`: 2 cue (`00:00:00,000 → 00:00:04,500`, `00:00:04,780 → 00:00:07,600`), tempi monotoni, entro la durata del WAV e identici ai segmenti JSON.
  - Percorso via servizio (`zp-speech request --engine openai-whisper`): stesso SRT.
- Senza rete: stessa trascrizione lanciata sotto `sandbox-exec` con le connessioni IP in uscita negate (prima verificato che curl e `urllib` del venv Whisper fallissero): exit 0, SRT identico byte per byte a quello ottenuto con la rete.
- Modello non scaricato: `--model medium` senza rete restituisce subito (≈1,3 s) `unsupported_model` con `installed: ["openai-whisper:small"]`, exit 2; nessun file nuovo nella cartella modelli né in `~/.cache/whisper`. Via servizio: `model is not installed: medium`, exit 2.
- File WAV/JSON/SRT temporanei rimossi al termine.

### 4. Cosa resta da verificare
- Collaudo reale su macchine **Windows e Linux**: restano **sperimentali** finché non sono provati sui rispettivi sistemi (installatori, ruote PyTorch, FFmpeg, percorsi, prestazioni, regressioni REAPER).
- Prova dall'interno di REAPER del Benvenuto (rilevamento Python, stato motore/modello, pulsante **Whisper locale**) e della 29 con `openai-whisper`, dopo la copia degli script nell'installazione REAPER.
- Installazione da zero su un Mac senza venv preesistenti e senza MacWhisper (qui il venv Whisper esisteva già con pip 24.0 ed è stato aggiornato).
- Prestazioni e memoria con modelli più grandi (`large-v3-turbo`, `large-v3`) e file lunghi; timeout.
