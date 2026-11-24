#!/usr/bin/env python3
"""P601 prototype: composes the preview PNGs from gen_proto_p601.gd's scratch output and the PNG
bake. Usage: python3 proto_p601_preview.py SCRATCH_DIR OUT_DIR"""
import json
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import proto_p601_bake as bake  # noqa: E402

S = sys.argv[1]
OUT = sys.argv[2]
R2 = len(sys.argv) > 3
ZOOMS = [("far 0.75", 0.75), ("default 1.0", 1.0), ("closest 1.5", 1.5)]


def load(p):
    return Image.open(p).convert("RGBA")


def tile_img(name, scale):
    return load(f"{S}/png/ground/{name}_s{round(scale * 100)}.png")


def ground(canvas_wh, centre, scale, n=7):
    """Desert ground: sand with a rock patch, diamond grid; `centre` is the ground point in px."""
    img = Image.new("RGBA", canvas_wh, (0, 0, 0, 255))
    for gx in range(-n, n + 1):
        for gy in range(-n, n + 1):
            rock = (gx - gy) < -2 or (gx + gy) > 5 and (gx - gy) < 1
            name = ("rock_" if rock else "sand_") + ("a" if (gx * 7 + gy * 3) % 3 else "b")
            t = tile_img(name, scale)
            x = centre[0] + (gx - gy) * 64 * scale - 64 * scale
            y = centre[1] + (gx + gy) * 32 * scale - 32 * scale
            img.alpha_composite(t, (round(x), round(y))) if 0 <= x < canvas_wh[0] and 0 <= y < canvas_wh[1] else paste_clip(img, t, round(x), round(y))
    return img


def paste_clip(img, t, x, y):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    layer.paste(t, (x, y))
    img.alpha_composite(layer)


def put(img, im, origin, at, scale):
    x = round(at[0] - origin[0] * scale)
    y = round(at[1] - origin[1] * scale)
    paste_clip(img, im, x, y)


def scene(model_id, variant, zoom, size, dir_=6, turret_dir=None):
    m = json.load(open(f"{S}/{model_id}_manifest.json"))
    centre = (size[0] // 2, size[1] // 2 + int(8 * zoom))
    img = ground(size, centre, zoom)
    key = "cur" if variant == "cur" else "proto"
    lay = m[key]["layouts"]
    dd = 0 if model_id == "hq" else max(dir_, 0)
    td = dd if turret_dir is None else turret_dir
    sc = round(zoom * 100)
    folder = "cur" if variant == "cur" else ("L4" if model_id == "tank2" else "L3")
    shadow = load(f"{S}/png/{folder}/{model_id}_shadow_d{dd:02d}_s{sc}.png")
    put(img, shadow, lay["shadow"]["origin"], centre, zoom)
    if variant == "png":
        g = json.load(open(f"{S}/geom/{model_id}_hull_d{dd:02d}.json"))
        hull = bake_cached(model_id, "hull", dd, zoom)
    else:
        hull = load(f"{S}/png/{folder}/{model_id}_hull_d{dd:02d}_s{sc}.png")
    put(img, hull, lay["hull"]["origin"], centre, zoom)
    if "turret" in lay and m["parts"].count("turret"):
        if variant == "png":
            tur = bake_cached(model_id, "turret", td, zoom)
        else:
            tur = load(f"{S}/png/{folder}/{model_id}_turret_d{td:02d}_s{sc}.png")
        mo = m[key]["mount"][str(dd)]
        at = (centre[0] + mo[0] * zoom, centre[1] + mo[1] * zoom)
        put(img, tur, lay["turret"]["origin"], at, zoom)
    return img


_cache = {}


def bake_cached(model_id, part, d, zoom):
    k = (model_id, part, d, zoom)
    if k not in _cache:
        g = json.load(open(f"{S}/geom/{model_id}_{part}_d{d:02d}.json"))
        _cache[k] = bake.bake(g, zoom)
    return _cache[k]


def label(img, text):
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 8 + 6 * len(text), 14], fill=(0, 0, 0, 200))
    d.text((4, 2), text, fill=(255, 255, 255, 255))
    return img


