import sys; sys.path.insert(0, '/tmp/p653/docs/proto/p653/tools')
from pipeline import *

TANK = dict(hull=(166, 104, 83, 65), turret=(214, 118, 107, 72), shadow=(254, 130, 119, 61))
MOUNT_DY = -25.1   # art px, the turret pivot above the hull's ground point (sheet mounts)
BLD = dict(hull=(384, 346, 192, 153 + 96), shadow=(456, 230, 228, 19 + 96))  # origin = anchor + 32 n


class Sprite:
    """An image with its origin (the ground point) in the image, at `dens` texels per art px."""
    def __init__(self, img, ox, oy, dens):
        self.img, self.ox, self.oy, self.dens = img, ox, oy, dens


def proto_layer(path, f, anchor, team, raw_scale, shadow=False):
    dens = raw_scale / f
    if shadow:
        lin, a = load_lin(path)
        lin, a = box_down(lin, a, f)
        img = to_image(np.zeros(a.shape + (3,)), a * 0.35)
    else:
        img = frame(path, f, team)
    return Sprite(img, anchor[2] * dens, anchor[3] * dens, dens)


def svg_layer(path, anchor, shadow=False):
    img = Image.open(path).convert('RGBA')
    if shadow:
        img.putalpha(img.getchannel('A'))   # the shadow SVG already carries its 35 % group
    return Sprite(img, anchor[2], anchor[3], 1.0)


def proto_tank(d, team, dens='2x'):
    f = 4 if dens == '2x' else 8
    L = []
    for part in ('shadow', 'hull', 'turret'):
        L.append((part, proto_layer(f'{RAW}heavy_tank_{part}_d{d:02d}.png', f, TANK[part], team, 8.0, part == 'shadow')))
    return L


def svg_tank(d, which):
    return [(p, svg_layer(f'{RAW}svg/heavy_tank_{p}_d{d:02d}_{which}.png', TANK[p], p == 'shadow')) for p in ('shadow', 'hull', 'turret')]


def paste(canvas, sprite, x, y, k, dy_art=0.0):
    """Draw `sprite` with its origin at screen (x, y); k = screen px per art px."""
    s = k / sprite.dens
    im = sprite.img
    nw, nh = max(1, round(im.width * s)), max(1, round(im.height * s))
    im2 = im.resize((nw, nh), Image.LANCZOS if s < 1 else Image.BICUBIC)
    canvas.alpha_composite(im2, (round(x - sprite.ox * s), round(y + dy_art * k - sprite.oy * s)))


def draw_tank(canvas, layers, x, y, k):
    for name, sp in layers:
        paste(canvas, sp, x, y, k, MOUNT_DY if name == 'turret' else 0.0)
