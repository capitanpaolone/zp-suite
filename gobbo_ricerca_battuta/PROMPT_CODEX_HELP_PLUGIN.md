Sei il collaboratore di Paolo Balestri sulla ZP Suite per REAPER. Rispondi in italiano, testi chiari e diretti. Lavoro lungo: procedi un plugin alla volta, risparmia token, lascia traccia di tutto.

REPO: ~/Documents/ZP/zp-suite (branch codex/zp-speech-phase-1-macwhisper)
LEGGI PRIMA: gobbo_ricerca_battuta/MEMORIA.md (per intero; ultime righe del 2026-10-09), ANTI_REGRESSIONE.md (TUTTE le regole "JSFX / EEL2" e "Harmonic Space Carver": mappa della memoria, gmem, @init, slider_show, niente notazione scientifica).

REGOLE FERME: niente commit/push/tag/bump/ReaPack senza richiesta di Paolo. Mai `git stash`. Backup in gobbo_ricerca_battuta/backup/<file>_prima_help_2026-10-10.<ext> prima di toccare ogni file. `bash gobbo_ricerca_battuta/test/run_all.sh` e `bash gobbo_ricerca_battuta/test/fumo_tutte.sh` OK prima di dire "fatto". Una riga nel registro di MEMORIA.md per ogni plugin finito. Un plugin che non compila in REAPER blocca il lavoro di Paolo: dopo ogni plugin chiedi a Paolo di aprirlo (o caricalo tu con REAPER -nonewinst solo se Paolo lo permette). Mai il DSP che scrive sui parametri (vedi ANTI_REGRESSIONE). Prima di sovrascrivere le copie installate (REAPER/Effects/ZP Suite/..., Scripts/ZP Suite/...) controlla che siano quelle registrate in MEMORIA.

DECISIONE DI PAOLO (2026-10-09): nei plugin il pulsante "?" apre DIRETTAMENTE la sezione della guida HTML di quel plugin, e gli aiuti dentro i plugin seguono la lingua della Suite (italiano / inglese). Un JSFX non puo' aprire il browser: si fa con un PONTE via gmem verso uno script Lua che gira gia'.

PLUGIN (11): ZP Voce: BUS Chain, Harmonic Space Carver, Spoken Finish, Stagekeeper Dialogue Director, Subliminal Presence Layer White, Voiceover Unified Chain. ZP Master: Master Pro, Reference Tone Mirror EQ Pro. ZP Misura: Loudness Meter Multichannel, Oscilloscope 16ch, Voice-Music Probe.
Oggi: 7 usano `options:gmem=ZPVoiceoverSharedBus`; Stagekeeper, Subliminal (options:no_menu), Mirror EQ (options:gfx_hz=30), Loudness Meter e Oscilloscope (options:no_meter) no: aggiungi gmem=ZPVoiceoverSharedBus sulla STESSA riga options (es. `options:no_meter gmem=ZPVoiceoverSharedBus`). Testi degli aiuti oggi mescolati: BUS Chain e Carver in italiano, Stagekeeper quasi tutto in inglese con avvisi in italiano, Master Pro a meta'. Il testo `about:` (il "?" della finestra FX di REAPER) c'e' solo in Carver, Stagekeeper, Loudness Meter.

