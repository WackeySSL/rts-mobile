"""P655 compose script: the detailed tank against today's SVG, the P653 prototype and the Figma card.
Imports P653's pipeline and compose helpers (docs/proto/p653/tools, run from a checkout that has them)."""
import sys, json, os, glob, time
P653 = '/tmp/p655/docs/proto/p653/tools'
sys.path.insert(0, P653)
import pipeline
SC5 = '/tmp/claude-0/-home-user-rts-mobile/f4088c2f-7ea6-5710-9456-77d97126fbd5/scratchpad/p655/'
pipeline.SC = '/tmp/claude-0/-home-user-rts-mobile/f4088c2f-7ea6-5710-9456-77d97126fbd5/scratchpad/p653/'
pipeline.RAW = pipeline.SC + 'raw/'
import compose
compose.RAW = pipeline.RAW
from build2 import *
from PIL import ImageDraw          # build.py and build2.py import compose and pipeline, so they see the paths above
import build
RAW5 = SC5 + 'raw/'
OUT5 = '/tmp/p655/docs/proto/p655/'
FIGCARD = SC5 + 'figma_card.png'   # scratchpad only, never committed
HERO = 10                          # the Figma card's pose: the gun to the lower left
SIG, KOB = SIGNAL[1], KOBOLT[1]


def det_tank(d, team, dens='1x'):
    f = 8 if dens == '1x' else 4
    return [
        ('shadow', proto_layer(f'{RAW}heavy_tank_shadow_d{d:02d}.png', f, TANK['shadow'], team, 8.0, True)),
        ('hull', proto_layer(f'{RAW5}heavy_tank_hull_d{d:02d}.png', f, TANK['hull'], team, 8.0)),
        ('turret', proto_layer(f'{RAW5}heavy_tank_turret_d{d:02d}.png', f, TANK['turret'], team, 8.0)),
    ]


def layers(variant, d, team):
    if variant == 'svg':
        return svg_tank(d, 'O' if team == SIG else 'B')
    if variant == 'p653':
        return proto_tank(d, team)
    return det_tank(d, team)


def tank_panel(variant, k, team, kind, w=320, h=360, d=HERO):
    c = ground_fill(w, h, kind, k)
    draw_tank(c, layers(variant, d, team), w / 2, h * 0.62, k)
    return c


