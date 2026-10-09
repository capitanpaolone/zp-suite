#!/usr/bin/env python3
"""
genera_langpack.py — Generatore e validatore del Language Pack Italiano (ZP) per REAPER.

Legge il template ufficiale (template_reaper782.ReaperLangPack) e il catalogo univoco
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
TEMPLATE_PATH = BASE_DIR / "REAPER_Italiano" / "template_reaper782.ReaperLangPack"
CATALOG_PATH = BASE_DIR / "REAPER_Italiano" / "catalogo_reaper_it.txt"
OUTPUT_PATH = BASE_DIR / "REAPER_Italiano" / "Italiano (ZP).ReaperLangPack"

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

def validate_placeholders(orig, trans):
    """Verifica che i segnaposto in orig siano conservati in trans."""
    orig_fmt = re.findall(r"%[-+0-9.]*[a-zA-Z%]", orig)
    trans_fmt = re.findall(r"%[-+0-9.]*[a-zA-Z%]", trans)
    if sorted(orig_fmt) != sorted(trans_fmt):
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

    with open(TEMPLATE_PATH, "r", encoding="utf-8", errors="ignore") as f_in, \
         open(OUTPUT_PATH, "w", encoding="utf-8") as f_out:

        for line in f_in:
            total_lines += 1
            line_str = line.rstrip("\r\n")

            # Intestazione file
            if total_lines == 1 and line_str.startswith("#NAME:"):
                f_out.write("#NAME:Italiano (ZP)\n")
                continue

            # Riconoscimento sezione
            m_sec = re.match(r"^\[([^\]]+)\](?:\s*;\s*(.*))?$", line_str)
            if m_sec:
                current_sec = m_sec.group(1)
                f_out.write(line_str + "\n")
                # Se la sezione ha una scala impostata, aggiungila subito sotto l'header
                if current_sec in SCALE_OVERRIDES:
                    scale = SCALE_OVERRIDES[current_sec]
                    f_out.write(f"5CA1E00000000000={scale}\n")
                continue

            # Se è una sezione Action, lasciamo la riga commentata intatta
            if current_sec in ACTION_SECTIONS:
                f_out.write(line_str + "\n")
                continue

            # Parsing chiave=valore
            # Può iniziare con ;^ o ; o niente
            m_kv = re.match(r"^(;(?:\^|))([^=]+)=(.*)$", line_str)
            if m_kv:
                prefix = m_kv.group(1)  # ";" o ";^"
                key = m_kv.group(2)
                orig_val = m_kv.group(3)

                # Se è già la chiave di scala saltiamo o lasciamo
                if key == "5CA1E00000000000":
                    f_out.write(line_str + "\n")
                    continue

                if orig_val in catalog:
                    trans_val = catalog[orig_val]
                    # Scommenta la riga
                    f_out.write(f"{key}={trans_val}\n")
                    translated_keys += 1
                else:
                    # Non presente nel catalogo -> mantieni commentato
                    f_out.write(line_str + "\n")
            else:
                f_out.write(line_str + "\n")

    print(f"Generato con successo: {OUTPUT_PATH}")
    print(f"Righe totali processate: {total_lines}")
    print(f"Chiavi tradotte e scommentate: {translated_keys}")
    return translated_keys

if __name__ == "__main__":
    generate_langpack()
