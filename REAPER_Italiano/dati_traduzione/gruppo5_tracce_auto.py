# gruppo5_tracce_auto.py — Traduzioni overlay spiegazioni: Tracce di default, Automazioni, Item di automazione, Inviluppi, Colori inviluppi (76 voci)

TRADUZIONI_G5 = {
    # [prefs_trackdefs_help]
    "Volume envelopes can be scaled by amplitude (half as high is half as loud), or by the track fader scale (envelope height corresponds to the track fader).":
        "Gli inviluppi di volume possono essere scalati per ampiezza (metà altezza corrisponde a metà volume) o secondo la scala del fader di traccia.",
    "Changing scaling for an existing envelope may change the sound, because changes on the track fader are not linearly equivalent to changes in amplitude.":
        "Cambiare la scala di un inviluppo esistente può alterare il suono, poiché le variazioni del fader non sono linearmente equivalenti a quelle dell'ampiezza.",
    "The default fader gain for newly created tracks. The factory default is +0dB":
        "Guadagno predefinito del fader per le nuove tracce (valore di fabbrica: +0 dB).",
    "When enabled, new tracks will be visible in the mixer.":
        "Quando abilitato, le nuove tracce saranno visibili nel mixer.",
    "When enabled, new tracks created within a folder will send audio and MIDI to the folder parent track.":
        "Quando abilitato, le nuove tracce create dentro una cartella invieranno audio e MIDI alla traccia genitore della cartella.",
    "Certain track envelopes may be shown automatically for new tracks.":
        "Determina quali inviluppi di traccia mostrare automaticamente alla creazione di nuove tracce.",
    "Automatically show volume envelopes for new tracks.":
        "Mostra automaticamente l'inviluppo di volume per le nuove tracce.",
    "Automatically show pan envelopes for new tracks.":
        "Mostra automaticamente l'inviluppo di panorama (pan) per le nuove tracce.",
    "Automatically show pre-FX volume envelopes for new tracks.":
        "Mostra automaticamente l'inviluppo di volume pre-FX per le nuove tracce.",
    "Automatically show pre-FX pan envelopes for new tracks.":
        "Mostra automaticamente l'inviluppo di pan pre-FX per le nuove tracce.",
    "Default point shape for new track envelopes.":
        "Forma del punto predefinita per i nuovi inviluppi di traccia.",
    "The default automation mode for new tracks.  The factory default is Trim/Read Mode.":
        "Modalità di automazione predefinita per le nuove tracce (valore di fabbrica: Modalità Trim/Read).",
    "Default track height in new projects. This is also set via File/Project Settings/Save as default project settings.":
        "Altezza predefinita delle tracce nei nuovi progetti (impostabile anche da File/Impostazioni progetto/Salva come impostazioni predefinite).",
    "When enabled, new track envelopes will be automatically armed for recording automation.":
        "Quando abilitato, i nuovi inviluppi di traccia vengono armati automaticamente per la registrazione dell'automazione.",
    "Automatically enable free item positioning for new tracks.":
        "Abilita automaticamente il posizionamento libero degli item (Free Item Positioning) sulle nuove tracce.",
    "Automatically enabled fixed item lanes for new tracks.":
        "Abilita automaticamente le corsie fisse (Fixed Item Lanes) sulle nuove tracce.",
    "New fixed lane tracks can have small lanes (all lanes fit within a normal track height), or big lanes (each lane is the height of a track).":
        "Le tracce a corsie fisse possono avere corsie compatte (tutte raggruppate nell'altezza standard) o estese (ogni corsia ha l'altezza di una traccia).",
    "Automatically record-arm new tracks.":
        "Arma automaticamente per la registrazione le nuove tracce.",
    "Default record settings for new tracks.":
        "Impostazioni di registrazione predefinite per le nuove tracce.",
    "Default gain for new track-to-track sends.":
        "Guadagno predefinito per le nuove mandate da traccia a traccia.",
    "Default gain for new hardware outputs.":
        "Guadagno predefinito per le nuove uscite hardware.",
    "Default send type for new sends and hardware outputs.":
        "Tipo di mandata predefinito per nuove mandate e uscite hardware (Post-Fader, Pre-Fader, ecc.).",
    "When enabled, new sends will send MIDI from the source track.":
        "Quando abilitato, le nuove mandate trasmettono i dati MIDI dalla traccia sorgente.",
    "When enabled, new sends will send audio from the source track.":
        "Quando abilitato, le nuove mandate trasmettono l'audio dalla traccia sorgente.",
    "Track meter defaults for newly created tracks. Existing tracks in existing projects will not be affected.":
        "Impostazioni predefinite dei meter per le nuove tracce (le tracce esistenti nei progetti attuali non verranno modificate).",

    # [prefs_auto_help]
    "When the track automation mode is touch, latch, or write, moving any track control or FX knob will create an automation envelope for it.":
        "Nelle modalità Touch, Latch o Write, muovere qualsiasi controllo di traccia o manopola FX crea automaticamente il relativo inviluppo di automazione.",
    "After recording an automation write pass, automation can automatically switch to a different mode (to avoid overwriting just-written automation).":
        "Dopo una passata di scrittura automazione, il sistema può passare a un'altra modalità (per evitare di sovrascrivere i dati appena registrati).",
    "The time it takes for the envelope to return to its previous or default value after the end of recording an automation pass.":
        "Tempo impiegato dall'inviluppo per tornare al valore precedente o predefinito al termine di una passata di automazione.",
    "The transition time applied when writing envelope ranges via actions.":
        "Tempo di transizione applicato quando si scrivono intervalli di inviluppo tramite azioni.",
    "If (default) enabled, hidden envelopes in read mode will update their relevant track controls.":
        "Se abilitato (predefinito), gli inviluppi nascosti in modalità Read aggiornano comunque i relativi controlli di traccia.",
    "If enabled, allows writing automation to armed but hidden envelopes (which is otherwise not supported).":
        "Se abilitato, consente di registrare automazione su inviluppi armati anche se nascosti alla vista (altrimenti non consentito).",
    "If a track fader is at -X dB, the track volume envelopes can be created at -X dB or +0 dB. In both cases the track output will be automatically adjusted.":
        "Se il fader è a -X dB, l'inviluppo di volume può essere creato a -X dB oppure a +0 dB; in entrambi i casi l'uscita complessiva viene regolata automaticamente.",
    "If hiding an envelope and the envelope only has a single point, apply that value back to the trim/parameter and clear the envelope contents.":
        "Nascondendo un inviluppo con un solo punto, riapplica quel valore al trim/parametro statico e azzera il contenuto dell'inviluppo.",
    "Automatically reduce (prune) redundant points when recording or drawing automation. To reduce points afterwards, use the envelope right-click menu.":
        "Riduce automaticamente i punti ridondanti durante la registrazione o il disegno dell'automazione (per ridurli dopo, usa il menu contestuale dell'inviluppo).",
    "When recording automation while playback is stopped, choose whether to add points before/after edit position.":
        "Durante la registrazione di automazione a riproduzione ferma, stabilisce se aggiungere punti prima o dopo la posizione di modifica.",
    "When recording automation, choose whether to record at the processing position (the default, what you hear), or the playback position.":
        "Durante la registrazione dell'automazione, stabilisce se registrare alla posizione di elaborazione (predefinita, ciò che ascolti) o di riproduzione.",
    "If enabled, latches will be reset on looped playback/recording.":
        "Se abilitato, lo stato di aggancio (latch) viene reimpostato a ogni ciclo di loop in riproduzione o registrazione.",
    "Causes all track envelope points to be deselected when clicking an empty area of the arrange view.":
        "Deseleziona tutti i punti degli inviluppi di traccia facendo clic su un'area vuota della vista Arrange.",
    "Causes all take envelope points to be deselected when clicking an empty area of the arrange view.":
        "Deseleziona tutti i punti degli inviluppi dei take facendo clic su un'area vuota della vista Arrange.",
    "Causes all take envelope points to be deselected for a given item when an area of that item is clicked.":
        "Deseleziona tutti i punti degli inviluppi di take di un item facendo clic su un'area dell'item stesso.",
    "If recording automation and multiple matching envelopes are armed, control which envelope is modified.":
        "Se sono armati più inviluppi corrispondenti durante la registrazione, definisce quale inviluppo viene effettivamente modificato.",
    "If enabled, latches will not be automatically reset when in latch/write modes, and will need to be manually reset.":
        "Se abilitato, gli agganci (latch) non vengono reimpostati automaticamente in modalità Latch/Write e richiedono un reset manuale.",

    # [prefs_auto_items_help]
    "Like media items, automation items can be looped or unlooped by default.":
        "Come gli item multimediali, gli item di automazione possono essere impostati come ciclici (loop) o non ciclici per impostazione predefinita.",
    "By default, each instance of a pooled automation item has a separate baseline and amplitude setting.":
        "Per impostazione predefinita, ciascuna istanza di un item di automazione collegato (pool) mantiene regolazioni indipendenti di ampiezza e linea di base.",
    "Create new automation items rather than recording directly to the envelopes.":
        "Crea nuovi item di automazione anziché registrare direttamente sui punti dell'inviluppo.",
    "Record to existing non-selected automation items rather than creating new items.":
        "Registra all'interno degli item di automazione non selezionati esistenti anziché creare nuovi item.",
    "By default, copy/pasting automation items will not create pooled copies.":
        "Per impostazione predefinita, copiare e incollare item di automazione non crea copie collegate (pool).",
    "By default, when automation items are copied or split because of a track/media item/razor edit, pooled copies of the automation items will be created.":
        "Per impostazione predefinita, quando gli item di automazione vengono copiati o divisi da modifiche razor o di traccia, si creano copie collegate (pool).",
    "Editing automation item position or edges to overlap existing automation items can either play both items together, or trim content from the existing items.":
        "Far sovrapporre item di automazione può sommare entrambi gli item oppure rifilare il contenuto di quelli sottostanti.",
    "Automation items can transition at the start and end to avoid abrupt changes in envelope value.":
        "Gli item di automazione possono includere transizioni morbide all'inizio e alla fine per evitare salti bruschi di valore.",
    "Automation items will be automatically assigned a user-editable label. The envelope name can be automatically appended to this label.":
        "Agli item di automazione viene assegnata un'etichetta modificabile; il nome dell'inviluppo può essere accodato automaticamente all'etichetta.",

    # [prefs_env_help]
    "Display newly created automation envelopes in separate lanes, as opposed to drawing the envelope over the media lane.":
        "Mostra i nuovi inviluppi di automazione in corsie separate, anziché disegnarli sopra la corsia dei file multimediali.",
    "Envelopes are not normally drawn overlaid over one another. When drawing envelopes over media, overlay them if they would otherwise be too small.":
        "Gli inviluppi di norma non si sovrappongono. Se disegnati sopra i media, sovrapponili se lo spazio verticale risulta troppo ridotto.",
    "When activating an envelope in the track envelopes dialog or via menu selection, select the envelope after activation.":
        "Quando si attiva un inviluppo nella finestra inviluppi o dal menu, seleziona l'inviluppo subito dopo l'attivazione.",
    "Selecting a different envelope via the envelope lane control panel menu will either hide the old envelope or move it to the media lane.":
        "Selezionando un altro inviluppo dal menu del pannello della corsia, il precedente viene nascosto o spostato sulla corsia dei media.",
    "Decibel range of volume envelopes, from the bottom to the top of the envelope.":
        "Escursione in decibel (dB) degli inviluppi di volume, dalla base alla sommità della corsia dell'inviluppo.",
    "The default display range of per-take pitch envelopes. A value of 3 means the envelope range is -3 to +3 semitones. This can be overridden per-project.":
        "Intervallo di visualizzazione predefinito per gli inviluppi di intonazione (pitch) per-take (es. 3 imposta un intervallo da -3 a +3 semitoni; modificabile per progetto).",
    "Per-take pitch envelope points can be snapped to semitones, or fractional semitones.":
        "I punti dell'inviluppo di intonazione per-take possono agganciarsi a semitoni interi o a frazioni di semitono.",
    "Transition time between envelope points that are automatically added when moving the lane slider with a time selection, moving media items, etc.":
        "Tempo di transizione tra punti di inviluppo inseriti automaticamente muovendo il cursore con una selezione temporale attiva, spostando item, ecc.",
    "When mouse modifier preferences are set to insert an envelope point, clicking an inactive envelope can just select the envelope, or insert a point.":
        "Se i modificatori mouse sono impostati per inserire un punto, fare clic su un inviluppo inattivo può limitarsi a selezionarlo o inserire subito il punto.",
    "When editing a single envelope point with the mouse, the edit can be constrained to the the space between adjacent envelope points.":
        "Durante la modifica di un punto di inviluppo con il mouse, il movimento può essere vincolato allo spazio compreso tra i punti adiacenti.",
    "When moving media items across tracks, make sure all envelopes that are modified are made visible so that you are aware of the changes being made.":
        "Spostando item multimediali tra tracce diverse, rende visibili tutti gli inviluppi modificati per monitorare con chiarezza le variazioni.",
    "Envelope point selection can follow time selection for the currently active envelope.":
        "La selezione dei punti di inviluppo può seguire automaticamente la selezione temporale per l'inviluppo attivo.",
    "Moving or copying items can automatically create edge points for envelopes, preserving the existing envelope shape around the edits.":
        "Spostare o copiare item può generare automaticamente punti di bordo negli inviluppi, preservando la forma dell'automazione circostante.",
    "Moving or copying multiple envelope points can automatically create edge points, to preserve the existing envelope shape around the edits.":
        "Spostare o copiare più punti di inviluppo può creare automaticamente punti di bordo per mantenere intatta la curva dell'automazione adiacente.",
    "Ripple editing or inserting time can automatically create edge points, to preserve the existing envelope shape.":
        "L'editing ripple o l'inserimento di tempo nel progetto può creare automaticamente punti di bordo per preservare la forma degli inviluppi.",
    "The default display range for the tempo map envelope. This can be overridden per-project.":
        "Intervallo di visualizzazione predefinito per l'inviluppo della mappa del tempo (tempo map; modificabile per singolo progetto).",
    "The tempo map envelope points can be snapped to whole beats per minute, or fractional beats per minute.":
        "I punti dell'inviluppo della mappa del tempo possono agganciarsi a BPM interi o a frazioni di BPM.",
    "Relative mouse edits provide more Y-axis resolution at the expense of envelope points not following the mouse pointer.":
        "La modifica relativa con il mouse offre maggiore risoluzione verticale sull'asse Y, a discapito dell'allineamento visivo col puntatore.",
    "When editing fader-scaled volume envelopes, one vertical pixel of mouse movement translates to 0.2dB of gain (or 1dB when below -60dB).":
        "Negli inviluppi di volume su scala fader, un pixel verticale di movimento del mouse equivale a 0,2 dB di guadagno (o 1 dB sotto i -60 dB).",
    "When editing envelopes that are not fader-scaled volume envelopes, one vertical pixel of mouse movement translates to 0.5% of value adjustment.":
        "Negli inviluppi non scalati sul fader, un pixel verticale di movimento del mouse equivale a una regolazione dello 0,5% del valore.",

    # [prefs_envcolor_help]
    "Override colors for envelopes based on their name. The matching logic is similar to search/filter in REAPER, and the first match found will be used.":
        "Personalizza i colori degli inviluppi in base al loro nome. Il criterio di corrispondenza usa i filtri di REAPER e applica la prima regola trovata.",
    "Adds a new rule for envelope color selection.":
        "Aggiunge una nuova regola per l'assegnazione del colore dell'inviluppo.",
    "Removes any selected rules.":
        "Rimuove le regole selezionate.",
    "Exports all envelope color overrides to a .ReaperEnvColorList file.":
        "Esporta tutte le regole dei colori degli inviluppi in un file .ReaperEnvColorList.",
    "Adds envelope color overrides from a .ReaperEnvColorList file.":
        "Importa regole per i colori degli inviluppi da un file .ReaperEnvColorList."
}
