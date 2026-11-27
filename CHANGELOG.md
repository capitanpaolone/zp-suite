# Changelog — ZP Suite

## ZP Studio Suite 2.6.9 — 2026-11-27

- **Identità grafica di prodotto unificata (`latocardioide.it · dubbertools.com`) e restyling hardware `ZP Reference Tone Mirror EQ Pro 1.0.0`**: tutte le finestre Lua della Suite (`ZP_UI.lua` e interfacce standalone), tutti i 17 JSFX (`desc:` e `@gfx`, inclusi `ZP Subliminal Presence Layer White 3.2.4` e `ZP Oscilloscope 16ch 12.3`) e tutte le 16 pagine guida IT/EN adottano l'intestazione/footer di prodotto `ZP <nome> · latocardioide.it · dubbertools.com` (nome autore nei soli metadati). **`ZP Reference Tone Mirror EQ Pro 1.0.0`** riceve la nuova interfaccia hardware ZP Suite completa (vista `FULL` pulita senza slider nativi sovrapposti + vista `JSFX` per OSARA, grafico live della curva EQ a 31 bande `20 Hz – 20 kHz`, 3 pannelli con pomelli rotativi e `Debug Overlay` spento di default; DSP e slider `1..109` invariati).
- **Unified product branding (`latocardioide.it · dubbertools.com`) & `ZP Reference Tone Mirror EQ Pro 1.0.0` hardware UI**: all Lua Suite windows (`ZP_UI.lua` and standalone UIs), all 17 JSFX plugins (`desc:` and `@gfx`, including `ZP Subliminal Presence Layer White 3.2.4` and `ZP Oscilloscope 16ch 12.3`), and all 16 IT/EN help pages display consistent `ZP <name> · latocardioide.it · dubbertools.com` product branding (author attribution kept strictly in metadata). **`ZP Reference Tone Mirror EQ Pro 1.0.0`** upgrades to a full ZP Suite hardware UI (clean `FULL` view hiding raw sliders + `JSFX` view for OSARA, live 31-band `20 Hz – 20 kHz` EQ curve plot, 3 rotary-knob panels, and `Debug Overlay` off by default; DSP and sliders `1..109` unchanged).

