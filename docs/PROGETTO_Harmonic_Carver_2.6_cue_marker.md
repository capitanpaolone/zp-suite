# ZP Harmonic Space Carver 2.6 — cue che seguono l'editing (marker `#HSC`)

Decisione di Paolo (2026-10-05): strada **B**. I cue nascono per evitare le automazioni, quindi
niente corsia di automazione: i cue diventano anche marker di servizio sul righello.

Stato: **fatto e collaudato da Paolo** (2026-10-05; RIALLINEA e Ctrl+Z verificati): Carver 2.6.1 + helper Cue Navigator 1.6.
La parte del plugin è nella 2.5 (comando 5 "sostituisci elenco"). Render offline verificato da Paolo.
Test: `test_hsc_sync.lua` (logica pura, in run_all) e simulazione del giro completo con REAPER finto
(migrazione, ripple, ADD, marker cancellato, CLEAR ALL, undo, marker di testo ignorato, due Carver).

> **Regole attuali (2.6.2 e seguenti, decise da Paolo dopo la revisione).** Le sezioni qui sotto
> descrivono il primo progetto. Oggi: i cue si aggiungono e si tolgono **solo dal Carver**; i marker
> `#HSC` si possono solo spostare (un marker cancellato a mano torna, uno aggiunto a mano sparisce);
> marker in lane 4; le correzioni automatiche non creano punti di undo; ogni Carver ha un numero unico.
> Dettagli in `DEBUG_Harmonic_Carver_2.6.md`. Pubblicato con Carver 2.6.4 e helper 1.9.

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

## Helper Cue Navigator 1.4

Ogni 0,25 s, per ogni Carver trovato (stessa scansione della 1.2). Un comando alla volta nella
casella: l'istantanea si aggiorna solo dopo l'ack del Carver; se il Carver non risponde in 1 s si riprova.
Se la casella e' occupata da un'azione da tastiera, l'helper aspetta.

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

## Riferimento dei cue: l'audio della voce (Carver 2.6.1, helper 1.5-1.6)

Domanda di Paolo: con piu' podcast in timeline un taglio nel primo non deve spostare i cue del secondo;
i cue devono restare fermi e diventare rossi se perdono il riferimento. Scelta: il riferimento e' l'audio
della voce sotto il cue, non la timeline e non la regione.

- **Tracce voce** (1.5): quelle che arrivano ai pin delle fonti SC accese (invii, figlie del folder, a
  ritroso). Azione "ZP HSC - Mostra tracce voce" per vederle. Verificato da Paolo sul progetto dei Guardiani.
- **Ancora** (1.6): file della voce e punto nel file (`src = offs + (pos - item_pos) * rate`). Voce sotto il
  cue; se non c'e', quella finita da meno di 5 s; se no quella che parte entro 2 s; se no cue libero.
  Salvate nel progetto (`ProjExtState ZP_HSC/anchors`), per numero di marker.
- **Giudizio** a ogni giro: al suo posto (scarto <= 20 ms) ciano; marker spostato e audio fermo = trascinato
  a mano, nuova ancora; audio spostato (o sparito) e cue fermo = **rosso**. Ripple su tutte le tracce o
  regione spostata con il contenuto: audio e marker si muovono insieme, resta ciano.
- **Rosso**: marker `#HSC` rosso, punto rosso e "N FUORI POSTO" nel Carver (maschere in gmem nella zona
  libera della traccia: base traccia + 4032 + 2*fx). RIALLINEA (comando 6 sul canale GUI->helper) sposta
  il marker sulla voce; TIENI QUI (comando 7) ancora il cue dov'e'. Tasto "ZP HSC Cue - Riallinea"
  (ExtState ZP_HSC/req -> rep) riallinea tutti i rossi.
- Item diviso: il punto resta valido (stesso file, stessa mappatura). File usato piu' volte: vale
  l'occorrenza piu' vicina al cue.

