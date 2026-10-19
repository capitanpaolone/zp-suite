# gruppo7_midi_ui.py — Traduzioni overlay spiegazioni: MIDI, Dispositivi MIDI, Editor MIDI, Aspetto, TCP, Meter (121 voci)

TRADUZIONI_G7 = {
    # [prefs_midi_help]
    "By default, middle C (MIDI note 60) is labeled C4, A=440Hz (MIDI note 69) is A4. A display offset of -1 causes these notes to be labeled C3/A3, etc.":
        "Per impostazione predefinita, il Do centrale (nota MIDI 60) è indicato come C4 (La 440 Hz = A4). Un offset di -1 mostra le note come C3/A3 (standard italiano Do3/La3).",
    "Pooled (ghosted) MIDI source data can be converted to a separate editable media item (unpooled) by gluing the media item.":
        "I dati MIDI collegati in pool (ghost) possono essere convertiti in un item autonomo indipendente consolidando (glue) l'item multimediale.",
    "The default format for storing new MIDI items. In-project items allow more flexible editing, and can be exported as .MID files at any time.":
        "Formato predefinito per i nuovi item MIDI: gli item interni al progetto consentono modifiche più versatili ed esportabili in .MID in qualsiasi momento.",
    "New MIDI items will be stored as native REAPER data inside the project file (.RPP), which allows more flexible editing and preserves note selections.":
        "I nuovi item MIDI vengono salvati come dati nativi nel file di progetto (.RPP), offrendo modifiche flessibili e preservando le selezioni di note.",
    "New MIDI items will be stored as .MID files on disk, which is less flexible for editing but more portable.":
        "I nuovi item MIDI vengono salvati come file .MID su disco (meno flessibili per l'editing ma più facilmente scambiabili con altri software).",
    "Prompt for a filename when creating new items as .MID files (otherwise a unique but not very meaningful name will be used).":
        "Richiedi il nome file durante la creazione di item come file .MID (altrimenti viene generato un nome univoco predefinito).",
    "Imported MIDI files can be automatically converted to in-project items.":
        "I file MIDI importati possono essere convertiti automaticamente in item interni al progetto.",
    "Automatically convert imported MIDI files to in-project items, so that edits will not affect the source .MID file.":
        "Converti automaticamente i file MIDI importati in item interni al progetto, evitando che le modifiche alterino il file .MID sorgente su disco.",
    "Import MIDI files as references to the source .MID file, so that edits will alter the source file on disk.":
        "Importa i file MIDI come riferimenti al file .MID sorgente (le modifiche altereranno direttamente il file su disco).",
    "Multichannel MIDI files can be imported to a single track, or to separate tracks per channel.":
        "I file MIDI multicanale possono essere importati su una singola track o suddivisi su track separate per ciascun canale.",
    "Data resolution for new MIDI items. 960ppq is two ticks per millisecond at 120bpm, which is suitable for almost all purposes.":
        "Risoluzione temporale per i nuovi item MIDI (960 PPQ corrisponde a due tick per millisecondo a 120 BPM, ideale per quasi tutti gli utilizzi).",
    "When splitting a MIDI item, split the underlying MIDI data source if possible (inserting new note-ons/offs, and optionally CC/PC).":
        "Durante la divisione di un item MIDI, divide la sorgente dati inserendo i nuovi eventi Note-On/Note-Off e, a scelta, controller CC e Program Change.",
    "When splitting a MIDI data source, chase CC/PC values for the new items.":
        "Durante la divisione di una sorgente MIDI, insegue i valori CC/PC per mantenerli coerenti nei nuovi item generati.",
    "When importing a MIDI file, time signature change events can be snapped to whole measures (recommended).":
        "Durante l'importazione di file MIDI, aggancia i cambi di tempo metrico (metronomo) a misure intere (consigliato).",
    "When importing a MIDI file, tempo change events can be snapped to whole beats.":
        "Durante l'importazione di file MIDI, aggancia i cambi di tempo (BPM) a battiti interi.",
    "Export MIDI text events as Latin-1 (some international characters, maximum compatibility), UTF-8 (full character support), or 7-bit ASCII.":
        "Esporta gli eventi di testo MIDI in codifica Latin-1 (massima compatibilità), UTF-8 (supporto completo caratteri estesi) o ASCII a 7 bit.",
    "Prompt to import tempo map when importing MIDI files with simple tempo information (hold control when importing to temporarily toggle).":
        "Chiedi se importare la mappa del tempo per file MIDI con informazioni di tempo (tieni premuto Ctrl/Cmd all'importazione per invertire la scelta).",
    "When importing a single-channel MIDI file that contains lyrics or other meta-events, obey the user preference for importing multichannel MIDI.":
        "All'importazione di un file MIDI monocanale contenente testi o meta-eventi, rispetta le preferenze di importazione per file multicanale.",
    "Timeout touch-replace recording when a CC/pitch message hasn't been sent in this many millseconds":
        "Interrompi la registrazione touch-replace quando non viene ricevuto alcun messaggio CC o Pitch Bend per questo intervallo in millisecondi.",
    "Default PPQ for non-square CC segment interpolation -- this is configurable per-MIDI item; new items are created with this value.":
        "Risoluzione PPQ predefinita per l'interpolazione di segmenti CC non rettangolari (configurabile per item; i nuovi item usano questo valore).",

    # [prefs_mididev_help]
    "MIDI input devices may be enabled for track inputs or for control messages (which can be assigned in the actions list), or both.":
        "Le periferiche di ingresso MIDI possono essere abilitate come ingressi track, per messaggi di controllo (assegnabili alle azioni) o per entrambi.",
    "Closes and reopens all MIDI devices, and rescans for new devices if possible.":
        "Chiude e riapre tutte le periferiche MIDI, eseguendo una nuova scansione delle periferiche collegate.",
    "Allows creating a new virtual MIDI device (e.g. loopback or joystick).":
        "Consente di creare una nuova periferica MIDI virtuale (es. loopback o joystick).",
    "Filter visible list of MIDI input devices - can use device name and/or <avail> <enabled> <all> <control> <ignored>":
        "Filtra l'elenco delle periferiche MIDI in ingresso (usa il nome della periferica o tag come <avail>, <enabled>, <all>, <control>, <ignored>).",
    "MIDI output devices may be enabled as track outputs, optionally with MIDI clock and SPP sending. Reset messages can also be disabled.":
        "Le periferiche di uscita MIDI possono essere abilitate per le track, con invio opzionale di MIDI Clock e SPP; è possibile disabilitare i messaggi di reset.",
    "This will send MIDI all-notes-off and all-sound-off messages to reset.":
        "Invia i messaggi MIDI All-Notes-Off e All-Sound-Off per reimpostare i sintetizzatori.",
    "This will send MIDI Pitch and Sustain (CC#64) reset messages to reset.":
        "Invia messaggi di reset per Pitch Bend e Pedale Sustain (CC #64).",
    "Enable this to drive all MIDI hardware from a single thread, which isn't ideal for performance but may be more compatible with some hardware.":
        "Abilita la gestione dell'hardware MIDI da un singolo thread (riduce leggermente le prestazioni ma migliora la stabilità con alcune periferiche).",
    "Send reset messages (according to by-preference) on playback start or when seeking playback.":
        "Invia messaggi di reset MIDI all'avvio della riproduzione o durante il posizionamento temporale (seek).",
    "Send reset messages (according to by-preference) on stop or when seeking while stopped.":
        "Invia messaggi di reset MIDI all'arresto della riproduzione o durante il seek a trasporto fermo.",
    "Filter visible list of MIDI output devices - can use device name and/or <avail> <enabled> <ll> <noreset> <clock> <nospp> <ignored>":
        "Filtra l'elenco delle uscite MIDI (usa il nome o tag come <avail>, <enabled>, <noreset>, <clock>, <nospp>, <ignored>).",

    # [prefs_midiedit_help]
    "Show a brief color flash on the MIDI editor keyboard when the track receives MIDI note-on input.":
        "Mostra un lampeggio colorato sui tasti della tastiera dell'editor MIDI alla ricezione di note Note-On.",
    "Show horizontal grid lines in CC lanes in the MIDI editor, height permitting.":
        "Mostra linee orizzontali di griglia nelle corsie CC dell'editor MIDI (se l'altezza verticale della corsia lo consente).",
    "Set the MIDI event density when drawing in CC lanes with the mouse.":
        "Imposta la densità di generazione degli eventi MIDI durante il disegno a mano libera nelle corsie CC con il mouse.",
    "CC event drawing density will be greater when the view is zoomed in, and lower when zoomed out.":
        "La densità degli eventi CC generati sarà maggiore con zoom ravvicinato e minore con zoom panoramico allargato.",
    "When adding a new segment to a CC lane, use this segment shape.":
        "Forma predefinita della curva assegnata all'inserimento di un nuovo segmento in una corsia CC (lineare, quadrata, curva, ecc.).",
    "Automatically reduce events when drawing, if the segment shape is square or linear.":
        "Riduce automaticamente i punti ridondanti durante il disegno se la forma del segmento è lineare o quadrata.",
    "Add some empty space at the top and bottom of CC lanes, to make it easier to edit values close to the minimum/maximum.":
        "Aggiunge un margine vuoto in alto e in basso nelle corsie CC per facilitare la regolazione dei valori estremi (0 e 127).",
    "When editing a single CC event with the mouse, the edit can be constrained to the the space between adjacent CC events.":
        "Durante la modifica di un singolo evento CC con il mouse, il movimento può essere vincolato allo spazio compreso tra gli eventi adiacenti.",
    "Set the default behavior when double-clicking a MIDI media item.":
        "Imposta l'azione predefinita eseguita al doppio clic su un item multimediale MIDI.",
    "The active MIDI item in the MIDI editor can follow the media item or track selection in the arrange view, or neither.":
        "L'item attivo nell'editor MIDI può seguire automaticamente la selezione di track o item nella vista Arrange, oppure rimanere indipendente.",
    "Media item selection in the arrange view can determine whether a MIDI item is visible in the MIDI editor.":
        "La selezione degli item nella vista Arrange può determinare se un item MIDI viene mostrato nell'editor MIDI.",
    "Media item selection in the arrange view can determine whether a MIDI item is editable in the MIDI editor.":
        "La selezione degli item nella vista Arrange può determinare se un item MIDI è modificabile nell'editor MIDI.",
    "By default all displayed MIDI items can be editable, or only those on the same track.":
        "Stabilisce se tutti gli item MIDI visualizzati sono modificabili o solo quelli appartenenti alla stessa track.",
    "By default MIDI items on non-playing track fixed lanes can be visible, or only those on lanes that are playing back.":
        "Stabilisce se mostrare gli item MIDI presenti su corsie fisse non in riproduzione o solo quelli sulle corsie attive.",
    "When displaying multiple MIDI media items in a single editor, the editor can be set to remain open if the active media item is deleted.":
        "Con più item aperti in un unico editor MIDI, mantiene aperta la finestra anche se l'item attivo viene eliminato.",
    "More information about displaying multiple MIDI media items within a single MIDI editor.":
        "Informazioni dettagliate sulla visualizzazione e gestione di più item MIDI all'interno di un unico editor.",
    "When displaying multiple MIDI media items at once, choose how to switch the active media item within the MIDI editor.":
        "Definisce come selezionare l'item attivo quando l'editor MIDI visualizza più item contemporaneamente.",
    "MIDI notes/CC in inactive media items can be drawn more or less faintly (0-1, default is 0.25).":
        "Trasparenza con cui disegnare note e CC negli item inattivi (da 0 a 1; predefinito 0,25).",
    "MIDI notes/CC in secondary editable media items can be drawn more or less faintly (0-1, default is 0.75).":
        "Trasparenza con cui disegnare note e CC negli item modificabili secondari (da 0 a 1; predefinito 0,75).",
    "Colormap image to use for drawing notes in the MIDI editor. If no colormap is specified here, the colormap in the current color theme will be used.":
        "Immagine mappa colori (colormap) per disegnare le note nell'editor MIDI (se non specificata, viene usata quella del tema corrente).",
    "Browse for a colormap image to use as the default for drawing notes in the MIDI editor.":
        "Sfoglia per selezionare un'immagine di mappa colori personalizzata per le note dell'editor MIDI.",

    # [prefs_appear_help]
    "The length of the mouse hover delay before tooltips appear.":
        "Ritardo del passaggio del mouse (in ms) prima che vengano visualizzati i suggerimenti a comparsa (tooltip).",
    "Enable tooltips on the UI elements.":
        "Abilita i suggerimenti a comparsa (tooltip) sugli elementi dell'interfaccia utente.",
    "Enable tooltips when editing items or envelopes.":
        "Abilita i suggerimenti a comparsa durante la modifica di item o inviluppi.",
    "If tooltips are enabled for envelopes, show the tooltip when hovering the mouse over an envelope.":
        "Se i tooltip sono abilitati per gli inviluppi, mostra il suggerimento al passaggio del mouse sopra la linea dell'inviluppo.",
    "Enable peak value and loudness (if peaks settings are configured to calculate loudness) tooltip when hovering the mouse over a media item.":
        "Mostra il valore di picco e la sonorità (loudness) al passaggio del mouse sopra un item multimediale.",
    "Use legacy drawing code for drawing text, may be faster but not recommended as it is of lower quality with some fonts.":
        "Usa il motore di rendering testo legacy (può risultare più veloce ma ha resa visiva inferiore con alcuni caratteri).",
    "Cache rendered font glyphs, which can improve drawing performance significantly vs FreeType. ":
        "Memorizza nella cache i glifi dei font renderizzati, migliorando le prestazioni grafiche rispetto a FreeType.",
    "Draw smooth item fadein/fadeout curves and automation envelopes. No meaningful performance penalty.":
        "Disegna con anti-aliasing le curve di dissolvenza degli item e gli inviluppi di automazione (nessun impatto sulle prestazioni).",
    "Fill automation envelopes with color, for easier reading but a slight performance penalty. (Media item fade area curve fills use a theme setting.)":
        "Riempie con campitura colorata l'area sotto gli inviluppi di automazione per migliorarne la leggibilità.",
    "Fill automation envelopes with color when drawing envelopes over media, for easier reading but a slight performance penalty.":
        "Riempie con campitura colorata gli inviluppi sovrapposti ai file multimediali per migliorarne il contrasto visivo.",
    "Show horizontal grid lines in envelope lanes, height permitting.":
        "Mostra linee orizzontali di griglia nelle corsie degli inviluppi (se l'altezza della corsia lo consente).",
    "Adjust size of all envelope points - 1.0 is the default, 1.5 might be easier to see.":
        "Regola la dimensione visiva dei punti di inviluppo (1.0 predefinito; 1.5 per una visualizzazione ingrandita).",
    "Adjust size of unselected envelope points (relative to selected points)":
        "Regola la dimensione dei punti di inviluppo non selezionati rispetto a quelli selezionati.",
    "Width of play cursor in pixels.":
        "Spessore del cursore di riproduzione in pixel.",
    "By default, the edit cursor will display a highlight over the last selected track, to indicate where pasted content will go.":
        "Per impostazione predefinita, il cursore di modifica evidenzia l'ultima track selezionata per indicare dove verranno incollati i contenuti.",
    "Draw solid lines at the edges of the time selection. In the theme, set the time selection fill mode alpha to zero for a minor performance improvement.":
        "Disegna linee continue ai bordi della selezione temporale.",
    "Draw solid lines through the arrange view at the edges of the loop selection, for a slight performance penalty.":
        "Disegna linee continue attraverso la vista Arrange ai bordi della selezione di loop.",
    "Draw guide lines at the edges of media items and envelope points while moving them. Partially-checked checkbox draws guides but no item move horizontal guides.":
        "Mostra linee guida ai bordi di item e punti di inviluppo durante il trascinamento (la casella parzialmente spuntata esclude le guide orizzontali).",
    "Draw a vertical line to indicate the mouse position in the arrange view.":
        "Disegna una linea verticale per indicare la posizione del puntatore del mouse nella vista Arrange.",
    "When changing the size of the toolbar or floating toolbar, don't allow buttons to be drawn smaller than the size of their underlying theme images.":
        "Nel ridimensionamento delle toolbar, impedisce ai pulsanti di diventare più piccoli delle immagini originali del tema.",
    "When changing the size of the toolbar or floating toolbar, don't allow buttons to be drawn larger than the size of their underlying theme images.":
        "Nel ridimensionamento delle toolbar, impedisce ai pulsanti di diventare più grandi delle immagini originali del tema.",
    "Floating toolbars, and the Toolbar Docker, can be displayed without a window frame, for a smaller appearance.":
        "Le floating toolbar e il dock delle barre possono essere visualizzati senza cornice per un ingombro minimo.",
    "Disable all toolbar animations. Animations can be configured per-button in the toolbar context menu, under 'Customize toolbar'.":
        "Disabilita tutte le animazioni dei pulsanti delle toolbar (configurabili per pulsante in 'Personalizza toolbar').",
    "Disable animations for armed toolbar buttons. Animations can be configured per-button in the toolbar context menu, under 'Customize toolbar'.":
        "Disabilita le animazioni per i pulsanti di barra armati o attivi.",
    "Vertical pixel spacing below media items, above the following track.":
        "Spaziatura verticale in pixel sotto gli item multimediali prima della track successiva.",
    "Pixel size of track spacer, applied to track control panels, mixer, and arrange view.":
        "Spessore in pixel dei separatori di track applicati al TCP, al Mixer e alla vista Arrange.",
    "When drawing vertical text in the theme (for example, track names or meter scale numbers), draw from bottom to top rather than top to bottom.":
        "Nei testi verticali del tema (es. nomi track o scale dei meter), orienta la scrittura dal basso verso l'alto anziché dall'alto in basso.",
    "Set the minimum size in pixels where a single tab will be displayed in a docker. Below this size, a minimal handle will be displayed.":
        "Dimensione minima in pixel per mostrare una scheda singola in un docker; sotto questa soglia viene mostrata una maniglia minimale.",
    "Spacers in the TCP will shrink so that they are not larger than the following track panel's lane size.":
        "I separatori nel pannello di controllo track si riducono automaticamente per non superare l'altezza della track seguente.",
    "Region edges and markers appear as vertical lines in the arrange view by default.":
        "I bordi delle region e i marker compaiono come linee verticali nella vista Arrange per impostazione predefinita.",
    "Time signature changes appear as vertical lines in the arrange view by default.":
        "I cambi di tempo metrico (metronomo) compaiono come linee verticali nella vista Arrange per impostazione predefinita.",
    "Draw grid lines in a dotted style.":
        "Disegna le linee della griglia con stile punteggiato.",
    "Use color theme odd/even track colors to divide the arrange view vertically.":
        "Usa i colori del tema per track pari/dispari per alternare lo sfondo della vista Arrange con bande verticali.",
    "Grid label spacing and vertical shading can reset at the start of each region, or every X (zoom-dependent) measures.":
        "La spaziatura delle etichette di griglia e le ombreggiature possono riazzerarsi all'inizio di ciascuna region o ogni tot misure.",
    "Controls whether grid lines are drawn in front, in between the background and peaks, or behind items.":
        "Stabilisce se le linee della griglia vengono disegnate in primo piano, tra sfondo e onde, o dietro agli item multimediali.",
    "Controls whether marker lines are drawn in front of, in between the background and peaks, or behind items.":
        "Stabilisce se le linee dei marker vengono disegnate davanti agli item, tra lo sfondo e i picchi, o dietro agli item.",
    "Adjust how sparsely ruler labels are drawn.":
        "Regola la densità con cui vengono visualizzate le etichette numeriche sul righello temporale.",
    "The ruler can be resized smaller or larger by dragging beneath the main toolbar.":
        "Il righello può essere ridimensionato in altezza trascinando il bordo inferiore sotto la toolbar principale.",
    "When adding or removing ruler lanes, the ruler height can adjust to ensure all lanes are visible, or not.":
        "Aggiungendo o rimuovendo corsie del righello, l'altezza del righello si adatta automaticamente per mantenerle tutte visibili.",
    "When the ruler is too small to display all lanes, regions and markers can be displayed as if there are no lanes.":
        "Quando il righello è troppo stretto per tutte le corsie, region e marker vengono raggruppati come in assenza di corsie separate.",
    "When regions are named, the region number can be displayed or hidden.":
        "Quando le region hanno un nome, il numero identificativo della region può essere mostrato o nascosto.",
    "When markers are named, the region number can be displayed or hidden.":
        "Quando i marker hanno un nome, il numero identificativo del marker può essere mostrato o nascosto.",
    "When the start of a region is offscreen left, the number and name can scroll offscreen as well, or stay onscreen.":
        "Quando l'inizio di una region esce a sinistra dallo schermo, il nome e il numero possono scorrere fuori campo o rimanere visibili.",
    "Regions can be drawn with rounded or square edges in the ruler. Square edges are the default.":
        "Le region sul righello possono avere bordi arrotondati o squadrati (squadrati è l'impostazione predefinita).",
    "Markers can be drawn with rounded or square edges in the ruler. Rounded edges are the default.":
        "I marker sul righello possono avere bordi arrotondati o squadrati (arrotondati è l'impostazione predefinita).",

    # [prefs_tcp_help]
    "If a track has a custom color set, set the background color of the track label field to be the track color. Color theme may override this preference.":
        "Se la track ha un colore personalizzato, colora lo sfondo dell'etichetta del nome track (il tema visivo può prevalere).",
    "If a track has a custom color set, tint the track's panel backgrounds to the custom color. Color theme may override this preference.":
        "Se la track ha un colore personalizzato, colora l'intero pannello di controllo track (il tema può prevalere).",
    "When using track icons or fixed item lanes, align track controls on all tracks, which uses extra space but provides a cleaner appearance.":
        "Con icone track o corsie fisse attive, allinea i controlli su tutte le track per un layout visivo più ordinato.",
    "Tracks in a folder can be normal-sized, small, or collapsed. Collapsed tracks can be displayed as tiny, or not displayed at all.":
        "Le track in una cartella possono essere normali, piccole o raggruppate; le track raggruppate possono essere piccolissime o del tutto nascoste.",
    "The lane display button on fixed lane tracks controls whether lanes are big or small, and whether all lanes are displayed or only one lane at a time.":
        "Il pulsante delle corsie fisse stabilisce se le corsie sono estese o compatte, e se mostrarle tutte insieme o una alla volta.",
    "When track controls are grouped (View -> Track Grouping Matrix), draw a matching colored ribbon across the corner of all grouped controls.":
        "Quando i controlli track sono raggruppati, mostra un nastro colorato coordinato nell'angolo di tutti i controlli del gruppo.",
    "When track controls are grouped (View -> Track Grouping Matrix), draw a matching colored line at the bottom edge of all grouped controls.":
        "Quando i controlli track sono raggruppati, mostra una linea colorata coordinata sul bordo inferiore di tutti i controlli del gruppo.",
    "When track controls are grouped (View -> Track Grouping Matrix), don't draw any indication of which controls are grouped.":
        "Non mostra alcun indicatore visivo sui controlli raggruppati nella matrice dei gruppi.",
    "Decibels of attenuation applied when the volume fader is at the left/bottom.":
        "Decibel (dB) di attenuazione applicati quando il fader del volume si trova a fondo corsa (a sinistra o in basso).",
    "Decibels of gain (attenuation if negative) applied when the volume fader is at the right/top.":
        "Decibel (dB) di guadagno applicati quando il fader del volume si trova al massimo (a destra o in alto).",
    "Sensitivity of volume faders at the bottom and top. 1 is linear, lower gives more sensitivity at the bottom, higher gives more sensitivity at the top.":
        "Sensibilità dei fader del volume agli estremi di corsa (1 è lineare; valori inferiori aumentano la sensibilità in basso, superiori in alto).",
    "Display pan values in percentage or decibels.":
        "Visualizza i valori del panorama (pan) in percentuale o in decibel.",

    # [prefs_meter_help]
    "The refresh rate of the meters. The higher the rate, the faster the meters will redraw.":
        "Frequenza di aggiornamento dei meter: valori più alti garantiscono un disegno più fluido e reattivo dei livelli di picco.",
    "The decay rate of the meters. The higher the value, the faster the meters will decay and fall back to -inf.":
        "Velocità di decadimento dei meter: valori più alti fanno scendere i meter più rapidamente verso -inf dB.",
    "The minimum value of the meters in dB.":
        "Valore minimo visualizzato sulla scala dei meter in decibel (dB).",
    "The maximum value of the meters in dB.":
        "Valore massimo visualizzato sulla scala dei meter in decibel (dB).",
    "Make the clip indicator stay on when clipping occurs (enabled by default). Click the red clipping indicator to clear it.":
        "Mantiene acceso l'indicatore rosso di clipping al superamento dello 0 dBFS (fai clic sull'indicatore per azzerarlo).",
    "Automatically clear the VU meter peak indicators each time the transport is put into play, or playback is seeked to a new location.":
        "Azzera automaticamente gli indicatori di picco dei VU meter a ogni avvio della riproduzione o salto temporale.",
    "Show the name of the active recording source on the track VU meters when the track is record-armed.":
        "Mostra il nome della sorgente di ingresso sui VU meter quando la track è armata per la registrazione.",
    "Draw a dropdown box graphic around the recording source name (when shown on track VU meters) to make it clear that the source can be changed there.":
        "Disegna una cornice a menu a tendina attorno al nome della sorgente sui meter per evidenziare che è possibile cambiarla con un clic.",
    "Display pre-fader levels on track VU meters (normally post-fader levels are displayed on track meters)":
        "Mostra i livelli pre-fader sui VU meter di track (normalmente i meter mostrano i livelli post-fader).",
    "When a track has MIDI input, show the MIDI note velocity as a thin line at the bottom of the track VU meters.":
        "In presenza di segnale MIDI in ingresso, mostra la velocity delle note come una linea sottile alla base dei VU meter.",
    "When a track has MIDI output, show the activity on the track VU meters, as a thin line for note velocity and a small square for other activity.":
        "In presenza di uscita MIDI, mostra l'attività sui meter con una linea per la velocity e un quadratino per gli altri messaggi.",
    "Right-click the track meter to enable displaying total gain reduction for any plugins that support reporting this value to the host.":
        "Fai clic con il tasto destro sul meter di track per visualizzare la riduzione di guadagno (GR) complessiva comunicata dai plug-in."
}
