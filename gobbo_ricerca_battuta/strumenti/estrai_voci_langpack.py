#!/usr/bin/env python3
"""
estrai_voci_langpack.py — Estrae le stringhe da tradurre per frequenza e priorità.
"""

import re
from pathlib import Path
from collections import Counter, defaultdict

BASE_DIR = Path(__file__).resolve().parent.parent.parent
TEMPLATE_PATH = BASE_DIR / "REAPER_Italiano" / "template_reaper782.ReaperLangPack"
CATALOG_PATH = BASE_DIR / "REAPER_Italiano" / "catalogo_reaper_it.txt"

ACTION_SECTIONS = {
    "actions", "midi_actions", "explorer_actions", "xfade_actions",
    "actions_fmt", "actions_sub", "customaction", "actionlist",
    "actiondialog", "actionlist_synonyms"
}

def extract():
    counts = Counter()
    sec_map = defaultdict(set)
    current_sec = None

    with open(TEMPLATE_PATH, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line_str = line.strip()
            m_sec = re.match(r"^\[([^\]]+)\]", line_str)
            if m_sec:
                current_sec = m_sec.group(1)
                continue
            if not current_sec or current_sec in ACTION_SECTIONS:
                continue

            m_kv = re.match(r"^(?:;\^?|)([^=]+)=(.*)$", line_str)
            if m_kv:
                key = m_kv.group(1).strip()
                val = m_kv.group(2)
                if key == "5CA1E00000000000" or not val.strip():
                    continue
                counts[val] += 1
                sec_map[val].add(current_sec)

    return counts, sec_map

if __name__ == "__main__":
    counts, sec_map = extract()
    print(f"Testi unici estraibili: {len(counts)}")
    # Voci presenti in common o MENU_102
    prio_1 = [v for v, c in counts.most_common() if "common" in sec_map[v] or "MENU_102" in sec_map[v]]
    print(f"Voci priorità 1 (common o MENU_102): {len(prio_1)}")
