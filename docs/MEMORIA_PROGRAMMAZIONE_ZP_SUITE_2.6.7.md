# Memoria tecnica della ZP Suite 2.6.7

**Scopo:** descrivere il software dal punto di vista del codice e del flusso di esecuzione, per orientare una successiva ricerca di complessità inutile, duplicazioni e costi di runtime.

**Base osservata:** checkout `/Volumes/DiscoM28T/Progetti e siti web/ZP/zp-suite-2.6.7`, ramo `release/2.6.7`, HEAD `e8693d8` (`Documenta i riconoscimenti e i collaudi confermati della ZP Suite 2.6.7`). La candidata è in preparazione e non è la versione pubblicata. La provenienza dei file acquisiti e i successivi interventi sono registrati in `docs/PROVENIENZA_2.6.7.md` e `docs/PRE_RELEASE_2.6.7.md`.

**Limite di questa memoria:** è una lettura statica di sorgenti e documentazione. Non ho profilato REAPER, misurato CPU/memoria/tempi, né confrontato ogni file con la copia installata o con la versione pubblicata. Le dimensioni dei file e i punti indicati come candidati a debito sono indicatori per un audit, non prove di lentezza o di cattiva qualità.

## Come leggere le istruzioni del repository

La richiesta dell’utente è produrre una mappa programmatica di cosa fa la Suite e di come lo fa, utile a trovare codice residuo che appesantisce l’esecuzione. L’`AGENTS.md` allegato al checkout è invece un insieme di istruzioni per gli agenti che lavorano sul repository: richiede, fra le altre cose, di preservare gli indici pubblici JSFX, distinguere beta/pubblicato, non fare commit o push senza richiesta e conservare snapshot/hash prima di interventi rischiosi. Queste regole governano il lavoro futuro, ma non sono caratteristiche funzionali della Suite e non sono state trasformate in requisiti del prodotto.

Le note storiche di `AGENTS.md` descrivono più fasi di Stagekeeper, inclusi stati superati. Non vanno lette come descrizione automatica del codice del candidato corrente. Per la funzione corrente fanno fede prima il sorgente presente nel checkout e poi le note esplicitamente marcate come stato corrente. Le indicazioni di progetto in `docs/PROGETTO_*.md` possono descrivere prototipi o proposte; qui sono trattate come contesto, non come prova che una funzione sia inclusa o pronta.

## Quadro generale

ZP Suite non è un unico programma residente. È una distribuzione di componenti per REAPER, principalmente ReaScript Lua e plugin JSFX, con un sottosistema Python chiamato ZP Speech, pagine HTML/JavaScript locali e strumenti accessori. ReaPack installa le azioni, gli helper, le risorse e gli effetti dichiarati nell’indice `index.xml`. REAPER avvia di norma uno script quando l’utente richiama l’azione; gli script con finestra restano attivi tramite `reaper.defer()` e interrogano/aggiornano lo stato del progetto e della GUI.

Il modello di esecuzione ha quindi due famiglie:

1. **Azioni brevi:** leggono selezione/progetto, compiono una trasformazione e terminano. Esempi: collegare marker, applicare colori, creare regioni.
2. **Azioni interattive o di servizio:** mantengono un ciclo GUI/eventi con `defer`, oppure avviano un processo esterno. Esempi: Gobbo, Benvenuto, 29 Trascrizione, SOLO Recorder, Probe Guard.

La Suite non applica una pipeline globale a ogni playback. Il codice audio in tempo reale è nei JSFX; gran parte delle funzioni Lua lavora solo quando la relativa azione è in uso. Un loop `defer` può tuttavia continuare a interrogare REAPER mentre una finestra resta aperta: frequenza, lavoro per frame e condizioni di uscita sono elementi da misurare nell’audit.

## Linguaggi e responsabilità

