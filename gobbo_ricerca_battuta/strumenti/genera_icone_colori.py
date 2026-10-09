"""Icone della toolbar ZP Colori.

- ZP_tbC_01..20: un quadrato pieno del colore della palette (ZP_Colori.lua). Bordo scuro sottile,
  chiaro col mouse sopra.
- ZP_tbC_Item / Traccia / Tutto / Togli: stile B come la toolbar ZP (riquadro scuro, disegno chiaro,
  bordo verde acqua quando il modo e' acceso).
Genera icons/ZP_tbC_*.png (90x30: normale, mouse sopra, acceso) e icons/200/ (180x60).
Lancio dalla radice del repo:  python3 gobbo_ricerca_battuta/strumenti/genera_icone_colori.py
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from genera_icone_toolbar_B import ICONS, INK, LW, S, bar, make_strip  # noqa: E402

# stessa palette di ZP Studio Suite/ZP_Colori.lua (M.PALETTE)
PALETTE = [
    "9eea64", "e2e093", "ecac6b", "e686b2", "d38ce6", "6f6aee", "4a79f4", "6ccced",
    "81e5bd", "7fe57d", "ebd46e", "e99577", "caa6e0", "70c1ec", "7de6d8", "c5df9c",
    "ffffff", "000000", "808080", "ff1a1a",
]
SWATCH_BORDER = ((40, 44, 48, 255), (240, 244, 244, 255), (26, 188, 152, 255))


def wave(d, x0, x1, yc, amp):     # forma d'onda: barrette di altezza diversa
    heights = (0.35, 0.7, 1.0, 0.55, 0.85, 0.4, 0.95, 0.6, 0.3)
    step = (x1 - x0) / (len(heights) - 1)
    for i, h in enumerate(heights):
        x = x0 + i * step
        d.rounded_rectangle([x - 5, yc - amp * h, x + 5, yc + amp * h], radius=4, fill=INK)


def g_item(d):                    # item: riquadro con la forma d'onda
    d.rounded_rectangle([52, 72, 188, 168], radius=12, outline=INK, width=LW - 2)
    wave(d, 74, 166, 120, 34)


def g_traccia(d):                 # tracce: tre righe con la testata a sinistra
    for i in range(3):
        y = 66 + i * 40
        bar(d, 52, y, 82, y + 26, 5)
        bar(d, 92, y + 8, 188, y + 18, 4)


def g_tutto(d):                   # traccia + item: testata a sinistra, item con onda a destra
    bar(d, 50, 60, 84, 180, 6)
    d.rounded_rectangle([96, 60, 190, 180], radius=12, outline=INK, width=LW - 2)
    wave(d, 114, 172, 120, 40)


def g_togli(d):                   # quadratino vuoto barrato
    d.rounded_rectangle([64, 64, 176, 176], radius=14, outline=INK, width=LW)
    d.line([(76, 164), (164, 76)], fill=INK, width=LW + 2)


GLYPHS = {"ZP_tbC_Item": g_item, "ZP_tbC_Traccia": g_traccia, "ZP_tbC_Tutto": g_tutto, "ZP_tbC_Togli": g_togli}


def swatch_strip(hexcol: str, cell: int) -> Image.Image:
    rgb = tuple(int(hexcol[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
    border = SWATCH_BORDER
    if sum(rgb[:3]) < 200:            # nero: bordo grigio, se no sparisce sulla toolbar scura
        border = ((128, 134, 138, 255),) + SWATCH_BORDER[1:]
    strip = Image.new("RGBA", (cell * 3, cell), (0, 0, 0, 0))
    for state in range(3):
        c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(c).rounded_rectangle([10, 10, S - 11, S - 11], radius=30, fill=rgb,
                                            outline=border[state], width=8 if state == 0 else 16)
        strip.paste(c.resize((cell, cell), Image.LANCZOS), (state * cell, 0))
    return strip


def main() -> int:
    os.makedirs(os.path.join(ICONS, "200"), exist_ok=True)
    for i, hexcol in enumerate(PALETTE, 1):
        name = f"ZP_tbC_{i:02d}.png"
        swatch_strip(hexcol, 30).save(os.path.join(ICONS, name))
        swatch_strip(hexcol, 60).save(os.path.join(ICONS, "200", name))
    for name, glyph in GLYPHS.items():
        make_strip(glyph, 30).save(os.path.join(ICONS, name + ".png"))
        make_strip(glyph, 60).save(os.path.join(ICONS, "200", name + ".png"))
    print(f"{len(PALETTE) + len(GLYPHS)} icone in {ICONS} e {ICONS}/200")
    return 0


if __name__ == "__main__":
    sys.exit(main())
