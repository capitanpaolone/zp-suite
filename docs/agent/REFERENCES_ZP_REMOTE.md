# REFERENCES_ZP_REMOTE — Riferimenti esterni di ZP Remote

> Documento canonico dei riferimenti esterni per l'architettura di ZP Remote (rinominato da `REFERENCES.md`; nessun contenuto tecnico modificato in questa rinomina). Vive in `docs/agent/` accanto a `ARCHITETTURA_ZP_REMOTE.md`, `CURRENT_ZP_REMOTE.md` e `ROADMAP_ZP_REMOTE.md`.
>
> Riferimenti esterni studiati/citati per l'architettura di ZP Remote. Per ognuno: repository/URL ufficiale, licenza (dove applicabile), tipo di progetto, cosa ci interessa studiare, e — punto esplicitamente richiesto — cosa NON significa la presenza del riferimento in questo documento.
>
> **Promemoria di principio (vale per tutte le voci sotto)**: usare un software/driver esterno installato, comunicare con esso, distribuirlo insieme al proprio prodotto, e incorporarne/copiarne il codice sono **quattro scenari diversi** con implicazioni legali diverse. Questo documento non prende decisioni legali definitive: registra solo licenza dichiarata e cosa vogliamo imparare. Nessuna decisione di incorporazione di codice GPL è stata presa in questa fase.
>
> Verificato via ricerca web il 5 settembre 2026 (fonti in fondo a ogni voce); dove non sono riuscito a verificare con certezza qualcosa lo dico esplicitamente.

---

## SonoBus

- **Repository ufficiale**: https://github.com/sonosaurus/sonobus
- **Licenza**: GPLv3 (confermato leggendo `LICENSE` nel repo: "GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007").
- **Tipo di progetto**: applicazione desktop/mobile open source di streaming audio di rete P2P in tempo reale per collaborazione musicale a distanza, di Jesse Chappell (sonosaurus). Basata su JUCE, usa il protocollo AOO (vedi voce sotto) per il trasporto.
- **Cosa ci interessa studiare**: come SonoBus separa il **networking audio P2P** dal resto (codec Opus/PCM selezionabili, gestione jitter/perdita pacchetti, riconnessione), come tiene il **signaling/server separato dal flusso media** (il flusso audio è P2P, non passa dal server una volta stabilita la connessione), e in generale come un sistema reale già in produzione ha affrontato gli stessi problemi che ZP Remote dovrà affrontare nella Fase 0 (Audio Feasibility Spike): latenza, qualità percepita, gestione dispositivi.
- **Cosa NON significa questo riferimento**: non significa "copiamo SonoBus" né incorporare il suo codice (GPLv3 — qualunque incorporazione futura andrebbe valutata con attenzione legale a parte, non decisa qui). Significa solo studiarne l'architettura pubblica come caso reale.
- Nota: esiste anche una copia storica su SourceForge (menzionata in una sessione precedente come `https://sourceforge.net/projects/sonobus.mirror/`) — il repository GitHub `sonosaurus/sonobus` è quello che ho verificato attivamente in questa sessione ed è quello da considerare ufficiale.

## AOO (Audio over OSC)

