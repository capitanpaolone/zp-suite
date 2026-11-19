# ZP Studio Suite 2.6.7 — appunti pre-release

Stato: candidata 2.6.7 consolidata su `release/2.6.7` e pronta al gate di pubblicazione (non ancora pubblicata/taggata su `master`).

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
- **ZP Magic Voice 1.2.0 / LAB 3 e zoom JSFX (2026-11-18)**: taratura strumentale completa sull'AU `MagicFlow` (Input Level auto-compensato, Dynamic EQ a 5 bande, Tone EQ + Mid Bump, Dynamic Balance A/B, DRC con SOLO a molla, vista JSFX scorrevole) e grafica proporzionale (`zp_sc`) su tutti i 15 JSFX (`ZP Voce`, `ZP Master`, `ZP Misura`, `ZP Lab`) con DSP invariato al 100%, committati e archiviati su LaCie (`2026-11-18_MagicVoice_LAB3_e_Zoom_JSFX/`).
- **Zoom proporzionale Lua, restyling Project Viewer e fix icone (2026-11-19)**: introdotto `ZP_GfxScale.lua` su tutte le 24 finestre Lua operative (+ `ZP_UI.lua`), corretto lo spacing di `07_Note_Personaggio.lua`, ridisegnato `18_Project_Viewer.lua` (colonna `Tipo` fissa, scorrimento orizzontale su `Nome/Start/End/Durata`, colonne auto-fit e ridimensionabili, griglia 3×2 senza pulsante `Scroll`, `?` adattivo anche a `320 px` in dock), corretta la copia automatica delle icone PNG toolbar in `tools/sincronizza_reaper.sh` e `32_Installa_Toolbar_ZP.lua` (es. `ZP_tbB_37_Consolidate.png`). Collaudato da Paolo in `Reaper26_test`, verificato con `run_all.sh` (incluso `test_gfx_scale.lua`) e `fumo_tutte.sh`, archiviato su LaCie (`2026-11-19_Zoom_Lua_e_Project_Viewer/`).

## Prima della pubblicazione

- Raccogliere qui tutti gli interventi verificati dopo la 2.6.6, inclusi quelli emersi nel collaudo export.
- Consolidare su una base aggiornata alla 2.6.6, senza perdere le modifiche beta locali utili.
- Eseguire i controlli anti-regressione e confrontare i file di release preparati, l'installazione REAPER e GitHub prima di pubblicare.

## Copia di riferimento REAPER — 2026-11-09

- Creato il worktree `release/2.6.7` partendo dal tag immutabile `v2.6.6`.
- Copiati i file installati più avanzati elencati in `PROVENIENZA_2.6.7.md`; lo snapshot originale e i rispettivi SHA-256 sono sul Lacie.
- Le versioni interne dei componenti non sono state sostituite con il numero della Suite.
