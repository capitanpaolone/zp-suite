# ZP Shared Bus v3 — Specifica Architetturale (`gmem=ZPVoiceoverSharedBus`)

Aggiornata: 2026-11-23  
Stato: **Implementato nella candidata `zp-suite-2.6.9` (Shared Bus v3.1 + ZP Telemetry Engine)**  
Compatibilità: Retrocompatibile al 100% con **Shared Bus v2.20** (`gmem[0..606]`) e **HSC / Ponte Help** (`gmem[3800..]`).

---

## 1. Obiettivo

Superare i tre limiti storici dello Shared Bus v2.20 (slot unici fissi con collisioni su più tracce, plugin invisibili come Magic Voice LAB/Stagekeeper/Carver/Lab, assenza di posizione nella catena) permettendo a **ZP Master Pro** di leggere organicamente **chi sta facendo cosa a monte** (canali voce, bus voce, bus musica, master), ordinato dalla sorgente al master, con:

- **Zero nuovi slider pubblici** e **zero modifiche al DSP (`@sample`)**.
- **Identità automatica dell'istanza** tramite `get_host_placement(chain_pos, flags)` in EEL2 (`track_idx`, `chain_pos`, `host_flags`).
- **Scadenza automatica dei nodi rimossi o in bypass host (`2.5 s`)**, così un plugin disattivato da REAPER sparisce senza lasciare dati fantasma.
- **Arricchimento opzionale via `ZP Harmonic Space Carver Cue Navigator.lua`**: nomi reali delle tracce, stato mute/solo/folder/ruolo (`VO_BUS`, `MUSIC_BUS`) e **click-per-aprire** la finestra del plugin a monte direttamente da Master Pro. In assenza dell'helper, Master Pro degrada pulitamente a `Tr N · FX M`.

---

## 2. Mappa indirizzi `gmem=ZPVoiceoverSharedBus`

| Intervallo `gmem` | Dominio | Note |
|---|---|---|
| `0..606` | Shared Bus v2.20 (legacy) | Preservato intatto per retrocompatibilità |
| `410..425` | **Master Reference Block (v3.1)** | Stato Tone Guard (`tone_on`, `tone_dyn_on`, `tone_slope`, `tone_gain1..4`), target/misure Output di `ZP Master Pro` |
| `1000..1015` | **Shared Bus v3 Header & Open-FX Mailbox** | Magic, versione, Track Directory heartbeat, comando apri-FX |
| `1024..3071` | **Shared Bus v3 Tabella Nodi Attivi** | 64 slot × 32 float (max 64 istanze simultanee) |
| `3072..3583` | **Shared Bus v3 Track Directory (opzionale)** | 64 tracce × 8 float pubblicati da Cue Navigator (o da Telemetry Engine se Cue Navigator è spento) |
| `3600..3663` | **ZP Telemetry Engine Summary (v3.1)** | Riassunto verdetti, metro di riferimento attivo, scostamenti medi e segnalazione principale |
| `3670..3683` | **Monitor FX Audition Noise Bridge (v3.1)** | Telecomando da `ZP Master Pro` (`3670..3676`, magic `905367`, `gmem[3674]` SNR `-24..+6 dB`) e heartbeat/stato da `ZP Audition Noise Monitor` in Monitor FX (`3678..3683`, magic `905368`) |
| `3800..3899` | HSC Carver Command Mailbox | Invariato |
| `3900..3984` | Ponte Help/Lingua + HSC Pref Bank | Invariato |
| `4032..8378476` | HSC Carver slot e maschere cue | Invariato |

---

## 3. Header & Open-FX Mailbox (`gmem[1000..1015]`)

| Indice | Nome | Tipo / Semantica | Scrittore |
|---|---|---|---|
| `1000` | `magic_v3` | `905300` | Qualsiasi nodo v3 |
| `1001` | `version_v3` | `300` (`v3.00`) | Qualsiasi nodo v3 |
| `1002` | `max_nodes` | `64` | Qualsiasi nodo v3 |
| `1003` | `node_stride` | `32` | Qualsiasi nodo v3 |
| `1004` | `dir_heartbeat` | Contatore incrementale (`> 0` se attivo) | Cue Navigator |
| `1005` | `dir_time` | `reaper.time_precise()` | Cue Navigator |
| `1006` | `dir_track_count` | Numero tracce nel progetto attivo (`0..64`) | Cue Navigator |
| `1008` | `cmd_track_idx` | `-1` = Master, `0..N-1` = traccia 0-based | Master Pro |
| `1009` | `cmd_fx_idx` | Indice FX 0-based | Master Pro |
| `1010` | `cmd_req_seq` | Incrementato dopo aver scritto `1008..1009` | Master Pro |
| `1011` | `cmd_ack_seq` | Eguagliato a `cmd_req_seq` a comando evaso | Cue Navigator |
| `1012` | `cmd_ack_status` | `1` = aperto (`TrackFX_Show(..., 3)`), `2` = non trovato | Cue Navigator |

