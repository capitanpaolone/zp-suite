# ZP Private Regions — protocollo v1

La lane stabilisce l'ownership e, quando registrato, il ruolo. Per Stagekeeper
la lane determina SPACE o IGNORE; la regione ne delimita l'intervallo temporale.
Nome e colore servono all'operatore. La posizione visiva non identifica una lane.

## Registro comune

Helper: `ZP_Private_Regions.lua`. Project ExtState: `ZP_PRIVATE_REGIONS_V1`.
Ogni chiave `lane:{GUID}` contiene l'owner, per esempio `STAGEKEEPER`.
La chiave aggiuntiva `role:{GUID}` contiene il ruolo immutabile, ad esempio
`SPACE` o `IGNORE`. La coppia owner/ruolo identifica una sola lane; duplicati
vengono rifiutati. Il formato owner resta compatibile con i filtri editoriali.
Il registro viene salvato insieme al progetto. Il GUID viene letto tramite
`GetSetProjectInfo_String(..., "RULER_LANE_GUID:X", ...)`; la lane attuale della
regione tramite `GetRegionOrMarkerInfo_Value(..., "I_LANENUMBER")`.
Gli indici delle API sono zero-based; i numeri mostrati all'operatore sono presentazione.

Non si riconoscono Private Regions dal colore, dal nome della lane, dal numero
visivo o dal nome della regione. Ogni regione su una lane registrata viene esclusa
dai consumatori editoriali, anche quando owner o tipo non sono conosciuti.
Letture, modifiche e cancellazioni offerte dall'helper richiedono l'owner corretto
e risolvono la regione tramite il suo GUID corrente. Questo è un protocollo di
cooperazione della Suite: non impedisce modifiche manuali in REAPER.

Per gli owner che non registrano un ruolo, il nome della regione contiene il tipo, un token maiuscolo `A-Z`, `0-9`, `_` che
inizia con una lettera. Un nome non valido non attiva alcuna semantica, ma la regione
resta privata. Le estensioni future devono definire il proprio formato senza far
interpretare ad altri owner i propri metadati.

## Stagekeeper

Azioni da caricare nella Action List e assegnare ai tasti desiderati:

- `28_Stagekeeper_Private_SPACE.lua`
- `29_Stagekeeper_Private_IGNORE.lua`

Selezionare un intervallo temporale e richiamare l'azione. La prima esecuzione
di ciascuna azione crea la propria lane separata (SPACE oppure IGNORE),
inizialmente nella posizione 4 se possibile; se quella
posizione esiste già, la nuova lane viene aggiunta in fondo. Non viene acquisita
una lane preesistente. Le esecuzioni successive cercano il GUID registrato,
anche dopo riordino o rinomina. Colori iniziali: SPACE ambra, IGNORE grigio.
Ogni azione crea esclusivamente regioni nella propria lane. Eseguire entrambe
inizializza due lane, mai una sottolane per ogni nuova regione.
Le azioni creano un punto Undo e non cambiano la selezione temporale.
`read` restituisce `role` e deriva `type` dal ruolo anche se la regione è rinominata.
`update` rifiuta un tipo diverso dal ruolo prima di modificare l'intervallo.

La semantica prevista è:

- `SPACE`: maggiore contesto e prudenza prima di un cambio di autorità.
- `IGNORE`: nessun intervento Authority Assist; Stagekeeper/Shadow normale attivo.

**In questa fase sono annotazioni. Authority Assist non è implementata e non legge
ancora queste regioni. Nessuna modifica al DSP Stagekeeper.** L'eventuale priorità
fra indicazioni sovrapposte dovrà essere definita nella fase Authority Assist.

Se la lane registrata viene eliminata, l'azione segnala l'errore invece di
appropriarsi della lane ora presente nello stesso punto. Ripristinarla con Undo.
Il riferimento nel registro non viene cancellato o sostituito dopo l'errore;
Undo può ripristinare il GUID originale. La lane dell'altro ruolo resta indipendente.

