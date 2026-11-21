"""In EEL2 una funzione va definita prima di essere usata: una chiamata che la precede
(anche dentro un'altra funzione) fa fallire la compilazione del JSFX in REAPER
('xxx' undefined). Magic Voice LAB, 2026-11-21."""
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
    defs = {m.group(1): m.start() for m in re.finditer(r"\bfunction\s+([A-Za-z_][\w.]*)\s*\(", code)}
    for name, pos in defs.items():
        base = name.split(".")[-1]
        for m in re.finditer(r"(?<![\w.])(?:[A-Za-z_]\w*\.)?" + re.escape(base) + r"\s*\(", code):
            if m.start() >= pos:
                break
            if code[max(0, m.start() - 9):m.start()].rstrip().endswith("function"):
                continue
            riga = code[:m.start()].count("\n") + t.split("\n@init", 1)[0].count("\n") + 2
            print(f"FUNZIONE USATA PRIMA DI ESSERE DEFINITA: {base}() alla riga {riga} di {f}")
            bad = 1
            break
sys.exit(bad)
