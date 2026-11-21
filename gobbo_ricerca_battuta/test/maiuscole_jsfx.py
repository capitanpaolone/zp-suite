"""In EEL2 i nomi delle variabili NON distinguono maiuscole e minuscole: lk_P e lk_p sono la stessa
variabile (Magic Voice LAB, 2026-11-21: il livello del Peak sovrascritto dall'interruttore del legame).
Segnala i nomi che differiscono solo per maiuscole; quelli gia' verificati innocui stanno in NOTI."""
import glob, re, sys, collections
NOTI = {  # verificati: variabili locali o parametri di funzioni grafiche, non si pestano
    "ZP Master/ZP Master Pro.jsfx": {"ph", "pw", "px", "dbl"},
    "ZP Misura/ZP BrownSlope Prism.jsfx": {"n"},
    "ZP Misura/ZP Loudness Meter Multichannel.jsfx": {"h", "k", "w", "x", "y"},
    "ZP Voce/ZP BUS Chain.jsfx": {"a", "cr", "cy", "kr", "mode_y", "pbw", "ph", "pw", "px", "q", "vh", "vx", "vy"},
    "ZP Voce/ZP Magic Voice LAB.jsfx": {"h", "hb", "w", "x", "y", "xl", "xr"},
    "ZP Voce/ZP Voiceover Unified Chain.jsfx": {"cy", "kr", "pbw", "ph", "pw", "px", "q", "vh", "vx", "vy", "cr"},
}
bad = 0
for f in sorted(glob.glob("ZP */*.jsfx")):
    s = open(f, encoding="utf-8", errors="replace").read()
    s = re.sub(r'"(\\.|[^"\\])*"', '""', s); s = re.sub(r"//[^\n]*", "", s); s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    if "\n@init" not in s:
        continue
    nomi = collections.defaultdict(set)
    for n in re.findall(r"(?<![#\w.])([A-Za-z_]\w*)\b(?!\s*\()", s.split("\n@init", 1)[1]):
        nomi[n.lower()].add(n)
    for k, v in sorted(nomi.items()):
        if len(v) > 1 and k not in NOTI.get(f, set()):
            print(f"NOMI UGUALI PER EEL2 (maiuscole/minuscole): {' / '.join(sorted(v))} in {f}")
            bad = 1
sys.exit(bad)
