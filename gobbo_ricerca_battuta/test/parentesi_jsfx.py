"""Parentesi tonde e quadre bilanciate nel codice di ogni JSFX (da @init in giu', senza testi e commenti).
Una parentesi persa impedisce al plugin di compilare in REAPER (Mirror EQ, 2026-10-10)."""
import glob, re, sys
bad = 0
for f in sorted(glob.glob("ZP */*.jsfx")):
    t = open(f, encoding="utf-8", errors="replace").read()
    t = re.sub(r'"(\\.|[^"\\])*"', '""', t)
    t = re.sub(r"//[^\n]*", "", t)
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    if "\n@init" not in t:
        continue
    code = t.split("\n@init", 1)[1]
    for a, b in (("(", ")"), ("[", "]")):
        if code.count(a) != code.count(b):
            print(f"PARENTESI {a}{b} SBILANCIATE ({code.count(a) - code.count(b):+d}): {f}")
            bad = 1
sys.exit(bad)
