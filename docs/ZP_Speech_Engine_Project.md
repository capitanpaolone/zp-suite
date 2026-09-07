# ZP Speech Engine — progetto architetturale

Data: 7 settembre 2026
Stato: proposta approvata come base di lavoro
Repository: `capitanpaolone/zp-suite`

## 1. Scopo

ZP Speech Engine è il componente condiviso della ZP Suite dedicato a:

- trascrivere audio e video;
- conservare il collegamento fra testo e tempo;
- produrre SRT/VTT/TXT e altri formati derivati;
- creare e mantenere un indice locale ricercabile;
- permettere a REAPER e ad altre applicazioni ZP di cercare parole o frasi negli audio;
- astrarre il motore di trascrizione reale, così che le applicazioni non dipendano direttamente da MacWhisper, whisper.cpp o da un singolo provider.

Il progetto nasce dal caso d'uso `Audio -> SRT` del tool `26_SRT_Tools.lua`, ma viene deliberatamente separato da quel tool perché dovrà servire anche Solo Recorder, Gobbo, ricerca testuale nella timeline, indicizzazione di sessioni e future applicazioni della ZP Suite.

## 2. Principio architetturale

Le applicazioni ZP non devono chiamare direttamente MacWhisper, whisper.cpp o altri motori.

Devono chiamare un'interfaccia unica:

```text
Applicazione ZP
    -> ZP Speech Engine
        -> provider disponibile
            -> MacWhisper
            -> whisper.cpp
            -> provider futuri
```

Il provider deve essere sostituibile senza modificare il client.

Nome del componente: **ZP Speech Engine**.

Evitare il nome `ZP Whisper`, perché Whisper è una tecnologia sottostante e non il contratto pubblico del sistema.

## 3. Posizione nella ZP Suite

Struttura logica proposta:

```text
ZP Suite
|
+-- ZP Core
|   +-- ZP Speech Engine
|       +-- CLI / launcher
|       +-- provider detection
|       +-- model manager
|       +-- transcription schema
|       +-- cache / index
|       +-- exporters
|       +-- local API
|
+-- ZP Studio Suite
|   +-- 26_SRT_Tools.lua
|   +-- 25_ZP_SOLO_Recorder.lua
|   +-- Gobbo verticale/orizzontale
|   +-- futura ricerca testo nella timeline
|
+-- altre applicazioni ZP
    +-- stesso Speech Engine
```

`ZP Core` è una separazione concettuale. La posizione fisica definitiva nel repository potrà essere scelta durante l'implementazione, purché il componente resti condiviso e indipendente dai singoli tool REAPER.

## 4. Provider iniziali

### 4.1 MacWhisper

Su macOS, se disponibile, ZP Speech Engine può usare la CLI `mw` inclusa in MacWhisper.

Provider preferito quando:

- MacWhisper è installato;
- la CLI è disponibile;
- l'app è pronta a ricevere comandi;
- il formato di output richiesto è compatibile con il contratto ZP.

MacWhisper è un provider opzionale, non una dipendenza obbligatoria.

### 4.2 whisper.cpp

Provider locale multipiattaforma per:

- macOS senza MacWhisper;
- Windows;
- Linux;
- sistemi in cui si desidera un motore completamente controllato dalla ZP Suite.

I modelli non devono essere duplicati per ogni applicazione: devono essere gestiti in una directory condivisa della ZP Suite.

### 4.3 Selezione automatica

Modalità predefinita:

```text
engine = auto
```

Logica iniziale:

```text
macOS:
    MacWhisper disponibile e compatibile?
        si -> usa MacWhisper
        no -> usa whisper.cpp

Windows/Linux:
    usa whisper.cpp
```

In futuro la strategia potrà tenere conto di qualità, hardware, modello richiesto o preferenze dell'utente.

## 5. Contratto dati ZP Speech v1

SRT non è il formato interno del sistema.

Il formato canonico deve essere un JSON versionato, capace di conservare segmenti, parole e metadati temporali.

Principio fondamentale per REAPER: **il dato persistente deve essere ancorato alla sorgente audio e al tempo nella sorgente, non alla posizione corrente nella timeline del progetto**.

`project_seconds` è un valore derivato e ricalcolabile. Non deve essere la chiave primaria dell'indice, perché un item può essere tagliato, spostato, duplicato o riutilizzato senza che la trascrizione della sorgente cambi.

Esempio minimo:

```json
{
  "schema": 1,
  "engine": "whisper.cpp",
  "model": "small",
  "language": "it",
  "source": {
    "id": "source-sha256-or-stable-id",
    "path": "audio.wav",
    "hash": "..."
  },
  "segments": [
    {
      "source_start_ms": 1250,
      "source_end_ms": 4380,
      "text": "Questa e una frase.",
      "speaker": null,
      "words": [
        {"source_start_ms": 1250, "source_end_ms": 1640, "text": "Questa"},
        {"source_start_ms": 1640, "source_end_ms": 1820, "text": "e"}
      ]
    }
  ]
}
```

