"""Firma Lato Cardioide sulle guide HTML della ZP Studio Suite (stile "A · Carta", scelto da Paolo
il 2026-10-09): riga "Lato Cardioide · Strumenti" col marchio sopra il titolo, filetto terracotta sotto
la testata, piede "ZP Studio Suite · Sviluppata su un'idea di Paolo Balestri · Lato Cardioide".

Si rilancia senza danni: ogni pezzo sta fra commenti <!-- lc-... --> e viene sostituito.
Pagine nuove: basta rilanciarlo. Lancio dalla radice del repo:
    python3 gobbo_ricerca_battuta/strumenti/firma_help.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

HELP = Path("ZP Studio Suite/help")
SITO = "https://latocardioide.it/strumenti/"
LOGO = ('<svg class="lc-logo" viewBox="0 0 48 48" aria-hidden="true" fill="none">'
        '<circle cx="24" cy="24" r="23" stroke="#d8b37a" stroke-width="2" fill="#1e293b"/>'
        '<path d="M24 9 C16 9 11 15 11 22 C11 29 20 36 24 40 C28 36 37 29 37 22 C37 15 32 9 24 9 Z" '
        'stroke="#a33f28" stroke-width="2.5"/>'
        '<circle cx="24" cy="23" r="6.5" stroke="#d8b37a" stroke-width="1.5" stroke-dasharray="2 2"/>'
        '<circle cx="24" cy="23" r="2.5" fill="#f6f2e8"/></svg>')
CSS = """<style id="lc-firma">
.lc-testata{display:flex;align-items:center;gap:.5rem;margin:0 0 .4rem;font:600 .78rem/1.2 -apple-system,"Segoe UI",Helvetica,Arial,sans-serif;
  letter-spacing:.08em;text-transform:uppercase;color:#565F66}
.lc-testata a{color:inherit;text-decoration:none}.lc-testata a:hover{color:#A94F35}
.lc-logo{width:22px;height:22px;flex:none}
.lc-filetto{border:0;border-top:2px solid #A94F35;margin:.6rem 0 1.4rem}
.lc-piede{display:flex;align-items:center;gap:.6rem;margin:3rem 0 1rem;padding:.8rem 1rem;border:1px solid #CFCCC3;
  border-radius:6px;background:#FAF9F5;color:#37444E;font:.95rem/1.4 -apple-system,"Segoe UI",Helvetica,Arial,sans-serif}
.lc-piede a{color:#8F4630}
@media (prefers-color-scheme: dark){
  .lc-testata{color:#9aa4ac}.lc-piede{background:#1d2226;border-color:#2e3439;color:#c9cfd4}.lc-piede a{color:#d98b6f}
}
</style>"""
TXT = {
    "it": ("Strumenti", "Sviluppata su un'idea di Paolo Balestri"),
    "en": ("Tools", "Developed from an idea by Paolo Balestri"),
}


def strip_old(html: str) -> str:
    html = re.sub(r'<style id="lc-firma">.*?</style>\n?', "", html, flags=re.S)
    return re.sub(r"<!-- lc-(testata|filetto|piede) -->.*?<!-- /lc-\1 -->\n?", "", html, flags=re.S)


def sign(html: str, lang: str) -> str:
    strumenti, idea = TXT[lang]
    html = strip_old(html)
    # vecchio piede dell'indice ("ZP Studio Suite for REAPER · Paolo Balestri · latocardioide.it ...")
    html = re.sub(r'\s*<p class="small">ZP Studio Suite for REAPER &middot; Paolo Balestri.*?</p>', "", html, flags=re.S)
    html = html.replace("</head>", CSS + "\n</head>", 1)
    testata = (f'<!-- lc-testata --><div class="lc-testata">{LOGO}<a href="{SITO}">Lato Cardioide</a>'
               f' &middot; {strumenti}</div><!-- /lc-testata -->\n')
    html = re.sub(r"(<h1[\s>])", testata + r"\1", html, count=1)
    # filetto dopo il titolo, o dopo il sottotitolo (occhiello) se viene subito dopo
    filetto = '<!-- lc-filetto --><hr class="lc-filetto"><!-- /lc-filetto -->\n'
    m = re.search(r"</h1>\s*(<p class=\"occhiello\">.*?</p>)?", html, flags=re.S)
    if m:
        html = html[:m.end()] + filetto + html[m.end():]
    piede = (f'<!-- lc-piede --><p class="lc-piede">{LOGO}<span>ZP Studio Suite &middot; {idea} &middot; '
             f'<a href="{SITO}">Lato Cardioide</a></span></p><!-- /lc-piede -->\n')
    i = html.rfind("</main>")
    return html[:i] + piede + html[i:] if i >= 0 else html


def main() -> int:
    pages = [(p, "it") for p in sorted(HELP.glob("*.html"))] + [(p, "en") for p in sorted((HELP / "en").glob("*.html"))]
    for page, lang in pages:
        text = page.read_text(encoding="utf-8")
        new = sign(text, lang)
        if new != text:
            page.write_text(new, encoding="utf-8")
        print(f"{page}: {'firmata' if new != text else 'gia a posto'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
