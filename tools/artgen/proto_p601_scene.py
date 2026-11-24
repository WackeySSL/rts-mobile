#!/usr/bin/env python3
"""P601 / P637: the same desert scene three times, only the Facet building changes:
(a) artgen SVG, (b) Figma vector drawing, (c) Figma AI picture (hand-fitted). Each scene holds the
building, a Nordvaern works from artgen and three L4 tanks, on one ground, in one light, at zoom 1.0
and 2.0. Usage: python3 proto_p601_scene.py SCRATCH_DIR OUT_DIR"""
import json
import os
import sys

from PIL import Image, ImageDraw

sys.argv = sys.argv[:3] + ["r2"]
import proto_p601_preview as pv  # noqa: E402

S, OUT = pv.S, pv.OUT
os.makedirs(OUT, exist_ok=True)
load = pv.load


def sprite(path, origin, at, zoom, img):
    pv.put(img, load(path), origin, at, zoom)


def manifest(name):
    return json.load(open(f"{S}/{name}_manifest.json"))


M_TANK, M_NORD, M_HQ = manifest("tank2"), manifest("nord"), manifest("hq")
DIRS = {"t1": 6, "t2": 4, "t3": 10}  # three tanks, three headings
LAYOUT = {  # ground points in tiles (footprint centres for buildings)
    "hq": (0.0, 0.0),
    "nord": (4.2, -1.1),
    "t1": (2.6, 1.9),
    "t2": (3.6, 3.1),
    "t3": (-2.5, 2.2),
}


def screen(g, c, z):
    return (c[0] + (g[0] - g[1]) * 64 * z, c[1] + (g[0] + g[1]) * 32 * z)


def tank_parts(key, z, c):
    d = DIRS[key]
    sc = round(z * 100)
    at = screen(LAYOUT[key], c, z)
    lay = M_TANK["proto"]["layouts"]
    mo = M_TANK["proto"]["mount"][str(d)]
    parts = [
        (f"{S}/png/L4/tank2_hull_d{d:02d}_s{sc}.png", lay["hull"]["origin"], at),
        (
            f"{S}/png/L4/tank2_turret_d{d:02d}_s{sc}.png",
            lay["turret"]["origin"],
            (at[0] + mo[0] * z, at[1] + mo[1] * z),
        ),
    ]
    shadow = (f"{S}/png/L4/tank2_shadow_d{d:02d}_s{sc}.png", lay["shadow"]["origin"], at)
    return shadow, parts


def render(variant, z, size=(960, 520)):
    W, H = int(size[0] * z), int(size[1] * z)
    c = (380 * z, 200 * z)
    img = pv.ground((W, H), (round(c[0]), round(c[1])), z, n=9)
    sc = round(z * 100)
    shadows, objs = [], []
    # Nordvaern works
    nat = screen(LAYOUT["nord"], c, z)
    lay = M_NORD["proto"]["layouts"]
    shadows.append((f"{S}/png/L4/nord_shadow_d00_s{sc}.png", lay["shadow"]["origin"], nat))
    objs.append((sum(LAYOUT["nord"]), [(f"{S}/png/L4/nord_hull_d00_s{sc}.png", lay["hull"]["origin"], nat)]))
    # Facet building, three ways
    hat = screen(LAYOUT["hq"], c, z)
    hl = M_HQ["proto"]["layouts"]
    if variant == "a":
        shadows.append((f"{S}/png/L3/hq_shadow_d00_s{sc}.png", hl["shadow"]["origin"], hat))
        objs.append((0, [(f"{S}/png/L3/hq_hull_d00_s{sc}.png", hl["hull"]["origin"], hat)]))
    elif variant == "b":
        objs.append((0, [(f"{S}/figma_hq_{sc}.png", (220 * z, 250 * z), hat, True)]))
    else:
        meta = json.load(open(f"{S}/ai_hq_{sc}.png.json"))
        # no cast shadow came with the picture: borrow the artgen shadow of the same footprint
        shadows.append((f"{S}/png/L3/hq_shadow_d00_s{sc}.png", hl["shadow"]["origin"], hat))
        objs.append((0, [(f"{S}/ai_hq_{sc}.png", meta["origin"], hat, True)]))
    for key in ("t1", "t2", "t3"):
        sh, parts = tank_parts(key, z, c)
        shadows.append(sh)
        objs.append((sum(LAYOUT[key]), parts))
    for p, o, at in shadows:
        pv.paste_clip(img, load(p), round(at[0] - o[0] * z), round(at[1] - o[1] * z))
    for _, parts in sorted(objs, key=lambda t: t[0]):
        for part in parts:
            p, o, at = part[0], part[1], part[2]
            raw = len(part) > 3  # origin already in px of this scale
            ox, oy = (o[0], o[1]) if raw else (o[0] * z, o[1] * z)
            pv.paste_clip(img, load(p), round(at[0] - ox), round(at[1] - oy))
    return img.convert("RGB")


def small(img, path, colours=224):
    img.quantize(colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(path, optimize=True)


if __name__ == "__main__":
    names = {"a": "scene_a_svg", "b": "scene_b_figma_vector", "c": "scene_c_figma_ai"}
    for z, tag in ((1.0, "1_0"), (2.0, "2_0")):
        shots = {}
        for v, n in names.items():
            shots[v] = render(v, z)
            small(shots[v], f"{OUT}/{n}_{tag}.png")
        # side-by-side sheet: a | b | c, cropped to the Facet building and the tanks at 2.0
        crop = (int(40 * z), 0, int(740 * z), int(520 * z)) if z > 1.0 else None
        cells = [shots[v].crop(crop) if crop else shots[v] for v in "abc"]
        for im, lab in zip(cells, ("(a) artgen SVG", "(b) Figma vector", "(c) Figma AI")):
            d = ImageDraw.Draw(im)
            d.rectangle([0, 0, 8 + 6 * len(lab), 14], fill=(0, 0, 0))
            d.text((4, 2), lab, fill=(255, 255, 255))
        sheet = Image.new("RGB", (sum(c.width for c in cells) + 8, cells[0].height), (20, 22, 24))
        x = 0
        for im in cells:
            sheet.paste(im, (x, 0))
            x += im.width + 4
        small(sheet, f"{OUT}/sheet_{tag}.png")
