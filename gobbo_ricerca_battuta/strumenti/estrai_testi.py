#!/usr/bin/env python3
"""
estrai_testi.py — Estrattore di testi e gestore catalogo per ZP Studio Suite.
Trova testi visibili negli script Lua (drawstr, draw_button, MB, showmenu, OSARA, status, aiuti, T("..."))
e aggiorna o consulta il catalogo lang/en.txt senza doppioni.
"""

import sys
import os
import re
import argparse
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SUITE_DIR = REPO_ROOT / "ZP Studio Suite"
LANG_FILE = SUITE_DIR / "lang" / "en.txt"

# Stringhe o pattern da ignorare tassativamente
IGNORE_EXACT = {
    "", " ", "  ", "\t", "\n", "\r\n",
    "?", "!", "#", "-", "+", "x", "X", "<", ">", "|", "/", "\\", ":", ";", "=",
    "...", "…", "·", "•", "▲", "▼", "◄", "►",
    "Arial", "Calibri", "Helvetica", "Courier",
    "it", "en", "auto",
    "r", "w", "a", "rb", "wb",
    "GET", "SET", "OK",
}

IGNORE_PATTERNS = [
    r"^%[a-zA-Z0-9_#%.\-+ ]*$",           # solo segnaposto isolati tipo %s, %d
    r"^#[a-zA-Z0-9_]+$",                   # hashtag o marker servizio tipo #HSC
    r"^!.*",                               # marker azione REAPER
    r"^SOLO_[A-Z0-9_]+",                   # marker SOLO
    r"^ZP_[A-Z0-9_]+",                     # prefissi chiavi ExtState ZP
    r"^[A-Za-z0-9_]+/[A-Za-z0-9_]+",       # percorsi o chiavi tipo Sezione/Chiave
    r"^https?://.*",                       # URL
    r"^file://.*",                         # URL locali
    r"^\.[a-zA-Z0-9]+$",                   # estensioni tipo .lua, .wav
    r"^_[A-Za-z0-9_]+$",                   # comandi/ID REAPER tipo _S&M_...
    r"^[0-9]+$",                           # solo numeri
    r"^[0-9]+[a-z]?$",                     # numeri con suffisso
    r"^#[0-9a-fA-F]{3,8}$",                # colori hex
    r"^[a-f0-9]{32,40}$",                  # hash o GUID
]

def should_ignore(s: str) -> bool:
    s_strip = s.strip()
    if s in IGNORE_EXACT or s_strip in IGNORE_EXACT:
        return True
    if len(s_strip) <= 1:
        return True
    for pat in IGNORE_PATTERNS:
        if re.match(pat, s_strip):
            return True
    return False

def escape_catalog(s: str) -> str:
    return s.replace("\\", "\\\\").replace("\t", "\\t").replace("\r", "\\r").replace("\n", "\\n")

def unescape_catalog(s: str) -> str:
    res = []
    i = 0
    n = len(s)
    while i < n:
        if s[i] == "\\" and i + 1 < n:
            c = s[i+1]
            if c == "n": res.append("\n"); i += 2
            elif c == "t": res.append("\t"); i += 2
            elif c == "r": res.append("\r"); i += 2
            elif c == "\\": res.append("\\"); i += 2
            else: res.append(c); i += 2
        else:
            res.append(s[i])
            i += 1
    return "".join(res)

def load_catalog(path: Path) -> dict:
    catalog = {}
    if not path.exists():
        return catalog
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t", 1)
            if len(parts) == 2:
                k = unescape_catalog(parts[0])
                v = unescape_catalog(parts[1])
                catalog[k] = v
            elif len(parts) == 1:
                k = unescape_catalog(parts[0])
                catalog[k] = ""
    return catalog

