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

TEMPLATE_PATH = BASE_DIR / "REAPER_Italiano" / "template_reaper786.ReaperLangPack"
SPEC_RE = re.compile(r"%[-+0-9.]*[a-zA-Z%]")

# Stringhe che REAPER confronta con un letterale inglese (dimostrato dal disassemblato):
# la Render Queue riconosce il job cercando ".RPP (delay" nel testo della colonna;
# se il suffisso e' tradotto il job non si puo' piu' cancellare ne' eseguire.
MUST_STAY_ENGLISH = {
    ("renderq", "F1B801E6F94AB9D5"): "(delay %ds)",
    ("renderq", "FEE3D8E1E609E3D3"): "sel_regions",
    ("renderq", "C879AB4AE275313D"): "sel_markers",
}


def _active_keys(lines):
    sec = None
    out = {}
    for line in lines:
        s = line.rstrip("\r\n")
        m = re.match(r"^\[([^\]]+)\]", s)
        if m:
            sec = m.group(1)
            continue
        if sec and not s.startswith(";") and "=" in s:
            k, v = s.split("=", 1)
            out[(sec, k)] = v
    return out


def check_functional_strings(lines):
    active = _active_keys(lines)
    for key, expected in MUST_STAY_ENGLISH.items():
        got = active.get(key)
        assert got == expected, f"{key[0]}/{key[1]} deve restare '{expected}' (REAPER lo confronta in inglese), trovato {got!r}"


def check_placeholders_in_order(lines):
    """Ogni voce attiva deve avere gli stessi segnaposto printf, nello stesso ordine, del template."""
    with open(TEMPLATE_PATH, "r", encoding="utf-8", errors="ignore") as f:
        tmpl_lines = f.readlines()
    english = {}
    sec = None
    for line in tmpl_lines:
        s = line.rstrip("\r\n")
        m = re.match(r"^\[([^\]]+)\]", s)
        if m:
            sec = m.group(1)
            continue
        m = re.match(r"^;\^?([0-9A-Fa-f]{16})=(.*)$", s)
        if m:
            english[(sec, m.group(1))] = m.group(2)
    bad = []
    for (sec, key), val in _active_keys(lines).items():
        en = english.get((sec, key))
        if en is None:
            continue
        if SPEC_RE.findall(en) != SPEC_RE.findall(val):
            bad.append(f"[{sec}] {key}: {en!r} -> {val!r}")
    assert not bad, "Segnaposto diversi dal template o in ordine diverso:\n" + "\n".join(bad[:10])


def test():
    if not LANGPACK_PATH.exists():
        print(f"ERRORE: File non trovato: {LANGPACK_PATH}")
        sys.exit(1)

    with open(LANGPACK_PATH, "r", encoding="utf-8") as f:
        lines = f.readlines()

    assert lines[0].strip() == "#NAME:Italiano (ZP)", f"Header non valido: {lines[0]}"
    header_lines = lines[1:16]
    assert sum(l.strip().startswith("; @version ") for l in header_lines) == 1, "Il tag ReaPack @version deve comparire una volta sola!"
    assert sum(l.strip().startswith("; @description ") for l in header_lines) == 1, "Il tag ReaPack @description deve comparire una volta sola!"
    assert any(l.strip() == "; @noindex" for l in header_lines), "Il language pack è incluso nella Suite e non va indicizzato come pacchetto separato!"

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
    check_functional_strings(lines)
    check_placeholders_in_order(lines)
    print(f"VERIFICA LANGPACK: OK")
    print(f"  Sezioni totali: {total_sections}")
    print(f"  Chiavi tradotte e scommentate: {total_uncommented}")
    print(f"  Chiavi scommentate nelle sezioni action: {uncommented_in_actions} (0 come da specifica)")

if __name__ == "__main__":
    test()
