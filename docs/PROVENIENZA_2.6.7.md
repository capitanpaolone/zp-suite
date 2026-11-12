# Provenienza dei file acquisiti per ZP Studio Suite 2.6.7

Acquisizione: 2026-11-09 dall’installazione REAPER locale. La base del pacchetto installato è 2.6.6; alcuni file comprendono modifiche beta locali. Versioni interne e @version dei componenti restano indipendenti dal numero della Suite.

Lo snapshot byte per byte precedente alla copia è conservato in `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/2026-11-09_Pre-release-2.6.7_from-REAPER/` con `MANIFEST.md` e SHA-256.

| File nel repository | Proprietà / pacchetto d’origine | Versione interna rilevata |
|---|---|---|
| `ZP Studio Suite/17_Crea_Regioni_Export_da_Item_Nominati.lua` | Suite 2.6.6 locale / Gestore Progetto | 1.0.5 |
| `ZP Studio Suite/19_Report_Minuti_Voce.lua` | Suite 2.6.6 locale / Report Minuti Voce | 1.0.6 |
| `ZP Studio Suite/33_Benvenuto_Controllo_Installazione.lua` | Suite 2.6.6 locale / Benvenuto | Segue la versione del pacchetto principale |
| `ZP Studio Suite/remote/ZP_Remote_Crea_Pacchetto.lua` | Suite 2.6.6 locale / ZP Remote | 1.0 |
| `ZP Studio Suite/remote/zp_remote_import_logic.lua` | Suite 2.6.6 locale / helper ZP Remote | Non dichiarata; `@noindex` |
| `ZP Studio Suite/remote/zp_remote_importer.lua` | Suite 2.6.6 locale / helper ZP Remote | Non dichiarata separatamente |
| `ZP Studio Suite/remote/zp_remote_preflight.py` | Suite 2.6.6 locale / helper ZP Remote | Non dichiarata separatamente |
| `ZP Studio Suite/help/index.html`, `help/en/index.html`, `lang/en.txt` | Suite 2.6.6 locale | Risorse del pacchetto |
| `ZP Voce/ZP Harmonic Space Carver Cue Navigator.lua` | Harmonic Space Carver 2.6.10 locale | 1.14 |
| `ZP Voce/ZP Harmonic Space Carver.jsfx` | Harmonic Space Carver 2.6.10 locale | 2.6.10 |

La versione d’origine descrive il pacchetto installato da cui proviene il file; non certifica da sola quando il singolo file sia stato scaricato o se sia stato modificato localmente. Per questo la cattura è datata e hashata, e la destinazione 2.6.7 è esplicita.

## Correzione GUI Harmonic Space Carver — 2026-11-09

Versione candidata 2.6.10 mantenuta; Helper 1.14 invariato. Intervento richiesto da Paolo sulla grafica precedente, con sistemazione C/S/M/L, etichette Rampa/Personalizza e Voice Ret. Corretta anche la parentesi mancante in @block: nessuna variazione agli algoritmi DSP o allo stato dei cue. Sorgente e installazione REAPER allineati. Snapshot e diff: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Harmonic Space Carver/2026-11-09_HSC-2.6.10-GUI-Candidate`. Verifiche statiche delle sezioni e dei delimitatori; nessun collaudo runtime in questa fase.

## Tempi HSC per marker — 2026-11-09

Su richiesta di Paolo, la memoria per marker ora comprende Rampa e durata Custom, con richiamo nei pomelli e tempi usati dal cue in riproduzione. Layout conservato; @sample byte identico. Aggiornati JSFX e helper candidati (2.6.10 / 1.14), formato seriale 2611 con migrazione dai precedenti. Installati nel REAPER principale. Snapshot, diff e hash: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Harmonic Space Carver/2026-11-09_HSC-Marker-Timings-Candidate`. Sintassi Lua e struttura JSFX controllate staticamente; nessun collaudo runtime in questa fase.

## Gobbo (testo temporizzato) e ZP Speech — 2026-11-09

