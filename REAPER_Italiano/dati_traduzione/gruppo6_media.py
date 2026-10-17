# gruppo6_media.py — Traduzioni overlay spiegazioni: Media, Picchi, Dissolvenze, Corsie, Pulsanti item, Testo/Etichette, Default item (127 voci)

TRADUZIONI_G6 = {
    # [prefs_media_help]
    "Sets project media inactive when REAPER is inactive, so that other programs can access/modify the media.":
        "Imposta i file multimediali come inattivi (offline) quando REAPER non è in primo piano, consentendo ad altri programmi di accedervi o modificarli.",
    "Allows video items (and certain audio items decoded by VLC/FFmpeg, and still images) to be set offline, which can be slow to bring back online.":
        "Consente di mandare offline anche gli item video (e alcuni file decodificati da VLC/FFmpeg o immagini fisse), il cui ripristino online può risultare più lento.",
    "Allow choosing the filename used when using \\\"open copy\\\" action. If unchecked, the default filename will be used.":
        "Consente di scegliere il nome file durante l'azione \"Apri copia\"; se deselezionato, viene utilizzato il nome file predefinito.",
    "When using apply FX action, allow this much extra time at the end for reverb tails, delay lines, etc.":
        "Tempo di coda aggiuntivo (in ms) al termine dell'item durante l'azione 'Applica FX', per catturare code di riverbero, delay, ecc.",
    "When using the batch converter or various render/apply FX actions with per-item/take FX, add this much time past the item end for tails.":
        "Nel convertitore batch o nel rendering/applicazione di FX per-item o per-take, aggiunge questo tempo dopo la fine dell'item per le code sonore.",
    "When using take FX, duplicate take FX when splitting (so that new split items get copies of the FX). Caution, this can use a lot of RAM if you aren't careful.":
        "Negli FX per-take, duplica la catena FX al momento della divisione dell'item (ogni nuovo item riceve una copia degli FX; attenzione all'uso di RAM).",
    "If project media is set inactive when REAPER is inactive, having this checked will cause peaks to be rebuilt on demand if necessary.":
        "Se i media sono inattivi quando REAPER è in background, questa opzione ricostruisce i file di picco su richiesta se necessario.",
    "Generate item peak cache files on file import (recommended).":
        "Genera i file di cache dei picchi (.reapeaks) all'importazione dei file (consigliato).",
    "Generate item peak cache files on project load (recommended).":
        "Genera i file di cache dei picchi al caricamento del progetto (consigliato).",
    "Display a status window when generating peaks.":
        "Mostra una finestra di avanzamento durante la generazione dei file di picco.",
    "The highest resolution peaks generated in peak cache files. 300 is recommended. Higher or lower can result in diminished performance in different scenarios.":
        "Risoluzione massima dei picchi generati nei file di cache (consigliato 300; valori diversi possono ridurre le prestazioni a seconda dello scenario).",
    "If unable to write to the media directory, use the alternate path (set in Preferences/General/Path) to store peak cache files.":
        "Se non è possibile scrivere nella cartella dei media, memorizza i file di picco nel percorso alternativo (definito in Preferenze/Generale/Percorsi).",
    "Prefers to store newly created peak cache files in a directory named \\\"peaks\\\" relative to the media file.":
        "Memorizza i nuovi file di picco in una sottocartella denominata \"peaks\" all'interno della cartella dei file multimediali.",
    "Enabled by default, prevents generating enhanced peaks when in plain peaks mode, which is faster and produces smaller peak files.":
        "Attivo per impostazione predefinita: evita di generare picchi avanzati in modalità picchi standard, velocizzando il rendering e riducendo i file.",
    "If enabled, do not generate spectral peak information unless actually in spectral peak mode (potentially requiring a peaks rebuild).":
        "Se abilitato, non genera informazioni di picco spettrale se non quando è attiva la modalità spettrale (potrebbe richiedere la ricostruzione dei picchi).",
    "Enabled by default, do not generate spectrogram information unless actually viewing spectrogram.":
        "Attivo per impostazione predefinita: genera informazioni di spettrogramma solo quando la vista a spettrogramma è effettivamente attiva.",
    "Automatically re-generate peaks files if needed when enabling different display modes. If disabled, peaks files will need to be be explicitly re-generated.":
        "Rigenera automaticamente i file di picco al cambio di modalità di visualizzazione; se disabilitato, la rigenerazione dovrà essere eseguita manualmente.",
    "Allow REAPER to generate peaks for multiple files at once, which is faster but uses more CPU cores.":
        "Consente a REAPER di generare i file di picco per più file contemporaneamente, sfruttando più core CPU per completare l'operazione più rapidamente.",
    "Chooses which item peaks are built first. The default is to calculate the longest items first, which will minimize the total time when used with parallel building.":
        "Sceglie quali picchi calcolare per primi (per impostazione predefinita si elaborano prima gli item più lunghi, ottimizzando i tempi su CPU multi-core).",
    "Require manual rebuild of peaks when media file timestamps change, this can fix issues with cloud-synchronized disks/folders.":
        "Richiede la ricostruzione manuale dei picchi al variare della data/ora del file (risolve problemi di sincronizzazione su cloud o cartelle condivise).",

    # [prefs_mediapeaks_help]
    "Draw peaks (graphical representation of audio loudness and MIDI notes) for media items.":
        "Disegna i picchi (rappresentazione grafica del livello audio e delle note MIDI) per gli item multimediali.",
    "Draw approximate peaks for media items that are currently being recorded.":
        "Disegna forme d'onda approssimate per gli item attualmente in fase di registrazione.",
    "Only draw peaks for selected media items.":
        "Disegna le forme d'onda dei picchi solo per gli item multimediali selezionati.",
    "Only draw peaks for tracks and items that are soloed or not muted (only for audio and MIDI that will be heard during playback).":
        "Disegna i picchi solo per tracce e item in solo o non silenziati (mostrando solo l'audio e il MIDI udibili durante la riproduzione).",
    "Draw faint audio peaks/waveforms and MIDI notes in folder tracks, to represent the contents of the child tracks.":
        "Mostra forme d'onda e note MIDI attenuate nelle tracce cartella, per visualizzare il contenuto delle tracce figlie sottostanti.",
    "Draw faint audio peaks/waveforms and MIDI notes in envelope lanes, for easier timing adjustment.":
        "Mostra forme d'onda e note MIDI attenuate nelle corsie degli inviluppi, agevolando l'allineamento temporale dell'automazione.",
    "Draw a colored edge (defined in the color theme) around media item peaks. Color theme may override this preference.":
        "Disegna un bordo colorato (definito dal tema) attorno ai picchi degli item (il tema visivo può prevalere su questa opzione).",
    "Draw a colored edge (defined in the color theme) around media item waveforms. Color theme may override this preference.":
        "Disegna un bordo colorato (definito dal tema) attorno alle forme d'onda degli item (il tema visivo può prevalere su questa opzione).",
    "Draw smooth audio peaks and waveforms. Color theme may override this preference.":
        "Disegna picchi e forme d'onda audio con rendering smussato (il tema visivo può prevalere su questa opzione).",
    "The method used to draw the most zoomed-in audio view (when the exact location of each sample is drawn).":
        "Metodo impiegato per visualizzare l'audio al massimo livello di zoom (quando viene mostrata la posizione esatta dei singoli campioni).",
    "Draw the zero line overlaid on the audio peaks (otherwise the zero line is hidden behind the audio).":
        "Disegna la linea dello zero sovrapposta alle forme d'onda audio (altrimenti rimane nascosta dietro la visualizzazione dell'onda).",
    "Adjust audio peak drawing to reflect any track or take envelope that will affect the audio item before FX are applied.":
        "Aggiorna il disegno dei picchi riflettendo le variazioni degli inviluppi di traccia o di take che agiscono prima degli FX.",
    "Draw a colored edge (defined in the color theme) around MIDI notes in media items. Color theme may override this preference.":
        "Disegna un bordo colorato (definito dal tema) attorno alle note MIDI negli item (il tema visivo può prevalere su questa opzione).",
    "Choose how many of the CC/channel pressure/pitch lanes that are visible in the MIDI editor to display in the arrange view.":
        "Stabilisce quante corsie CC, Channel Pressure o Pitch visibili nell'editor MIDI mostrare all'interno della vista Arrange.",
    "Choose whether media item waveform peaks are tinted by custom track, item, or take colors.":
        "Stabilisce se i picchi della forma d'onda degli item vengono colorati con le tinte personalizzate di traccia, item o take.",
    "Choose whether media item backgrounds are tinted by custom track, item, or take colors.":
        "Stabilisce se lo sfondo degli item multimediali viene colorato con le tinte personalizzate di traccia, item o take.",
    "Tint media item waveform peaks by the custom track color, if any. Color theme may override this preference.":
        "Colora i picchi della forma d'onda con il colore personalizzato della traccia (il tema visivo può prevalere su questa opzione).",
    "Tint media item waveform peaks by the custom item color, if any. This overrides a custom track color. Color theme may override this preference.":
        "Colora i picchi della forma d'onda con il colore personalizzato dell'item (prevale sul colore della traccia).",
    "Tint media item waveform peaks by the custom take color, if any. This overrides a custom track or item color. Color theme may override this preference.":
        "Colora i picchi della forma d'onda con il colore personalizzato del take (prevale sui colori di traccia e item).",
    "Tint media item backgrounds by the custom track color, if any. Color theme may override this preference.":
        "Colora lo sfondo degli item con il colore personalizzato della traccia (il tema visivo può prevalere su questa opzione).",
    "Tint media item backgrounds by the custom item color, if any. This overrides a custom track color. Color theme may override this preference.":
        "Colora lo sfondo degli item con il colore personalizzato dell'item (prevale sul colore della traccia).",
    "Tint media item backgrounds by the custom take color, if any. This overrides a custom track or item color. Color theme may override this preference.":
        "Colora lo sfondo degli item con il colore personalizzato del take (prevale sui colori di traccia e item).",
    "How much custom color to blend into the selected media item background. Zero means do not use the custom color. Color theme may override this preference.":
        "Intensità di miscelazione del colore personalizzato sullo sfondo degli item selezionati (0 disabilita la colorazione personalizzata).",
    "How much custom color to blend into the unselected media item background. Zero means do not use the custom color. Color theme may override this preference.":
        "Intensità di miscelazione del colore personalizzato sullo sfondo degli item non selezionati (0 disabilita la colorazione personalizzata).",
    "Custom take colors override custom item colors, which override custom track colors. You can also set colors from the track and item context menus.":
        "I colori personalizzati del take prevalgono su quelli dell'item, che a loro volta prevalgono su quelli di traccia (modificabili dal menu contestuale).",
    "MIDI program names and text events can be displayed or hidden in the arrange view.":
        "I nomi dei Program Change MIDI e gli eventi di testo possono essere mostrati o nascosti nella vista Arrange.",
    "Hide media item peaks display when the media item height is less than this threshold.":
        "Nasconde la visualizzazione dei picchi quando l'altezza verticale dell'item scende sotto questa soglia in pixel.",
    "Enable high-resolution spectrogram view when in spectrogram mode, if the item is sufficiently zoomed-in.":
        "Abilita la visualizzazione a spettrogramma in alta risoluzione (quando attiva la modalità spettrogramma e con zoom ravvicinato).",
    "Maximum arrange view width (in seconds) where high-resolution spectrogram will be used. When zoomed out to viewing more than about 20 seconds, calculating high-resolution spectrogram can be very slow.":
        "Larghezza massima della vista Arrange (in secondi) per l'uso dello spettrogramma HD (con zoom oltre i 20 secondi il calcolo può rallentare).",
    "Minimum item height, as a percentage of the total arrange view height, where high-resolution spectrogram will be used, if enabled.":
        "Altezza minima dell'item (in percentuale rispetto alla vista Arrange) richiesta per attivare lo spettrogramma HD.",

    # [prefs_mediafades_help]
    "Edit the media item fade-in/out by grabbing a triangle in the corner of the media item.":
        "Modifica la dissolvenza in entrata/uscita (fade) afferrando il triangolo nell'angolo superiore dell'item multimediale.",
    "Edit overlapping media item fades (crossfades) by grabbing a diamond at the intersection of the fade curves.":
        "Modifica la dissolvenza incrociata (crossfade) tra item sovrapposti afferrando il rombo all'intersezione delle curve di fade.",
    "Edit media item fade curvature by grabbing a diamond displayed on the upper half of the fade curve.":
        "Modifica la curvatura della dissolvenza afferrando il rombo posizionato sulla metà superiore della curva di fade.",
    "Edit media item fade S-curvature by grabbing a diamond displayed on the bottom half of the fade curve.":
        "Modifica la curvatura a 'S' della dissolvenza afferrando il rombo posizionato sulla metà inferiore della curva di fade.",
    "Hide fade curve handles when the fade (not the item) is small to prevent accidentally grabbing them with the mouse.":
        "Nasconde le maniglie della curva quando la dissolvenza è molto corta, per evitare trascinamenti accidentali con il mouse.",
    "Prevent accidentally editing media item fade-in/out when the media item is small.":
        "Impedisce modifiche accidentali alle dissolvenze quando l'item multimediale ha dimensioni visive ridotte.",
    "Allow the mouse to target the fade curve itself. The top edge of the fade start/end line (where the fade handle is drawn) can always be targeted.":
        "Consente al puntatore del mouse di agganciare direttamente la curva di dissolvenza (la maniglia superiore rimane sempre agganciabile).",
    "Allow the mouse to target the fade start/end line. The top edge of the fade start/end line (where the fade handle is drawn) can always be targeted.":
        "Consente al puntatore del mouse di agganciare la linea di inizio/fine della dissolvenza.",
    "Allow the mouse to target the bottom half of the fade curve to edit S-curvature for all fade shapes, when mouse modifier set to \\\"adjust fade curve\\\".":
        "Consente di agganciare la metà inferiore della curva per modificare la curvatura a S su tutte le forme di dissolvenza con il modificatore dedicato.",
    "Crossfades are drawn with custom theme colors when using the crossfade editor. These colors can be used when editing crossfades with the mouse.":
        "Le dissolvenze incrociate usano i colori del tema durante l'uso del Crossfade Editor; questi colori possono essere usati anche nell'editing con mouse.",
    "When using the crossfade editor, display the item in the arrange view using custom theme colors for the entire item, or just the crossfaded area.":
        "Nell'uso del Crossfade Editor, mostra l'item nella vista Arrange con i colori del tema per l'intero item o solo per l'area incrociata.",

    # [prefs_medialanes_help]
    "When offsetting overlapping media items vertically, offset by this amount. Can be greater than 100.":
        "Distanza di sfalsamento verticale tra item multimediali sovrapposti (può superare 100 per una separazione più marcata).",
    "When offsetting overlapping media items vertically, draw overlapping items as opaque.":
        "Nello sfalsamento verticale, disegna gli item sovrapposti come opachi anziché semitrasparenti.",
    "When offsetting overlapping media items vertically, display earlier-created items above later-created items.":
        "Nello sfalsamento verticale, posiziona gli item creati per primi sopra quelli creati successivamente.",
    "Where to center when zooming vertically.":
        "Punto di ancoraggio centrale per lo zoom verticale.",
    "Maximum vertical zoom. If greater than 100%, tracks may be taller than the visible arrange view height.":
        "Livello massimo di zoom verticale. Se superiore al 100%, le singole tracce possono superare l'altezza visibile della vista Arrange.",
    "When zooming vertically, envelope lane height is set to a percentage of the track height. 0% means vertical zoom does not affect envelope lanes.":
        "Nello zoom verticale, l'altezza delle corsie inviluppo è proporzionale a quella della traccia (0% esclude le corsie inviluppo dallo zoom verticale).",
    "Where to center when zooming horizontally.":
        "Punto di ancoraggio centrale per lo zoom orizzontale.",
    "By default, horizontal zoom/scroll is limited to the start of the project, preventing the display of negative dead space.":
        "Per impostazione predefinita, lo zoom e lo scorrimento orizzontale sono bloccati all'inizio del progetto, evitando spazio vuoto a valori temporali negativi.",
    "When scrolling or auto-scrolling vertically, the maximum step size can be customized for a slower or faster scroll.":
        "Passo massimo per lo scorrimento o l'auto-scorrimento verticale, personalizzabile per uno scorrimento più fluido o più veloce.",
    "Enable or disable vertical zoom for tracks that are pinned in the arrange view.":
        "Abilita o disabilita lo zoom verticale per le tracce bloccate (pinned) nella vista Arrange.",

    # [prefs_mediabuttons_help]
    "Display a lock button when items are locked.":
        "Mostra il pulsante di blocco (lucchetto) quando gli item sono bloccati.",
    "Display an unlit lock button when items are not locked.":
        "Mostra il pulsante di blocco non illuminato quando gli item non sono bloccati.",
    "Display an FX button when items have per-take FX.":
        "Mostra il pulsante FX quando l'item contiene effetti (FX) per-take.",
    "Display an unlit FX button when items have no per-take FX.":
        "Mostra il pulsante FX non illuminato quando l'item non contiene FX per-take.",
    "Display an envelopes button when items have per-take automation envelopes.":
        "Mostra il pulsante degli inviluppi quando l'item contiene inviluppi di automazione per-take.",
    "Display an unlit envelopes button when items have no active per-take automation envelopes.":
        "Mostra il pulsante degli inviluppi non illuminato quando non vi sono inviluppi per-take attivi.",
    "Display a mute button when items are muted.":
        "Mostra il pulsante di silenziamento (mute) quando l'item è in mute.",
    "Display an unlit mute button when items are not muted.":
        "Mostra il pulsante di silenziamento non illuminato quando l'item non è in mute.",
    "Display a notes button when an item has text or image notes attached.":
        "Mostra il pulsante delle note quando all'item sono allegate note di testo o immagini.",
    "Display an unlit notes button when an item has no text or image notes attached.":
        "Mostra il pulsante delle note non illuminato quando non vi sono note allegate.",
    "Display a properties button (which opens the Item Properties dialog) for all media items. The button will light if the item is resampled.":
        "Mostra il pulsante delle proprietà (apre Proprietà item) su tutti gli item; si illumina se l'audio è ricampionato.",
    "Display a properties button (which opens the Item Properties dialog) for resampled media items only.":
        "Mostra il pulsante delle proprietà solo per gli item multimediali ricampionati.",
    "Display a properties button (which opens the Item Properties dialog) for phase inverted media items only.":
        "Mostra il pulsante delle proprietà solo per gli item multimediali con fase invertita.",
    "Display a group button when an item is grouped with other items (the button will light when an item in the group is selected).":
        "Mostra il pulsante di gruppo quando l'item è raggruppato con altri (si illumina selezionando un elemento del gruppo).",
    "Display a pool button when an item's active take shares pooled MIDI source data with other media items.":
        "Mostra il pulsante pool quando il take attivo condivide dati sorgente MIDI collegati con altri item.",
    "Display a button to indicate the effective media item timebase. Timebase can be set in project settings, per-track, or in media item properties.":
        "Mostra un pulsante per indicare il timebase effettivo dell'item (impostabile nel progetto, per traccia o nelle proprietà dell'item).",
    "Media items can have a volume handle with with +0dB being the top or the center of the item, or a volume knob, or both.":
        "Gli item possono includere una maniglia del volume (+0 dB in alto o al centro), una manopola del volume o entrambi.",
    "When labels are drawn within the media item rather than above, hide media item buttons (except lock button) when the media item is too small.":
        "Quando le etichette sono disegnate all'interno dell'item, nasconde i pulsanti (eccetto il blocco) se l'item è troppo piccolo.",

    # [prefs_mediavu_help]
    "Write the name of each media item at the top of the item.":
        "Scrive il nome di ciascun item multimediale nella parte superiore dell'item.",
    "If a media item has any pitch or playrate adjustment, write the adjustment on the item.":
        "Se l'item ha regolazioni di pitch o velocità di riproduzione (playrate), mostra il valore sull'item.",
    "If a media item has per-item or per-take gain adjustment, write the adjustment on the item.":
        "Se l'item ha regolazioni di guadagno per-item o per-take, mostra la modifica sull'item.",
    "Draw media item labels above the top of media items (for an info-strip appearance) rather than within the item.":
        "Disegna le etichette sopra la sommità degli item (in stile striscia informativa) anziché all'interno dell'item.",
    "Make sure media item labels are visible even if the start of the item (where the label would normally be shown) is offscreen.":
        "Mantiene visibile l'etichetta dell'item anche quando l'inizio dell'item si trova fuori dall'area visibile dello schermo.",
    "Draw a solid colored background behind the media item label text, so it can be easily read.":
        "Disegna uno sfondo colorato opaco dietro al testo dell'etichetta per garantirne la massima leggibilità.",
    "Do not draw media item text labels when the height of the media item, or the specific take, is too small.":
        "Non disegna le etichette di testo quando l'altezza verticale dell'item o del take è troppo ridotta.",
    "Draw full text labels for item pitch and playrate adjustments (when enabled).":
        "Mostra etichette descrittive estese per le regolazioni di intonazione (pitch) e velocità di riproduzione.",
    "Draw abbreviated text labels for item pitch and playrate adjustments (when enabled).":
        "Mostra etichette abbreviate per le regolazioni di intonazione e velocità di riproduzione.",
    "Draw no text labels, just numbers, for item pitch and playrate adjustments (when enabled).":
        "Mostra solo i valori numerici per le regolazioni di pitch e velocità, senza testo descrittivo.",
    "Draw a themed indicator on selected media items. The default indicator is a small dot.":
        "Disegna un indicatore grafico del tema sugli item selezionati (l'indicatore predefinito è un puntino).",
    "Limit take/transient handle width to a minimum of a DPI-adjusted pixel size (6 default), or a percentage of take height (12% default).":
        "Limita la larghezza delle maniglie di take/transienti a una dimensione minima in pixel adattata ai DPI (default 6) o a una percentuale dell'altezza (default 12%).",
    "When recording, automatically apply the same random color to all takes created in the same recording pass, or all media items in the same fixed lane.":
        "Durante la registrazione, assegna lo stesso colore casuale a tutti i take registrati nella stessa passata o a tutti gli item della stessa corsia fissa.",
    "Automatically apply the same random color to all MIDI media items that share the same pooled MIDI source data, as they are created.":
        "Assegna automaticamente lo stesso colore casuale a tutti gli item MIDI che condividono i medesimi dati sorgente collegati (pool).",
    "Draw item backgrounds less precisely when updating the arrange view, can improve performance significantly with some themes.":
        "Disegna lo sfondo degli item in modo meno rifinito durante gli aggiornamenti della vista Arrange (può velocizzare sensibilmente la grafica con certi temi).",
    "Disable macOS retina for arrange view, which can speed up drawing on larger retina displays.":
        "Disabilita la modalità Retina di macOS per la vista Arrange, accelerando il rendering grafico sui monitor Retina di grandi dimensioni.",

    # [prefs_itemdefs_help]
    "The default fade-in/fade-out length.":
        "Lunghezza predefinita della dissolvenza in entrata e in uscita (fade-in / fade-out).",
    "The default crossfade length.":
        "Lunghezza predefinita della dissolvenza incrociata (crossfade).",
    "The default fade-in/fade-out shape.":
        "Forma della curva predefinita per le dissolvenze in entrata e in uscita.",
    "The default crossfade shape.":
        "Forma della curva predefinita per le dissolvenze incrociate (crossfade).",
    "Automatically fade-in/fade-out imported media items.":
        "Applica automaticamente una dissolvenza in entrata/uscita agli item multimediali importati.",
    "Automatically fade-in/fade-out newly recorded media items.":
        "Applica automaticamente una dissolvenza in entrata/uscita ai nuovi item multimediali registrati.",
    "Overlap and crossfade when a new recording overlaps existing media items.":
        "Sovrapponi e applica una dissolvenza incrociata (crossfade) quando una nuova registrazione si sovrappone a item esistenti.",
    "Automatically fade-in/fade-out when an edit creates a new media item edge.":
        "Applica automaticamente dissolvenze quando un'operazione di editing crea un nuovo bordo sull'item.",
    "Overlap and crossfade when splitting media items.":
        "Sovrapponi e applica una dissolvenza incrociata durante la divisione (split) degli item multimediali.",
    "Crossfade to the left, right, or center when splitting media items.":
        "Allinea la dissolvenza incrociata a sinistra, a destra o al centro del punto di divisione degli item.",
    "Automatically fade-in/fade-out/crossfade comp areas when comping in fixed lanes.":
        "Applica automaticamente dissolvenze e crossfade alle aree di comping nelle corsie fisse.",
    "Overlap and crossfade when editing with 'trim content behind media items' enabled.":
        "Sovrapponi e applica crossfade durante le modifiche con 'Rifila contenuti dietro gli item' abilitato.",
    "Overlap and crossfade when editing with 'trim content behind razor edits' enabled.":
        "Sovrapponi e applica crossfade durante le modifiche con 'Rifila contenuti dietro le modifiche razor' abilitato.",
    "When splits create fades/crossfades, limit the fade length in pixels. Otherwise, the fade length is limited to a percentage of the visible arrange view area.":
        "Quando la divisione crea dissolvenze, limita la lunghezza del fade in pixel (altrimenti è limitata a una percentuale dell'area visibile in Arrange).",
    "Right-click a fade or crossfade to change the fade shape. For a crossfade, right-click can change the shape of both sides, or one side only.":
        "Fai clic con il tasto destro su una dissolvenza per cambiarne la forma; per un crossfade, può modificare entrambi i lati o un lato singolo.",
    "Apply the above fade/crossfade settings, and the project auto-crossfade setting, to MIDI items. Fades on MIDI items affect note velocities, not MIDI volume.":
        "Applica le impostazioni di dissolvenza/crossfade agli item MIDI (sui file MIDI le dissolvenze scalano le velocity delle note, non il volume CC).",
    "Default stretch marker crossfade size for new items. Change existing items via media item properties.":
        "Dimensione predefinita del crossfade per gli stretch marker sui nuovi item (modificabile sugli item esistenti da Proprietà item).",

    # [prefs_itemloopdefs_help]
    "Enable the \\\"loop source\\\" attribute for imported media items. Dragging the right edge of the item will automatically loop the media.":
        "Abilita l'attributo \"Sorgente ciclica (loop)\" per gli item importati: trascinando il bordo destro l'item ripeterà il file in loop.",
    "Enable the \\\"loop source\\\" attribute for new MIDI items. Dragging the right edge of the item will automatically loop the media.":
        "Abilita l'attributo \"Sorgente ciclica (loop)\" per i nuovi item MIDI: trascinando il bordo destro l'item si ripeterà in loop.",
    "Enable the \\\"loop source\\\" attribute for recorded audio items. Dragging the right edge of the item will automatically loop the media.":
        "Abilita l'attributo \"Sorgente ciclica (loop)\" per gli item audio registrati: trascinando il bordo destro l'audio si ripeterà in loop.",
    "Enable the \\\"loop source\\\" attribute for glued items. Dragging the right edge of the item will automatically loop the media.":
        "Abilita l'attributo \"Sorgente ciclica (loop)\" per gli item consolidati (glue): trascinando il bordo destro l'audio si ripeterà in loop.",
    "When auto-punch recording into a time selection, loop the time selection's content when extending the edges of the resulting item.":
        "Durante la registrazione auto-punch in selezione temporale, ripete il contenuto della selezione quando si allargano i bordi dell'item risultante."
}
