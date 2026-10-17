# Progetto — ZP Montaggio Parlato (evoluzione del 22)

Data: 2026-10-11 · Stato: proposta v2 (con le risposte di Paolo), nessun codice scritto
File: `ZP Studio Suite/22_Pulisci_Code_Silenzi_e_Separa_Item.lua` (v1.1.0; il nome file resta, cambia il titolo visibile)

---

## 1. Perché oggi funziona solo su file puliti

Il 22 è un **gate RMS**: una sola soglia per item (`rumore + 12 dB`), considera parlato tutto ciò che
sta sopra, poi trim o split con revisione obbligatoria di ogni segmento.

| Limite | Effetto pratico |
|---|---|
| Una soglia per tutto l'item | Se il fondo cambia, è sbagliata per metà del file |
| Ascolta solo l'energia | Respiri forti, clic, pagine girate valgono come voce |
| Non sa *cosa* è stato detto | Una falsa partenza è parlato quanto la frase buona |
| Sa solo **tenere** pezzi | Non taglia dentro il parlato continuo |
| Silenzio = da togliere | Non distingue una pausa voluta da un buco |
| Revisione obbligatoria di ogni segmento | Su un'ora di lettura APPLICA resta bloccato |
| Cambi un parametro → decisioni perse | La revisione si azzera |
| Analisi nel ciclo della finestra | Su file lunghi la finestra si blocca |

Il gate resta utile per **dove** cade un taglio. Manca **cosa** si sta tagliando.

---

## 2. Principio: il testo decide *cosa*, l'audio decide *dove*, il respiro resta

```
 1. AUDIO        gate adattivo (fondo misurato a tratti) + rilevatore di schiocchi/click
 2. PAROLE       ZP Speech / MacWhisper con tempi per parola (contratto v1 già con words)
 3. COPIONE      allineamento parole dette ↔ testo originale (locale, niente AI)
 4. COMANDI      parole chiave dette in sala + schiocco/click come segnale di ripresa
 5. AGENTE AI    facoltativo, a richiesta, solo sui dubbi
 6. RESPIRI      (fase successiva) energia tra le parole senza parola
```

### 2.1 Regola del respiro (mai "incollato a muro")
Ogni pausa che resta deve **suonare come un respiro**, non come una spillatrice.
- Una pausa si accorcia **togliendo dal centro**: resta la coda naturale della frase prima
  (decadimento + ambiente) e resta **intera l'inspirazione** prima della frase dopo.
- **Pausa minima garantita** (es. 0,45 s tra frasi, 0,30 s a una virgola; regolabile): nessun taglio
  scende sotto. Pause già più corte della minima non si toccano.
- La giunzione è una dissolvenza incrociata su ambiente (20–40 ms), non su silenzio digitale.
- "Stringere" = abbassare la pausa obiettivo, mai la minima sotto una soglia di sicurezza (~0,25 s).

### 2.2 Perché ibrido e non solo Whisper
- Whisper **ripulisce** ripetizioni ed esitazioni: dove il gate sente voce ma Whisper non ha parole
  → "parlato non trascritto" = candidato falsa partenza.
- I tempi di Whisper sbagliano di 100–200 ms → ogni taglio si aggancia alla **valle di energia** più vicina.
- Whisper a volte inventa sui silenzi lunghi → una parola senza energia sotto non conta.
- Verificato oggi: la CLI di MacWhisper (`mw transcribe`) **non** accetta un prompt iniziale né
  dà la confidenza per parola. Quindi la contromisura audio è essenziale, non opzionale.

---

## 3. Cosa riconosce

### 3.1 Testa, coda e pause interne (senza copione, senza AI)
- Testa/coda: dalla prima all'ultima parola vera, con la regola del respiro ai bordi.
- Pause interne: **accorciate** a una durata obiettivo secondo §2.1, non spezzate.

### 3.2 Comandi parlati e segnali

