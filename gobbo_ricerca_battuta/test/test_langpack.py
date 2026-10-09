#!/usr/bin/env python3
"""
test_langpack.py — Verifica di integrità del file Italiano (ZP).ReaperLangPack.
"""

import sys
import re
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent.parent
LANGPACK_PATH = BASE_DIR / "REAPER_Italiano" / "Italiano (ZP).ReaperLangPack"

ACTION_SECTIONS = {
    "actions", "midi_actions", "explorer_actions", "xfade_actions",
    "actions_fmt", "actions_sub", "customaction", "actionlist",
    "actiondialog", "actionlist_synonyms"
}

def test():
    if not LANGPACK_PATH.exists():
        print(f"ERRORE: File non trovato: {LANGPACK_PATH}")
        sys.exit(1)

    with open(LANGPACK_PATH, "r", encoding="utf-8") as f:
        lines = f.readlines()

    assert lines[0].strip() == "#NAME:Italiano (ZP)", f"Header non valido: {lines[0]}"

    current_sec = None
    uncommented_in_actions = 0
    total_uncommented = 0
    total_sections = 0

    for line_num, line in enumerate(lines, 1):
        line_str = line.strip()
        m_sec = re.match(r"^\[([^\]]+)\]", line_str)
        if m_sec:
            current_sec = m_sec.group(1)
            total_sections += 1
            continue

        if not current_sec:
            continue

        # Se la riga non inizia con ';' ed ha '='
        if not line_str.startswith(";") and "=" in line_str:
            key, val = line_str.split("=", 1)
            if key == "5CA1E00000000000":
                continue # chiave di scala
            total_uncommented += 1
            if current_sec in ACTION_SECTIONS:
                uncommented_in_actions += 1
                print(f"ERRORE riga {line_num}: chiave tradotta nella sezione action [{current_sec}]: {line_str}")

    assert uncommented_in_actions == 0, f"Trovate {uncommented_in_actions} chiavi non commentate nelle action!"
    print(f"VERIFICA LANGPACK: OK")
    print(f"  Sezioni totali: {total_sections}")
    print(f"  Chiavi tradotte e scommentate: {total_uncommented}")
    print(f"  Chiavi scommentate nelle sezioni action: {uncommented_in_actions} (0 come da specifica)")

if __name__ == "__main__":
    test()
