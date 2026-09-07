# LESSONS.md — Errori Documentati, Bug Risolti e Regole Tecniche

> Registro degli errori reali riscontrati durante lo sviluppo della suite, con le relative contromisure tecniche adottate. Da consultare prima di toccare codice DSP o ReaScript.

## 1. ReaPack e Versioning
- **Commit con Versione Duplicata [Fatto Verificato]**:
  - *Problema*: Rilasciati due commit consecutivi riutilizzando lo stesso tag di versione (v1.2.1). `reapack-index` indicizza una versione unicamente la prima volta che la rileva nello storico Git e ignora in silenzio qualsiasi commit successivo con la medesima versione. Conseguenza: i file del secondo commit (help aggiornato e icone) non sono mai stati recapitati agli utenti.
  - *Regola*: **Una versione, un singolo commit**. Qualsiasi fix o aggiunta richiede un bump di versione (es. patch da 1.2.1 a 1.2.2).

## 2. Audio DSP ed EEL2 (JSFX)
- **Collisione di ID Hover nei Controlli GUI [Fatto Verificato]**:
  - *Problema*: Nel plugin `ZP BUS Chain`, il pomello rotativo di input (`IN`), la sua hit-box di click e la striscia di trim orizzontale condividevano lo stesso identificatore di hover `3001`. Poiché la libreria grafica interna riconosce il doppio click controllando l'identificatore del controllo, due click separati su elementi visivi diversi venivano interpretati come doppio click sul pomello, azzerando il trim e sganciando il cursore del mouse.
  - *Soluzione*: Assegnare ID rigorosamente univoci a ogni singolo componente interattivo (ad es. `3001` per il pomello, `9101` per l'area di presa, `9102` per la striscia di trim).
- **Disaccoppiamento Thread Audio vs Thread Grafico (`@gfx`) [Fatto Verificato]**:
  - *Regola*: La sezione `@gfx` gira a circa 30 fps nel thread grafico della DAW, in modo asincrono rispetto ai blocchi di campioni audio (`@sample` e `@block`). **Nessuna variabile o calcolo audio deve dipendere da codice eseguito in `@gfx`**. L'interfaccia deve limitarsi a leggere stati atomici o buffer dedicati.
- **Fase e Plugin Delay Compensation (PDC) [Fatto Verificato]**:
  - *Problema*: Nei filtri multibanda e nei processori a pendenza dinamica (BrownSlope e Voiceover Chain), l'introduzione di filtri a fase non lineare o lookahead genera disallineamenti temporali. Se sommati in parallelo al segnale dry o monitorati live, generano grave filtraggio a pettine (comb filtering).
  - *Regola*: Ogni blocco di ritardo o filtraggio deve dichiarare esplicitamente la latenza host tramite `pdc_delay` e compensare i percorsi paralleli.
- **Commenti Bilanciati in EEL2 [Fatto Verificato]**:
  - *Problema*: In `ZP Oscilloscope 16ch`, la presenza di un blocco commenti sbilanciato (un `/*` seguito da due `*/`) ha causato l'esclusione silenziosa di oltre quaranta righe di codice funzionale.
  - *Regola*: Ispezionare sempre i commenti multilinea in JSFX o preferire il commento a inizio riga (`//`).

## 3. ReaScript Lua e REAPER Engine
- **Chiusura Finestra Render Nativa in REAPER 7.77+ [Fatto Verificato]**:
  - *Problema*: REAPER 7.77 ("Lucky Seven") gestisce la chiusura della finestra modale di render in modo asincrono. Gli script di mixdown che tentavano di generare i file CSV, creare statistiche o rimuovere item tecnici prima della chiusura completa della finestra causavano il blocco dell'interfaccia o la riapertura spuria della finestra render.
  - *Soluzione*: Implementare un monitor di attesa (`defer`) prudente che verifichi l'effettiva chiusura della finestra render prima di eseguire la pipeline post-render.
- **Le 6 Regole della Migrazione Marker (Script 14) [Fatto Verificato]**:
  1. *Ciclo Multi-Item*: Non usare solo `GetSelectedMediaItem(0, 0)`, ma iterare su `CountSelectedMediaItems(0)`.
  2. *Disuguaglianza Stretta*: Usare `marker_pos < item_end` (non `<=`). Con item adiacenti generati da pulizia silenzi, la condizione inclusiva duplica lo stesso marker su due item contigui.
  3. *Formula di Conversione*: Calcolare accuratamente `source_pos = start_offset + (pos - item_pos) * playrate`.
  4. *Playrate Negativo*: Gestire la direzione inversa quando il take ha velocità negativa (take reverse).
  5. *Boundary della Sorgente*: Verificare che `source_pos` non ecceda la durata reale del media sorgente su disco, altrimenti il take marker viene allocato ma resta invisibile.
  6. *Integrazione OSARA*: Usare sempre la convenzione `osara_outputMessage` prima di mostrare finestre di alert `reaper.MB()`.
- **Prevenzione Conflitti di Routing Send [Fatto Verificato]**:
  - REAPER 7.77 ha stabilizzato le API di creazione/rimozione delle send tra tracce; gli script `23_ZP_Chain_Builder` e `07_Note_Personaggio` richiedono REAPER 7.77 come versione minima consigliata per evitare instabilità nel routing.
