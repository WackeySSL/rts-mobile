import sys, json
sys.path.insert(0, '/tmp/p653/docs/proto/p653/tools')
from build import *

TILES = json.load(open(RAW + 'terrain_tiles.json'))
AX, AY = 516, 150
WATER_Y = -0.07
TERRAIN_GRADE = dict(contrast=0.10, sat=1.25, gain=1.30)


def proto_terrain(f):
    lin, a = load_lin(RAW + 'terrain_patch.png')
    lin, a = box_down(lin, a, f)
    c, a = grade(lin, a, TERRAIN_GRADE)
    return Sprite(to_image(c, a), AX * 4 / f, AY * 4 / f, 4 / f)


def svg_tile(name):
    return Image.open(RAW + f'svg/{name}_O.png').convert('RGBA')


def svg_terrain_patch():
    """The same 8 x 8 layout drawn with today's ground diamonds (the nearest of the six ids)."""
    W, H = 8 * 128 + 8, 8 * 64 + 150 + 30
    c = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    kinds = {}
    for t in TILES:
        i, j = t['i'], t['j']
        if t['h'] < WATER_Y + 0.03:
            kind = 'water'
        elif t['cliff'] > 0.45:
            kind = 'rock'
        elif t['road'] > 0.5:
            kind = 'sand_b'      # today there is no road tile
        elif t['sand'] > 0.4:
            kind = 'sand'
        else:
            kind = 'grass'
        kinds[(i, j)] = kind
    for s in range(15):
        for j in range(8):
            i = s - j
            if not 0 <= i < 8:
                continue
            k = kinds[(i, j)]
            v = 'a' if (i * 7 + j * 13) % 2 == 0 else 'b'
            name = k if k == 'sand_b' else f'{k}_{v}'
            tile = svg_tile(name)
            x = AX + (i - j) * 64 - 64
            y = AY + (i + j) * 32
            c.alpha_composite(tile, (x, y))
    return Sprite(c, AX, AY, 1.0), kinds


def terrain_canvas(variant, k, w, h, focus_g):
    """Terrain only, 1280 x 720 style canvas centred on ground point `focus_g` (tiles)."""
    c = Image.new('RGBA', (w, h), (18, 22, 28, 255))
    sp = proto_terrain(2) if variant == 'proto' else svg_terrain_patch()[0]
    fx = (focus_g[0] - focus_g[1]) * 64 * k; fy = (focus_g[0] + focus_g[1]) * 32 * k
    paste(c, sp, w / 2 - fx, h / 2 - fy, k)
    return c


if __name__ == '__main__':
    # terrain side-by-sides: zoom 1 (whole patch) and zoom 2 (the cliff foot and shore)
    for z, k, foc in (('z1', 0.5, (4.0, 4.0)), ('z2', 1.0, (5.2, 3.4))):
        svg = terrain_canvas('svg', k, 640, 720, foc); pro = terrain_canvas('proto', k, 640, 720, foc)
        label(svg, 'today: generator SVG ground (no road, no cliff tile exists)'); label(pro, 'prototype: pre-rendered 3D terrain')
        hcat([svg, pro]).save(OUTD + f'terrain_{z}.png')
        figs = {'z1': (68, 247, 404, 387), 'z2': (1196, 247, 1532, 387)}
        fig = hcat([fig_panel('terrain.png', (68, 235, 1532, 731), 640, 360), fig_panel('terrain.png', (56, 800, 986, 1230), 640, 360)])
        fp = Image.new('RGBA', (640, 720), (12, 16, 22, 255)); fp.paste(fig_panel('terrain.png', (56, 235, 1532, 731), 640, 360), (0, 0)); fp.paste(fig_panel('terrain.png', (56, 800, 986, 1230), 640, 360), (0, 360))
        label(fp, 'Figma reference (look only)')
        hcat([svg, pro, fp]).save(SCR + f'threeway_terrain_{z}.png')
    print('ok')