| Parte | Tecnologia | Ruolo |
|---|---|---|
| Azioni e interfacce REAPER | Lua/ReaScript | Legge e modifica tracce, item, take, marker, regioni, file di progetto, ExtState e finestre. |
| Elaborazione audio in tempo reale | JSFX/EEL2 | Filtri, dinamica, meter e altri processori eseguiti dal motore audio REAPER. |
| Trascrizione | Python (`speech-engine/`) | Contratto dati, provider, servizio locale, client/CLI, validazione, esportazione e traduzione. |
| UI browser locale | HTML/JavaScript/CSS | SRT Tools e interfaccia web associata a SOLO; il bridge REAPER/web espone una superficie separata. |
| Risorse | XML, HTML, PNG, SVG, template REAPER, cataloghi | Registrazione ReaPack, help, toolbar, localizzazione e configurazioni iniziali. |

Il codice Lua usa in prevalenza API native REAPER. SWS, js_ReaScriptAPI e OSARA sono integrazioni facoltative o circoscritte: il pannello Benvenuto rileva la loro presenza e diverse funzioni riducono o disabilitano capacità quando l’estensione manca. Su Windows NVDA usa un helper Python dedicato. Render & Copy richiede js_ReaScriptAPI per parte delle funzioni Windows; il README documenta inoltre dipendenze per sistemi operativi e provider.

## Come viene installata e avviata

`index.xml` è il manifest ReaPack: dichiara pacchetti, versioni, sorgenti, file da installare e risorse. `ZP Studio Suite/00_Apri_Help_ZP_Studio_Suite.lua` è il punto d’ingresso di catalogazione della Suite: contiene la versione del pacchetto, descrizioni, changelog e blocchi `@provides` per helper e azioni. I nomi numerati diventano azioni riconoscibili nella Action List e pulsanti toolbar installabili.

`33_Benvenuto_Controllo_Installazione.lua` è il controllo diagnostico guidato: verifica toolbar/effetti, configurazione web REAPER, Cue Navigator, ZP Speech e integrazioni esterne; mostra lo stato e offre azioni di installazione/riparazione. Non è un daemon della Suite. La maggior parte degli script ricava la propria cartella con `debug.getinfo`, poi carica helper adiacenti con `dofile`, così che il pacchetto installato possa essere rilocato senza percorsi macchina fissi.

## Moduli condivisi e stato

I principali helper sono:

- **`ZP_UI.lua`**: primitive grafiche, pulsanti, tooltip, finestre, palette, link/help e inizializzazione comune. È riutilizzato da varie finestre; una modifica qui può influire su molti strumenti.
- **`ZP_Lingua.lua`** e `lang/en.txt`: selezione e traduzioni italiane/inglesi, indipendenti dalla lingua di REAPER.
- **`ZP_Testo_Copione.lua`**, **`ZP_Editor_Copione.lua`**: normalizzazione/testo temporizzato e disegno/editor condivisi dai Gobbi; la scrittura in progetto resta responsabilità del chiamante.
- **`ZP_cerca.lua`**: normalizzazione e ricerca testuale riutilizzabili.
- **`ZP_SRT_Progetto.lua`**: registro persistente dei file SRT/VTT nel Project ExtState, quindi nel progetto RPP.
- **`ZP_sincronizza_aggancio.lua`**: converte take marker in item di testo collegati all’audio e riallinea tali item dopo tagli/spostamenti.
- **`ZP_Colori.lua`**: logica condivisa dietro le numerose azioni della toolbar colori.
- **`lib_RythmoBand_Accessibile.lua`** e `ZP_NVDA_Speech.py`: lettura/accessibilità OSARA e ponte NVDA su Windows.
- **helper remoti** in `remote/`: identità stabili, ID personaggio, JSON, preflight e logica importer separata dall’interfaccia REAPER.

Lo stato è distribuito deliberatamente su più livelli: ExtState per preferenze e stato globale utente; Project ExtState per dati che devono seguire il file RPP; P_EXT dei singoli item/take per identità e associazioni; file accanto ai media o in `Media/` per audio, sottotitoli e risultati; normali marker/regioni/item per dati direttamente manipolabili in REAPER. Questa distinzione è centrale: una preferenza non dovrebbe migrare con il progetto, mentre un’associazione di sorgente sì.

