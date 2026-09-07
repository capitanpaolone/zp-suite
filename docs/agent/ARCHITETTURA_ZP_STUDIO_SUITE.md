# ARCHITETTURA_ZP_STUDIO_SUITE

> Mappa architetturale della **ZP Studio Suite** (cartella `ZP Studio Suite/` nel repo `zp-suite`), scritta per un agente AI che deve intervenire sul codice senza dover rileggere tutti i 27 script ogni volta. Non sostituisce `docs/agent/PROJECT.md` (che resta il catalogo ufficiale di scopo/componenti): questo documento scende un livello più in basso, dentro le convenzioni condivise e le duplicazioni, in vista del progetto **ZP Remote** (bridge OSC/WebSocket + gobbo in HTML, vedi `zp-telecomando-reaper`).
>
> **Metodo**: analisi statica via grep mirati sui 27 file `.lua` di `ZP Studio Suite/` (ExtState/ProjExtState, `P_EXT:`, `P_NOTES`, marker/regioni, `dofile`) più lettura strutturale dei file più grandi (i due gobbi, SOLO Recorder, Note Personaggio, Gestore Progetto). Non è una lettura riga-per-riga di tutto il codice né un collaudo in REAPER: è una mappa da verificare sul campo, non un oracolo. Dove non sono sicuro lo dico esplicitamente.
>
> Fuori perimetro: gli 11 effetti JSFX (`ZP Voce`/`ZP Master`/`ZP Misura`) e ZP Catalogo — hanno le loro note a parte.
>
> **Revisione 5 settembre 2026**: §11 e §12 sono stati riscritti in fase di riallineamento architetturale di ZP Remote, per correggere alcune assunzioni della prima versione (un solo ospite, REC/STOP come divieto assoluto invece che capability, Meet/Teams come percorso principale, "gobbo remoto" come unica identità del client artista). L'analisi della Suite (§0-§10, §13) non è stata toccata. Il documento architetturale completo di ZP Remote ora vive in `ARCHITETTURA_ZP_REMOTE.md`; questo file resta la mappa interna della Suite.

---

## 0. Cos'è la ZP Studio Suite oggi

Un pacchetto di 27 script Lua/ReaScript per REAPER, distribuito come unico pacchetto ReaPack, pensato per doppiaggio/voiceover/audiolibri. Sotto la varietà di funzioni (gobbo, SRT, marker, render, registrazione) c'è **un solo modello dati**, mai scritto esplicitamente finora:

> una **battuta/cue** è un *media item* su una traccia testi designata, dove `D_POSITION`/`D_LENGTH` sono il timing e `P_NOTES` è il testo. Tutto il resto (SRT, gobbo, note personaggio, export) legge o scrive questo stesso item, ciascuno a modo suo.

Attorno a questo nucleo girano quattro sottosistemi relativamente indipendenti — import/export SRT, i due gobbi, Note Personaggio, Gestore Progetto/render — più un satellite autonomo (SOLO Recorder) e un satellite offline (SRT Tools in HTML). Nessuno di questi sottosistemi importa dati dagli altri tramite un'API: comunicano solo attraverso lo stato che scrivono nello stesso project (item, track, marker, ExtState).

---

## 1. Convenzioni condivise

### 1.1 Track speciali

Non esiste un registro unico delle track "speciali": ogni script cerca la sua per **nome** (sottostringa case-sensitive quasi ovunque), tranne due casi che usano un tag `P_EXT` dedicato.

| Track / ruolo | Costante nome | Script che la creano/cercano | Come viene identificata |
|---|---|---|---|
| Testi/cue (SRT, gobbo, OSARA) | `"Rythmo Band Testi"` | 01, 05, 05_worker, 02, 03, 09-12, `lib_RythmoBand_Accessibile.lua` | match per sottostringa su `P_NAME` |
| Import video/media massivo | `"MEDIA IMPORT"` | 20 | match esatto su `P_NAME`, creata se assente |
| Warmup ghost (pre-roll tecnico export) | `"ZP Warmup Ghost"` | 17 | match per nome + `P_NOTES == WARMUP_REGION_NAME` |
| Voce personaggio + nota personaggio (coppia) | template `RB Voice Track.RTrackTemplate`, prefisso `"BB Note Personaggio - "` | 07 | creazione da chunk di template; la nota è figlia/folder-child della voce |
| Sessione SOLO Recorder | folder `"ZP SOLO SESSION"` + `VO_MAIN`/`VO_INSERTS`/`VO_RETAKES`/`VO_ALT`/`REF / VIDEO AUDIO` | 25 | match esatto per nome (`find_track_exact`), ricreata se assente |
| Ruolo di catena (bus voce/musica per la sonda) | — | 23 (scrive), 24 (legge) | **non per nome**: tag `P_EXT:ZP_CHAIN_ROLE`, con fallback su sottostringa nome solo se il tag è vuoto |