def grid(rows, title_cols=None, pad=6):
    """rows: list of lists of images (variable size); bottom-aligned rows centred in cells."""
    colw = [max(r[c].width for r in rows if c < len(r)) for c in range(max(len(r) for r in rows))]
    rowh = [max(i.height for i in r) for r in rows]
    W = sum(colw) + pad * (len(colw) + 1)
    H = sum(rowh) + pad * (len(rows) + 1)
    sheet = Image.new("RGB", (W, H), (24, 26, 28))
    y = pad
    for r, rh in zip(rows, rowh):
        x = pad
        for c, im in enumerate(r):
            sheet.paste(im.convert("RGB"), (x + (colw[c] - im.width) // 2, y + (rh - im.height) // 2))
            x += colw[c] + pad
        y += rh + pad
    return sheet


def crop_centre(img, w, h, dy=0):
    x0 = (img.width - w) // 2
    y0 = (img.height - h) // 2 + dy
    return img.crop((x0, y0, x0 + w, y0 + h))


def zoom_sheet(model_id, box, name, dy=0):
    rows = []
    for variant, vname in (("cur", "current"), ("svg", "prototype SVG"), ("png", "prototype PNG bake")):
        row = []
        for zn, z in ZOOMS:
            big = scene(model_id, variant, z, (int(box[0] * z * 2.4), int(box[1] * z * 2.4)))
            c = crop_centre(big, int(box[0] * z), int(box[1] * z), int(dy * z))
            row.append(label(c, f"{vname} / {zn}"))
        rows.append(row)
    sh = grid(rows)
    sh.save(f"{OUT}/{name}", optimize=True)
    return sh


def large(model_id, box, name, dy=0, z=2.5):
    row = []
    for variant, vname in (("cur", "current"), ("svg", "prototype SVG"), ("png", "prototype PNG bake")):
        big = scene(model_id, variant, z, (int(box[0] * z * 1.5), int(box[1] * z * 1.5)))
        row.append(label(crop_centre(big, int(box[0] * z), int(box[1] * z), int(dy * z)), f"{vname} / 2.5x"))
    sh = grid([row])
    sh.save(f"{OUT}/{name}", optimize=True)


def png_single(model_id, box, name, variant, z=2.5, dy=0):
    big = scene(model_id, variant, z, (int(box[0] * z * 1.5), int(box[1] * z * 1.5)))
    crop_centre(big, int(box[0] * z), int(box[1] * z), int(dy * z)).convert("RGB").save(f"{OUT}/{name}", optimize=True)


def ladder(model_id, box, name, dy=0):
    """Current art, then the new model at levels 0..3 (SVG) and the PNG bake, default view, 1.5x."""
    z = 1.5
    row = []
    items = [("current", "cur"), ("new model L0 flat", 0), ("L1 shading", 1), ("L2 panels", 2), ("L3 full SVG", 3), ("PNG bake", "png")]
    m = json.load(open(f"{S}/{model_id}_manifest.json"))
    for label_, v in items:
        if v in (0, 1, 2):
            big = scene_level(model_id, m, v, z, (int(box[0] * z * 1.4), int(box[1] * z * 1.4)))
        else:
            big = scene(model_id, "cur" if v == "cur" else ("svg" if v == 3 else "png"), z, (int(box[0] * z * 1.4), int(box[1] * z * 1.4)))
        row.append(label(crop_centre(big, int(box[0] * z * 0.62), int(box[1] * z * 0.62), int(dy * z)), label_))
    grid([row]).save(f"{OUT}/{name}", optimize=True)


def scene_level(model_id, m, level, zoom, size):
    centre = (size[0] // 2, size[1] // 2 + int(8 * zoom))
    img = ground(size, centre, zoom)
    lay = m["proto"]["layouts"]
    sc = round(zoom * 100)
    f = f"{S}/png/L{level}/{model_id}_"
    put(img, load(f + f"shadow_d06_s{sc}.png" if model_id == "tank" else f + f"shadow_d00_s{sc}.png"), lay["shadow"]["origin"], centre, zoom)
    d = "06" if model_id == "tank" else "00"
    put(img, load(f + f"hull_d{d}_s{sc}.png"), lay["hull"]["origin"], centre, zoom)
    if "turret" in lay:
        mo = m["proto"]["mount"]["6"]
        put(img, load(f + f"turret_d{d}_s{sc}.png"), lay["turret"]["origin"], (centre[0] + mo[0] * zoom, centre[1] + mo[1] * zoom), zoom)
    return img


def directions(name):
    """Eight hull directions with turret, current vs prototype SVG vs PNG bake, at 1.0."""
    rows = []
    for variant, vname in (("cur", "current"), ("svg", "proto SVG"), ("png", "proto PNG")):
        row = []
        for d in range(0, 16, 2):
            big = scene("tank", variant, 1.0, (170, 140), dir_=d)
            row.append(label(big, f"{vname} d{d:02d}"))
        rows.append(row)
    grid(rows, pad=3).save(f"{OUT}/{name}", optimize=True)


if __name__ == "__main__" and not R2:
    os.makedirs(OUT, exist_ok=True)
    zoom_sheet("tank", (230, 170), "tank_zoom_levels.png", dy=-14)
    large("tank", (260, 200), "tank_large.png", dy=-20)
    ladder("tank", (260, 200), "tank_ladder.png", dy=-20)
    directions("tank_directions.png")
    zoom_sheet_hq = zoom_sheet("hq", (450, 300), "hq_zoom_levels.png", dy=-30)
    large("hq", (470, 320), "hq_large.png", dy=-45, z=1.5)
    png_single("tank", (260, 200), "tank_large_proto_png.png", "png", dy=-20)
    png_single("tank", (260, 200), "tank_large_proto_svg.png", "svg", dy=-20)
    png_single("hq", (470, 320), "hq_large_proto_png.png", "png", dy=-45)
    png_single("hq", (470, 320), "hq_large_proto_svg.png", "svg", dy=-45)
    ladder("hq", (470, 320), "hq_ladder.png", dy=-45)
