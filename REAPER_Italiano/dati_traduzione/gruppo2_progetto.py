# gruppo2_progetto.py — Traduzioni overlay spiegazioni: Generale, Progetto, Percorsi (60 voci)

TRADUZIONI_G2 = {
    # [prefs_gen_help]
    "The number of projects displayed in the \\\"Recent Projects\\\" menu and prompt can be limited.":
        "È possibile limitare il numero di progetti visualizzati nel menu e nella finestra di dialogo \"Progetti recenti\".",
    "The way files are listed in the \\\"Recent Projects\\\" menu and prompt can be customized, and the list can be reset.":
        "È possibile personalizzare il modo in cui i file compaiono nel menu e nella finestra \"Progetti recenti\", o azzerare l'elenco.",
    "Select the project(s) to open on startup. Override this option by holding Shift (new project, default template) or Cmd+Shift (empty project) while starting up.":
        "Seleziona quali progetti aprire all'avvio. Puoi bypassare questa scelta tenendo premuto Shift (nuovo progetto da template) o Cmd+Shift (progetto vuoto) all'avvio.",
    "Select the project(s) to open on startup. Override this option by holding Shift (new project, default template) or Ctrl+Shift (empty project) while starting up.":
        "Seleziona quali progetti aprire all'avvio. Puoi bypassare questa scelta tenendo premuto Shift (nuovo progetto da template) o Ctrl+Shift (progetto vuoto) all'avvio.",
    "Deselect this option to prevent REAPER checking for new program updates once per day via the internet.":
        "Deseleziona questa opzione per impedire a REAPER di cercare nuovi aggiornamenti una volta al giorno via Internet.",
    "When opening a REAPER project directly from the system file explorer/finder, the current project can be replaced, or a new project tab created.":
        "Quando si apre un progetto REAPER direttamente dal Finder/Explorer, è possibile sostituire il progetto corrente o creare una nuova scheda di progetto.",
    "Displays the splash screen and REAPER logo when the application starts.":
        "Mostra la schermata di caricamento (splash screen) e il logo REAPER all'avvio dell'applicazione.",
    "Skips the REAPER logo animation and potentially slightly reduces startup time.":
        "Salta l'animazione del logo REAPER, riducendo leggermente il tempo di avvio.",
    "More advanced user interface and system settings. These should be used with caution.":
        "Impostazioni avanzate di sistema e interfaccia utente. Da utilizzare con cautela.",
    "Warn when REAPER's memory use exceeds the amount listed. Recommended values are 1800 for 32-bit, 0 (disabled) for 64-bit.":
        "Avvisa quando l'uso di memoria di REAPER supera il valore indicato. Valori consigliati: 1800 per sistemi a 32 bit, 0 (disabilitato) per 64 bit.",
    "If enabled, projects will be unloaded in background on exit. REAPER may continue to use CPU and memory during this time.":
        "Se abilitato, i progetti vengono scaricati in background all'uscita; REAPER potrebbe continuare a usare CPU e memoria durante questa fase.",
    "Choose language from installed languages (you must quit and restart REAPER for language changes to take effect.":
        "Scegli la lingua tra quelle installate (è necessario riavviare REAPER per applicare le modifiche alla lingua).",
    "Opens an options menu related to localization.":
        "Apre un menu di opzioni relativo alla localizzazione e alla lingua.",
    "When rendering or converting files, filename collisions may be resolved by adding a suffix to the filename.":
        "Durante il rendering o la conversione di file, i conflitti tra nomi uguali possono essere risolti aggiungendo un suffisso numerico.",
    "If myfile_001 and myfile_003 already exist, enable this setting to auto-increment myfile as myfile_004 instead of myfile_002.":
        "Se esistono già 'file_001' e 'file_003', abilita questa opzione per incrementare 'file' come 'file_004' anziché riempire 'file_002'.",
    "If the auto-increment suffix is _001, enable this setting to auto-increment myfile-001 as myfile_002 instead of myfile-001_001.":
        "Se il suffisso di incremento è _001, abilita questa opzione per incrementare 'file-001' come 'file_002' anziché 'file-001_001'.",
    "If enabled, REAPER will request that the OS not blank the screen or show any screensaver when REAPER is using an audio device, or when rendering.":
        "Se abilitato, REAPER richiede al sistema operativo di non oscurare lo schermo né avviare lo screensaver durante l'uso dell'audio o il rendering.",
    "Maximum undo memory (default: 256 MB). Enter 0 to disable the Undo function as well as the prompt to save modified projects on close.":
        "Memoria massima per l'annullamento (predefinita: 256 MB). Inserisci 0 per disabilitare la funzione Annulla (Undo) e la richiesta di salvataggio alla chiusura.",
    "This option, enabled by default, will create a new undo point each time you select an item.":
        "Questa opzione, attiva per impostazione predefinita, crea un nuovo punto di annullamento (undo point) a ogni selezione di un item.",
    "This option, disabled by default, will create a new undo point each time you select a track.":
        "Questa opzione, disattivata per impostazione predefinita, crea un nuovo punto di annullamento a ogni selezione di una traccia.",
    "This option, disabled by default, will create a new undo point each time you select an envelope point.":
        "Questa opzione, disattivata per impostazione predefinita, crea un nuovo punto di annullamento a ogni selezione di un punto di inviluppo.",
    "This option, enabled by default, will create a new undo point each time you create a time selection.":
        "Questa opzione, attiva per impostazione predefinita, crea un nuovo punto di annullamento a ogni creazione di una selezione temporale.",
    "This option, disabled by default, will create a new undo point each time you move the edit cursor.":
        "Questa opzione, disattivata per impostazione predefinita, crea un nuovo punto di annullamento a ogni spostamento del cursore di modifica.",
    "This option, enabled by default, creates a new undo point each time you change MIDI event selection in the MIDI editor.":
        "Questa opzione, attiva per impostazione predefinita, crea un nuovo punto di annullamento a ogni modifica della selezione di eventi nell'editor MIDI.",
    "If this option is enabled, REAPER will discard the oldest undo points first. If this option is disabled, undo points from in between are removed.":
        "Se abilitato, REAPER elimina per primi i punti di annullamento più vecchi. Se disabilitato, rimuove i punti di annullamento intermedi.",
    "Saves undo history in a file with your projects, so you can preserve the history across sessions. Slows down project saves and uses more disk space.":
        "Salva la cronologia degli annullamenti in un file insieme al progetto, conservandola tra sessioni diverse. Rallenta il salvataggio e occupa più disco.",
    "Loads the undo history from disk when opening a project.":
        "Carica la cronologia degli annullamenti dal disco all'apertura del progetto.",
    "Gives you more options when working your way back through the undo history; useful but does use a lot of memory.":
        "Offre più opzioni per navigare all'indietro nella cronologia degli annullamenti; utile ma comporta un elevato consumo di memoria.",
    "Show the last user action in REAPER's title bar.":
        "Mostra l'ultima azione eseguita nella barra del titolo di REAPER.",
    "Show the last user action in REAPER's menu bar. Clicking the action will open the undo window.":
        "Mostra l'ultima azione eseguita nella barra dei menu di REAPER. Facendo clic sull'azione si apre la finestra della cronologia annullamenti.",

    # [prefs_project_help]
    "Using this feature you can create new projects that are automatically setup with your choice of basic tracks and project settings (bit depth, sample rate, etc).":
        "Consente di creare nuovi progetti preconfigurati con le tracce di base e le impostazioni desiderate (profondità di bit, sample rate, ecc.).",
    "Makes REAPER open the save project window each time you create a new project, getting you to save before you start recording.":
        "Apre la finestra di salvataggio ogni volta che crei un nuovo progetto, invitandoti a salvare prima di iniziare a registrare.",
    "Select this option to make REAPER open the project settings window each time a new project is created.":
        "Seleziona questa opzione per aprire la finestra Impostazioni progetto a ogni creazione di un nuovo progetto.",
    "Makes REAPER look for project media items in the project media path(s) before checking fully qualified paths.":
        "Fa sì che REAPER cerchi i file multimediali nella cartella dei media di progetto prima di controllare i percorsi assoluti completi.",
    "This option, selected by default, makes REAPER prompt you for the location of missing files when a Project is opened.":
        "Questa opzione, attiva per impostazione predefinita, richiede all'utente la posizione dei file mancanti all'apertura del progetto.",
    "Displays the splash screen and status indicator when projects are loading.":
        "Mostra la schermata iniziale e l'indicatore di avanzamento durante il caricamento dei progetti.",
    "Saves the pathname of files in projects as relative. Files that are in a different drive or higher directories are saved with the full pathnames.":
        "Salva i percorsi dei file nel progetto in formato relativo. I file situati su unità diverse o cartelle superiori conservano il percorso assoluto.",
    "Settings that affect only the current project are in the Project Settings dialog. Global settings that affect all projects are in this dialog.":
        "Le impostazioni relative solo al progetto corrente si trovano in Impostazioni progetto. Le impostazioni globali si trovano in questa finestra.",
    "Define a wildcard pattern to use as the default prompt when running \\\"File: Save project as...\\\"":
        "Definisce un pattern con caratteri jolly (wildcard) predefinito per il comando \"File: Salva progetto con nome...\".",
    "When using the action 'save new version of project', the new project name is generated by adding a suffix.":
        "Quando si usa l'azione 'salva nuova versione del progetto', il nuovo nome viene generato aggiungendo un suffisso numerico.",
    "Saves a backup of your old Project file with the extension \\\".rpp-bak\\\" each time a save is performed.":
        "Salva una copia di backup del file di progetto precedente con estensione \".rpp-bak\" a ogni salvataggio.",
    "Saves a copy of all previous saved versions of the project in one (potentially very large!) .rpp-bak file.":
        "Salva una copia di tutte le versioni salvate in precedenza in un unico file .rpp-bak cumulativo (può diventare molto grande!).",
    "Saves backup copies with timestamped names (letting you keep a history of saved projects, one per file).":
        "Salva copie di backup con data e ora nel nome (consentendo di conservare uno storico ordinato dei progetti salvati, uno per file).",
    "Enter the interval in minutes for the automatic saves.":
        "Inserisci l'intervallo in minuti per il salvataggio automatico.",
    "This option enables automatic saving of your project to the main project file.":
        "Abilita il salvataggio automatico del progetto direttamente sul file di progetto principale.",
    "This option enables automatic saving of your project to an extra timestamped file.":
        "Abilita il salvataggio automatico del progetto su un file separato con data e ora nel nome.",
    "This option enables automatic saving of your project to an extra timestamped file in the specified directory.":
        "Abilita il salvataggio automatico del progetto su un file con data e ora nella cartella specificata.",
    "REAPER can automatically save timestamped project files to this folder.":
        "REAPER può salvare automaticamente i file di progetto con data e ora in questa cartella specifica.",
    "Limit timestamped backup files to a maximum number of copies or unique days for a given project.":
        "Limita i file di backup con data/ora a un numero massimo di copie o di giorni unici per ciascun progetto.",
    "Limit timestamped auto-save backup files to a maximum number of copies or unique days for a given project.":
        "Limita i file di salvataggio automatico a un numero massimo di copie o di giorni unici per ciascun progetto.",
    "Limit timestamped backup files in an alternate path to a maximum number of copies or unique days, for either a given project or for all backups.":
        "Limita i file di backup nel percorso alternativo a un numero massimo di copie o giorni, per singolo progetto o per tutti i backup.",
    "Controls whether timestamped backup files are saved alongside the project or in the Backups subdirectory.":
        "Stabilisce se i file di backup con data/ora vengono salvati accanto al file di progetto o nella sottocartella Backups.",
    "Controls whether timestamped auto-saved files are saved alongside the project or in the AutoSaves subdirectory.":
        "Stabilisce se i file di salvataggio automatico vengono salvati accanto al file di progetto o nella sottocartella AutoSaves.",
    "If enabled, unsaved projects will be saved automatically to temporary files to be possibly re-loaded on relaunch (if configured to load last project).":
        "Se abilitato, i progetti non salvati vengono archiviati temporaneamente per poter essere riaperti al riavvio (se impostato il caricamento dell'ultimo progetto).",

    # [prefs_path_help]
    "Set the default directory for rendered files. If blank, the current project directory will be used.":
        "Imposta la cartella predefinita per i file renderizzati. Se vuoto, verrà utilizzata la cartella del progetto corrente.",
    "Fallback recording path for all new files, if the project has not previously been saved, and no path is set in file/project settings.":
        "Percorso di registrazione di riserva per i nuovi file se il progetto non è stato salvato e non è definito alcun percorso nelle impostazioni.",
    "Alternate path for REAPER peak cache files (.reapeaks). The alternate path may also be used even if not enabled here, see Preferences/Media.":
        "Percorso alternativo per i file cache dei picchi di REAPER (.reapeaks). Può essere utilizzato anche se non abilitato qui (vedi Preferenze/Media).",
    "List of paths that will always have their peak cache files placed in the alternate path rather than with the media. Useful for sample libraries etc.":
        "Elenco di percorsi i cui file di picco verranno sempre collocati nel percorso alternativo anziché accanto ai media (utile per librerie di campioni, ecc.).",
    "Set the default directory to browse when no project is loaded and you wish to load or save a project file.":
        "Imposta la cartella predefinita da esplorare quando non vi è alcun progetto caricato e si desidera aprire o salvare un file di progetto.",
    "List of paths that will not have media copied or moved from (on import if configured, or save-as with copy). Useful for sample libraries etc.":
        "Elenco di percorsi dai quali i file multimediali non verranno mai copiati o spostati (durante l'importazione o il salva con copia; utile per librerie)."
}