Campi opzionali futuri:

- confidence;
- speaker;
- token normalizzato;
- identificatore item/take REAPER;
- project time calcolato;
- source offset;
- playrate;
- provider-specific metadata.

Le applicazioni devono dipendere dallo schema ZP, non dallo schema nativo del provider.

## 6. Normalizzazione per la ricerca

L'indice deve conservare il testo originale e anche una chiave di confronto normalizzata.

Per l'italiano:

- minuscole;
- trim spazi;
- apostrofi uniformati;
- punteggiatura separata;
- possibilità di ignorare gli accenti solo nel confronto;
- testo originale sempre conservato per visualizzazione e correzione.

La ricerca deve supportare almeno:

- parola esatta;
- frase esatta;
- ricerca case-insensitive;
- ricerca accent-insensitive opzionale.

Ricerca fuzzy e tolleranza agli errori di riconoscimento sono una fase successiva.

## 7. Cache e indice

Ogni trascrizione deve essere riutilizzabile.

La cache deve poter determinare se un audio è cambiato usando almeno:

- identificatore/hash della sorgente o del render;
- impostazioni di trascrizione;
- provider;
- modello;
- lingua.

La trascrizione della sorgente deve restare valida anche se gli item REAPER che la usano vengono:

- tagliati;
- trimmati;
- spostati;
- duplicati;
- distribuiti su tracce diverse.

Per REAPER la relazione con il progetto deve essere mantenuta separatamente e può includere:

- item GUID;
- take GUID;
- source id/hash;
- posizione corrente dell'item nel progetto;
- start offset del take;
- playrate;
- lunghezza dell'item;
- eventuale origine da render temporaneo.

Obiettivo: se l'audio sorgente non è cambiato, la ricerca deve essere immediata e non deve ritrascrivere il file. La posizione in timeline deve essere ricalcolata dalla situazione corrente del progetto.

## 8. REAPER: ricerca di parole negli audio

Caso d'uso principale:

```text
Utente cerca: "italiani"
    -> REAPER chiede a ZP Speech Engine
    -> Speech Engine cerca nella trascrizione indicizzata della sorgente
    -> per ogni occorrenza ottiene source_id + source_time
    -> REAPER verifica quali item/take correnti contengono quel punto della sorgente
    -> calcola la posizione attuale nella timeline
    -> restituisce una o più occorrenze nel progetto
    -> REAPER porta il cursore al punto corretto
```

Una stessa parola della stessa sorgente può produrre più risultati se quel tratto audio è duplicato o riutilizzato più volte nel progetto.

Risultato persistente dell'indice:

```json
{
  "token": "italiani",
  "source_id": "...",
  "source_start_ms": 240,
  "source_end_ms": 600,
  "segment_text": "Gli italiani sotto la morsa...",
  "speaker": null,
  "source_hash": "..."
}
```

Risultato risolto nel progetto REAPER:

```json
{
  "token": "italiani",
  "source_id": "...",
  "source_start_ms": 240,
  "source_end_ms": 600,
  "project_seconds": 133.420,
  "track": "VO",
  "item_guid": "{...}",
  "take_guid": "{...}",
  "segment_text": "Gli italiani sotto la morsa..."
}
```

`project_seconds` appartiene quindi al risultato della risoluzione corrente, non alla trascrizione permanente.

Azioni REAPER previste:

- Vai;
- Riproduci;
- Seleziona intervallo;
- Crea marker;
- Crea regione;
- mostra contesto;
- filtra per traccia/item/parlante.

Non creare marker automaticamente per ogni parola.

## 9. Mappatura audio -> timeline REAPER

Due modalità complementari.

### 9.1 Indice della sorgente del take — modalità preferita per normali edit

La trascrizione viene associata alla sorgente originale. REAPER calcola dinamicamente la posizione nel progetto:

```text
tempo_progetto = posizione_item + (tempo_sorgente - start_offset_take) / playrate_take
```

Questo consente di mantenere valida una sola trascrizione anche dopo tagli, trim, spostamenti e duplicazioni degli item.

La ricerca deve prima verificare che il `tempo_sorgente` cada realmente nell'intervallo della sorgente usato dall'item corrente. Se la stessa porzione è presente in più item, devono essere restituiti più risultati.

La formula semplice non copre tutti i casi complessi.

### 9.2 Render temporaneo — modalità di precisione per casi complessi

