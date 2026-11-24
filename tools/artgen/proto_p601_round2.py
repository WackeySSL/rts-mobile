#!/usr/bin/env python3
"""P601 round 2 previews: tank SVG at L3 vs the richer L4 (gradients, fixed orange, team marker) at
four zooms, and the building three ways (artgen SVG, artgen PNG bake, Figma vector drawing).
Usage: python3 proto_p601_round2.py SCRATCH_DIR OUT_DIR round2 (the third word only selects this mode)"""
import json
import os
import sys

from PIL import Image

sys.argv = sys.argv[:3] + ["r2"]
import proto_p601_preview as pv  # noqa: E402

S, OUT = pv.S, pv.OUT
os.makedirs(OUT, exist_ok=True)
ZOOMS4 = [("far 0.75", 0.75), ("default 1.0", 1.0), ("closest 1.5", 1.5), ("new 2.25", 2.25)]


def small(img, path, colours=200):
    img.convert("RGB").quantize(colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(path, optimize=True)


def tank_rows():
    rows = []
    variants = [("current", "tank", "cur"), ("round 1 (L3)", "tank", "svg"), ("round 2 (L4)", "tank2", "svg")]
    box = (230, 170)
    for name, model, var in variants:
        row = []
        for zn, z in ZOOMS4:
            big = pv.scene(model, var, z, (int(box[0] * z * 2.4), int(box[1] * z * 2.4)))
            row.append(pv.label(pv.crop_centre(big, int(box[0] * z), int(box[1] * z), int(-14 * z)), f"{name} / {zn}"))
        rows.append(row)
    return rows


def figma_scene(zoom, size):
    centre = (size[0] // 2, size[1] // 2 + int(8 * zoom))
    img = pv.ground(size, centre, zoom)
    f = Image.open(f"{S}/figma_hq_{round(zoom * 100)}.png").convert("RGBA")
    pv.put(img, f, (220, 250), centre, zoom) if zoom in (1.0, 2.25) else None
    return img


def hq_row(zoom):
    box = (470, 320)
    size = (int(box[0] * zoom * 1.5), int(box[1] * zoom * 1.5))
    cells = []
    for name, var in (("current", "cur"), ("artgen SVG", "svg"), ("artgen PNG bake", "png")):
        cells.append(pv.label(pv.crop_centre(pv.scene("hq", var, zoom, size), int(box[0] * zoom), int(box[1] * zoom), int(-40 * zoom)), f"{name} / {zoom}"))
    cells.append(pv.label(pv.crop_centre(figma_scene(zoom, size), int(box[0] * zoom), int(box[1] * zoom), int(-40 * zoom)), f"Figma vector / {zoom}"))
    return cells


if __name__ == "__main__":
    rows = tank_rows()
    small(pv.grid(rows), f"{OUT}/tank_round2_zoom_levels.png")
    z = 2.25
    big = pv.scene("tank2", "svg", z, (int(260 * z * 1.5), int(200 * z * 1.5)))
    small(pv.crop_centre(big, int(260 * z), int(200 * z), int(-20 * z)), f"{OUT}/tank_round2_large_2_25.png", 256)
    for zoom in (1.0, 2.25):
        small(pv.grid([hq_row(zoom)]), f"{OUT}/hq_three_ways_{str(zoom).replace('.', '_')}.png")