Osservazione per chi lavorerà al bridge: la maggior parte delle track speciali si trova **rinominandole ogni volta**, scorrendo tutte le track del progetto. Solo `23_ZP_Chain_Builder`/`24_ZP_Probe_Guard` usano un tag stabile (`P_EXT:ZP_CHAIN_ROLE`) indipendente dal nome visibile. È l'unico precedente in codebase di un pattern "tag di ruolo" invece di "match sul nome" — vedi §9 e §10.

### 1.2 Regioni/marker

REAPER espone marker e regioni sulla stessa API (`EnumProjectMarkers*`), distinti da un flag `isrgn`. La Suite usa una convenzione di **lane** per dare struttura ai marker (documentata anche in `docs/agent/DECISIONS.md`, qui verificata a codice in `17_Crea_Regioni_Export_da_Item_Nominati.lua`):

- **Lane 1** → genera la cartella Mixdown principale della sezione;
- **Lane 2** → genera una sottocartella dentro la Lane 1 immediately precedente (`current_lane1` in 17);
- **Lane 3+** → note di lettura/dizione, ignorate da export, render e anteprima.

REAPER numera le lane a partire da 0 internamente; tutti gli script che le leggono fanno `+1` per allinearsi alla UI (vedi `lane_number_at_enum_index` in 17).

Non esiste un modulo condiviso per enumerare marker/regioni: **12 script diversi** chiamano direttamente `EnumProjectMarkers`/`EnumProjectMarkers3`/`AddProjectMarker2`/`SetProjectMarker3`/`DeleteProjectMarker` (02, 03, 04_worker, 05, 05_worker, 08, 14, 17, 18, 19, 20, 22, 25) — vedi §13.

### 1.3 `ExtState` / `ProjExtState`

C'è una convenzione implicita, mai scritta finora, ma seguita in modo abbastanza coerente:

- **`ExtState`** (`reaper.GetExtState`/`SetExtState`, persiste nel `reaper.ini` della macchina) → preferenze UI e comportamento dello script, indipendenti dal progetto (dimensioni finestra, font, tema, ultimo percorso usato). Sezioni trovate: `RythmoBand_Gobbo_State`, `RythmoBand_Teleprompter`, `ZP_VoiceOver_Studio_Gobbo_Orizzontale`, `ZP_RythmoBand_ExportRegions`, `ZP_RythmoBand_ProjectViewer`, `ZP_VoiceOverStudio_FolderVideoMixdown`, `ZP_SOLO_Recorder`.
- **`ProjExtState`** (`reaper.GetProjExtState`/`SetProjExtState`, salvato *dentro* il file .rpp) → dati legati al singolo progetto: selezioni correnti, contatori take, profili di rendering, stato abilitato/indice colore di Note Personaggio. Sezioni trovate: `RythmoBand_NP`, `ZP_RythmoBand_ExportRegions`, `ZP_RythmoBand_ProjectViewer`, `ZP_VoiceOverStudio_FolderVideoMixdown`, `ZP_CHAIN_BUILDER`, `ZP_SOLO_Recorder_Project`.

Da notare: `17_Crea_Regioni_Export_da_Item_Nominati` e `18_Project_Viewer` usano **la stessa sezione** `ZP_RythmoBand_ExportRegions`/`ZP_RythmoBand_ProjectViewer` sia per `ExtState` (preferenze) sia per `ProjExtState` (dati) — sono namespace testuali, non due concetti separati per script, quindi la stessa stringa convive nei due archivi diversi senza collisione (sono API REAPER distinte), ma è facile confondersi leggendo il codice.

`25_ZP_SOLO_Recorder` applica lo split più pulito della Suite: `ExtState` per `mode`/`pin`/`toolbar`/`preroll`/`folder_mode` (preferenze macchina), `ProjExtState` per `active_track_key`/`take_counter` (stato del progetto) — buon modello di riferimento per un futuro modulo condiviso.

### 1.4 `P_EXT:*`

`P_EXT:<chiave>` (via `GetSetMediaItemInfo_String`/`GetSetMediaTrackInfo_String`) è il meccanismo con cui la Suite allega metadati persistenti a un item o a una track, fuori da `P_NOTES`. Catalogo completo trovato nel codice:

| Chiave | Su | Scritto da | Letto da | Significato |
|---|---|---|---|---|
| `RythmoBand_SRT_PATH` | item | 01, 05_worker | 05_worker, 13 | percorso del file SRT sorgente della battuta |
| `RythmoBand_SRT_FILE` | item | 01, 05_worker | 05_worker, 13 | nome file SRT sorgente |
| `RythmoBand_SRT_CUE` | item | 01, 05_worker | 05_worker, 13 | indice del cue nel file SRT sorgente |
| `RythmoBand_HIGHLIGHT` | item | 02, 03 | 02, 03 | termini evidenziati nel gobbo, serializzati (parser duplicato, §13) |
| `RythmoBand_NP` | track | 07 | 02, 03, 07 | flag "questa track è una nota-personaggio" (valore `"1"`) |
| `ZP_CHAIN_ROLE` | track | 23 | 24 | ruolo della track nella catena (bus voce/musica, per la sonda) |
| `ZP_WARMUP_GHOST` (`WARMUP_EXT_KEY`) | item | 17 | 17 | marca l'item/regione di pre-roll tecnico da escludere dall'export "reale" |