## Cosa fa la ZP Studio Suite

### Copione, Gobbo e accessibilità

`02_Gobbo_Verticale.lua` e `03_Gobbo_Orizzontale.lua` leggono item di testo REAPER sulle tracce `Rythmo Band Testi…`. Disegnano un copione scorrevole con parola/battuta corrente agganciata alla posizione del trasporto, supportano ricerca, selezione, flussi di testo e modalità di lettura/modifica. Gli script persistono preferenze UI tramite ExtState, non riscrivono il documento a ogni frame e usano i moduli copione/editor condivisi. La versione verticale e quella orizzontale hanno comunque implementazioni UI e cicli propri: la loro convergenza o duplicazione va valutata guardando il codice, non presunta dal fatto che condividano alcuni helper.

`04_Crea_Marker_Item.lua`, `07_Note_Personaggio.lua`, le azioni `09–13` e i Gobbi supportano navigazione e accessibilità; `10/11` avanzano/arretrano tra battute e `12` legge automaticamente con OSARA quando disponibile. `14_Marker_da_Timeline_a_Item.lua` trasferisce cue/marker nella struttura testo. `ZP_sincronizza_aggancio.lua` gestisce il collegamento durevole: identifica marker con GUID del take e tempo sorgente, calcola il tempo progetto come `pos_item + (source_time - startoffs) / playrate`, aggiorna gli item derivati senza sovrascrivere correzioni manuali e gestisce marker rimossi/orfani.

### SRT, video e trascrizione

`01_Importa_Video_SRT.lua` importa video e sottotitoli, creando tracce e item temporizzati. `05_*` fornisce worker e operazioni di gestione/sostituzione; `06_Importa_SRT_Reference.lua`, `08_Esporta_SRT.lua`, `26_SRT_Tools.lua`, `28_Collega_Marker.lua`, `30_ZP_SRT.lua` e `31_SRT_da_Marker_Audio.lua` coprono collegamento, conversione, import/export e strumenti di supporto.

`29_ZP_Trascrizione.lua` è una finestra/workflow di orchestrazione: osserva gli item selezionati, decide i passaggi mancanti (trascrivere, abbinare SRT/marker, portare le parole nel Gobbo, seguire i tagli), lancia gli script già esistenti e mostra lo stato. Usa una coda batch asincrona e il client di servizio per non bloccare la UI durante la trascrizione. I risultati SRT/VTT sono associati al progetto tramite `ZP_SRT_Progetto.lua`; i marker audio possono generare testo ancorato alla sorgente.

**ZP Speech** è un sottosistema separato, non incluso come semplice script ReaPack. Il suo contratto canonico è JSON versionato (`schema_version=1`, tempi interi in millisecondi, intervalli semiaperti, `source_id` basato sullo SHA-256 dei byte sorgente). Il livello applicativo parla al client/servizio, il servizio locale su loopback gestisce job e provider, e i provider normalizzano MacWhisper o OpenAI Whisper nel contratto ZP. Il servizio limita la coda, valida richieste e tiene job in memoria; il README segnala che riavvio del servizio perde la coda/storia e che cancellazione/ripresa persistente/cache condivisa sono lavori futuri. Il flusso dati è dunque:

```text
29 Trascrizione / altri client
    -> CLI o API locale ZP Speech
        -> coda del servizio
            -> provider (MacWhisper o OpenAI Whisper)
        -> JSON ZP Speech v1
    -> SRT/metadata registrati nel progetto
    -> marker take -> item testo sincronizzati al Gobbo
```

### Preparazione progetto, montaggio e consolidamento

`17_Crea_Regioni_Export_da_Item_Nominati.lua`, `18_Project_Viewer.lua`, `19_Report_Minuti_Voce.lua` e `20_Importa_Cartelle_Video_Mixdown.lua` affrontano organizzazione e consegna: raggruppamento di item in regioni, vista di marker/regioni, calcolo minuti e importazione di media/mixdown. `22_Pulisci_Code_Silenzi_e_Separa_Item.lua` analizza l’audio selezionato tramite AudioAccessor e crea un piano per code/silenzi/tagli; la lettura audio si svolge a blocchi e la UI mostra progresso. `23_ZP_Chain_Builder.lua` crea/verifica strutture di tracce e bus per profili. `24_ZP_Probe_Guard.lua` controlla nel tempo la posizione dei meter/Probe negli FX chain mentre la sua finestra è aperta.