---

## 4. Tabella Nodi Attivi (`gmem[1024..3071]`, 64 slot × 32 float)

Base dello slot `s` (`0..63`): `b = 1024 + s * 32`.

### Ordine di scrittura atomica (lock-free tear-free)
1. Il publisher calcola `inst_key = (max(0, tr_idx + 2)) * 1024 + max(0, fx_pos) * 16 + plugin_type`.
2. Cerca uno slot esistente con uguale `inst_key`, altrimenti parte dall'hash `(max(0, tr_idx + 2) * 13 + max(0, fx_pos) * 7 + plugin_type * 3) % 64` e fa probing lineare su slot liberi o scaduti (`magic != 905301` oppure `now - ts > 2.5`). Se l'istanza si è spostata (cambio traccia o posizione FX), libera il vecchio slot (`magic = 0; seq = 0`).
3. Scrive prima tutto il payload (`b+3..b+31`), poi `b+0 = 905301`, `b+1 = time_precise()`, e **per ultimo** incrementa `b+2` (`seq`).
4. Il lettore (`ZP Master Pro`) legge `seq0 = gmem[b+2]`, copia il blocco e rilegge `seq1 = gmem[b+2]`, scartando eventuali frame letti durante una scrittura parziale (`seq0 != seq1`).

### Layout del nodo (32 float)

| Offset | Campo | Descrizione |
|---|---|---|
| `+0` | `magic` | `905301` attivo, `0` libero |
| `+1` | `ts` | `time_precise()` (TTL `2.5 s`) |
| `+2` | `seq` | Sequence monotono (scritto per ultimo) |
| `+3` | `inst_key` | Chiave univoca istanza `(max(0,tr+2))*1024 + max(0,fx)*16 + ptype` |
| `+4` | `plugin_type` | `1..13` (vedi tabella sotto) |
| `+5` | `track_idx` | `-1` = Master, `0..` = indice traccia 0-based |
| `+6` | `chain_pos` | Indice FX 0-based nella catena |
| `+7` | `host_flags` | Flags restituiti da `get_host_placement()` |
| `+8` | `stage_role` | `0`=Canale/Voce, `1`=Voice Bus, `2`=Musica/Sidechain, `3`=Probe/Misura, `4`=Master |
| `+9` | `status_flags` | Bitmask: `1`=Engaged, `2`=Bypass/EngineOff, `4`=Alert DELTA, `8`=Alert SOLO, `16`=Alert CHECK, `32`=Alert CLIP/Clamp |
| `+10` | `gr_comp_db` | Riduzione dinamica compressione / leveling / ducking / gate (`>= 0 dB`) |
| `+11` | `gr_dyneq_db` | Riduzione DRC / DynEQ / BrownSlope Guard / De-Click / Carver spectral (`>= 0 dB`) |
| `+12` | `gr_lim_db` | Riduzione limiter / safety / glue (`>= 0 dB`) |
| `+13` | `tone_low_db` | Bilanciamento Low/Body (`dB` o proxy) |
| `+14` | `tone_mid_db` | Bilanciamento Mid/Presence (`dB` o proxy) |
| `+15` | `tone_high_db` | Bilanciamento High/Air (`dB` o proxy) |
| `+16` | `harm_pct` | Saturazione / armoniche / drive (`0..100 %`) |
| `+17` | `rms_in_db` | RMS ingresso (`dBFS`, `-120` se n/d) |
| `+18` | `rms_out_db` | RMS uscita (`dBFS`, `-120` se n/d) |
| `+19` | `peak_out_db` | Peak uscita (`dBFS`, `-120` se n/d) |
| `+20` | `gain_delta_db` | Variazione netta livello/trim (`dB` con segno) |
| `+21` | `activity_pct` | Attività vocale / segnale (`0..100 %`) |
| `+22` | `crest_db` | Crest factor (`dB`, `-1` se n/d) |
| `+23` | `bright_db` | Brightness (`dB`, `-99` se n/d) |
| `+24..+29` | `det1..det6` | 6 campi specifici per tipo plugin |
| `+30..+31` | `reserved` | `0` |

