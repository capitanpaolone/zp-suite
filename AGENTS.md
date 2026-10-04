# ZP Suite — memoria operativa agenti

Aggiornata: 2026-09-09

## Percorsi e vincoli

- Percorso risorse REAPER corrente: `/Users/paolob/Library/Application Support/REAPER`.
- Non usare il vecchio percorso `Reaper26` salvo richiesta esplicita per installazioni legacy.
- Per i file JSFX preservare ordine delle sezioni, indici degli slider pubblici e compatibilità con progetti REAPER esistenti.
- Non eseguire commit o push senza richiesta esplicita.
- Archivio storico di sicurezza obbligatorio: `/Volumes/DISCO LACIE/Archivio_Storico_ZP`.
- Dopo ogni fase significativa, prima di interventi rischiosi e prima di sostituire una baseline funzionante, conservare nell'archivio una copia identificabile tramite data/fase e SHA-256.
- Preferire un report Markdown con stato consolidato, risultati, hash, percorsi e istruzioni di ricostruzione quando non serve duplicare il plugin.
- Quando il plugin cambia realmente, conservare anche uno snapshot immutabile del `.jsfx`; non sovrascrivere né eliminare snapshot precedenti validi.
- Non scartare lavoro funzionante per rifacimenti estetici o sperimentali. Ripartire dall'ultima baseline verificata salvo errori grossolani dimostrati.

## ZP Stagekeeper Dialogue Director

File principale:

`ZP Voce/ZP Stagekeeper Dialogue Director.jsfx`

Stato corrente: versione sorgente `2.5.0`, con rifacimento DSP della Dominance Engine (fader smoothing in dB, Softness continua, timing asimmetrico corretto).

Decisioni implementate:

- Il monitor operativo è lo slider 34: `MIX | CHECK L | CHECK R`.
- `MIX` è lo stato iniziale e fail-safe.
- `CHECK L/R` duplica sulle due uscite il relativo canale dopo `gate_l/gate_r`; Master e limiter restano a valle.
- Entrambi gli ingressi continuano a pilotare la dominance durante CHECK: Gate Off permette il confronto integro, Gate On fa ascoltare quando e quanto il canale selezionato viene attenuato dall'altro microfono.
- Gli slider 31 e 32 sono mantenuti agli stessi indici come legacy, ma vengono neutralizzati e non pilotano più l'audio.
- [STATO STORICO — SUPERATO dalla Fase A del 2026-09-09, vedi "STATO CORRENTE CONSOLIDATO" in fondo al file] Il formato storico dei preset era di 33 celle per slot e i preset applicativi salvavano/caricavano soltanto gli slider audio 1–30 (le vecchie celle 31/32 venivano ignorate e azzerate in salvataggio). Dalla Fase A: `preset_size`=32, `num_preset_sliders`=31, e la mappa preset corrente include anche Output L/R (slider36/37) — Engine (slider5) e Link (slider38) restano esclusi.
- Il caricamento di qualunque preset applicativo forza il monitor a `MIX` e ripristina `slider35` (Reduction Softness) al default `50%`.
- Durante CHECK compare un banner testuale globale; Full, Compact e JSFX mantengono un ritorno immediato a MIX.
- La telemetria distingue `PROCESS` da `MONITOR`; durante CHECK i meter finali sono identificati come monitor.
- Dominance Engine v2.5.0 & Redesign GUI Full View:
  - Lo smoothing opera sulla riduzione normalizzata $x \in [0, 1]$ con guadagno logaritmico esatto $10^{x \cdot \text{depth\_db} / 20}$, eliminando lo scatto non lineare in apertura.
  - Asimmetria corretta: la voce attiva (takeover o sovrapposizione) apre con Attack (e lookahead); il rientro alla quiete dopo Hold usa Release (lento, ambiente naturale).
  - Profilo AUTO ritarato: Attack 12 ms / Release 200 ms.
  - Nuovo `slider35: Reduction Softness (%)` (0% HARD a 1 polo $\leftrightarrow$ 100% SMOOTH a 2 poli criticamente smorzati), con normalizzazione a tempo nominale invariante (fattore 0.55 per il 2-pole).
  - Buffer lookahead riallocato a 100.000 campioni per canale (da 10.000 a 210.000, ben sotto i preset a 1010000), supportando nativamente 192 kHz senza alcun clamp artificiale.
  - Redesign Full View:
    - Versione 2.5.0 visualizzata nell'header.
    - Dominance Engine riorganizzata dall'alto al basso: RILEVAMENTO -> STATO MIC L / MIC R (due channel strip affiancate con terminologia `Speech Detect` e `Background`) -> DECISIONE (bipolare L/R con neutral deadband in Delta, testo stabile in Absolute) -> RISPOSTA & TIMING (5 knob: Attack, Release, Hold, Lookahead, Softness 0-100% con lettura `HARD ↔ SMOOTH`).
    - Taratura matematica threshold: `f(x) = (x + 80) / 80` perfettamente coerente tra valore numerico, tacca del knob, detector ring del knob e marker linea sul ladder meter per l'intero range [-80, 0] dB.
    - Meter ladder segmentati per tutti i meter del plugin (Input, Output, Speech Detect, Reduction, Limiter GR).
    - Contrasto tipografico migliorato (`sub_r/g/b = 0.62/0.68/0.76`), stringa AUTO 12/200 ms e tooltip footer dedicati (incluso Softness info 240).
    - Geometria stabile `dom_h = 478 px` con scrolling verticale naturale, senza alterazioni a DSP, slider indices, preset o Monitor.
    - Rifinitura GUI Full View v2.5.0 (layout & compattazione):
      - Risolto overlap in Live State su `PROCESS GATE / Absolute`: righe 0 (`MONITOR STATE`) e 1 (`PROCESS GATE`) a tutta larghezza (332 px), righe 2–5 su 2 colonne (161 px ciascuna) per le 10 celle di telemetria; etichetta a sinistra, valore a destra con guardrail dinamico anti-collisione `max(x + 8 + tw + 6, x + w - vw - 8)`.
      - Separazione verticale Softness: scala `HARD ◄──●──► SMOOTH` con indicatore dinamico di posizione posizionata a `soft_sy + 36`, separata dalla lettura percentuale a `soft_sy + 19..32`.
      - Knob Delta in modalità Absolute disabilitato graficamente tramite `ui_disabled_knob` (knob e lettura attenuati in `0.42, 0.46, 0.52`, click/drag inibiti, tooltip hover attivo) senza salti di layout.
      - Recupero di 86 px di altezza complessiva nelle sezioni inferiori: `input_h` da 322 a 264 px (-58 px), `output_h` da 322 a 264 px (-58 px), `live_h` e `bank_h` uniformati a 216 px (-28 px su riga inferiore); `content_bottom` sceso da 1232 px a 1146 px.
      - Preset Bank ottimizzato: delta `d X.X` allineato a destra, etichetta scena ad alto contrasto (`0.82, 0.86, 0.92`), guida slot nel footer del pannello.
    - Intuitività Dominance Engine:
      - Convenzione coerente segno/direzione Delta documentata: `diff_db = db_l - db_r`. Quando L domina (`diff_db > 0`), il cursore si sposta a sinistra verso "L" (Cyan). Quando R domina (`diff_db < 0`), il cursore si sposta a destra verso "R" (Amber).
      - Testi di stato e formattazione coerenti: `MIC L leads (+X.X dB)` (Cyan), `MIC R leads (+X.X dB)` (Amber, risolto doppio meno `--X.X dB`), `Neutral (L +X.X dB)` / `Neutral (R +X.X dB)` / `Neutral (0.0 dB diff)` al centro (Green).
      - Deadband centrale esplicita con pill protettiva ad alto contrasto: etichetta `NO SWITCH ±X dB` aggiornata dinamicamente con `slider9`.
      - Catena Response esplicitata nell'header: `Speech -> Attack (open) -> Hold (wait) -> Release (to bkg)`. Micro-label funzionali sotto i 5 knob (`OPEN`, `TO BKG`, `WAIT`, `PRE-DET`, `HARD ◄──●──► SMOOTH`).
      - Tooltip footer resi operativi (Hold, Release, Delta, Attack, Lookahead, Background) e chiarito modello mentale nel footer predefinito: `Trim: bilanciamento | Speech Detect: soglie voce | Delta: margine switch | Background: attenuazione`. [STATO STORICO — SUPERATO dalla UI CLEANUP PASS del 2026-09-09: il footer predefinito è stato poi semplificato a "STAGEKEEPER v2.5.0"; questo glossario permanente non è più a schermo].

