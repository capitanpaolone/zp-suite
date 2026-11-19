# ZP Studio Suite 2.6.7 — appunti pre-release

Stato: release 2.6.7 consolidata su `release/2.6.7`; controlli automatici completati e `index.xml` generato sul commit sorgente `2e3db417f296335d7c718ffb07d1f665017108ad` il 2026-11-19. Push, tag e release GitHub in corso.

## Base

- Ultima release pubblicata: **2.6.6**, tag `v2.6.6`, pubblicata il 4 novembre 2026.
- REAPER sul Mac di Paolo è un ambiente beta permanente. Il numero mostrato dall'installazione non certifica da solo che ogni file sia quello pubblicato.
- Per preparare la release, partire dal codice della 2.6.6 pubblicata e integrare le modifiche locali verificate dopo quella release.
- Tutte le correzioni e novità completate da ora fino alla pubblicazione appartengono alla **2.6.7**. Il numero e i file di release si aggiornano nella preparazione finale, secondo `gobbo_ricerca_battuta/ANTI_REGRESSIONE.md`.

## Modifiche già emerse in questo ciclo

- **ZP Remote — importazione:** ZIP della consegna selezionabile direttamente oppure cartella estratta; importazione consentita anche senza video o pacchetto originale, con item al cursore quando mancano i riferimenti per riallinearli alla regione.
- **ZP Remote — riferimenti:** quando progetto originale e regione corrispondono, gli item mantengono la posizione relativa alla regione di destinazione. Paolo ha riferito che le registrazioni sono entrate calibrate come nel progetto.
- **ZP Suite — Benvenuto:** controllo dei moduli distribuiti e requisiti distinti per importazione (Python 3 e `shasum`) ed esportazione (Python 3 e FFmpeg). Installato in REAPER come modifica pre-release.
- **ZP Remote — esportazione progetto:** collaudo avviato da Paolo il 7 novembre 2026; esito e correzioni da annotare dopo la prova.
- **Gobbo — testo temporizzato:** dal Gobbo verticale si incolla un copione in un item standard. La durata si stima da parole/minuto (predefinito 120), layout e righe vuote; i due Gobbi seguono la durata dell'item. Rotella e barra consentono il riposizionamento manuale e «Riposiziona sul player» riaggancia la lettura. La fine del testo non ferma play o registrazione. Collaudato in REAPER da Paolo.

- **ZP Consolidate e registro SRT**: azione 37, modulo `ZP_SRT_Progetto.lua`, PNG toolbar 90×30/180×60, riga toolbar e help integrati; `@provides` e routing ReaPack sono stati integrati; il controllo dell’indice generato resta un gate prima del tag. I SRT/VTT vengono tenuti nel Media e registrati nel RPP. Non è inclusa la scansione degli SRT fuori timeline non registrati: resta affidata all’incarico separato. Aggiornamento 2026-11-12: l’azione 37 riscritta apre una finestra ZP con due comandi indipendenti e un aiuto (`?`). «Consolida progetto» esamina tutti i take, anche inattivi, deduplica per percorso effettivo, copia byte per byte con verifica (audio, MIDI esterni, video, SECTION/reverse, SRT/VTT del registro, degli item e accanto ai media), gestisce sorgenti non raggiungibili (Riprova, scegli file, salta, annulla) e collisioni di nome, salva il progetto e conserva una copia di sicurezza del RPP prima di ricollegare in un solo blocco Undo. «Pulisci Media» sposta, senza cancellare, i file di primo livello in Media non usati dal progetto in `Media non usati <data ora>`, fuori da Media, dopo conferma; non è proposta con errori, riferimenti intatti o dipendenze manuali. Collaudato con REAPER simulato (`gobbo_ricerca_battuta/test/test_consolidate.lua`) e in REAPER da Paolo, compresi Redo del blocco Undo, MIDI esterni e sorgenti offline. Help toolbar IT/EN aggiornato. Sincronizzato nell’installazione REAPER locale; non pubblicato.
- **Benvenuto 33**: scroll smussato e limitato; codice aggiornato in candidata e installazione beta locale, senza prova interattiva dichiarata.
- **ZP Magic Voice LAB 1.2.0-lab3 e zoom JSFX (2026-11-18)**: taratura strumentale completa sull’AU MagicFlow (Input Level auto-compensato, Dynamic EQ a 5 bande, Tone EQ + Mid Bump, Dynamic Balance A/B, DRC con SOLO a molla, vista JSFX scorrevole). La versione senza LAB (1.2.0) è il prototipo archiviato; la LAB è l’unica destinata alla distribuzione. Grafica proporzionale zp_sc applicata ai 15 file sorgente JSFX, con DSP invariato al 100%; snapshot del prototipo e degli altri file in archivio su LaCie (2026-11-18_MagicVoice_LAB3_e_Zoom_JSFX/).
- **Zoom proporzionale Lua, restyling Project Viewer e fix icone (2026-11-19)**: introdotto `ZP_GfxScale.lua` su tutte le 24 finestre Lua operative (+ `ZP_UI.lua`), corretto lo spacing di `07_Note_Personaggio.lua`, ridisegnato `18_Project_Viewer.lua` (colonna `Tipo` fissa, scorrimento orizzontale su `Nome/Start/End/Durata`, colonne auto-fit e ridimensionabili, griglia 3×2 senza pulsante `Scroll`, `?` adattivo anche a `320 px` in dock), corretta la copia automatica delle icone PNG toolbar in `tools/sincronizza_reaper.sh` e `32_Installa_Toolbar_ZP.lua` (es. `ZP_tbB_37_Consolidate.png`). Collaudato da Paolo in `Reaper26_test`, verificato con `run_all.sh` (incluso `test_gfx_scale.lua`) e `fumo_tutte.sh`, archiviato su LaCie (`2026-11-19_Zoom_Lua_e_Project_Viewer/`).