`37_ZP_Consolidate.lua` analizza i take, inclusi quelli non attivi, risolve sorgenti file e riferimenti SRT/VTT, deduplica percorsi, copia i file in `Media` a blocchi con verifica e aggiorna le sorgenti take. Gestisce file offline/non accessibili con scelta dell’utente, collisioni e rollback/Undo; prima di modificare i riferimenti salva il progetto e conserva una copia del RPP. La funzione separata Pulisci Media sposta fuori dalla cartella Media i file non usati, senza cancellarli. La memoria di pre-release documenta collaudo simulato e parziale da Paolo, con verifiche ancora aperte per Redo, MIDI esterni e sorgenti offline.

### SOLO Recorder, SOLO Web, Render & Copy e ZP Remote

`25_ZP_SOLO_Recorder.lua` è una superficie operativa di registrazione: prepara una struttura di tracce, gestisce arm/record/next take, regioni take e viste compatte; integra funzioni best-effort per controllo finestre e comunica con la componente web. Il file è molto ampio e ospita più responsabilità UI/registrazione/ponte, quindi è un candidato alla scomposizione concettuale nell’audit, non una prova che consumi CPU quando non è aperto.

`web/ZP_SOLO_Web_Motore.lua` e le risorse web forniscono il lato browser/servizio di SOLO. `render_copy/ZP_RenderCopy.lua` osserva il rendering, copia output in destinazioni configurate e offre sincronizzazione: il comportamento dipende dalla piattaforma e dalle API opzionali rilevate.

ZP Remote esporta dal progetto salvato un pacchetto limitato alla regione scelta (audio guida, proxy video, waveform, battute, note, marker e manifest/ZIP) tramite Lua e Python/ffmpeg; l’importatore valida una consegna e inserisce nel progetto take/marker seguendo un contratto idempotente e identità persistenti. `remote/zp_remote_esporta.py`, `zp_remote_preflight.py`, `zp_remote_import_logic.lua`, `zp_remote_importer.lua` e gli helper identity/character IDs dividono esportazione, verifica e importazione. L’operazione passa da REAPER ai processi Python/ffmpeg e ai file/ZIP: avvio processi, parsing RPP e letture/copie sono costi di job espliciti, non costi continui di playback.

### Toolbar e utility

`32_Installa_Toolbar_ZP.lua` installa/configura le toolbar; `34_ZP_Set_Comandi.lua` prepara comandi/azioni. `35_ZP_Colori.lua` apre la famiglia di azioni colori, i cui script elementari delegano a `ZP_Colori.lua`. `27_Pulisci_Installazione_Precedente.lua` gestisce residui di vecchie installazioni, con verifica ReaPack quando l’API c’è. Gli script `00–37` non sono necessariamente una sequenza eseguibile: i numeri sono etichette di catalogo/uso umano e non un orchestratore globale.

## Altri pacchetti ZP nel repository

Le cartelle esterne alla Studio Suite ospitano effetti distinti caricati da REAPER:

- **ZP Voce:** catene e processori vocali (tra cui BUS Chain, Voiceover Unified Chain, Stagekeeper, Spoken Finish, Harmonic Space Carver e Cue Navigator). Gli script JSFX contengono DSP e GUI EEL2; il Cue Navigator è un helper Lua per la gestione dei cue/memorie.
- **ZP Master:** processori di mastering e confronto timbrico (per esempio ZP Master Pro e Reference Tone Mirror EQ Pro).
- **ZP Misura:** loudness meter, oscilloscopio multicanale e probe di misura.
- **ZP Lab:** prototipi/strumenti sperimentali, tra cui BrownSlope.