### Tabella `plugin_type` e dettagli `det1..det6`

| ID | Plugin | Ruolo | `det1` | `det2` | `det3` | `det4` | `det5` | `det6` |
|---|---|---|---|---|---|---|---|---|
| `1` | `ZP BUS Chain` | `1` | 1175 GR (dB) | LA2 GR (dB) | Major Tom GR (dB) | Gate GR (dB) | Brown max GR (dB) | Analog harm (%) |
| `2` | `ZP Voiceover Unified Chain` | `1` | 1175 GR (dB) | LA2 GR (dB) | Major Tom GR (dB) | Gate GR (dB) | Brown act (dB) | `0` |
| `3` | `ZP Magic Voice LAB` | `0` | Peak GR (dB) | DRC max GR (dB) | DynEQ GR (dB) | DynBal act (%) | TP Lim GR (dB) | Output trim (dB) |
| `4` | `ZP Spoken Finish` | `0` | Harm avg (%) | Body / VOG (%) | Presence (%) | Air (%) | Dyn Drive (%) | Profile (`0/1`) |
| `5` | `ZP Stagekeeper Dialogue Director` | `0` | State (`0=NEU,1=L,2=R`) | Red L (dB) | Red R (dB) | Monitor (`0=MIX,1=L,2=R`) | Engine (`0/1`) | `0` |
| `6` | `ZP Click & Attack Softener` | `0` | De-Click hold (dB) | Attack hold (dB) | Clicks/s | Mix (%) | De-Click ON | Attack ON |
| `7` | `ZP BrownSlope Dynamic Guard` | `1` | `gd1` Low (dB) | `gd2` Low-Mid (dB) | `gd3` Mid-High (dB) | `gd4` High (dB) | Mix (%) | Output Trim (dB) |
| `8` | `ZP Harmonic Space Carver` | `2` | VCA Duck (dB) | Carver Mid (dB) | Carver Low (dB) | Carver High (dB) | Glue GR (dB) | Delta mode (`0..3`) |
| `9` | `ZP Voice-Music Probe` (VOICE `85-14k`) | `3` | Density (%) | Brightness legacy (dB) | Crest (dB) | Speech (%) | RMS (dBFS) | Zona 4 Brown `4k-14k` (dB) — +13..+15=`z1..z3` (`85-250/250-800/800-4k`), +23=`tilt`, `+30`=`sub_excess_db (<80 Hz)`, `+31`=`1` |
| `10` | `ZP Voice-Music Probe` (FULL/MUS+FX `40-14k`) | `3` | Density (%) | Brightness legacy (dB) | Crest (dB) | Glue est (%) | RMS (dBFS) | Zona 4 Brown `4k-14k` (dB) — +13..+15=`z1..z3` (`40-160/160-800/800-4k`), +23=`tilt`, `+30`=`0`, `+31`=`0` |
| `11` | `ZP BrownSlope Prism` | `3` | Level (dB) | Verdict (`0/1/2`) | Have data (`0/1`) | Target (`0=-18,1=-24`) | Compare (`0=abs,1=shape`) | Zona 4 `zh` `4k-14k` (dB) — +13..+15=`zb/zlm/zmh`, +23=`tilt` dB/oct, `+30`=`comb_ms` (`0` o `0.33..8` ms), `+31`=`comb_est` (`-1..1`) |
| `12` | `ZP Loudness Meter Multichannel` | `3` | LUFS-M (LUFS) | LRA (LU) | Target LUFS | Tolleranza (LU) | TP red threshold (dBTP) | Mono mode (`0/1`) — +17=`LUFS-S`, +18=`LUFS-I`, +19=`TP` |
| `13` | `ZP Master Pro` | `4` | LUFS-S (LUFS) | LUFS-I (LUFS) | Target LUFS | Tone ON (`0/1`) | Tone Slope (`dB/oct`) | Target Profile (`0..6`) |

---

## 5. Track Directory (`gmem[3072..3583]`, 64 tracce × 8 float)

Pubblicata ogni `0.5 s` da `ZP Harmonic Space Carver Cue Navigator.lua` (o in fallback da `39_ZP_Telemetry_Engine.lua` quando Cue Navigator non è attivo) per le prime 64 tracce (`0..63`) del progetto attivo (`EnumProjects(-1)`). Base traccia `i`: `d = 3072 + i * 8`:

| Offset | Campo | Descrizione |
|---|---|---|
| `+0` | `tr_flags` | Bitmask: `1`=esiste, `2`=muted, `4`=soloed, `8`=folder parent (`I_FOLDERDEPTH > 0`), `16`=`VO_BUS`, `32`=`MUSIC_BUS` |
| `+1` | `parent_idx` | `-1` se top-level/Master, `0..63` indice traccia padre |
| `+2` | `name_len` | Lunghezza nome sanificato (`0..20`) |
| `+3..+7` | `packed[0..4]` | 5 float, ciascuno con 4 caratteri ASCII (`32..126`) impacchettati `b1 + b2*256 + b3*65536 + b4*16777216` (max `< 2^31`) |

---

## 6. Blocco Riferimento Master (`gmem[410..425]`, scritto da `ZP Master Pro`)

| Indice | Campo | Descrizione |
|---|---|---|
| `410` | `mref_magic` | `905410` |
| `411` | `mref_time` | `time_precise()` |
| `412` | `tone_on` | `0` = Tone Guard spento (metro fisso Brown `4.5 dB/oct ±10%`), `1` = Tone Guard attivo (precedenza Master Tone) |
| `413` | `tone_dyn_on` | `0` = statico (`target_slope = 4.5 + tone_slope`), `1` = dinamico (`target_slope = tone_slope` se `>= 1.5`) |
| `414` | `tone_slope` | Valore slider `Tone Slope [dB/oct]` |
| `415..418` | `tone_gain1..4` | Offset 4 punti `Tone Low / Low-Mid / Mid-High / High Gain [dB]` |
| `419` | `out_mode` | `0=Off, 1=LUFS, 2=RMS, 3=L+R` |
| `420` | `out_target_lufs` | Target LUFS di Master Pro |
| `421` | `lim_ceiling` | Limiter ceiling `[dB]` |
| `422` | `ui_lufs_s` | LUFS Short-Term misurato su Master Pro |
| `423` | `ui_lufs_i` | LUFS Integrato misurato su Master Pro |
| `424` | `ui_tp_db` | Picco / True Peak dB su Master Pro |
| `425` | `target_profile` | Profilo target attivo (`0..6`) |

---

## 7. Blocco Sintesi ZP Telemetry Engine (`gmem[3600..3619]`)

Pubblicato da `39_ZP_Telemetry_Engine.lua` (~`4 Hz`) e letto da `ZP Master Pro` e `ZP Voice-Music Probe`:

| Indice | Campo | Descrizione |
|---|---|---|
| `3600` | `te_magic` | `905360` |
| `3601` | `te_heartbeat` | Contatore incrementale |
| `3602` | `te_time` | `reaper.time_precise()` (TTL `3.0 s`) |
| `3603` | `te_ref_slope` | Pendenza target attiva (`4.5` se Master Tone spento) |
| `3604` | `te_ref_mode` | `0` = Brown `4.5 ±10%`, `1` = Master Tone statico, `2` = Master Tone dinamico |
| `3605` | `te_useful_sec` | Secondi di segnale utile integrati nella finestra di giudizio |
| `3606` | `te_status` | `0` = attesa, `1` = in tolleranza, `2` = attenzione, `3` = fuori margine / opposizione |
| `3607` | `te_issue_count` | Numero segnalazioni di accordatura attive (escluse quelle marcate "Scelta voluta") |
| `3608` | `te_top_kind` | `0=ok, 1=brown_tilt, 2=brown_zone, 3=loudness, 4=opposizione_tono, 5=opposizione_gain, 6=carico_comp, 7=alert_sicurezza` |
| `3609` | `te_top_track` | Traccia principale coinvolta (`-1`=Master, `-2`=n/d) |
| `3610` | `te_top_fx` | Indice FX 0-based principale (`-1`=fader/segmento) |
| `3611` | `te_top_val` | Grandezza numerica della segnalazione principale (dB / LU / dB/oct) |
| `3612..3615` | `te_z1..te_z4` | Media scostamento 4 zone Brown (`40-160 / 160-800 / 800-4k / 4k-14k`) vs target attivo (dB) |
| `3616` | `te_tilt_err` | Media scostamento pendenza vs target attivo (`dB/oct`) |
| `3617` | `te_lufs_err` | Media scostamento loudness vs target (`LU`) |
| `3618` | `te_conflict_count` | Numero opposizioni senza non-linearità intermedia |
| `3619` | `te_preemph_count` | Numero pre-enfasi/recuperi con non-linearità intermedia riconosciuta (informativi) |