- **Gobbo Verticale e Orizzontale (`02_Gobbo_Verticale.lua`, `03_Gobbo_Orizzontale.lua`)**: integrata la funzione `+ Testo temporizzato` (`+ Timed text`), WPM configurabile, calcolo durata item con righe vuote e parole, riposizionamento su player, e aggiornamento documentazione (`help/index.html`, `help/en/index.html`, `lang/en.txt`).
- **ZP Speech Engine**: collaudato con provider locale `OpenAIWhisperProvider` in ambiente dedicato Python 3.11 su macOS, CLI `models`, `download-model`, `doctor --engine`, test coverage 98.45% (203 passati), basedpyright strict, ty, ruff, wheel. Script `29_ZP_Trascrizione.lua` e `33_Benvenuto_Controllo_Installazione.lua` allineati e verificati.
- **Battezzatura a 2.6.7**: `00_Apri_Help_ZP_Studio_Suite.lua` aggiornato a `@version 2.6.7`; allineata l'installazione locale REAPER (`/Users/paolob/Library/Application Support/REAPER`) con snapshot di backup precauzionale in `REAPER/ZP_StudioSuite_Backups/pre_2.6.7_alignment_2026-11-09`.


## Gobbo — editor copione e importazione, 2026-11-10

Sviluppo nel checkout `release/2.6.7` sui sorgenti acquisiti il 9 novembre, senza nuova importazione dalla REAPER locale. Aggiunti `ZP_Testo_Copione.lua` e `ZP_Editor_Copione.lua`; aggiornati 02/03, troncamento UTF-8 e stile ambra in ZP_UI, guide IT/EN, catalogo e @provides. Versione Suite 2.6.7 invariata. `run_all.sh` superato e 135 verifiche mirate superate. Nessuna installazione REAPER, commit o pubblicazione. Dettagli e limiti: `AVANZAMENTO_GOBBO_COPIONE_2026-11-10.md`.

2026-11-10 (Codex): su richiesta di Paolo installato l’aggiornamento Gobbo 2.6.7 nel REAPER locale. Confronto preventivo: 7 file uguali a HEAD, 2 helper assenti; 9 file copiati e verificati identici SHA-256 ai sorgenti. Backup: `/Users/paolob/Library/Application Support/REAPER/ZP_StudioSuite_Backups/gobbo_copione_2.6.7_20261110_115159`; archivio: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Gobbo/2026-11-10_copione/install_REAPER_20261110_115159`. Copia manuale, non test del percorso ReaPack. Nessuna modifica agli ini; nessuna prova interattiva, commit o pubblicazione. GitHub resta non sincronizzato.

## Correzione velocità e riaggancio — 2026-11-10

Su richiesta di Paolo, il valore parole/minuto è sulla riga sopra i pulsanti −/+, senza sovrapposizioni. Esc riaggancia al player dopo lo scorrimento manuale; Spazio mantiene sempre Play/stop. Nell’editor Esc continua ad annullare e nel pannello Cerca continua a chiudere la ricerca. Banner, catalogo EN e guide IT/EN aggiornati. Installati quattro file nel REAPER locale, verificati identici ai sorgenti; sintassi Lua verificata, nessuna nuova suite di test o prova interattiva eseguita. Backup locale: `/Users/paolob/Library/Application Support/REAPER/ZP_StudioSuite_Backups/gobbo_esc_velocita_20261110_144225`; archivio con SHA-256: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Gobbo/2026-11-10_esc_velocita_20261110_144225`. Versione 2.6.7 invariata, GitHub non aggiornato.

## Clic sul testo: conserva la posizione — 2026-11-10