Nota terminologica: quasi tutte le chiavi portano ancora il prefisso storico `RythmoBand_*` (nome di lavoro pre-rebrand), mentre gli script più recenti (23, 17) usano il prefisso `ZP_*`. Nessun conflitto oggi, ma è un'incoerenza di naming da tenere a mente se si scrive un glossario/protocollo per il bridge (§12): meglio scegliere *un* prefisso stabile prima di esporre queste chiavi fuori da Lua.

### 1.5 `P_NOTES`

`P_NOTES` sull'item è, di fatto, **il campo testo del cue**: import SRT, gobbo verticale/orizzontale, OSARA e export SRT leggono/scrivono tutti lì. È anche riusato per due scopi collaterali non testuali: come segnaposto ("TESTO" all'inserimento vuoto in 02) e come nome della regione di warmup (`WARMUP_REGION_NAME`, scritto su un item in 17) — quest'ultimo è un uso improprio del campo (il nome semanticamente dovrebbe stare sulla regione, non nell'item), ma funziona perché quell'item non viene mai letto come cue.

---

## 2. Modello SRT/Cue

- **Import** (`01_Importa_Video_SRT.lua`): parsing SRT/WebVTT (`parse_srt`, `parse_subtitle_file`, `subtitle_time_to_seconds`), crea gli item sulla track testi con `P_NOTES = cue.text` e allega `P_EXT:RythmoBand_SRT_PATH/FILE/CUE`. Gestisce anche l'import "solo MIDI reference" (item senza SRT, `P_NOTES = "RythmoBand SRT-only MIDI reference"`).
- **Aggiornamento** (`05_Aggiorna_SRT_Video.lua` + `05_worker_Gestione_SRT.lua`): il worker **duplica byte-per-byte** `subtitle_time_to_seconds`/`parse_subtitle_file`/`parse_srt` dello script 01 (stessa firma, stesso corpo) invece di richiamarli — vedi §13.
- **Reference/lingue** (`06_Importa_SRT_Reference.lua`): non è un motore proprio. È un wrapper di ~10 righe che imposta `_G.RYTHMOBAND_UPDATE_MODE = "reference"` e fa `dofile` dello stesso `05_worker_Gestione_SRT.lua`, che si comporta diversamente a seconda del flag globale. È l'unico vero esempio di riuso di motore nella Suite (in contrasto con la duplicazione 01/05_worker sopra).
- **Backup**: il worker crea una copia della track testi rinominata `<TRACK_NAME> BKP <timestamp>` prima di sovrascrivere, invece di un vero versionamento — è un backup "in progetto", non su disco.
- **Export/round-trip** (`08_Esporta_SRT.lua`): `write_srt`/`seconds_to_srt_time` leggono gli item della track testi e riscrivono un SRT standard, preservando timecode. Chiude il giro: item → SRT → (modifiche esterne) → item aggiornato via 05/06.
- **Motore parallelo offline**: `26_SRT_Tools.lua` è solo un lanciatore (`os.execute("open"/"start"/"xdg-open")`) di `tools/srt_tools.html`, che contiene **una terza implementazione indipendente** di parsing/formattazione SRT in JavaScript (`parseSrt`, `writeSrt`, `formatSrtTime`, `parseSrtTime`, `secToHms`, oltre a merge/traduzione testo-cue). Non condivide codice né garanzie di formato con le due implementazioni Lua, e non tocca il progetto REAPER aperto: è uno strumento offline, file-in/file-out.

---

## 3. Modello Video/Regioni