Verifiche già eseguite:

- Parentesi, graffe, apici e indici bilanciati (0 errori di sintassi).
- Test suite DSP automatizzata (15 scenari su 15 superati):
  1. L solo: OK
  2. R solo: OK
  3. Alternanza L -> R (takeover rapido): OK
  4. Alternanza R -> L (takeover simmetrico): OK
  5. Brevi pause fra parole (tenuta Hold): OK
  6. Sovrapposizione L+R: OK
  7. Rumore sotto soglia: OK
  8. Onset forte dopo silenzio: OK
  9. Consonanti/transienti rapidi: OK
  10. Depth moderato (-12 dB): OK
  11. Depth forte (-40 dB): OK
  12. Depth quasi gate (-80 dB): OK
  13. Lookahead 0 ms: OK
  14. Lookahead 15 ms: OK
  15. Valori estremi timing: OK
- File sincronizzato in `/Users/paolob/Library/Application Support/REAPER/Effects/ZP Suite/ZP Voce/ZP Stagekeeper Dialogue Director.jsfx`.
- Nessun commit e nessun push effettuato.

### Audit Authority / Learn / Metering — 2026-09-08

Vincolo della fase: audit in sola lettura. Non sono state apportate modifiche al plugin durante l'analisi.

Baseline consolidata:

- La baseline da cui proseguire è `ZP Voce/ZP Stagekeeper Dialogue Director.jsfx`, versione 2.5.0.
- SHA-256 osservato: `eb1f02bbb4382e8368285dfde8b0a06e1829810b4bb578d2b9dfe545a6a354b8`.
- La copia installata in `/Users/paolob/Library/Application Support/REAPER/Effects/ZP Suite/ZP Voce/ZP Stagekeeper Dialogue Director.jsfx` era identica byte per byte alla baseline.
- Il file sciolto `/Users/paolob/Library/Application Support/REAPER/Effects/ZP Suite/ZP%20Stagekeeper%20Dialogue%20Director%20v2.5.0%20truth-pass.jsfx` è un prototipo sperimentale successivo (`truth indicators & causal feedback`), non è la baseline e non deve sostituire automaticamente la copia nella cartella ZP Suite.

Conclusioni DSP:

- Il detector corrente usa un RMS esponenziale della potenza con costante nominale di 100 ms, dopo Trim, Phase e Low/High Tilt.
- Absolute confronta indipendentemente RMS L/R con Speech Detect L/R.
- Delta usa essenzialmente `diff_db = db_l - db_r`, insieme ai due Speech Detect come noise floor.
- Non vengono ancora usati correlazione, lag, onset, spettro, rapporto direct/bleed appreso o una authority confidence esplicita.
- Se entrambi i detector sono attivi, entrambi i canali restano aperti; questo non distingue una vera sovrapposizione dal bleed della stessa voce.
- Hold stabilizza lo stato ma non migliora la classificazione della sorgente.
- Softness modifica soltanto la forma temporale del fader (blend 1-pole/2-pole) e deve restare concettualmente separata dal riconoscimento overlap/authority.
- In AUTO i tempi effettivi sono Attack 12 ms e Release 200 ms. Attack governa chiusura, takeover e apertura causata da voce attiva; Release governa il ritorno alla quiete dopo la fine dell'Hold.

Monitor operativo e sicurezza:

- CHECK L/R è realmente post-gate: il canale scelto, dopo `gate_l/gate_r`, viene duplicato sulle due uscite.
- Entrambi gli ingressi continuano a comandare la dominance durante CHECK.
- Gate Off consente il confronto integro; Gate On permette di sentire se e quando il canale controllato viene attenuato mentre l'altro è autorevole.
- Il caricamento di un preset applicativo forza MIX, ma `slider34` è un normale parametro del progetto REAPER: non esistono ancora timeout o ritorno automatico a MIX su trasporto. Una sessione può quindi restare accidentalmente in CHECK.
- Sviluppo successivo: mostrare insieme, in modo inequivocabile, CHECK L/R, Gate On/Off e riduzione corrente; valutare un fail-safe che impedisca di dimenticare il preascolto attivo.

Problemi di telemetria/GUI individuati:

- La GUI legge `det_la_l` e `det_la_r`, ma nel sorgente analizzato il detector assegna `det_la` e `det_ra`: l'accensione istantanea dei ladder può non rappresentare fedelmente il detector.
- Il live ring Delta controlla `delta_mode`, variabile non alimentata nel sorgente analizzato, invece dello stato reale `slider6`/`trigger_delta`.
- I valori numerici Input Pk/RMS sono troppo ravvicinati e possono sovrapporsi.
- Peak e RMS visualizzati usano dinamiche troppo rapide per una lettura numerica affidabile.
- Lo stato GUI `SPEECH ACTIVE` può essere dedotto dal semplice canale aperto (`gate > 0.98`) anche quando nessuno sta parlando.
- La telemetria deve essere corretta senza alterare il comportamento DSP.

Metering futuro:

- Mantenere separati `DETECTOR RMS` e `DISPLAY RMS`.
- Non rallentare l'RMS da 100 ms usato dalla dominance per rendere leggibile la GUI.
- Per la lettura numerica valutare Display RMS 400–700 ms, aggiornamento 4–8 Hz e peak hold di circa 2 secondi seguito da decadimento 10–15 dB/s; possibile reset aggiuntivo su STOP -> PLAY.
- I ring Speech Detect L/R sono matematicamente coerenti con knob e ladder sul dominio -80..0 dB.
- Il ring Delta è concettualmente coerente sul dominio 0..20 dB usando `abs(diff)`, ma è affetto dalla variabile di modalità errata indicata sopra.
- I ring Limiter Threshold e Ceiling richiedono telemetria dedicata e un significato esplicito; il Ceiling -6..0 dB è matematicamente coerente ma poco informativo per segnali normali molto sotto -6 dBFS.

Direzione consigliata per Authority Detector:

- Stati distinti: `IDLE`, `SINGLE L`, `SINGLE R`, `OVERLAP`, `UNCERTAIN`.
- Prima scelta tecnica: combinare margine RMS normalizzato dal Learn, rapporto direct/bleed appreso, correlazione normalizzata a corto lag, onset e stabilità temporale.
- Correlazione alta può indicare la stessa sorgente, ma non determina da sola quale microfono sia autorevole.
- `OVERLAP` e `UNCERTAIN` devono inizialmente avere comportamento fail-safe aperto o con riduzione molto moderata.
- Non partire da FFT/GCC-PHAT finché una correlazione breve e meno costosa non sia stata validata insufficiente su audio reale.

Learn concettuale:

- Preferire un Learn guidato: ambiente, più interventi di A, più interventi di B, cambi di turno e un breve overlap.
- Minimo realistico 15–20 secondi soltanto se gli eventi richiesti sono presenti; durata consigliata 30–60 secondi.
- Stati previsti: `LEARNING`, `INSUFFICIENT DATA`, `UNSTABLE`, `GOOD SEPARATION`, `DIFFICULT ROOM`, `READY`.
- Può applicare con limiti conservativi noise floor/Speech Detect, Delta iniziale, authority margin, Hold e statistiche interne direct/bleed/correlazione.
- Deve soltanto suggerire Depth aggressivo, Attack/Release, Trim, tone, Phase Invert, Dual Mono e limiter.
- Phase Invert non corregge il ritardo e il comb filtering; non applicarlo automaticamente. Al massimo proporre un audition se un miglioramento di coerenza è forte, multibanda e stabile.

Materiale di test:

- Nel repository `zp-suite` non sono stati trovati file audio dual-mic adatti a validare authority, overlap, correlazione o lag.
- Non usare registrazioni generiche dell'archivio come test Stagekeeper senza conferma del routing L/R e del contenuto.

Roadmap approvabile per fasi:

1. Metering e verità GUI, incluso fail-safe CHECK, senza cambiare la dominance.
2. Authority telemetry only, validata su registrazioni dual-mic reali.
3. Learn in modalità advisory.
4. Authority-assisted gating con fallback al detector corrente.
5. Auto setup controllato e reversibile per i soli parametri sicuri.

### Phase B.1 Authority Detector telemetry-only — 2026-09-08

- Implementato in `ZP Voce/ZP Stagekeeper Dialogue Director.jsfx` come ramo parallelo diagnostico; il gate audio e lo Shadow A.6 restano invariati.
- Baseline A.6 verificata prima dell'edit: SHA-256 `e98c6eae21ae9e829eaef68e192eaa948629377491f9538187bf22ecfceafbb4`.
- Sorgente B.1 corrente: SHA-256 `c96a18a3766bde241d09ff1addfb67ca180a81aed02241f6aa671f9c4d419162`.
- Backup pre-change e snapshot finale conservati in `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Stagekeeper/Phase B.1/`; report `ZP Stagekeeper Phase B.1 report 2026-09-08.md`.
- Authority usa `ctrl_in_l/r` post Trim/Phase/Tilt e pre-gate, decimazione nominale 8 kHz, finestra 40 ms, lag ±2 ms, refresh 10 ms e storia 120 ms. Convenzione: lag positivo = R dopo L = L-direct; lag negativo = L dopo R = R-direct.
- Stati diagnostici: `IDLE`, `SINGLE L`, `SINGLE R`, `OVERLAP`, `UNCERTAIN`; confidence L/R/overlap e lag signed/absolute esposti nella sezione GUI scrollabile.
- OVERLAP richiede speech valido su entrambi, livello entro 8 dB e storia bidirezionale del lag; soglia `auth_overlap_conf >= 0.12` sperimentale, da rivalidare su altri setup.
- Validazione offline corpus A.7: 232,566729 s, Shadow 53 flip (2,28/10 s), Authority intera registrazione IDLE 6,61%, SINGLE L 59,00%, SINGLE R 20,01%, OVERLAP 1,10%, UNCERTAIN 13,29%; caso debole 197,25 s: Authority SINGLE R 197,524 s, Shadow R 197,634 s.
- Polarity R invertita: lag/stati/confidence invariati, solo correlazione signed invertita; nessuna Phase automatica.
- Static proof: Authority non assegna `det_la/det_ra/hold_l/hold_r/tgt_l/tgt_r/gate_l/gate_r/spl0/spl1`; il percorso legacy non legge `auth_*`. `speech-engine/` invariato. Nessun commit/push.

### Shadow Detector A.6 e validazione reale A.7 — 2026-09-08 [STATO STORICO — superato da B.3a-LITE, vedi sezione "CURRENT STATE AFTER B.3a-LITE" sotto]

