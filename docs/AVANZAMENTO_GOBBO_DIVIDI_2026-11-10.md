# Gobbo — selezione della parola e divisione del copione, 2026-11-10

Suite 2.6.7 in preparazione, checkout `release/2.6.7`. Backup sorgenti e REAPER eseguito prima delle modifiche. Nessun commit, push, tag o aggiornamento dell’indice ReaPack.

## Comportamento

- Nei due Gobbi il doppio clic seleziona la parola, evidenziata in azzurro, senza entrare nell’editor e senza fermare il trasporto o spostare il cursore della timeline. La selezione conserva item, GUID, testo e offset: resta riferita alla parola scelta anche se il documento continua a scorrere.
- Il menu destro propone «Edita testo…», «Aggiungi promemoria su questa parola…», «Dividi prima di questa parola» e, quando presenti, lo scollegamento dei promemoria. Senza una selezione già valida, il clic destro sceglie la parola sotto il puntatore. «Edita testo…» riutilizza l’editor esistente, posizionato sulla parola selezionata. Le note di regia mantengono i propri gesti nel pannello Note.
- La divisione è consentita soltanto per item con ZP_TIMED_SCROLL=1, senza take e senza ZP_SYNC_KEY. Il comando dedicato taglia al tempo della parola nel piano di lettura originale. L’item sinistro conserva il testo precedente; il destro parte dalla parola scelta e contiene il resto. L’item destro viene selezionato per lo spostamento manuale. Il normale Split di REAPER resta fuori da questa funzione.
- La durata totale e il passo già assegnato alle parole e alle pause sono conservati, anche con pezzi inferiori a cinque secondi e con tagli ripetuti. Il confine tra item sostituisce l’ultimo accapo e l’eventuale indentazione prima della parola, evitando una pausa fantasma. Questi caratteri di separazione sono contabilizzati dal confine, non rimossi dal contenuto parlato.
- Il piano temporale dei due pezzi è persistito nei soli metadati ZP_GOBBO_TIMING e ZP_GOBBO_TIMING_TEXT. La lettura usa il piano salvato soltanto se il testo corrisponde esattamente e il numero di eventi è valido. Cambi espliciti a testo/WPM invalidano il piano precedente; salvataggi senza cambiamenti o di sole evidenziazioni lo conservano. Posizione e lunghezza attuali dell’item restano la base del rendering.
- I promemoria sono ripartiti tra i due item, con offset relativi aggiornati nel destro; i marker nativi restano dov’erano. Colori, velocità ed evidenziazioni sono conservati. Il taglio non esegue azioni di ripple, non taglia audio o altri item e non modifica ZP_SYNC.
- Controlli prima del taglio: item ancora nel progetto corrente, testo non cambiato rispetto alla selezione, ammissibilità del tipo di item, entrambi i pezzi con contenuto parlato e tempi validi. Un solo blocco Undo comprende taglio e riscrittura dei metadati. Se la scrittura fallisce dopo il taglio, viene annullato quel blocco; se SplitMediaItem non crea il destro, non si annulla alcuna azione precedente.
- Gli intervalli temporizzati sono ora aperti a destra: al punto esatto di taglio la parola appartiene al secondo item. Corretti anche il comportamento sul bordo finale/gap e il troncamento UTF-8 dei nomi degli item.

## Verifiche

Nuovo test `test_gobbo_dividi.lua`: 1.915 verifiche, comprese proprietà su tutti i confini di parola di più testi UTF-8, accapi, indentazioni, pause iniziali/finali, durate corte/lunghe, tagli ripetuti, identità della parola e dello stato di pausa prima/dopo il taglio in molti istanti, promemoria, metadati, Undo/Redo, rifiuto degli item audio/sincronizzati/di altro progetto, selezione obsoleta, taglio nativo fallito, rollback su scrittura fallita e gesti dei due Gobbi.