- **Repository canonico (dichiarato)**: https://git.iem.at/aoo/aoo (IEM — Institute of Electronic Music and Acoustics, Graz), versione attuale scritta principalmente da Christof Ressi come riscrittura completa in C del concetto originale di Winfried Ritsch (2009). Documentazione API: https://aoo.iem.sh/api_documentation/aoo_v2.0-pre4/
- **Repository correlato**: https://github.com/essej/aoo — **attenzione**: è un fork esplicitamente marcato dal suo stesso README come "usato SOLO per costruire SonoBus e software correlato, NON usare per altri scopi" — non è la versione da studiare come riferimento generale, solo quella integrata dentro SonoBus (`sonobus/deps/aoo`).
- **Licenza**: **non sono riuscito a verificarla con certezza in questa sessione** — il fetch diretto a `git.iem.at/aoo/aoo` ha restituito un errore (403) e la pagina di documentazione API non riporta la licenza. È una voce da chiudere prima di qualunque valutazione di riuso (vedi §6 del riepilogo finale in chat).
- **Tipo di progetto**: protocollo/libreria per streaming audio peer-to-peer "message-based" via OSC, pensato per topologie di rete arbitrarie (più sorgenti verso più destinazioni contemporaneamente).
- **Cosa ci interessa studiare**: il modello concettuale "audio come messaggi OSC" è rilevante perché la Suite ha già un precedente di OSC nel progetto Telecomando (ponte OSC-WebSocket per esporre i parametri JSFX, vedi `ARCHITETTURA_ZP_STUDIO_SUITE.md`/memoria) — capire se AOO è un livello di trasporto audio pertinente o solo un riferimento concettuale lontano dal nostro caso d'uso (voce/talkback punto-punto, non rete audio multi-topologia).
- **Cosa NON significa questo riferimento**: non significa che ZP Remote userà AOO come libreria — è annotato come "pertinente da valutare", non come dipendenza scelta.

## BlackHole

- **Repository ufficiale**: https://github.com/ExistentialAudio/BlackHole
- **Licenza**: GPLv3 (confermato leggendo `LICENSE` nel repo: "The BlackHole source code is licensed under the GNU General Public License v3.0").
- **Tipo di progetto**: driver audio virtuale per macOS (CoreAudio) che instrada audio fra applicazioni senza latenza aggiuntiva — un "cavo audio virtuale" fra processi sulla stessa macchina.
- **Cosa ci interessa studiare**: è il candidato più maturo per implementare l'`External Media Ingress` (`ARCHITETTURA_ZP_REMOTE.md` §13/§15) su macOS — instradare audio da un'applicazione esterna (es. una videochiamata, un player) verso REAPER o verso un futuro ZP Media Bridge, senza dover scrivere un driver CoreAudio proprio. Da valutare anche varianti multicanale (fork comunitari trovati in ricerca, es. `arvidtp/BlackHole` a 32 canali) e configurazioni Aggregate/Multi-Output Device.
- **Cosa NON significa questo riferimento**: non significa che BlackHole sostituisce WebRTC — ha un ruolo diverso (routing locale, non trasporto di rete, vedi `ARCHITETTURA_ZP_REMOTE.md` §13). Non significa nemmeno che lo distribuiremo insieme a ZP Remote: nella fase attuale si presume "installato dall'utente separatamente", non incorporato — se in futuro si volesse distribuirlo insieme al prodotto, la licenza GPLv3 andrebbe rivalutata a parte (scenario diverso da "usarlo installato").

## WebRTC (riferimenti ufficiali)

- **Sito del progetto**: https://webrtc.org — pubblicato dal team WebRTC di Google, con il supporto dichiarato di Apple, Google, Microsoft e Mozilla fra gli altri.
- **Specifica standard**: https://www.w3.org/TR/webrtc/ (W3C, "WebRTC: Real-Time Communication in Browsers"); gruppo di lavoro: https://www.w3.org/groups/wg/webrtc/publications/
- **Licenza**: non applicabile nello stesso senso delle voci sopra — è uno standard web (W3C) con implementazioni open source nei motori browser; l'uso è tramite le API native del browser (`getUserMedia`, `RTCPeerConnection`, ecc.), non tramite incorporazione di codice.
- **Tipo di progetto**: standard + implementazione di riferimento, non un prodotto a sé.
- **Cosa ci interessa studiare**: le API stesse (`getUserMedia`, selezione dispositivo, vincoli di codec/bitrate, `RTCPeerConnection`) sono la base tecnica della Fase 0 (Audio Feasibility Spike) e della Fase 4 (Artist Client + Media) — vanno lette direttamente dalla specifica/documentazione ufficiale, non ricostruite da memoria.
- **Cosa NON significa questo riferimento**: non è un fornitore di servizi (non fornisce TURN/signaling gestiti) — quelli restano da scegliere a parte (`ARCHITETTURA_ZP_REMOTE.md` §17).

## Source-Connect (Source Elements) — riferimento funzionale