- **Fine della beta (decisione di Paolo, 2026-11-26)**: ZP Clean & Paint, ZP Montaggio Parlato, ZP BrownSlope Dynamic Guard, ZP Click & Attack Softener e ZP Speech Engine escono dalla maturazione: via l'etichetta BETA da titoli, finestre, guide e README. Requisiti e limiti (motore esterno di Clean & Paint, runtime ZP Speech, Poppler/SWS) restano documentati. ZP Magic Voice LAB mantiene il nome LAB per scelta. Gain Match si sospende mentre un LEGA OUTPUT è attivo.
- **End of beta (Paolo's decision, 2026-11-26)**: ZP Clean & Paint, ZP Montaggio Parlato, ZP BrownSlope Dynamic Guard, ZP Click & Attack Softener and ZP Speech Engine leave the maturing list: BETA label removed from titles, windows, guides and READMEs. Requirements and limits (Clean & Paint external engine, ZP Speech runtime, Poppler/SWS) stay documented. ZP Magic Voice LAB keeps the LAB name by choice. Gain Match suspends while an OUTPUT LINK is active.
- **`ZP Click & Attack Softener 1.4` — stadio spettrale STFT `MICRO-CLICK` a tasche locali (`~940 Hz`), controllo continuo `Freq Skew` (`Low ↔ Air`), `Micro %` automatizzabile e grafica hardware ZP Suite**:
  - Aggiunge a monte del crossover SVF (con PDC fisso a `~14,7 ms` @ 48 kHz, zero salti di latenza in automazione) lo stadio spettrale attivabile **`MICRO-CLICK: ON/OFF`** (`slider19`, `fft_real/ifft_real` a finestra corta `5,3 ms` con overlap `75%` Hann-COLA, coerenza locale a tasche scorrevoli `~940 Hz` per catturare anche micro-sfrigolii risonanti stretti `5–9 kHz` tra consonanti e guardia glottica sulle vocali piene `< 800 Hz`) con controllo bipolare continuo **`Freq Skew`** (`-10..+10`, `slider22`) che calibra in tempo reale pavimento (`380 Hz..2,6 kHz`) e peso tra bande lasciando intatta la fondamentale vocale.
  - Il dosatore **`Micro %`** (`slider20`, smoothing anti-zipper a `5 ms`) è progettato per l'**automazione sulla timeline di REAPER** così da far lavorare il modulo solo nei passaggi sporchi; `D·MOLLA` isola anche il solo scarto **`DELTA: MICRO`**, il monitor eventi traccia le attenuazioni in ambra e l'interfaccia adotta lo stile hardware della ZP Suite (`slider1..14` e `16..18` invariati).
- **`ZP Click & Attack Softener 1.4` — STFT spectral `MICRO-CLICK` with local `~940 Hz` pocket coherence, continuous `Freq Skew` (`Low ↔ Air`), automatable `Micro %` & ZP Suite hardware UI**:
  - Adds a switchable **`MICRO-CLICK: ON/OFF`** (`slider19`) short-window STFT spectral stage (`5.3 ms`, `75%` Hann-COLA overlap, fixed `~14.7 ms` PDC @ 48 kHz with zero latency jumps) upstream of the SVF crossover, featuring sliding `~940 Hz` local sub-band coherence (catching narrow `5–9 kHz` resonant saliva sizzles between consonants without dulling clean speech), a `< 800 Hz` voiced-harmonic guard, and a continuous bipolar **`Freq Skew`** control (`-10..+10`, `slider22`, `380 Hz..2.6 kHz` floor).
  - Exposes a `5 ms` zipper-free **`Micro %`** (`slider20`) control tailored for **REAPER track automation** so it acts strictly where needed, dedicated **`DELTA: MICRO`** spring-audition, amber event telemetry, and ZP Suite hardware UI (`slider1..14` and `16..18` preserved).
- **Due template di progetto ZP calibrati (`-18 LUFS` VoiceOver e `-8 LUFS` Mix-Spot, solo plugin della Suite)**: inclusi come `ProjectTemplates` ReaPack, installati anche da `32 Installa toolbar` e apribili con un clic sia da `33 Benvenuto` sia da `23 ZP Chain Builder` (oltre che da *File → Project templates*), con bus voce, bus musica/effetti in sidechain su Harmonic Space Carver, sonde Shared Bus v3 e taratura Master Pro ai livelli di punta.
- **Two calibrated ZP Project Templates (`-18 LUFS` VoiceOver and `-8 LUFS` Mix-Spot, ZP Suite plugins only)**: shipped as ReaPack `ProjectTemplates`, also installed by `32 Install toolbar` and one-click accessible from both `33 Welcome` and `23 ZP Chain Builder` (as well as *File → Project templates*), complete with voice bus, sidechained music/SFX bus into Harmonic Space Carver, Shared Bus v3 probes and Master Pro peak-target calibration.

- **`30 ZP SRT 2.0` + `ZP_SRT_Engine.lua` — stazione unica sottotitoli a 4 schede e `Accorpa item brevi`**:
  - **Finestra unica operativa (`880×610` con zoom proporzionale)**: sostituisce il vecchio smistatore a finestre separate unificando in 4 schede **`1 · CARICA`** (Video + SRT/VTT/Excel `.xlsx`, Solo SRT, Solo Video, Cartella Batch con stacco regolabile, punto d'inserimento e gestione sovrapposizioni su 2ª corsia rossa o taglio coda), **`2 · SOSTITUISCI & LINGUE`** (aggiornamento sottotitoli con salvataggio pulito su un'unica traccia muta `BKP` e aggiunta tracce lingua Reference `ENG/ORIG/FRA/ESP/DEU` o libera anche su più video selezionati o regioni), **`3 · MODIFICA & ACCORPA`** (ispettore live con CPS e origine SRT, editor `ZP_Editor_Copione` integrato nella finestra, `+ Nuova battuta`, unione/divisione alla playhead o per righe e offset rapidi) e **`4 · ESPORTA`** (esportazione per video/regioni/traccia intera + SRT dai take marker audio `31`).
  - **Nuovo `Accorpa item brevi` (in timeline e all'importazione)**: individua e assorbe automaticamente le micro-battute da `1–3` parole lasciate dalle trascrizioni automatiche nel blocco di dialogo adiacente (anche di 2–3 righe), guidandosi con punteggiatura e distanza temporale, senza mai fondere cambi d'interlocutore (`- ` o `PERSONAGGIO:`), pause lunghe o item agganciati all'audio (`29`), e ricalcolando intatte ancore ed evidenziazioni del Gobbo in un solo passo di `Undo`. Gli script singoli (`01`, `05`, `06`, `08`, `13`, `31`, `38`) restano intatti e compatibili.
- **`30 ZP SRT 2.0` + `ZP_SRT_Engine.lua` — unified 4-tab subtitle workstation & `Coalesce short cues`**:
  - **Single always-open workstation (`880×610` proportional zoom)**: replaces the multi-window launcher with 4 direct tabs — **`1 · LOAD`** (Video + SRT/VTT/Excel `.xlsx`, SRT only, Video only, Folder Batch, insertion point & overlap mode), **`2 · REPLACE & LANG`** (subtitle replacement with clean muted `BKP` safety track and multi-video/region Reference language tracks), **`3 · EDIT & COALESCE`** (live CPS/origin inspector, embedded `ZP_Editor_Copione` modal, `+ New cue`, Playhead/Line split, manual merge & quick nudges), and **`4 · EXPORT`** (relative-timecode video/region/track export + audio take-marker SRT export `31`).
  - **Smart `Coalesce short cues` (on timeline & on import)**: automatically absorbs isolated `1–3` word transcription slivers into their natural adjacent dialogue block (including 2–3 line blocks) using punctuation and gap proximity while respecting pauses, dialogue dashes, speaker prefixes, audio-synced cues (`29`), and Teleprompter word anchors/highlights in a single `Undo` block.
- **Nuovo `ZP Spoken Finish Pro 1.0.0` (affiancato al classico `ZP Spoken Finish 3.10.2` per 100% recall sessioni) — firma sonora `MAGIC` (`VELVET · AIR SILK · 3D FOCUS` con `S-Guard`), motore armonico Chebyshev 2× e curva creativa a due zone**:
  - **Retrocompatibilità totale delle sessioni esistenti**: `ZP Voce/ZP Spoken Finish.jsfx` resta sul motore classico `3.10.2` (stesso DSP, stessi preset `Simple`/`Advanced` e stessa `ZP_Bus_VoiceChain.RfxChain`), mentre la nuova generazione è distribuita come plugin autonomo **`ZP Voce/ZP Spoken Finish Pro.jsfx` (`1.0.0`)** con sezione guida `?` dedicata (`#plugin-spoken-finish-pro`) e telemetria `Shared Bus v3`.
  - **Modulo firma `MAGIC` (OFF di default, immediato in `Simple` e `Advanced`)**: trasforma con un clic e un solo dosatore (`Magic %`) una voce povera o spenta in una voce ricca e tridimensionale tramite 3 caratteri selezionabili al volo con morphing morbido senza click: **`VELVET`** (calore di prossimità `H2` `125–260 Hz` + tasca anti-cartone `380 Hz` + alte vellutate), **`AIR SILK`** (aria armonica `> 7 kHz` stile Dolby-361 / Aphex con **`S-Guard` automatica** `> 4,8 kHz` che apre vocali e respiro abbassandosi istantaneamente sulle sibilanti `S/Z/F`) e **`3D FOCUS`** (rete all-pass analogica a 2 stadi in serie + densità formantica `1,6–4,5 kHz` per portare la voce in primo piano a parità di LUFS).
  - **Motore armonico Chebyshev normalizzato 2× + 3 zone coerenti di fase + curva creativa a due zone (`0–42%` / `42–100%`)**: sintesi `H2 + H4` pari e `H3 + H5` dispari in oversampling 2× sul solo residuo (`0,00 dB` fino a `20 kHz`, passa-alto `0,9× Crossover` anti-DC e anti-intermodulazione), de-exciter dinamico sui valori negativi senza inversioni HF, `Voice of God` con 2ª armonica toracica, `Cinema Air` reale (`> 6,2 kHz`), `Gain Match` esteso (`-6..+3 dB`), `DELTA` puro (auto-off `30 s`), tema `CHIARO / SCURO` persistente (`ext_noinit = 1`) e **True Peak Limiter 4× cubico**.
- **New `ZP Spoken Finish Pro 1.0.0` (shipped alongside classic `ZP Spoken Finish 3.10.2` for 100% session recall) — `MAGIC` sonic signature (`VELVET · AIR SILK · 3D FOCUS` with `S-Guard`), 2× Chebyshev harmonic engine & two-zone creative drive**:
  - **Full session backward compatibility**: `ZP Voce/ZP Spoken Finish.jsfx` remains on the classic `3.10.2` engine (identical DSP, `Simple`/`Advanced` presets, and `ZP_Bus_VoiceChain.RfxChain`), while the new architecture ships as a standalone plugin **`ZP Voce/ZP Spoken Finish Pro.jsfx` (`1.0.0`)** with dedicated `?` guide anchor (`#plugin-spoken-finish-pro`) and `Shared Bus v3` telemetry.
  - **`MAGIC` signature module (OFF by default, one-click in `Simple` & `Advanced`)**: turns thin, dull, or home-booth vocals into rich, dimensional studio voices via one `Magic %` control and 3 click-free morphing cartridges: **`VELVET`** (`125–260 Hz` `H2` proximity warmth + `380 Hz` anti-box scoop + creamy ribbon top), **`AIR SILK`** (`> 7 kHz` Dolby-361 style harmonic air with level-independent **`S-Guard`** that blooms on vowels while ducking automatically on `S/Z/F` sibilants), and **`3D FOCUS`** (2-stage unitary analog all-pass dispersion + `1.6–4.5 kHz` upward formant density at matched loudness).
  - **Envelope-normalized 2× Chebyshev harmonic engine + phase-coherent 3-zone contour + two-zone control law (`0–42%` / `42–100%`)**: rich `H2 + H4` / `H3 + H5` harmonics in residual-only 2× oversampling (`0.00 dB` linear error up to `20 kHz`, `0.9× Crossover` harmonic high-pass), bounded dynamic de-exciter with zero phase inversion, 2nd-harmonic chest `Voice of God`, `> 6.2 kHz` `Cinema Air`, widened `Gain Match` (`-6..+3 dB`), pure sample-aligned `DELTA` (`30 s` auto-off), persistent `LIGHT / DARK` theme (`ext_noinit = 1`), and real **4× cubic True Peak** limiting.
- **`ZP Magic Voice LAB 1.2.7` — trasparenza lineare 20 kHz, cartucce hardware UAD e rifinitura interfaccia**:
  - **Oversampling 2× sul solo residuo armonico (`0,00 dB` fino a Nyquist) e allineamento al campione**: eliminati il roll-off sulle alte (`-5,5..-10,9 dB @ 20 kHz`), lo scavo di fase `-3,4 dB` sul crossover di `Dynamic Balance` e il disallineamento di `DELTA / D·MOLLA / MIX` parallelo; `Preamp`, `Dynamic Balance` e `Safety Limiter` processano ora in 2× il solo residuo non lineare `f(x)-x` con riallineamento al campione dei rami lineari e dry.
  - **Legame OUTPUT + Limiter pulito**: riferimento predefinito del picco vocale portato a `-19 dBFS` (evita rialzi indebiti di `OUTPUT` alzando `INPUT` a `0 dB` di riduzione) e aggiunto micro-attacco morbido (`0,35 ms`) al `Sample Peak Limiter` per eliminare ruvidità sui picchi quando `PEAK CEIL` viene raggiunto; corretti inoltre 3 indici slider nella telemetria `Shared Bus v3`.
  - **5 cartucce hardware calibrate su riferimenti UAD + UI snella**: mantenuto intatto al 100% `0 · GLUE` (firma MagicFlow AU) e ritarate le cartucce `1..4` sulle misure reali di **`VOXBOX`** (*UAD Manley VoxBox*), **`NEVE`** (*UAD Neve 1073*), **`VCA`** (*UAD SSL E / API*) e **`TAPE`** (*UAD Studer A800 15 IPS*) a parità di RMS sul parlato (`0,00 ± 0,02 dB`). In `1 · INPUT & PEAK` la spia sopra `PEAK RED` diventa un **LED gioiello dinamico di riduzione** (senza scritta), la barra in basso diventa il **meter reale `Input Level`** (con tacca a `-18 dBFS`), i pulsanti di legame d'uscita adottano il simbolo compatto **`∞`** senza testo e il pannello 3 diventa **`3 · DYN EQ TONE & BALANCE`**.
- **`ZP Magic Voice LAB 1.2.7` — 20 kHz linear transparency, UAD hardware cartridges & UI refinement**:
  - **Residual-only 2× oversampling (`0.00 dB` up to Nyquist) & sample alignment**: removed HF linear roll-off (`-5.5..-10.9 dB @ 20 kHz`), the `-3.4 dB` phase notch on the `Dynamic Balance` crossover, and `DELTA / S·DELTA / MIX` comb-filtering by restricting 2× oversampling in `Preamp`, `Dynamic Balance`, and `Safety Limiter` strictly to the nonlinear residual `f(x)-x` with exact sample alignment across linear and dry paths.
  - **Clean Output Link + Limiter**: calibrated default voice peak reference (`-19 dBFS`) so raising `INPUT` never falsely boosts `OUTPUT` at `0 dB` Peak GR, added `0.35 ms` smooth micro-attack to the `Sample Peak Limiter`, and fixed 3 `Shared Bus v3` telemetry slider indices.
  - **5 UAD-calibrated hardware cartridges & cleaner UI**: preserved `0 · GLUE` (MagicFlow AU signature) 100% intact and recalibrated `1..4` against measured **`VOXBOX`** (*UAD Manley VoxBox*), **`NEVE`** (*UAD Neve 1073*), **`VCA`** (*UAD SSL E / API*), and **`TAPE`** (*UAD Studer A800 15 IPS*) Audio Units (`0.00 ± 0.02 dB` speech RMS). Replaced the static `PEAK` label/toggle above `PEAK RED` with a **label-free dynamic GR jewel LED**, converted the bottom bar of Panel 1 into a live **`Input Level` meter** (`-18 dBFS` tick), replaced `"LEGA OUTPUT"` text buttons with compact **`∞`** link buttons, and updated Panel 3 title to **`3 · DYN EQ TONE & BALANCE`**.
- **Taratura strumentale `LA2 GRAY` in `ZP BUS Chain 1.3.7` su Teletronix LA-2A Gray**:
  - Eliminata l'opacizzazione sulle alte frequenze (fino a `-6,3 dB` a `20 kHz` nel vecchio decimatore lineare) e la cancellazione di fase sul controllo `MIX` parallelo: lo stadio valvolare `12AX7A / 12BH7A` applica ora l'**oversampling 2× sul solo residuo non lineare** (`0,00 dB` di perdita lineare fino a Nyquist, DC blocker a `6 Hz` confinato al solo residuo armonico, `MIX` parallelo sincrono al campione).
  - Curva tonale del trasformatore d'uscita **UTC A-24** allineata entro `±0,03 dB` alle misure del riferimento hardware/UAD (`0,00 dB` fino a `20 Hz` e dolce apertura d'aria `+0,24 dB @ 10 kHz`, `+0,56 dB @ 15 kHz`, `+0,81 dB @ 20 kHz`, attiva come puro line-amp anche a `RED = 0`), armoniche calibrate (`H2 = -58,5 dBc` a `-18 dBFS` senza schiacciamento dinamico sui picchi), sidechain ad enfasi aperta che risparmia l'aria sui `6–10 kHz` e inviluppo cella **T4B** reale (attacco rapido + 50% del rilascio in `60 ms` con memoria del fosforo). Modalità **`CLEAN`** invariata al 100%.
- **Instrumental calibration of `LA2 GRAY` in `ZP BUS Chain 1.3.7` on Teletronix LA-2A Gray**:
  - Removed high-frequency dulling and parallel `MIX` phase cancellation via **residual-only 2× oversampling** (`0.00 dB` linear HF loss up to Nyquist, `6 Hz` DC blocker strictly on the harmonic residual, sample-aligned parallel `MIX`), matched **UTC A-24** output transformer air curve (`±0.03 dB` across `20 Hz–20 kHz`, `+0.81 dB @ 20 kHz`, pure tube/transformer line-amp at `RED = 0`), calibrated `12AX7A / 12BH7A` harmonics (`H2 = -58.5 dBc @ -18 dBFS`), open-emphasis sidechain sparing `6–10 kHz` air, and true dual-stage **T4B** ballistics (fast optical strike + 50% release in `60 ms` with phosphor memory). **`CLEAN`** mode 100% unchanged.
- **Capacità loudness spot radio (`-8 LUFS`), oversampling 2× e headroom intermedio (`ZP Master Pro 2.51` + `ZP BUS Chain 1.3.6`)**:
  - **`ZP Master Pro 2.52` (profilo `TRANSP` + meter LIVE)**: aggiunto **Pre-Clipper trasparente 2× oversampled** (`PRECLIP 0..100%`, `slider74`) prima del Precision Limiter `4× ISP` per smussare gli spike brevi senza aliasing sulle medio-alte, **oversampling 2×** sullo shaper pre-ceiling di `ENHANCE` (lift fino a `+7.5 dB`) con **guardia dinamica anti-asprezza `2.4–6.2 kHz`** (`0..-3.2 dB`), escursione `INPUT` estesa a `-12..+30 dB`, target `LUFS / RMS / L+R` estesi fino a `-6 dB`, preset rapido **`SPT` (`-8 LUFS`)**, meter LIVE (`M/S/I/RMS/TP/IN`) riallineati alla scala dB non lineare dell'asse con linee verdi Target, linea rossa Ceiling e peak-hold flottante su `TP` stereo.
  - **`ZP BUS Chain 1.3.6`**: stadio valvolare **`LA2 GRAY`** aggiornato a **2× oversampling** con curva asintotica continua (rimosso il vecchio hard clamp), modulo **`ANA`** con guardia morbida pre-folding e pulsante **`PAD -6`** auto-compensato (`slider81`, `-6 dB` in / `+6 dB` out), e saturazione **`SAT`** del Voice Limiter in **2× oversampling** per azzerare l'aliasing medio-alto sui bus spinti.
  - **`ZP Magic Voice LAB 1.2.6`**: headroom intermedio pulito senza cambio PDC (`0`) né cambio di firma timbrica — **Preamp** (tutti e 5 i profili hardware) in **2× oversampling**, **Dynamic Balance** convertito da polinomio cubico aperto a curva razionale monotona in **2× oversampling** (elimina il foldback digitale oltre `0 dBFS`) e **Safety Limiter** con rilevamento **True Peak 4× cubico reale** + soft-knee catcher **2× oversampled** negli ultimi `1.5 dB` sotto ceiling.
- **Radio spot loudness capacity (`-8 LUFS`), 2× oversampling & intermediate headroom (`ZP Master Pro 2.51` + `ZP BUS Chain 1.3.6`)**:
  - **`ZP Master Pro 2.52` (`TRANSP` profile + LIVE meter)**: added a **2× oversampled transparent Pre-Clipper** (`PRECLIP 0..100%`, `slider74`) ahead of the `4× ISP` Precision Limiter to shave fast spikes cleanly without upper-mid aliasing, **2× oversampling** on the `ENHANCE` pre-ceiling shaper (up to `+7.5 dB` lift) with a **dynamic `2.4–6.2 kHz` de-harshness guard** (`0..-3.2 dB`), extended `INPUT` drive (`-12..+30 dB`), `LUFS / RMS / L+R` targets extended up to `-6 dB`, quick **`SPT` (`-8 LUFS`)** preset, and LIVE meters (`M/S/I/RMS/TP/IN`) realigned to the nonlinear dB axis with green Target lines, red Ceiling line, and floating stereo `TP` peak-hold.
  - **`ZP BUS Chain 1.3.6`**: **`LA2 GRAY`** tube stage upgraded to **2× oversampling** with a smooth asymptotic curve (removing hard clamping), **`ANA`** upgraded with a smooth pre-folding guard plus auto-compensated **`PAD -6`** toggle (`slider81`), and **Voice Limiter `SAT`** upgraded to **2× oversampling** to eliminate upper-mid aliasing on hot mixes.
  - **`ZP Magic Voice LAB 1.2.6`**: clean intermediate headroom with zero PDC change and unchanged calibrated tone — **Preamp** (all 5 hardware profiles) upgraded to **2× oversampling**, **Dynamic Balance** Low/Mid saturation replaced with a bounded monotonic rational curve at **2× oversampling** (eliminating digital foldback above `0 dBFS`), and **Safety Limiter** upgraded to real **4× cubic True Peak** detection + **2× oversampled** `1.5 dB` soft-knee catcher.
- **Fix crash `Cue Navigator`, LED ON/OFF diretti in `ZP Magic Voice LAB`, `ZP BUS Chain 1.3.5` (`LA2 GRAY T4B` + rack auto-compatto) e manleva GPLv3**:
  - **`ZP Harmonic Space Carver Cue Navigator.lua`**: validazione `MediaTrack*` (`ValidatePtr2`) in `collect_voice_items()`, `sc_channels()` e `voice_tracks()` + rescan automatico al cambio progetto o numero tracce, eliminando il crash `bad argument #1 to 'GetMediaTrackInfo_Value'` quando una traccia voce viene eliminata tra due rescan.
  - **`ZP Magic Voice LAB`**: LED cliccabili ON/OFF direttamente sui moduli **PEAK**, **DYN EQ**, **TONE** e **DYN BAL** nei rispettivi pannelli (sincronizzati con la striscia Dymo in testata) + escursione libera del vertice `FREQ` DRC (`24 Hz–19 kHz`) anche con `OCT`/Q largo (restringimento simmetrico `lo * hi = fc^2` contro i limiti `20 Hz / 20 kHz`).
  - **`ZP Loudness Meter Multichannel 45.3`**: colonna sinistra a larghezza fissa con numeri grandi stabili e meter canali espandibili, finestra `DERIVA 60s` opzionale (OFF di default) con tasto diretto `DERIVA` in testata + legenda e tooltip leggibili, **rotore target a 9 scatti discreti** (`-24 / -21 / -18 / -16 / -14 / -12 / -10 / -8 / -6 LUFS`, con trascinamento, rotella, `- / +` e scala cliccabile, affiancato a `TARGET` libero e `SEGUI QUI`) e pulsante tema orientato all'azione (`CHIARO` quando è scuro, `SCURO` quando è chiaro).
  - **`ZP BUS Chain 1.3.5`**: nuovo motore opto-valvolare **`LA2 GRAY`** (selettore `CLEAN | GRAY`, retrocompatibile su `CLEAN`) con trasformatori ingresso/uscita sempre in percorso anche a `0 dB` GR, armoniche valvolari asimmetriche H2/H3 con DC blocker `16 Hz`, cella T4B dual-stage con memoria del fosforo, soft knee `12 dB` e sidechain HF R37; rack auto-compatto con i 7 pulsanti di presenza modulo (default `SOLO ATTIVI`, clic = accendi/spegni e mostra solo attivi, **tasto destro / Alt+clic = isola quel solo modulo**, rimossi gli ON/OFF duplicati nei pannelli e barra tooltip agganciata al fondo del rack).
  - **Guide tecniche 2.6.9 e manleva di responsabilità**: aggiornate le guide IT/EN (inclusa guida tecnica `ZP Master Pro 2.50` `ANALOG/TRANSP/ENHANCE/4× True Peak`, `ZP Audition Noise Monitor`, `39 ZP Telemetry Engine`, `Voice-Music Probe 1.6`, `BUS Chain 1.3.5`) e aggiunta l'esclusione di garanzia GPLv3 («così com'è») in README e guide.
