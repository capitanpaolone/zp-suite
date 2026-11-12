# ZP Studio Suite 2.6.7 — appunti pre-release

Stato: raccolta aperta. Da aggiornare con i collaudi e le modifiche fino alla pubblicazione.

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
- **Gobbo — testo temporizzato:** dal Gobbo verticale si incolla un copione in un item standard. La durata si stima da parole/minuto (predefinito 120), layout e righe vuote; i due Gobbi seguono la durata dell'item. Rotella e barra consentono il riposizionamento manuale e «Riposiziona sul player» riaggancia la lettura. La fine del testo non ferma play o registrazione. Da collaudare in REAPER.

- **ZP Consolidate e registro SRT**: azione 37, modulo `ZP_SRT_Progetto.lua`, PNG toolbar 90×30/180×60, riga toolbar e help integrati; `@provides` e routing ReaPack sono stati integrati; il controllo dell’indice generato resta un gate prima del tag. I SRT/VTT vengono tenuti nel Media e registrati nel RPP. Non è inclusa la scansione degli SRT fuori timeline non registrati: resta affidata all’incarico separato.
- **Benvenuto 33**: scroll smussato e limitato; codice aggiornato in candidata e installazione beta locale, senza prova interattiva dichiarata.

## Prima della pubblicazione

- Raccogliere qui tutti gli interventi verificati dopo la 2.6.6, inclusi quelli emersi nel collaudo export.
- Consolidare su una base aggiornata alla 2.6.6, senza perdere le modifiche beta locali utili.
- Eseguire i controlli anti-regressione e confrontare i file di release preparati, l'installazione REAPER e GitHub prima di pubblicare.

## Copia di riferimento REAPER — 2026-11-09

- Creato il worktree `release/2.6.7` partendo dal tag immutabile `v2.6.6`.
- Copiati i file installati più avanzati elencati in `PROVENIENZA_2.6.7.md`; lo snapshot originale e i rispettivi SHA-256 sono sul Lacie.
- Le versioni interne dei componenti non sono state sostituite con il numero della Suite.
