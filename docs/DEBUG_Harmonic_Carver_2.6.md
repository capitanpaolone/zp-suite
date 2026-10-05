# ZP Harmonic Space Carver 2.6.1 + Cue Navigator 1.6 — revisione prima della pubblicazione

Revisione del 2026-10-05 (Claude, Code), richiesta da Paolo ("un debuggone serio").
Codice letto: `ZP Voce/ZP Harmonic Space Carver.jsfx` (2.6.1), `ZP Harmonic Space Carver Cue Navigator.lua` (1.6),
le sei azioni `ZP HSC ...`. Nessuna correzione fatta in questa revisione: solo l'elenco.

Legenda: **A** = da correggere prima di pubblicare, **B** = importante, **C** = da verificare in REAPER, **D** = piccolo.

## A — da correggere prima di pubblicare

1. **Progetto aperto nella stessa scheda: i cue di un progetto vecchio possono essere cancellati.**
   L'helper riconosce il cambio di progetto solo dal puntatore della scheda (`EnumProjects(-1)`). Se chiudi
   un progetto e ne apri un altro nella stessa scheda, il puntatore probabilmente resta lo stesso: l'helper
   tiene l'istantanea del progetto precedente. Se il progetto nuovo ha cue nel Carver ma non ha ancora
   marker `#HSC` (progetti fatti prima della 2.6), il confronto vede "marker spariti" e manda al Carver un
   elenco vuoto: **cue cancellati**. Le ancore del progetto precedente verrebbero applicate ai marker con gli
   stessi numeri (cue rossi a caso).
   Correzione: riconoscere il progetto anche dal nome del file (`EnumProjects(-1)` restituisce anche il
   percorso) e azzerare istantanee e ancore quando cambia.

2. **Cancellare tutti i marker cancella tutti i cue.** "Il marker comanda": un'azione che toglie tutti i
   marker (di REAPER o di altri script) svuota anche il Carver. Ctrl+Z li rimette, ma il rischio e' alto.
   Correzione: se in un colpo solo spariscono tutti i `#HSC` (da 3 in su), l'helper non svuota il Carver,
   rimette i marker e avvisa ("Ctrl+Z se volevi cancellarli" oppure CLEAR ALL dal Carver).

3. **Il tasto Riallinea puo' ripartire da solo.** La richiesta resta in ExtState: se l'helper viene
   riavviato, la rilegge come nuova e riallinea tutti i cue rossi senza che tu l'abbia chiesto.
   Correzione: l'helper cancella la richiesta dopo averla eseguita e, all'avvio, ignora quella vecchia.

4. **Tasti premuti due volte di fila.** Le azioni `ZP HSC Cue - ...` restano attive circa 2 secondi (per far
   sparire il suggerimento). Se ripremi il tasto prima, REAPER chiede "lo script e' gia' in esecuzione".
   Correzione: `reaper.set_action_options(3)`, cosi' la nuova pressione chiude la precedente e riparte.

5. **Installazione con ReaPack.** Helper e azioni oggi sono copiati a mano in `Scripts/ZP Suite/`, e
   l'helper parte all'avvio da li'. ReaPack li installera' in un'altra cartella: dopo il primo
   aggiornamento all'avvio partirebbe ancora la copia vecchia, e restano doppioni nella lista azioni.
   Correzione: decidere la cartella, spostare l'avvio sulla copia di ReaPack, togliere le copie a mano.
   Prima del merge: controllo dell'indice (`reapack-index --check`, che su questo Mac non e' installato)
   con i sei script nuovi.

## B — importanti

6. **Min Duck = Max Duck nei progetti vecchi: il VCA e' fisso.** La forbice ha riprodotto il suono di
   prima (Floor oltre Max Red), quindi nel progetto dei Guardiani Min = Max = -16,5 dB: con la voce la
   musica scende sempre di 16,5 dB e Ceiling e Prio non fanno niente. Non e' un errore di calcolo, ma
   non si vede. Correzione: avviso nel blocco VCA ("Min = Max: VCA fisso, Ceiling e Prio fermi") e
   decisione tua sui valori da usare nei progetti in corso.