| Detto / fatto in sala | Cosa succede |
|---|---|
| «**alternativa**» | Le due versioni restano entrambe. La seconda va nella **corsia sotto** (REAPER 7, corsie fisse) o resta in fila colorata. La parola-comando viene tolta. Blocca la regola "vince l'ultima". |
| «**silenzio di N secondi**» | Comando tolto; al suo posto N secondi di **ambiente del file** (vedi 3.3). Nota «SILENZIO N s». |
| «**slide numero N**» / «**traccia numero N**» | Punto di divisione: da qui inizia un nuovo item chiamato «Slide N» / «Traccia N». Utile quando una registrazione lunga contiene molte slide. |
| «**rifaccio**» | Ripresa dichiarata: quello che c'era prima, dal punto in cui riparte il testo, è da togliere (§3.4). |
| **schiocco di dita / click forte** | Stesso significato di «rifaccio». Riconosciuto dall'audio: impulso brevissimo e forte, isolato, fuori dalle parole. Lo schiocco stesso viene tolto. |

Con il copione i comandi sono sicuri: se «alternativa» è scritta nel testo, in quel punto non è un comando.

### 3.3 Silenzio dichiarato con l'ambiente del file
- L'analisi cerca nel file il **tratto più silenzioso** (almeno ~0,5 s, senza respiri né clic) e lo usa
  come campione di ambiente.
- Il silenzio di N secondi è fatto di copie di quel tratto (item che puntano allo stesso WAV, con
  dissolvenze incrociate): niente render, niente file nuovi.
- È un segnaposto fedele: la lavorazione finale (catena di processamento) lo tratterà come il resto del file.

### 3.4 False partenze, «rifaccio» e taglia-e-cuci
È il caso più frequente: una parola inciampata **in mezzo a una frase**, poi la ripresa.
1. Il segnale (rifaccio / schiocco / ripetizione trovata dal copione) indica *che* c'è una ripresa.
2. Il copione (o, senza copione, le parole uguali ripetute) indica *da dove* riparte la lettura.
3. Si cerca il punto di cucitura: fine dell'ultima parola buona prima dell'inciampo ↔ inizio della
   stessa parola nella ripresa, entrambi su una valle di energia.
4. **Se la cucitura è pulita** (c'è una micro-pausa vera tra le parole) → taglia e cuci proposto, sicurezza alta.
5. **Se non lo è** (parole legate, coarticolazione, nessuna valle) → **bandierina rossa «Controllare»**:
   non si taglia in automatico, il montatore decide a orecchio.

Regola generale: lo stesso pezzo letto due volte di fila → **vince l'ultima lettura completa**.

### 3.5 Errori di lettura vs errori di Whisper
Con il copione sotto mano ogni differenza viene classificata, non solo segnalata:

| Differenza | Esempio | Classe |
|---|---|---|
| Solo scrittura | «15» / «quindici», apostrofi, maiuscole, punteggiatura | ignorata (normalizzazione, riusa `ZP_cerca.lua`) |
| Nome proprio o parola rara scritta diversamente ma suona uguale | «Leapmotor» / «Lip motor» | **Whisper** — grigio, non conta |
| Parolina scambiata | «nel» al posto di «del», «il»/«lo», «un»/«una» | **Possibile errore di lettura** — giallo |
| Parola cambiata, invertita, saltata o aggiunta | | **Errore di lettura probabile** — arancione; le omissioni vanno nel rapporto |

Per i casi gialli il giudice è l'orecchio: un tasto ascolta i 2 secondi con **copione e trascrizione
uno sopra l'altro**. Aiuti facoltativi: ritrascrivere solo quel frammento (se esce uguale al copione
era Whisper) e, a richiesta, l'agente AI.

### 3.6 Respiri (fase 5)
Tra due parole, energia sopra il fondo ma senza parola = respiro. Si misura rispetto alla voce attorno.
Azione senza automazioni: respiro come piccolo item con volume item ridotto o accorciato (mai tolto del tutto).

---

## 4. Ambito: il tempo è la costante

