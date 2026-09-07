# DECISIONS.md — Decisioni Architetturali Consolidate

> Questo documento raccoglie le scelte architetturali irrevocabili e le convenzioni vincolanti adottate per la ZP Suite.

## 1. Gestione del Repository e del File System
- **Isolamento da Servizi di Cloud Sync [Fatto Verificato]**:
  - *Decisione*: Il repository `.git` deve risiedere esclusivamente su file system locale non sincronizzato (es. `/Users/paolob/Documents/zp-suite`).
  - *Motivazione*: I motori di sincronizzazione automatica (Lacie Sync, Dropbox, iCloud) introducono lock sui file e latenze che creano conflitti multipli denominati `-CONFLICT-1` e rischiano la corruzione irreversibile dell'albero `.git`.
- **Cartella Storica su Disco Esterno [Fatto Verificato]**:
  - *Decisione*: La directory `/Volumes/DISCO LACIE/Sync/condivisioni/Paolo Balestri effetti` è declassata ad archivio storico congelato di sola consultazione; nessun file lì contenuto deve essere impiegato come punto di partenza per nuove release.

## 2. Distribuzione e Packaging
- **Adozione Esclusiva di ReaPack [Fatto Verificato]**:
  - *Decisione*: Dismissione totale dei pacchetti ZIP manuali e degli script di installazione per piattaforma (`.command`, `.cmd`, `.sh`). La suite si distribuisce unicamente tramite indice XML compatibile con ReaPack (`index.xml`).
  - *Motivazione*: Automatizza la risoluzione degli aggiornamenti, gestisce le disinstallazioni e previene sovrascritture parziali di file.
- **Normalizzazione Nomi File e Nomi Display [Fatto Verificato]**:
  - *Decisione*: I nomi dei file `.jsfx` e il campo `desc:` non devono mai riportare il numero di versione (es. `ZP Voiceover Unified Chain.jsfx`, non `v4.0-dev`).
  - *Motivazione*: ReaPack mostra all'utente la stringa `desc:`. Versionare il nome del file costringerebbe a rilasciare nuovi plugin invece di aggiornare l'esistente, rompendo i template di traccia e i progetti degli utenti.
- **Componenti Opzionali vs Dipendenze Obbligatorie [Fatto Verificato]**:
  - *Decisione*: La suite non deve pretendere l'installazione forzata di librerie esterne (SWS, js_ReaScriptAPI).
  - *Motivazione*: Ogni script include controlli preventivi del tipo `if not reaper.API_Function then fallback() end`. La suite deve restare pienamente usabile su installazioni REAPER pulite o portable.

## 3. Workflow Doppiaggio, Marker e Render
- **Gerarchia Rigida delle Corsie Marker (Marker Lanes) [Fatto Verificato]**:
  - *Lane 1*: Genera la cartella Mixdown principale.
  - *Lane 2*: Genera la sottocartella all'interno della rispettiva cartella di Lane 1.
  - *Lane 3+*: Riservata a note di lettura, appunti di dizione, metadati di lavorazione; le regioni e i marker fuori da Lane 1 e 2 vengono rigorosamente ignorati dai moduli di export, anteprima e render.
- **Formato Dati Mixdown: CSV vs TXT [Fatto Verificato]**:
  - *Decisione*: Unificazione sul registro cumulativo `Mixdown/Mixdown_Report.csv`.
  - *Motivazione*: I file di testo grezzo `.txt` non permettevano l'elaborazione automatica delle statistiche di consuntivo e minuti voce; il CSV garantisce compatibilità sia con fogli di calcolo che con parser web.
- **Accessibilità Nativa nei Flussi Guidati [Fatto Verificato]**:
  - *Decisione*: Le interfacce operative per non vedenti (in particolare Gestore Progetto e importazione sezioni) devono impiegare le finestre di dialogo native di REAPER anziché controlli grafici custom.
  - *Motivazione*: Assicura compatibilità deterministica con OSARA, rispetta lo stato del Caps Lock e supporta nativamente il copia-incolla da tastiera.
