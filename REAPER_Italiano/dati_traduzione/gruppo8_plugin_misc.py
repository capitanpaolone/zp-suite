# gruppo8_plugin_misc.py — Traduzioni overlay spiegazioni: Plug-in, Compatibilità, VST, LV2/CLAP, DX/ReWire, ARA, Video, ReaScript, Tastiera/Gesture, Mouse, Importazione, Rendering (156 voci)

TRADUZIONI_G8 = {
    # [prefs_plugin_help]
    "When showing a plugin in the FX chain window, the window can be automatically resized to fit the plugin GUI.":
        "Quando si visualizza un plug-in nella catena FX, la finestra può ridimensionarsi automaticamente per adattarsi all'interfaccia grafica.",
    "When showing a plugin that is too big to fit in the FX chain window, automatically make the window bigger.":
        "Ingrandisce automaticamente la finestra della catena FX se il plug-in è più grande della finestra attuale.",
    "When showing a plugin that is smaller than the FX chain window, automatically make the window smaller.":
        "Riduce automaticamente la finestra della catena FX se il plug-in è più piccolo della finestra attuale.",
    "When selecting FX in the FX chain that has a floating FX window, focus that floating FX window.":
        "Selezionando un effetto nella catena FX che ha una finestra mobile aperta, porta il focus su tale finestra mobile.",
    "Automatically float FX UI windows when creating FX via the FX browser.":
        "Apre automaticamente l'interfaccia del plug-in in una finestra mobile quando viene aggiunto dal browser degli FX.",
    "Where to position newly-created FX chain windows (default is to cascade). Modal default is configured in Preferences/General: Advanced.":
        "Posizione iniziale per le nuove finestre della catena FX (predefinita: a cascata; configurabile in Preferenze/Generale: Avanzate).",
    "Where to position newly-created floating FX windows (default is to cascade). Modal default is configured in Preferences/General: Advanced.":
        "Posizione iniziale per le nuove finestre FX mobili (predefinita: a cascata; configurabile in Preferenze/Generale: Avanzate).",
    "Automatically open the FX GUI when adding an FX using a right-click menu (e.g. track FX button).":
        "Apre automaticamente l'interfaccia grafica del plug-in quando lo si aggiunge tramite menu contestuale (tasto destro sul tasto FX).",
    "Automatically dock newly created FX chain windows.":
        "Aggancia automaticamente nei docker le nuove finestre della catena FX.",
    "List the current track FX in the FX button right-click menu. Clicking an FX name in the list will float/unfloat that FX window.":
        "Elenca gli FX della track nel menu del tasto destro sul pulsante FX (un clic apre o chiude la finestra mobile del plug-in).",
    "Maximum number of plugins to keep in the \\\"Recently used\\\" list in the add-FX window.":
        "Numero massimo di plug-in da mantenere nell'elenco \"Usati di recente\" della finestra Aggiungi FX.",
    "When opening an empty FX chain, automatically show the add-FX window.":
        "Apre automaticamente la finestra Aggiungi FX all'apertura di una catena FX vuota.",
    "Do not show the empty FX chain when showing the add-FX window.":
        "Non mostrare la finestra vuota della catena FX durante la visualizzazione della finestra Aggiungi FX.",
    "When opening an FX chain window for a track or media item, close any other open FX chain window.":
        "All'apertura della catena FX di una track o di un item, chiude qualsiasi altra finestra di catena FX aperta.",
    "When changing track selection, automatically open the newly selected track's FX chain window.":
        "Al cambio di selezione della track, apre automaticamente la finestra della catena FX della nuova track selezionata.",
    "When changing track selection, if there is already an FX chain window open, automatically open the newly selected track's FX chain.":
        "Al cambio di selezione della track, se è già aperta una catena FX, passa a mostrare la catena FX della nuova track selezionata.",
    "Specify filter strings here to allow removing specific plug-ins from the FX browser, e.g.: 'NOT ( Cockos VSTi: )' to remove Cockos softsynths.":
        "Specifica stringhe di filtro per escludere determinati plug-in dal browser FX (es. 'NOT ( Cockos VSTi: )' per escludere i softsynth di Cockos).",
    "When inserting instruments that have more than 2 outputs, prompt to create new tracks with routing for these outputs.":
        "All'inserimento di strumenti virtuali con più di 2 uscite, chiedi se creare automaticamente le track con il relativo instradamento audio.",
    "Show list of FX (and other UI elements) in the FX chain window on the right side of the window rather than the left.":
        "Mostra l'elenco degli FX nella finestra della catena FX sul lato destro anziché sul lato sinistro.",
    "Show FX chain window add/remove buttons above FX list.":
        "Mostra i pulsanti di aggiunta e rimozione sopra l'elenco degli effetti nella catena FX.",
    "Show FX comment field above FX UIs in the chain view (the user may edit comments as desired).":
        "Mostra il campo commenti sopra l'interfaccia dell'effetto nella vista a catena (il testo è liberamente modificabile).",
    "Undo points may be added when closing FX windows to catch changes in plug-in state that may not have been reported by the plug-in.":
        "Crea un punto di annullamento (undo point) alla chiusura della finestra FX per registrare variazioni non notificate dal plug-in.",
    "Include descriptive text in FX names for parallel/offline/bypassed FX, for improved usability screen readers.":
        "Include etichette testuali (parallelo, offline, bypassato) nei nomi degli FX per facilitare la lettura agli screen reader per non vedenti.",
    "If checked, prevent user interaction with FX plug-ins during render (which can cause rendering errors depending on the plug-in)":
        "Impedisce l'interazione con l'interfaccia dei plug-in durante il rendering (in alcuni plug-in potrebbe causare anomalie o errori nel file finale).",
    "Prevents pin mappings from being changed by loading (REAPER-native) presets, or default presets, for plug-ins.":
        "Impedisce che il caricamento di preset nativi o predefiniti sovrascriva la mappatura dei pin (routing I/O) del plug-in.",
    "Opens the destination FX chain UI when duplicating entire FX chain by dragging track/item FX button.":
        "Apre l'interfaccia della catena FX di destinazione quando si duplica l'intera catena trascinando il pulsante FX di track o item.",
    "When enabled, closes any existing floating FX windows before opening a new window.":
        "Chiude le finestre FX mobili esistenti prima di aprirne una nuova (modalità a finestra mobile singola).",
    "Exclude monitoring FX from single-floating-FX mode, allowing monitoring FX windows to remain open.":
        "Esclude gli FX di monitoraggio dalla modalità a finestra mobile singola, mantenendoli sempre visibili.",
    "Exclude master track FX from single-floating-FX mode, allowing master FX windows to remain open.":
        "Esclude gli FX della track Master dalla modalità a finestra mobile singola, mantenendoli sempre aperti.",
    "Allow multiple floating FX, but only one per track/context.":
        "Consente più finestre mobili contemporanee, ma con un limite di una sola finestra per ciascuna track o contesto.",

    # [prefs_plugincompat_help]
    "Test all plug-in input and output for denormalized sample values (meaninglessly small values that can cause very high CPU use).":
        "Verifica ingressi e uscite dei plug-in alla ricerca di campioni denormalizzati (valori infinitesimi che possono sovraccaricare la CPU).",
    "Clear plug-in output buffers before passing them to the plug-in. Some plug-ins can output occasional uninitialized buffers, which makes bad loud noises.":
        "Azzera i buffer di uscita dei plug-in prima di elaborarli; previene forti scariche o disturbi audio generati da buffer non inizializzati.",
    "Save the plug-in's entire internal state, not just the position of the knobs. Recommended because many plug-ins store additional settings.":
        "Salva l'intero stato interno del plug-in anziché solo i controlli visibili (consigliato: molti plug-in contengono dati avanzati non visibili).",
    "Optionally send automation messages more frequently than once per buffer block when interpolating between non-square-shaped envelope points.":
        "Invia i messaggi di automazione con frequenza sub-buffer durante l'interpolazione di punti di inviluppo curvi o lineari.",
    "If a buggy or malicious plugin corrupts memory, REAPER can quit immediately, or try to continue with a high risk of crashing or other errors later.":
        "In caso di corruzione della memoria causata da un plug-in difettoso, REAPER può chiudersi subito o tentare di proseguire a rischio di crash.",
    "Additional settings, such as buggy plugin compatibility mode and save/undo options, can be set by right-clicking the plug-in name in the FX browser.":
        "Opzioni avanzate di compatibilità, salvataggio e undo sono accessibili facendo clic destro sul nome del plug-in nel browser FX.",

    # [prefs_vst_help]
    "Directories to scan for VST plug-ins. Subdirectories will also be scanned.":
        "Cartelle in cui cercare i plug-in VST (le sottocartelle vengono scansionate automaticamente).",
    "Displays a menu with options to re-scan plug-ins, and view a list of plug-ins that failed to scan.":
        "Mostra un menu con le opzioni per ripetere la scansione dei plug-in e visualizzare l'elenco dei plug-in falliti.",
    "Use the generic slider view instead of the VST's custom GUI. You can switch views at any time using the UI button on the plug-in window.":
        "Usa la vista a slider generici anziché l'interfaccia personalizzata del VST (è possibile cambiare vista in qualsiasi momento con il tasto UI).",
    "Set the default VST knob behavior. Almost no plug-ins support this setting.":
        "Imposta il comportamento predefinito delle manopole VST (supportato da pochissimi plug-in).",
    "Set how automation notifications are handled from VST plug-ins. You can also override this per-plugin, most people will want to leave this on the default.":
        "Definisce la gestione delle notifiche di automazione dai plug-in VST (impostabile per singolo plug-in; si consiglia il valore predefinito).",
    "Don't inform VSTis that playback has stopped. Most synths (especially arpeggiators) want to know playback has stopped to avoid hanging notes.":
        "Non notificare ai VSTi l'arresto della riproduzione (la maggior parte dei synth e arpeggiatori necessita di questo avviso per evitare note bloccate).",
    "Preserve held notes and current pitch when resetting VSTis. This is probably needed when disabling Preferences/Audio/Playback/Reset MIDI CC/Pitch.":
        "Conserva le note tenute e l'intonazione corrente al reset dei VSTi (necessario disabilitando il reset MIDI CC/Pitch in Audio/Playback).",
    "Some VSTs behave differently when rendering offline (not in realtime).  When deselected,  plugins always think they are online.":
        "Alcuni VST si comportano diversamente nel rendering offline (non in tempo reale). Se deselezionato, i plug-in crederanno di essere sempre online.",
    "Some buggy plug-ins crash when the GUI is opened while a different thread is processing audio. This avoids the crash by interrupting audio.":
        "Alcuni plug-in difettosi vanno in crash se l'interfaccia si apre mentre un thread elabora l'audio: questa opzione interrompe l'audio per evitare il crash.",
    "Allow unloading of VST DLLs, which gets them completely out of memory, but also may cause compatibility issues.":
        "Consente lo scaricamento completo delle librerie DLL/dylib dei VST dalla memoria RAM (può causare problemi di compatibilità con certi plug-in).",
    "Special mode, applied to UAD plugins only, that reduces parallel processing benefits to avoid UAD-1 crashes.":
        "Modalità speciale applicata esclusivamente ai plug-in UAD per prevenire instabilità o crash con schede DSP UAD-1.",
    "Scan for new/updated VST plug-ins on startup (recommended). If disabled you can manually re-scan or choose the plug-ins to scan here.":
        "Cerca nuovi VST all'avvio di REAPER (consigliato). Se disabilitato, la scansione potrà essere avviata manualmente da qui.",

    # [prefs_lv2_help]
    "Directories to scan for CLAP plug-ins. Subdirectories are automatically scanned.":
        "Cartelle in cui cercare i plug-in in formato CLAP (le sottocartelle vengono scansionate automaticamente).",
    "Re-scan CLAP paths for added/updated plug-ins.":
        "Riesegui la scansione delle cartelle CLAP alla ricerca di plug-in aggiunti o aggiornati.",
    "Status of how many CLAP plug-ins scanned/failed, click the Re-scan button to rescan the paths and/or view which plug-ins failed.":
        "Riepilogo dei plug-in CLAP scansionati e falliti; fai clic per ripetere la scansione o verificare quali plug-in sono falliti.",
    "Directories to scan for LV2 plug-ins. Subdirectories will not be scanned and must be added manually.":
        "Cartelle in cui cercare i plug-in in formato LV2 (le sottocartelle non sono scansionate in automatico e vanno aggiunte manualmente).",
    "Scan all LV2 directories for any added or updated plug-ins.":
        "Scansiona tutte le cartelle LV2 alla ricerca di plug-in nuovi o aggiornati.",
    "If a LV2 plug-in only outputs a single channel, append (Mono) to the name.":
        "Se un plug-in LV2 produce un'uscita a singolo canale, aggiunge '(Mono)' al nome visualizzato.",
    "If a LV2 plug-in outputs more than stereo, append (X channel) to the name.":
        "Se un plug-in LV2 ha un'uscita multicanale superiore allo stereo, aggiunge '(X canali)' al nome visualizzato.",
    "If a LV2 plug-in is MIDI-only, append (MIDI) to the name.":
        "Se un plug-in LV2 elabora solo segnali MIDI, aggiunge '(MIDI)' al nome visualizzato.",
    "Append the LV2 plug-in developer/maintainer name, if available.":
        "Aggiunge il nome dello sviluppatore o manutentore del plug-in LV2 (se disponibile nei metadati).",
    "Status of how many LV2 plug-ins scanned/failed, click the Re-scan button to rescan the paths and/or view which plug-ins failed.":
        "Riepilogo dei plug-in LV2 scansionati e falliti; fai clic per rieseguire la scansione o verificare i plug-in falliti.",

    # [prefs_dx_help]
    "Show any already-opened ReWire-aware applications/devices as available FX in the add-FX window.":
        "Mostra le applicazioni o dispositivi compatibili con ReWire già aperti come effetti disponibili nella finestra Aggiungi FX.",
    "When adding ReWired applications/devices, automatically open the device control panel.":
        "All'inserimento di dispositivi ReWire, apre automaticamente il relativo pannello di controllo dell'applicazione collegata.",
    "Process all track FX even when playback is stopped, when any ReWire device is active.":
        "Elabora tutti gli FX di track anche a riproduzione ferma quando è attivo un dispositivo ReWire.",
    "If an application/device is already open that can act as ReWire master, automatically place Reaper in ReWire client mode.":
        "Se è già aperta un'applicazione configurata come ReWire Master, imposta automaticamente REAPER come ReWire Client (slave).",
    "When running in ReWire client mode, use a separate preferences configuration file so separate preferences and settings can be preserved for this mode only.":
        "In modalità ReWire Client, usa un file di configurazione preferenze dedicato per preservare impostazioni specifiche separate.",
    "Change ReWire client settings for the current project. To save this project's settings as default, go to File/Project Settings.":
        "Modifica le impostazioni ReWire Client per il progetto corrente (per salvarle come predefinite, vai in File/Impostazioni progetto).",

    # [prefs_ara_help]
    "Enable or disable ARA globally for plugins that support it.":
        "Abilita o disabilita a livello globale il supporto ARA (Audio Random Access) per i plug-in compatibili.",
    "Edits can be automatically pooled (shared) between copies of the same source media.":
        "Le modifiche ARA possono essere condivise automaticamente (in pool) tra le copie dello stesso file sorgente.",

    # [prefs_video_help]
    "Choose the priority of available video decoders. See \\\"Show decoder information\\\" for more detail.":
        "Scegli l'ordine di priorità dei decodificatori video disponibili (vedi \"Mostra informazioni decodificatore\" per i dettagli).",
    "The video window will sync to the specified seek point when moving/resizing audio items.":
        "La finestra video si sincronizza al punto temporale specificato durante lo spostamento o il ridimensionamento degli item audio.",
    "OpenGL output is preferred, but DirectShow modes are also available, as is BitBlt for the most compatible/slowest. Force format to reduce flicker when changing colorspaces/output size.":
        "Il rendering OpenGL è consigliato; DirectShow e BitBlt offrono massima compatibilità ma minore velocità. Forza il formato per evitare sfarfallii.",
    "Automatic output uses colorspace of project/media, otherwise you can override the output colorspace here.":
        "L'uscita automatica usa lo spazio colore del progetto/media; è possibile forzare uno spazio colore specifico da questo menu.",
    "OpenGL output is preferred, very slow but more-compatible output modes are also available.":
        "L'uscita video OpenGL è consigliata; sono disponibili anche modalità più lente per massima compatibilità hardware.",
    "Low-res peaks (less detail when zoomed in) can improve responsiveness. You can set peaks resolution per-item in video source properties.":
        "Picchi a bassa risoluzione migliorano la reattività sui video; la risoluzione dei picchi è impostabile per singolo item nelle proprietà.",
    "Delay video output during playback by a small (and possibly negative) amount to allow best possible sychronization.":
        "Ritarda o anticipa l'uscita video durante la riproduzione (anche con valori negativi) per una sincronizzazione perfetta audio-video.",
    "Length of newly imported image files, in milliseconds. Negative values set length in frames.":
        "Durata predefinita per le immagini statiche importate, in millisecondi (valori negativi impostano la durata in fotogrammi/frame).",
    "Thumbnail display mode for image files imported as items.":
        "Modalità di visualizzazione delle miniature (thumbnail) per le immagini importate come item.",
    "Uses a standard OS editing control for the video code editor, useful for accessibility but otherwise lacks many useful editing features":
        "Usa il controllo di testo standard del sistema operativo per l'editor video (utile per l'accessibilità, ma privo di evidenziazione sintassi).",

    # [prefs_reascript_help]
    "View ReaScript overview online, at http://www.reaper.fm/sdk/reascript/reascript.php.":
        "Consulta la guida introduttiva a ReaScript online su http://www.reaper.fm/sdk/reascript/reascript.php.",
    "View ReaScript documentation, including a full function reference for the REAPER API.":
        "Visualizza la documentazione completa di ReaScript con il riferimento a tutte le funzioni dell'API di REAPER.",
    "The ReaScript console can also be cleared with ClearConsole().":
        "La console dei messaggi ReaScript può essere azzerata anche richiamando la funzione ClearConsole().",
    "Lua ReaScripts can be automatically halted if they run for too long, to avoid scripts crashing REAPER. (The timeout limit is not foolproof.)":
        "Gli script Lua possono essere interrotti automaticamente se restano bloccati in esecuzione troppo a lungo, prevenendo blocchi dell'applicazione.",
    "Update the ReaScript IDE watch window for deferred-running scripts at this interval (default 0.5 seconds)":
        "Intervallo di aggiornamento della finestra variabili (Watch) nell'IDE ReaScript per script con funzioni differite (default 0,5 secondi).",
    "ReaScript for EEL2 and Lua will always work. Python must be enabled here.":
        "Gli script in linguaggio EEL2 e Lua sono sempre operativi; il supporto per Python richiede l'abilitazione in questa scheda.",
    "Python is available as a free download. Please see ReaScript documentation for more information.":
        "Python è disponibile gratuitamente per il download; consulta la documentazione di ReaScript per i dettagli di installazione.",
    "After you install Python, REAPER should find the Python dynamic library automatically.":
        "Dopo l'installazione di Python, REAPER individua automaticamente la libreria dinamica condivisa di Python.",
    "If REAPER finds a compatible version of Python on this machine, view the path to the Python dynamic library.":
        "Visualizza il percorso della libreria dinamica di Python se REAPER ne rileva una versione compatibile sul sistema.",
    "If REAPER cannot find Python automatically, enter the path here. See the Python installer readme for more information.":
        "Se REAPER non individua Python in automatico, inserisci qui il percorso della libreria dinamica (vedi note di rilascio di Python).",
    "If you have multiple versions of Python installed, you can force REAPER to use a specific dynamic library if needed.":
        "Se sul computer sono installate più versioni di Python, puoi forzare REAPER a utilizzarne una specifica indicandone la libreria.",
    "Only show an autocomplete suggestion list of this many entries (you can still navigate the longer list with arrow keys). 0 to disable suggestions.":
        "Numero massimo di suggerimenti di completamento automatico mostrati nell'IDE (0 disabilita i suggerimenti).",
    "By default, ReaScript compile-time error messages are displayed at the bottom of the IDE. The message can be output to the console as well.":
        "I messaggi di errore di compilazione compaiono alla base dell'IDE; è possibile inviarli anche alla console ReaScript.",
    "Click to change the color theme for the ReaScript/JSFX/Video Processor IDEs.":
        "Fai clic per modificare il tema cromatico degli editor di codice (IDE) integrati per ReaScript, JSFX e Video Processor.",
    "If enabled, doubleclicking a user-defined function name will jump to that functions implementation.":
        "Se abilitato, fare doppio clic sul nome di una funzione definita dall'utente salta direttamente alla sua implementazione nel codice.",
    "Prevent scripts/plug-ins from displaying the ReaScript console. In this case, a [MSG] or [ERR] appearsin the main menu bar, and you can click to open the console.":
        "Impedisce agli script di aprire forzatamente la console: comparirà l'avviso [MSG] o [ERR] nella barra dei menu per aprirla a richiesta.",

    # [prefs_kbd_help]
    "You can maintain a separate set of keyboard shortcuts for use only when recording.":
        "Consente di definire una mappa di scorciatoie da tastiera dedicata, attiva esclusivamente durante la registrazione.",
    "Prevent pressing/holding the ALT key in the main view from focusing the main menu (suppress the default Windows behavior).":
        "Impedisce alla pressione del tasto Alt di attivare la barra dei menu principale (disabilita il comportamento standard di Windows).",
    "Allows the space key to be used for checkboxes/etc in various windows including the media item properties.":
        "Consente alla barra spaziatrice di attivare caselle di controllo e pulsanti in varie finestre, inclusa Proprietà item.",
    "When typing new values in some edit fields, the new value can be committed after 1 second, or only after pressing enter.":
        "Nei campi di immissione numerica, il valore può essere confermato dopo 1 secondo di inattività o solo premendo Invio.",
    "Allows the space key to be used to start/stop transport (via default binding) when editing plug-in text fields. If enabled, insert a space character using shift+space.":
        "Usa la barra spaziatrice per avviare/fermare il trasporto anche mentre si scrive nei campi testo dei plug-in (inserisci spazi con Shift+Spazio).",
    "Assign any keyboard shortcut to a REAPER action, using the Actions dialog.":
        "Assegna qualsiasi scorciatoia da tastiera alle azioni di REAPER tramite la finestra Azioni.",
    "View a list of all existing keyboard shortcuts as a web page in an external browser.":
        "Visualizza l'elenco completo delle scorciatoie da tastiera attive come pagina web nel browser predefinito.",
    "Enable the multitouch swipe action: two fingers moved together horizontally or vertically.":
        "Abilita il gesto multitouch di scorrimento (swipe) con due dita in orizzontale o verticale.",
    "Enable the multitouch zoom action: two fingers moved closer together (pinch) or farther apart.":
        "Abilita il gesto multitouch di zoom (pizzico a due dita per allargare o stringere la visualizzazione).",
    "Enable the multitouch rotate action: rotate one finger around another stationary finger.":
        "Abilita il gesto multitouch di rotazione con un dito attorno a un altro punto fermo.",
    "Reverse the direction of this gesture.":
        "Inverte la direzione naturale di questo gesto multitouch.",
    "Suppress inertia, so that each gesture triggers only one action, rather than a series of actions.":
        "Elimina l'inerzia del gesto, facendo sì che ogni movimento esegua una singola azione anziché una sequenza continua.",
    "Scale the magnitude of this gesture.":
        "Scala la sensibilità e la portata del movimento per questo gesto multitouch.",
    "Reverse the direction of the vertical scroll (standard mousewheel).":
        "Inverte la direzione dello scorrimento verticale (rotella classica del mouse).",
    "Reverse the direction of the horizontal scroll (horizontal mousewheel).":
        "Inverte la direzione dello scorrimento orizzontale (rotella o scorrimento orizzontale).",
    "Ignore mousewheel messages for a short time after a multitouch gesture is seen.":
        "Ignora gli eventi della rotella del mouse per un breve intervallo dopo un gesto multitouch.",
    "Ignore multitouch gestures of a different type for a short time after a multitouch gesture is seen.":
        "Ignora altri tipi di gesti multitouch per un breve istante dopo il rilevamento di un gesto.",
    "Assign any enabled multitouch gesture to a REAPER action, using the Actions dialog.":
        "Assegna i gesti multitouch abilitati alle azioni di REAPER attraverso la finestra Azioni.",
    "When using actions that override keyboard sections momentarily, return to the active keyboard section if no key pressed within this time (default 1000ms)":
        "Nelle azioni con cambio temporaneo della sezione tastiera, ripristina la sezione normale se non viene premuto alcun tasto entro questo tempo.",

    # [prefs_mouse_help]
    "By default, a mouse click anywhere in the fader area will move the fader handle directly to the mouse position.":
        "Per impostazione predefinita, fare clic in qualsiasi punto dell'escursione di un fader sposta istantaneamente la manopola sulla posizione del cursore.",
    "Mousewheel messages are passed to the window under the mouse cursor (default), or the currently focused/active window.":
        "Gli eventi della rotella del mouse vengono inviati alla finestra sotto il puntatore (predefinito) o alla finestra attiva con il focus.",
    "Check to prevent the mousewheel from moving any fader. If not checked, mouse modifiers can be customized for faders.":
        "Seleziona per impedire alla rotella del mouse di spostare i fader di volume; se deselezionato, è possibile personalizzare i modificatori del mouse.",
    "Check to prevent the mousewheel from affecting TCP send controls, embedded FX, volume/pan faders, etc.":
        "Seleziona per impedire alla rotella del mouse di alterare send nel TCP, controlli FX integrati, fader e potenziometri di panorama.",
    "Disable mousewheel editing of project playrate, project tempo, and time selection start/end/length fields in the transport area.":
        "Disabilita la modifica con rotella del mouse per velocità di riproduzione, BPM e campi di selezione temporale nella barra di trasporto.",
    "Mousewheel editing of the time selection fields in the transport can change the time selection by a small amount, or by the project beat grid.":
        "La regolazione con rotella della selezione temporale nel trasporto può variare per piccoli intervalli o a passi di griglia metrica.",
    "Some trackpads can send scroll messages. Reaper can try to convert these to mousewheel messages.":
        "Alcuni trackpad inviano messaggi di scroll: REAPER può provare a convertirli in eventi di rotella mouse per uniformare il controllo.",
    "Clicking faders and controls can select the track, otherwise only clicking empty track control panel space or lane buttons will select.":
        "Fare clic su fader e controlli può selezionare la track; altrimenti la selezione avviene solo cliccando su aree vuote del pannello o sui pulsanti corsia.",
    "Enable editing track names with a single mouse click (default requires double click).":
        "Abilita la ridenominazione delle track con un singolo clic del mouse (l'impostazione predefinita richiede un doppio clic).",
    "Clicking in the arrange view can select that track, otherwise tracks can only be selected by clicking the track control panel.":
        "Fare clic nell'area della vista Arrange può selezionare la track (altrimenti la selezione richiede un clic sul pannello TCP).",
    "Allow editing the time selection where the selection edge passes through a media item, otherwise dragging will move the media item.":
        "Consente di modificare il bordo della selezione temporale anche se cade sopra un item (altrimenti il trascinamento sposta l'item multimediale).",
    "Allow resizing the ruler height by dragging the bottom of the ruler. Otherwise the ruler can be resized by dragging below the toolbar.":
        "Consente di ridimensionare l'altezza del righello trascinando il suo bordo inferiore (in alternativa trascinando sotto la toolbar).",
    "Control+click can be used for one-button mice to emulate right-click behavior, but then the control key will not be available as a mouse modifier.":
        "Control+Clic può emulare il tasto destro sui mouse a tasto singolo, ma rende il tasto Control non disponibile come modificatore del mouse.",
    "If you use a pen or tablet or other absolute pointing device as a mouse, this will improve behavior when adjusting REAPER's knobs":
        "Se utilizzi una penna, una tavoletta grafica o un dispositivo a coordinate assolute, migliora la fluidità di rotazione delle manopole.",
    "When drag/dropping track panels, controls when destination track is converted to a folder to contain the source track.":
        "Durante il trascinamento dei pannelli track, stabilisce quando la track di destinazione viene convertita in cartella per contenere la track trascinata.",

    # [prefs_import_help]
    "If you expect to continue to modify the project tempo, import as beat slices. If you want to immediately loop the file, import as a single item.":
        "Se prevedi di variare il tempo metronomico del progetto, importa come slice ritmiche; se desideri mandare subito in loop l'audio, importa come item singolo.",
    "Each slice may contain tail audio that can play underneath later slices. These tails can be played, or chopped off on import.":
        "Ciascuna slice ritmica può contenere code audio sottostanti alle slice successive: possono essere riprodotte o tagliate all'importazione.",
    "Media containing embedded tempo information can be automatically tempo-matched. Media explorer tempo-match settings will override.":
        "I file contenenti informazioni di tempo metronomico possono adattarsi automaticamente al tempo di progetto (le impostazioni del Media Explorer prevalgono).",
    "Media tempo for tempo-matching may be suggested in the filename or metadata, or estimated based on the file length.":
        "Il tempo metronomico del file può essere letto dal nome file, dai metadati o stimato in base alla durata complessiva dell'audio.",
    "When importing media with embedded or suggested tempo information into an empty project, the project tempo can be set from the media.":
        "All'importazione di file con metadati di tempo in un progetto vuoto, il tempo del progetto può essere impostato automaticamente su quello del file.",
    "Media containing embedded tempo information can be set to automatically stretch when the media item crosses a project tempo change marker.":
        "I file con metadati di tempo possono adattarsi automaticamente (time-stretch) quando oltrepassano un marker di cambio tempo nel progetto.",
    "Raw PCM files may be imported with best-guess audio parameters (sample rate, etc). When importing, explain how to fix incorrect parameters.":
        "I file PCM raw vengono importati con parametri stimati (sample rate, ecc.): all'importazione mostra una guida su come correggere parametri errati.",
    "When inserting multiple media items via action or drag and drop, the items can be added on separate tracks, or sequentially on a single track.":
        "All'inserimento di più file multimediali, stabilisce se disporli su track separate o in sequenza temporale su una singola track.",
    "When dragging media items into REAPER, allow dragging to the top part of a track to insert a new track to receive the media.":
        "Trascina un file multimediale nella parte superiore di una track per creare e inserire una nuova track destinata a ricevere il file.",
    "When importing directories into REAPER, create new folder tracks for each imported directory.":
        "All'importazione di intere cartelle, crea automaticamente track cartella (folder track) per ciascuna directory importata.",
    "When importing files from directories, also recursively scan for files in subdirectories.":
        "All'importazione di cartelle, scansiona ricorsivamente anche tutte le relative sottocartelle.",
    "If configured to copy imported media, also copy media when pasting items from project to project.":
        "Se è impostata la copia dei media importati, copia i file multimediali anche quando si incollano item tra progetti differenti.",
    "If checked, copy imported media items to the project media path (if they are not already in the project path).":
        "Se selezionato, copia i file multimediali importati nella cartella media del progetto (se non sono già presenti nel percorso di progetto).",
    "If checked, name unnamed tracks after the media on media import.":
        "Se selezionato, assegna alle track prive di nome il nome del file multimediale importato.",
    "If auto-naming tracks on import, remove trailing numbers from track names.":
        "Durante l'assegnazione automatica del nome track, rimuove i numeri finali presenti nel nome del file.",
    "When importing or pasting media with ripple editing enabled, existing media items that start earlier can be split, or unaffected.":
        "All'importazione o inserimento di media con Ripple Edit attivo, gli item esistenti con inizio antecedente possono essere divisi o lasciati intatti.",

    # [prefs_render_help]
    "Sets the audio block size used when rendering. If blank, rendering will use the audio device block size (recommended for consistent FX playback).":
        "Dimensione del blocco buffer usata durante il rendering (se vuoto, usa la dimensione del buffer della scheda audio; consigliato per coerenza degli FX).",
    "When checked, configured multiprocessing settings will be used for rendering. If unchecked, rendering will be slower but can be more reliable with some plug-ins.":
        "Usa le impostazioni multi-core per il rendering; se deselezionato, il rendering avverrà a thread singolo (più lento ma risolve problemi con certi plug-in).",
    "When checked, limit apply FX/render stems actions to realtime. This is good for certain plug-ins that fail when running faster than realtime.":
        "Limita le azioni Applica FX e Render Stem alla velocità reale 1x (utile per plug-in esterni o DSP hardware che non supportano il rendering offline veloce).",
    "Rendering the project or stems, or freezing tracks, can run beyond the last media item in the project, to be sure to record any FX tails (like reverb).":
        "Nel rendering di progetti, stem o freeze delle track, prosegue oltre l'ultimo item per catturare per intero le code degli effetti (riverberi, delay).",
    "When rendering stems for the entire project, apply the tail length setting. This also affects the default tail settings in the render window.":
        "Nel rendering degli stem dell'intero progetto, applica l'impostazione della lunghezza coda (influisce anche sul valore predefinito nella finestra Render).",
    "When rendering stems for a time selection, apply the tail length setting. This also affects the default tail settings in the render window.":
        "Nel rendering degli stem di una selezione temporale, applica l'impostazione della lunghezza coda.",
    "By default, only media items will be rendered when freezing. If there are FX on the track, the entire track can be rendered, which may be slower.":
        "Durante il freeze vengono renderizzati solo gli item; se la track contiene FX, è possibile renderizzare l'intera track (operazione più lenta).",
    "When freezing an entire track, apply the tail length setting.":
        "Applica l'impostazione della lunghezza coda sonora durante il freeze dell'intera track.",
    "After canceling a render, the incompletely rendered files can automatically be saved or deleted, or REAPER can prompt every time.":
        "All'annullamento manuale di un rendering, i file parziali incompleti possono essere conservati, eliminati automaticamente o confermati a richiesta.",
    "After rendering, the render output/statistics window can remain open, or the render setup window can remain open, or both windows can close.":
        "Al termine del rendering, stabilisce se mantenere aperta la finestra statistiche/file, la finestra di impostazione o chiudere entrambe.",
    "Various statistics can be calculated and displayed when rendering.":
        "Consente di calcolare e visualizzare varie statistiche di livello (picco, RMS, LUFS) durante e dopo il rendering.",
    "If freezing a track with muted items, generate silent items so that the presence of muted items is known.":
        "Nel freeze di una track contenente item silenziati, genera item vuoti di silenzio per segnalarne visivamente la presenza.",
    "Prevents auto-bypass project/FX setting from being used during offline renders, apply FX, stem renders, etc.":
        "Impedisce l'intervento dell'auto-bypass dei plug-in durante i rendering offline, l'applicazione di FX e il rendering di stem.",
    "After rendering, the render output/statistics window can prevent focus from returning to the project, or reopen modelessly to allow focus to change.":
        "Al termine del rendering, stabilisce se la finestra dei risultati deve trattenere il focus o aprirsi in modalità non modale consentendo di usare il progetto."
}
