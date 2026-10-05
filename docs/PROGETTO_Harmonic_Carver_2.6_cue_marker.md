# ZP Harmonic Space Carver 2.6 — cue che seguono l'editing (marker `#HSC`)

Decisione di Paolo (2026-10-05): strada **B**. I cue nascono per evitare le automazioni, quindi
niente corsia di automazione: i cue diventano anche marker di servizio sul righello.

Stato: **progetto**. La parte del plugin è già nella 2.5 (comando 5 "sostituisci elenco").
Render offline verificato da Paolo il 2026-10-05: i cue scattano anche in render.
Manca l'helper 1.4 (la 1.3 è uscita con il controllo del routing sidechain).

## Il problema

Nella 2.5 un cue è un tempo assoluto salvato dentro il plugin. Con un taglio in ripple il materiale
si sposta e i cue no: dopo un taglio di 3 s i cue successivi arrivano 3 s in anticipo.

## Come funziona la 2.6

- Ogni cue è anche un marker di progetto chiamato `#HSC`, colore ciano.
- Il `#` lo rende marker di servizio (regola già in 14, aggancio e 31: mai testo, mai nel gobbo
  né nell'SRT, mai copiato o cancellato dal 14). Verificato in `31_SRT_da_Marker_Audio.lua` e
  `ZP_sincronizza_aggancio.lua` (`M.is_service`).
- **Il marker comanda.** Se sposti, cancelli o aggiungi un `#HSC` a mano, o se il ripple lo sposta,
  il Carver si aggiorna. Se aggiungi o togli un cue dal Carver (pulsante o tasto), compare o sparisce
  il marker.
- Il plugin tiene sempre una copia dell'elenco (salvata nel progetto): senza helper e in render
  usa quella.
- L'undo di REAPER (Ctrl+Z) vale anche per i cue, perché i marker sono stato del progetto.

## Helper Cue Navigator 1.4 (da scrivere)

Ogni 0,25 s, per ogni Carver trovato (stessa scansione della 1.2):

1. Legge i marker `#HSC` (`EnumProjectMarkers3`), ordinati per tempo.
2. Legge l'elenco del Carver (gmem `base+4` numero, `base+5..68` tempi).
3. Confronta entrambi con l'ultima istantanea sincronizzata (tenuta in memoria dall'helper):
   - cambiati solo i marker → manda al Carver il comando 5 con l'elenco dei marker;
   - cambiato solo il Carver → aggiunge/toglie i marker (`AddProjectMarker2`, `DeleteProjectMarker`),
     in un blocco di undo "ZP HSC: cue";
   - cambiati entrambi → vincono i marker.
4. Primo avvio su un progetto con cue e senza `#HSC`: crea i marker dai cue (migrazione).

Tolleranza per "stesso cue": 5 ms. Massimo 64 cue (oltre: l'helper avvisa e non crea marker).

### Comando 5 (già nel plugin 2.5.0)

Casella comune gmem `3800`:

| cella | contenuto |
|---|---|
| 3800 | base gmem del Carver destinatario |
| 3801 | comando: 1 aggiungi/togli, 4 annulla, **5 sostituisci elenco** |
| 3802 | posizione (comandi 1) |
| 3803 | seq (si scrive per ultima) |
| 3804 | ack = seq quando il Carver ha eseguito |
| 3805 | esito (1 aggiunto, 2 tolto, 3 pieno, 5/6 annullato, 9 elenco sostituito, 0 niente) |
| 3806 | cue selezionato (1..n) |
| 3807 | numero di cue |
| 3810 | numero di tempi nell'elenco (comando 5) |
| 3811–3874 | tempi in secondi |

Le celle per FX (`base+0..71`) restano quelle della 2.4: 72 celle per FX, mai oltre `+71`.

## Più Carver nello stesso progetto

`#HSC` vale per tutti i Carver. Se un giorno servono cue diversi per Carver diversi, si userà
`#HSC <nome traccia>` (da decidere con Paolo quando servirà).

## Da verificare prima di scrivere l'helper

1. ~~Render offline~~: verificato da Paolo il 2026-10-05.
2. Ripple "tutte le tracce" sposta i marker; ripple "per traccia" no. Va scritto nell'help.
3. Tempo di reazione: con l'helper ogni 0,25 s, un marker spostato durante il Play vale dal giro dopo.

## Test

`gobbo_ricerca_battuta/test/test_hsc_sync.lua`: la logica di confronto (istantanea, marker, Carver)
come funzione pura, con i casi: marker spostato, marker cancellato, cue aggiunto dal Carver, conflitto,
migrazione, 64 cue, cue a 4 ms l'uno dall'altro.
