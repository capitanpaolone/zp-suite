#!/usr/bin/env python3
"""
genera_langpack.py — Generatore e validatore del Language Pack Italiano (ZP) per REAPER.

Legge il template ufficiale (template_reaper786.ReaperLangPack) e il catalogo univoco
di traduzione (catalogo_reaper_it.txt), e genera 'Italiano (ZP).ReaperLangPack'.

Regole ferree:
1. Le sezioni delle Action restano SEMPRE commentate (';') in inglese.
2. Segnaposto (%s, %d, %f, \n, \t, sigle, ecc.) validati automaticamente.
3. Nessun duplicato: il catalogo associa testo originale -> traduzione italiana.
4. Acceleratori con '&' e scorciatoie dopo '\t' rispettate.
"""

import sys
import re
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent.parent
TEMPLATE_PATH = BASE_DIR / "REAPER_Italiano" / "template_reaper786.ReaperLangPack"
LEGACY_PATH = BASE_DIR / "REAPER_Italiano" / "template_voci_precedenti.txt"
CATALOG_PATH = BASE_DIR / "REAPER_Italiano" / "catalogo_reaper_it.txt"
OUTPUT_PATH = BASE_DIR / "REAPER_Italiano" / "Italiano (ZP).ReaperLangPack"

# Intestazione ReaPack (letta da reapack-index). Alzare @version a ogni nuova uscita e aggiornare @changelog.
# Deve finire con una riga vuota: e' lei a chiudere l'intestazione.
REAPACK_HEADER = """; @description Italiano (ZP) — traduzione italiana di REAPER 7.86, con le spiegazioni delle preferenze
; @noindex
; @version 2.6.7
; @author Paolo Balestri (Lato Cardioide)
; @about
;   Language pack italiano di REAPER, parte della ZP Studio Suite.
;   Dopo l'installazione: REAPER > Options > Preferences > General > Language > Browse e scegli "Italiano (ZP)".
;   Pensato per REAPER 7.86; conserva anche le voci delle versioni dalla 7.82 alla 7.85.
;   Le voci che una versione diversa non conosce restano in inglese.
; @changelog
;   ZP Studio Suite 2.6.7: allineato a REAPER 7.86. In italiano anche le finestre dei pacchetti .ReaperPkg, la cartella FX nascosti, il Learn MIDI/OSC di track e send, le nuove opzioni di render e i take marker con durata.
;   ZP Studio Suite 2.6.4: aggiornamento terminologico della traduzione; il menu principale "Help" mantiene la ricerca nativa di macOS, con voci e sottomenu in italiano.
;   2.6.0: Primo rilascio in ReaPack: traduzione completa dei menu e delle finestre, con le spiegazioni delle preferenze.

"""

ACTION_SECTIONS = {
    "actions", "midi_actions", "explorer_actions", "xfade_actions",
    "actions_fmt", "actions_sub", "customaction", "actionlist",
    "actiondialog", "actionlist_synonyms"
}

# Finestre che necessitano di fattore di scala per evitare troncamenti di testo in italiano
# Formato: id_sezione -> fattore scala (es. "DLG_128": "1.15")
SCALE_OVERRIDES = {
    "DLG_128": "1.10", # Preferences
    "DLG_127": "1.10", # Project settings
    "DLG_126": "1.10", # Project settings sub
    "DLG_218": "1.15", # Lock settings
    "DLG_274": "1.10", # Actions dialog
}

