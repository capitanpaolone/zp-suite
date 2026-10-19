# REAPER Italiano (ZP) — Memoria di lavoro e stato traduzione

Aggiornata: 2026-10-18

## 1. File e architettura del generatore

- **File Language Pack generato**: `REAPER_Italiano/Italiano (ZP).ReaperLangPack`
  - **SHA-256 corrente**: `dd851a8d886382608ae23e7e537c02404e37743a68a7b570b1a7fbe2d5e38993`
  - **Installazione REAPER locale**: `/Users/paolob/Library/Application Support/REAPER/LangPack/Italiano (ZP).ReaperLangPack` (o `~/Library/Application Support/REAPER/LangPack/Italiano (ZP).ReaperLangPack`)
- **Template ufficiale di riferimento**: `REAPER_Italiano/template_reaper782.ReaperLangPack` (REAPER v7.82, 841 sezioni, 25.715 righe chiave=valore)
- **Catalogo centrale di traduzione**: `REAPER_Italiano/catalogo_reaper_it.txt`
  - Formato: `<stringa_originale_inglese>\t<traduzione_italiana>` (una voce per riga; righe che iniziano con `#` sono commenti di sezione).
  - Voci uniche tradotte: **11.753** (con conservazione esatta degli spazi iniziali/finali richiesti dalle concatenazioni UI di REAPER).
- **Moduli di traduzione Preferenze (`[prefs_*_help]`)**: `REAPER_Italiano/dati_traduzione/gruppo1..8.py`
- **Script generatore e validatore**: `gobbo_ricerca_battuta/strumenti/genera_langpack.py`
  - Preserva automaticamente l'intestazione ReaPack (`; @version 1.0`, `; @author Paolo Balestri`, `; @about ...`, `; @changelog ...`, `;`) subito dopo `#NAME:Italiano (ZP)`.
  - Valida tutti i segnaposto C (`%s`, `%d`, `%f`, `%u`, `%.1f`, ecc.) prima di scrivere il file.
  - Applica gli override di scala (`5CA1E00000000000`) sulle finestre critiche (`DLG_128`, `DLG_127`, `DLG_126`, `DLG_218`, `DLG_274`).
- **Test automatico di integrità**: `gobbo_ricerca_battuta/test/test_langpack.py` (richiamato anche da `gobbo_ricerca_battuta/test/run_all.sh`).
- **Backup pre-modifica (2026-10-18)**: `gobbo_ricerca_battuta/backup/`
  - `catalogo_reaper_it_prima_2026-10-18.txt`
  - `Italiano_ZP_prima_2026-10-18.ReaperLangPack`
  - `genera_langpack_prima_2026-10-18.py`

---

## 2. Regole ferree e glossario tecnico (NON VIOLARE)

1. **Le 10 sezioni delle Action NON vanno MAI tradotte**:
   ```python
   ACTION_SECTIONS = {
       "actions", "midi_actions", "explorer_actions", "xfade_actions",
       "actions_fmt", "actions_sub", "customaction", "actionlist",
       "actiondialog", "actionlist_synonyms"
   }
   ```
   Tutte le 3.689 righe di queste sezioni devono restare commentate con `;` in inglese per non alterare la ricerca per nome nella Action List di REAPER.
2. **I 16 termini tecnici DAW restano SEMPRE in inglese** (come stabilito in `gobbo_ricerca_battuta/glossario_traduzione.md`):
   - `item` (mai *elemento* quando riferito a media/MIDI/automation item)
   - `take` (mai *ripresa*)
   - `marker` (mai *marcatore*)
   - `take marker` (mai *marcatore di take*)
   - `region` (mai *regione*)
   - `track` (mai *traccia/tracce*)
   - `render` (mai *renderizzazione/esportazione* per l'azione di render)
   - `ripple` (mai *ondulazione*)
   - `trim` (mai *rifilatura*)
   - `loop` (mai *ciclo*)
   - `edit` (usare *edit* nei composti tecnici come *cursore di edit*, *razor edit*, *edit spettrale*, *comportamento di edit*)
   - `FX` (mai *effetti* quando indica la catena/slot FX)
   - `bus`
   - `send` (mai *mandata/mandate*)
   - `toolbar` (mai *barra degli strumenti*)
   - `SRT`
3. **Preservazione formattazione**:
   - Mantenere intatti tutti i segnaposto (`%s`, `%d`, `%f`, `%u`, ecc.), le sequenze di escape (`\r\n`, `\n`, `\t`, `\0`), gli acceleratori `&` e gli spazi iniziali/finali delle stringhe.

---

## 3. Stato di copertura (`REAPER 7.82`)

| Categoria | Prima (14/10) | Ora (18/10) | Totale | Copertura | Dettagli |
| :--- | ---: | ---: | ---: | ---: | :--- |
| **Menu principali e contestuali (`MENU_*`, `*_MENU_*`)** | 2.671 | **3.579** | 3.579 | **100,0%** | Tutti i menu di REAPER, MIDI, Media Explorer, Video e ReaPlugs |
| **Finestre di dialogo (`DLG_*`, `*_DLG_*`)** | 2.138 | **4.367** | 4.367 | **100,0%** | Tutte le finestre di dialogo di REAPER, formati audio/video e ReaPlugs |
| **Aiuto/Tooltip Preferenze (`prefs_*_help`)** | 723 | **723** | 723 | **100,0%** | Tutte le 49 sezioni di spiegazione in basso nelle Preferenze |
| **Stringhe condivise (`[common]`)** | 1.073 | **1.970** | 2.028 | **97,1%** | Escluse solo le 33 stringhe usate esclusivamente nelle Action e 25 sigle/simboli invarianti |
| **Sezioni UI operative (`track`, `item*`, `fx*`, `render*`, `midi*`, `prefs*`, `routing`, `explorer*`, `projbay`, `tooltip`, `transport`, `xfade`, `nudge`, `cpumeter`, `screenset`, `glue`, `saveas`, `regmgr*`, `video*`, `wave*`, `vst`/`au`/`clap`/`lv2`/`jsfx*`, ecc.)** | 315 | **7.058** | 11.329 | **100% UI visibile** | Restano commentate solo le sezioni interne non-UI (`undo`, `mousemaps`, `theme`, `tag_genre`, `midi_insts`, `access`) |
| **Sezioni Action (`ACTION_SECTIONS`)** | 0 | **0** | 3.689 | **0,0% (Intatte)** | **100% commentate (`;`) in inglese** come da specifica |
| **Totale complessivo (escluse Action)** | **5.847** | **17.697** | **22.026** | **80,3%** | `VERIFICA LANGPACK: OK` (0 errori di segnaposto) |

---

## 4. Comandi rapidi di rigenerazione e verifica

Dalla radice del repository (`zp-suite`):

```bash
# 1. Rigenera REAPER_Italiano/Italiano (ZP).ReaperLangPack dal catalogo
python3 gobbo_ricerca_battuta/strumenti/genera_langpack.py

# 2. Esegue il test di integrità del Language Pack (header, ReaPack tag, 0 chiavi in ACTION_SECTIONS)
python3 gobbo_ricerca_battuta/test/test_langpack.py
```