Quando la relazione sorgente/timeline non è affidabile o l'audio ascoltato non corrisponde più in modo semplice alla sorgente, REAPER produce un render temporaneo e la trascrizione parte da zero rispetto all'inizio del render:

```text
tempo_progetto = inizio_render + tempo_trascrizione
```

È la modalità da usare in presenza di casi come:

- stretch marker complessi;
- reverse;
- montaggi compositi;
- elaborazioni che modificano sostanzialmente il contenuto o il tempo;
- casi in cui serve indicizzare esattamente ciò che si ascolta.

### 9.3 Regola di scelta

Usare **source index** quando possibile, perché è persistente, economico e sopravvive all'editing.

Usare **render index** quando necessario per rappresentare fedelmente il risultato effettivo della timeline.

Queste due modalità non sono concorrenti: fanno parte dello stesso contratto ZP Speech.

## 10. CLI proposta

Comandi iniziali:

```text
zp-speech doctor
zp-speech transcribe <file>
zp-speech serve
```

### `doctor`

Deve riportare almeno:

- piattaforma;
- architettura;
- provider trovati;
- provider predefinito;
- modelli disponibili;
- directory cache/modelli;
- compatibilità API/schema.

### `transcribe`

Esempio:

```text
zp-speech transcribe input.wav --language it --format json --output transcript.json
```

Opzioni previste:

- `--engine auto|macwhisper|whispercpp`;
- `--language it|auto|...`;
- `--model ...`;
- `--format json|srt|vtt|txt`;
- `--output ...`;
- `--overwrite`;
- `--speakers` quando supportato.

### `serve`

Espone un servizio locale su loopback, ad esempio `127.0.0.1`, destinato alle interfacce HTML e alle applicazioni locali ZP.

Non deve essere esposto in rete esterna per default.

## 11. Integrazione con `26_SRT_Tools.lua`

Il 26 attuale deve restare un client leggero.

La pagina HTML esistente mantiene le funzioni:

- TXT timecode -> SRT;
- TXT tradotto + SRT.

Nuova funzione:

- Audio -> SRT.

Il browser non deve chiamare direttamente MacWhisper o whisper.cpp.

Flusso previsto:

```text
26_SRT_Tools.lua
    -> verifica/avvia ZP Speech Engine
    -> apre la UI locale
    -> Audio -> richiesta al servizio locale
    -> JSON ZP
    -> esportazione SRT / modifica / download
```

Questo permette di mantenere l'HTML come interfaccia e spostare tutto il lavoro di sistema nel Core.

## 12. Integrazione con Gobbo, Solo Recorder e applicazioni future

La stessa trascrizione deve poter essere consumata da più strumenti.

### Gobbo

Il Gobbo potrà avere una nuova sorgente:

```text
Sorgente:
- Copione
- SRT
- Trascrizione REAPER
```

Funzioni possibili:

- mostrare il testo continuo o segmentato della trascrizione;
- seguire il cursore/playhead di REAPER;
- evidenziare il segmento corrente;
- cliccare una frase nel Gobbo e portare REAPER all'audio corrispondente;
- mostrare solo l'item selezionato, una traccia o l'intero progetto;
- riutilizzare la stessa trascrizione già prodotta per ricerca/SRT senza nuova elaborazione.

### Solo Recorder e altri client

Lo stesso motore potrà essere usato da:

- ZP SOLO Recorder;
- ricerca testuale nella timeline REAPER;
- indicizzazione batch di progetti;
- generazione automatica di sottotitoli;
- ricerca in registrazioni e take;
- sistemi di gobbo/copione;
- verifica fra copione e registrato;
- future applicazioni standalone della ZP Suite.

Il principio è: **una sola trascrizione deve poter servire più strumenti e più rappresentazioni dello stesso audio**.

## 13. Gestione modelli

I modelli non devono vivere dentro i singoli pacchetti ReaPack.

Devono essere installati una sola volta in una directory condivisa, ad esempio:

```text
macOS:
~/Library/Application Support/ZP Suite/Speech/

Windows:
%LOCALAPPDATA%\ZP Suite\Speech\

Linux:
~/.local/share/zp-suite/speech/
```

La struttura potrà contenere:

```text
Speech/
+-- bin/
+-- models/
+-- cache/
+-- logs/
+-- config/
```

Download e aggiornamenti dei modelli devono prevedere verifica di integrità.

## 14. Audio canonico

Per la prima implementazione locale è sufficiente definire un formato intermedio canonico:

```text
WAV PCM
mono
16 kHz
```

REAPER può produrre direttamente un render temporaneo adatto alla trascrizione.

Supporto diretto a MP3, M4A, MOV, MP4 e altri formati può essere aggiunto nel layer di input del Core senza cambiare il contratto dati.

## 15. Privacy