Corretto su richiesta di Paolo in entrambi i Gobbi: il clic Studio/Edit seleziona l’item senza saltare al suo inizio; il doppio clic apre l’editor senza chiamare OnStopButton. L’editor già aperto intercetta i clic e non viene riaperto dal documento sottostante. Timeline e trasporto vengono quindi preservati anche con Muove la timeline attivo; ricerca e navigazione manuale esplicita restano disponibili. Guide IT/EN aggiornate; quattro file installati e verificati identici ai sorgenti. Sintassi dei due script controllata con luac; nessun nuovo test automatico o collaudo interattivo eseguito. Backup: `/Users/paolob/Library/Application Support/REAPER/ZP_StudioSuite_Backups/gobbo_clic_posizione_20261110_160201`; snapshot e SHA-256: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Gobbo/2026-11-10_clic_posizione_20261110_160201`. Suite 2.6.7 invariata; GitHub non aggiornato.

## Pause nel testo e doppio clic sulla parola — 2026-11-10

Su richiesta di Paolo rimosso il pulsante + Battuta e la funzione che creava un item TESTO sovrapposto. La numerazione OSARA resta stabile: 11 ora ricorda di usare Shift+Invio nell’editor. Shift+Invio inserisce una riga vuota nel testo (nelle note conserva l’accapo normale). Le righe vuote compaiono nel Gobbo Verticale e aggiungono tempo allo stesso item temporizzato con Ricalcola durata attivo. Per modifiche alle sole pause, a parole e WPM invariati, la durata reale precedente aumenta o diminuisce del numero di righe vuote per il tempo medio di una riga originale; il ricalcolo non azzera una durata calibrata a mano. Conservate anche le pause iniziali/finali. Nessun item di progetto preesistente viene eliminato o spostato.

Doppio clic: il cursore viene ricavato dalla posizione effettiva del testo disegnato, con spazi compressi e confini UTF-8; l’editor apre la riga interessata al centro della zona visibile. Il clic/rilascio che apre la finestra non viene riutilizzato per spostare il cursore o premere un pulsante nell’editor. Correzione applicata a Verticale e Orizzontale; timeline e trasporto restano invariati.

Aggiornati guide IT/EN, catalogo inglese e suggerimento nell’editor. 170 verifiche mirate superate (132 editor e 38 helper), run_all.sh TUTTO OK, sintassi dei quattro Lua e git diff --check OK. Nessuna prova interattiva in REAPER dichiarata. Installati sette file e verificati identici ai sorgenti, con backup `/Users/paolob/Library/Application Support/REAPER/ZP_StudioSuite_Backups/gobbo_pause_doppio_clic_20261110_163641` e archivio/SHA-256 `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Gobbo/2026-11-10_pause_doppio_clic_20261110_163641`. Suite 2.6.7 invariata. GitHub non aggiornato; nessun commit, tag o pubblicazione.

2026-11-10: controllo finale pause completato. Nel nuovo testo Orizzontale la durata passa come singolo valore all’API REAPER, mentre numero e tempo delle pause restano interni al calcolo. Test esteso alla creazione effettiva con API simulate e controllo del numero degli argomenti: 135 verifiche editor superate (più 38 helper, totale 173). Correzione installata e hash identici tra repo e REAPER. Archivio: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Gobbo/2026-11-10_pause_controllo_finale_20261110_180243`. Nessun altro componente modificato.

## Pause effettive e marker promemoria — 2026-11-10

Correzione della regressione segnalata da Paolo: l’aumento di durata e le righe vuote erano salvati, ma l’evidenziazione sceglieva ancora la parola tramite percentuale uniforme dell’item. Ora i testi temporizzati hanno un piano composto da parole e intervalli silenziosi. Durante una riga vuota la parola corrente resta l’ultima letta, il gruppo di evidenziazione non anticipa la successiva e la camera verticale/banda orizzontale non avanza. La durata effettiva delle pause usa parole/minuto e peso della riga; il tempo parlato occupa il resto della durata reale dell’item. Nessuna scrittura della durata durante il rendering, nessun download o cambiamento a ZP_SYNC/take marker. I sottotitoli ordinari mantengono il comportamento precedente. Anche le pause già salvate sono riconosciute.

Marker: richiesta chiarita da Paolo come PROMEMORIA, non sincronizzazione. Clic destro sulla parola nella vista di lettura del Verticale → «Aggiungi promemoria su questa parola…». Viene creato un marker REAPER al cursore della timeline, con bollino/sottolineatura della parola nel Gobbo. È liberamente spostabile, anche fuori dall’item, e non altera mai il piano di lettura, il trasporto o gli item. Identità tramite GUID del marker, conservata dopo rinomina/rinumerazione; P_EXT:ZP_GOBBO_ANCHORS dell’item conserva soltanto l’offset testuale del promemoria. Nessun vincolo di sincronizzazione è stato implementato. Scollega conserva i marker; eliminarli da REAPER non li ricrea. I riferimenti testuali seguono inserimenti/rimozioni precedenti alla parola, con Undo editor; una parola eliminata lascia il marker in timeline senza riassegnarlo ad altre parole.

