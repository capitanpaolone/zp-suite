# ZP Shared Bus v3 — Specifica Architetturale (`gmem=ZPVoiceoverSharedBus`)

Aggiornata: 2026-11-22  
Stato: **Implementato nella candidata `zp-suite-2.6.9`**  
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
| `1000..1015` | **Shared Bus v3 Header & Open-FX Mailbox** | Magic, versione, Track Directory heartbeat, comando apri-FX |
| `1024..3071` | **Shared Bus v3 Tabella Nodi Attivi** | 64 slot × 32 float (max 64 istanze simultanee) |
| `3072..3583` | **Shared Bus v3 Track Directory (opzionale)** | 64 tracce × 8 float pubblicati da Cue Navigator |
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
| `+4` | `plugin_type` | `1..10` (vedi tabella sotto) |
| `+5` | `track_idx` | `-1` = Master, `0..` = indice traccia 0-based |
| `+6` | `chain_pos` | Indice FX 0-based nella catena |
| `+7` | `host_flags` | Flags restituiti da `get_host_placement()` |
| `+8` | `stage_role` | `0`=Canale/Voce, `1`=Voice Bus, `2`=Musica/Sidechain, `3`=Probe/Misura |
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
| `9` | `ZP Voice-Music Probe` (Voice) | `3` | Density (%) | Brightness (dB) | Crest (dB) | Speech (%) | RMS (dBFS) | Peak (dBFS) |
| `10` | `ZP Voice-Music Probe` (Music) | `3` | Density (%) | Brightness (dB) | Crest (dB) | Glue est (%) | RMS (dBFS) | Peak (dBFS) |

---

## 5. Track Directory (`gmem[3072..3583]`, 64 tracce × 8 float)

Pubblicata ogni `0.5 s` da `ZP Harmonic Space Carver Cue Navigator.lua` per le prime 64 tracce (`0..63`) del progetto attivo (`EnumProjects(-1)`). Base traccia `i`: `d = 3072 + i * 8`:

| Offset | Campo | Descrizione |
|---|---|---|
| `+0` | `tr_flags` | Bitmask: `1`=esiste, `2`=muted, `4`=soloed, `8`=folder parent (`I_FOLDERDEPTH > 0`), `16`=`VO_BUS`, `32`=`MUSIC_BUS` |
| `+1` | `parent_idx` | `-1` se top-level/Master, `0..63` indice traccia padre |
| `+2` | `name_len` | Lunghezza nome sanificato (`0..20`) |
| `+3..+7` | `packed[0..4]` | 5 float, ciascuno con 4 caratteri ASCII (`32..126`) impacchettati `b1 + b2*256 + b3*65536 + b4*16777216` (max `< 2^31`) |