Restano superati i 304 controlli precedenti di editor, testo, scorrimento e promemoria. `run_all.sh`: TUTTO OK. Sintassi dei tre Lua modificati e git diff --check sui file della modifica: OK. Sono verifiche automatiche con API REAPER simulate, non un collaudo interattivo del progetto reale. Nessun progetto aperto è stato modificato durante l’installazione dei file.

## Installazione

Sei file distribuiti aggiornati nel REAPER locale, verificati identici byte per byte ai sorgenti: 02, 03, ZP_Testo_Copione, guide IT/EN e catalogo EN. Riaprire i Gobbi per caricare le modifiche. GitHub non aggiornato.

Backup locale: `/Users/paolob/Library/Application Support/REAPER/ZP_StudioSuite_Backups/gobbo_dividi_parola_20261110_184946`.

Archivio storico: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Gobbo/2026-11-10_dividi_parola_20261110_184946` (copie pre-source/pre-REAPER, SHA256-pre.json, snapshot finali e log run_all).

## Correzione divisione annullata — 2026-11-10

Difetto riprodotto in un’istanza REAPER 7.85/macOS-arm64 separata, con progetto vuoto e resource directory temporanea. Il codice precedente interpretava `GetSetMediaItemInfo_String(..., true) == false` come scrittura fallita. REAPER restituisce invece false per campi P_EXT vuoti correttamente vuoti (osservati RythmoBand_HIGHLIGHT e ZP_GOBBO_ANCHORS). Il controllo attivava quindi un rollback spurio. Gli stub precedenti restituivano sempre true su una scrittura valida e non riproducevano questa semantica.

Correzione: ogni proprietà viene scritta e poi riletta; il confronto verifica il valore effettivo, indipendentemente dal booleano del setter. P_NOTES viene confrontato dopo normalizzazione CRLF/LF, perché il native Undo ripristina le note con CRLF. Se il contenuto non coincide, il rollback resta attivo, anche quando il setter restituisce true senza salvare.

Prova nativa: vecchio codice riproduce il messaggio; rollback restituisce il copione completo. Con la correzione: «A B\n\nC D» diviso prima di C diventa «A B\n» e «C D», durate 5+3 secondi; Undo e Redo corretti; secondo taglio prima di D mantiene soltanto D e dura 1,5 secondi. Nessun progetto del REAPER di lavoro è stato aperto o modificato dalla prova: lo script controlla il resource path temporaneo prima di operare. Log e script del test conservati nell’archivio; nessun file di licenza o configurazione audio copiato nell’archivio.

Test automatico esteso a false sui campi vuoti, false con valore persistito, CRLF nelle note e successo dichiarato senza persistenza: 1.934 verifiche del taglio superate; run_all.sh TUTTO OK. Modificato e installato soltanto ZP_Testo_Copione.lua; source e runtime identici SHA-256. Suite 2.6.7 invariata, nessuna pubblicazione. Riaprire il Gobbo per ricaricare il modulo.

Backup locale: `/Users/paolob/Library/Application Support/REAPER/ZP_StudioSuite_Backups/gobbo_dividi_verifica_scrittura_20261110_215703`. Archivio e log: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Gobbo/2026-11-10_dividi_verifica_scrittura_20261110_215703`.


## Collaudo Gobbo confermato — 2026-11-10

Paolo conferma in questa chat che il collaudo del Gobbo è passato. Consolidate in un commit locale dedicato le modifiche ai due Gobbi, i moduli copione/editor, i test e le fixture, le guide IT/EN e i riferimenti del pacchetto. La conferma riguarda il collaudo svolto da Paolo: in questa fase non sono stati ripetuti i test o le prove interattive. Suite 2.6.7 invariata, nessun push, tag o pubblicazione. La modifica indipendente a help/pannello_trascrizione.html resta fuori dal commit Gobbo. Snapshot pre-commit con SHA-256: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Gobbo/2026-11-10_collaudo_confermato_commit_231310`.