Due modi di percorrere il lavoro, sulla **traccia selezionata** (o più tracce):
- **Slide separate**: ogni item della traccia è un'unità a sé (pulizia di testa, coda, pause, riprese).
- **Timeline**: si parte da 0 (o dal cursore, o da una selezione di tempo) e si va avanti; ogni
  item incontrato lungo il percorso è un candidato.

Le trascrizioni passano dalla **coda in background del 29** (non una seconda coda) e restano in cache
accanto al WAV: se il file non cambia, non si ritrascrive.

---

## 5. Non distruttivo: si decide sulla console, si lavora sulla traccia

- La **console** (finestra ZP Montaggio Parlato) mostra il piano e serve a decidere.
- Il risultato sono **modifiche agli item sulla traccia REAPER**: split, trim, spostamenti, dissolvenze.
  Il WAV non si tocca mai; tutto in un solo Undo.
- Lo spostamento indietro dopo un taglio riguarda **solo la traccia in lavorazione**, non musica o altre voci.
- Facoltativo: l'originale intatto in una **corsia fissa sotto che non suona** (REAPER 7), per tornare
  indietro su un punto senza Undo.

### 5.1 Il Piano di montaggio
Ogni intervento ha: tipo, tempo sorgente, azione proposta, **testo coinvolto**, chi lo propone
(audio / copione / comando / agente), sicurezza (alta / media / bassa / bandierina rossa).
- Salvato con il progetto: si chiude REAPER e si riprende. Cambiare un parametro non cancella le decisioni prese.
- **Revisione per eccezioni**: i sicuri sono già approvati, ti mostro solo dubbi e bandierine rosse.

### 5.2 Note di montaggio: né marker di progetto né take marker
- **Marker di progetto**: no, ingombrano il righello e la gestione progetto.
- **Take marker**: no, nella Suite sono il **testo della trascrizione** (li legge Sincronizza, il Gobbo,
  il 31 li esporta in SRT): note di montaggio lì finirebbero nei sottotitoli.
- **Scelta: una traccia note nascosta** «ZP Montaggio <voce>», come le tracce «Rythmo Band Testi»:
  item vuoti colorati (rosso = controllare, giallo = possibile errore, verde = fatto) con la nota in
  `P_NOTES`. Un pulsante la **mostra/nasconde**. Le note restano **agganciate al tempo sorgente**
  con lo stesso meccanismo di `ZP_sincronizza_aggancio.lua`, quindi seguono i tagli.
- Il Gobbo può mostrarle (stessa forma dei testi): trascrizione e note di montaggio nello stesso posto.

---

## 6. Il copione

Formati: **doc, docx, rtf, odt** (con `textutil`, già in macOS) e **pdf** (`pdftotext`, presente su questo
Mac; sul MacBook va verificato o si usa una libreria nel runtime di ZP Speech). XLS: lo estrai tu.
Si può anche incollare. Il testo estratto si mostra prima dell'uso, così vedi se il PDF è uscito pulito.

Comando nuovo nel motore: `zp-speech copione <file>` → testo semplice.

---

## 7. Agente AI (facoltativo, sempre a richiesta)

Solo dopo l'analisi locale, solo con un pulsante, con la frase che dice dove va il testo (`ZP_Agenti.lua`;
Ollama = resta sul Mac). Riceve **solo testo** (casi dubbi + pezzo di copione), mai audio. Risponde con
una classificazione e una riga di motivo; entra nel piano come proposta, mai come decisione.
Comando nuovo `zp-speech edit-plan`, riusando `PromptAgent` di `translate.py`.

---

## 8. Cosa si riusa (niente doppioni)