def figma_panel(w=320, h=720):
    im = Image.open(FIGCARD).convert('RGBA')
    s = w / im.width
    im = im.resize((w, round(im.height * s)), Image.LANCZOS)
    c = Image.new('RGBA', (w, h), (12, 16, 22, 255))
    c.paste(im, (0, (h - im.height) // 2))
    return c


def threeway(zoom):
    k = zoom * 0.5
    cols = []
    for variant, name in (('svg', 'today: SVG L2'), ('p653', 'P653 prototype'), ('det', 'P655 detailed')):
        top = tank_panel(variant, k, SIG, 'grass'); bot = tank_panel(variant, k, KOB, 'sand')
        col = stack(top, bot)
        build.label(col, name)
        cols.append(col)
    fig = figma_panel(); build.label(fig, 'Figma card (look only)')
    cols.append(fig)
    return hcat(cols)


def mirror_pair(k, kind='grass', dirs=(HERO, HERO), w=640, h=360):
    c = ground_fill(w, h, kind, k)
    for i, (d, team) in enumerate(zip(dirs, (SIG, KOB))):
        draw_tank(c, det_tank(d, team), w * (0.3 + 0.4 * i), h * 0.62, k)
    return c



def scene(zoom, focus, tanks, dens='1x'):
    k = zoom * 0.5
    w, h = 1280, 720
    c = Image.new('RGBA', (w, h), (18, 22, 28, 255))
    sp = proto_terrain(2)

    def scr(g):
        return (w / 2 + ((g[0] - g[1]) - (focus[0] - focus[1])) * 64 * k, h / 2 + ((g[0] + g[1]) - (focus[0] + focus[1])) * 32 * k)
    ox, oy = scr((0, 0))
    paste(c, sp, ox, oy, k)
    bx, by = scr(BLD_G)
    paste(c, proto_layer(RAW + 'vehicle_factory_shadow.png', 2, BLD['shadow'], None, 4.0, True), bx, by, k)
    L = [(g, det_tank(d, SIG if t == 'S' else KOB, dens)) for g, d, t in tanks]
    for g, ls in L:
        x, y = scr(g); paste(c, ls[0][1], x, y, k)
    order = [(BLD_G[0] + BLD_G[1], 'b', BLD_G, None)] + [(g[0] + g[1], 't', g, ls) for g, ls in L]
    for _, kind, g, ls in sorted(order, key=lambda o: o[0]):
        x, y = scr(g)
        if kind == 'b':
            paste(c, proto_layer(RAW + 'vehicle_factory_hull.png', 2, BLD['hull'], SIG, 4.0), x, y, k)
        else:
            draw_tank(c, ls[1:], x, y, k)
    return c


BLD_G = (2.2, 4.1)
# a mirror pair that faces each other (Signal d6 = +gx, Kobolt d14 = -gx) and a pair side by side
TANKS = [((2.7, 6.4), 6, 'S'), ((4.7, 6.4), 14, 'K'), ((5.6, 4.9), HERO, 'S'), ((6.7, 5.4), HERO, 'K')]


def contact_sheet():
    k = 1.0
    cw, ch = 270, 170
    sheet = ground_fill(cw * 8, ch * 4, 'grass', k)
    for ti, team in enumerate((SIG, KOB)):
        for d in range(16):
            draw_tank(sheet, det_tank(d, team), (d % 8) * cw + cw / 2 - 5, (ti * 2 + d // 8) * ch + ch * 0.66, k)
    dr = ImageDraw.Draw(sheet)
    for d in range(16):
        dr.text(((d % 8) * cw + 6, (d // 8) * ch + 4), f'd{d:02d} Signal', fill=(255, 255, 255, 255), font=build.FONT)
        dr.text(((d % 8) * cw + 6, (2 + d // 8) * ch + 4), f'd{d:02d} Kobolt', fill=(255, 255, 255, 255), font=build.FONT)
    return sheet


def others(vid, d, team_dummy=None):
    """Today's SVG of another ground vehicle: composited hull (+turret) as one RGBA at 1 texel per art px."""
    meta = json.load(open(RAW5 + 'svg_meta.json'))[vid]
    c = Image.new('RGBA', (500, 400), (0, 0, 0, 0))
    ox, oy = 250, 250
    parts = meta['parts']
    for part in ('hull', 'turret'):
        if part not in parts:
            continue
        i = parts.index(part)
        im = Image.open(f'{RAW5}svg_{vid}_{part}_d{d:02d}.png').convert('RGBA')
        ax, ay = meta['anchors'][i * 2], meta['anchors'][i * 2 + 1]
        dx, dy = (0, 0)
        if part == 'turret':
            dx, dy = meta['mounts'][d]
        c.alpha_composite(im, (round(ox + dx - ax), round(oy + dy - ay)))
    return c.crop(c.getbbox())


def det_composite(d):
    c = Image.new('RGBA', (600, 500), (0, 0, 0, 0))
    draw_tank(c, det_tank(d, SIG)[1:], 300, 330, 1.0)
    return c.crop(c.getbbox())


def readability():
    ids = [('heavy_tank (today)', None), ('P655 heavy_tank', 'det'), ('light_tank', 'light_tank'), ('artillery', 'artillery'), ('harvester', 'harvester'), ('fossil_bunk_wagon', 'fossil_bunk_wagon'), ('fossil_shot_truck', 'fossil_shot_truck')]
    cell = 40
    dirs = (2, 9)
    sheet = Image.new('L', (len(ids) * cell * 6, len(dirs) * cell * 6 + 6), 0)
    for ci, (name, vid) in enumerate(ids):
        for ri, d in enumerate(dirs):
            if vid == 'det':
                t = det_composite(d)
            else:
                t = others(vid or 'heavy_tank', d)
            # all vehicles at their true relative size: today's heavy tank is 32 px on its long side
            ref = max(others('heavy_tank', d).size)
            s = 32.0 / ref
            small = t.resize((max(1, round(t.width * s)), max(1, round(t.height * s))), Image.LANCZOS)
            bg = Image.new('RGBA', small.size, (100, 110, 70, 255)); bg.alpha_composite(small)
            g = bg.convert('L')
            cl = Image.new('L', (cell, cell), 100); cl.paste(g, ((cell - g.width) // 2, (cell - g.height) // 2))
            sheet.paste(cl.resize((cell * 6, cell * 6), Image.NEAREST), (ci * cell * 6, ri * (cell * 6 + 6)))
    return sheet


def detail_view():
    """Our 2x-density render magnified 4x, beside the Figma card magnified to the same width. Look-development aid."""
    t = det_tank(HERO, SIG, '2x')
    c = Image.new('RGBA', (400, 300), (50, 58, 66, 255))
    draw_tank(c, t[1:], 200, 200, 2.0)
    c = c.resize((1200, 900), Image.LANCZOS)
    return c


def two_x_reference():
    """A phone with 2 device px per screen px at zoom 2: 1x data upscaled vs 2x data. Not shippable (see README)."""
    out = []
    for dens in ('1x', '2x'):
        c = ground_fill(640, 360, 'grass', 2.0)
        draw_tank(c, det_tank(HERO, SIG, dens), 320, 360 * 0.62, 2.0)
        build.label(c, 'P655 at 1x data' if dens == '1x' else 'P655 at 2x data, not shippable')
        out.append(c)
    return hcat(out)


if __name__ == '__main__':
    for z in (1, 2):
        threeway(z).save(SC5 + f'threeway_z{z}.png')
    for z, zoom, foc in (('z1', 1.0, (4.0, 5.0)), ('z2', 2.0, (4.4, 5.6))):
        scene(zoom, foc, TANKS).save(SC5 + f'scene_{z}.png')
    scene(2.0, (4.4, 5.6), TANKS, '2x').save(SC5 + 'scene_z2_2xdata_not_shippable.png')
    contact_sheet().save(SC5 + 'contact_sheet_16dir.png')
    readability().save(SC5 + 'readability_32px_grey.png')
    detail_view().save(SC5 + 'detail_2xdata_x4.png')
    two_x_reference().save(SC5 + 'ref_2x_not_shippable.png')
    mp = stack(mirror_pair(1.0), mirror_pair(1.0, 'sand'))
    mp.save(SC5 + 'mirror_pair_z2.png')
    print('ok')