API identità marker: `GetSetProjectInfo_String(..., "MARKER_GUID:<indice>", ..., false)`, compatibile con gli script già installati nel REAPER locale; documentazione ufficiale: https://www.reaper.fm/sdk/reascript/reascripthelp.html#GetSetProjectInfo_String . Non si presume che l’ID numerico del marker sia stabile.

Verifiche: nuovo `test_gobbo_lettura.lua`, 131 controlli sul piano, sullo stato delle parole durante la pausa, sulla posizione immobile della banda orizzontale e sui promemoria indipendenti dalla timeline. 135 verifiche editor e 38 helper già esistenti restano superate: 304 verifiche mirate complessive; run_all.sh TUTTO OK, sintassi Lua e git diff --check OK. Nessuna prova interattiva REAPER dichiarata. Aggiornati sei file nel REAPER locale e verificati identici ai sorgenti. Nessuna modifica ai progetti aperti durante l’installazione.

Backup: `/Users/paolob/Library/Application Support/REAPER/ZP_StudioSuite_Backups/gobbo_pause_effettive_promemoria_20261110_182126`. Archivio e SHA-256: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Gobbo/2026-11-10_pause_effettive_promemoria_20261110_182126`. Versione Suite 2.6.7 invariata, GitHub non aggiornato.

2026-11-10: su richiesta di Paolo e dopo backup, implementati doppio clic = selezione della parola, editor esplicito dal menu destro e divisione del copione temporizzato alla parola. Tempi/pause preservati nei due pezzi; promemoria ripartiti senza spostare marker; item audio/ZP_SYNC esclusi. 1.915 verifiche nuove e run_all.sh superati. Installati sei file nel REAPER locale, hash uguali al repo; nessun collaudo interattivo, commit o pubblicazione. Rapporto: `docs/AVANZAMENTO_GOBBO_DIVIDI_2026-11-10.md`. Backup e hash: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Gobbo/2026-11-10_dividi_parola_20261110_184946`.

## Correzione divisione annullata — 2026-11-10

Difetto riprodotto in un’istanza REAPER 7.85/macOS-arm64 separata, con progetto vuoto e resource directory temporanea. Il codice precedente interpretava `GetSetMediaItemInfo_String(..., true) == false` come scrittura fallita. REAPER restituisce invece false per campi P_EXT vuoti correttamente vuoti (osservati RythmoBand_HIGHLIGHT e ZP_GOBBO_ANCHORS). Il controllo attivava quindi un rollback spurio. Gli stub precedenti restituivano sempre true su una scrittura valida e non riproducevano questa semantica.

Correzione: ogni proprietà viene scritta e poi riletta; il confronto verifica il valore effettivo, indipendentemente dal booleano del setter. P_NOTES viene confrontato dopo normalizzazione CRLF/LF, perché il native Undo ripristina le note con CRLF. Se il contenuto non coincide, il rollback resta attivo, anche quando il setter restituisce true senza salvare.

Prova nativa: vecchio codice riproduce il messaggio; rollback restituisce il copione completo. Con la correzione: «A B\n\nC D» diviso prima di C diventa «A B\n» e «C D», durate 5+3 secondi; Undo e Redo corretti; secondo taglio prima di D mantiene soltanto D e dura 1,5 secondi. Nessun progetto del REAPER di lavoro è stato aperto o modificato dalla prova: lo script controlla il resource path temporaneo prima di operare. Log e script del test conservati nell’archivio; nessun file di licenza o configurazione audio copiato nell’archivio.

Test automatico esteso a false sui campi vuoti, false con valore persistito, CRLF nelle note e successo dichiarato senza persistenza: 1.934 verifiche del taglio superate; run_all.sh TUTTO OK. Modificato e installato soltanto ZP_Testo_Copione.lua; source e runtime identici SHA-256. Suite 2.6.7 invariata, nessuna pubblicazione. Riaprire il Gobbo per ricaricare il modulo.

