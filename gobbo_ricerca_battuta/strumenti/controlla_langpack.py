#!/usr/bin/env python3
"""Controlla un language pack REAPER (anche di terzi) contro i problemi noti.

Uso:  python3 controlla_langpack.py "<file.ReaperLangPack>" [altro.ReaperLangPack ...]
      python3 controlla_langpack.py            (controlla tutti i pack in REAPER/LangPack)

Segnala:
  1. Render Queue: voci che REAPER confronta con un letterale inglese e che
     devono restare invariate ("(delay %ds)", "sel_regions", "sel_markers").
     Se tradotte, i job in coda non si possono piu' cancellare ne' eseguire.
  2. Segnaposto printf (%d %s ...) diversi dal template o in ordine diverso
     (REAPER li passa in ordine fisso: un ordine scambiato puo' dare testo
     sbagliato o un crash).

Non modifica nessun file. Exit code 1 se trova problemi della classe 1.
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "test"))
import test_langpack as T  # noqa: E402


def default_packs():
    d = Path.home() / "Library/Application Support/REAPER/LangPack"
    return sorted(d.glob("*.ReaperLangPack")) if d.is_dir() else []


def check(path):
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()
    active = T._active_keys(lines)
    functional = []
    for key, expected in T.MUST_STAY_ENGLISH.items():
        got = active.get(key)
        if got is not None and got != expected:
            functional.append(f"[{key[0]}] {key[1]}: deve restare {expected!r}, trovato {got!r}")
    placeholders = []
    try:
        T.check_placeholders_in_order(lines)
    except AssertionError as e:
        placeholders = str(e).splitlines()[1:]
    return functional, placeholders


def main(argv):
    packs = [Path(a) for a in argv] or default_packs()
    if not packs:
        print("Nessun pack da controllare.")
        return 0
    bad = 0
    for p in packs:
        functional, placeholders = check(p)
        status = "OK" if not functional and not placeholders else "PROBLEMI"
        print(f"== {p.name}: {status}")
        for line in functional:
            print("   RENDER QUEUE  " + line)
        for line in placeholders:
            print("   SEGNAPOSTO    " + line)
        if functional:
            bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
