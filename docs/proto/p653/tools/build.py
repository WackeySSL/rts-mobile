import sys, json, os, io
sys.path.insert(0, '/tmp/p653/docs/proto/p653/tools')
from compose import *
from PIL import ImageDraw, ImageFont

OUTD = '/tmp/p653/docs/proto/p653/'          # committed: our own renders only
SCR = SC                                      # scratchpad: three-way with Figma crops
FIG = SC + 'figma/'
FONT = ImageFont.load_default(size=14)
GRASS = Image.open(RAW + 'svg/grass_a_O.png'); GRASS_B = Image.open(RAW + 'svg/grass_b_O.png')
SAND = Image.open(RAW + 'svg/sand_a_O.png'); SAND_B = Image.open(RAW + 'svg/sand_b_O.png')


def ground_fill(w, h, kind, k):
    """Today's flat ground tiles (128 x 64 art px) tiled over a w x h canvas at k screen px per art px."""
    c = Image.new('RGBA', (w, h), (0, 0, 0, 255))
    tw, th = 128 * k, 64 * k
    t1 = (GRASS if kind == 'grass' else SAND); t2 = (GRASS_B if kind == 'grass' else SAND_B)
    ims = [t.resize((max(1, round(tw)), max(1, round(th))), Image.LANCZOS) for t in (t1, t2)]
    n = 0
    for j in range(-2, int(h / (th / 2)) + 4):
        for i in range(-2, int(w / tw) + 4):
            x = i * tw + (tw / 2 if j % 2 else 0) - tw / 2
            y = j * th / 2 - th / 2
            c.alpha_composite(ims[(i * 7 + j * 13) % 2], (round(x), round(y)))
    return c


def label(im, text, xy=(8, 6)):
    d = ImageDraw.Draw(im)
    d.rectangle([xy[0] - 4, xy[1] - 3, xy[0] + 8 * len(text) + 2, xy[1] + 17], fill=(0, 0, 0, 170))
    d.text(xy, text, fill=(255, 255, 255, 255), font=FONT)


def tank_row(variant, dirs, kind, team, k, w=640, h=360):
    c = ground_fill(w, h, kind, k)
    n = len(dirs)
    for n_i, d in enumerate(dirs):
        x = (n_i + 0.5) * w / n
        y = h * 0.62
        layers = svg_tank(d, 'O' if team == 'S' else 'B') if variant == 'svg' else proto_tank(d, SIGNAL[1] if team == 'S' else KOBOLT[1])
        draw_tank(c, layers, x, y, k)
    return c


def bld_row(variant, kind, team, k, w=640, h=360):
    c = ground_fill(w, h, kind, k)
    x, y = w / 2, h * 0.5
    if variant == 'svg':
        w_ = 'O' if team == 'S' else 'B'
        paste(c, svg_layer(f'{RAW}svg/vehicle_factory_shadow_{w_}.png', BLD['shadow']), x, y, k)
        paste(c, svg_layer(f'{RAW}svg/vehicle_factory_hull_{w_}.png', BLD['hull']), x, y, k)
    else:
        hexm = SIGNAL[1] if team == 'S' else KOBOLT[1]
        paste(c, proto_layer(RAW + 'vehicle_factory_shadow.png', 2, BLD['shadow'], None, 4.0, True), x, y, k)
        paste(c, proto_layer(RAW + 'vehicle_factory_hull.png', 2, BLD['hull'], hexm, 4.0), x, y, k)
    return c


def stack(top, bottom):
    c = Image.new('RGBA', (top.width, top.height + bottom.height))
    c.paste(top, (0, 0)); c.paste(bottom, (0, top.height))
    return c


def hcat(ims, gap=0, bg=(12, 16, 22, 255)):
    c = Image.new('RGBA', (sum(i.width for i in ims) + gap * (len(ims) - 1), max(i.height for i in ims)), bg)
    x = 0
    for i in ims:
        c.paste(i, (x, 0)); x += i.width + gap
    return c


def fig_panel(name, box, w=640, h=720):
    im = Image.open(FIG + name).convert('RGBA').crop(box)
    s = min(w / im.width, h / im.height)
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    c = Image.new('RGBA', (w, h), (12, 16, 22, 255)); c.paste(im, ((w - im.width) // 2, (h - im.height) // 2))
    return c


def compare(name, make_svg, make_proto, fig_name, fig_box):
    """Writes <name>.png (our SVG | our prototype, 1280 x 720, committed) and the three-way one into the scratchpad."""
    svg = make_svg(); pro = make_proto()
    label(svg, 'today: generator SVG, L2'); label(pro, 'prototype: pre-rendered 3D')
    two = hcat([svg, pro])
    two.save(OUTD + name + '.png')
    fig = fig_panel(fig_name, fig_box); label(fig, 'Figma reference (look only)')
    hcat([svg, pro, fig]).save(SCR + 'threeway_' + name + '.png')
    return two


FIGBOX = dict(tank=(1198, 332, 1530, 447), bld=(822, 614, 1154, 746))

if __name__ == '__main__':
    for z, k in (('z1', 0.5), ('z2', 1.0)):
        dirs = (2, 5, 9, 13) if z == 'z1' else (4, 10)
        compare(f'tank_{z}',
                lambda: stack(tank_row('svg', dirs, 'grass', 'S', k), tank_row('svg', dirs, 'sand', 'K', k)),
                lambda: stack(tank_row('proto', dirs, 'grass', 'S', k), tank_row('proto', dirs, 'sand', 'K', k)),
                'units.png', FIGBOX['tank'])
        compare(f'building_{z}',
                lambda: stack(bld_row('svg', 'grass', 'S', k), bld_row('svg', 'sand', 'K', k)),
                lambda: stack(bld_row('proto', 'grass', 'S', k), bld_row('proto', 'sand', 'K', k)),
                'buildings.png', FIGBOX['bld'])
    print('done')