- **Nota 2026-09-08**: al momento di questa fase (A.6/A.7) lo Shadow era esclusivamente diagnostico. Da B.3a-LITE questo non è più vero: Shadow controlla il percorso audio. La riga sotto resta come registrazione storica della fase A.6, non come stato corrente.
- La sorgente Stagekeeper, all'epoca di questa fase (A.6/A.7), includeva il detector Shadow A.6 esclusivamente diagnostico: non controllava il gate. [STATO STORICO — SUPERATO da B.3a-LITE, vedi nota sopra e "STATO CORRENTE CONSOLIDATO" in fondo al file].
- Baseline/snapshot A.6 SHA-256: `e98c6eae21ae9e829eaef68e192eaa948629377491f9538187bf22ecfceafbb4`.
- Snapshot durevole: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Stagekeeper/Phase A.6/ZP Stagekeeper Dialogue Director Phase A.6 e98c6eae.jsfx`.
- Corpus dual-mic reale autorizzato e sincronizzato, 48 kHz float 32 bit, durata 232,567 s:
  - L: `/Volumes/DiscoM28T/AudioSSD/FalcoMultimedia_2026/Tabilia 2026/09_Tabilia_Settembre/09_Tabilia_ENI_Test_TEC_2.4.2_Documento Storyboard su cluster Approccio Responsabile/Tabilia_ENI_Test_TEC_2.4.2_Documento Storyboard su cluster Approccio Responsabile prj/Media/03-L1-260907_1340.wav`;
  - R: `/Volumes/DiscoM28T/AudioSSD/FalcoMultimedia_2026/Tabilia 2026/09_Tabilia_Settembre/09_Tabilia_ENI_Test_TEC_2.4.2_Documento Storyboard su cluster Approccio Responsabile/Tabilia_ENI_Test_TEC_2.4.2_Documento Storyboard su cluster Approccio Responsabile prj/Media/04-TLM103-260907_1340.wav`.
- Con noise floor -40 dBFS e Delta 4 dB, sull'intera registrazione i flip sono scesi da 522 Legacy (22,45/10 s) a 53 Shadow 100 ms (2,28/10 s).
- Release Shadow offline: 70 ms = 59 flip; 100 ms = 53; 140 ms = 45. Tenere 100 ms come candidato corrente: 140 ms riduce i flip ma può rallentare molto gli onset deboli.
- Lo Shadow elimina gran parte del chatter e dei dropout, ma non risolve overlap, bleed quasi paritario o onset con margine insufficiente. Nel caso A->B debole intorno a 197,25 s conferma R dopo circa 380 ms.
- Priming A.6: nessuno stato stale o lato errato su STOP/PLAY, seek e loop; un seek dentro materiale poco discriminante può richiedere 105–263 ms prima della conferma corretta.

### Authority Feature Study B.0 — 2026-09-08

Vincolo della fase: analisi offline in sola lettura. Nessuna modifica a Stagekeeper, Shadow A.6 o `speech-engine/`; nessun collegamento al gate.

Risultati fisici sul corpus reale:

- Il setup è fortemente asimmetrico:
  - SINGLE L: RMS L -26,3 dBFS, RMS R -38,8 dBFS, margine globale +12,4 dB; Delta 40 ms mediano +13,3 dB (IQR +11,7..+14,9).
  - SINGLE R: RMS L -27,4 dBFS, RMS R -23,3 dBFS, margine globale R/L 4,1 dB; Delta 40 ms mediano -4,7 dB (IQR -5,6..-3,6).
  - Overlap/scambio rapido 14,8..17,9 s: Delta globale +1,9 dB; mediana 40 ms +0,4 dB con IQR -1,8..+6,7.
- Convenzione lag: positivo = R arriva dopo L; negativo = L arriva dopo R.
- Cross-correlazione normalizzata, finestra 40 ms e ricerca a lag breve:
  - SINGLE L: correlazione massima mediana 0,720; lag +0,708 ms (~+34 campioni), segno coerente 95,7%, IQR lag +0,625..+0,750 ms.
  - SINGLE R: correlazione massima mediana 0,850; lag -0,521 ms (~-25 campioni), segno coerente 99,3%, IQR lag -0,542..-0,479 ms.
  - Overlap/scambio: correlazione massima mediana 0,720, quindi il coefficiente da solo non separa l'overlap; il lag è instabile, IQR -0,464..+0,583 ms e segno coerente soltanto 66,4%.
- Le finestre 20/40/60 ms danno risultati simili. 40 ms è il miglior punto di partenza: più stabile di 20 ms senza il costo decisionale di 60 ms.
- L'onset direct anticipa spesso il bleed di 1–22 ms e in alcuni casi di più, ma non è universale. Pendenza e onset lead non sono affidabili come prova autonoma; usarli soltanto come acceleratore a peso ridotto.
- I rapporti spettrali presence/low-mid e high/presence non separano stabilmente direct e bleed e sono confusi dalle differenze L1/TLM103. Non introdurre FFT o GCC-PHAT in B.1.
- Caso A->B debole ~197,25 s:
  - onset forte rilevabile intorno a 197,409 s, senza anticipo R misurabile e con margine iniziale di circa 3,3 dB;
  - tra 197,30 e 197,34 s il Delta è ancora circa -2,7/-3,4 dB, ma correlazione 0,67..0,76 e lag stabile -0,458 ms mostrano già la firma R;
  - Shadow passa L->NEUTRAL intorno a 197,337 s e conferma R intorno a 197,630 s;
  - una Authority basata sul lag può plausibilmente anticipare la conferma di circa 150–250 ms, ma non può decidere prima che esista evidenza fisica.

Ranking consolidato delle feature:

1. Molto utile: Delta/RMS validato dal noise floor.
2. Molto utile: segno e stabilità temporale del lag.
3. Utile come supporto: correlazione massima combinata con il lag.
4. Utile come supporto: onset a peso ridotto.
5. Debole: peak iniziale e correlazione a lag zero.
6. Non utile per la prima Authority: rapporti spettrali, FFT e GCC-PHAT.

Direzione minima per Phase B.1 telemetry-only:

- Stati diagnostici: `IDLE`, `SINGLE L`, `SINGLE R`, `OVERLAP`, `UNCERTAIN`; non forzare sempre L o R.
- Evidenza minima: level Shadow + correlazione normalizzata a lag breve + segno/stabilità del lag + onset secondario.
- Confidence continue separate: `L authority`, `R authority`, `same-source probability`, `overlap probability`.
- Invalidare la decisione sotto noise floor e usare `UNCERTAIN` quando level e lag si contraddicono.
- Implementazione iniziale consigliata: analisi decimata 6–8 kHz, ricerca circa +/-1,5..2 ms, 19–33 lag candidati, finestra 40 ms, refresh 5–10 ms, stabilità 80–150 ms.
- Costo atteso JSFX basso-moderato, senza latenza audio perché telemetry-only; confidence iniziale 20–40 ms, overlap stabile 80–150 ms.
- B.1 deve esporre almeno: `auth_corr_max`, `auth_lag_samples/ms`, `auth_lag_sign_stability`, `auth_same_source_conf`, `auth_l_conf`, `auth_r_conf`, `auth_overlap_conf`, stato e motivo della decisione.
- Benchmark obbligatorio a 44,1/48/96/192 kHz e regressione obbligatoria sul caso 197,25 s. Nessun controllo del gate in B.1.

============================================================
ZP STAGEKEEPER — CURRENT STATE AFTER B.3a-LITE
2026-09-08
============================================================

[Nota: questa sezione descrive il comportamento Shadow/Authority stabilito con B.3a-LITE ed è tuttora valido — non è contraddetta da nulla di successivo. Il titolo "CURRENT STATE" è però storico: la baseline SHA corrente e i controlli aggiunti dopo (Background curve, Output L/R+Link, Engine ON/OFF, preset estesi, UI Cleanup) sono nelle sezioni successive e riassunti in "STATO CORRENTE CONSOLIDATO" in fondo al file.]

Sorgente canonica:
ZP Voce/ZP Stagekeeper Dialogue Director.jsfx

Stato corrente:

- Shadow A.6 NON è più telemetry-only.
- Da B.3a-LITE `nd_delta_state` controlla il percorso audio
  attraverso `tgt_l/tgt_r`.
- L_DOM → L open / R Background
- R_DOM → R open / L Background
- NEUTRAL → OPEN BOTH
- takeover opposto Shadow non viene bloccato dal vecchio Hold.
- resta una sola macchina gain/smoothing.

Authority B.1:

- resta TELEMETRY ONLY;
- non scrive tgt_l/tgt_r;
- non controlla gate_l/gate_r;
- non controlla spl0/spl1;
- non può fare veto sullo Shadow;
- possibile futuro uso solo come assistenza conservativa
  nei takeover deboli, se l'ascolto lo giustifica.

Cross Analysis:

- mapping .RPP verificato:
  POSITION 278.946310
  SOFFS 19.942056
  PLAYRATE 1

- "libellula" ≈ 28.275s:
  Legacy perde R;
  Shadow mantiene R ~270ms più a lungo e copre il marker.

- "grazie" ≈ 29.806s:
  vero takeover R→L;
  Shadow acquisisce L ~29.904s;
  Authority resta temporaneamente stale su R;
  OPEN BOTH durante incertezza è comportamento corretto.

- weak takeover ~197.25s:
  Authority R ~197.524s;
  Shadow R ~197.634s;
  vantaggio Authority ~110ms,
  non ancora dimostrato percettivamente necessario.

Decisione corrente:
SHADOW FIRST è stata implementata.
Non implementare Authority full-control.
Non allungare globalmente Hold.
Non usare auth_state come veto.

Stato percettivo preliminare:
Paolo riferisce che il DSP Shadow Control gli piace molto,
anche con configurazione volutamente stressata.

Catena SHA:

B.1:
c96a18a3766bde241d09ff1addfb67ca180a81aed02241f6aa671f9c4d419162

B.3a-LITE:
6847f8e5228ce5f11665d26b3d0a089733efbe86f7efb15bc9a6b92f0a48d81b

UI PASS 1:
a17a605d9367672f6d724fbdde437c0053137e3a52be23f47911aeef14730f99

UI PASS 2A:
78828e7ecf2ba6b3275b70d1546d1ad8b3e221ef255e3e04823f5179ad838cf5

UI PASS 2B [STATO STORICO — SUPERATO, non più la baseline corrente]:
d5cac8e84313cfc2187dbd3ce7e953e703a670374e35d00b1fd6e3f85fc2e925

Allineamento verificato 2026-09-09:

- Sorgente canonica, copia runtime REAPER e snapshot storico UI PASS 2B sono identici.
- SHA-256 comune: `d5cac8e84313cfc2187dbd3ce7e953e703a670374e35d00b1fd6e3f85fc2e925`.
- Runtime: `/Users/paolob/Library/Application Support/REAPER/Effects/ZP Suite/ZP Voce/ZP Stagekeeper Dialogue Director.jsfx`.
- Snapshot immutabile: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Stagekeeper/UI PASS 2B/final/ZP Stagekeeper UI PASS 2B d5cac8e8.jsfx`.
- Rapporto: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Stagekeeper/UI PASS 2B/ZP Stagekeeper UI PASS 2B alignment report 2026-09-09.md`.
- La sincronizzazione non ha modificato la sorgente canonica né `speech-engine/`; nessun commit o push.

Per dettagli, marker e storia completa fare riferimento a:

/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/ZP_STAGEKEEPER_WORKLOG.md

============================================================
ZP STAGEKEEPER — CONTROLS / DSP PASS, FASE A (mechanical)
2026-09-09
============================================================

Sorgente canonica:
ZP Voce/ZP Stagekeeper Dialogue Director.jsfx

Baseline verificata prima della Fase A:
d5cac8e84313cfc2187dbd3ce7e953e703a670374e35d00b1fd6e3f85fc2e925

Ambito Fase A (SOLO controlli meccanici, NESSUNA Authority Assist):

- Background (slider15/16): reintrodotta SOLO la curva di interazione della manopola
  (funzioni `bg_db_to_t`/`bg_t_to_db`, `bg_t_split=0.25`, `bg_db_split=-24`):
  ~75% della corsa copre 0..-24dB (zona musicale), il restante ~25% copre -24..-80dB
  (plunge verso il gate). Il significato DSP del valore memorizzato (dB di attenuazione
  del mic non dominante, usato invariato nella formula `gate_l = exp(x_l*depth_l_coeff)`)
  NON è cambiato: cambia solo il mapping mouse→valore e la lettura a schermo (dB + %).
  Disegnata come funzione dedicata `ui_knob_bg` (non tocca `ui_knob` condivisa da ~20
  altre manopole).
- Output L/R (nuovi slider36/slider37, ±12dB, gain lineare `2^(dB/6)` come Master):
  inseriti in `@sample` subito DOPO la moltiplicazione per `master_cur` e PRIMA del
  downmix Dual Mono e del Limiter. Stessa macchina di smoothing one-pole di Master
  (`ctrl_smooth`), nessuna seconda macchina di gain. Non toccano detector, Speech
  Detect, Delta, Shadow o Authority.
- LINK (nuovo slider38, toggle): a delta costante, non a valore identico. Implementato
  in `ui_knob_linked`: ad ogni variazione (drag, doppio click, tasto destro) calcola
  `delta = new_val - old_val` e, solo se LINK è attivo, applica lo stesso delta
  all'altro canale (clampato al range). Esempio verificato: L+1.5/R-0.5 con LINK
  attivato e poi abbassati di 2dB → L-0.5/R-2.5 (offset preservato, non snap).
- Engine ON/OFF (slider5): default cambiato a 1 (ON) come da richiesta Factory.
  Il comportamento "Engine Off = zero attenuazione del Dialogue Engine, resto della
  catena (Trim, tono, Phase, Monitor, Output L/R, Output Mode, Limiter) invariato,
  telemetria Shadow/Authority sempre calcolata" era GIÀ il comportamento esistente
  del blocco gate/dominanza in `@sample` (verificato leggendo il codice: il ramo
  else di `slider5 ?(...)` già poneva `gate_l=gate_r=1` senza toccare s0/s1, e il
  calcolo di `nd_delta_state`/`auth_state` avviene prima ed è incondizionato).
  Cambiati solo: valore di default, disegno del pulsante (icona power a primitive
  via `gfx_arc`+`gfx_line`, funzione dedicata `ui_engine_button`, niente glifi font),
  ed esclusione dai preset (vedi sotto).
- Master: MANTENUTO per questa fase, non rimosso, per esplicita decisione di Paolo.
  Motivazione DSP: Output L/R bilanciano i due interlocutori tra loro; Master sposta
  l'intero mix risultante rispetto al Limiter; non sono ridondanti nella catena
  attuale. Valutare l'eventuale rimozione solo dopo uso reale.

Preset P1-P9 (formato esteso, non retrocompatibile per scelta esplicita — nessun
preset legacy da proteggere):

- `num_preset_sliders` 30→31, `preset_size` 33→32, `preset_used_offset` 32→31.
- Salvati nei preset: Output L (slider36), Output R (slider37) — modificano il
  suono e devono essere richiamabili.
- ESCLUSI dai preset: Engine (slider5) e LINK (slider38) — un richiamo preset non
  deve accendere/spegnere l'Engine né alterare lo stato LINK.
- LINK è persistente a livello di progetto/sessione REAPER (stato JSFX normale),
  non a livello di preset P1-P9.
- `preset_slider_map` ricostruita esplicitamente (31 voci): rimuovere slider5 dal
  mezzo del vecchio range 1-30 sposta la posizione di storage di tutti gli slider
  successivi; `set_factory_preset` e le 3 chiamate P1/P2/P3 sono state riderivate
  per intero (non semplice append). Corretti anche due offset hardcoded nella UI
  del banco preset (`preset_mem[p_base+8]`→`+7` per il readout Delta Threshold;
  `+4` non è più "Gate on/off" ma "Delta mode"/"Absolute mode", perché quello slot
  ora corrisponde a Trigger Mode/slider6). P3 rinominato "Stereo (gate manuale)":
  non forza più Engine OFF al richiamo, va impostato manualmente.

SHA dopo Fase A:
be3cb80af3884c775760d3ec655ce333fc0b869547864ddf0d115d94597d8a87

Snapshot:
- pre-change: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Stagekeeper/Fase A/pre-change/ZP Stagekeeper pre-Fase-A d5cac8e8.jsfx`
- final: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Stagekeeper/Fase A/final/ZP Stagekeeper Fase A be3cb80a.jsfx`
- report: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Stagekeeper/Fase A/ZP Stagekeeper Fase A report 2026-09-09.md`

