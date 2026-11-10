# Gobbo — editor copione, 2026-11-10

Destinazione: checkout `zp-suite-2.6.7`, ramo `release/2.6.7`. Versione del pacchetto invariata (2.6.7 in preparazione). Nessun commit, push, tag o aggiornamento dell’indice ReaPack. Installazione REAPER aggiornata su richiesta di Paolo il 10 novembre (vedi aggiornamento in fondo).

## Implementazione

- `ZP_Testo_Copione.lua`: normalizzazione UTF-8, accenti italiani, pulizia esplicita pause multiple, ricomposizione righe PDF, separazione frasi, maiuscole/minuscole/iniziale sulla selezione; parser DOCX, ODT e RTF; TXT UTF-8. DOCX/ODT letti come ZIP/XML senza Office installato: `unzip` su macOS/Linux, PowerShell/.NET su Windows (comando UTF-16LE/Base64 per preservare percorsi con spazi, Unicode e metacaratteri). SWS per gli appunti, fallback `pbpaste`/PowerShell/Wayland/X11. Gli errori di importazione lasciano intatto il testo dell’editor.
- `ZP_Editor_Copione.lua`: viewport con rotella e scrollbar, cursore visibile su inserimento/movimento, selezione e trascinamento; toolbar e Strumenti; contatori parole/pause e durata con WPM. Cache dell’impaginazione; vengono disegnate solo le righe visibili. Testi e metadati di evidenziazione sono salvati in timeline soltanto con Salva: Esc/Annulla scarta entrambi. Undo include le evidenziazioni.
- Verticale: importazione dalla barra o Ctrl/⌘+L; ricalcolo durata disattivabile per item temporizzati; niente pannello Corpo duplicato; pulsanti/interruttori da ZP_UI, firma e versione dal 00; nomi personaggio orizzontali, fascia opzionale di lettura, progresso item, banner ambra di riaggancio visibile con Tab. Esc, quando sganciato, riaggancia senza cambiare il trasporto; Spazio mantiene Play/stop. +/− e Alt+rotella cambiano WPM.
- Orizzontale: stesso editor, importazione e ricalcolo opzionale degli item temporizzati, creazione al salvataggio di un nuovo copione importato; pulsante Carica file con finestra larga almeno 740 px, Ctrl/⌘+L sempre disponibile; progresso item e versione dinamica. La stima pause usa le righe testuali, mentre il Verticale mantiene il proprio modello basato sulle righe impaginate.
- Corrette le misure byte-per-byte del cursore nelle lettere UTF-8. `ZP_UI.fit_text` ora tronca solo tra caratteri completi.
- Guide IT/EN e catalogo inglese aggiornati; OSARA mantiene le voci 1–17 e aggiunge 18 Carica file, 19 Riposiziona, 20 Fascia. Due helper nel `@provides` del 00.

## Verifiche e limiti

Test mirati: `test_testo_copione.lua` (33 verifiche) e `test_editor_copione.lua` (102 verifiche con API REAPER simulate). Fixture DOCX/ODT sono veri archivi Office minimi, sintetici, senza dati personali; verificano XML, accenti, paragrafi vuoti, a capo ed evidenziazioni. Non sono documenti esportati da una sessione reale di Word/LibreOffice.

Verificati con simulazione: editor su 100 righe, finestra 420×320, scroll manuale, cursore UTF-8, highlight differiti e annullamento, Undo, salvataggio senza cambiamenti, conservazione durata manuale e ricalcolo esplicito.

Il parser importa testo e marcature dirette DOCX; non interpreta tutte le proprietà ereditate da styles.xml di Word. Per ODT legge anche gli stili e la relativa ereditarietà. RTF gestisce testo ANSI occidentale/Unicode, gruppi e destinazioni comuni; non è un renderer RTF completo. I documenti protetti, le note a piè pagina e gli oggetti incorporati non sono convertiti. Se manca `unzip` su Linux, l’importazione Office restituisce un errore e TXT/RTF restano disponibili.

Restano da collaudare dall’interno di REAPER: aspetto reale, retina/font, appunti senza SWS, file reali forniti da Paolo, mouse durante Play/REC, Undo progetto e resa OSARA. PowerShell/Windows e Wayland/X11 non eseguiti su host nativi. Nessuna validazione interattiva è dichiarata.

Baseline e manifest SHA-256 nell’archivio storico: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Gobbo/2026-11-10_copione/`. Il report finale e i file modificati vengono conservati nella stessa cartella.

## Esito finale automatico

`run_all.sh`: **TUTTO OK** (109 Lua tracciati verificati, test di logica, catalogo EN, language pack, mock server SOLO Web). Sintassi dei due nuovi helper controllata esplicitamente con `luac -p`; il runner usa Git e non li enumera finché non sono tracciati. Test nuovi: **135 verifiche complessive superate**. `git diff --check` pulito. Le funzioni `UpdateItems` dei due Gobbi sono identiche alla baseline. Il primo tentativo di mock server era bloccato dal sandbox; rieseguito con permesso per localhost, superato.

**NON SINCRONIZZATO**: candidato 2.6.7 modificato soltanto nel checkout; installazione REAPER e GitHub non aggiornati, per lasciare il collaudo interattivo e la pubblicazione come fasi distinte.

## Installazione REAPER locale — 2026-11-10

Su richiesta esplicita di Paolo installati i nove file modificati del pacchetto (00, 02, 03, ZP_UI, i due helper, guide IT/EN e catalogo inglese). Confronto preventivo a tre: sette file installati uguali a HEAD e due helper assenti; nessuna variante locale sovrascritta. Copia manuale nella destinazione del pacchetto ReaPack: **non** è un collaudo dell’installazione attraverso ReaPack. Verifica dopo copia: tutti e nove i file identici byte per byte ai sorgenti. Nessun ini o progetto modificato.

Backup locale: `/Users/paolob/Library/Application Support/REAPER/ZP_StudioSuite_Backups/gobbo_copione_2.6.7_20261110_115159`. Archivio e hash: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Gobbo/2026-11-10_copione/install_REAPER_20261110_115159`. Riaprire i Gobbi per caricare gli script nuovi. Nessun collaudo interattivo eseguito. Repo e REAPER allineati per questi nove file; GitHub non aggiornato, nessuna pubblicazione.

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


## Collaudo Gobbo confermato — 2026-11-10

Paolo conferma in questa chat che il collaudo del Gobbo è passato. Consolidate in un commit locale dedicato le modifiche ai due Gobbi, i moduli copione/editor, i test e le fixture, le guide IT/EN e i riferimenti del pacchetto. La conferma riguarda il collaudo svolto da Paolo: in questa fase non sono stati ripetuti i test o le prove interattive. Suite 2.6.7 invariata, nessun push, tag o pubblicazione. La modifica indipendente a help/pannello_trascrizione.html resta fuori dal commit Gobbo. Snapshot pre-commit con SHA-256: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Gobbo/2026-11-10_collaudo_confermato_commit_231310`.
