#!/usr/bin/env python3
"""Sincronizzazione della lingua per il telecomando SOLO Web (zp_solo.html).

Legge le voci usate dalla pagina web, le assicura nel catalogo centrale
ZP Studio Suite/lang/en.txt, ed inietta in ZP Studio Suite/web/zp_solo.html
il blocco JavaScript <script id="zp-lingua">const ZP_EN = {...}</script>
delimitato da commenti marcatori <!-- zp-lingua --> ... <!-- /zp-lingua -->.

Rilanciabile senza danni (idempotente).
Lancio:
    python3 gobbo_ricerca_battuta/strumenti/lingua_web.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
CATALOGO_FILE = ROOT / "ZP Studio Suite" / "lang" / "en.txt"
HTML_FILE = ROOT / "ZP Studio Suite" / "web" / "zp_solo.html"

# Frasi usate dal telecomando Web (HTML, ARIA, messaggi dinamici del motore)
WEB_TEXTS: dict[str, str] = {
    # UI statica & accessibilità
    "Motore spento: in REAPER avvia l'azione <b>ZP_SOLO_Web_Motore</b> (Action List). Finché non parte, i comandi non arrivano.": (
        "Engine offline: in REAPER launch the action <b>ZP_SOLO_Web_Motore</b> (Action List). Until running, commands will not arrive."
    ),
    "Salva progetto": "Save project",
    "Annulla": "Undo",
    "Ripeti": "Redo",
    "motore…": "engine…",
    "motore acceso": "engine online",
    "motore spento": "engine offline",
    "Condividi: indirizzo per aprire questa pagina da un altro dispositivo": (
        "Share: address to open this page from another device"
    ),
    "Telecomando": "Remote",
    "Traccia: — · Regione: — · Pre-roll: —": "Track: — · Region: — · Pre-roll: —",
    "Traccia: ": "Track: ",
    "nessuna traccia armata": "no armed track",
    "Regione: ": "Region: ",
    "Pre-roll %d s": "Pre-roll %d s",
    "Pre-roll off": "Pre-roll off",
    "Pre-roll: serve SWS": "Pre-roll: SWS required",
    "Apri il SOLO da un altro dispositivo (iPad, telefono, altro computer)": (
        "Open SOLO from another device (iPad, phone, other computer)"
    ),
    "Condividi": "Share",
    "Funziona sulla stessa rete Wi-Fi o cablata. Chi ha questo indirizzo puo' comandare REAPER: se la rete non e' solo tua, metti una password in REAPER, Preferences › Control/OSC/web › Web browser interface.": (
        "Works on the same Wi-Fi or wired network. Anyone with this address can control REAPER: if the network is not private, set a password in REAPER, Preferences › Control/OSC/web › Web browser interface."
    ),
    "Nessun indirizzo di rete trovato: il computer e' collegato a una rete?": (
        "No network address found: is the computer connected to a network?"
    ),
    "Copia": "Copy",
    "Copiato": "Copied",
    "Trasporto": "Transport",
    "Indietro di 5 secondi": "Back 5 seconds",
    "-5s": "-5s",
    "Registra": "Record",
    "REC": "REC",
    "Pre-roll acceso o spento": "Pre-roll on or off",
    "PRE": "PRE",
    "Stop": "Stop",
    "STOP": "STOP",
    "Pausa, anche della registrazione": "Pause, including recording",
    "PAUSA": "PAUSE",
    "Play": "Play",
    "PLAY": "PLAY",
    "Dopo l'ultimo item più 5 secondi": "After last item plus 5 seconds",
    "fine +5s": "end +5s",
    "Ingresso e ascolto": "Input & monitoring",
    "Livello ingresso": "Input level",
    "Livello ritorno": "Return level",
    "Secondi del pre-roll": "Pre-roll seconds",
    "Meno un secondo": "Minus one second",
    "Più un secondo": "Plus one second",
    "Vai a e segna": "Go to & mark",
    "Metti marker qui": "Place marker here",
    "Nome marker… (Invio)": "Marker name… (Enter)",
    "Nome del marker, vuoto per numerato": "Marker name, empty for numbered",
    "Timeline": "Timeline",
    "tutto il progetto": "entire project",
    "Zoom della timeline": "Timeline zoom",
    "Allontana: mostra piu' tempo": "Zoom out: show more time",
    "Avvicina: mostra meno tempo, piu' dettagli": "Zoom in: show less time, more details",
    "Mostra tutto il progetto": "Show entire project",
    "Tutto": "All",
    "Timeline: tocca un punto per portarci il cursore": "Timeline: tap a point to position the cursor",
    "non disponibile": "not available",
    "%s visibili, da %s": "%s visible, from %s",
    "❚❚ REC in pausa — %s": "❚❚ REC paused — %s",
    "● REC — %s": "● REC — %s",
    "Sviluppata su un'idea di Paolo Balestri": "Developed from an idea by Paolo Balestri",
    "ZP Studio Suite": "ZP Studio Suite",
    "Lato Cardioide": "Lato Cardioide",

    # Messaggi di stato dal motore
    "Motore web acceso": "Web engine online",
    "Marker: %s": "Marker: %s",
    "REAPER sta gia' registrando.": "REAPER is already recording.",
    "REC bloccato: nessuna traccia armata nel progetto.": "REC blocked: no armed track in the project.",
    "REC su %s": "REC on %s",
    "REC ripreso": "REC resumed",
    "REC in pausa: PLAY o PAUSA per riprendere, STOP per chiudere": (
        "REC paused: PLAY or PAUSE to resume, STOP to close"
    ),
    "Indietro 5 s": "Back 5 s",
    "Dopo l'ultimo item + 5 s": "After last item + 5 s",
    "Nessun item: cursore a 0": "No items: cursor at 0",
    "Il pre-roll in secondi richiede SWS.": "Pre-roll in seconds requires SWS.",
    "Pre-roll acceso, %d s": "Pre-roll on, %d s",
    "Pre-roll spento": "Pre-roll off",
    "Pre-roll: %d s": "Pre-roll: %d s",
    "Posizione non valida": "Invalid position",
    "Vai a %s": "Go to %s",
    "Progetto salvato": "Project saved",
    "Errore nel comando %s: %s": "Error in command %s: %s",
    "Comando sconosciuto: %s": "Unknown command: %s",
    "nessun ingresso": "no input",
}


def carica_catalogo(path: Path) -> dict[str, str]:
    cat: dict[str, str] = {}
    if not path.is_file():
        return cat
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t", 1)
            if len(parts) == 2:
                cat[parts[0]] = parts[1]
    return cat


def aggiorna_catalogo(path: Path, nuove_voci: dict[str, str]) -> int:
    esistenti = carica_catalogo(path)
    aggiunte = 0
    with open(path, "a", encoding="utf-8") as f:
        for it, en in nuove_voci.items():
            if it not in esistenti:
                f.write(f"{it}\t{en}\n")
                esistenti[it] = en
                aggiunte += 1
    return aggiunte


def genera_blocco_script(dizionario: dict[str, str]) -> str:
    # Genera JSON formattato a 2 spazi
    json_lines = json.dumps(dizionario, indent=2, ensure_ascii=False)
    # Rientra di 2 spazi
    lines = ["<!-- zp-lingua -->", '<script id="zp-lingua">', f"const ZP_EN = {json_lines};", "</script>", "<!-- /zp-lingua -->"]
    return "\n".join(lines)


def inietta_nello_html(html_path: Path, blocco_js: str) -> bool:
    content = html_path.read_text(encoding="utf-8")
    marcatore = r"<!-- zp-lingua -->.*?<!-- /zp-lingua -->"
    if re.search(marcatore, content, flags=re.S):
        new_content = re.sub(marcatore, blocco_js, content, flags=re.S)
    else:
        # Inserisci appena prima del tag <script> principale
        m = re.search(r"<script>", content)
        if m:
            idx = m.start()
            new_content = content[:idx] + blocco_js + "\n" + content[idx:]
        else:
            # Fallback prima di </body>
            new_content = content.replace("</body>", blocco_js + "\n</body>")
    
    if new_content != content:
        html_path.write_text(new_content, encoding="utf-8")
        return True
    return False


def main() -> int:
    print(f"Catalogo: {CATALOGO_FILE}")
    agg = aggiorna_catalogo(CATALOGO_FILE, WEB_TEXTS)
    if agg > 0:
        print(f"Aggiunte {agg} nuove voci al catalogo en.txt")
    else:
        print("Tutte le voci del web sono gia' presenti nel catalogo en.txt")

    cat_completo = carica_catalogo(CATALOGO_FILE)
    diz_web: dict[str, str] = {}
    mancanti = []
    for k in WEB_TEXTS:
        if k in cat_completo and cat_completo[k]:
            diz_web[k] = cat_completo[k]
        else:
            mancanti.append(k)

    if mancanti:
        print(f"ATTENZIONE: {len(mancanti)} voci mancanti nel catalogo!")
        for m in mancanti:
            print(f"  - {m}")
        return 1

    blocco = genera_blocco_script(diz_web)
    modificato = inietta_nello_html(HTML_FILE, blocco)
    if modificato:
        print(f"Aggiornato {HTML_FILE} con {len(diz_web)} traduzioni ZP_EN.")
    else:
        print(f"{HTML_FILE} gia' aggiornato con il blocco lingua.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