Principio predefinito: elaborazione locale.

Trascrizioni e indici possono contenere materiale sensibile.

Il progetto deve prevedere:

- cache locale;
- nessun upload automatico;
- politica chiara per temporanei;
- possibilità di cancellare cache e trascrizioni;
- nessun accesso diretto al database personale interno di MacWhisper come dipendenza stabile.

Un eventuale provider cloud futuro dovrà essere esplicitamente selezionato dall'utente e separato dai provider locali.

## 16. Compatibilità e versionamento

Definire:

```text
ZP Speech API v1
ZP Speech Schema v1
```

Client e Core devono poter verificare la compatibilità.

Gli aggiornamenti del provider non devono modificare silenziosamente il formato pubblico usato dai client.

## 17. Roadmap

### Fase 0 — contratto

- fissare struttura repository;
- definire ZP Speech Schema v1;
- rendere esplicita la distinzione fra `source_time` persistente e `project_time` calcolato;
- definire CLI;
- definire errori e stati;
- definire directory condivise.

### Fase 1 — MVP MacWhisper

- `zp-speech doctor`;
- provider MacWhisper;
- trascrizione file WAV;
- normalizzazione output in ZP JSON;
- export SRT;
- test con campione voce 20-30 secondi.

Obiettivo: validare l'architettura prima di aggiungere un secondo motore.

### Fase 2 — provider whisper.cpp

- build/runtime per macOS;
- Windows;
- Linux;
- model manager;
- `engine=auto`;
- fallback automatico;
- test di equivalenza del contratto JSON.

### Fase 3 — integrazione SRT Tools

- aggiungere tab `Audio -> SRT`;
- progress;
- annullamento;
- scelta lingua/modello;
- output modificabile;
- esportazione SRT.

### Fase 4 — ricerca REAPER

- indicizzazione sorgente audio;
- mapping corrente source -> item/take -> timeline;
- cache per source hash e relazione con GUID item/take;
- ricerca parola/frase;
- gestione di item tagliati/spostati/duplicati;
- elenco risultati;
- salto al punto;
- preview;
- time selection;
- fallback render-index per casi complessi.

### Fase 5 — Gobbo e condivisione trascrizione

- sorgente `Trascrizione REAPER` nel Gobbo;
- sincronizzazione col playhead;
- click testo -> posizione REAPER;
- riuso della cache Speech Engine senza nuova trascrizione.

### Fase 6 — estensione

- batch progetto;
- ricerca fuzzy;
- diarizzazione;
- SQLite FTS5 quando necessario;
- condivisione dell'indice fra più strumenti ZP.

## 18. Criteri di accettazione del primo MVP

Il primo MVP è riuscito quando:

1. un file WAV può essere passato a `zp-speech transcribe`;
2. il motore può usare MacWhisper sul sistema di sviluppo;
3. il risultato viene convertito nello ZP Speech Schema v1;
4. dallo stesso risultato si può generare un SRT valido;
5. una parola cercata nel JSON restituisce almeno il segmento e il timestamp nella sorgente corretto;
6. nessun codice del provider è incorporato nel 26;
7. il Core è progettato per accettare whisper.cpp senza modificare i client.

Il successivo MVP REAPER è riuscito quando una parola indicizzata in una sorgente continua a essere trovata nella posizione corretta del progetto dopo trim, taglio, spostamento o duplicazione dell'item, senza ritrascrivere inutilmente la sorgente.

## 19. Non-obiettivi iniziali

Non fare nella prima fase:

- incorporare Python/PyTorch in REAPER;
- leggere o modificare direttamente il database SQLite interno di MacWhisper come API di produzione;
- creare marker per ogni parola;
- includere modelli pesanti nel repository/ReaPack;
- implementare subito un motore cloud;
- implementare subito fuzzy search, diarizzazione avanzata o semantica LLM.

## 20. Decisione progettuale riassuntiva

ZP Speech Engine non è una funzione di SRT Tools.

È un servizio condiviso della ZP Suite che trasforma audio in informazione temporale ricercabile.

La catena concettuale è:

```text
AUDIO
  -> TRASCRIZIONE
  -> SOURCE TIME
  -> INDICE
  -> RICERCA
  -> MAPPING REAPER CORRENTE
  -> PROJECT TIME
  -> LOCALIZZAZIONE
```

SRT Tools usa la parte `audio -> trascrizione -> SRT`.

Gobbo usa la stessa trascrizione come rappresentazione testuale sincronizzabile dell'audio.

REAPER usa la stessa base per `parola/frase -> source time -> item corrente -> posizione nella timeline`.

Il provider reale può cambiare, la timeline può cambiare, ma il contratto ZP e l'ancoraggio alla sorgente restano stabili.