7. **I cue rossi scattano lo stesso, anche in render.** Un cue fuori posto fa rientrare la musica nel
   punto sbagliato. Da decidere: lasciarli attivi con un avviso forte prima del render, oppure
   sospenderli finche' non li riallinei o li tieni.

8. **Due "annulla" che si pestano i piedi.** L'UNDO del Carver ha una memoria sua; Ctrl+Z di REAPER
   un'altra. Dopo che l'helper ha cambiato l'elenco (marker spostati), l'UNDO del Carver puo' rimettere
   un cue in un punto vecchio. Proposta: con l'helper attivo, UNDO del Carver = Ctrl+Z di REAPER (o
   sparisce), e l'UNDO del Carver resta solo senza helper.

9. **Helper spento: il Carver non lo dice.** Con SALTA attivo e l'helper fermo, < e > non fanno niente e
   nessuno lo segnala; i cue rossi restano rossi anche quando nessuno li controlla piu'. Il Carver sa
   gia' se l'helper e' vivo (il controllo del routing arriva ogni secondo). Correzione: spia "HELPER" nella
   barra cue, maschere dei rossi ignorate se l'helper e' fermo.

10. **Numeri dei marker come chiave delle ancore.** Le ancore sono salvate per numero di marker. Se rinumeri
    i marker (azione di REAPER o altri script), le ancore si perdono in silenzio: i cue rossi tornano
    ciano e le ancore si rifanno sulla posizione attuale. Correzione: chiave piu' stabile (posizione +
    numero, o GUID del marker se REAPER lo espone) e avviso quando la chiave non torna.

11. **Progetti vecchi in SIMPLE o in VOCAL suonano diversi.** Simple non e' piu' un motore a parte: un
    progetto lasciato in Simple ora usa i valori Advanced salvati (magari mai toccati). VOCAL non
    esclude piu' Max Red. Hai detto che i preset vecchi non contano: resta da controllare i progetti in
    corso prima di riaprirli in consegna.

## C — da verificare in REAPER (non verificabili fuori)

12. **Preascolto OFF alla riapertura.** Lo azzero in `@init`; se REAPER ricarica i parametri dopo
    `@init`, il preascolto resta acceso. Prova: Preascolto CARV, salva, chiudi, riapri.
13. **Anticipo (lookahead) e PDC.** `pdc_delay` e' impostato in `@block`: va visto che REAPER compensi
    davvero (render allineato con Anticipo a 20 ms) e che cambiare l'Anticipo in Play non dia un click
    fastidioso (il buffer si azzera).
14. **Piu' progetti aperti in schede.** L'indirizzo gmem del Carver dipende dal numero di traccia, non dal
    progetto: due Carver sulla stessa traccia in due schede usano le stesse celle. Con "Run background
    projects" spento non succede niente; se e' acceso, i due Carver si sovrascrivono e l'helper vedrebbe
    cue che cambiano di continuo. Da controllare l'impostazione; se serve, l'helper lavora solo sui
    Carver del progetto attivo e il Carver scrive solo se il suo progetto e' quello attivo.
15. **Prestazioni su progetti lunghi.** L'helper rilegge tutti gli item voce 4 volte al secondo. Con
    centinaia di item va misurato; correzione semplice: rileggere solo quando cambia lo stato del
    progetto (`GetProjectStateChangeCount`).

## D — piccoli

16. Testo "v2.5" ancora nell'intestazione `about` del JSFX e in `// Versione:` (il file e' 2.6.1).
17. Azioni da tastiera e helper scrivono nella stessa casella gmem: se premi un tasto nell'istante in cui
    l'helper manda un elenco, uno dei due comandi si perde (raro; l'helper riprova, il tasto no).
