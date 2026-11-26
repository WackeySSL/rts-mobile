import sys
sys.path.insert(0, '/tmp/p653/docs/proto/p653/tools')
from build2 import *

BLD_G = (2.2, 4.1)
TANKS = [((3.0, 6.62), 6, 'S'), ((4.7, 6.45), 6, 'K'), ((6.1, 6.36), 7, 'S')]


def scene(variant, zoom, focus):
    k = zoom * 0.5
    w, h = 1280, 720
    c = Image.new('RGBA', (w, h), (18, 22, 28, 255))
    sp = proto_terrain(2) if variant == 'proto' else svg_terrain_patch()[0]

    def scr(g):
        return (w / 2 + ((g[0] - g[1]) - (focus[0] - focus[1])) * 64 * k, h / 2 + ((g[0] + g[1]) - (focus[0] + focus[1])) * 32 * k)
    ox, oy = scr((0, 0))
    paste(c, sp, ox, oy, k)
    items = []
    # shadows first
    if variant == 'svg':
        x, y = scr(BLD_G); paste(c, svg_layer(f'{RAW}svg/vehicle_factory_shadow_O.png', BLD['shadow']), x, y, k)
    else:
        x, y = scr(BLD_G); paste(c, proto_layer(RAW + 'vehicle_factory_shadow.png', 2, BLD['shadow'], None, 4.0, True), x, y, k)
    for g, d, team in TANKS:
        x, y = scr(g)
        L = svg_tank(d, 'O' if team == 'S' else 'B') if variant == 'svg' else proto_tank(d, SIGNAL[1] if team == 'S' else KOBOLT[1])
        paste(c, L[0][1], x, y, k)
    order = [(BLD_G[0] + BLD_G[1], 'b', BLD_G, None, None)] + [(g[0] + g[1], 't', g, d, team) for g, d, team in TANKS]
    for _, kind, g, d, team in sorted(order, key=lambda o: o[0]):
        x, y = scr(g)
        if kind == 'b':
            if variant == 'svg':
                paste(c, svg_layer(f'{RAW}svg/vehicle_factory_hull_O.png', BLD['hull']), x, y, k)
            else:
                paste(c, proto_layer(RAW + 'vehicle_factory_hull.png', 2, BLD['hull'], SIGNAL[1], 4.0), x, y, k)
        else:
            L = svg_tank(d, 'O' if team == 'S' else 'B') if variant == 'svg' else proto_tank(d, SIGNAL[1] if team == 'S' else KOBOLT[1])
            draw_tank(c, L[1:], x, y, k)
    return c


if __name__ == '__main__':
    for z, zoom, foc in (('z1', 1.0, (4.0, 4.0)), ('z2', 2.0, (3.9, 5.1))):
        s = scene('svg', zoom, foc); p = scene('proto', zoom, foc)
        s.save(OUTD + f'scene_svg_{z}.png'); p.save(OUTD + f'scene_proto_{z}.png')
    print('ok')