- **Import** puntuale: `01_Importa_Video_SRT.lua` importa un video associandolo all'SRT.
- **Import massivo**: `20_Importa_Cartelle_Video_Mixdown.lua` popola la track `MEDIA IMPORT`, e mantiene una mappa cartella↔regione (`region_map`) codificata e salvata in `ProjExtState` (`EXT_SECTION = ZP_VoiceOverStudio_FolderVideoMixdown`).
- **Gestore Progetto** (`17_Crea_Regioni_Export_da_Item_Nominati.lua`, il file più grande della Suite): genera regioni da item nominati secondo la gerarchia di lane (§1.2), gestisce il **warmup ghost** (region/item tecnico di pre-roll escluso dall'export "reale" via `P_EXT:ZP_WARMUP_GHOST` + nome/colore dedicati), produce il report cumulativo `Mixdown/Mixdown_Report.csv` (CSV unificato, decisione già presa in `DECISIONS.md`), e applica il fix di `LESSONS.md` sulla chiusura asincrona della finestra di render in REAPER 7.77+ (attende la chiusura reale prima di proseguire la pipeline).
- **Project Viewer ↔ Report Minuti Voce**: `18_Project_Viewer.lua` mostra l'albero marker/regioni e, quando l'utente seleziona regioni da renderizzare, scrive `render_selected_regions`/`render_selected_count` in `ProjExtState` sotto `ZP_RythmoBand_ProjectViewer`. `19_Report_Minuti_Voce.lua` **legge la stessa coppia di chiavi** (ridefinendo la sezione con un proprio nome di costante, `PROJECT_VIEWER_SECTION`, ma con lo stesso valore stringa) per sapere su quali regioni calcolare i minuti di parlato. È l'unico vero "contratto" dati fra due script della Suite, e oggi è tenuto insieme solo da una stringa letterale coerente per convenzione, non da un modulo condiviso o da una costante importata (§8, §13).

---

## 4. Modello Actor/Personaggio

`07_Note_Personaggio.lua`: per ogni ruolo (parsato da testo libero con `parse_roles`, separatori `,`/`;`/a-capo) crea una **coppia di track** a partire dal template `RB Voice Track.RTrackTemplate`:

- la **voce** resta una track normale;
- la **nota** (`"BB Note Personaggio - <voce>"`) è figlia/folder-child della voce, disarmata e nascosta dal mixer.

Colore: assegnato via HSV (`hsv_to_rgb`/palette dedicata) e "specchiato" fra voce e nota (`mirror_track_color`) con fallback casuale se la sorgente non ha colore. Lo stato abilitato/ultimo indice/indice colore vive in `ProjExtState` sotto `RythmoBand_NP` (`KEY_ENABLED`, `KEY_LAST_INDEX`, `KEY_COLOR_INDEX`). Il flag per-track `P_EXT:RythmoBand_NP = "1"` (§1.4) è ciò che i due gobbi (02, 03) leggono per sapere se una track è "di note personaggio" e trattarla di conseguenza durante la navigazione.

Nota di accessibilità propria dello script: gestisce da sé il rilevamento Caps Lock via `JS_VKeys_GetState` (dipendenza opzionale, con fallback) — lo stesso bug di Caps Lock corretto altrove nella Suite (6 call site, da `zp-studio-suite` in memoria) riguarda proprio questa famiglia di controlli.

---

## 5. Gobbo (02 Verticale, 03 Orizzontale)

Sono due finestre `gfx` indipendenti (128 KB e 76 KB di Lua), ciascuna con il proprio loop `reaper.defer(DrawGUI)` (~30 fps, thread grafico separato dal thread audio — regola di `LESSONS.md`: nessun calcolo audio deve dipendere da `@gfx`, qui vale l'equivalente Lua/UI-thread).

- **Sorgenti**: stessa track/item model di §2 — leggono gli item della track testi, `P_NOTES` come testo.
- **Sincronizzazione**: playhead (`GetPlayPosition` in play/rec, `GetCursorPosition` da fermo) confrontato con `pos`/`pos+len` di ogni item, stesso principio di `lib_RythmoBand_Accessibile.lua` (`find_current`/`find_next`/`find_previous`) ma **reimplementato indipendentemente** in ciascuno dei tre posti (02, 03, la lib OSARA) invece di condividere un solo "motore di cue".
- **Rendering**: solo la cornice (bottoni, header, aiuto) passa da `ZP_UI.lua`; il layout del testo scorrevole (word-wrap, evidenziazione termini, scroll) è codice `gfx` immediate-mode scritto due volte, una per orientamento.
- **Editing**: modifica inline del testo che scrive direttamente in `P_NOTES`; i termini evidenziati sono serializzati in `P_EXT:RythmoBand_HIGHLIGHT` tramite `ParseHighlightTerms`/`SerializeHighlightTerms`, **duplicate identiche** fra 02 e 03 (§13). Il widget di editing testo inline (`cursor_from_mouse`, `fit_text`) è scritto una terza volta, con variazioni, anche in `07_Note_Personaggio.lua`.
- **Accessibilità**: entrambi usano OSARA (`osara_outputMessage`). Solo il **Gobbo Orizzontale (03)** aggiunge in più un canale NVDA via `ZP_NVDA_Speech.py` (bridge Python/ctypes verso `nvdaControllerClient64.dll`, solo Windows) — il Verticale (02) non ce l'ha. È un'asimmetria di accessibilità fra le due varianti, non un errore, ma da decidere se colmare (aggiungere NVDA anche a 02) o consolidare in un solo modulo di "voce" condiviso invece che duplicato per orientamento.

---

## 6. SOLO Recorder (25)

Modulo dichiaratamente a parte ("non modifica gli altri script ZP", dal commento di testata), ancora in versione `v0.2.0`/POC nel codice (la Suite lo cita come v1.3.0 nelle note di progetto — probabile disallineamento fra numero di versione interno al file e numero di release pacchetto, da verificare all'header ReaPack).

- **Modello di sessione**: una folder track `"ZP SOLO SESSION"` con figlie fisse `VO_MAIN`/`VO_INSERTS`/`VO_RETAKES`/`VO_ALT`/`REF / VIDEO AUDIO` (`TRACK_NAMES`/`TRACK_ORDER`), create/ritrovate per nome esatto (`ensure_solo_structure`/`find_track_exact`).
- **Stato**: split pulito `ExtState` (macchina: `mode`, `pin`, `toolbar`, `preroll`, `folder_mode`) / `ProjExtState` (progetto: `active_track_key`, `take_counter`) — il migliore esempio in Suite di questa convenzione (§1.3).
- **Registrazione esclusiva**: `arm_only_solo_target` disarma il **record-arm su tutto il progetto**, non solo sulle track SOLO, prima di armare il target scelto — con messaggio di blocco esplicito se l'esclusività non può essere garantita. C'è un pre-roll configurabile (`start_preroll`) prima dello start reale.
- **Take workflow**: `do_record_now` apre una `record_session`; allo stop viene creata automaticamente una regione/marker di take; `next_take` calcola la posizione dopo l'ultimo item + `NEXT_TAKE_GAP_SECONDS` (5s) e riarma+registra in sequenza; `undo_last_take`/**TOGLI TAKE** usa `item_guid`/`snapshot_items` per rimuovere il take appena fatto e ripristinare il cursore.
- **UI**: nel codice esistono **tre** livelli di finestra (`MINI_W/H`, `COMPACT_W/H`, `EXPANDED_W/H`), mentre `docs/agent/CURRENT.md` ne cita solo due ("layout a due livelli, Mini ed Expanded") — piccola discrepanza doc/codice da segnalare, non necessariamente un bug.

---

## 7. Utility browser/HTML già presenti

Tutte le pagine HTML della Suite sono **statiche e locali**, aperte con `os.execute("open"/"start"/"xdg-open")` da Lua: non c'è un server, non c'è alcun collegamento dati col progetto REAPER aperto.

| File | Aperto da | Natura |
|---|---|---|
| `help/index.html` | `00_Apri_Help_ZP_Studio_Suite.lua`, e `ZP_UI.open_help(anchor)` da ogni script (deep-link per ancora) | help ipertestuale generale |
| `help/toolbar.html` (107 KB) | help contestuale toolbar | documentazione pulsanti |
| `help/solo_recorder.html` | help SOLO Recorder | documentazione dedicata |
| `help/voice_cleaner.html` | help script 22 | documentazione dedicata |
| `tools/srt_tools.html` | `26_SRT_Tools.lua` | **unico tool interattivo**: converte/unisce SRT lato client, JS autonomo (§2), file-in/file-out, nessuna scrittura su REAPER |

Per ZP Remote questo è il precedente più vicino a "un browser accanto a REAPER", ma oggi è a **senso unico e senza stato condiviso**: lanciare la pagina e basta. Il salto verso il bridge (§11) è passare da "apri una pagina locale" a "una pagina che legge/scrive lo stato di REAPER in tempo reale".

---

## 8. Dipendenze fra gli script

**Librerie condivise (`dofile`):**

| Libreria | Usata da |
|---|---|
| `ZP_UI.lua` (helper grafici: bottoni, header, help) | 01, 04, 05, 07, 08, 17, 18, 19, 20, 23, 25 (11 script) |
| `lib_RythmoBand_Accessibile.lua` (lookup track/item + TTS OSARA) | 09, 10, 11, 12 |
| `04_worker_Crea_Marker_Item.lua` | richiamato da 04 via `pcall(dofile, WORKER_PATH)` |
| `05_worker_Gestione_SRT.lua` | richiamato da 05 (`pcall(dofile, ...)`) e da 06 (con `_G.RYTHMOBAND_UPDATE_MODE` per cambiare comportamento) |

**Contratti dati impliciti fra script (nessun modulo condiviso, solo stringhe coerenti per convenzione):**

- `18_Project_Viewer` → `19_Report_Minuti_Voce`: `ProjExtState["ZP_RythmoBand_ProjectViewer"]["render_selected_regions"/"render_selected_count"]` (§3).
- `23_ZP_Chain_Builder` → `24_ZP_Probe_Guard`: `P_EXT:ZP_CHAIN_ROLE` sulle track di bus (§1.1, §1.4).
- `07_Note_Personaggio` → `02`/`03` (Gobbo): `P_EXT:RythmoBand_NP` sulle track.
- `01`/`05_worker` → `13_Info_Item_SRT`: `P_EXT:RythmoBand_SRT_PATH/FILE/CUE` sugli item.

Nessuno di questi contratti è verificato a livello di codice (niente costanti condivise, niente versionamento di formato): se uno script rinomina la sua sezione o cambia la forma del valore, l'altro si rompe silenziosamente. È lo stesso rischio, in piccolo, che si porrebbe in grande scala con un bridge esterno (§10).

---

## 9. Componenti che possono diventare API/servizi comuni

Non è necessario (né richiesto ora) rifattorizzare: questi sono candidati per quando si costruirà il livello comune verso ZP Remote.

1. **`ZP_UI.lua`** è già una libreria condivisa reale (11 script). È il punto di partenza naturale per crescere: oggi fa solo grafica, potrebbe accogliere anche i helper "data-aware" più duplicati (vedi punti sotto) senza introdurre una nuova libreria per ognuno.
2. **`lib_RythmoBand_Accessibile.lua`** è già, nella sostanza, l'embrione di un "motore cue" minimo: trova la track, raccoglie gli item validi (`collect_items`), trova cue corrente/successivo/precedente rispetto al playhead. Generalizzato (rimuovendo l'assunzione di un unico nome di track fisso) è il miglior candidato per un modulo `ZP_Cue.lua` unico, usato da OSARA, dai due gobbi e da un futuro bridge.
3. **Parser tempo/SRT**: unificare `subtitle_time_to_seconds`/`parse_subtitle_file`/`parse_srt` (duplicati in 01 e 05_worker, §13) e le almeno 5-6 varianti indipendenti di `format_time`/`seconds_to_srt_time` (08, 13, 17, 18, 19, 25) in un solo `ZP_Time.lua`, con funzioni nominate per formato (`mmss`, `hhmmss_ms_dot`, `hhmmss_ms_comma_srt`) così da non perdere le differenze di formato che oggi sono incidentali.
4. **Enumerazione marker/regioni + lane**: la logica di lane (`lane_number_at_enum_index`, gerarchia Lane1/Lane2/Lane3+) esiste solo dentro 17; il resto degli script che toccano marker/regioni (§1.2) reimplementa l'enumerazione da zero. Un `ZP_Regions.lua` con "dammi le regioni di Lane 1/2 con la loro gerarchia" toglierebbe la duplicazione più diffusa della Suite.
5. **Registro di ruolo per track** (generalizzazione di `P_EXT:ZP_CHAIN_ROLE`): oggi è usato solo per i bus della catena. Estenderlo come convenzione unica per *tutte* le track speciali (testi, video, SOLO session, personaggio) al posto del match per nome (§1.1) darebbe alla Suite — e a un domani bridge esterno — un modo stabile di riferirsi alla "stessa" track anche se l'utente la rinomina.

---

## 10. Cose da NON duplicare nel futuro ZP Remote

Lette come specchio di §9 e §13: ogni duplicazione già presente in Lua è un errore che si può *ripetere una volta di più* nel bridge o nel browser, se non si sta attenti.

- **Non riscrivere un quarto parser SRT/timecode** nel bridge o nella pagina del gobbo HTML: ne esistono già tre indipendenti (01, 05_worker, `tools/srt_tools.html`). Consolidare prima, o almeno far sì che il nuovo layer consumi l'output di uno di questi invece di reinterpretare SRT da zero.
- **Non portare il pattern "track per nome" nel livello web**: se il browser deve riferirsi a "la track dei testi" o "la track REF", che lo faccia tramite il tag di ruolo `P_EXT` (generalizzato, punto 5 di §9), non richiedendo che il nome visualizzato resti invariato — altrimenti ogni rinomina dell'utente rompe anche il bridge, non solo lo script Lua.
- **Non aprire un terzo canale di accessibilità/voce**: esistono già OSARA (via `lib_RythmoBand_Accessibile.lua`, usato da 4 script + i due gobbi) e NVDA-Python (solo nel Gobbo Orizzontale). Un'eventuale sintesi vocale lato browser per l'ospite remoto dovrebbe passare dallo stesso impianto, non aggiungerne un terzo scollegato.
- **Non reinventare l'enumerazione marker/regioni e la gerarchia di lane** una quarta volta nel servizio bridge: è già copiata 12 volte in Lua (§1.2); il bridge dovrebbe leggerla da un unico punto (Lua o, se estratta, un modulo condiviso), non re-implementarla in JS/Node.
- **Non inventare un nuovo prefisso di namespace ExtState/P_EXT ad hoc per ogni nuovo componente**: la Suite ha già `RythmoBand_*` e `ZP_*` che convivono senza un criterio dichiarato (§1.4). Meglio fissare qui, una volta, lo schema di naming per tutto ciò che ZP Remote toccherà (vedi glossario, §12).

---

## 11. Mappa verso ZP Remote

**Questo paragrafo rimanda ad `ARCHITETTURA_ZP_REMOTE.md`**, che è ora il documento canonico per l'architettura di ZP Remote (componenti, ruoli/capability, control plane, media plane, REAPER Adapter, Cue Model, ecc.). Qui resta solo la parte che riguarda specificamente *questa* codebase: quali pezzi della Suite, così come li ho trovati nelle sezioni precedenti, sono il materiale grezzo da cui l'adapter REAPER di ZP Remote dovrà partire.

> **Correzioni rispetto alla versione precedente di questo paragrafo** (revisione 5 settembre 2026): la prima stesura riprendeva senza filtro alcune formulazioni della roadmap Telecomando pre-riallineamento, oggi superate — vedi `ARCHITETTURA_ZP_REMOTE.md` per la trattazione completa: Meet/Teams non sono più il percorso principale (concetto generalizzato in *External Media Ingress*); il motore WebRTC proprio non è "un'opzione", è esplicitamente fuori perimetro v1 ed eventuale solo in futuro; "un solo ospite" diventa "una sola sorgente artista registrabile in v1", con il modello dati che resta aperto a `1 artista + regia + 0..N observer`; "REC/STOP sempre negato all'artista" diventa "REC/STOP sono una capability (`record`) assegnata di norma al ruolo `control`/`director`, non un divieto tecnico assoluto"; il "gobbo remoto" non è più l'unica identità del client artista, che ora comprende anche mic/talkback/video/monitoring locale.

**Cosa resta Lua** (logica che deve restare autoritativa dentro REAPER/DAW Adapter, non delegabile a un servizio esterno — invariato rispetto alla versione precedente):
- l'arbitraggio della registrazione esclusiva (`arm_only_solo_target` e l'intera macchina a stati di 25) — la sicurezza "non registro due tracce per sbaglio" non deve dipendere dalla latenza di rete;
- la creazione di marker/regioni/take al momento giusto (stop, next take) — sono scritture nel progetto, non letture;
- i guardiani "audio-adiacenti" come `24_ZP_Probe_Guard` (mantenere la sonda in fondo al bus è un controllo che deve girare vicino al motore audio);
- i parametri JSFX restano automatizzabili nativamente (già oggi esposti come parametri FX generici — confermato in `zp-telecomando-reaper`), non serve portarli altrove.

**Materiale grezzo per il REAPER Adapter** (ciò che la Suite offre già, da normalizzare — non un elenco di "cosa passa nel bridge", quello è in `ARCHITETTURA_ZP_REMOTE.md` §7):
- il modello cue (item pos/len + `P_NOTES` + `P_EXT:RythmoBand_SRT_*`/`RythmoBand_HIGHLIGHT`, §1.4-§1.5, §2) è la base su cui costruire il `Cue Document` normalizzato — vedi `ARCHITETTURA_ZP_REMOTE.md` §12;
- la gerarchia di lane per marker/regioni (§1.2, §3) è materiale grezzo per l'esposizione di timeline/regioni;
- `P_EXT:ZP_CHAIN_ROLE` (§1.1, §9.5) è il precedente più vicino a un registro di ruolo per track, utile come punto di partenza se l'adapter avrà bisogno di riferirsi a track per funzione invece che per nome;
- le operazioni di alto livello di `25_ZP_SOLO_Recorder` (§6) — `nextTake`, `undo_last_take`, arm esclusivo — sono il tipo di comando "di alto livello" che un Control Client dovrebbe poter invocare, invece di ricostruire la sequenza lato browser (vedi `ARCHITETTURA_ZP_REMOTE.md` §10).

**Cosa NON deve più essere ricostruito una volta di più lato bridge/browser**: vedi §10 sopra — resta valido, ed è anche il riferimento diretto per `ARCHITETTURA_ZP_REMOTE.md` §12 (Cue Model) e §7 (REAPER Adapter).

---

## 12. Glossario/protocollo candidato

Proposta minima di vocabolario comune interno alla Suite — oggi non scritto da nessuna parte, solo convenzioni implicite (§1). **Attenzione a un'ambiguità terminologica**: questo glossario e `ARCHITETTURA_ZP_REMOTE.md` usano entrambi la parola "ruolo" per due concetti diversi e non collegati:

- **ruolo di catena audio** (questo documento, voce sotto): tag `P_EXT:ZP_CHAIN_ROLE` su una track REAPER, usato da `23`/`24` per riconoscere bus voce/musica — un concetto solo-Lua, solo-Suite;
- **ruolo di sessione ZP Remote** (`control`/`director`, `artist`, `observer`): permessi/capability di un client browser in una sessione ZP Remote — un concetto nuovo, definito in `ARCHITETTURA_ZP_REMOTE.md` §3-§4, senza alcuna relazione col precedente.

Non vanno confusi né unificati: sono due tassonomie di "ruolo" a livelli completamente diversi (track audio vs. partecipante umano).

- **Cue**: un item sulla track testi. Campi: `start` (`D_POSITION`), `duration` (`D_LENGTH`), `text` (`P_NOTES`), `source` (`P_EXT:RythmoBand_SRT_PATH/FILE/CUE`, opzionale), `highlights` (`P_EXT:RythmoBand_HIGHLIGHT`, opzionale, oggi serializzato in un formato solo-Lua). Il `Cue Document`/`Cue Model` normalizzato per ZP Remote (che estende questo concetto con Script Mode/Dynamic Gobbo Mode) è definito in `ARCHITETTURA_ZP_REMOTE.md` §12 — questa voce resta la descrizione del dato così com'è oggi in Lua.
- **Ruolo di catena** (*role tag*, solo-Suite): valore di `P_EXT:ZP_CHAIN_ROLE` o equivalente generalizzato (§9.5) che identifica una track per funzione, indipendentemente dal nome visualizzato. Valori oggi esistenti: ruoli di bus (23/24); da estendere a `TEXT_TRACK`, `VIDEO_TRACK`, `PERSONAGGIO_NOTE`, `SOLO_SESSION_*`.
- **Lane**: livello di raggruppamento dei marker/regioni. `1` = sezione/cartella Mixdown, `2` = sottocartella, `3+` = note ignorate dall'export.
- **Sessione** (SOLO Recorder, solo-Suite — da non confondere con la "sessione" di ZP Remote in `ARCHITETTURA_ZP_REMOTE.md` §8): la folder track `ZP SOLO SESSION` con le sue track figlie fisse, più lo stato in `ProjExtState["ZP_SOLO_Recorder_Project"]`.
- **Take**: un `record_session` (25) chiuso da uno stop, con relativa regione/marker generata e `take_counter` incrementato.

La bozza di schema JSON del cue, che in questa revisione precedente viveva qui, è stata spostata e ampliata (Script Mode/Dynamic Gobbo Mode) in `ARCHITETTURA_ZP_REMOTE.md` §12, per non tenere due schemi dello stesso concetto in due file diversi.

---

## 13. Debito tecnico o duplicazioni già visibili

Elenco puntuale, con riferimenti a file, pensato per essere consultato prima di toccare uno qualsiasi di questi punti — **non è una richiesta di rifattorizzare ora**, è la lista che il report doveva segnalare.

1. **Parser SRT duplicato byte-per-byte**: `subtitle_time_to_seconds`/`parse_subtitle_file`/`parse_srt` esistono identiche in `01_Importa_Video_SRT.lua` (righe ~139-218) e in `05_worker_Gestione_SRT.lua` (righe ~167-235). Un fix o un nuovo formato supportato va applicato in due posti o si disallineano.
2. **Un terzo motore SRT, in JavaScript**, dentro `tools/srt_tools.html` (`parseSrt`, `writeSrt`, `formatSrtTime`, `parseSrtTime`) — stessa funzione, zero condivisione di codice o di garanzie di formato con i due Lua sopra.
3. **`format_time`/equivalenti reimplementati indipendentemente in almeno 6 script**: `13_Info_Item_SRT`, `17_Crea_Regioni_Export_da_Item_Nominati`, `18_Project_Viewer`, `19_Report_Minuti_Voce`, `25_ZP_SOLO_Recorder`, oltre a `seconds_to_srt_time` in `08_Esporta_SRT`. Non sono necessariamente bug (alcuni formattano per UI mm:ss, altri per SRT hh:mm:ss,mmm), ma il *pattern* di reinventare la formattazione tempo ogni volta, invece di un'unica libreria con funzioni nominate per formato, è il rischio: una correzione di arrotondamento fatta in un solo posto lascia gli altri cinque inconsistenti.
4. **`ParseHighlightTerms`/`SerializeHighlightTerms` duplicate identiche** fra `02_Gobbo_Verticale.lua` e `03_Gobbo_Orizzontale.lua`.
5. **Enumerazione marker/regioni ripetuta in 12 script** (02, 03, 04_worker, 05, 05_worker, 08, 14, 17, 18, 19, 20, 22, 25) invece di un modulo unico — solo `17` incapsula la logica di lane, tutti gli altri enumerano "a mano".
6. **Widget di editing testo inline reimplementato tre volte** (`cursor_from_mouse`/`fit_text` in 02, 03, 07) con piccole varianti, invece di essere in `ZP_UI.lua`.
7. **Identificazione delle track non uniforme**: la maggior parte del sistema trova le track "speciali" per sottostringa del nome (fragile se l'utente rinomina), mentre 23/24 usano un tag `P_EXT` stabile. Nessun motivo tecnico impedirebbe di generalizzare il secondo pattern (§9.5) — oggi è solo un'eccezione isolata.
8. **Contratti fra script non tipizzati**: 18↔19 (regioni selezionate) e 23↔24 (ruolo bus) dipendono da stringhe letterali coerenti per convenzione, senza una costante condivisa importata né un formato versionato (§8).
9. **Asimmetria di accessibilità fra i due gobbi**: solo il Gobbo Orizzontale (03) ha il bridge NVDA-Python; il Verticale (02) no. Non è detto sia un problema (dipende da chi usa quale schermo/OS), ma è una divergenza da decidere consapevolmente.
10. **Piccola discrepanza doc/codice**: `docs/agent/CURRENT.md` descrive il layout di `25_ZP_SOLO_Recorder` come "Mini ed Expanded" (due livelli), mentre nel codice esistono tre costanti di finestra (`MINI`, `COMPACT`, `EXPANDED`). Da allineare quando si aggiorna `CURRENT.md`.
11. **Prefisso di naming non unificato**: `RythmoBand_*` (storico) e `ZP_*` (più recente) convivono nelle chiavi `ExtState`/`P_EXT` senza un criterio dichiarato (§1.4) — non urgente, ma da fissare prima di esporre queste chiavi a un bridge esterno.

---

*Documento prodotto da Claude (Cowork) il 5 settembre 2026, rivisto il 5 settembre 2026 in fase di riallineamento architetturale di ZP Remote, per il progetto "Report architettura ZP Suite". Consolidato in `docs/agent/` come documentazione canonica del repository `zp-suite` (terza fase di riallineamento, chiusura della fase documentale di ZP Remote). Vive accanto a `docs/agent/PROJECT.md`, `CURRENT.md`, `DECISIONS.md`, `LESSONS.md`, `TOOLS.md` e, per la parte ZP Remote, a `ARCHITETTURA_ZP_REMOTE.md`, `CURRENT_ZP_REMOTE.md`, `ROADMAP_ZP_REMOTE.md` e `REFERENCES_ZP_REMOTE.md` — tutti referenziati dalla mappa della documentazione in `AGENTS.md`.*