Per questi plug-in il costo potenziale durante il playback è il lavoro `@sample`/`@block`/`@gfx` del singolo JSFX e il numero di istanze attive nel progetto. Non va sommato al costo della UI Lua se l’azione Lua è chiusa. Gli slider JSFX e il loro ordine sono dati di progetto potenzialmente persistenti: una pulizia non può rinumerarli senza migrazione/compatibilità.

## Dove può annidarsi complessità residua

Questi sono candidati verificabili, ordinati per probabilità di produrre costo manutentivo o runtime misurabile. Nessuno è etichettato come bug senza profilazione o prova riproducibile.

1. **Script grandi con più responsabilità.** Nel checkout, i maggiori file Suite sono 17 (circa 4.700 righe), Gobbo verticale (4.400), SOLO Recorder (2.850), Gobbo orizzontale (2.740), import video/SRT (1.650), Report Minuti (1.460), Consolidate (1.400), import cartelle (1.380), Cleaner (1.370), Project Viewer (1.320), 29 Trascrizione (1.250), Remote exporter Lua (1.190) e Benvenuto (1.110). Le dimensioni possono essere spiegate da UI/help/localizzazione e casi multipiattaforma. Vanno mappate per responsabilità e call path prima di estrarre moduli.
2. **Cicli `defer`.** Inventariare tutte le azioni che mantengono un loop, il periodo di polling, API chiamate ogni frame, lavoro fatto solo quando cambia lo stato e percorsi di arresto (`atexit`, chiusura, progetto cambiato). Verificare che ricerca filesystem, scansioni complete di tracce/item e parsing non avvengano ripetutamente durante il disegno.
3. **UI condivisa contro UI duplicate.** `ZP_UI.lua` riduce duplicazioni ma può diventare un punto centrale; i due Gobbi condividono logica testo, non necessariamente ciclo di disegno/stato. Misurare duplicazioni prima di uniformare, perché differenze di interazione potrebbero essere intenzionali.
4. **Persistenza e serializzazione.** Esaminare il costo di riscrivere Project ExtState/ExtState, parsing di RPP, JSON, note item e liste intere. Preferire aggiornamenti incrementali dove il comportamento attuale già identifica GUID/chiavi stabili. Evitare di trattare dati derivati (posizione timeline) come fonte primaria quando è già disponibile l’identità sorgente.
5. **Processi shell e scansioni file.** `29`, Benvenuto, Render & Copy, Remote e installer invocano CLI, `os.execute`, `io.popen` o `ExecProcess`. Verificare se ogni comando è lanciato a richiesta, se il polling blocca la UI e se ci sono scansioni ripetute. Qualunque hardening dei comandi va fatto senza rompere Windows/macOS/Linux.
6. **Lavoro audio nel thread UI.** Il Cleaner 22 è documentato come a blocchi; controllare che AudioAccessor e analisi vengano eseguiti con budget temporale e `defer`, non per intero in un frame. In JSFX, valutare separatamente `@sample`, `@block` e rendering GUI: un costoso aggiornamento GUI non deve implicare costo uguale per campione.
7. **Confini tra orchestratori e azioni.** `29` coordina altri script anziché duplicarne ogni operazione; 30 fa da launcher degli strumenti SRT. Accertare che le azioni esterne si chiudano correttamente, che il progetto non venga analizzato due volte e che i processi già in coda non siano riavviati.
8. **Compatibilità storica e rami morti.** Nei JSFX, vecchie versioni slider, chiavi ExtState, migrazioni e modalità legacy possono essere necessarie per progetti salvati. Ogni rimozione deve distinguere codice inattivo ma compatibile da codice realmente irraggiungibile. In Lua, controllare fallback per versioni REAPER, SWS/JS API assenti e formati precedenti.
9. **Codice duplicato o percorso parallelo.** Cercare parser duplicati (SRT/JSON/RPP), normalizzazioni, conversioni path/time, utility shell e gestione degli errori ripetute. Non sostituire un helper locale con un helper comune se il contratto differisce; confrontare input, side effect e test esistenti.
10. **Risorse e versionamento.** `@provides`, `index.xml`, help, cataloghi, immagini e script devono restare coerenti. Un helper condiviso modificato in una candidata non viene necessariamente installato in ogni copia locale. La provenienza di 2.6.7 segnala che il checkout combina base installata 2.6.6, beta locali e aggiornamenti successivi: una differenza di file non è automaticamente codice inutile.

