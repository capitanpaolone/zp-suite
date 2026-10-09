Sei il collaboratore di Paolo Balestri (italiano; preferisce testi chiari e diretti) sulla ZP Studio Suite per REAPER. Rispondi in italiano. Lavoro lungo e meccanico: risparmia token, procedi a blocchi, lascia traccia di tutto.

REPO: ~/Documents/ZP/zp-suite (branch di lavoro codex/zp-speech-phase-1-macwhisper)
MEMORIA: gobbo_ricerca_battuta/MEMORIA.md (leggila per intero) e gobbo_ricerca_battuta/ANTI_REGRESSIONE.md.

REGOLE FERME: niente commit, push, tag, version bump o ReaPack senza richiesta di Paolo. Mai `git stash` (c'e' uno stash vecchio di Paolo). Prima di ogni modifica importante copia il file in gobbo_ricerca_battuta/backup/. `bash gobbo_ricerca_battuta/test/run_all.sh` deve finire con TUTTO OK. Ogni modifica = una riga nel registro di MEMORIA.md. Prima di fermarti: riga "STOP: dove sono arrivato, prossimo passo esatto".

OBIETTIVO (decisione di Paolo, 2026-10-09)
A. ZP Studio Suite in INGLESE (prima), poi altre lingue con lo stesso sistema. L'italiano resta la lingua originale nel codice.
B. REAPER in ITALIANO: un language pack (.ReaperLangPack) SOLO per menu, finestre e messaggi. NON tradurre l'elenco delle action (sezioni delle azioni): chi usa REAPER le conosce in inglese, come nei forum.

METODO A RISPARMIO DI TOKEN (vale per A e B)
1. Catalogo una volta sola: file "originale -> traduzione" (A: `ZP Studio Suite/lang/en.txt`, una voce per riga, formato semplice e leggibile da Lua). Si traduce solo cio' che nel catalogo manca o e' cambiato: un aggiornamento costa poche righe.
2. Niente doppioni: frasi uguali una volta sola. Prima conta le voci uniche e scrivi il numero in MEMORIA.
3. Glossario fisso in testa al lavoro (gobbo_ricerca_battuta/glossario_traduzione.md): restano in inglese item, take, marker, region, track, render, ripple, trim, loop, edit, FX, bus, send, toolbar, SRT, take marker. Nomi degli strumenti ZP (Gobbo -> Teleprompter? chiedi a Paolo UNA volta e annota la risposta), sigle e tasti invariati.
4. Blocchi grandi (100-200 voci) con istruzioni brevi una volta per blocco; risposta solo JSON o righe numerate; controlla che il numero di voci torni.
5. La traduzione la fa l'agente via ZP Speech quando conviene (`zp-speech translate` per SRT; per cataloghi puoi aggiungere un comando simile in speech-engine/src/zp_speech, con test, sul modello di `explain-keys`), oppure direttamente tu. Ollama (locale) va bene per le bozze; rileggi tu il risultato.
6. Testi segnaposto (%s, %d, \n, nomi di file, percorsi, sigle) intatti: aggiungi un controllo automatico.

PARTE A: la Suite in inglese
- In ZP_UI.lua (o in un nuovo ZP_Lingua.lua [nomain], da aggiungere al @provides del 00) una funzione `T(testo)` che restituisce la traduzione dal catalogo della lingua scelta, o il testo stesso se manca. Lingua: ExtState persistente ZP_STUDIO_SUITE/lingua ("it" di serie; scelta nel 33 Benvenuto con un menu). Logica pura testabile fuori da REAPER + test in gobbo_ricerca_battuta/test/.
- Uno script di estrazione (gobbo_ricerca_battuta/strumenti/) che trova i testi visibili negli script (drawstr, draw_button, MB/ShowMessageBox, status, suggerimenti, menu gfx.showmenu, messaggi OSARA) e aggiorna il catalogo con le voci nuove. Non estrarre: chiavi ExtState, nomi di file/tracce/marker di servizio (#, !, SOLO_*), comandi, nomi di azioni REAPER.
- Avvolgi i testi in T(...) uno script alla volta, cominciando dai piu' visibili: 33 Benvenuto, 35 Colori, 34 Set Comandi, 29 Trascrizione, 25 SOLO Recorder, 02/03 Gobbi. Attenzione: 25 e' al limite di 200 variabili locali (vedi ANTI_REGRESSIONE); i numeri delle voci del menu OSARA del Gobbo non cambiano.
- Testo che non entra nei pulsanti: l'inglese e' spesso piu' corto, ma controlla con UI.fit_text dove serve.
- Help: help/en/ con le pagine tradotte (stesse ancore); UI.open_help apre la lingua scelta se la pagina c'e'.
- Dopo ogni script: luac, run_all, e istruzioni per Paolo per provarlo in REAPER (un passo per riga).

PARTE B: REAPER in italiano (dopo A, o in parallelo se Paolo lo chiede)
- Parti dal template ufficiale in inglese (reaper.fm, pagina dei language pack: "template" .ReaperLangPack con le righe commentate ';'), NON da un pack di un'altra lingua. Controlla prima se esiste gia' un pack italiano della comunita' (forum Cockos / stash): se c'e' e la licenza lo permette, completalo invece di rifarlo.
- Traduci [common], menu e finestre (DLG_*, MENU_*...); lascia commentate (';') le sezioni delle action. Scala le finestre dove l'italiano non entra (5CA1E00000000000=scala).
- File finale: ~/Documents/ZP/zp-suite/REAPER_Italiano/Italiano (ZP).ReaperLangPack (non dentro i pacchetti ReaPack finche' Paolo non decide). Paolo lo prova copiandolo in REAPER/LangPack e scegliendolo in Preferences > General.

Quando hai finito un blocco, riassumi a Paolo in 5 righe: cosa e' tradotto, quante voci, cosa resta, come provarlo.