Le registrazioni Stagekeeper della versione iniziale, prive di `role:{GUID}`,
restano private per i filtri ma bloccano la creazione con un errore esplicito
di migrazione necessaria. Non si deduce il ruolo dai nomi delle regioni o della
lane, né si divide automaticamente una lane legacy eventualmente mista.
La migrazione dei progetti legacy richiede un intervento esplicito dedicato.

Spostare una regione fuori dalla lane privata ne cambia l'appartenenza, come
previsto dal protocollo. Il riordino dell'intera lane invece non la cambia.

## Consumatori editoriali e render

Project Viewer esclude tutte le lane registrate dalla raccolta, dai conteggi e
dalla selezione render. Lo stesso filtro è applicato ai lettori di regioni di
SRT, report minuti, importazione mixdown, SOLO Recorder, pulizia preview e Gestore
Progetto. Quest'ultimo mantiene il proprio vincolo editoriale sulla lane 1,
con un controllo aggiuntivo utile se una lane privata viene spostata in prima posizione.

Quando esistono regioni private, il render aperto dal Viewer richiede una selezione
editoriale e usa `Selected regions`. Gestore Progetto e la sua coda usano la stessa
selezione nativa. La coda conserva tutte le Private Regions nel progetto, escludendole
dagli intervalli render, e ripristina la selezione dopo la creazione della snapshot
anche se la callback fallisce.

Questo filtro riguarda i flussi della Suite. Il comando nativo REAPER “tutte le
regioni” resta un comando globale: non esiste qui un intercettore delle operazioni
manuali esterne alla Suite. Le regioni tecniche restano visibili sulla timeline.

## Compatibilità e uso da altri owner

La creazione richiede le API native per regioni e Ruler Lane con GUID. Senza queste
API, un progetto privo di registrazioni mantiene il comportamento editoriale
precedente; con registrazioni presenti il filtro esclude prudenzialmente i dati
che non può classificare. Non esiste un fallback al colore o al numero di lane.

L'argomento opzionale finale `role` di `ensure_lane`, `create` e `register_lane`
abilita lane persistenti per coppia owner/ruolo. Senza ruolo resta il contratto
generico precedente; non mescolare registrazioni con e senza ruolo per lo stesso
owner. I metadati incompleti vengono segnalati, senza appropriazioni automatiche.

Whisper potrà usare `ensure_lane`, `create`, `read`, `update` e `delete` con owner
`WHISPER`, definendo autonomamente i propri tipi. Non viene creata alcuna lane
Whisper prima che il modulo la richieda. L'helper non conosce SPACE, IGNORE o la
semantica di Whisper. I chiamanti di scrittura devono gestire il proprio blocco Undo.

Riferimento API: https://www.reaper.fm/sdk/reascript/reascripthelp.html

## Verifiche e distribuzione

Eseguire dalla radice del repository: `lua tests/test_private_regions.lua`.
22 test con API REAPER simulate: ripetizione e alternanza delle azioni reali,
due ruoli distinti, ordine di prima creazione, riordino e riapertura dell'helper,
ruolo indipendente dal nome regione, registro legacy/duplicato, ripristino del GUID
dopo cancellazione simulata, GUID e riordino, lane occupate/eliminate,
separazione owner, CRUD, tipi futuri, selezione render, raccolta reale Viewer e
snapshot coda con errore simulato. Controllo sintattico superato per i 32 script Lua.

Non ancora verificato in una sessione REAPER reale: creazione delle lane, Undo/Redo,
salvataggio/riapertura, selezione nativa e contenuto del job di coda. Questi test
restano necessari prima di dichiarare la versione validata per produzione.

La modifica è nel repository; non è stata installata nella cartella risorse REAPER
né pubblicata. Le dipendenze e le due azioni sono dichiarate nel blocco `@provides`
dello script principale; l'indice ReaPack pubblicato non è stato rigenerato.
