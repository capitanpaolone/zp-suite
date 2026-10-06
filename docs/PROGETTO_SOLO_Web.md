# ZP SOLO Web — versione HTML del SOLO Recorder

Stato: **prototipo locale fatto** (2026-10-06), approvato da Paolo come "prototipo per gestione
locale". Prossimo passo dichiarato da Paolo: implementare la parte **online** dentro un altro suo
progetto, che mi fara' leggere. Non pubblicato su ReaPack, non committato.

## Perche'
- L'interfaccia web di REAPER ha gia' un canale adatto, ma le sue pagine (index, fancier...) sono
  fatte male. Paolo vuole una pagina HTML del SOLO.
- Vantaggi: telecomando vero da iPad/telefono in sala, grafica nitida e ridimensionabile,
  accessibilita' nativa (VoiceOver/NVDA), niente simulazioni di impaginazione gfx.

## Architettura: motore + pagina
```
 pagina zp_solo.html  --GET /_/SET/EXTSTATE/ZP_SOLO_WEB/cmd/<id|verbo|arg>-->  REAPER (web, porta 8080)
        ^                                                                            |
        |                                                            ZP_SOLO_Web_Motore.lua (defer, senza finestra)
        +---GET /_/GET/EXTSTATE/ZP_SOLO_WEB/state  (JSON, 20 volte/s) <--------------+
```
- **Motore** (`ZP Studio Suite/web/ZP_SOLO_Web_Motore.lua`, @noindex): tutta la logica sta qui
  (controllo traccia armata, pre-roll in secondi -> config `preroll`/`prerollmeas` via SWS, ingresso
  vero con `GetInputActivityLevel` in dB, marker con i contatori del SOLO). Esegue ogni comando una
  volta sola (id) e scrive l'id in `state.ack`. Rilanciarlo lo ferma (`set_action_options(1|4)`).
  All'uscita pubblica `{off:true}`.
- **Pagina** (`ZP Studio Suite/web/zp_solo.html`, installata in `REAPER/reaper_www_root/`): solo
  interfaccia. Coda comandi: uno alla volta, il successivo dopo l'ack (o 800 ms). Fascia rossa
  "Motore spento" se `state.t` non cambia da 1,5 s. Meter con balistica in JS (24 dB/s, picco 1,5 s).

## Protocollo (verificato sul REAPER vero, 2026-10-06)
- `GET /_/GET/EXTSTATE/sez/chiave` -> `EXTSTATE\tsez\tchiave\tvalore\n`; nel valore REAPER codifica
  `\t`, `\n`, `\\` (decodifica in un solo passaggio: `/\\(t|n|\\)/g`).
- `GET /_/SET/EXTSTATE/sez/chiave/valore`: il valore va con `encodeURIComponent`; **REAPER lo
  decodifica da solo** (provato con `a|b c/d;e%f\g"è`): il motore NON deve decodificare di nuovo.
- Comandi (`id|verbo|arg`): rec, stop, play (durante il REC = pausa, come REAPER), pause (azione 1008, anche del REC), back (-5 s), fine (ultimo item +5 s), preroll
  (acceso/spento), preroll_s (1-5), mark (arg = nome; vuoto = SOLO_MARK_NNN), save, undo, redo.
- Stato JSON: v, t, ack, msg, transport (STOP/PLAY/PAUSE/REC/REC_PAUSE), pos, tc, track, armed, input,
  in_db, rit_db, region, preroll, preroll_s, sws, dirty, can_undo, can_redo; `{off:true}` a motore spento.
- Condivide col SOLO: ExtState `ZP_SOLO_Recorder/preroll_s`, ProjExtState
  `ZP_SOLO_Recorder_Project/SOLO_MARK_counter`.

## Prototipo: cosa c'e'
Testata (Salva staccato, Annulla/Ripeti attenuati, pallino non salvato, spia motore), stato + timecode,
traccia/ingresso/regione/pre-roll; trasporto (-5s, REC con PRE, STOP, PLAY, fine +5s); meter IN/RIT in dB;
pre-roll − N s +; marker (bandierina + casella, Invio). Barra spaziatrice play/stop fuori dalla casella.
Si adatta al telefono. Lavora come il Telecomando (traccia = prima armata).

## Verifiche fatte
- Motore con REAPER finto: comando ripetuto eseguito una volta, pre-roll 4 s = 2 misure a 120 BPM,
  marker numerato e con nome (accenti, `|`), cursore fine +5 s, comando sconosciuto segnalato, JSON valido.
- Pagina con server finto che imita `/_/`: 4 comandi in coda eseguiti in ordine, REC, PRE, +, marker
  "Scena è 2"; vista telefono 375 px.
- REAPER vero: `/_/TRANSPORT` risponde, `zp_solo.html` servita (200) da `reaper_www_root`.
- Da fare con Paolo: caricare il motore nell'Action List e provare con REAPER vero.

## Aggiunte del 2026-10-06 (dopo la prima prova di Paolo: "funziona molto bene")
- PAUSA in tutti e due (SOLO gfx e pagina): pulsante piccolo fra STOP e PLAY; PLAY durante il REC = pausa
  come in REAPER; testata rosso scuro "REC in pausa".
- Lancio: nel SOLO gfx il **globo** in testata (gruppo Finestra) copia la pagina in reaper_www_root, accende
  il motore se non gira (`AddRemoveReaScript` sul file installato + Main_OnCommand) e apre il browser sulla
  porta letta da reaper.ini (`csurf_N=HTTP flag porta`). Azzurro = motore vivo (state.t fresco).
- Attenzione: Paolo aveva registrato il motore dal percorso del repo; il globo registra quello installato.
  Due registrazioni non fanno danni (il globo non lancia se un motore e' gia' vivo).

## Come si usa (locale)
1. REAPER: Preferenze > Control/OSC/web: c'e' gia' "Web browser interface" sulla porta 8080.
2. Nel SOLO clic sul globo in testata (oppure Actions > Load ReaScript: `Scripts/ZP Suite/ZP Studio Suite/web/ZP_SOLO_Web_Motore.lua`). Il motore e' un interruttore: lanciato una seconda volta si spegne.
3. Browser sul Mac: http://localhost:8080/zp_solo.html (da iPad: http://<ip-del-Mac>:8080/zp_solo.html).

## Mancano (per la versione completa)
Sessione SOLO (cartella e tracce MAIN/INSERTS/RETAKES/ALT), regione Take a ogni STOP, NEXT TAKE,
Retake/Insert/Alt take, Togli take, Nome/nota, etichette OK/BAD/ALT/NOISE, navigatore, scelta ingresso e
armamento, monitor, ritorno, Lock REC, toolbar. Strada: spostare la logica del SOLO in una libreria
comune usata sia dalla finestra gfx sia dal motore web, cosi' le due versioni non si separano.

## Online (prossimo progetto)
Il canale `/_/` di REAPER e' solo in rete locale e senza cifratura. Per l'online servira' un ponte
(il progetto di Paolo da leggere): autenticazione, HTTPS/WebSocket, nessuna porta di REAPER esposta
direttamente. Il protocollo comandi/stato qui sopra e' pensato per poter passare anche da li'.