- **Rilevamento comb filtering cepstrale (`BrownSlope Prism 1.2`), hardening PDC/Sample-Rate e `ZP Audition Noise Monitor 1.1`**: aggiunto in `ZP BrownSlope Prism` (senza carico sui sensori di traccia) un rilevatore cepstrale reale (`0,33–8 ms`) che segnala eventuali cancellazioni di fase in testata (`COMB`) e su **Shared Bus v3** verso **ZP Telemetry Engine** (con alert immediato anche quando un FX ha *Ignore PDC* attivo in REAPER e latenza `> 0`), più `rebuild_sr_tables()` al cambio sample rate, griglia moderna con suddivisioni logaritmiche e crosshair mouse. `ZP Audition Noise Monitor 1.1` corregge la calibrazione RMS reale dei 4 ambienti (`0 dBFS`), porta il controllo SNR fino a `+6 dB` (tasti fino a `+3 dB`), aggiunge 4 profili di ascolto diffusori su Monitor FX (**Studio Flat**, **Auto / Furgone**, **Soffitto Mono**, **Cuffiette Open** con attenuazione passiva del rumore) e soft-limiter protettivo `-0,3 dBFS`. Induriti lookahead, buffer ring e cambio sample rate su **Harmonic Space Carver 2.6.13** (`0` PDC con Anticipo a 0; PDC fisso a `20 ms` quando attivo con dual-tap ring buffer senza click), **Stagekeeper 2.5.4**, **Master Pro 2.50**, **Magic Voice LAB 1.2.5**, **Click & Attack Softener 0.3**, **BUS Chain 1.3.4** e **Voiceover Unified Chain 4.1.10**.
- **ZP Master Pro 2.50 (profilo `TRANSPARENT + ENHANCE`) e `ZP Audition Noise Monitor 1.0` (Monitor FX)**: nuovo selettore in testa a `ZP Master Pro` per passare al volo tra **ANALOG** (catena classica Tape + Glue Matrix + Tone + Lookahead Limiter, intatta al 100%) e **TRANSPARENT** (percorso pulito senza colorazione analogica con **Input Drive**, dosatore **ENHANCE 0–100%** per sollevare corpo e micro-dettagli con gate anti-soffio, **Soft Knee**, **Precision Lookahead Limiter** con **Auto-Release dual-stage**, **True Peak 4×** e grafico live della curva di trasferimento). Aggiunto il plugin dedicato **ZP Audition Noise Monitor** per la catena **Monitor FX** di REAPER (mai renderizzato nel mix) con 4 profili acustici calibrati (**Auto Città**, **Autostrada**, **Ambiente Rosa**, **Treno/Aereo**), livello SNR riferito al target LUFS, gate allo stop e telecomando diretto dalla testata di `ZP Master Pro` (`gmem[3670..3683]`).
- **ZP Telemetry Engine (`39_ZP_Telemetry_Engine.lua`) e Shared Bus v3.1 (`ZP Master Pro 2.49`, `Voice-Music Probe 1.6`, `BrownSlope Prism 1.2`, `Loudness Meter 45.1`)**: servizio di analisi a finestra lenta separato da `Cue Navigator` che legge il grafo reale di routing di REAPER (folder, send, fader, mute/solo, plugin ZP e plugin terze parti VST3/AU/CLAP con `GainReduction_dB` host) e misura la catena rispetto a un metro fisso (**Brown `-4,5 dB/oct ±10%`**, oppure l'orizzonte di **Tone Guard** su Master Pro quando acceso). Distingue automaticamente progetti **Solo Voce (`85–14k Hz` + controllo rumble `<80 Hz`, senza falsi allarmi su HPF vocale)** da **Full Mix (`40–14k Hz`)** con analisi mascheramento Voce/Musica agganciata a **ZP Harmonic Space Carver** (VCA Ducker, Carver Mid `800–4k` e Carver Low `40–160`), distingue le opposizioni a vuoto ("tiro alla fune") dalla pre-enfasi intenzionale prima di un compressore/saturatore, risolve i falsi `BUS NON ATTIVO` / `DATI BUS VECCHI` senza `BUS Chain` e apre con un clic qualsiasi plugin a monte.
- **ZP Shared Bus v3 (`ZP Master Pro 2.48` + 9 plugin JSFX + `Cue Navigator 1.16`)**: flusso telemetrico organico e multi-istanza dai singoli canali (Magic Voice LAB 1.2.4, Spoken Finish 3.10.2, Stagekeeper 2.5.3, Click & Attack Softener 0.2), dai bus (BUS Chain 1.3.3, Unified Chain 4.1.9, BrownSlope Dynamic Guard 0.5.1-assist-dev, Harmonic Space Carver 2.6.12) e dalle sonde (Voice-Music Probe 1.4 Voice e Music) verso `ZP Master Pro`. Nel Navigator di Master Pro arrivano le schede **SINTESI** e **CATENA** (nodi ordinati da monte a valle con compressione, DynEQ/DRC, limiter, tono, RMS/delta, alert **DELTA/SOLO/CHECK** a monte, contesto Music Probe/Carver e, con Cue Navigator attivo, nomi reali delle tracce e **click-per-aprire** la finestra del plugin a monte). DSP audio, slider e retrocompatibilità Shared Bus v2.20 invariati.
- **ZP Harmonic Space Carver 2.6.12 e Cue Navigator 1.16**: ReaPack riceverà l'aggiornamento che seleziona il cue quando si clicca il suo marker #HSC a trasporto fermo.
- **ZP Magic Voice LAB 1.2.4**: ReaPack riceverà `HW INS` (`slider57`), il banco interno a 5 firme hardware (`GLUE`, `TUBE`, `IRON`, `BCAST`, `TAPE`, `slider58`), la taratura fine `0 · GLUE` / catena (EQ/LPF e all-pass a 6 stadi riallineati in fase/ampiezza, compensazione spettrale DRC, Dynamic EQ B bassa, Peak Leveler), restyling hardware old-style, `LEGA OUTPUT`, memoria `A/B` e uscita fino a `±24 dB`.
- **Beta**: Clean & Paint, Montaggio Parlato, BrownSlope Dynamic Guard e Click & Attack Softener restano pacchetti separati; prerequisiti e limiti sono descritti in README e nella guida.

- **Cepstral comb-filter detection (`BrownSlope Prism 1.2`), PDC/Sample-Rate hardening & `ZP Audition Noise Monitor 1.1`**: added a real zero-track-overhead cepstral comb detector (`0.33–8 ms`) inside `ZP BrownSlope Prism` with a header `COMB` badge, **Shared Bus v3** alert toward **ZP Telemetry Engine** (plus immediate alert when REAPER's *Ignore PDC* is enabled on any FX with latency `> 0`), `rebuild_sr_tables()` on sample-rate changes, and a modernized log-subdivided spectrum grid with mouse crosshair. `ZP Audition Noise Monitor 1.1` fixes real `0 dBFS` RMS calibration across all 4 profiles, extends SNR control up to `+6 dB` (quick steps up to `+3 dB`), adds 4 Monitor FX speaker simulations (**Studio Flat**, **Car / Van**, **Ceiling Mono**, **Open Earbuds** with passive external noise attenuation), and adds a `-0.3 dBFS` protective soft-limiter. Hardened lookahead, ring buffers, and sample-rate changes across **Harmonic Space Carver 2.6.13** (`0` PDC at 0 ms; fixed `20 ms` PDC when active with click-free dual-tap ring buffer), **Stagekeeper 2.5.4**, **Master Pro 2.50**, **Magic Voice LAB 1.2.5**, **Click & Attack Softener 0.3**, **BUS Chain 1.3.4**, and **Voiceover Unified Chain 4.1.10**.
- **ZP Master Pro 2.50 (`TRANSPARENT + ENHANCE` profile) & `ZP Audition Noise Monitor 1.0` (Monitor FX)**: new header switch in `ZP Master Pro` to A/B between **ANALOG** (original Tape + Glue Matrix + Tone + Lookahead Limiter chain, 100% preserved) and **TRANSPARENT** (clean uncolored path with **Input Drive**, **ENHANCE 0–100%** upward-density loudness shaper with noise-floor gate, **Soft Knee**, dual-stage **Auto-Release** **Precision Lookahead Limiter**, **4× True Peak**, and live transfer curve graph). Adds the dedicated **ZP Audition Noise Monitor** JSFX for REAPER's **Monitor FX** chain (never printed to mix or renders) featuring 4 calibrated acoustic profiles (**City Car**, **Highway**, **Pink Environment**, **Train/Jet**), LUFS-referenced SNR level, stop gate, and direct remote control from `ZP Master Pro`'s header (`gmem[3670..3683]`).
- **ZP Telemetry Engine (`39_ZP_Telemetry_Engine.lua`) & Shared Bus v3.1 (`ZP Master Pro 2.49`, `Voice-Music Probe 1.6`, `BrownSlope Prism 1.2`, `Loudness Meter 45.1`)**: dedicated slow-window advisory engine (separate from `Cue Navigator`) reading REAPER's real routing DAG (folders, sends, faders, mute/solo, ZP plugins and 3rd-party VST3/AU/CLAP FX with host `GainReduction_dB`) against a fixed reference frame (**Brown `-4.5 dB/oct ±10%`**, or **Master Pro Tone Guard** whenever engaged). Automatically adapts between **Voice Only (`85–14k Hz` + `<80 Hz` rumble-only check, no false HPF low-end alerts)** and **Full Mix (`40–14k Hz`)** with Voice/Music masking guidance tied directly to **ZP Harmonic Space Carver** (VCA Ducker, Carver Mid `800–4k`, Carver Low `40–160`), distinguishes wasteful opposing EQ/gain moves from intentional pre-emphasis before active dynamics/saturation, fixes false `BUS OFFLINE` / `BUS DATA OLD` alerts without `BUS Chain`, and opens any upstream FX on click.
- **ZP Shared Bus v3 (`ZP Master Pro 2.48` + 9 JSFX plugins + `Cue Navigator 1.16`)**: organic multi-instance telemetry flow from individual channels (Magic Voice LAB 1.2.4, Spoken Finish 3.10.2, Stagekeeper 2.5.3, Click & Attack Softener 0.2), buses (BUS Chain 1.3.3, Unified Chain 4.1.9, BrownSlope Dynamic Guard 0.5.1-assist-dev, Harmonic Space Carver 2.6.12), and probes (Voice-Music Probe 1.4 Voice & Music) into `ZP Master Pro`. Master Pro's Navigator adds **SINTESI** and **CATENA** tabs (nodes ordered upstream to downstream with compression, DynEQ/DRC, limiter, tone, RMS/delta, upstream **DELTA/SOLO/CHECK** safety alerts, Music Probe/Carver context, and — when Cue Navigator is running — real track names and **click-to-open** upstream FX windows). Audio DSP, sliders and Shared Bus v2.20 compatibility remain unchanged.
- **ZP Harmonic Space Carver 2.6.12 and Cue Navigator 1.16**: ReaPack will deliver cue selection when its #HSC marker is clicked while stopped.
- **ZP Magic Voice LAB 1.2.4**: ReaPack will deliver `HW INS` (`slider57`), the internal 5-profile hardware signature bank (`GLUE`, `TUBE`, `IRON`, `BCAST`, `TAPE`, `slider58`), `0 · GLUE` / chain fine calibration (phase/magnitude-aligned EQ/LPF & 6-stage all-pass, DRC spectral compensation, Dynamic EQ B low band, Peak Leveler), old-style hardware panel restyling, `LINK OUTPUT`, `A/B` memory and output gain up to `±24 dB`.
- **Beta**: Clean & Paint, Montaggio Parlato, BrownSlope Dynamic Guard and Click & Attack Softener remain separate packages; prerequisites and limitations are documented in the README and guide.

## ZP Studio Suite 2.6.8 — 2026-11-21

- **ZP Magic Voice LAB (ZP Voce): LEGA OUTPUT e memoria A/B**: sulle righe PEAK, DYN EQ, TONE SCL e DYN BAL un pulsante con la catenella lega il modulo a `OUTPUT`, che si corregge di quanto il modulo alza o abbassa (calcolato dai parametri; per i moduli dinamici sul livello medio della voce degli ultimi secondi, INPUT compreso): si giudica il suono a parità di volume. Comandi coinvolti in viola. Memoria di lavoro A/B nella barra USCITA (A, B, A=B), salvata nel progetto. `OUTPUT` ora ±24 dB. Pulsante `?` che apre la guida dedicata.
- **ZP Magic Voice LAB (ZP Voce): LINK OUTPUT and A/B memory**: a chain button on the PEAK, DYN EQ, TONE SCL and DYN BAL rows links the module to `OUTPUT`, which moves by the gain the module adds or removes (computed from the parameters; dynamic modules use the average voice level of the last seconds, INPUT included): you judge the sound at equal loudness. Involved controls turn purple. A/B working memory in the OUTPUT bar (A, B, A=B), saved with the project. `OUTPUT` now ±24 dB. `?` button opening the dedicated guide.
- **ZP Harmonic Space Carver 2.6.11 (ZP Voce): cue fino alla voce e LOCK**: dopo la rampa (regolabile per marker fino a 1200 ms) la musica resta a duck 0 fino al primo suono del sidechain dopo un silenzio; tolti i preset C/S/M/L. `LOCK` nel pannello Carver: attacco e rilascio del Carver comandati dal VCA (Voice Hold e rientro GRADUAL compresi). Cue Navigator 1.15 allineato (formato di scambio della rampa allargato).
- **ZP Harmonic Space Carver 2.6.11 (ZP Voce): cues held until the voice, and LOCK**: after the ramp (per marker, up to 1200 ms) music stays at 0 dB ducking until the first sidechain sound after a silence; C/S/M/L presets removed. `LOCK` in the Carver panel: Carver attack and release driven by the VCA (Voice Hold and GRADUAL recovery included). Cue Navigator 1.15 updated (wider ramp exchange format).
- **ZP SOLO Recorder e telecomando web: loop della selezione**: cerchietto sul PLAY che fa della selezione temporale la zona di loop e accende il Repeat di REAPER; stato sempre allineato a REAPER.
- **ZP SOLO Recorder and web remote: selection loop**: a small circle on PLAY turns the time selection into the loop area and enables REAPER Repeat; state always follows REAPER.
- **ZP Remote: FFmpeg trovato ovunque e spiegato**: un solo elenco di ricerca (scelta dell'utente, PATH, `/usr/local/bin`, `/opt/homebrew/bin`, `/opt/local/bin`) per Benvenuto, Crea pacchetto ed esportatore, che riceve il percorso con `--ffmpeg`: risolto il caso del Mac Intel con REAPER aperto dal Finder (Benvenuto verde, esportazione fallita). Il Benvenuto mostra percorso e versione, riconosce un FFmpeg che non parte, offre «Scegli FFmpeg…» e «Come installare FFmpeg…» (nuova pagina dell'help per Mac Apple Silicon e Intel, Windows e Linux). La guida audio segnala gli errori del decoder.
- **ZP Remote: FFmpeg found everywhere and explained**: one search list (user choice, PATH, `/usr/local/bin`, `/opt/homebrew/bin`, `/opt/local/bin`) for Welcome, Create package and the exporter, which gets the path via `--ffmpeg`: fixes Intel Macs with REAPER opened from the Finder (green Welcome, failed export). The Welcome shows path and version, detects an FFmpeg that does not run, offers "Choose FFmpeg…" and "How to install FFmpeg…" (new help page for Apple Silicon and Intel Macs, Windows and Linux). The audio guide reports decoder errors.
- **Grafica zoomabile davvero distribuita**: 10 JSFX e il Cue Navigator erano cambiati nella 2.6.7 senza alzare la versione, quindi ReaPack non li aggiornava: ora Master Pro 2.47, Mirror EQ 0.064, Oscilloscope 12.2, Voice-Music Probe 1.3, BUS Chain 1.3.2, Spoken Finish 3.10.1, Stagekeeper 2.5.2, Subliminal 3.2.3, Unified Chain 4.1.8 (solo grafica, audio invariato).
- **Zoomable graphics actually shipped**: 10 JSFX and the Cue Navigator changed in 2.6.7 without a version bump, so ReaPack did not update them: now Master Pro 2.47, Mirror EQ 0.064, Oscilloscope 12.2, Voice-Music Probe 1.3, BUS Chain 1.3.2, Spoken Finish 3.10.1, Stagekeeper 2.5.2, Subliminal 3.2.3, Unified Chain 4.1.8 (graphics only, audio unchanged).
- **Help**: pagina Glue Matrix di Master Pro ora distribuita e collegata dalla scheda Master Pro; icona di Collega marker distribuita (prima l'immagine era rotta).
- **Help**: Master Pro Glue Matrix page now shipped and linked from the Master Pro card; Link markers icon shipped (the image was broken before).
- **Sviluppo**: `tools/prova_installazione.sh` installa la prossima release in un REAPER di prova esattamente come ReaPack (indice locale), con fumo JSFX e confronto con il repo; `run_all.sh` controlla anche le funzioni JSFX usate prima di essere definite.
- **Development**: `tools/prova_installazione.sh` installs the next release in a test REAPER exactly like ReaPack (local index), with a JSFX smoke test and repo comparison; `run_all.sh` also catches JSFX functions used before being defined.
- **ZP Render & Copy: storico scorrevole nel pannello STATO**: quando i messaggi superano lo spazio visibile, il registro di `STATO` ora scorre con rotella/trackpad, tastiera (Frecce, PagSu/PagGiù, Home/End) e barra laterale cliccabile/trascinabile (con indicatore di riga cliccabile per tornare subito in cima e posizione salvata per progetto).
- **ZP Render & Copy: scrollable STATO log**: when messages exceed the visible area, the `STATO` history now scrolls via mouse wheel/trackpad, keyboard (Arrows, PageUp/PageDown, Home/End) and an interactive draggable/clickable scrollbar (with a top-right position indicator to jump back to top and per-tab scroll state).
- **ZP Loudness Meter Multichannel 45.0 (ZP Misura)**: interfaccia ridisegnata da zero in formato vertical-first anti-deriva (`268×580`, leggibile fino a `180 px`), con `TARGET` libero + pulsante `SEGUI QUI` (`LOCK NOW`), 4 scorciatoie (`-23 / -18 / -16 / -14`), scheda `LUFS-I` con livella `±6 LU`, griglia sempre visibile (`LUFS-S`, `TRUE PK` cliccabile per azzerare solo picchi/clip, `LUFS-M`, `LRA`), meter canali con peak-hold e linea `TP RED`, colonna `S/I` con fascia verde `±LU`, nastro storico `DERIVA 60s` congelato in pausa, 4 viste responsive (incluso embedded TCP/MCP con `LUFS-I` + `TP`), cassetto impostazioni e tema Scuro/Chiaro (motore BS.1770-4, 4× True Peak e slider `1..42` invariati).
- **ZP Loudness Meter Multichannel 45.0 (ZP Misura)**: redesigned vertical-first anti-drift UI (`268×580`, usable down to `180 px`), featuring free `TARGET` + one-click `LOCK NOW` (`SEGUI QUI`), 4 quick shortcuts (`-23 / -18 / -16 / -14`), `LUFS-I` hero card with `±6 LU` spirit level, always-visible `LUFS-S` / clickable `TRUE PK` (peaks & clips reset) / `LUFS-M` / `LRA`, channel bars with floating peak-hold & `TP RED` line, `S/I` target column with green `±LU` band, 60s drift ribbon (freezes on pause), 4 responsive layouts (including TCP/MCP embedded with `LUFS-I` + `TP`), compact settings drawer, and Dark/Light themes (BS.1770-4 / 4x TP core and sliders `1..42` preserved).
- **Fissa marker negli item**: nella finestra Marker trasferisce negli item selezionati solo i marker scelti sulla timeline. I marker operativi, compresi i cue `#HSC` di Harmonic Space Carver, restano in timeline; si possono fissare anche marker senza nome.
- **Embed markers in items**: the Marker window copies only timeline markers you select into selected items. Operational markers, including Harmonic Space Carver's `#HSC` cues, stay on the timeline; unnamed markers can also be embedded.
- **ZP Magic Voice LAB 1.2.3 (ZP Voce)**: `MONITOR · DYNAMIC EQ` e `MONITOR · DYNAMIC BALANCE` ora tracciano le curve reali continue delle funzioni di trasferimento complesse (albero 2 SVF a 5 bande e split 1-pole a 3 bande), con zoom `±5 / ±12 dB` su `DYN EQ`, zoom `±6 / ±12 dB` su `DYN BAL` e barre energia/target per banda; DSP invariato.
- **ZP Magic Voice LAB 1.2.3 (ZP Voce)**: `MONITOR · DYNAMIC EQ` and `MONITOR · DYNAMIC BALANCE` now render the real continuous complex transfer-function curves (5-band 2-SVF tree and 3-band 1-pole split), with `±5 / ±12 dB` zoom on `DYN EQ`, `±6 / ±12 dB` zoom on `DYN BAL` and per-band energy/target telemetry; DSP unchanged.
- **ZP Magic Voice LAB 1.2.2 (ZP Voce)**: nel `2·DRC` i rotori `HP / LP` diventano `FREQ` (centro logaritmico in Hz con input numerico al doppio clic) e `OCT` (ampiezza in ottave `0.12–3.50`, retrocompatibili sugli slider `HP / LP` esistenti); `MONITOR · DRC` ridisegnato con le curve a campana SVF reali dinamiche (`0..-12 dB`), anteprima statica delle campane e somma complessiva.
- **ZP Magic Voice LAB 1.2.2 (ZP Voce)**: `2·DRC` replaces `HP / LP` knobs with `FREQ` (logarithmic center Hz with double-click numeric entry) and `OCT` (bandwidth in octaves `0.12–3.50`, backward-compatible with existing `HP / LP` sliders); `MONITOR · DRC` redesigned to plot the real dynamic SVF bell curves (`0..-12 dB`), static bell guides and combined response.
- **ZP Magic Voice LAB 1.2.1 (ZP Voce)**: pannelli ridisegnati con selezione modulo più leggibile e isoletta Uscita/Output; INPUT drive dritto (-12..+12 dB, auto-compensato) e soglie DRC ritarate sul parlato con spia BYPASSED cliccabile; DELTA globale lampeggiante con auto-off a 30 s e D·MOLLA esteso al delta del singolo stadio; suggerimenti su blocchi di 4 s di parlato attivo (in pausa durante DELTA/SOLO); monitor DYN EQ centrato e zoomabile (±5 dB / ±12 dB); selettore solo cromatico CHIARO/SCURO con tutti i controlli DRC sempre visibili.
- **ZP Magic Voice LAB 1.2.1 (ZP Voce)**: redesigned panels with clearer module selection and a dedicated Output island; straight auto-compensated INPUT drive (-12..+12 dB) and recalibrated DRC speech thresholds with clickable BYPASSED indicator; flashing global DELTA with 30 s auto-off plus extended spring-loaded per-stage S·DELTA audition; 4 s active-speech block suggestions (paused during DELTA/SOLO); centered zoomable DYN EQ monitor (±5 dB / ±12 dB); color-only LIGHT/DARK theme keeping all DRC controls visible.
- **ZP BrownSlope Prism 1.1 (ZP Misura)**: restyling grafico comunicativo con corridoio target verde ±1,5 dB (e alone ±3 dB), curva smussata con riempimento differenziale caldo (+Eccesso) / freddo (-Carenza), traccia Live opzionale dietro la media lunga, etichette di zona nel grafico, barre bipolari nei 4 box inferiori, livella per la pendenza residua, badge esito, griglia dB adattiva a ogni Scala e selettore tema Scuro/Chiaro (DSP passivo e parametri OSARA invariati).
- **ZP BrownSlope Prism 1.1 (ZP Misura)**: redesigned UI with a green ±1.5 dB tolerance corridor (±3 dB outer halo), smoothed curve with warm/cool differential fill against the target, optional translucent Live trace behind long averages, in-plot zone headers, bipolar zone balance bars, residual slope level, result badge, range-adaptive symmetric dB grid, and Dark/Light header theme toggle (passive DSP and OSARA parameters unchanged).

## ZP Studio Suite 2.6.7 — 2026-11-19

- **ZP Magic Voice LAB 1.2.0-lab3 (ZP Voce)**: taratura strumentale completa di Input Level (-24..0 dB auto-compensato), Dynamic EQ a 5 bande coerenti di fase (A/B/C/D), Tone EQ (A/B/C/D) + Mid Bump, Dynamic Balance (A/B), DRC con SOLO A/B/C/D a molla sui 3 rotori di banda, preset MAGIC 1, monitor per stadio, barra suggerimenti e vista parametri JSFX scorrevole. È la versione Magic Voice distribuita; ZP Magic Voice 1.2.0 senza LAB è il prototipo archiviato ed escluso dalla release.
- **ZP Magic Voice LAB 1.2.0-lab3 (ZP Voce)**: fully calibrated against the MagicFlow audio unit, including auto-compensated Input Level, five-band phase-coherent Dynamic EQ, Tone EQ and Mid Bump, multiband Dynamic Balance, spring-loaded DRC solo, preset MAGIC 1, stage monitoring and a scrollable JSFX parameter view. LAB is the distributed version; ZP Magic Voice 1.2.0 without LAB is the archived prototype and is excluded from this release.
- **Grafica JSFX interamente zoomabile su tutta la Suite**: tutti i plugin JSFX di `ZP Voce`, `ZP Master`, `ZP Misura` e `ZP Lab` scalano proporzionalmente disegni, testi e pomelli ridimensionando la finestra FX di REAPER (con DSP invariato al 100%).
- **Grafica Lua zoomabile proporzionalmente (`ZP_GfxScale.lua`)**: tutte le 24 finestre operative Lua della Suite scalano proporzionalmente controlli, grafici e testi al ridimensionamento (incluso `17 Gestore Progetto` ora ridimensionabile liberamente); `18 Project Viewer` mantiene un fattore minimo `1.0` quando agganciato (dock).
- **Proportional Lua UI zoom (`ZP_GfxScale.lua`)**: all 24 operative Suite Lua windows scale controls, graphics and text proportionally when resized (including `17 Project Manager`, now freely resizable); `18 Project Viewer` keeps a `1.0` minimum scale when docked.
- **Project Viewer ridisegnato, Actor/Note e icone toolbar**: nel Project Viewer la colonna `Tipo` resta fissa a sinistra mentre `Nome`, `Start`, `End` e `Durata` scorrono orizzontalmente con colonne auto-adattate e ridimensionabili da separatori (doppio clic per tornare ad auto), pulsanti in griglia 3×2 senza il vecchio pulsante `Scroll`, e `?` sempre leggibile anche in dock stretto; corretta la spaziatura di `07 Note Personaggio` e aggiunta la copia automatica delle icone toolbar PNG mancanti (`32 Installa Toolbar ZP` e `sincronizza_reaper.sh`).
- **Project Viewer redesign, Character Notes & toolbar icons**: in Project Viewer the `Type` column stays pinned on the left while `Nome`, `Start`, `End` and `Durata` scroll horizontally with auto-fit, header-resizable columns (double-click to reset to auto), a 3×2 tool grid without the old `Scroll` button, and an overlap-free `?` button down to narrow docked panels; fixed text spacing in `07 Character Notes` and added automatic copying of missing PNG toolbar icons (`32 Install ZP Toolbar` and `sincronizza_reaper.sh`).

- **Project Viewer e Gestore Progetto**: controlli e icone più grandi, funzioni spiegate al passaggio del puntatore; Spazio fra item distingue item adiacenti da item sovrapposti e offre ripple globale o spostamento dei soli selezionati. Play/Stop del Project Viewer usano i pulsanti tondi del SOLO Recorder; nel Gestore Progetto Sel, Play, Stop e Salva hanno icona con didascalia leggibile anche con Sel attivo. Nel SOLO Recorder le frecce navigano marker, regioni e item con selettori a icone.
- **Project Viewer and Project Manager**: larger controls and icons, hover explanations; Space between items distinguishes adjacent from overlapping items and offers global ripple or selected-only movement. Project Viewer Play/Stop use the SOLO Recorder's round buttons; Project Manager Sel, Play, Stop, and Save use icons with captions that remain readable when Sel is active. SOLO Recorder arrows navigate markers, regions, and items using icon selectors.

- **ZP Render & Copy con più progetti in tab**: stato, messaggi e «Mostra in consegna» seguono il progetto in primo piano; un render in coda viene attribuito al progetto che lo ha accodato. Aiuto, conferma di Sincronizza (con progetto, consegna ed elenco dei file) e richiesta della cartella compaiono dentro la finestra.
- **ZP Render & Copy: stesso nome in consegna**: quando in consegna c'è già un file con lo stesso nome si può sostituirlo o tenere tutte le versioni; il nuovo viene copiato come «nome (vers 2)», «(vers 3)»… Un pulsante lo decide per la copia automatica, «Sincronizza ora» lo chiede.
- **ZP Render & Copy: same name in delivery**: when the delivery folder already has a file with the same name you can replace it or keep every version; the new one is copied as "name (vers 2)", "(vers 3)"… A button decides it for automatic copying, "Sync now" asks.
- **ZP Render & Copy with several project tabs**: status, messages and "Show in delivery" follow the project in front; a queued render is attributed to the project that queued it. Help, the Sync confirmation (with project, delivery folder and file list) and the folder request are shown inside the window.
- **Language pack italiano per REAPER 7.86**: in italiano anche le finestre dei pacchetti `.ReaperPkg`, la cartella FX nascosti, il Learn MIDI/OSC di track e send, le nuove opzioni di render e i take marker con durata. Resta completo anche su REAPER 7.82–7.85.
- **Italian language pack for REAPER 7.86**: package (`.ReaperPkg`) windows, the Hidden FX folder, MIDI/OSC Learn for tracks and sends, the new render options and take markers with length are now in Italian. It stays complete on REAPER 7.82–7.85 too.
- **Collega marker (28) e SRT dall'audio (31) con REAPER 7.86**: i marker dell'item portano la durata della battuta e l'SRT riscritto dai marker ha la fine esatta. Con REAPER precedenti il comportamento non cambia.
- **Collega marker (28) and SRT from audio (31) with REAPER 7.86**: item markers carry the cue length and the SRT rewritten from markers has the exact end time. Nothing changes on earlier REAPER versions.
- **Gobbi: unisci battute**: clic destro sul testo → «Unisci con la battuta successiva» o «Unisci le battute selezionate in timeline». Resta il primo item con i testi in fila e la durata fino alla fine dell'ultimo; promemoria e parole evidenziate seguono il testo. Nuova azione **38 ZP Unisci Battute** per farlo sugli item selezionati senza aprire il Gobbo.
- **Teleprompters: join cues**: right-click the text → "Join with the next cue" or "Join the cues selected in the timeline". The first item stays with the texts in a row and its length reaching the end of the last one; reminders and highlighted words follow the text. New action **38 ZP Unisci Battute** does it on the selected items without opening the Teleprompter.
- **ZP Consolidate (37): Numera item**: terzo comando della finestra; rinomina gli item delle tracce selezionate con nome della traccia e numero progressivo, nell'ordine in cui stanno sulla traccia.
- **ZP Consolidate (37): Number items**: third command in the window; renames the items on the selected tracks with the track name and a running number, in track order.
- **Copione in Excel (01, 05, 06)**: dove si sceglie l'SRT/VTT si può scegliere un `.xlsx` con i tempi. Colonne riconosciute dalle intestazioni, battute come `PERSONAGGIO: testo` con la reazione in coda, fine stimata dal successivo inizio; accanto all'Excel resta l'SRT. Con più fogli adatti o più colonne di testo (una per lingua) chiede quale importare. Stesse regole di SRT Tools (26). Nel testo libero dei Gobbi, Carica file… accetta lo stesso `.xlsx` (una battuta per riga). Il menu ZP SRT indica dove si sceglie l'Excel.
- **Importa Video + SRT (01)**: l'importazione registra l'SRT nel progetto senza fermarsi.
- **Excel script (01, 05, 06)**: wherever an SRT/VTT is requested you can pick an `.xlsx` with timecodes. Columns recognised from headers, cues as `CHARACTER: text` with the reaction appended, end estimated from the next start; the SRT is written next to the Excel file. With several suitable sheets or several text columns (one per language) it asks which one to import. Same rules as SRT Tools (26). In the prompters' free text, Load file… accepts the same `.xlsx` (one cue per line). The ZP SRT menu shows where the Excel file is chosen.
- **VTT e reazioni**: la voce `<v Nome>` di un WebVTT diventa `Nome: testo`; i tag di formato spariscono, le reazioni fra parentesi angolari (`<sospira>`) restano nel testo delle battute.
- **VTT and reactions**: a WebVTT `<v Name>` voice becomes `Name: text`; formatting tags are removed, reactions in angle brackets (`<sospira>`) stay in the cue text.
- **ZP BrownSlope Prism 1.0 (ZP Misura)**: analizzatore passivo della pendenza brown. Lo spettro è compensato di 4,5 dB per ottava, con riferimenti a -18 e -24 LUFS, scarto per zona, pendenza residua ed esito Pareggiato / Quasi / No; Calibra lega il riferimento a un proprio file, la vista JSFX espone le letture a OSARA. Il ? apre la sezione nella guida della Suite.
- **ZP BrownSlope Prism 1.0 (ZP Misura)**: passive brown-slope analyzer. The spectrum is compensated by 4.5 dB per octave, with -18 and -24 LUFS references, deviation per zone, residual slope and a Matched / Close / No result; Calibrate ties the reference to your own file, the JSFX view exposes the readings to OSARA. The ? opens its section in the Suite guide.
- **ZP Consolidate (37)**: raccoglie in Media le sorgenti file dei take e gli SRT/VTT registrati nel progetto, preserva montaggio e originali, e gestisce le collisioni scegliendo sovrascrittura o rinomina. Aggiunti modulo SRT condiviso, icona e pulsante toolbar.
- **Benvenuto (33)**: scroll della lista smussato e limitato prima del disegno per evitare salti dovuti ai delta rapidi/inerziali della rotella.
- **SRT di progetto**: trascrizioni e traduzioni sono copiate/registrate in Media e referenziate nel file RPP.
- **ZP Speech su Windows (sperimentale)**: Trascrivi e Traduci (29) girano in background anche su Windows (PowerShell), con elenco modelli via `curl.exe`; il Benvenuto (33) installa ZP Speech con PowerShell e l'installatore si ferma con un errore se un passo non riesce. ZP Remote nel Benvenuto dice che per ora funziona solo su macOS.
- **ZP Speech on Windows (experimental)**: Transcribe and Translate (29) run in the background on Windows too (PowerShell), with the model list read through `curl.exe`; Welcome (33) installs ZP Speech with PowerShell and the installer stops with an error if a step fails. ZP Remote in Welcome says it only works on macOS for now.
- **Language pack italiano e Render Queue**: il suffisso `(delay %ds)` e le voci `sel_regions`/`sel_markers` restano in inglese, come le riconosce REAPER; l'import multicanale rispetta l'ordine degli argomenti. `controlla_langpack.py` verifica qualsiasi pack, anche di terzi.
- **ZP Crea Regioni Export (17)**: riconosce la finestra di render anche con REAPER localizzato.

- Gobbi: importazione DOCX/ODT/RTF/TXT, incolla pulito, editor con scroll/Undo e durata temporizzata opzionale; controlli ZP_UI, progresso e riaggancio rapido. Guide IT/EN aggiornate. Pause effettive con Shift+Invio, promemoria tramite marker e divisione alla parola selezionata con conservazione del testo rimanente. Verifiche automatiche superate; collaudo del Gobbo confermato da Paolo il 10 novembre 2026.

### Beta in questa versione / Beta in this release

- **ZP Clean & Paint (BETA) 1.0.1**: ReaPack distribuisce le action REAPER; il motore AI ZP Voice Model Lab resta esterno e in sviluppo.
- **ZP Montaggio Parlato (BETA) 0.1.0**: richiede ZP Studio Suite e ZP Speech dal 33 Benvenuto; collaudo corrente su macOS.
- **ZP BrownSlope Dynamic Guard (BETA) 0.5-assist-dev** e **ZP Click & Attack Softener (BETA) 0.1**: pacchetti ZP Lab per prove su sessioni e copie di lavoro.

- **ZP Clean & Paint (BETA) 1.0.1**: ReaPack ships the REAPER actions; the ZP Voice Model Lab AI engine remains external and in development.
- **ZP Montaggio Parlato (BETA) 0.1.0**: requires ZP Studio Suite and ZP Speech from 33 Welcome; currently tested on macOS.
- **ZP BrownSlope Dynamic Guard (BETA) 0.5-assist-dev** and **ZP Click & Attack Softener (BETA) 0.1**: ZP Lab packages for testing on sessions and working copies.

ZP Speech Engine resta un runtime separato installato dal 33 Benvenuto; il supporto Windows/Linux è sperimentale. / ZP Speech Engine remains a separate runtime installed from 33 Welcome; Windows/Linux support is experimental.

Le versioni dei singoli effetti sono indipendenti: le trovi nell'intestazione di
ciascun file e nel gestore pacchetti. Questo file registra la storia della Suite
nel suo insieme.

## ZP Studio Suite 2.6.6 — 2026-11-04

- **ZP Render & Copy** estende la copia automatica e Sincronizza ora a Windows (con js_ReaScriptAPI) e Linux (con `find` e `stat`). Mostra in consegna apre il gestore file del sistema.
- **ZP Render & Copy** supports automatic copying and Sync now on Windows (with js_ReaScriptAPI) and Linux (with `find` and `stat`). Show in delivery opens the system file manager.

### Non incluso in questa versione

ZP Montaggio Parlato, ZP BrownSlope Dynamic Guard, ZP BrownSlope Prism e ZP Speech Engine sono in lavorazione.

## ZP Studio Suite 2.6.5 — 2026-11-03

- **Guida del Solo Recorder**: chiarisce che i pacchetti preparati con ZP Remote sono destinati a Dubbertools e distingue questa consegna dai comandi di registrazione del SOLO Web Remote.
- **Solo Recorder guide**: clarifies that packages prepared with ZP Remote are intended for Dubbertools and distinguishes package delivery from the SOLO Web Remote recording controls.

## ZP Studio Suite 2.6.4 — 2026-11-03

- **Report minuti voce (19)**: esporta in CSV lo storico HTML già presente nel progetto. “Salva questa sessione” crea anche un CSV separato, con progetto, data e modalità nel nome; “Aggiungi allo storico” aggiorna il CSV cumulativo insieme all'HTML.

- **ZP Render & Copy**: copia il risultato del render nella cartella di consegna. La finestra e la toolbar hanno un’icona dedicata e il pulsante di aiuto spiega come impostare le cartelle.
- **ZP Remote**: da REAPER si può creare il pacchetto di una regione per Dubbertools e importare le registrazioni ricevute. Il telecomando web del Solo Recorder ha un collegamento a dubbertools.com.
- **ZP Colori e Gestore Progetto**: selettori per item, tracce, marker e regioni, modalità Auto per la selezione mista e colore effettivo delle regioni nel Gestore.
- **Harmonic Space Carver 2.6.8 e Cue Navigator 1.13**: i cue seguono l’identità dell’item anche se cambia il take. Il navigatore distingue un riferimento mancante da un cue spostato e offre il comando Adotta posizione.
- **SRT Tools**: aggiornato lo strumento offline per preparare e convertire i sottotitoli.
- **Pre-roll**: il comando PRE nel Recorder e nel telecomando web aggiorna la spia della toolbar nativa di REAPER, mantenendo sincronizzato lo stato visivo.
- **Gobbo verticale**: i colori speaker si applicano anche selezionando item della traccia voce o note personaggio associate.
- **Italiano (ZP)**: la voce principale del menu resta *Help* per mantenere attiva la ricerca nativa dei menu su macOS; le voci interne restano tradotte.

### Non incluso in questa versione

ZP Montaggio Parlato, ZP BrownSlope Dynamic Guard, ZP BrownSlope Prism e ZP Speech Engine sono in lavorazione.

## ZP Studio Suite 2.6.3 — 2026-10-19

- **Lingua di REAPER, correzione**: nel 33 Benvenuto la scelta della lingua non aveva effetto. La 2.6.2
  installava bene *Italiano (ZP)* e lo elencava, ma il comando usato per scrivere la scelta
  (`SNM_SetStringConfigVar`) con REAPER aperto restituisce *falso*. Ora la scelta resta in attesa e
  **Riavvia ora** chiude REAPER, scrive la riga `langpack=` in `reaper.ini` e lo riapre.
- **Importa un language pack...**: dal menu della lingua copi nella cartella LangPack un tuo file
  `.ReaperLangPack` (si controlla che sia un language pack) e lo selezioni subito.
- **Cerca altri language pack in ReaPack...**: apre ReaPack sui language pack disponibili.
- Il menu è per macOS; su Windows e Linux il pulsante apre le Preferenze di REAPER (Language).
- **Traduzione italiana di REAPER, molto più completa**: *Italiano (ZP)* passa da circa 7.500 a circa
  17.700 voci tradotte su REAPER 7.82. Menu principali e contestuali e finestre di dialogo sono tradotti
  al 100%, come le spiegazioni delle Preferenze. Le Action restano in inglese, così la ricerca per nome
  nella Action List continua a funzionare; i termini tecnici (item, take, marker, region, track, render,
  FX, send, ...) restano in inglese. Per usare la nuova traduzione riavvia REAPER dopo l'aggiornamento.

### Non incluso in questa versione

36 ZP Montaggio Parlato (prototipo), ZP BrownSlope Dynamic Guard, ZP BrownSlope Prism e ZP Speech Engine.
Sono in lavorazione e non fanno parte del pacchetto ReaPack.

## ZP Studio Suite 2.6.2 — 2026-10-18

- **Traduzione italiana di REAPER, correzione**: con la 2.6.1 il language pack *Italiano (ZP)* veniva
  installato in una sottocartella di LangPack e REAPER non lo vedeva nell'elenco delle lingue. Ora va
  direttamente in LangPack. Dopo l'aggiornamento scegli *Italiano (ZP)* nel 33 Benvenuto, alla voce
  *Lingua di REAPER*.
- **Gestore Progetto (17)**: **Salva** applica alle rispettive regioni i nomi ancora in bozza, crea solo
  le regioni mancanti per quei nomi e salva il progetto. Chiudendo con nomi in bozza, **Sì** li applica
  e salva prima di uscire; **No** torna al Gestore.

### Non incluso in questa versione

36 ZP Montaggio Parlato (prototipo), ZP BrownSlope Dynamic Guard, ZP BrownSlope Prism e ZP Speech Engine.
Sono in lavorazione e non fanno parte del pacchetto ReaPack.

## ZP Studio Suite 2.6.1 — 2026-10-18

- **Traduzione italiana di REAPER**: il language pack *Italiano (ZP)* viene installato insieme alla Suite
  nella cartella LangPack di REAPER. Si sceglie dalle preferenze di REAPER, alla voce della lingua. Sono
  tradotti menu, finestre di dialogo e aiuto delle Preferenze; le Action restano in inglese.

## ZP Studio Suite 2.6.0 — 2026-10-17

- **Guide nella lingua della Suite**: anche *00 Apri Help* apre la guida italiana o inglese scelta nel
  33 Benvenuto. README su GitHub in inglese (`README.md`) e in italiano (`README.it.md`).
- **SOLO Recorder**: il pulsantino **S** sul REC mette in solo la traccia di registrazione (in Telecomando
  la prima traccia armata); il picco del meter IN è una barretta azzurra.
- **Gobbi**: il pannello note mostra prima le note aperte, poi quelle concluse; doppio clic nello spazio
  libero o tasto destro aggiunge una nota; ogni risultato di *Cerca* ha il pulsante **Vai →**.
- **Gestore Progetto (17)**: una barra in fondo alla finestra spiega il pulsante su cui passi con il mouse.
- **Voice Cleaner (22)**: pannello *Revisione manuale* per ascoltare e decidere ogni segmento (Play, zoom,
  Approva o Scarta segmento, Approva tutti); **ASCOLTA**, **PULISCI MARKER** e una memoria della
  calibrazione con nome. APPLICA usa solo i segmenti approvati.
- **Report minuti voce (19)** e **Chain Builder (23)**: gli esiti restano nella loro finestra.
- **SRT Tools (26)**: legge i file Excel XLS e XLSX, con scelta di foglio e colonne (inizio, fine, testo,
  personaggio, reazione). Include SheetJS (Apache-2.0, testo della licenza accanto alla pagina).
- **Plugin**: Harmonic Space Carver 2.6.7 con Cue Navigator 1.12 (un clic sull'avviso rosso
  *CUE FUORI POSTO* riporta tutti i cue sulla loro voce) e ZP BUS Chain 1.3.1 (interruttori Brown Guard
  DYN ed EQ separati). Guide aggiornate per Carver, Voice Cleaner, BUS Chain e Gestore Progetto.

## ZP Studio Suite 2.5.0 — 2026-10-10

- **ZP Colori (35)**: finestrella *clicca e colora*. Scegli il modo (**Item**, **Traccia** o **Tutto**),
  selezioni e clicchi uno dei 20 colori; **Togli colore** li toglie. Si apre e si chiude dal pulsante
  tavolozza della toolbar ZP e si può agganciare. La stessa cosa come toolbar sempre a vista,
  facoltativa, si installa dal 33 Benvenuto.
- **ZP Set Comandi (34)**: set di scorciatoie da tastiera (montaggio video, abitudini Pro Tools o Logic,
  i tuoi). Ogni set ha la sua pagina con tutte le scorciatoie scritte per esteso; Salva, Importa,
  Rinomina, Archivia; prima di ogni cambio i tasti in uso vanno nel set *Backup automatico*. Cambia solo
  i tasti (script e toolbar restano) e vale dal riavvio di REAPER. *Spiega con l'AI*, a richiesta,
  descrive un set in poche righe.
- **Inglese**: nel 33 Benvenuto scegli la lingua della Suite (italiano / English) e, a parte, quella di
  REAPER (originale o un language pack installato). Finestre, messaggi e guide in inglese; la pagina web
  del SOLO ha IT / EN.
- **Funzioni AI** (Traduci, Spiega con l'AI) con l'agente che hai sul Mac: Codex, Claude, Qwen, OpenCode o
  Ollama in locale (niente esce dal Mac). Prima di partire dicono quale agente usano e dove va il testo.
  Serve ZP Speech aggiornato (`bash speech-engine/install_macos.sh`).
- Firma **Lato Cardioide** nelle finestre e nelle guide; toolbar ZP con i pulsanti *ZP Colori* e
  *Set Comandi*; il Benvenuto scorre quando la finestra è bassa.
- **Plugin** (BUS Chain 1.3.0, Harmonic Space Carver 2.6.6, Spoken Finish 3.10.0, Stagekeeper 2.5.1,
  Subliminal Presence Layer 3.2.2, Voiceover Unified Chain 4.1.7, Master Pro 2.46, Reference Tone Mirror
  EQ 0.063, Loudness Meter 44.0.2, Oscilloscope 12.1, Voice-Music Probe 1.2): il pulsante **?** apre la
  sezione del plugin nella guida (con il Cue Navigator 1.11 acceso); testi di aiuto in italiano o
  inglese secondo la lingua della Suite; descrizione bilingue con i crediti Lato Cardioide.

## ZP Studio Suite 2.4.1 — 2026-10-08

- Guida della toolbar con le icone nuove, l'installazione con *32 Installa* e riavvio di REAPER, e il
  bordo che diventa verde acqua quando lo strumento è aperto (un secondo clic lo chiude).
- Menu OSARA del Gobbo con gli stessi nomi della barra comandi (Parola per parola, Scorrimento
  continuo, Conto alla rovescia, Pannello note, Tracce visibili, Nuova battuta); i numeri delle voci
  restano quelli di prima.

## ZP Studio Suite 2.4.0 — 2026-10-08

- 29 ZP Trascrizione: tendine **Modello** e **Lingua** (italiano, inglese, francese, tedesco,
  spagnolo, portoghese, cinese, giapponese, coreano, russo, automatica, o *Altra…* per qualsiasi
  codice; avviso se Parakeet non conosce la lingua). La riga della tappa dice «5 selezionati: 3 da
  trascrivere, 2 già fatti». Abbina con più item non apre il Finder e salta quelli già abbinati.
  Ogni file ricorda con che modello e lingua è stato trascritto.
- Trascrivi, Ritrascrivi e Traduci lavorano **in background**: chiudere la finestra non li ferma, il
  titolo mostra l'avanzamento e alla fine arriva una notifica di macOS. Un file che non riesce non
  ferma gli altri.
- **Traduci** (facoltativo): l'SRT accanto al file viene tradotto da un agente AI con il tuo login
  (Codex) in `Nome.it.srt`, con gli stessi tempi; se l'agente cambia le battute il file non viene
  scritto. Nel Gobbo ogni traduzione è un flusso in più («Kevin · IT») agganciato agli stessi marker:
  segue i tagli e la ricerca trova le frasi tradotte. Serve ZP Speech aggiornato
  (`bash speech-engine/install_macos.sh`).
- Toolbar ZP con icone nuove: il disegno resta uguale e il bordo diventa verde acqua quando lo
  strumento è aperto; un secondo clic sull'icona chiude la finestra. Si applica con 32 Installa.
- SOLO Recorder: i comandi REAPER anche in Mini; cambiando vista la finestra cresce verso il basso.
- SOLO Web: timeline con regioni, marker e take della traccia armata; un tocco porta il cursore,
  zoom con − + *Tutto*, rotella, pizzico o trascinamento, e la vista segue la testina.

## ZP Studio Suite 2.3.7 — 2026-10-08

- Gobbo, ricerca: trova le parole dall'inizio (`ved` trova *vedere*), senza badare a maiuscole e
  accenti; tra virgolette cerca la parola esatta. Sotto il campo c'e' l'elenco dei risultati in
  ordine di timeline, con timecode e file audio di ogni battuta; clic, frecce, `<` e `>` portano
  alla battuta.
- Gobbo verticale, Sostituisci: cambia solo parole intere e gli accenti contano (`è` non tocca
  *e*). Un clic mostra la parola, il secondo la cambia e resta li'; Tutti chiede conferma e si
  annulla con un solo Undo.
- Gobbo verticale: Modifica battuta si apre sotto Cerca e la battuta in modifica e' segnata nel
  copione. Il pannello note elenca tutte le note ed e' scorrevole: clic porta la timeline, doppio
  clic modifica, bollino OK per segnarle fatte o riaprirle, x a sinistra per cancellarle. In
  Modifica la rotella scorre il testo. La barra comandi e' divisa in blocchi, con caselle e il
  flusso testi a tendina.
- Gobbo orizzontale: flusso testi a tendina.

## ZP Harmonic Space Carver 2.6.5, Cue Navigator 1.10, ZP Studio Suite 2.3.6 — 2026-10-07

### ZP Harmonic Space Carver 2.6.5
- ELIMINA nella fila dei cue: clic su un punto per sceglierlo, Cmd/Ctrl+clic per aggiungerne
  altri, Shift+clic per un intervallo; toglie i cue e i loro marker `#HSC`, UNDO li rimette.
- GUI Advanced in tre colonne: VOCE con LIVELLI sotto, CARVER con BANDE, VCA con il meter VCA,
  GLUE e USCITA. Min Duck (giallo) e Max Duck (arancio) stanno accanto al meter VCA, collegati
  alle loro linee; il pomello Glue sta con il suo meter.

### Cue Navigator 1.10
- Ogni progetto aperto in una scheda tiene i suoi cue e i suoi marker `#HSC`: al cambio di scheda
  l'helper rilegge subito i Carver di quel progetto.

### ZP Studio Suite 2.3.6
- Marker degli item protetti: trascinando sopra un take marker prendi l'item, Shift+trascina sposta
  il marker. Lo imposta 32 Installa; nel 33 Benvenuto la riga "Marker degli item" ha Proteggi e
  Ripristina standard.

## ZP Studio Suite 2.0.0 — 2026-10-04

- Trascrizione con whisper (29 ZP Trascrizione), gobbo che segue i tagli, Ritrascrivi.
- ZP SRT (30), SRT dall'audio (31), Info item SRT e Esporta SRT rinnovati.
- Marker: 04 e 14 uniti; marker di servizio mai trattati come testo.
- 32 Installa toolbar ed effetti (toolbar, catene di effetti, preset).
- SOLO Recorder: pulsantiera a zone, pomelli, guida rapida, Telecomando, lucchetto REC.
- Chain Builder: BUS Chain con preset Voiceover, Master Pro con Flat -19.
- Report minuti voce: report della sola sessione.
- ZP Stagekeeper Dialogue Director 2.5.0 (la 2.3.1 resta come riferimento in
  `gobbo_ricerca_battuta/backup/`).

## ZP Harmonic Space Carver 2.6.4, ZP Studio Suite 2.0.1 — 2026-10-05

### ZP Harmonic Space Carver 2.6.4 (con Cue Navigator 1.9 e azioni ZP HSC)
- GUI nell'ordine del segnale (Voce, Carver, VCA, Bande, VCA/Glue, Uscita, Livelli), un solo motore:
  Simple mostra i controlli principali dell'Advanced; SCORE / FLAT / VOCAL sono punti di partenza.
- Sidechain da tre fonti (3/4, 5/6, 7/8) legate al routing vero, con spia per fonte.
- Anticipo (lookahead compensato), Knee, Apertura del cue, Min/Max Duck a forbice; vista DOCK.
- Quick return cues: funzionano in ogni vista e a finestra chiusa; marker `#HSC` sul righello
  (lane 4) che si spostano liberamente ma si aggiungono e tolgono solo dal Carver; ogni cue e'
  ancorato alla voce che ha sotto e diventa rosso se la voce si sposta (RIALLINEA / TIENI QUI).
- Helper "ZP Harmonic Space Carver Cue Navigator" (da avviare all'apertura di REAPER) e azioni
  da tastiera: Cue aggiungi o togli, Successivo, Precedente, Annulla, Riallinea, Mostra tracce voce.
- Ogni Carver ha un numero unico: piu' progetti aperti in schede non si mescolano.
- Preascolto segnalato e spento alla riapertura; livelli sempre sull'uscita vera.
- Dettagli e revisione: `docs/PROGETTO_Harmonic_Carver_2.6_cue_marker.md`, `docs/DEBUG_Harmonic_Carver_2.6.md`.

### ZP Studio Suite 2.0.1
- 17 Gestore Progetto: niente regioni da item di testo o vuoti; pulsanti Video e No muti.
- 19 Report minuti voce: pulsante No muti.

## Non rilasciato

### Corretto
- Quattro effetti non entravano nell'indice ReaPack: Reference Tone Mirror EQ Pro,
  Oscilloscope 16ch, Harmonic Space Carver e Subliminal Presence Layer White.
  Causa: `reapack-index` riconosce come tag anche `author:` e `version:` scritti
  senza chiocciola nell'intestazione JSFX storica, e le righe di commento indentate
  che li seguivano li rendevano multilinea. Entrambi i tag devono stare su una riga
  sola. Le vecchie righe sono state rinominate in `// Autore:` e `// Versione:`:
  l'informazione resta leggibile, il conflitto sparisce.
- Stessa correzione applicata anche a Loudness Meter e Stagekeeper, che passavano
  per caso ma avevano lo stesso difetto latente.

### Aggiunto
- Repository unico per gli 11 effetti della Suite, in tre categorie: ZP Voce, ZP Master, ZP Misura.
- `LICENSE` (GPLv3) e `NOTICE.md` con la catena di attribuzioni del DSP di terzi.

### Corretto
- **ZP Voice-Music Probe**: la copia in uso nella cartella di lavoro era precedente a
  quella distribuita e non conteneva il fix *v1.1 Role Switch* (cambio ruolo
  VOICE/MUSIC a trasporto fermo, da GUI e da Chain Builder). Eletta come fonte la
  versione corretta.

### Aggiunto
- Pipeline ReaPack: `.reapack-index.conf` e due workflow GitHub Actions.
  `check` valida i pacchetti a ogni push e su ogni pull request; `deploy` rigenera
  `index.xml` a ogni push su master e lo ricommitta da solo.
- `index.xml` iniziale con il nome "ZP Suite" — e' il nome che ReaPack mostra.
  Da qui in avanti il file lo mantiene la CI: non va modificato a mano.

### Modificato
- Rinominati sette file per togliere la versione dal nome: con ReaPack il nome del file
  e' l'identita' del pacchetto e non puo' piu' cambiare dopo la pubblicazione. La versione
  vive ora solo in `@version` e nella riga `desc:`, dove puo' crescere liberamente.
  Rinomina fatta con `git mv`: la storia dei file e' conservata.
- `ZP Subliminal Presence Layer White` mantiene "White": e' un descrittore del tipo di
  layer, non un numero di versione.

### Compatibilita'
- I file gia' installati in `Effects/ZP_Paolo Balestri JSFX/` restano dove sono e non
  vengono toccati: i progetti REAPER esistenti continuano a trovarli. I pacchetti ReaPack
  si installano in una cartella propria, quindi le due serie convivono senza collisioni.

### Note
- Import iniziale con i nomi file storici. La rinomina che toglie la versione dal nome
  avviene nel passo successivo, con `git mv`, prima della prima pubblicazione.

## ZP Studio Suite 2.1.0 — 2026-10-06

### SOLO Recorder
- Testata a icone uguale in Mini, Compact ed Expanded: salva (staccato), annulla, ripeti; Sessione SOLO o
  Telecomando; regioni take, effetti, video; viste; toolbar; nascondi REAPER; versione web; guida; puntina.
- Meter IN dall'ingresso vero della scheda e RIT dal master, in dB da -60 a 0, con picco trattenuto.
- Pre-roll di REAPER: PRE sul bordo del REC lo accende, i secondi (1-5) stanno nella toolbar.
- PAUSA fra STOP e PLAY, anche durante il REC; PLAY durante il REC mette in pausa come in REAPER.
- Marker con la bandierina e il nome scritto in una casella del pannello (Invio).
- In Telecomando la traccia da armare si sceglie dal menu dell'ingresso; navigatore anche in Compact.

### SOLO Web (prototipo)
- Il SOLO nel browser (Mac, iPad, telefono) attraverso l'interfaccia web di REAPER: trasporto con pausa,
  pre-roll, meter, marker, salva/annulla/ripeti. Si apre dal globo in testata del SOLO, che prepara la
  pagina e accende il motore `ZP_SOLO_Web_Motore`.

## ZP Studio Suite 2.2.0 — 2026-10-06

- 33 Benvenuto: controllo dell'installazione. Una spia per pezzo (toolbar ed effetti, Cue Navigator del
  Harmonic Space Carver e il suo avvio con REAPER, ZP Speech, SWS, js_ReaScriptAPI, OSARA, interfaccia web)
  e il pulsante che lo sistema. Si apre da solo la prima volta che si usa uno strumento ZP; poi dall'Action
  List o dall'help.

## ZP Studio Suite 2.3.1 — 2026-10-06

- 32 Installa toolbar: toolbar ZP con le icone di REAPER (piu' due icone ZP nello stesso stile, anche per
  schermi Retina), i pulsanti della finestra video (anche dai progetti
  in sottofondo) e l'ordine della toolbar di lavoro.
- 33 Benvenuto: ZP Speech si installa con un clic (il Terminale scarica da GitHub e installa); se mancano
  Python 3.11+ o MacWhisper la riga lo dice e porta a scaricarli.

## ZP Studio Suite 2.3.2 — 2026-10-06

- 33 Benvenuto: la toolbar ZP in tre momenti chiari: da installare (Installa), da importare (Importa apre
  Customize toolbars e copia il percorso del file), pronta (dice in quale toolbar e' e la apre).
- 32 Installa toolbar: consiglia una Floating toolbar fra 1 e 16, quelle del menu View > Toolbars.

## ZP Studio Suite 2.3.4 — 2026-10-06

- 32 Installa toolbar: la toolbar "ZP Studio Suite" entra direttamente fra le toolbar di REAPER, col suo nome
  (Switch toolbar o View > Toolbars, dopo un riavvio): nella toolbar che si chiama gia' cosi', altrimenti nella
  prima libera fra 1 e 16. Le altre toolbar restano come sono; accanto a reaper-menu.ini resta un backup.
- 33 Benvenuto: toolbar da installare, da riavviare, pronta (dice in quale toolbar e' e la apre).

## ZP Studio Suite 2.3.5 — 2026-10-06

- SOLO Web: pulsante Condividi con il link per aprire il SOLO da un altro dispositivo della stessa rete (iPad,
  telefono, altro computer), con Copia e QR; Wi-Fi e cavo insieme. Il globo del SOLO Recorder copia il link.