18. Cambiare l'Anticipo azzera il buffer del ritardo: piccolo buco nell'audio in quel momento.
19. Due marker `#HSC` con lo stesso numero (possibile copiando marker): colore e ancora vanno al primo.
20. La Forbice Min/Max scrive il parametro anche se e' in automazione: con una corsia di Min o Max Duck
    in scrittura si puo' sporcare l'automazione.

## Ordine proposto

1, 3, 4 (sicurezza dei dati e dei tasti) → 2 → 9 → 6 → 8 → 10 → prove C in REAPER → 7 (decisione) →
16-20 → 5 (pubblicazione).

## Esito (2026-10-05, Carver 2.6.2 + helper 1.7 + azioni 1.1)

Decisioni di Paolo e cosa e' stato fatto:

- 1 progetto nella stessa scheda: progetto riconosciuto anche dal file; e al primo giro comanda il Carver
  (mai cancellare cue da li'). **Fatto.**
- 2 cancellazione dei marker: regola nuova di Paolo, "i #HSC non si toccano fuori dal Carver, al massimo si
  spostano": cancellati a mano tornano, aggiunti a mano spariscono, rinumerati restano. **Fatto.**
- 3 Riallinea: la richiesta si cancella dopo l'uso e quella vecchia si ignora all'avvio. **Fatto.**
- 4 tasti ripremuti: `set_action_options(3)` in tutte le azioni (1.1), nessun dialogo. **Fatto.**
- 5 installazione: file nella cartella di ReaPack `Scripts/ZP Suite/ZP Voce/`; nella vecchia posizione
  restano tre rimandi (helper avviato da SWS, Mostra tracce voce, Riallinea su Ctrl+\) per non cambiare
  scorciatoie e avvio; le quattro copie vecchie non registrate spostate in un backup. Un solo helper alla
  volta (l'ultimo avviato prende il posto). **Fatto.** Resta: `reapack-index --check` prima del merge.
- 6 Min = Max: progetti salvati prima della 2.6.2 con Min = Max (o Min piu' profondo) -> Min Duck -3 dB;
  avviso "Min = Max: VCA fisso" nel blocco VCA. **Fatto.**
- 7 cue rossi: restano attivi, avviso rosso lampeggiante non bloccante in testata + messaggio OSARA quando
  aumentano. **Fatto.**
- 8 due annulla: con la regola nuova l'UNDO del Carver annulla aggiunte e rimozioni, Ctrl+Z gli spostamenti.
- 9 helper spento: spia "HELPER SPENTO" nella barra cue; le maschere dei rossi si ignorano se l'helper e' fermo. **Fatto.**
- 10 rinumerazione: riconosciuta (stessa posizione, numero nuovo), ancore conservate. **Fatto.**
- 12 preascolto: Paolo ha verificato che NON si spegneva (lo azzeravo in @init, prima che REAPER ricarichi i
  parametri). Ora lo spegne il primo @block dopo il caricamento (segnale da @serialize). **Da riprovare.**
- 15 prestazioni: le ancore si ricalcolano solo quando cambia lo stato del progetto (o ogni 2 s). **Fatto.**
- Marker #HSC in lane 4 (proposta di Paolo): `SetRegionOrMarkerInfo_Value(..., "I_LANENUMBER", 3)`. **Da provare in REAPER.**
- Aperti: 11 (progetti vecchi in Simple/Vocal), 13 (PDC dell'Anticipo), 14 (Run background projects),
  16-20 piccoli (16 fatto: testi a v2.6).

Test: test_hsc_sync.lua riscritto per le regole nuove (in run_all); simulazione completa dell'helper 1.7 con
REAPER finto, 20 passaggi ok (progetto vecchio, spostamento, ADD, marker cancellato/aggiunto/tutti cancellati,
rinumerati, CLEAR ALL, cue rosso, Riallinea, altro progetto nella stessa scheda, secondo helper, richiesta vecchia).

