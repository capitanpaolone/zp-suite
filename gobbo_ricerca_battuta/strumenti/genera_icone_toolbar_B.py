"""Icone della toolbar ZP in stile B, disegnate da zero (nessuna icona di REAPER dentro).

Riquadro scuro con disegno chiaro; il disegno non cambia mai, cambia solo il BORDO:
grigio = spento, chiaro = mouse sopra, verde acqua = acceso (finestra aperta). SOLO Recorder ha la sua.
Genera icons/ZP_tbB_*.png (90x30: normale, mouse sopra, acceso) e icons/200/ (180x60).
Lancio dalla radice del repo:  python3 gobbo_ricerca_battuta/strumenti/genera_icone_toolbar_B.py
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw, ImageFont

ICONS = "ZP Studio Suite/icons"
S = 240                       # tela di lavoro (4x di 60): disegno grande e riduco, bordi morbidi
INK = (222, 228, 228, 255)    # colore del disegno, uguale in tutti gli stati
BORDER = ((112, 122, 124, 255), (210, 216, 216, 255), (26, 188, 152, 255))
FILL = (30, 36, 40, 255)
LW = 13                       # spessore del tratto sulla tela da 240


def frame_box() -> tuple[float, float, float, float]:
    return 46, 46, S - 46, S - 46          # area utile del disegno dentro il riquadro


def line(d, pts, w=LW):
    d.line(pts, fill=INK, width=w, joint="curve")
    for x, y in (pts[0], pts[-1]):
        d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=INK)


def bar(d, x0, y0, x1, y1, r=6):
    d.rounded_rectangle([x0, y0, x1, y1], radius=r, fill=INK)


def arrow_head(d, x, y, direction, size=22):
    if direction == "down":
        d.polygon([(x - size, y - size), (x + size, y - size), (x, y + 4)], fill=INK)
    elif direction == "up":
        d.polygon([(x - size, y + size), (x + size, y + size), (x, y - 4)], fill=INK)
    elif direction == "right":
        d.polygon([(x - size, y - size), (x - size, y + size), (x + 4, y)], fill=INK)
    elif direction == "left":
        d.polygon([(x + size, y - size), (x + size, y + size), (x - 4, y)], fill=INK)


def g_project_viewer(d):          # panoramica: tre tracce con item
    for i, (a, b) in enumerate(((60, 150), (95, 185), (70, 120))):
        y = 72 + i * 36
        bar(d, a, y, b, y + 20)
    d.rectangle([52, 64, 54 + 4, 176], fill=INK)


def g_gestore(d):                 # regioni: parentesi con blocchi dentro
    line(d, [(78, 66), (60, 66), (60, 174), (78, 174)])
    line(d, [(162, 66), (180, 66), (180, 174), (162, 174)])
    bar(d, 84, 104, 112, 136, 4)
    bar(d, 128, 104, 156, 136, 4)


def g_report(d):                  # cronometro: minuti voce
    d.ellipse([66, 78, 174, 186], outline=INK, width=LW)
    line(d, [(120, 132), (120, 100)])
    line(d, [(120, 132), (144, 146)])
    bar(d, 108, 54, 132, 66, 4)
    line(d, [(166, 88), (178, 76)])


def g_trascrizione(d):            # voce -> testo: forma d'onda e righe
    xs = [58, 70, 82, 94, 106]
    hs = [24, 56, 80, 48, 30]
    for x, h in zip(xs, hs):
        line(d, [(x, 120 - h / 2), (x, 120 + h / 2)], w=10)
    arrow_head(d, 130, 120, "right", 12)
    for i, w in enumerate((48, 40, 48)):
        y = 92 + i * 26
        bar(d, 140, y, 140 + w, y + 12, 5)


def g_gobbo_v(d):                 # pagina con righe che scorre in verticale
    d.rounded_rectangle([58, 56, 150, 184], radius=10, outline=INK, width=LW)
    for i, w in enumerate((58, 46, 58, 36)):
        y = 82 + i * 24
        bar(d, 76, y, 76 + w, y + 10, 4)
    line(d, [(178, 76), (178, 164)], w=11)
    arrow_head(d, 178, 64, "up", 16)
    arrow_head(d, 178, 176, "down", 16)


def g_gobbo_o(d):                 # banda che scorre in orizzontale (rythmo)
    d.rounded_rectangle([52, 84, 188, 140], radius=10, outline=INK, width=LW)
    for x0, x1 in ((70, 110), (122, 170)):
        bar(d, x0, 106, x1, 118, 4)
    line(d, [(70, 172), (170, 172)], w=11)
    arrow_head(d, 182, 172, "right", 16)
    arrow_head(d, 58, 172, "left", 16)


def g_importa(d):                 # cartella con freccia in giu'
    d.polygon([(54, 98), (54, 184), (186, 184), (186, 108), (118, 108), (104, 92), (60, 92)],
              outline=INK, width=LW)
    line(d, [(120, 52), (120, 142)])
    arrow_head(d, 120, 152, "down", 22)


def g_srt(d):                     # schermo con due righe di sottotitolo
    d.rounded_rectangle([50, 66, 190, 166], radius=14, outline=INK, width=LW)
    bar(d, 76, 120, 164, 132, 5)
    bar(d, 94, 142, 146, 152, 5)
    d.polygon([(106, 166), (134, 166), (120, 184)], fill=INK)


def g_marker(d):                  # bandierina su asta
    line(d, [(78, 56), (78, 188)])
    d.polygon([(84, 60), (178, 84), (84, 112)], fill=INK)
    line(d, [(60, 188), (110, 188)])


def g_actor(d):                   # persona (actor) con fumetto nota
    d.ellipse([70, 66, 122, 118], outline=INK, width=LW)
    d.chord([46, 128, 146, 228], 180, 360, outline=INK, width=LW)
    d.rounded_rectangle([142, 58, 192, 96], radius=8, fill=INK)
    d.polygon([(150, 94), (166, 94), (148, 110)], fill=INK)


def g_cleaner(d):                 # forma d'onda con forbici sul silenzio
    for x, h in zip((56, 68, 80, 92), (40, 72, 52, 28)):
        line(d, [(x, 120 - h / 2), (x, 120 + h / 2)], w=10)
    line(d, [(108, 120), (128, 120)], w=6)
    d.ellipse([136, 70, 168, 102], outline=INK, width=11)
    d.ellipse([136, 138, 168, 170], outline=INK, width=11)
    line(d, [(162, 98), (190, 140)], w=11)
    line(d, [(162, 142), (190, 100)], w=11)


def g_chain(d):                   # catena di effetti: tre blocchi collegati
    for x in (46, 100, 154):
        d.rounded_rectangle([x, 88, x + 40, 152], radius=9, outline=INK, width=LW)
    line(d, [(86, 120), (100, 120)], w=LW)
    line(d, [(140, 120), (154, 120)], w=LW)


def g_video(d):                   # schermo con play
    d.rounded_rectangle([50, 66, 190, 170], radius=14, outline=INK, width=LW)
    d.polygon([(106, 92), (106, 144), (148, 118)], fill=INK)


def g_video_sfondo(d):            # due schermi: video del progetto sullo sfondo
    d.rounded_rectangle([86, 54, 192, 136], radius=12, outline=INK, width=LW - 2)
    d.rounded_rectangle([48, 104, 154, 186], radius=12, fill=FILL, outline=INK, width=LW)
    d.polygon([(88, 126), (88, 166), (120, 146)], fill=INK)


def g_probe(d):                   # scudo con segno di controllo
    d.polygon([(120, 52), (180, 74), (176, 132), (120, 188), (64, 132), (60, 74)],
              outline=INK, width=LW)
    line(d, [(92, 122), (114, 144), (152, 98)])


def g_help(d):                    # punto di domanda
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 150)
    except OSError:
        font = ImageFont.load_default()
    d.text((120, 124), "?", font=font, fill=INK, anchor="mm")


def g_tastiera(d):               # tastiera: riquadro con tre file di tasti e la barra spaziatrice
    d.rounded_rectangle([44, 74, 196, 168], radius=12, outline=INK, width=LW - 2)
    for row, (y, n, x0) in enumerate(((90, 6, 58), (112, 6, 66), (134, 1, 0))):
        if row < 2:
            for i in range(n):
                x = x0 + i * 21
                d.rounded_rectangle([x, y, x + 14, y + 13], radius=3, fill=INK)
        else:
            d.rounded_rectangle([82, 136, 158, 150], radius=4, fill=INK)


def g_colori(d):                  # tavolozza con quattro gocce di colore
    d.ellipse([46, 56, 194, 186], outline=INK, width=LW)
    d.ellipse([132, 128, 162, 158], fill=(30, 36, 40, 255), outline=INK, width=LW - 4)   # foro
    for (cx, cy), col in zip(((84, 98), (120, 80), (156, 98), (82, 140)),
                             ((158, 234, 100, 255), (236, 172, 107, 255),
                              (74, 121, 244, 255), (230, 134, 178, 255))):
        d.ellipse([cx - 14, cy - 14, cx + 14, cy + 14], fill=col)


GLYPHS = {
    "ZP_tbB_18_Project_Viewer": g_project_viewer,
    "ZP_tbB_17_Gestore_Progetto": g_gestore,
    "ZP_tbB_19_Report_Minuti": g_report,
    "ZP_tbB_29_Trascrizione": g_trascrizione,
    "ZP_tbB_02_Gobbo_Verticale": g_gobbo_v,
    "ZP_tbB_03_Gobbo_Orizzontale": g_gobbo_o,
    "ZP_tbB_20_Importa_Cartelle": g_importa,
    "ZP_tbB_30_ZP_SRT": g_srt,
    "ZP_tbB_04_Marker": g_marker,
    "ZP_tbB_07_Actor_Note": g_actor,
    "ZP_tbB_22_Voice_Cleaner": g_cleaner,
    "ZP_tbB_23_Chain_Builder": g_chain,
    "ZP_tbB_Video": g_video,
    "ZP_tbB_Video_Sfondo": g_video_sfondo,
    "ZP_tbB_24_Probe_Guard": g_probe,
    "ZP_tbB_00_Help": g_help,
    "ZP_tbB_34_Set_Comandi": g_tastiera,
    "ZP_tbB_35_Colori": g_colori,
}


def make_strip(glyph, cell: int) -> Image.Image:
    strip = Image.new("RGBA", (cell * 3, cell), (0, 0, 0, 0))
    for state in range(3):
        c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        d = ImageDraw.Draw(c)
        d.rounded_rectangle([8, 8, S - 9, S - 9], radius=36, fill=FILL, outline=BORDER[state],
                            width=16 if state == 2 else 12)
        glyph(d)
        strip.paste(c.resize((cell, cell), Image.LANCZOS), (state * cell, 0))
    return strip


def main() -> int:
    os.makedirs(os.path.join(ICONS, "200"), exist_ok=True)
    for name, glyph in GLYPHS.items():
        make_strip(glyph, 30).save(os.path.join(ICONS, name + ".png"))
        make_strip(glyph, 60).save(os.path.join(ICONS, "200", name + ".png"))
    print(f"{len(GLYPHS)} icone disegnate in {ICONS} e {ICONS}/200")
    return 0


if __name__ == "__main__":
    sys.exit(main())
