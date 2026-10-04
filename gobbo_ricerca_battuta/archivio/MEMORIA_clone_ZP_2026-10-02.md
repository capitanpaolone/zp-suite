# MEMORIA — ricerca battuta nel gobbo (ZP Studio Suite)

File vivo. Chi lavora al progetto (Claude, Codex, Paolo) lo LEGGE per intero all'inizio di ogni sessione e lo AGGIORNA durante il lavoro. Serve a recuperare dopo un'interruzione e a non causare regressioni. Non cancellare righe del registro: aggiungi.

## 1. Obiettivo
Podcast di ~2 h di parlato, più personaggi. Il gobbo deve portare Paolo a qualsiasi battuta cercata, ovunque sia in timeline, anche dopo tagli, spostamenti e Glue. Gli SRT sono trascrizioni Whisper (uno per file audio, stesso nome del WAV, tempi = tempo SORGENTE) usate anche dal tecnico audio. Paolo NON vuole esportare marker nei file: gli basta che REAPER segua gli item e sappia dove sono i marker.

## 2. Regole ferme (non violarle)
- NON pubblicare, NON fare version bump, NON push/tag/ReaPack: la pubblicazione la lancia solo Paolo.
- NON committare senza richiesta di Paolo.
- NON modificare `02_Gobbo_Verticale.lua` se non strettamente necessario (il gobbo funziona: legge la traccia "Rythmo Band Testi" con UpdateItems()).
- REAPER usa Lua 5.4. Separare logica pura e codice `reaper.*` (`if not reaper then return {...} end`) per testare fuori da REAPER (lupa/lua5.4).
- Non scansionare cartelle personali fuori dal repo.
- Paolo vuole capire cosa si fa e perché; lasciargli i passaggi da cui impara; risparmiare token.
- Modifiche minime: niente riscritture di file interi se basta una modifica.

## 3. Fatti tecnici verificati (da test di Paolo in REAPER)
- Take marker: salvati nel progetto (.RPP), non nel WAV. Posizione = tempo SORGENTE.
- Dopo taglio/spostamento/cancellazione ogni pezzo conserva TUTTI i marker del take (600); contano solo quelli nella parte usata (19). Quindi filtrare sempre su [D_STARTOFFS, D_STARTOFFS + D_LENGTH*D_PLAYRATE).
- Tempo timeline = pos_item + (src − startoffs)/playrate. Gli SRT Whisper sul file intero sono già tempi sorgente: si scrivono direttamente con SetTakeMarker, senza compensazioni.
- Sopravvivono a salvataggio e riapertura. Undo funziona. 600 marker creati in 0,003 s.
- Glue: il nuovo item ha solo i marker nella parte usata (37), ma il WAV incollato NON ha cue dentro.
- Render con "Embed: Take markers" (REAPER ≥ 6.10): NON scrive i take marker nel WAV (solo marker di progetto). Percorso abbandonato.
- Cue dentro un WAV (chunk `cue ` + `LIST adtl/labl`): REAPER li mostra in rosso ma NON sono take marker (GetTakeMarker restituisce 0). L'azione nativa 40692 li trasforma in marker di progetto (tempo timeline, non seguono i tagli).
- Per importare da file esterni con cue: 40692 + script utente `_RSec76c1a2359012fb969d191afa2c67a8c9cd6b67` (marker progetto → take marker) + cancellare i marker di progetto creati.
- Il nome del marker = solo testo su una riga, nessun timecode. Marker = inizio battuta (tempo Whisper).
- Import SRT come take marker: COLLAUDATO (23/23 cue su "Portante Leapmotor B03X.wav", 209 s, 48 kHz mono). `conta` dice "nomi lunghi intatti 0/0" ed è normale (cerca solo le stringhe del test).
- Dati di prova di Paolo: prova.srt, 23 cue; cue lunghe 7, 10, 12 (≈25,7 s); frase doppia alle cue 16 e 18; inizi: #1 0,52 s, #7 48,3 s, #10 74,58 s (1:14,580), #12 102,56 s, #23 193,21 s (3:13,210).

## 4. Architettura scelta
- Take marker nel progetto (seguono cuts/moves/Glue) + SRT con lo stesso nome accanto al WAV (portatore tra progetti/backup) + import opzionale dei cue WAV come take marker.
- Il gobbo resta invariato: legge la traccia "Rythmo Band Testi" (item vuoti, testo in P_NOTES), ricostruita dallo script Sincronizza dai take marker filtrati sulla parte usata.
- Sincronizza marca i propri item con `P_EXT:ZP_SYNC=1` e cancella/rifà solo quelli: i testi scritti a mano restano.
- Gobbo: `UpdateItems()` (riga ~2282 di 02_Gobbo_Verticale.lua) costruisce `cached_items` dalla traccia; ricerca = `FindSubtitleMatch`, che sposta il cursore.

