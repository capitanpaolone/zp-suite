# ZP Harmonic Space Carver — cue di rientro rapido

Richiesta di Paolo, 2026-10-04. Implementazione sorgente v2.4.5 (v2.4.3 di Codex, corretta il 2026-10-05) in `ZP Voce/ZP Harmonic Space Carver.jsfx`, installata in REAPER.

## Interfaccia e comportamento

- Il cue manager usa lo spazio libero a destra dei controlli Advanced.
- Le frecce `<` e `>` saltano al cue precedente o successivo. Il pulsante centrale mostra il cue selezionato (numero in ordine di tempo e minuti:secondi) e ci salta.
- `Timeline: SALTA / RESTA FERMO`: con RESTA FERMO le frecce scorrono i cue senza muovere il playhead (helper non usato). Salvato con il progetto.
- `ADD / REMOVE` (solo in Play) memorizza o rimuove un cue sul playhead; a trasporto fermo dice "PLAY PER AGGIUNGERE" e non resta in sospeso.
- `UNDO LAST` annulla l'ultima aggiunta, rimozione o cancellazione totale.
- `CLEAR ALL` cancella tutti i cue: primo clic arma (CONFERMA?), secondo clic entro 3 s cancella; UNDO LAST li rimette (solo nella sessione).
- Si possono salvare fino a 64 cue nello stato serializzato del plugin.
- Al cue, VCA, bande Carver e Glue tornano a unity con rampa morbida regolabile da 10 a 250 ms (iniziale 200 ms). Per 500 ms il processing resta aperto e ignora il sidechain; poi il ducking riprende normalmente.

## Helper REAPER

`ZP Voce/ZP Harmonic Space Carver Cue Navigator.lua` (sorgente) e `Scripts/ZP Suite/ZP Harmonic Space Carver Cue Navigator.lua` (installato) collega i pulsanti di navigazione al playhead mediante la memoria condivisa JSFX/ReaScript. È installato e impostato come azione globale di avvio SWS; la verifica REAPER ha confermato che non era già definita un’altra azione globale.

## Verifica rimanente

Il ReaScript è stato caricato nell’Action List, avviato e configurato all’avvio globale. Restano da verificare il caricamento della nuova GUI JSFX e i salti reali su cue in un progetto di prova, oltre al salvataggio/riapertura dei cue e alla protezione DSP durante la riproduzione.

## Correzioni 2026-10-05 (v2.4.4)
- I cue non avevano una memoria propria (`quick_points` partiva da 0) e finivano sugli stati dei filtri
  SVF del crossover (celle 0-15): aggiungere un cue poteva far saltare il filtro, e il DSP riscriveva i cue.
  Ora i cue stanno da 8192, il backup per CLEAR ALL da 8320 (in 2.4.4 erano a 1024, dentro il buffer
  dell'oscilloscopio 16-6159: corretto in 2.4.5).
- REAPER rilancia `@init` a ogni Play (il plugin non usa `ext_noinit`): i cue venivano azzerati a ogni
  avvio della riproduzione. Ora sono inizializzati una volta sola (guardia `quick_inited`).
- I cue restano ordinati per tempo (prima la rimozione scambiava l'ultimo al suo posto e la numerazione
  "CUE n / N" non corrispondeva all'ordine). I progetti vecchi si riordinano al caricamento.
- Un cue appena aggiunto non fa ripartire la rampa una seconda volta; i messaggi di stato spariscono dopo 2,5 s.
- Su take FX o input FX il salto e' disattivato (l'indirizzo gmem non sarebbe univoco).
- Helper 1.1: rilegge l'elenco degli FX una volta al secondo invece che a ogni giro.
- 2.4.5: pannello spostato nello spazio libero (y 350-456, sotto la fila Mix/In/Out/SC/Voice Ret) dopo lo
  screenshot di Paolo con sovrapposizioni; tre righe compatte, pomello Rampa a destra, messaggi dentro i
  pulsanti, font piccolo automatico se il testo non entra.