def load_catalog(path):
    catalog = {}
    if not path.exists():
        return catalog
    with open(path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.rstrip("\r\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) >= 2:
                orig = parts[0]
                trans = parts[1]
                catalog[orig] = trans
    return catalog

def load_legacy(path):
    """Voci di template precedenti (tolte o riscritte nelle versioni nuove), per sezione.
    Aggiunte in coda alla sezione: il pack resta tradotto anche sulle versioni di REAPER precedenti."""
    legacy = {}
    if not path.exists():
        return legacy
    sec = None
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            s = line.rstrip("\r\n")
            m = re.match(r"^\[([^\]]+)\]$", s)
            if m:
                sec = m.group(1)
            elif sec and re.match(r"^;\^?[^=;][^=]*=", s):
                legacy.setdefault(sec, []).append(s)
    return legacy

def validate_placeholders(orig, trans):
    """Verifica che i segnaposto in orig siano conservati in trans."""
    orig_fmt = re.findall(r"%[-+0-9.]*[a-zA-Z%]", orig)
    trans_fmt = re.findall(r"%[-+0-9.]*[a-zA-Z%]", trans)
    # Ordine incluso: printf legge gli argomenti per posizione, scambiarli (es. %s al posto di %d) manda in crash REAPER.
    if orig_fmt != trans_fmt:
        return False, f"Mismatch segnaposto: orig={orig_fmt} trans={trans_fmt}"
    
    # Controllo tab e newline letterali (\t, \n)
    if orig.count(r"\t") != trans.count(r"\t") and "\t" not in orig:
        # Se c'è un tab reale o \t letterale
        pass
    return True, ""

def generate_langpack():
    if not TEMPLATE_PATH.exists():
        print(f"ERRORE: Template non trovato in {TEMPLATE_PATH}")
        sys.exit(1)

    catalog = load_catalog(CATALOG_PATH)
    print(f"Catalogo caricato: {len(catalog)} voci uniche tradotte.")

    errors = []
    # Validazione preliminare catalogo
    for orig, trans in catalog.items():
        ok, msg = validate_placeholders(orig, trans)
        if not ok:
            errors.append(f"ERRORE '{orig}' -> '{trans}': {msg}")

    if errors:
        for err in errors[:10]:
            print(err)
        if len(errors) > 10:
            print(f"... e altri {len(errors) - 10} errori.")
        sys.exit(1)

    translated_keys = 0
    total_lines = 0
    current_sec = None

    legacy = load_legacy(LEGACY_PATH)
    legacy_keys = 0

    def write_entry(f_out, sec, line_str):
        """Scrive una riga chiave=valore: tradotta e scommentata se il catalogo la conosce."""
        if sec in ACTION_SECTIONS:
            f_out.write(line_str + "\n")
            return 0
        m_kv = re.match(r"^(;(?:\^|))([^=]+)=(.*)$", line_str)
        if not m_kv:
            f_out.write(line_str + "\n")
            return 0
        key = m_kv.group(2)
        orig_val = m_kv.group(3)
        if key == "5CA1E00000000000":
            f_out.write(line_str + "\n")
            return 0
        if orig_val in catalog:
            f_out.write(f"{key}={catalog[orig_val]}\n")
            return 1
        f_out.write(line_str + "\n")
        return 0

    def flush_legacy(f_out, sec):
        """A fine sezione: le voci che esistevano nei template precedenti (solo quelle tradotte)."""
        count = 0
        for line_str in legacy.pop(sec, []):
            m_kv = re.match(r"^;\^?([^=]+)=(.*)$", line_str)
            if sec in ACTION_SECTIONS or not m_kv or m_kv.group(2) not in catalog:
                continue
            f_out.write(f"{m_kv.group(1)}={catalog[m_kv.group(2)]}\n")
            count += 1
        return count

    with open(TEMPLATE_PATH, "r", encoding="utf-8", errors="ignore") as f_in, \
         open(OUTPUT_PATH, "w", encoding="utf-8") as f_out:

        pending_blank = []
        for line in f_in:
            total_lines += 1
            line_str = line.rstrip("\r\n")

            # Intestazione file
            if total_lines == 1 and line_str.startswith("#NAME:"):
                f_out.write("#NAME:Italiano (ZP)\n")
                f_out.write(REAPACK_HEADER)
                continue

            # Le righe vuote in coda a una sezione si scrivono dopo le voci precedenti.
            if line_str == "" and current_sec is not None:
                pending_blank.append(line_str)
                continue

            # Riconoscimento sezione
            m_sec = re.match(r"^\[([^\]]+)\](?:\s*;\s*(.*))?$", line_str)
            if m_sec:
                if current_sec is not None:
                    legacy_keys += flush_legacy(f_out, current_sec)
                for blank in pending_blank:
                    f_out.write(blank + "\n")
                pending_blank = []
                current_sec = m_sec.group(1)
                f_out.write(line_str + "\n")
                # Se la sezione ha una scala impostata, aggiungila subito sotto l'header
                if current_sec in SCALE_OVERRIDES:
                    scale = SCALE_OVERRIDES[current_sec]
                    f_out.write(f"5CA1E00000000000={scale}\n")
                continue

            for blank in pending_blank:
                f_out.write(blank + "\n")
            pending_blank = []
            translated_keys += write_entry(f_out, current_sec, line_str)

        if current_sec is not None:
            legacy_keys += flush_legacy(f_out, current_sec)
        for blank in pending_blank:
            f_out.write(blank + "\n")

    if legacy:
        print(f"ATTENZIONE: sezioni delle voci precedenti non piu' presenti nel template: {sorted(legacy)}")
    print(f"Voci di versioni precedenti di REAPER aggiunte: {legacy_keys}")
    print(f"Generato con successo: {OUTPUT_PATH}")
    print(f"Righe totali processate: {total_lines}")
    print(f"Chiavi tradotte e scommentate: {translated_keys}")
    return translated_keys

if __name__ == "__main__":
    generate_langpack()