- **Sito ufficiale**: https://www.source-elements.com/products/source-connect/ ; documentazione: https://support.source-elements.com/
- **Licenza**: non applicabile — prodotto commerciale proprietario, nessun codice sorgente disponibile da studiare.
- **Tipo di progetto**: software professionale per sessioni di doppiaggio/voiceover a distanza in tempo reale (Source-Connect Pro/Pro X, Source-Connect Link), di **Source Elements**, ampiamente usato nell'industria audio professionale — il tipo di prodotto con cui un fonico o un cliente di ZP potrebbe già avere familiarità. Tipicamente richiede un'applicazione/plugin installato, non solo il browser.
- **Cosa ci interessa studiare**: **solo il comportamento funzionale/UX** (parametri di sessione, workflow regia↔talent, aspettative di qualità/latenza del settore), non l'implementazione (non pubblica). È il riferimento di "cosa si aspetta un professionista del doppiaggio da una sessione remota", utile per validare le decisioni prese in `ARCHITETTURA_ZP_REMOTE.md` (es. audio artist→studio a qualità più alta possibile, REC/STOP come capability di regia).
- **Cosa NON significa questo riferimento**: non c'è alcun codice da incorporare (è proprietario) — è un riferimento di prodotto/UX, non tecnico-architetturale come SonoBus.

## SessionLinkPRO (SessionLinkPRO Solutions GmbH) — riferimento funzionale

- **Sito ufficiale**: https://www.sessionlinkpro.com/
- **Licenza**: non applicabile — prodotto commerciale proprietario di **SessionLinkPRO Solutions GmbH**, nessun codice sorgente disponibile da studiare.
- **Tipo di progetto**: "professional far end recording through your web browser" — registrazione remota professionale (doppiaggio/dubbing, conferencing) esplicitamente **via browser**, presentato come alternativa/evoluzione dell'ISDN. **Azienda e prodotto distinti da Source-Connect/Source Elements** — nella prima stesura di questo documento erano stati impropriamente accorpati in una sola voce; corretto qui.
- **Cosa ci interessa studiare**: è il riferimento funzionale **più vicino** a ciò che vogliamo per l'Artist Client (§9 di `ARCHITETTURA_ZP_REMOTE.md`), perché punta esplicitamente su "via browser" invece che su un'app/plugin dedicato — utile per validare aspettative di qualità/latenza e workflow per un client artist browser-only.
- **Cosa NON significa questo riferimento**: nessun codice da incorporare (proprietario); non è la stessa azienda o lo stesso prodotto di Source-Connect, e non va citato come se lo fosse.

---

## Riepilogo licenze (per chiarezza legale, non decisionale)

| Riferimento | Licenza | Implicazione per ora |
|---|---|---|
| SonoBus | GPLv3 | Solo studio architetturale, nessuna incorporazione codice |
| AOO (git.iem.at) | non verificata con certezza in questa sessione | Da chiarire prima di qualunque valutazione di riuso |
| BlackHole | GPLv3 | Uso come driver esterno installato dall'utente, non distribuzione/incorporazione. **Non è un requisito architetturale di ZP Remote** — solo una possibile implementazione macOS del `Local Media I/O` (`ARCHITETTURA_ZP_REMOTE.md` §13/§15) |
| WebRTC | standard W3C, non un pacchetto di codice da noi incorporato | Uso tramite API native del browser — core della v1, non uno "strumento a parte" |
| Source-Connect (Source Elements) | proprietario | Solo riferimento funzionale/UX, nessun codice disponibile |
| SessionLinkPRO (SessionLinkPRO Solutions GmbH) | proprietario | Solo riferimento funzionale/UX, nessun codice disponibile — azienda e prodotto distinti da Source-Connect |

*Documento prodotto da Claude (Cowork) il 5 settembre 2026, aggiornato in seconda fase di riallineamento architetturale ZP Remote, rinominato da `REFERENCES.md` a `REFERENCES_ZP_REMOTE.md` e consolidato in `docs/agent/` nella terza fase (chiusura della fase documentale). Nessuna decisione legale definitiva presa: da rivedere con attenzione se e quando si arriverà a incorporare o distribuire codice di terzi.*