| Già nella Suite | Uso qui |
|---|---|
| 22: lettura AudioAccessor + gate (unico script che legge campioni) | base del livello audio, reso a blocchi |
| ZP Speech: servizio, `request`, contratto v1 con `words` | trascrizione con tempi per parola (serve uscita JSON accanto all'SRT) |
| 29: coda di trascrizione in background (`start_batch` / `poll_batch`) | stessa coda, non una seconda |
| `ZP_sincronizza_aggancio.lua`: chiave take GUID + tempo sorgente, formula sorgente→timeline, tracce testo nascoste, orfani | traccia note di montaggio che segue i tagli |
| `ZP_cerca.lua`: normalizzazione accenti/maiuscole | confronto copione ↔ trascrizione |
| `ZP_Agenti.lua` + `PromptAgent` | agente sui dubbi |
| `ZP_UI.lua`, `ZP_Lingua.lua` (T) | finestra, firma, inglese |
| Regole marker di servizio (14, 31, ANTI_REGRESSIONE) | le note di montaggio non diventano mai testo |
| 01: tracce nascoste, corsie | corsia alternative / originale |
| `help/voice_cleaner.html` | da riscrivere come help di ZP Montaggio Parlato |

---

## 9. Architettura

| Parte | Dove |
|---|---|
| Audio: gate adattivo, valli, schiocchi, tratto più silenzioso | Lua (22), a blocchi con `defer` e barra di avanzamento |
| Trascrizione con parole | ZP Speech (esiste) |
| Copione: estrazione, allineamento, classificazione differenze, comandi parlati | Python `zp-speech` (pytest) |
| Agente | `zp-speech edit-plan` |
| Piano: fusione, regola del respiro, cuciture, revisione, applicazione | Lua, modulo puro `ZP_Montaggio.lua` (test in `run_all.sh`) + UI nel 22 |
| Note di montaggio | Lua, riusando le funzioni di `ZP_sincronizza_aggancio.lua` |

---

## 10. Fasi

| Fase | Contenuto | AI | Copione |
|---|---|---|---|
| **F0 Fondamenta** | Piano JSON, cache parole, analisi a blocchi, traccia note mostra/nascondi, nuova console (mockup da scegliere) | no | no |
| **F1 Sgrossatura** | Testa/coda, pause con regola del respiro, comandi alternativa / silenzio N / slide N / rifaccio, schiocco, ambiente del file, revisione per eccezioni, slide separate e Timeline | no | no |
| **F2 Copione** | Import doc/docx/pdf, allineamento, false partenze e taglia-e-cuci, classificazione errori di lettura vs Whisper, rapporto omissioni | no | sì |
| **F3 Agente** | Dubbi all'agente, a richiesta | sì | facoltativo |
| **F4 Respiri** | Rilevamento, livello, attenuazione con volume item | no | no |

---

## 11. Rischi da verificare

- Schiocco vs consonanti esplosive («p», «t» forti): il rilevatore deve chiedere che l'impulso sia **isolato**
  (silenzio prima e dopo). Da tarare su registrazioni vere di Paolo.
- Le parole-comando devono essere trascritte bene da Whisper: test su un file di prova con tutti i comandi.
- `pdftotext` sul MacBook.
- Item già tagliati, spostati, con playrate: conversione sorgente→timeline con test dedicati (la formula
  esiste già e va riusata, non riscritta).

## 12. Prossimo passo
Mockup della console (2–3 varianti da scegliere) e un file di prova registrato con: una falsa partenza
a metà frase, un «rifaccio», uno schiocco, un'«alternativa», un «silenzio di 5 secondi», un «slide numero 2».

---

## 13. Prima prova su un file vero (2026-10-12)

File: `Il DJ differenziale/u87 e gli altri/Media/01-261012_1301.wav` (120,7 s, 48 kHz 24 bit mono).
Copione: tre frasi del promo «Sagra della Zucca». Prototipo Python fuori da REAPER (energia a 10 ms,
ZP Speech JSON con parole, confronto col copione); niente toccato nella Suite.

### 13.1 Whisper ha saltato 18 secondi di voce
Trascrizione del file intero: **nessuna parola tra 57,5 e 82,7 s**. L'energia dice invece voce forte
(fino a −15 dB RMS) tra **61,0 e 79,1 s**. Ritrascritto solo quel pezzo, esce:
«Sabato 31 ci sarà la strega Bertuz con giochi per bambini. Sagra della zucca… a San Carlo di Ferrara.
La domenica solo a pranzo. **Slide 2 oppure take 2.**»

Conseguenza per il progetto: il controllo «voce senza parole» + **ritrascrizione automatica del solo
frammento** non è un aiuto facoltativo, è un passo obbligatorio dell'analisi (locale, niente AI).

### 13.2 I comandi che Paolo usa davvero
Trovati nel file, senza averli concordati prima: «Ok, allora», «Allora, primo», «**Rifaccio**»,
«**Riprovo. Versione 2**», «**Slide 2 oppure take 2**», «**Alternativa**». Nessuno schiocco in questo file.
→ Vocabolario iniziale: rifaccio / riprovo · versione N / take N / slide N · alternativa · silenzio di N secondi.
Il resto («ok», «allora», «primo») = parlato fuori copione, da togliere.

### 13.3 Le letture trovate (ogni frase del copione, dove è stata letta)

| Frase | Letture |
|---|---|
| Prepara il palato | 28,7 s (unica) |
| Ritorna la Sagra … il Primo novembre | 30,4 s (interrotta: «…31 ottobre… Rifaccio», ripresa a 39,3) · 82,7 s |
| Gusterai i cappellacci … piatti tipici | 42,9 s · 95,1 s |
| Sabato 31 … giochi per bambini | 47,7 · 60,8 · 98,6 s |
| Sagra della Zucca … a San Carlo di Ferrara | 66,4 · 103,4 · 112,6 s (dopo «Alternativa») |
| la domenica solo a pranzo | 71,4 · 108,7 · 117,6 s |

### 13.4 Taglia e cuci del «Rifaccio» (34,9 → 39,3 s)
«…profumo di tartufo.» finisce a 34,88; pausa con valle a −59 dB (inspirazione), poi «Il 30 e 31 ottobre…
Rifaccio.» Ripresa «Il 30 e 31 ottobre e il primo novembre» a 39,33, preceduta da 0,7 s sotto −60 dB.
Entrambi i punti sono puliti → **taglio sicuro**, con la regola del respiro: resta la coda di «tartufo»,
resta l'inspirazione prima di «Il».

### 13.5 Differenze col copione (classificate)

| Dove | Copione | Detto (Whisper) | Seconda prova sul frammento | Classe proposta |
|---|---|---|---|---|
| 47,3 · 98,5 | IGP | GP | GP | Whisper (sigla), ignora |
| 95,1 | cappellacci | capellacci | capellacci | Whisper (grafia), ignora |
| 94 | Primo novembre | 1 novembre | — | solo scrittura, ignora |
| 82,7 | ritorna **la** | ritorna **alla** | alla | giallo: possibile errore di lettura |
| 95,1 | **gusterai** | **gusterà** | gusterà | giallo: possibile errore (la lettura a 42,9 dice «gusterai») |
| 108,7 | solo a pranzo | sola pranzo | sola pranzo | giallo: ascoltare |
| 117,6 | solo a pranzo | sola pranzo | sola **a** pranzo | giallo: probabile Whisper, ascoltare |
| 71,4 | solo a pranzo | — (saltato) | solo a pranzo | corretto |

### 13.6 Due montaggi possibili — qui serve una regola
- **M1 «vince l'ultima completa»**: «Prepara il palato» (28,7, unica) + lettura completa 82,7–109,7 +
  alternativa 112,6–118,7 nella corsia sotto. Porta con sé tre gialli (alla, gusterà, sola).
- **M2 «più fedele al copione»**: prima lettura 28,7–34,9 + 39,3–52,5 (col taglia e cuci) + 66,4–72,7.
  Nessun giallo; le letture successive restano come alternative.

Proposta: M1 di partenza, ma quando un'altra lettura della **stessa frase** è più fedele, il piano lo
dice e offre lo scambio con un tasto («usa la lettura delle 42,9»). Decide il montatore.

### 13.7 Altre osservazioni
- 0–25 s: «Ok, allora» e rumori bassi di preparazione → testa da togliere.
- Alcuni tratti scendono a −83/−90 dB, sotto il fondo della stanza (~−72/−74): c'è probabilmente un
  gate/espansore nella catena di registrazione. Per il silenzio dichiarato va preso il tratto più
  silenzioso **che ha ancora fondo vero** (qui 58,3 s, −72 dB), non un buco digitale.
- Tempo: trascrizione del file intero 28 s; ogni frammento pochi secondi.

---

## 14. Ordine di lavoro e regole di montaggio (da Paolo, 2026-10-12)

Questa sezione **prevale** su §3.4, §3.5 e §13.6 dove sono in contrasto.

### 14.1 Principi
- **Il testo fa fede.** Whisper non conosce la logica del discorso («gusterai»: si parla a un tu).
- **Il software sgrossa, il lavoro di fino si fa ascoltando in Timeline.** La console non cerca il taglio
  perfetto: porta il materiale grezzo vicino al montato, in fretta, e segna dove ascoltare.

### 14.2 Ordine delle fasi
1. **Fase 1 — Struttura (macro).** Letture, comandi, rifacimenti, false partenze, parlato fuori testo.
   Si decide quale lettura resta. Tutto ciò che sta in una parte scartata (per esempio quello che precede
   un rifacimento) **non viene più controllato**: un errore lì dentro è già sparito.
2. **Fase 2 — Parole, solo sul materiale tenuto.** Ogni differenza col testo si ascolta e si chiude con
   uno di due tasti: **«Ha sbagliato Whisper»** (la differenza sparisce) oppure **«Ho letto male»**
   (resta come errore). Per un errore confermato: se un'altra lettura della stessa frase è giusta, il
   piano propone lo scambio; se no, nota rossa per il ritocco.
3. **Fase 3 — Pause** (sgrossatura secondo il genere, §14.4).
4. Respiri: solo appunto per ora (§14.5).

Perché in quest'ordine: la Fase 1 elimina interi pezzi, quindi la Fase 2 ha meno differenze da
ascoltare e nessuna su parti già buttate.

### 14.3 Regola del rifacimento: inizio su inizio
Dopo un rifacimento (schiocco, click forte, «rifaccio», «riprovo») si riparte quasi sempre da una pausa:
una virgola, un respiro, una consonante. La prima versione è l'errore, quella dopo il segnale è la buona.
**Il taglio va dall'attacco della prima versione all'attacco della seconda, esattamente.**
Così il respiro prima della prima versione resta, e la seconda entra al suo posto.

Misurato sul file di prova («Il 30 e 31 ottobre… Rifaccio. Il 30 e 31 ottobre e il primo novembre»):

| | Whisper dice | Attacco vero (energia) |
|---|---|---|
| prima «Il» | 35,350 s | **35,425 s** |
| seconda «Il» | 39,330 s | **39,400 s** |

Taglio: **35,420 → 39,395** (4 ms prima di ciascun attacco, dissolvenza di pochi ms). Tolti 3,975 s.
Whisper anticipa gli attacchi di 70–75 ms: l'attacco va sempre cercato nell'energia.
L'inspirazione prima della prima «Il» (35,03–35,42) resta, come vuole la regola del respiro.

### 14.4 Parlato stretto (spot, broadcast)
Negli spot le parole sono fuse e scivolate: tra una parola e l'altra spesso non c'è nessuna pausa.
- I punti di taglio non sono pause ma **attacchi**: l'inizio di una parola dopo una virgola o un respiro,
  oppure la **chiusura di una consonante occlusiva** (p, t, k, b, d, g: un attimo di quasi silenzio prima
  dello scoppio), o l'inizio di una s/f.
- Vocale fusa con vocale, nessun attacco netto → **bandierina rossa**, si decide in Timeline.

### 14.5 Pause e respiri secondo il genere (appunto, da sviluppare dopo)
- **Spot e prodotti ritmati**: i respiri spariscono, lo spazio che occupavano si riduce **a metà**.
- **Narrazioni lunghe**: si tolgono i respiri che anticipano un capitolo nuovo; quelli intermedi, se
  leggeri, restano o si azzerano.
→ Nella console: scelta di genere **Spot / Narrazione** che imposta queste regole.

### 14.6 Conseguenza per §13.6
La scelta della lettura è della Fase 1 e segue i segnali dichiarati: dopo «rifaccio», «riprovo»,
«versione 2», «take 2» vale quella dopo. «Vince l'ultima completa» resta la regola quando non c'è
un segnale. La fedeltà al testo entra in Fase 2, come proposta di scambio.

---

## 15. Decisioni del 2026-10-12 (seconda parte)

- **Mockup scelto: C** (il copione come pagina), con tasto per la lista dei dubbi.
- **Sgrossatore, non fine editor.** I tempi in millisecondi della §14.3 sono solo la prova che l'attacco si
  trova; nella console non si mostrano e non si regolano. Basta non mozzare una sillaba: il fino in Timeline.

### 15.1 Segnali: «usa click» / «usa parole» (dizionario deterministico)
Come con il nastro e il montatore a cui si dichiarava cosa fare: Paolo sceglie le parole, il sistema le
riconosce e monta. Nessuna AI.
- Modo segnale: **Click** · **Parole** · **Entrambi**.
- Dizionario modificabile (parola → azione). Partenza:

| Parole | Azione |
|---|---|
| rifaccio · riprovo | rifacimento: inizio su inizio, vale quella dopo |
| alternativa · versione alternativa | tieni entrambe, la seconda in corsia sotto; **di cosa è alternativa lo dice il testo** (allineamento col copione) |
| silenzio di N secondi | N secondi di ambiente del file |
| slide N · take N · versione N | divisione / nuova lettura |

- Una parola del dizionario che sta dentro il copione in quel punto **non** è un comando.

### 15.2 Click: prova su `01-261012_1235.wav`
Rilevatore: picco brevissimo, sale di oltre 15 dB in 5 ms e ricade di oltre 12 dB entro 40 ms.
- I 4 click a **6:12.270 · 6:12.420 · 6:12.680 · 6:12.795**: trovati tutti, picco **−3/−5 dBFS**.
- Falsi allarmi sullo stesso file: 3:49.4 (−19 dB), 6:01.2 (−26 dB), 8:23.6 (−35 dB). Sull'altro file: 2.
- Distinzione facile: i click veri sono **molto più forti** della voce e arrivano **a gruppo**.
  → Taratura una volta sola: «insegna il tuo click» (si seleziona un click, il sistema ne prende livello e forma).

### 15.3 Lo stesso gruppo di click è anche nel file 1301 (1:29.830–1:30.350)
Stesso gruppo di click del 1235 (picchi identici: incollati in entrambi). Lì Whisper sul file intero aveva **nascosto il rifacimento**:
«ottobre… **e**» con la «e» lunga 4 secondi sopra i click e la ripresa. Ritrascrivendo da dopo i click
esce «Il 30 e 31 ottobre e il 1 novembre» a 1:31.16. Quindi:
- la lettura «ultima completa» (82,7–109,7) contiene a sua volta un rifacimento a click;
- **i segnali tagliano i frammenti da ritrascrivere**: mai un frammento a cavallo di un click.

### 15.4 Il copione si dà prima dell'analisi (Fase 0)
Sì: il primo passo della pagina C è «Copione» (doc, docx, pdf, oppure incollato). Il testo estratto
si mostra per conferma. A MacWhisper non si può passare (la CLI non accetta testo guida), quindi
il copione si usa **dopo** la trascrizione, per:
- separare il testo letto dal **parlato di commento** (quello che non si allinea al copione = fuori testo);
- non scambiare per comandi le parole del dizionario che sono nel testo;
- conoscere nomi e sigle (Bertuz, IGP) e non segnalarli come errori;
- scegliere le letture.
La trascrizione resta in cache: si può caricare o cambiare il copione anche dopo, e l'analisi si rifà in pochi secondi.
