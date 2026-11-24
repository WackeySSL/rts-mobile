#!/usr/bin/env python3
"""P601 prototype: builds the compare sheet and the 32 px greyscale check, then writes the small
palette PNGs that are committed. Usage: python3 proto_p601_finish.py SCRATCH_DIR OUT_DIR"""
import os
import sys

from PIL import Image

S, OUT = sys.argv[1], sys.argv[2]
SRC = f"{S}/out"
os.makedirs(OUT, exist_ok=True)


def small(img, path, colours=192):
    img.convert("RGB").quantize(colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(path, optimize=True)


def opened(n):
    return Image.open(f"{SRC}/{n}").convert("RGB")


# side-by-side sheet: tank and building, current / prototype SVG / prototype PNG bake
a, b = opened("tank_large.png"), opened("hq_large.png")
w = max(a.width, b.width)
sheet = Image.new("RGB", (w, a.height + b.height + 6), (24, 26, 28))
sheet.paste(a, (0, 0))
sheet.paste(b, (0, a.height + 6))
small(sheet, f"{OUT}/compare_sheet.png")

# 32 px greyscale check: tank (default view) and building at 32 px wide, enlarged 6x (nearest)
row = []
for name, crop in (("tank_large.png", 0), ("hq_large.png", 0)):
    im = opened(name)
    third = im.width // 3
    for i in range(3):
        m = int(third * 0.1)
        part = im.crop((i * third + m, int(im.height * 0.18), (i + 1) * third - m, int(im.height * 0.9)))
        t = part.resize((32, max(1, round(part.height * 32 / part.width))), Image.Resampling.LANCZOS).convert("L")
        row.append(t.resize((t.width * 6, t.height * 6), Image.Resampling.NEAREST).convert("RGB"))
H = max(r.height for r in row)
gs = Image.new("RGB", (sum(r.width for r in row) + 6 * (len(row) + 1), H + 12), (24, 26, 28))
x = 6
for r in row:
    gs.paste(r, (x, 6))
    x += r.width + 6
small(gs, f"{OUT}/greyscale_32px.png", 64)

for n in os.listdir(SRC):
    if n.endswith(".png") and n != "tank_large.png":
        small(opened(n), f"{OUT}/{n}")
small(a, f"{OUT}/tank_large.png")
small(b, f"{OUT}/hq_large.png")