Verifiche statiche eseguite (non sostituiscono l'ascolto REAPER):
- diff riga per riga contro il backup pre-Fase-A: 21 hunk, tutti fuori dai blocchi
  di calcolo Shadow (`nd_delta_state`) e Authority (`auth_state`).
- una sola macchina di gain/smoothing, nessun doppio gain.
- ordine DSP confermato: Master → Output Trim L/R → Output Mode (Dual Mono) → Limiter.
- `git diff --check` pulito, `git status --short` mostra solo il file del plugin
  modificato (più `AGENTS.md` non tracciato). Nessun commit, nessun push.

Non ancora fatto al momento della Fase A (2026-09-09) — [STATO STORICO, vedi
aggiornamenti successivi]:
- Fase B (Authority Assist): NON iniziata all'epoca. **Resta vero oggi**:
  Authority Assist non è ancora implementata (fase separata, da avviare solo
  dopo esplicita richiesta).
- Ascolto REAPER della Fase A: [STATO STORICO — SUPERATO] al momento della
  Fase A non era ancora stato fatto; Paolo lo ha poi eseguito e approvato
  (vedi "STATO CORRENTE CONSOLIDATO" in fondo al file).
- Help overlay: [STATO STORICO — SUPERATO] al momento della Fase A non era
  stato riscritto; è stato poi aggiornato nella UI CLEANUP PASS (Engine,
  Background, Output L/R/Link/Master in pagina OUTPUT) e non è più pending.

Per dettagli, marker e storia completa fare riferimento a:

/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/ZP_STAGEKEEPER_WORKLOG.md

============================================================

============================================================
ZP STAGEKEEPER — UI CLEANUP PASS (less text / more instrument)
2026-09-09
============================================================

Sorgente canonica:
ZP Voce/ZP Stagekeeper Dialogue Director.jsfx

Baseline verificata prima di questo pass:
be3cb80af3884c775760d3ec655ce333fc0b869547864ddf0d115d94597d8a87 (= Fase A corrente)

Ambito: SOLO @gfx (grafica, layout, testo, mouseover, Help). Nessun nuovo slider,
nessuna modifica a preset/Shadow/Authority/DSP. Tutte le 16 modifiche di questo
pass ricadono nell'area @init (funzioni di disegno, non calcolo) o in @gfx —
confermato per diff riga per riga contro il backup pre-pass: nessuna riga tocca
@slider/@block/@sample/@serialize.

Modifiche principali:

- Engine: da rettangolo con testo ENGINE ON/OFF a solo simbolo power (icona a
  primitive invariata, `ui_engine_button` ora a firma centro+raggio come
  `ui_phase_dot`), stessi slider5/hitbox comoda (+6px di margine), nessuna
  modifica alla semantica gia' approvata in Fase A.
- Background: knob NON toccato (curva, `bg_db_to_t`/`bg_t_to_db`, percentuale
  invariati per esplicita richiesta di Paolo — la semantica 100%=0dB/0%=-80dB
  era gia' corretta). Corretto invece il meter SCENE/BACKGROUND
  (`draw_channel_reduction_bar`): prima si normalizzava rispetto alla propria
  profondita' configurata (sempre ~100% a regime, qualunque fosse il valore di
  Background), ora usa la stessa `bg_db_to_t()` del knob — OPEN=100%, Background
  stabile=stessa percentuale del knob, in transizione segue live il gain reale
  sulla stessa curva. Per questo `bg_db_to_t`/`bg_t_to_db` sono state spostate
  (corpo invariato) prima di `draw_channel_reduction_bar`, che le richiama.
- Output panel: rimossi header/divider "OUTPUT TRIM (post engine, pre
  limiter)" e il grande pulsante LINKED/UNLINKED; Output L/R spostati subito a
  sinistra del Master (stessa riga, knob piccoli, anello blu/cyan — colore
  `grp_in_r/g/b` gia' usato per Trim/Hi, riutilizzato per coerenza visiva),
  con solo le lettere "L"/"R" come etichetta. Link ora e' un piccolo simbolo a
  catena (`ui_link_button`, due anelli a primitive) centrato sotto L/R.
  `output_h` tornato a 264 (era cresciuto a 350 in Fase A). Slider/logica
  invariati (36/37/38), solo riposizionamento grafico.
- Text cleanup: rimossa la narrativa MANUAL/AUTO ridondante sotto RESPONSE
  (tenuto solo il valore utile "AUTO: 12 / 200 ms", altrimenti invisibile);
  semplificato il testo di default del footer a "STAGEKEEPER v2.5.0" (era un
  glossario permanente Trim/Speech Detect/Delta/Background); rimosso l'hint
  "Left-click to recall * Right-click to save/clear" nel banco preset, gia'
  duplicato dal mouseover esistente (info 222).
- Help overlay: aggiornato senza riscrittura completa. ENGINE ora spiega ON/OFF
  e cosa resta attivo con Engine Off; BACKGROUND ora esplicita 100%/0%/dB;
  OUTPUT (pagina 2) ora include Output L/R, Link e Master (prima non li
  menzionava affatto).
- Mouseover: riformulato 205 (Engine) per allinearsi alla nuova semantica
  richiesta mantenendo i dettagli tecnici (telemetria, esclusione preset);
  aggiunta la clausola "Non influenza il detector" a 251/252 (Output L/R).

SHA dopo questo pass:
68b8185491198ca450316002519dbbfff9281869500b371b46c60c4bb6124d8a

Hotfix sintassi REAPER 2026-09-09:

- REAPER segnalava `@gfx:3038: syntax error: '<!> : ('` perché il cleanup aveva lasciato vuoto il ramo MANUAL del ternario che mostra `AUTO: 12 / 200 ms`.
- Correzione minima: il ternario vuoto è stato sostituito da `!reaction_manual ? gfx_drawstr("AUTO: 12 / 200 ms");`.
- Nessun cambiamento a DSP, slider, preset, Shadow o Authority.
- SHA corrente dopo hotfix: `210b85433d858c55dcc18ace1f733ddc8829f25614225d70751ccc871c93833e`.
- Snapshot e report: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Stagekeeper/UI Cleanup Pass Syntax Fix/`.

Stato consolidato e approvato 2026-09-09:

- Dopo il syntax fix è stato applicato un ultimo aggiustamento esclusivamente grafico: Output L/R e Link riequilibrati fra meter GR e Master; Master ingrandito da raggio 15 a 17,25.
- Paolo ha confermato positivamente sia la resa grafica sia il comportamento DSP in REAPER.
- Nuova baseline corrente: SHA-256 `48507bacb255be73101e386bb9d6703513295cb8f467a50d7c7dcfe35a907c7e`.
- Sorgente canonica, copia runtime REAPER e snapshot storico sono identici.
- Snapshot: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Stagekeeper/UI Cleanup Geometry Adjustment/final/ZP Stagekeeper UI Cleanup Geometry 48507bac.jsfx`.
- Rapporto: `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Stagekeeper/UI Cleanup Geometry Adjustment/ZP Stagekeeper UI Cleanup Geometry approval 2026-09-09.md`.
- Posizione DSP confermata dei trim Output L/R: dopo Master, prima di Stereo/Dual Mono e prima del Limiter. La collocazione grafica a sinistra del Master non rappresenta l'ordine DSP.
- Authority Assist resta fuori scope e non è stata iniziata. Nessun commit o push.

Snapshot:
- pre-change: `Archivio_Storico_ZP/ZP Suite/Stagekeeper/UI Cleanup Pass/pre-change/ZP Stagekeeper pre-UI-Cleanup be3cb80a.jsfx`
- final: `Archivio_Storico_ZP/ZP Suite/Stagekeeper/UI Cleanup Pass/final/ZP Stagekeeper UI Cleanup Pass 68b81854.jsfx`
- report: `Archivio_Storico_ZP/ZP Suite/Stagekeeper/UI Cleanup Pass/ZP Stagekeeper UI Cleanup Pass report 2026-09-09.md`

Verifiche statiche eseguite:
- diff contro il backup pre-pass: 16 hunk, tutti fuori da @slider/@block/@sample/@serialize.
- slider invariati (ancora 1-38, nessuno aggiunto/rimosso); preset layout
  invariato (31 slider gestiti / 32 celle); Engine/Link ancora esclusi dai
  preset P1-P9 come da Fase A.
- Shadow/Authority non toccati (nessuna riga nel loro range).
- `git diff --check` pulito, `git status --short` mostra solo il plugin
  modificato. Nessun commit, nessun push, `speech-engine/` non toccato.

[STATO STORICO — SUPERATO] Al momento di questo report la verifica visiva in
REAPER e l'ascolto erano ancora da fare; Paolo li ha poi eseguiti ed
approvati entrambi (vedi "Stato consolidato e approvato 2026-09-09" sopra e
"STATO CORRENTE CONSOLIDATO" in fondo al file) — non serve rifarli salvo
regressione dimostrata.

Per dettagli, marker e storia completa fare riferimento a:

/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/ZP_STAGEKEEPER_WORKLOG.md

============================================================

============================================================
ZP STAGEKEEPER — STATO CORRENTE CONSOLIDATO (BASELINE APPROVATA)
2026-09-09
============================================================

Questa sezione è il riferimento UNICO per lo stato corrente. Qualunque altra
sezione più sopra in questo file che sembri in contraddizione con quanto
segue va letta come [STATO STORICO — SUPERATO] rispetto a questa.

Sorgente canonica:
ZP Voce/ZP Stagekeeper Dialogue Director.jsfx (versione sorgente 2.5.0)

Runtime REAPER:
/Users/paolob/Library/Application Support/REAPER/Effects/ZP Suite/ZP Voce/ZP Stagekeeper Dialogue Director.jsfx

Snapshot storico:
/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Stagekeeper/UI Cleanup Geometry Adjustment/final/ZP Stagekeeper UI Cleanup Geometry 48507bac.jsfx

Baseline approvata (sorgente, runtime e snapshot identici byte per byte):
SHA-256 48507bacb255be73101e386bb9d6703513295cb8f467a50d7c7dcfe35a907c7e

Comportamento Shadow/Authority:
- Shadow A.6 controlla realmente l'audio dalla fase B.3a-LITE (non più telemetry-only).
- `nd_delta_state` pilota `tgt_l`/`tgt_r`.
- L_DOM -> L open / R Background.
- R_DOM -> R open / L Background.
- NEUTRAL -> OPEN BOTH.
- Authority B.1 resta TELEMETRY ONLY: non scrive tgt_l/tgt_r, non controlla
  gate_l/gate_r/spl0/spl1, non può fare veto sullo Shadow.
- Authority Assist NON è ancora implementata (fase separata, non iniziata).

Catena DSP corrente:
Engine/Gate -> CHECK -> Master -> Output L/R -> Stereo/Dual Mono -> Limiter -> Output

Output L/R:
- slider36 / slider37, ±12 dB.
- post Master, pre Stereo/Dual Mono, pre Limiter.

LINK:
- slider38.
- mantiene l'offset L/R: applica lo stesso delta dalla GUI ad ogni variazione.
- persistente nel progetto/sessione REAPER, escluso dai preset P1-P9.

Engine:
- slider5, default ON, escluso da P1-P9.
- OFF = OPEN BOTH (non è un bypass totale del plugin: Input, Output, Monitor
  e Limiter restano attivi).

Preset — stato CORRENTE (sostituisce qualunque numero riportato più sopra):
- num_preset_sliders = 31
- preset_size = 32
- preset_used_offset = 31
- Mappa preset corrente: 1,2,3,4, 6,7,8,9,10,11,12,13,14,15,16,17,18,
  19,20,21,22,23,24,25,26,27,28,29,30, 36,37.
- Engine (slider5) ESCLUSO; Output L/R (slider36/37) INCLUSI; Link (slider38) ESCLUSO.
- Le vecchie frasi "33 celle per slot" e "salva slider audio 1-30" (sezione
  "ZP Stagekeeper Dialogue Director" più sopra) sono [STATO STORICO —
  SUPERATO dalla Fase A del 2026-09-09].

UI corrente (consolidato):
- Engine rappresentato da sola icona power.
- Phase L/R rappresentata da simboli Ø.
- Dominance Decision ripulita dai mini-meter ridondanti; fascia evidenziata.
- Output L/R compatti accanto al Master, riequilibrati fra meter GR e Master;
  Master ingrandito (raggio 15 -> 17.25).
- Link rappresentato da piccola icona a catena.
- Background: 100% = 0 dB / nessuna attenuazione, 0% = -80 dB / gate profondo;
  il meter SCENE/BACKGROUND usa la stessa scala del knob.
- Help overlay interno aggiornato (Engine, Background, Output L/R/Link/Master).
- Mouseover/footer verificati; narrativa inline ridondante rimossa (footer
  glossario permanente, narrativa Response MANUAL/AUTO, hint preset duplicato).
- [STATO STORICO — SUPERATO] Le vecchie descrizioni di Engine come rettangolo
  ENGINE ON/OFF, Output Trim come pannello separato, Help incompleto, footer
  glossario permanente e "verifica UI ancora da fare" (sezioni FASE A/UI
  CLEANUP PASS più sopra) non sono più lo stato corrente.

Approvazione umana:
2026-09-09: Paolo ha approvato in REAPER sia il comportamento DSP sia la
geometria/UI finale. Sorgente canonica, runtime REAPER e snapshot storico
sono identici. Questa è la baseline da cui deve partire qualunque fase futura.

Storia SHA (dalla più vecchia alla più recente; SOLO l'ultima è la baseline
corrente, nessun'altra va più chiamata "corrente"):
- B.1: c96a18a3766bde241d09ff1addfb67ca180a81aed02241f6aa671f9c4d419162
- B.3a-LITE: 6847f8e5228ce5f11665d26b3d0a089733efbe86f7efb15bc9a6b92f0a48d81b
- UI PASS 1: a17a605d9367672f6d724fbdde437c0053137e3a52be23f47911aeef14730f99
- UI PASS 2A: 78828e7ecf2ba6b3275b70d1546d1ad8b3e221ef255e3e04823f5179ad838cf5
- UI PASS 2B: d5cac8e84313cfc2187dbd3ce7e953e703a670374e35d00b1fd6e3f85fc2e925
- Fase A (mechanical): be3cb80af3884c775760d3ec655ce333fc0b869547864ddf0d115d94597d8a87
- UI Cleanup: 68b8185491198ca450316002519dbbfff9281869500b371b46c60c4bb6124d8a
- Syntax Fix: 210b85433d858c55dcc18ace1f733ddc8829f25614225d70751ccc871c93833e
- UI Cleanup Geometry APPROVATA (BASELINE CORRENTE): 48507bacb255be73101e386bb9d6703513295cb8f467a50d7c7dcfe35a907c7e

Pending — stato reale:
1. Authority Assist: fase separata, non iniziata. Shadow First resta principio
   fondamentale; Authority può solo eventualmente anticipare un takeover
   opposto robusto — mai veto, mai ritardo, mai full control.
2. Factory / Stress profiles: progettati ma non implementati.
3. Quick Scenes: idea futura, non implementata.
4. Help HTML esterno: da aggiornare alla fine, quando il comportamento
   definitivo del plugin sarà congelato.

Help overlay interno e mouseover sono GIÀ aggiornati: non sono pending.

Nessuna necessità di riaprire B.2/B.3a/UI Cleanup salvo regressione dimostrata.

============================================================

## ZP Speech Engine

Directory principale:

`speech-engine/`

Stato consolidato:

- Fase 0, contratto provider-neutral ZP Speech API/Schema v1: commit `efd8908` sul branch `codex/zp-speech-phase-0`.
- Fase 1, MacWhisper Provider Adapter: commit `39a5fca` sul branch `codex/zp-speech-phase-1-macwhisper`.
- La Fase 1 usa esclusivamente la CLI pubblica MacWhisper `/Applications/MacWhisper.app/Contents/MacOS/mw` oppure `mw` risolto dal `PATH`.
- Non leggere o modificare il database SQLite privato di MacWhisper e non usare `--persist`.
- Il raw output del provider deve sempre essere adattato al contratto ZP; non modificare il contratto pubblico per rispecchiare dettagli specifici di MacWhisper.
- Identità sorgente v1: `sha256:<digest>` calcolato sui byte esatti del file sorgente.
- Tutti i timestamp pubblici sono millisecondi interi e intervalli half-open `[start_ms, end_ms)`.
- Invariante: `word_timestamps=true` implica sempre `segment_timestamps=true`.
- L'SRT canonico viene generato dal transcript ZP normalizzato; l'SRT grezzo MacWhisper è soltanto una fixture di confronto.

Capability MacWhisper verificate realmente con la versione 14.8.1:

- segment timestamp e word timestamp disponibili;
- selezione automatica lingua e streaming osservati;
- input verificato conservativamente: WAV;
- output verificati: JSON, SRT e TXT;
- diarizzazione non dichiarata: `--speakers` non ha prodotto etichette neppure con un campione sintetico a due voci;
- il JSON raw contiene `segments` e `text`, ma non espone versione provider, modello o lingua automaticamente rilevata.

Componenti della Fase 1:

- `speech-engine/src/zp_speech/providers/macwhisper.py`: detection, capability probe, processo CLI, normalizzazione ed error mapping.
- `speech-engine/src/zp_speech/exporters/srt.py`: esportazione SRT dal transcript normalizzato.
- `speech-engine/src/zp_speech/cli.py`: comandi minimi `doctor` e `transcribe`.
- `speech-engine/tests/fixtures/macwhisper/14.8.1/`: output reali JSON/SRT, sintetici e privi di percorsi personali.

Comandi di verifica dalla directory `speech-engine/`:

```bash
.venv/bin/pytest --cov=zp_speech --cov-branch --cov-report=term-missing --cov-fail-under=100
.venv/bin/ruff check src tests
.venv/bin/ruff format --check src tests
.venv/bin/basedpyright
.venv/bin/ty check
.venv/bin/python -m build --wheel
```

Ultimo risultato verificato: 95 test passati, line coverage 100%, branch coverage 100%, Ruff/format OK, basedpyright strict OK, ty OK, wheel build OK; schema ed entry point inclusi nella wheel.

Fuori ambito finché non viene aperta una fase dedicata:

- server HTTP e API browser;
- client o integrazione REAPER e modifiche a `26_SRT_Tools.lua`;
- whisper.cpp, fallback provider e download/gestione generale dei modelli;
- resolver source-to-project timeline, Gobbo, Solo Recorder, ricerca FTS/fuzzy/semantica e provider cloud.

## Stato del worktree osservato

- Branch corrente: `codex/zp-speech-phase-1-macwhisper`.
- Il commit Speech `39a5fca` contiene esclusivamente modifiche sotto `speech-engine/`.
- `ZP Voce/ZP Stagekeeper Dialogue Director.jsfx` presenta modifiche non committate e indipendenti: non ripristinarle, sovrascriverle o includerle in commit Speech.
- `AGENTS.md` è memoria locale di progetto; aggiornarlo quando cambiano decisioni consolidate, percorsi, branch o gate.

## Private Regions — implementazione iniziale 2026-09-09

- Protocollo comune: `ZP Studio Suite/ZP_Private_Regions.lua`; specifica e stato
  verifiche in `ZP Studio Suite/PRIVATE_REGIONS.md`.
- Ownership da GUID Ruler Lane registrato in Project ExtState
  `ZP_PRIVATE_REGIONS_V1`, chiave `lane:{GUID}` -> owner. Mai da posizione/colore.
- Primo owner STAGEKEEPER, azioni 28 SPACE e 29 IGNORE; annotazioni soltanto,
  Authority Assist ancora non implementata. DSP Stagekeeper non modificato.
- Project Viewer e consumatori editoriali filtrano tutte le lane registrate,
  inclusi owner futuri. Render Suite con Private Regions usa selezione nativa
  esplicita; la coda non cancella/ricrea le regioni private.
- 13 test Lua con API simulate e sintassi di 32 script verificati. Validazione
  reale REAPER ancora da fare; nessuna installazione, commit o pubblicazione.
- Archivio pre-change/final con SHA-256 sotto
  `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Private Regions/2026-09-09_181607`.


## Private Regions — due lane Stagekeeper persistenti, 2026-09-09

- Stato corrente: 28 crea/riusa solo SPACE; 29 crea/riusa solo IGNORE.
- Registro progetto `ZP_PRIVATE_REGIONS_V1`: `lane:{GUID}` -> owner invariato;
  `role:{GUID}` -> ruolo immutabile. Risoluzione per coppia owner/ruolo e GUID,
  mai per posizione, nome o colore. Le lane vengono create su richiesta una volta.
- Lane registrata mancante: errore esplicito con indicazione Undo, nessuna
  ricreazione/appropriazione né modifica del registro. Ripristinare il GUID originale.
- Registrazioni legacy senza ruolo o duplicati ambigui: creazione bloccata;
  nessuna migrazione automatica basata sul nome. Restano escluse dai flussi editoriali.
- Per lane con ruolo, `read.type` deriva dal ruolo; `update` rifiuta cambi di tipo.
- 22 test Lua superati, comprese le azioni 28/29 eseguite con API simulate.
  Undo/Redo e salvataggio/riapertura reali REAPER restano da validare.
- DSP Stagekeeper 2.5.0 invariato byte per byte rispetto all'inizio della fase:
  SHA-256 `48507bacb255be73101e386bb9d6703513295cb8f467a50d7c7dcfe35a907c7e`.
- Archivio pre/final e manifest SHA-256:
  `/Volumes/DISCO LACIE/Archivio_Storico_ZP/ZP Suite/Private Regions/2026-09-09_persistent_roles`.
- Nessuna installazione REAPER, commit, push o modifica dell'indice ReaPack.
