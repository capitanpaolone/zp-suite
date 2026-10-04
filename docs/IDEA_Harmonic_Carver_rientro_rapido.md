# ZP Harmonic Space Carver — idea: pulsante "rientro rapido" legato alla timeline

Richiesta di Paolo, 2026-10-04. Stato: **da progettare, nessun codice**. Plugin: `ZP Voce/ZP Harmonic Space Carver.jsfx` (v2.4.1).

## Cosa vuole Paolo
Un pulsante nel plugin. Quando lo clicco, in quel punto della timeline il plugin
**memorizza un rientro più veloce del volume che sta gestendo** (la musica che torna su
quando la voce finisce). Così non devo andare a cercare nelle automazioni **tre lane diverse**
e scriverle a mano.

## Le tre lane di oggi (parametri che governano il rientro)
- `slider27` VCA Hold (ms) — quanto resta giù dopo la fine della voce
- `slider28` VCA Release (ms) — quanto ci mette a tornare su
- `slider18` Carver Release (ms) — rientro dello scavo multibanda
(da confermare con Paolo: forse conta anche `slider50` VCA Return Mode, Standard/Gradual)

## Ipotesi di progetto (da decidere con Paolo)
1. **Automazione interna**: il plugin tiene una lista di "punti di rientro rapido" (tempo del
   progetto) salvata con `@serialize`; durante la riproduzione legge la posizione
   (`play_position`) e, vicino a un punto, usa per quel rientro Hold/Release più corti.
   Niente lane di REAPER da gestire.
2. **Oppure** il pulsante scrive davvero i tre punti nelle tre lane di automazione
   (serve uno script Lua o l'automazione del JSFX con `slider_automate`): più trasparente
   in REAPER, ma torna il problema delle tre lane.
3. Da chiarire:
   - "più veloce" di quanto: un preset fisso (es. Hold 0, Release 1/3) o una manopola
     "Rientro rapido" che regola insieme le tre?
   - vale per il singolo rientro successivo al clic, o per un tratto (da/a)?
   - come si vedono e si cancellano i punti salvati (lista, marker nel grafico)?
   - comportamento in render offline (il punto deve funzionare anche senza play live).
   - accessibilità: pulsante e lista dei punti raggiungibili con OSARA (vista JSFX).

## Prossimo passo
Paolo completa o corregge questa memoria; poi proposta grafica e prova su una sessione vera.
