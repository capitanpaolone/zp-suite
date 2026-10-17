# gruppo4_editing.py — Traduzioni overlay spiegazioni: Editing, Comping, Blocco, Modifiche spettrali (45 voci)

TRADUZIONI_G4 = {
    # [prefs_edit_help]
    "Various options for moving the edit cursor (where playback will begin) after performing certain edits.":
        "Varie opzioni per posizionare il cursore di modifica (da cui partirà la riproduzione) dopo determinate operazioni di editing.",
    "The edit cursor (where playback will begin) moves to the start of the time selection when you change the time selection.":
        "Il cursore di modifica si sposta all'inizio della selezione temporale ogni volta che quest'ultima viene modificata.",
    "The edit cursor (where playback will begin) moves to the start of the razor edit when you create the razor edit or move it without contents.":
        "Il cursore di modifica si sposta all'inizio dell'area razor quando la crei o la sposti senza contenuti.",
    "The edit cursor (where playback will begin) moves to the mouse when pasting or inserting media items.":
        "Il cursore di modifica si sposta sulla posizione del mouse quando incolli o inserisci item multimediali.",
    "The edit cursor (where playback will begin) moves to start of the fixed lane comp area when you click the area.":
        "Il cursore di modifica si sposta all'inizio dell'area di comping a corsie fisse quando fai clic sull'area.",
    "The edit cursor (where playback will begin) moves to the end of newly recorded items when recording stops.":
        "Il cursore di modifica si sposta alla fine dei nuovi item registrati all'arresto della registrazione.",
    "Set the sensitivity of tab-to-transient and dynamic split. Lower sensitivity causes only the sharpest transients to be detected.":
        "Imposta la sensibilità della navigazione per transienti (Tab) e della divisione dinamica. Minore sensibilità rileverà solo i transienti più marcati.",
    "Tab-to-transient can ignore MIDI items, or consider MIDI notes as transients.":
        "La navigazione con Tab può ignorare gli item MIDI oppure considerare le note MIDI come transienti.",
    "Tab-to-transient can tab past media item edges, or consider media item edges as transients.":
        "La navigazione con Tab può superare i bordi degli item multimediali oppure considerarli come transienti.",
    "Media item edges between adjacent items can trim both items at once. This behavior can be restricted so both items are edited only if both are selected.":
        "I bordi tra due item adiacenti possono rifilare entrambi gli item contemporaneamente, oppure solo se entrambi sono selezionati.",
    "When creating a razor edit area, existing media item and envelope selection can be cleared, or preserved.":
        "Durante la creazione di un'area di modifica razor, la selezione esistente di item e inviluppi può essere azzerata o mantenuta.",
    "When auto-crossfades (toolbar button) are disabled, normally editing a crossfade will cause the fade-in and fade-out to separate.":
        "Quando la dissolvenza incrociata automatica (crossfade) è disattivata, la modifica manuale separa la dissolvenza in entrata da quella in uscita.",
    "Tracks that are automatically created when dragging media into empty space below the last track can be automatically deleted if not used.":
        "Le tracce create automaticamente trascinando media nello spazio vuoto sotto l'ultima traccia possono essere rimosse se non utilizzate.",
    "When using mouse modifiers like \\\"Move item contents\\\", the edit can be applied to only the take being edited, or to all takes in the same media item.":
        "Usando modificatori mouse come \"Sposta contenuto item\", la modifica può essere applicata solo al take modificato o a tutti i take dell'item.",
    "Actions to split, trim, or delete media items can affect all media items that intersect the edit cursor, if no media items are selected.":
        "Le azioni per dividere, rifilare o eliminare item possono agire su tutti gli item che intersecano il cursore se non vi sono item selezionati.",
    "Time selection and loop points can be linked, or unlinked so that they can be set or cleared independently.":
        "La selezione temporale e i punti di loop possono essere collegati tra loro oppure resi indipendenti.",
    "Loop points are cleared using the escape key, or optionally by single-clicking in the ruler/timeline area.":
        "I punti di loop vengono cancellati con il tasto Esc (Escape) o, a scelta, con un singolo clic nell'area del righello/timeline.",
    "The time selection is cleared using the escape key, or optionally whenever a mouse click in the arrange view moves the edit cursor.":
        "La selezione temporale si cancella con Esc o, a scelta, ogni volta che un clic nella vista Arrange sposta il cursore di modifica.",
    "When stretching a razor edit area edge that falls within an audio media item, either stretch markers can be added, or the item can be split.":
        "Allungando il bordo di un'area razor che cade dentro un item audio, è possibile inserire stretch marker oppure dividere l'item.",
    "Actions to normalize media items affect only the active take by default, but can affect all takes within the media item.":
        "Le azioni per normalizzare gli item agiscono solo sul take attivo per impostazione predefinita, ma possono estendersi a tutti i take dell'item.",
    "Actions like \\\"Sample edits: Set sample values to zero\\\" can automatically zoom in, to enable sample editing with the mouse if needed.":
        "Azioni come \"Modifica campioni: Imposta valori a zero\" possono eseguire automaticamente uno zoom per consentire la modifica con il mouse.",
    "Actions like \\\"Go to next marker\\\" or jumping via Jump To Time dialog can automatically select the region/marker that is navigated to.":
        "Azioni come \"Vai al marcatore successivo\" o salti temporali possono selezionare automaticamente la regione o il marcatore raggiunto.",
    "Take markers can be up-ranked or down-ranked. The maximum number of ranking levels is set here.":
        "I marcatori di take possono essere promossi o declassati di grado. Il numero massimo di livelli di classificazione si imposta qui.",
    "Actions to up-rank, down-rank, or cycle through rankings can either include or skip setting the take to have no ranking.":
        "Le azioni per promuovere, declassare o scorrere i gradi dei take possono includere o saltare lo stato 'nessun grado'.",
    "Constrain the mouse-edited time selection, loop, and razor edit length to a minimum pixel size.":
        "Imposta una dimensione minima in pixel per la selezione temporale, il loop e le modifiche razor effettuate con il mouse.",

    # [prefs_comping_help]
    "Editing item edges in the comping lane can force the corresponding source lane items to expand, to ensure the comp area stays in sync.":
        "La modifica dei bordi degli item nella corsia di comping può forzare l'espansione degli item nelle corsie sorgente, garantendo il sincronismo.",
    "Clicking empty track space in source lanes can either create an empty comp area, or do nothing.":
        "Facendo clic sullo spazio vuoto di una traccia nelle corsie sorgente è possibile creare un'area di comping vuota oppure non fare nulla.",
    "Comp area edge edits in source lanes can be constrained to the edges of media items, to prevent comping empty space.":
        "La modifica dei bordi dell'area di comping nelle corsie sorgente può essere vincolata ai bordi degli item per evitare di comporre silenzio.",
    "Changing the source lane for a comp area using an action like \\\"Fixed lane comp area: Move up\\\" can skip empty lanes, or not.":
        "Cambiare la corsia sorgente di un'area di comping tramite azioni come \"Area di comping corsie fisse: Sposta su\" può saltare le corsie vuote o includerle.",
    "Comping MIDI items can create pooled copies, so that edits to the MIDI notes/data in the source media items affect the comping lane.":
        "Il comping di item MIDI può creare copie collegate (pooled), così che le modifiche alle note o ai dati MIDI sorgente si riflettano nella corsia di comping.",

    # [prefs_locking_help]
    "By default, \\\"Item properties:\\\" actions and user edits in Media Item Properties dialog are applied to locked media items.":
        "Per impostazione predefinita, le azioni \"Proprietà item:\" e le modifiche nella finestra Proprietà item vengono applicate anche agli item bloccati.",
    "By default, locked media items can be copied during mouse edits or when running actions.":
        "Per impostazione predefinita, gli item multimediali bloccati possono essere duplicati tramite mouse o eseguendo azioni.",
    "By default, locked media items are affected by region editing and inserting/removing project time.":
        "Per impostazione predefinita, gli item bloccati sono influenzati dalla modifica delle regioni e dall'inserimento o rimozione di tempo nel progetto.",
    "How locked items behave in \\\"ripple edit all tracks\\\" and \\\"ripple edit per-track\\\" modes.":
        "Stabilisce il comportamento degli item bloccati nelle modalità 'Ripple edit su tutte le tracce' e 'Ripple edit su traccia singola'.",

    # [prefs_spectral_edits_help]
    "Default fade-in for new spectral edits, 100% is the first half of the edit region. The default is 0, no fade.":
        "Dissolvenza in entrata predefinita per le modifiche spettrali (100% copre la prima metà della regione modificata; predefinita 0, nessuna dissolvenza).",
    "Default fade-out for new spectral edits, 100% is the second half of the edit region. The default is 0, no fade.":
        "Dissolvenza in uscita predefinita per le modifiche spettrali (100% copre la seconda metà della regione modificata; predefinita 0, nessuna dissolvenza).",
    "Default low-frequency fade for new spectral edits, 100% is lowest half of the frequency range. The default is 0, no fade.":
        "Dissolvenza alle basse frequenze per nuove modifiche spettrali (100% copre la metà inferiore dello spettro selezionato; predefinita 0).",
    "Default high-frequency fade for new spectral edits, 100% is highest half of the frequency range. The default is 0, no fade.":
        "Dissolvenza alle alte frequenze per nuove modifiche spettrali (100% copre la metà superiore dello spettro selezionato; predefinita 0).",
    "Default gain for new spectral edits. The default is +0 dB (which does nothing).":
        "Guadagno predefinito per le nuove modifiche spettrali (predefinito +0 dB, nessuna variazione di livello).",
    "Default compression threshold for new spectral edits. If the compression ratio is set to 1:1, this threshold will have no effect.":
        "Soglia di compressione predefinita per le modifiche spettrali. Se il rapporto di compressione è 1:1, la soglia non ha alcun effetto.",
    "Default compression ratio for new spectral edits. The default is 1:1, which disables the per-band compressor.":
        "Rapporto di compressione predefinito per le modifiche spettrali (predefinito 1:1, che disabilita il compressore multibanda).",
    "Default gate threshold for new spectral edits. The default is -inf, which disables the per-band gate.":
        "Soglia del noise gate predefinita per le modifiche spettrali (predefinita -inf, che disabilita il gate multibanda).",
    "Default gate floor for new spectral edits. This allows an attenuated signal through when the gate is closed. The default is -inf.":
        "Floor del gate per le modifiche spettrali. Consente di far passare un segnale attenuato quando il gate è chiuso (predefinito -inf).",
    "If checked, new spectral edits will be soloed by default (which is often used to audition the area you have selected)":
        "Se selezionato, le nuove modifiche spettrali vengono messe in solo automaticamente (utile per preascoltare l'area isolata nel grafico).",
    "Sets the default FFT size for take spectral processors. The default is 1024, which offers a balance between temporal and frequency precision.":
        "Imposta la dimensione FFT predefinita per i processori spettrali dei take (predefinita: 1024, bilanciamento tra risoluzione temporale e in frequenza)."
}
