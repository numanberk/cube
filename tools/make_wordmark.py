#!/usr/bin/env python3
"""Writes the "Cube Idle" brand art (task V.9) into assets/images/brand/:

  wordmark.svg  the name as outlines of Fredoka SemiBold (OFL) in the palette's text colour, with the green "Idle"
  icon.svg      a sticker cube (three faces, a real cube's colours) on a dark rounded tile: the window/taskbar icon

The name is text in one place (NAME / ACCENT below), so a new name (decision D2) is one edit and a re-run.
Needs fontTools (dev only, not part of the game):  pip install --target /tmp/pylib fonttools
then  PYTHONPATH=/tmp/pylib python3 tools/make_wordmark.py
"""
import os
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.boundsPen import BoundsPen

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets/fonts/FredokaVariable.ttf")
OUT = os.path.join(ROOT, "assets/images/brand")
NAME = "Cube Idle"
ACCENT = "Idle"          # this word is drawn in the buy green
TEXT = "#eceef2"         # Palette text
GREEN = "#3ccf8e"        # Palette buy
WEIGHT = 600


def wordmark() -> None:
    font = instantiateVariableFont(TTFont(FONT), {"wght": WEIGHT, "wdth": 100} if "wdth" in [a.axisTag for a in TTFont(FONT)["fvar"].axes] else {"wght": WEIGHT})
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    units = font["head"].unitsPerEm
    ascent = font["hhea"].ascent
    x = 0.0
    paths = []
    accent_from = NAME.index(ACCENT) if ACCENT in NAME else len(NAME)
    for i, ch in enumerate(NAME):
        name = cmap.get(ord(ch))
        if name is None:
            continue
        glyph = glyphs[name]
        if ch != " ":
            pen = SVGPathPen(glyphs)
            glyph.draw(pen)
            colour = GREEN if i >= accent_from else TEXT
            paths.append(f'<path transform="translate({x:.1f} {ascent}) scale(1 -1)" fill="{colour}" d="{pen.getCommands()}"/>')
        x += glyph.width
    height = ascent - font["hhea"].descent
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {x:.0f} {height}" width="{x / units * 96:.0f}" '
           f'height="{height / units * 96:.0f}">\n' + "\n".join(paths) + "\n</svg>\n")
    with open(os.path.join(OUT, "wordmark.svg"), "w") as f:
        f.write(svg)


def icon() -> None:
    # An isometric cube, a real cube's colours: the top face white, left green, right red, 3×3 stickers each, on a
    # dark rounded tile. F is the corner nearest the viewer, where the three faces meet (at the tile's centre).
    import math
    s = 30.0                                          # a sticker's edge
    dx, dy = math.cos(math.radians(30)) * s, math.sin(math.radians(30)) * s
    fx, fy = 128.0, 128.0
    up_right, up_left, down = (dx, -dy), (-dx, -dy), (0.0, s)

    def quad(u, v, i, j, inset=2.4):
        pts = []
        for a, b in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)):
            pts.append((fx + u[0] * a + v[0] * b, fy + u[1] * a + v[1] * b))
        mx = sum(p[0] for p in pts) / 4
        my = sum(p[1] for p in pts) / 4
        k = 1 - inset / s
        return " ".join(f"{mx + (px - mx) * k:.1f},{my + (py - my) * k:.1f}" for px, py in pts)

    outline = [(fx, fy - 6 * dy), (fx + 3 * dx, fy - 3 * dy), (fx + 3 * dx, fy - 3 * dy + 3 * s), (fx, fy + 3 * s),
               (fx - 3 * dx, fy - 3 * dy + 3 * s), (fx - 3 * dx, fy - 3 * dy)]
    shapes = ['<polygon fill="#0b0c10" stroke="#0b0c10" stroke-width="10" stroke-linejoin="round" points="%s"/>'
              % " ".join(f"{x:.1f},{y:.1f}" for x, y in outline)]
    for i in range(3):
        for j in range(3):
            shapes.append(f'<polygon fill="#f4f4f4" points="{quad(up_right, up_left, i, j)}"/>')
            shapes.append(f'<polygon fill="#009e60" points="{quad(up_left, down, i, j)}"/>')
            shapes.append(f'<polygon fill="#c41e3a" points="{quad(up_right, down, i, j)}"/>')
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">\n'
           '<rect x="8" y="8" width="240" height="240" rx="48" fill="#1b1e25"/>\n' + "\n".join(shapes) + "\n</svg>\n")
    with open(os.path.join(OUT, "icon.svg"), "w") as f:
        f.write(svg)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    wordmark()
    icon()
    print("Wrote", OUT)