def save_catalog(path: Path, catalog: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("# ZP Studio Suite — Catalogo Inglese (en.txt)\n")
        f.write("# Formato: originale<TAB>traduzione (una voce per riga, newline escapati con \\n)\n\n")
        for k in sorted(catalog.keys(), key=lambda x: x.lower()):
            v = catalog[k]
            f.write(f"{escape_catalog(k)}\t{escape_catalog(v)}\n")

# Pattern per estrazione stringhe mirate
RE_T_CALL = re.compile(r'\bT\s*\(\s*(?:"([^"\\]*(?:\\.[^"\\]*)*)"|\'([^\'\\]*(?:\\.[^\'\\]*)*)\')\s*\)')
RE_BUTTON = re.compile(r'draw_button\s*\([^,]+,\s*(?:"([^"\\]*(?:\\.[^"\\]*)*)"|\'([^\'\\]*(?:\\.[^\'\\]*)*)\')')
RE_DRAWSTR = re.compile(r'gfx\.drawstr\s*\(\s*(?:"([^"\\]*(?:\\.[^"\\]*)*)"|\'([^\'\\]*(?:\\.[^\'\\]*)*)\')')
RE_SHOWMENU = re.compile(r'gfx\.showmenu\s*\(\s*(?:"([^"\\]*(?:\\.[^"\\]*)*)"|\'([^\'\\]*(?:\\.[^\'\\]*)*)\')')
RE_MB = re.compile(r'(?:reaper\.)?(?:MB|ShowMessageBox)\s*\(\s*(?:"([^"\\]*(?:\\.[^"\\]*)*)"|\'([^\'\\]*(?:\\.[^\'\\]*)*)\')\s*,\s*(?:"([^"\\]*(?:\\.[^"\\]*)*)"|\'([^\'\\]*(?:\\.[^\'\\]*)*)\')')
RE_OSARA = re.compile(r'(?:osara_outputMessage|speak)\s*\(\s*(?:"([^"\\]*(?:\\.[^"\\]*)*)"|\'([^\'\\]*(?:\\.[^\'\\]*)*)\')')
RE_TEXT_PROP = re.compile(r'\b(?:text|label|title|tip|tooltip|status|suggerimento|msg|desc|info)\s*=\s*(?:"([^"\\]*(?:\\.[^"\\]*)*)"|\'([^\'\\]*(?:\\.[^\'\\]*)*)\')')

def unescape_lua_lit(s: str) -> str:
    # converte escape base lua
    try:
        return s.encode('utf-8').decode('unicode_escape')
    except Exception:
        return s.replace('\\n', '\n').replace('\\t', '\t').replace('\\"', '"').replace("\\'", "'")

def extract_from_file(file_path: Path) -> set:
    found = set()
    try:
        content = file_path.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        print(f"Errore lettura {file_path}: {e}", file=sys.stderr)
        return found

    def add_match(m):
        for g in m.groups():
            if g is not None:
                txt = unescape_lua_lit(g)
                if not should_ignore(txt):
                    found.add(txt)

    # 1. Chiamate T("...")
    for m in RE_T_CALL.finditer(content):
        add_match(m)

    # 2. Pulsanti UI
    for m in RE_BUTTON.finditer(content):
        add_match(m)

    # 3. Disegno stringhe
    for m in RE_DRAWSTR.finditer(content):
        add_match(m)

    # 4. Message box
    for m in RE_MB.finditer(content):
        add_match(m)

    # 5. OSARA / Sintesi
    for m in RE_OSARA.finditer(content):
        add_match(m)

    # 6. Proprieta di testo / tabelle UI
    for m in RE_TEXT_PROP.finditer(content):
        add_match(m)

    # 7. Menu contestuali (spezza su | e toglie prefissi gfx.showmenu)
    for m in RE_SHOWMENU.finditer(content):
        raw = m.group(1) or m.group(2) or ""
        raw = unescape_lua_lit(raw)
        items = raw.split("|")
        for item in items:
            clean = re.sub(r'^[>!<#\s]+', '', item).strip()
            if not should_ignore(clean):
                found.add(clean)

    return found

def main():
    parser = argparse.ArgumentParser(description="Estrattore testi per ZP Studio Suite")
    parser.add_argument("--files", nargs="*", help="File specifici da analizzare (default: tutti i .lua della Suite)")
    parser.add_argument("--update", action="store_true", help="Aggiorna en.txt con le nuove voci trovate")
    parser.add_argument("--stats", action="store_true", help="Mostra statistiche catalogo")
    args = parser.parse_args()

    target_files = []
    if args.files:
        for f in args.files:
            p = Path(f)
            if not p.is_absolute():
                p = REPO_ROOT / p
            if p.exists() and p.is_file():
                target_files.append(p)
    else:
        # Tutti i .lua di ZP Studio Suite
        for p in SUITE_DIR.glob("*.lua"):
            if "backup" not in str(p):
                target_files.append(p)

    print(f"Scansione di {len(target_files)} file Lua...")
    all_found = set()
    per_file = {}
    for p in sorted(target_files):
        f_strings = extract_from_file(p)
        per_file[p.name] = len(f_strings)
        all_found.update(f_strings)

    catalog = load_catalog(LANG_FILE)
    already_in_catalog = set(catalog.keys())
    new_strings = all_found - already_in_catalog

    translated_count = sum(1 for k, v in catalog.items() if v.strip() != "")

    print("==================================================")
    print(f"Testi unici trovati negli script analizzati: {len(all_found)}")
    print(f"Voci gia presenti nel catalogo: {len(catalog)} (di cui tradotte: {translated_count})")
    print(f"Voci nuove da aggiungere: {len(new_strings)}")
    print("==================================================")

    for fname, count in per_file.items():
        if count > 0:
            print(f"  {fname}: {count} stringhe rilevate")

    if args.update and new_strings:
        for s in new_strings:
            catalog[s] = ""
        save_catalog(LANG_FILE, catalog)
        print(f"\nCatalogo aggiornato: {LANG_FILE} ({len(catalog)} voci totali)")

if __name__ == "__main__":
    main()