## Gate di release — 2026-11-19

- `bash gobbo_ricerca_battuta/test/run_all.sh`: superato, inclusi sintassi di 133 file Lua, test di logica, Language Pack e server mock.
- `bash gobbo_ricerca_battuta/test/fumo_tutte.sh`: superato in italiano e inglese.
- `reapack-index --check`: 115 pacchetti, zero errori. I file `37_ZP_Consolidate.lua` e `remote/ZP_Remote_Crea_Pacchetto.lua` sono componenti forniti dalla Suite, non pacchetti separati; `docs/` e `archivio_prototipi/` sono escluse dalla scansione.
- Confronto SHA-256 con REAPER locale: 279 file distribuibili coincidono; la copia installata del prototipo Magic Voice resta locale e non viene inclusa né acquisita nella 2.6.8.
- Pubblicazione autorizzata da Paolo il 2026-11-19.

## Copia di riferimento REAPER — 2026-11-09

- Creato il worktree `release/2.6.7` partendo dal tag immutabile `v2.6.6`.
- Copiati i file installati più avanzati elencati in `PROVENIENZA_2.6.7.md`; lo snapshot originale e i rispettivi SHA-256 sono sul Lacie.
- Le versioni interne dei componenti non sono state sostituite con il numero della Suite.

## Verifica GitHub e passaggio alla 2.6.8 — 2026-11-19

- Al controllo iniziale, GitHub `master` era a `7ae0a3d95c5e8f34828cfe3ddf853503fc42fdcd`; `v2.6.6` e la relativa release sono state conservate. L'archivio sorgenti offline è in `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/2026-11-19_Archivio_ZP_Suite_2.6.6_tag_v2.6.6`.
- La worktree `release/2.6.7` è partita dal tag `v2.6.6`. Prima di questo commit, HEAD era `b37809089f2699eeda7be527d321bfb859aa6168`. Il prototipo è conservato in `archivio_prototipi/ZP Magic Voice.jsfx`; `ZP Magic Voice LAB.jsfx` non è stato modificato.
- `index.xml` ora registra `2.6.7` e punta il pacchetto Suite al commit sorgente finale `2e3db417f296335d7c718ffb07d1f665017108ad`; il pacchetto `ZP Magic Voice LAB.jsfx` è presente e il prototipo senza LAB è escluso. Generazione con `reapack-index` 1.2.6 installato temporaneamente in `/private/tmp`.
- Dopo la pubblicazione di v2.6.7, creare release/2.6.8 identica al tag. Per gli aggiornamenti, confrontare il REAPER locale con quel tag, acquisire soltanto i file effettivamente cambiati e registrare snapshot, SHA-256 e provenienza prima della copia. La candidata e REAPER coincidono sugli altri 279 file; il prototipo archiviato e gli altri elementi locali restano esclusi dalle acquisizioni automatiche in 2.6.8.
- Dopo la pubblicazione di `v2.6.7`, creare `release/2.6.8` identica al tag. Per gli aggiornamenti, confrontare REAPER locale e tag, acquisire soltanto i file effettivamente cambiati e registrare snapshot, SHA-256 e provenienza. Non importare il prototipo Magic Voice né altri elementi locali esclusi.
- La correzione archivia il prototipo fuori dalla cartella distribuibile, esclude `archivio_prototipi/` e `docs/` dalla scansione ReaPack e aggiorna la documentazione italiana e inglese della release.