PASSO 0 — mappa gmem e casella del ponte
- Mappa TUTTE le celle gmem usate da tutti i plugin e dagli script (Shared Bus fino a ~606, Carver per traccia/posizione da 4096, per-traccia 4032-4095, casella HSC 3800-3899, slot Carver da 8310000...). Scegli una zona libera per il ponte (proposta: 3900-3919, verificala) e scrivila in ANTI_REGRESSIONE.md (sezione JSFX) e in MEMORIA.
- Contenuto: cella "lingua" (0 = italiano, 1 = inglese; la scrive il ponte), cella "richiesta help" (numero del plugin 1..11 + numero di sequenza, la scrive il plugin), cella "ack" (la scrive il ponte), cella "ponte vivo" (contatore che il ponte incrementa: se non si muove da 3 s il plugin sa che il ponte e' spento).

PASSO 1 — guida HTML: una sezione per plugin
- In help/index.html e help/en/index.html, sezione #zp-shared-bus: ogni plugin ha il suo blocco con un id stabile: plugin-bus-chain, plugin-carver, plugin-spoken-finish, plugin-stagekeeper, plugin-subliminal, plugin-unified-chain, plugin-master-pro, plugin-mirror-eq, plugin-loudness-meter, plugin-oscilloscope, plugin-probe. Chi non ha una descrizione la riceve (breve: a cosa serve, dove si mette, i controlli principali; prendi i fatti dal codice e dagli `about:` esistenti, non inventare). Poi `python3 gobbo_ricerca_battuta/strumenti/firma_help.py`.

PASSO 2 — il ponte nel Cue Navigator
- File: ZP Voce/ZP Harmonic Space Carver Cue Navigator.lua (helper che parte a ogni avvio, fa gia' gmem_attach("ZPVoiceoverSharedBus")). Aggiungi poche righe, nel suo giro esistente (non un secondo defer): (a) scrive la lingua della Suite (ExtState ZP_STUDIO_SUITE/lingua: "en" -> 1, altrimenti 0) nella cella lingua; (b) incrementa "ponte vivo"; (c) se trova una richiesta help nuova apre help/<lingua>/index.html#<id del plugin> con lo stesso metodo di ZP_UI.help_url/open_url (file:// codificato; l'help sta in Scripts/ZP Suite/ZP Studio Suite/help, en in help/en) e scrive l'ack. Logica pura (numero -> id, lingua -> percorso) testabile, con test in gobbo_ricerca_battuta/test/.
- Se la Suite non e' installata (niente help), apre https://latocardioide.it/strumenti/.
- Rispetta le regole dell'helper in ANTI_REGRESSIONE (un solo helper, richieste cancellate dopo l'uso).

PASSO 3 — "?" in ogni plugin (un plugin alla volta, prima Carver e BUS Chain)
- Un piccolo pulsante "?" in un angolo libero della GUI (mappa prima le coordinate di tutto cio' che e' gia' disegnato in quella zona, regola ANTI_REGRESSIONE). Clic: scrive la richiesta nella casella. Se "ponte vivo" e' fermo: mostra per 4 s una riga "Guida: apri Help ZP > <nome plugin>  (avvia il Cue Navigator dal 33 Benvenuto per aprirla da qui)" / in inglese "Guide: open ZP Help > <plugin> (start Cue Navigator from 33 Welcome to open it from here)".
- Se il plugin ha gia' un pannello di aiuto (overlay) interno, resta: il "?" nuovo apre la guida completa; dove c'e' gia' un "?" che apre l'overlay, chiedi a Paolo quale comportamento vuole (una domanda, due opzioni).

PASSO 4 — lingua dei testi nei plugin
- Ogni testo visibile all'utente (aiuti, overlay, avvisi, suggerimenti; NON i nomi dei parametri slider, che REAPER e OSARA usano e che restano come sono) in due versioni: italiano (quello di oggi, identico) e inglese. Scegli con la cella lingua (lingua = gmem[...] letto in @gfx). Senza ponte acceso la lingua resta quella di serie del plugin: italiano.
- Dove oggi il testo e' in inglese (Stagekeeper), scrivi la versione italiana; dove e' mescolato, uniforma.
- Terminologia: glossario in gobbo_ricerca_battuta/glossario_traduzione.md (item, take, marker, FX, bus, sidechain, gate... restano in inglese).
- Attenzione a: stringhe EEL2 (#s, sprintf, strcpy), limite di lunghezza dei testi disegnati (controlla che l'inglese entri negli stessi riquadri), niente notazione scientifica.

PASSO 5 — testo "about:" (il "?" della finestra FX di REAPER) in tutti gli 11
- Breve, prima italiano poi inglese, stesse informazioni: a cosa serve, dove si inserisce, 3-5 controlli principali, riga finale "Guida completa: ZP Studio Suite > Help > <nome>" / "Full guide: ZP Studio Suite > Help > <name>", crediti: "Sviluppata su un'idea di Paolo Balestri · Lato Cardioide (latocardioide.it)" / "Developed from an idea by Paolo Balestri · Lato Cardioide". Nei plugin con crediti propri (licenze Cockos LGPL nel Loudness Meter e nell'Oscilloscope) i crediti e le licenze esistenti restano intatti.

PRIMA DI PUBBLICARE (non farlo tu): ogni plugin cambiato richiede bump della sua @version: annota in MEMORIA l'elenco per Paolo.

Dopo ogni plugin riassumi a Paolo in 4 righe: cosa cambia, come provarlo in REAPER (un passo per riga: apri il plugin, clic su ?, cambia lingua dal 33 e riapri la finestra FX), cosa resta.
