# CURRENT.md — Stato Vivo e Lavori Aperti

> Stato aggiornato: Settembre 2026.
> Questo documento traccia unicamente la situazione attiva, i task pendenti e i prossimi passi operativi. Non contiene resoconti storici.

## 1. Stato Vivo del Repository
- **Allineamento Git**: Il branch `master` è sincronizzato e allineato a `origin/master` (nessun commit pendente da pushare).
- **Distribuzione ReaPack**: ZP Studio Suite e gli 11 effetti JSFX sono pubblicati online tramite `index.xml`.
- **Componenti Integrati nel Master**:
  - Script e toolbar integrati fino alla versione v1.4.0 (inclusi `14_Marker_da_Timeline_a_Item.lua`, `25_ZP_SOLO_Recorder.lua` v1.3.0 e toolbar da 16 pulsanti).
  - Nomi file e direttive `desc:` dei JSFX ripuliti per conformità all'indice ReaPack.

## 2. Lavori Aperti e Task Pendenti

### A. Fatti Verificati a Codice
1. **Collaudo `25_ZP_SOLO_Recorder.lua` (v1.3.0)**:
   - Funzionalità aggiunte: interruttore Monitor su traccia attiva, pulsante `TOGLI TAKE` (rimozione take registrato con ripristino cursore), `RIT - / RIT +` su volume cuffia traccia, layout a due livelli (Mini ed Expanded).
   - *Stato*: Geometria e sintassi verificate a tavolino; necessita di verifica e collaudo operativo dentro REAPER su schermo.
2. **BUS Chain — Selettività Pulsanti Preset Output**:
   - I preset output `POD`, `AUD`, `MIX`, `BRD`, `RAD` rispondono al click solo se la sezione Output è attiva (`out_on && hover && mouse_click`). Da spenti risultano inerti.
   - *Stato*: Verificare con l'utente se questo comportamento è pienamente desiderato o se richiede feedback visivo differente quando disattivo.
3. **Integrazione Documentazione Sito `/strumenti/`**:
   - Tre schede descrittive pronte per l'help della suite e per il sito: *Gobbo e copione*, *Produzione e consegna*, *La catena audio*.
   - Scheda della suite in `studio/sources/strumenti.json` scritta ma non ancora compilata online.

### B. Deduzioni da Riscontri Storici (Da Validare)
- **Script 15 (Take Marker -> Marker Timeline)**:
  - *Ipotesi ricavata dalle note*: È stata ipotizzata una direzione inversa dello Script 14 per riportare i riferimenti dai take marker alla timeline quando un item viene riposizionato.
  - *Stato*: Non ancora implementato né commissionato ufficialmente.
- **`ZP BrownSlope Dynamic Guard Assist` (v0.5-assist-dev)**:
  - Risiede in `ZP Lab/` (escluso da ReaPack).
  - *Stato*: Algoritmo stabile nei calcoli ma in attesa di stress test su sessioni di doppiaggio reali prima di decidere eventuale promozione nella suite ufficiale.

## 3. Prossimo Passo Immediato
1. Esecuzione del test a banco su REAPER di `25_ZP_SOLO_Recorder.lua` (v1.3.0).
2. Verifica visiva dell'help contestuale (`00_Apri_Help_ZP_Studio_Suite.lua`).
3. Verifica anteprima sito `/strumenti/` con `Aggiorna e leggi anteprima.command` per validare le nuove schede.
