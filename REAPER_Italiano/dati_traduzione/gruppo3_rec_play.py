# gruppo3_rec_play.py — Traduzioni overlay spiegazioni: Registrazione, Loop, Playback, Seek, Scrub (70 voci)

TRADUZIONI_G3 = {
    # [prefs_record_help]
    "While recording, respect the options menu setting to automatically scroll the arrange view when the record cursor moves offscreen.":
        "Durante la registrazione, rispetta l'impostazione del menu Opzioni per scorrere automaticamente la vista Arrange quando il cursore esce dallo schermo.",
    "Display a medium-resolution peak/waveform preview of audio items while recording. Regardless, a high-resolution display will be shown afterwards.":
        "Mostra un'anteprima dei picchi/forma d'onda a media risoluzione durante la registrazione (in ogni caso al termine verrà mostrata l'anteprima ad alta risoluzione).",
    "Update speed of peak/waveform preview for recording items, in frames per second (lower values leave more resources free for the actual recording).":
        "Velocità di aggiornamento dell'anteprima di picco/forma d'onda per gli item in registrazione, in fotogrammi al secondo (valori più bassi lasciano più risorse alla registrazione).",
    "Peak/waveform display data files are created for every audio item.":
        "I file di dati per la visualizzazione dei picchi/forma d'onda vengono creati per ciascun item audio.",
    "Create audio peak/waveform display data files while recording audio (recommended)":
        "Crea i file di picco/forma d'onda durante la registrazione dell'audio (consigliato)",
    "Create audio peak/waveform display data files only after recording stops.":
        "Crea i file di picco/forma d'onda solo al termine della registrazione.",
    "Create audio peak/waveform display data files only when manually selecting the menu item item/peaks/build peaks.":
        "Crea i file di picco/forma d'onda solo selezionando manualmente la voce di menu Item/Picchi/Costruisci picchi.",
    "New recorded files can be automatically saved, or selectively deleted.":
        "I nuovi file registrati possono essere salvati automaticamente o eliminati in modo selettivo.",
    "Prompt to selectively save or delete new recorded files after recording stops.":
        "Chiedi conferma per salvare o eliminare i file appena registrati dopo l'arresto della registrazione.",
    "Prompt to selectively save or delete new recorded files when punching out of recording (by pressing the play button).":
        "Chiedi conferma per salvare o eliminare i file registrati quando si esce dalla registrazione (punch-out premendo Play).",
    "Record-armed tracks can automatically expand to show the recording source and input level meters.":
        "Le tracce armate per la registrazione possono espandersi automaticamente per mostrare la sorgente di registrazione e i meter di ingresso.",
    "When recording a single, very long uninterrupted take, create new files (gaplessly) to avoid file-format size limitations.":
        "Durante la registrazione di un take ininterrotto molto lungo, crea nuovi file (senza interruzioni) per evitare i limiti di dimensione del formato file.",
    "During lengthy recording, switching files creates a momentary CPU load, which can be lessened by offsetting file switches when recording multiple tracks.":
        "Durante registrazioni prolungate, il cambio di file genera un carico momentaneo sulla CPU, attenuabile sfalsando i cambi file nella registrazione multitraccia.",
    "Abort recording if no tracks are record-armed. Tracks can always be record-armed and unarmed after recording has started.":
        "Interrompi la registrazione se nessuna traccia è armata. Le tracce possono comunque essere armate e disarmate dopo l'avvio della registrazione.",
    "Customize the filename that is automatically created for new recordings.":
        "Personalizza il nome file assegnato automaticamente alle nuove registrazioni.",
    "Customize the name that is automatically applied to new in-project MIDI media items.":
        "Personalizza il nome assegnato automaticamente ai nuovi item multimediali MIDI interni al progetto.",
    "Check the available disk space for recording when recording starts, and warn if the available recording space falls below a threshold.":
        "Controlla lo spazio su disco disponibile all'avvio della registrazione e avvisa se scende sotto una soglia minima.",
    "Always display the available disk space in the menu bar.":
        "Mostra sempre lo spazio su disco disponibile nella barra dei menu.",
    "Display the project recording path (primary, if multiple) in the menu bar.":
        "Mostra il percorso di registrazione del progetto (il primario, se multipli) nella barra dei menu.",
    "Automatically adjust recorded media positioning to compensate for the audio driver's reported latency.":
        "Regola automaticamente la posizione dell'audio registrato per compensare la latenza dichiarata dal driver audio.",
    "Record audio during pre-roll (if enabled in metronome settings). Allows access to parts played early, etc.":
        "Registra l'audio durante il pre-roll (se abilitato nelle impostazioni del metronomo); consente di recuperare attacchi suonati in leggero anticipo.",
    "Set or adjust the recording latency compensation. If auto adjust is enabled, these values are added to the automatic offset. Offsets can be negative.":
        "Imposta o corregge la compensazione della latenza di registrazione. Se la regolazione automatica è attiva, questi valori si sommano all'offset automatico (possono essere negativi).",

    # [prefs_record_loop_help]
    "Incomplete takes can be automatically discarded, as long as at least one complete pass through the loop selection was recorded.":
        "I take incompleti possono essere scartati automaticamente, purché sia stato registrato almeno un passaggio completo nella selezione di loop.",
    "Threshold of length that a take has to exceed to be considered complete. The default is 90%, but 50% or 100% are also sensible values.":
        "Soglia di lunghezza che un take deve superare per essere considerato completo (predefinita 90%, ma anche 50% o 100% sono valori ragionevoli).",
    "By default, MIDI recording that starts within a time selection will create a media item that starts when MIDI input begins.":
        "Per impostazione predefinita, la registrazione MIDI avviata dentro una selezione temporale crea un item che inizia al primo input MIDI ricevuto.",
    "Loop recording can create one or more audio files, which can be added to the project after each loop, or only when recording stops.":
        "La registrazione in loop può creare uno o più file audio, aggiunti al progetto dopo ogni loop oppure solo all'arresto della registrazione.",
    "Add recorded media to project after each loop, which can be used to build up layered recordings.":
        "Aggiungi i media registrati al progetto dopo ogni ciclo di loop (utile per registrazioni stratificate).",
    "Add recorded media to project only when recording stops (default).":
        "Aggiungi i media registrati al progetto solo all'arresto della registrazione (predefinito).",
    "Create a separate file on disk for each loop (default is to record to a single, continuous file).":
        "Crea un file separato su disco per ogni ciclo di loop (l'impostazione predefinita registra un singolo file continuo).",
    "Reuse existing lanes for new recording if space permits and doing so would not change the playback state significantly.":
        "Riutilizza le corsie esistenti per le nuove registrazioni se lo spazio lo consente e se ciò non altera in modo significativo la riproduzione.",
    "When recording into a fixed lane track, the normal behavior of trimming the recording to the auto-punch area can be overridden.":
        "Nella registrazione su tracce con corsie fisse, è possibile bypassare il comportamento normale che rifila la registrazione all'area di auto-punch.",

    # [prefs_playback_help]
    "Makes playback stop and/or loop at the end of the project.":
        "Arresta e/o ripete in loop la riproduzione alla fine del progetto.",
    "Stop the playback at the end of the time selection if loop is disabled.":
        "Ferma la riproduzione al termine della selezione temporale se la ripetizione in loop è disattivata.",
    "Clears the FX buffers at the end of a loop. This is not recommended for VSTi plug-ins, but may provide better performance for plug-ins like AutoTune.":
        "Svuota i buffer degli FX alla fine di un loop. Sconsigliato per i VSTi, ma può migliorare le prestazioni di plug-in come AutoTune.",
    "When track media playback offset is negative, a max play speed higher than 1 will ensure that all MIDI notes are played.":
        "Quando l'offset di riproduzione della traccia è negativo, una velocità massima superiore a 1 assicura che tutte le note MIDI vengano riprodotte.",
    "Select this option to make the view scroll to the edit cursor on stop.":
        "Seleziona questa opzione per far scorrere la vista sul cursore di modifica all'arresto della riproduzione.",
    "Allows you to preview sounds from your instrument plug-ins when stopped.":
        "Consente di ascoltare l'anteprima sonora dei virtual instrument quando la riproduzione è ferma.",
    "Clears the FX buffers when stopping playback, preventing reverb tails etc.":
        "Svuota i buffer degli FX all'arresto della riproduzione, eliminando code di riverbero, delay, ecc.",
    "If \\\"Run FX when stopped\\\" is unchecked, you can define the amount of time a FX will run after playback is stopped.":
        "Se 'Elabora FX a riproduzione ferma' è deselezionato, definisce per quanto tempo gli FX continuano a girare dopo lo stop.",
    "Apply a buffer block length fade-out to the monitor signal only, when stopping playback. N/A if FX configured to play back unflushed when stopped.":
        "Applica una dissolvenza in uscita (pari al blocco buffer) solo al segnale di monitoraggio all'arresto della riproduzione.",
    "Apply a buffer block length fade-in to the monitor signal only, when starting playback.":
        "Applica una dissolvenza in entrata (pari al blocco buffer) solo al segnale di monitoraggio all'avvio della riproduzione.",
    "Reduce CPU use on silent tracks by detecting silence during playback and avoiding additional processing (raises CPU use of non-silent tracks).":
        "Riduce il consumo di CPU sulle tracce silenziose rilevando il silenzio ed evitando elaborazioni superflue (aumenta lievemente l'uso CPU delle tracce attive).",
    "Send note-offs to all track destinations when disabling record-arm (to prevent hanging notes).":
        "Invia comandi Note-Off a tutte le destinazioni della traccia quando si disarma la registrazione (per evitare note bloccate).",
    "Reset MIDI CC/Pitch to neutral on playback start and/or stop.":
        "Reimposta i controller MIDI CC e il Pitch Bend al valore neutro all'avvio e/o all'arresto della riproduzione.",
    "Reset MIDI CC/Pitch to neutral when looping playback.":
        "Reimposta i controller MIDI CC e il Pitch Bend al valore neutro a ogni ciclo di loop.",
    "Override CC resets for various CCs here. Syntax is 'cc7=127 cc39=127' to set maximum volume, for example. -1 prevents reset, cc0-120= sets all":
        "Ignora il reset per specifici CC (sintassi: 'cc7=127 cc39=127' per volume massimo; -1 previene il reset, cc0-120= imposta tutti).",

    # [prefs_seek_help]
    "Define which areas of the REAPER window will trigger playback seek when clicked with the mouse.":
        "Definisce quali aree della finestra di REAPER attivano il posizionamento della riproduzione (seek) al clic del mouse.",
    "Seek playback when clicking on media items, but only if the mouse modifier moves the edit cursor.":
        "Sposta la riproduzione al clic sugli item multimediali, ma solo se il modificatore del mouse sposta il cursore di modifica.",
    "By default, playback will seek to the loop start or end point when you edit that point, and repeat is enabled.":
        "Per impostazione predefinita, la riproduzione si sposta all'inizio o alla fine del loop quando ne modifichi il punto e il loop è attivo.",
    "How far before the loop start or end playback should begin, when seeking is triggered by a loop point edit.":
        "Anticipo rispetto all'inizio o fine del loop con cui avviare la riproduzione quando il seek è attivato dalla modifica di un punto di loop.",
    "By default, playback will not seek to a media item when you edit that item's position, length, or fade-in/fade-out.":
        "Per impostazione predefinita, la riproduzione non si sposta su un item multimediale quando ne modifichi posizione, lunghezza o dissolvenze.",
    "How far before the media item end playback should begin, when seeking is triggered by a media item edit.":
        "Anticipo rispetto alla fine dell'item con cui avviare la riproduzione quando il seek è attivato dalla modifica dell'item.",
    "By default, if the project timebase is in beats, adjusting tempo (including tapping tempo) will preserve the beat-based playback position.":
        "Se il timebase di progetto è in battute, la regolazione del tempo (incluso il tap tempo) mantiene la posizione di riproduzione in battute.",
    "Smooth seek enables a more natural-sounding transition. This setting can also be toggled via the Actions list.":
        "Il posizionamento morbido (smooth seek) garantisce una transizione sonora più naturale; attivabile anche dalla lista Azioni.",
    "Wait until the current measure ends before changing the playback position, for a smoother sounding transition.":
        "Attende la fine della misura corrente prima di cambiare la posizione di riproduzione, per una transizione musicale fluida.",
    "This setting can be used to enable sequencing of audio blocks for live playback. Also search the Actions list for \\\"seek\\\".":
        "Questa impostazione consente di sequenziare blocchi audio per l'esecuzione dal vivo (cerca anche \"seek\" nella lista Azioni).",

    # [prefs_scrub_help]
    "Either the master mix, or only the selected tracks, may be scrubbed/jogged.":
        "Lo scrub/jog può agire sul mix master complessivo oppure solo sulle tracce selezionate.",
    "When scrubbing, the playback rate can be limited to 1.0 or slower.":
        "Durante lo scrub, la velocità di riproduzione può essere limitata a 1.0x o inferiore.",
    "When jogging, choose whether to limit the playback rate to 1x/2x/4x/8x":
        "Durante il jog, scegli se limitare la velocità di riproduzione a 1x/2x/4x/8x.",
    "Jog can respond more immediately to mouse/edit cursor moves.":
        "Il jog può rispondere in modo più istantaneo ai movimenti del mouse o del cursore di modifica.",
    "The jog rate can be limited to 1.0 or slower only when jogging near the playback cursor.":
        "La velocità di jog può essere limitata a 1.0x o inferiore solo quando ci si muove vicino al cursore di riproduzione.",
    "Scrub/jog can be disabled while playing back, or enabled, in which case normal playback will stop when scrub/jog is engaged.":
        "Lo scrub/jog può essere disabilitato durante il playback, oppure abilitato interrompendo la riproduzione normale all'attivazione.",
    "When enabled, plays a one-shot segment when adjusting item and time selection edges (via mouse or action), to either begin or end at the edited edge.":
        "Se abilitato, riproduce un breve segmento audio durante la regolazione dei bordi di item o selezioni temporali (in inizio o in fine bordo).",
    "Set the bounds of the looped section, when scrubbing or jogging in looped-segment mode.":
        "Imposta i limiti della sezione in loop durante lo scrub o il jog in modalità a segmento ciclico.",
    "Adjust the sensitivity and responsiveness when scrubbing via a controller.":
        "Regola la sensibilità e la prontezza di risposta quando si effettua lo scrub tramite un controller esterno.",
    "Moving the edit cursor via an action or when using a control surface can jog/scrub audio, or simply move the cursor.":
        "Lo spostamento del cursore di modifica tramite azione o superficie di controllo può riprodurre audio (jog/scrub) o muovere solo il cursore.",
    "When checked, scrubbing by moving the edit cursor will use a one-shot segment playback rather than a tape-scrub. There is an action to toggle this.":
        "Se selezionato, lo scrub da movimento del cursore usa la riproduzione di un segmento one-shot anziché l'emulazione a nastro.",
    "The settings on this page control how jog/scrub works. See Editing Behavior/Mouse Modifiers to control when jog/scrub happens.":
        "Queste impostazioni controllano la modalità operativa di jog/scrub. Per definire quando si attiva, vedi Comportamento di modifica/Modificatori mouse.",
    "Adjust the volume of scrub/jog by this amount.":
        "Regola il volume di ascolto dello scrub/jog di questa quantità in dB.",

    # [prefs_REPLACEME_help]
    "text":
        "testo"
}