Backup locale: `/Users/paolob/Library/Application Support/REAPER/ZP_StudioSuite_Backups/gobbo_dividi_verifica_scrittura_20261110_215703`. Archivio e log: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Gobbo/2026-11-10_dividi_verifica_scrittura_20261110_215703`.


## Collaudo Gobbo confermato — 2026-11-10

Paolo conferma in questa chat che il collaudo del Gobbo è passato. Consolidate in un commit locale dedicato le modifiche ai due Gobbi, i moduli copione/editor, i test e le fixture, le guide IT/EN e i riferimenti del pacchetto. La conferma riguarda il collaudo svolto da Paolo: in questa fase non sono stati ripetuti i test o le prove interattive. Suite 2.6.7 invariata, nessun push, tag o pubblicazione. La modifica indipendente a help/pannello_trascrizione.html resta fuori dal commit Gobbo. Snapshot pre-commit con SHA-256: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Gobbo/2026-11-10_collaudo_confermato_commit_231310`.


## Gobbo — leggibilità dei comandi nel tema Chiaro, 2026-11-11

Corretto il modulo condiviso `ZP Studio Suite/ZP_UI.lua`, distribuito come helper `@provides` della Suite 2.6.7. Origine della modifica: sorgente locale del ramo `release/2.6.7`, gia identico alla copia REAPER prima dell’intervento. `draw_rect` usava `gfx.roundrect` con un argomento di riempimento non supportato, lasciando trasparenti i fondi dei pulsanti. Ora fondo e ombra usano `UI.fill_round`, gia presente nel modulo; il bordo mantiene il disegno nativo. Nel tema Chiaro le etichette chiare hanno quindi il fondo scuro previsto. La correzione vale anche per il Gobbo orizzontale e gli altri chiamanti dello stesso helper. Palette e attenuazione del testo del copione conservate. Versione Suite 2.6.7 invariata.

Test di regressione `test_ui_button_background.lua`: il codice precedente fallisce, il corretto supera 54 controlli di composizione del fondo e contrasto su tre sfondi e tre stati, con e senza `gfx.roundrect`; verificati anche clic e disabilitazione. Verifica del rendering simulata, nessun collaudo visuale interattivo dichiarato in questa fase. Backup sorgente/installato e hash: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Gobbo/2026-11-11_contrasto_comandi_220430`. Installato il solo helper nella REAPER locale, source/runtime identici. Nessun commit o pubblicazione.


## ZP Consolidate, registro SRT e scroll Benvenuto — 2026-11-12

Aggiunta l’azione `37_ZP_Consolidate.lua` con helper `ZP_SRT_Progetto.lua`, icone toolbar PNG 90×30 e 180×60 e pulsante nel layout `32_Installa_Toolbar_ZP.lua`. Il registro SRT/VTT è nel Project ExtState del file RPP; `29_ZP_Trascrizione.lua`, `01_Importa_Video_SRT.lua`, `08_Esporta_SRT.lua` e `31_SRT_da_Marker_Audio.lua` lo usano per tenere i file associati in Media. Consolidate copia byte per byte i file referenziati da tutti i take e i sottotitoli registrati, relinka i take dopo la copia e lascia gli originali al loro posto. Gli SRT fuori timeline non registrati non vengono cercati, secondo il perimetro concordato; restano fuori da questa modifica.

Il Lua 33 calcola i limiti prima del disegno e interpola una posizione target dello scroll; così i delta inerziali non disegnano oltre il bordo. Candidato e installazione REAPER hanno lo stesso contenuto per il 33; la copia installata precedente è conservata in `/Users/paolob/Library/Application Support/REAPER/ZP_StudioSuite_Backups/2026-11-12_33_scroll_inertia/`. ZP Consolidate è installato localmente nella beta REAPER 7.85 con backup dei file precedenti in `ZP_StudioSuite_Backups/2026-11-12_ZP_Consolidate_install/`. Non è stata fatta una prova interattiva del nuovo scroll o della raccolta su un progetto reale.

Per la distribuzione, `00_Apri_Help_ZP_Studio_Suite.lua` dichiara l’azione, l’helper non indicizzato e le due icone tramite `@provides`; l’SVG resta sorgente Git esclusa dalla scansione ReaPack. Nessun commit, push, tag o pubblicazione ancora effettuato.
