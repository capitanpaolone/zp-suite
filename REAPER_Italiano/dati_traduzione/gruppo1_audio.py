# gruppo1_audio.py — Traduzioni overlay spiegazioni: Audio, Periferiche, Buffering, Mute/Solo (68 voci)

TRADUZIONI_G1 = {
    # [prefs_audio_help]
    "When enabled, REAPER will share audio devices with other applications by closing the audio hardware not active.":
        "Quando abilitato, REAPER condivide le periferiche audio con le altre applicazioni chiudendo l'hardware audio quando non è attivo.",
    "When unchecked and any tracks are record armed, then REAPER will not share audio devices.":
        "Se deselezionato e vi sono track armate per la registrazione, REAPER non condividerà le periferiche audio.",
    "When unchecked and any ReWire devices are in use, then REAPER will not share audio devices.":
        "Se deselezionato e vi sono periferiche ReWire in uso, REAPER non condividerà le periferiche audio.",
    "When checked, REAPER will close the audio devices whenever not playing back audio. ":
        "Se selezionato, REAPER chiude le periferiche audio ogni volta che non è in riproduzione audio.",
    "Warn about audio devices that could not be opened.":
        "Avvisa in caso di periferiche audio che non è stato possibile aprire.",
    "Warn about MIDI devices that could not be opened.":
        "Avvisa in caso di periferiche MIDI che non è stato possibile aprire.",
    "Warn about MIDI devices that are enabled but could not be found.":
        "Avvisa in caso di periferiche MIDI abilitate ma non rilevate.",
    "When auto-bypass is enabled in project settings or per-plug-in, this allows plug-ins to be auto-bypassed while the plug-in UI is open.":
        "Quando l'auto-bypass è abilitato nelle impostazioni di progetto o per singolo plug-in, consente di mandare in auto-bypass i plug-in anche con l'interfaccia aperta.",
    "Automatically disable oversampling on tracks that are record armed or receive from armed tracks. Oversampling changes only on playback start/stop.":
        "Disabilita automaticamente l'oversampling sulle track armate per la registrazione o che ricevono da track armate. L'oversampling cambia solo all'avvio/arresto della riproduzione.",
    "Enables audio input name aliasing, letting you rename your inputs for easier selection.":
        "Abilita gli alias per i nomi degli ingressi audio, consentendo di rinominare gli ingressi per una selezione più immediata.",
    "Enables audio output name aliasing, letting you rename your outputs for easier selection.":
        "Abilita gli alias per i nomi delle uscite audio, consentendo di rinominare le uscite per una selezione più immediata.",
    "When checked, allows you to treat odd pairs of inputs/outputs as stereo pairs, i.e. not just Channels 1/2, but 2/3 as well.":
        "Se selezionato, consente di trattare coppie dispari di ingressi/uscite come coppie stereo, ad es. non solo i canali 1/2, ma anche 2/3.",
    "Sets default output for metronome when project does not override -- default is project master outputs":
        "Imposta l'uscita predefinita per il metronomo quando il progetto non ne specifica una (predefinita: uscite master del progetto).",
    "If checked, audio processing and output will be bypassed if a disk write error warning occurs (in order to draw attention to the issue)":
        "Se selezionato, l'elaborazione e l'uscita audio vengono bypassate in caso di errore di scrittura su disco (per segnalare immediatamente il problema).",
    "REAPER can support up to 128 virtual hardware loopback audio channels which can be used to route audio between projects.":
        "REAPER può gestire fino a 128 canali audio virtuali di loopback hardware, utilizzabili per instradare l'audio tra progetti diversi.",
    "When checked, plug-ins with more than this PDC amount will by auto-bypassed when record-armed, reducing monitoring latency/improving performance.":
        "Se selezionato, i plug-in con compensazione del ritardo (PDC) superiore a questo valore vengono bypassati automaticamente all'armo della traccia, riducendo la latenza di monitoraggio.",
    "PDC auto-bypass only while recording, PDC FX will be active in stop/playback. This can result in glitches when punch-in recording.":
        "Auto-bypass PDC solo durante la registrazione; i plug-in con PDC resteranno attivi in stop/riproduzione. Può causare artefatti durante il punch-in.",

    # [prefs_audiodev_help]
    "Select your desired input device here.":
        "Seleziona qui la periferica di ingresso desiderata.",
    "Select your desired output device here.":
        "Seleziona qui la periferica di uscita desiderata.",
    "Select the desired bit depth that will be used for recordings.":
        "Seleziona la profondità di bit desiderata per le registrazioni.",
    "Enter a value into this field to set the number of input channels.":
        "Inserisci un valore in questo campo per impostare il numero di canali di ingresso.",
    "Enter a value into this field to set the number of output channels.":
        "Inserisci un valore in questo campo per impostare il numero di canali di uscita.",
    "Enter a value into this field to set the sample rate that will be used for recordings.":
        "Inserisci un valore in questo campo per impostare la frequenza di campionamento (sample rate) per le registrazioni.",
    "This section allows you to alter the buffer settings for REAPER. A larger buffer will give more stable performance on some systems, at the expense of latency.":
        "Questa sezione consente di modificare le impostazioni del buffer di REAPER. Un buffer più grande offre prestazioni più stabili, a scapito della latenza.",
    "Choose your desired audio system here. By default, REAPER uses WaveOut for compatibility, but ASIO is recommended for best performance.":
        "Scegli qui il sistema audio desiderato. Per impostazione predefinita REAPER usa WaveOut per compatibilità, ma si raccomanda ASIO (o CoreAudio su macOS) per prestazioni ottimali.",
    "If checked, the audio device system will use the project sample rate.":
        "Se selezionato, il sistema audio utilizzerà la frequenza di campionamento (sample rate) del progetto.",
    "Choose the priority for the main audio thread. ":
        "Scegli la priorità per il thread audio principale. ",

    # [prefs_audiodev_asio_help]
    "Select your desired ASIO driver here.":
        "Seleziona qui il driver ASIO desiderato.",
    "ASIO inputs are enabled by default. Clearing this check box will disable the inputs on your ASIO device, which can lower the load on your CPU.":
        "Gli ingressi ASIO sono abilitati per impostazione predefinita. Deselezionando questa casella si disabilitano gli ingressi della periferica ASIO, riducendo il carico sulla CPU.",
    "Select which input to use as the first of the input range.":
        "Seleziona quale ingresso usare come primo dell'intervallo di ingressi.",
    "Select which input to use as the last of the input range.":
        "Seleziona quale ingresso usare come ultimo dell'intervallo di ingressi.",
    "The Output range section operates in the same way as the input range section, allowing you to choose which ASIO outputs are accessible within REAPER.":
        "La sezione Intervallo uscite funziona come quella degli ingressi, consentendo di scegliere quali uscite ASIO sono accessibili in REAPER.",
    "Select which output to use as the first of the output range.":
        "Seleziona quale uscita usare come prima dell'intervallo di uscite.",
    "Select which output to use as the last of the output range.":
        "Seleziona quale uscita usare come ultima dell'intervallo di uscite.",
    "Click this button to open the Control Panel for your ASIO driver.":
        "Fai clic su questo pulsante per aprire il pannello di controllo del driver ASIO.",
    "Select this check box to request a specific sample rate for your audio device. If this option is not checked, then the soundcards current or default sample rate will be used.":
        "Seleziona questa casella per richiedere una frequenza di campionamento specifica alla periferica audio. Se deselezionata, verrà usata quella corrente della scheda audio.",
    "This option will zero the output buffers of the hardware BEFORE rendering to them, which on some hardware can reduce \\\"stuck buffer sounds\\\" in certain instances.":
        "Azzera i buffer di uscita dell'hardware PRIMA di renderizzarvi l'audio; su alcune schede riduce il rischio di residui sonori o rumori di buffer bloccato.",
    "Some buggy ASIO drivers might need this option for proper ASIO operation.":
        "Alcuni driver ASIO difettosi potrebbero richiedere questa opzione per funzionare correttamente.",

    # [prefs_buf_help]
    "Auto-detect the number of CPU cores in your system and use all of them.":
        "Rileva automaticamente il numero di core CPU del sistema e li utilizza tutti.",
    "The number of audio processing threads to create. This is usually set to the number of CPUs in your system.":
        "Numero di thread di elaborazione audio da creare. Di norma corrisponde al numero di core CPU presenti nel sistema.",
    "The relative thread priority to use for audio processing. This is an advanced performance tweak and should probably be left on the default.":
        "Priorità relativa dei thread da usare per l'elaborazione audio. È un'impostazione avanzata che si consiglia di lasciare al valore predefinito.",
    "How aggressive audio processing threads are. A more relaxed setting will use less CPU but will be less stable at low latencies.":
        "Livello di reattività dei thread di elaborazione audio. Un'impostazione più rilassata consuma meno CPU ma può risultare meno stabile a latenze basse.",
    "Media buffering uses RAM and CPU to avoid having to wait for disk IO. For systems with slower disks this should be set higher. Zero disables buffering.":
        "Il buffering dei media utilizza RAM e CPU per evitare attese di I/O dal disco. Su dischi più lenti è consigliabile un valore più alto. Zero disabilita il buffering.",
    "Disable buffering on tracks with MIDI editors open, which allows faster playback response to MIDI edits (recommended).":
        "Disabilita il buffering sulle track con editor MIDI aperto, consentendo una risposta più immediata alle modifiche MIDI (consigliato).",
    "How full source media buffers should be before starting playback. Lower numbers will give faster response time.":
        "Livello di riempimento dei buffer dei media sorgente prima di avviare la riproduzione. Valori più bassi garantiscono una risposta più rapida.",
    "When per-take FX are showing, use a lower media buffer size to minimize lag between audio playback and the visual response of the plugin.":
        "Quando sono visibili gli FX per-take, usa un buffer multimediale più piccolo per ridurre il ritardo tra la riproduzione audio e la risposta grafica del plug-in.",
    "Live FX multiprocessing allows live monitoring to be multiprocessed in addition to media/FX, but isn't ideal for low latency performance.":
        "Il multiprocessing per gli FX dal vivo elabora in parallelo anche il monitoraggio live, ma può non essere ideale per prestazioni a bassissima latenza.",
    "How many threads to use for Live FX multiprocessing.":
        "Numero di thread da utilizzare per il multiprocessing degli FX dal vivo.",
    "Use spare CPU to render FX ahead of time. This is beneficial regardless of CPU count, but may need to be disabled for use with some plug-ins (UAD).":
        "Utilizza la CPU residua per pre-renderizzare gli FX in anticipo. È vantaggioso con qualsiasi CPU, ma potrebbe dover essere disabilitato con alcuni plug-in (es. UAD).",
    "Higher render-ahead times will use multiple processors more efficiently.  Lower render-ahead times will lower response time for FX tweaks.":
        "Tempi di pre-rendering più alti sfruttano meglio i processori multipli. Tempi più bassi migliorano la reattività alle modifiche dei parametri FX.",
    "Use anticipative (render-ahead) processing on all tracks (even tracks without FX). This can help performance at the lowest latencies but uses more CPU.":
        "Usa l'elaborazione anticipata (pre-rendering) su tutte le track (anche senza FX). Può migliorare le prestazioni a latenze minime ma aumenta l'uso di CPU.",
    "Use anticipative (render-ahead) FX processing on tracks with open MIDI editors. Disable this for lower preview latency while editing.":
        "Usa l'elaborazione anticipata degli FX sulle track con editor MIDI aperto. Disabilita per avere minore latenza di anteprima durante l'editing.",
    "Use render-ahead on tracks that have automation write enabled. Disable this to improve the timing of recorded automation.":
        "Usa il pre-rendering sulle track con scrittura dell'automazione abilitata. Disabilita per migliorare la precisione temporale dell'automazione registrata.",
    "Advanced disk buffering options, only recommended for expert use.":
        "Opzioni avanzate di buffering del disco; consigliate solo a utenti esperti.",
    "Disable buffering on selected tracks, which allows faster audio playback response to edits.":
        "Disabilita il buffering sulle track selezionate per velocizzare la risposta audio alle modifiche.",

    # [prefs_audio_mutesolo_help]
    "Do not process tracks that are muted, allowing less CPU/disk usage for these tracks. Unmuting may not be instant with this checked.":
        "Non elabora le track in mute, riducendo l'uso di CPU e disco per tali track. La riattivazione del suono potrebbe non essere istantanea.",
    "Muted tracks that have their FX UIs visible will still be processed unless this option is checked.":
        "Le track in mute con interfaccia FX aperta continuano a essere elaborate, a meno che questa opzione non sia selezionata.",
    "Makes soloing a track also solo the routing of that track, Toggle which behavior is used by holding alt while clicking a solo button.":
        "Mettere in solo una track mette in solo anche il suo instradamento (routing). Tieni premuto Alt/Option mentre fai clic su Solo per invertire il comportamento.",
    "Enable to make pre-fader sends still be active when their track is muted.":
        "Abilita per mantenere attive i send pre-fader anche quando la track è in mute.",
    "Enable to make pre-fader hardware outputs still be active when their track is muted or another track is soloed.":
        "Abilita per mantenere attive le uscite hardware pre-fader anche se la track è in mute o un'altra track è in solo.",
    "The master track, or any track, can be automatically muted (like a circuit breaker) when the volume exceeds a certain level, to protect speakers and ears.":
        "La track master o qualsiasi track può essere messa automaticamente in mute (come un salvavita) quando il segnale supera una soglia, proteggendo diffusori e udito.",
    "Reset auto-muted tracks when starting playback":
        "Ripristina le track messe in auto-mute all'avvio della riproduzione",
    "If solo in front is enabled (via options menu or action), dim unsoloed tracks by this amount.":
        "Se il 'Solo in front' è attivo (dal menu Opzioni o tramite azione), attenua le track non in solo di questo valore in dB.",
    "Apply a small fade to mutes to avoid clicks, this controls how long that fade is. Must be no more than 100ms.":
        "Applica una micro-dissolvenza al mute per evitare click; questo valore ne controlla la durata (massimo 100 ms).",
    "If a soloed-in-place track sends to a soloed track, this option makes the parent/hardware sends effectively unsoloed.":
        "Se una track con solo-in-place invia a una track in solo, questa opzione rende le uscite parent/hardware effettivamente non soliste.",
    "If enabled, soloed tracks do not affect the master mix, instead solo is routed via a dedicated solo bus.":
        "Se abilitato, le track in solo non modificano il mix master; il segnale di solo viene invece instradato attraverso un bus di solo dedicato.",
    "If dedicated solo bus is enabled, controls whether the master fader affects the solo bus.":
        "Se il bus di solo dedicato è abilitato, stabilisce se il fader master controlla anche il bus di solo.",
    "Show metering on tracks even if another track is soloed, when project is dedicated solo bus mode.":
        "Mostra i meter sulle track anche se un'altra track è in solo, quando il progetto usa la modalità con bus di solo dedicato."
}