## 5. Motore di trascrizione (ZP Speech Engine)
- Servizio 127.0.0.1:8770 (LaunchAgent com.zp.speech-service); runtime installato in ~/Library/Application Support/ZP/runtimes/speech; `zp-speech request <wav> --format srt --output <srt>`.
- `26_SRT_Tools.lua` scrive l'SRT accanto al WAV con lo stesso nome (solo WAV).
- MacWhisper non fa diarizzazione: il personaggio va ricavato da traccia o nome file.
- Corretto `speech-engine/src/zp_speech/providers/macwhisper.py`: i word timestamp che sforano il segmento vengono clampati ai suoi limiti (errore solo se la parola cade fuori); rimossa WORD_SEGMENT_ROUNDING_TOLERANCE_MS; test aggiornati; 98 test ok, ruff pulito. Dopo modifiche al motore: reinstallare con `ZP/ZP_Tools/install_speech_service.sh` e riavviare il servizio.

## 6. File (bozze in `gobbo_ricerca_battuta/bozze/`)
| File | Stato |
|---|---|
| ZP_test_take_marker.lua | collaudato (crea/conta) |
| ZP_leggi_cue_dal_WAV.lua | testato su WAV di Paolo, lettore Lua puro |
| ZP_import_SRT_come_take_marker.lua | COLLAUDATO da Paolo (parse_time l'ha scritta lui) |
| ZP_importa_cue_come_take_marker.lua | NON provato (catena 40692) |
| ZP_sincronizza_take_marker_nel_gobbo.lua | scritta, NON provata |

## 7. Da fare (in ordine)
1. Sincronizza: verificare formato/nome traccia leggendo `UpdateItems()`, `GetRythmoTrack()`, `IsTextFlowTrackName`, `CollectTextFlowTracks`; collaudo di Paolo (23 marker, taglio, spostamento, rilancio).
2. Ricerca con doppioni (retake): due risultati per la stessa frase + "successivo".
3. Auto-sincronizzazione opzionale (GetProjectStateChangeCount, con limite di frequenza e interruttore).
4. Personaggio da nome traccia/file, se il gobbo lo consente (`cached_character_notes`, `BuildCharacterLanes`).
5. Split delle cue lunghe di Whisper con i timestamp delle parole (soglia configurabile).
6. Azione unica "Trascrivi e importa" (riusa 26_SRT_Tools.lua); verificare la segnalazione errori in REAPER.
7. Integrazione nella Suite (numerazione, menu/azioni, help, README, STATO LAVORI.md). Niente bump versione né pubblicazione: solo elenco per il changelog.
8. Facoltativo: export take marker → SRT accanto ai file dopo un Glue.

## 8. Pulizia in sospeso
- `.git/index.lock` e forse `speech-engine/uv.lock` lasciati nel repo da una sessione cloud: Paolo deve rimuoverli (`rm ~/Documents/zp-suite/.git/index.lock`). Verificare.
- Modifiche non committate: macwhisper.py, test_macwhisper.py, questa cartella.

## 9. PROTOCOLLO DI MEMORIA (obbligatorio)
- All'inizio sessione: leggi questo file e `git status`/`git diff --stat` per vedere lo stato reale.
- Dopo OGNI modifica a un file, e comunque a fine di ogni punto: aggiungi una riga in fondo al registro (sezione 10) con data, file toccati, cosa è cambiato, perché, come è stato provato, stato (da provare / provato da Paolo).
- Prima di cambiare un file già collaudato: annota nel registro quale comportamento va preservato e come verificarlo (regressione). Preferisci aggiungere funzioni a riscrivere.
- Prima di modifiche rischiose: copia il file in `gobbo_ricerca_battuta/backup/<nome>.<data>.bak`.
- Se scopri un fatto tecnico nuovo (comportamento di REAPER, formato, limite): aggiungilo in sezione 3.
- Se una decisione cambia: non cancellare la vecchia, aggiungi "SOSTITUITA da …" con motivo.
- Aggiorna la tabella (sezione 6) e l'elenco (sezione 7) quando cambia lo stato.
- Se ti fermi per limiti di uso: scrivi come ultima riga "STOP: dove sono arrivato, prossimo passo esatto, cosa NON ho finito".

## 10. Registro
- 2026-10-02 (Claude, cowork): collaudo take marker, import SRT 23/23, fix macwhisper.py + test, scritta ZP_sincronizza_take_marker_nel_gobbo.lua (non provata). Creata questa memoria. Prossimo passo: collaudo di Sincronizza da parte di Paolo, poi punto 1 e 2 della sezione 7.