## Metodo consigliato per trovare il codice che pesa davvero

1. **Fissare baseline e ambiente:** versione REAPER/OS, progetto minimo riproducibile, set di FX, azioni aperte e stato delle estensioni.
2. **Separare i costi:** playback JSFX; loop Lua con finestre aperte; azioni one-shot; operazioni disco/processi; avvio/chiusura. Un unico dato “CPU Suite” confonde costi diversi.
3. **Misurare prima e dopo:** CPU REAPER e per-plugin, tempi di frame/azione, numero di chiamate API e file letti, dimensione progetto e tempi di apertura/salvataggio. Per audio usare lo stesso buffer, sample rate, numero di tracce e passaggio playback.
4. **Tracciare i call path:** entry action → helper → API REAPER/processo → side effect. Annotare frequenza e condizioni di ricalcolo. Cercare in particolare lavoro che viene rifatto senza che siano cambiati gli input.
5. **Verificare il risultato funzionale:** comportamento audio, marker/item, stato persistito, Undo/Redo, accessibilità e piattaforme. La riduzione delle righe non equivale a riduzione del costo.
6. **Modificare una responsabilità alla volta:** baseline verificata, diff limitato, misura replicata e compatibilità salvata. Per JSFX preservare gli indici slider pubblici; per REAPER preservare GUID, ExtState e formato progetto.

## Inventario quantitativo iniziale

Il conteggio `wc -l` eseguito sul checkout ha rilevato circa **43.423 righe nei sorgenti Lua della cartella ZP Studio Suite** (incluse utility e helper), **33.753 righe nei file Lua/JSFX delle altre famiglie ZP** e circa **5.207 righe Python sotto `speech-engine/`**, comprese le prove. Questi totali includono codice, commenti e UI e non sono una metrica di qualità né di runtime; servono soltanto a delimitare il campo e a individuare concentrazioni per il prossimo passaggio.

I JSFX più estesi osservati sono BUS Chain (circa 5.950 righe), Voiceover Unified Chain (5.000), Master Pro (3.700), Stagekeeper (3.700), Reference Tone Mirror EQ Pro (3.150), Loudness Meter Multichannel (2.410), Spoken Finish (2.290) e Harmonic Space Carver (2.140). La parte Python più grande è OpenAI Whisper provider (circa 724 righe); service e MacWhisper provider sono circa 370/350 righe. Le dimensioni richiedono una lettura per sezioni, non una riscrittura automatica.

## Riferimenti primari nel checkout

- `README.it.md`, `index.xml`, `ZP Studio Suite/00_Apri_Help_ZP_Studio_Suite.lua`: distribuzione e catalogo.
- `ZP Studio Suite/` e `speech-engine/src/zp_speech/`: implementazione.
- `speech-engine/README.md`, `docs/ZP_Speech_Engine_Project.md`: contratto e processo del sottosistema Speech (distinguere stato implementato da roadmap storica).
- `docs/PROVENIENZA_2.6.7.md`, `docs/PRE_RELEASE_2.6.7.md`: stato e provenienza della candidata.
- `docs/IN_MATURAZIONE.md`: componenti non conclusi/non da trattare come feature pubblicate.
- `AGENTS.md`: istruzioni operative per futuri interventi; non specifica funzionale.

**Conclusione operativa:** la candidata è una collezione di strumenti modulari con alcuni helper centrali, non un’unica pipeline sempre attiva. Per individuare il codice che appesantisce davvero il funzionamento, il primo audit utile è associare ogni loop/azione al suo costo e misurarlo nel contesto in cui gira; le prime aree da osservare sono i grandi script interattivi, i loop `defer`, le scansioni progetto/file e i blocchi audio JSFX.
