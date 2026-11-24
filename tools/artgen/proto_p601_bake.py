#!/usr/bin/env python3
"""P601 prototype: the PNG bake path. Takes the faces that gen_proto_p601.gd exports (3D points,
normals, material) and shades them per pixel: panel seams, bolts, hazard stripes, paint chips,
grime, worn edges, a Lambert plus sky term, a small specular lobe on metals and a screen-space
ambient occlusion pass over a 3D position buffer. Exploration only; nothing here ships.

Usage (as a module): bake(geom_dict, scale) -> PIL RGBA image of size round(size * scale).
"""
import math

import numpy as np
from PIL import Image, ImageDraw

LIGHT = np.array([-0.35, 0.35, 0.90])
LIGHT /= np.linalg.norm(LIGHT)
VIEW = np.array([0.6123724, 0.6123724, 0.5])
METAL = {"gunmetal", "darksteel", "wornsteel", "trim", "hazard"}
EMISSIVE = {"glow", "lamp"}
CELL = {"team": 0.30, "gunmetal": 0.22, "darksteel": 0.20, "wornsteel": 0.20, "trim": 0.40}
PANELLED = set(CELL) | {"hazard"}
STRIPE = 0.075
SS = 3


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) for i in (0, 2, 4)], dtype=np.float64) / 255.0


def hash2(a, b, c, d):
    v = (a * 73856093) ^ (b * 19349663) ^ (c * 83492791) ^ (d * 40503)
    return (np.abs(v) % 10007) / 10007.0


def vnoise(x, y, z, seed=0):
    """3D value noise in [0,1], vectorised."""
    xi, yi, zi = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64), np.floor(z).astype(np.int64)
    xf, yf, zf = x - xi, y - yi, z - zi
    sm = lambda t: t * t * (3 - 2 * t)
    xf, yf, zf = sm(xf), sm(yf), sm(zf)

    def corner(dx, dy, dz):
        h = ((xi + dx) * 374761393 + (yi + dy) * 668265263 + (zi + dz) * 2147483647 + seed * 1274126177)
        h = (h ^ (h >> 13)) * 1274126177
        h = h ^ (h >> 16)
        return (h & 0xFFFF) / 65535.0

    c = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (xf if dx else 1 - xf) * (yf if dy else 1 - yf) * (zf if dz else 1 - zf)
                c = c + w * corner(dx, dy, dz)
    return c


def fbm(P, scale, seed=0):
    return 0.6 * vnoise(P[..., 0] * scale, P[..., 1] * scale, P[..., 2] * scale, seed) + 0.4 * vnoise(
        P[..., 0] * scale * 2.3, P[..., 1] * scale * 2.3, P[..., 2] * scale * 2.3, seed + 7
    )


def fit_affine(pts2, pts3):
    A = np.hstack([np.array(pts2), np.ones((len(pts2), 1))])
    coef, *_ = np.linalg.lstsq(A, np.array(pts3), rcond=None)
    return coef  # (3,3): [x,y,1] @ coef -> xyz


def bake(geom, scale, ss=SS):
    w0, h0 = geom["size"]
    W, H = int(round(w0 * scale)), int(round(h0 * scale))
    s = scale * ss
    Wb, Hb = W * ss, H * ss
    faces = geom["faces"]
    ids = Image.new("I", (Wb, Hb), 0)
    d = ImageDraw.Draw(ids)
    for k, f in enumerate(faces):
        d.polygon([(x * s, y * s) for x, y in f["pts"]], fill=k + 1)
    ids = np.array(ids, dtype=np.int64)
    P = np.zeros((Hb, Wb, 3))
    N = np.zeros((Hb, Wb, 3))
    col = np.zeros((Hb, Wb, 3))
    spec_k = np.zeros((Hb, Wb))
    emissive = np.zeros((Hb, Wb), dtype=bool)
    prim = np.full((Hb, Wb), -1, dtype=np.int64)
    ydx, xdx = np.mgrid[0:Hb, 0:Wb]
    for k, f in enumerate(faces):
        m = ids == k + 1
        if not m.any():
            continue
        ys, xs = ydx[m], xdx[m]
        sx, sy = (xs + 0.5) / s, (ys + 0.5) / s
        coef = fit_affine(f["pts"], f["p3"])
        pos = np.stack([sx, sy, np.ones_like(sx)], 1) @ coef
        P[m] = pos
        n = np.array(f["n"])
        N[m] = n
        prim[m] = f["prim"]
        mat = f["mat"]
        alb = hexc(f["albedo"])
        if mat in EMISSIVE:
            col[m] = alb
            emissive[m] = True
            continue
        c = np.tile(alb, (len(xs), 1))
        p3 = np.array(f["p3"])
        quad = len(p3) == 4
        if mat in PANELLED:
            if quad:
                c = shade_quad(c, pos, p3, f, mat, k, scale, ss)
            elif f["top"]:
                c = shade_ngon(c, pos, p3, f, mat, k, scale)
        # grime: low-frequency tone variation, dirt gathers near the ground on vertical faces
        g = fbm(pos, 9.0, k)
        c *= (0.93 + 0.14 * g)[:, None]
        if abs(n[2]) < 0.4:
            low = np.clip(1.0 - pos[:, 2] / 0.35, 0, 1)
            streak = vnoise(pos[:, 0] * 14 + pos[:, 1] * 14, pos[:, 2] * 1.5, np.zeros(len(g)) + k, 3)
            c *= (1.0 - 0.34 * low * (0.4 + streak))[:, None]
        col[m] = c
        spec_k[m] = 0.22 if mat in METAL else 0.07
    solid = ids > 0
    # lighting
    ndl = np.clip((N * LIGHT).sum(-1), 0, 1)
    light = 0.62 + 0.38 * ndl + 0.06 * N[..., 2]
    ao = ambient_occlusion(P, N, solid, s)
    # ground contact: vertical faces darken towards z = 0
    ground = np.where(np.abs(N[..., 2]) < 0.4, np.clip(1.0 - P[..., 2] / 0.22, 0, 1) * 0.30, 0.0)
    r = 2 * (N * LIGHT).sum(-1)[..., None] * N - LIGHT
    spec = np.clip((r * VIEW / np.linalg.norm(VIEW)).sum(-1), 0, 1) ** 20 * spec_k
    out = col * (light * (1 - 0.65 * ao) * (1 - ground))[..., None] + spec[..., None]
    out = np.where(emissive[..., None], col * 1.05, out)
    # edges: silhouette outline, light on convex edges, dark where two parts meet
    r_px = max(1, int(round(0.9 * s / 1.0)))
    out = edges(out, ids, N, prim, solid, r_px, emissive)
    out = np.clip(out, 0, 1)
    rgba = np.zeros((Hb, Wb, 4))
    rgba[..., :3] = out * solid[..., None]
    rgba[..., 3] = solid
    # downsample (premultiplied)
    pm = rgba[..., :3] * rgba[..., 3:4]
    pm = pm.reshape(H, ss, W, ss, 3).mean((1, 3))
    a = rgba[..., 3].reshape(H, ss, W, ss).mean((1, 3))
    rgb = np.where(a[..., None] > 1e-4, pm / np.maximum(a[..., None], 1e-4), 0)
    res = np.dstack([np.clip(rgb, 0, 1), a])
    return Image.fromarray((res * 255 + 0.5).astype(np.uint8), "RGBA")


def shade_quad(c, pos, p3, f, mat, k, scale, ss):
    e_u = p3[1] - p3[0]
    e_v = p3[3] - p3[0]
    lu, lv = np.linalg.norm(e_u), np.linalg.norm(e_v)
    if lu * lv < 0.006:
        return c
    rel = pos - p3[0]
    u = (rel @ e_u) / (lu * lu) * lu  # tiles along u
    v = (rel @ e_v) / (lv * lv) * lv
    px_tile = 90.5 * scale  # one tile on the ground in px at this scale (2x art)
    seam_w = 0.55 / (px_tile) * 1.0  # half seam width in tiles (about 0.55 px)
    if mat == "hazard":
        band = np.floor((u + v) / STRIPE).astype(np.int64) % 2
        base = c.copy()
        dark = hexc("#202326")
        out = np.where(band[:, None] == 0, base, dark[None, :])
        return out
    cs = CELL.get(mat, 0.25)
    nu, nv = max(1, round(lu / cs)), max(1, round(lv / cs))
    if mat == "team" and lu * lv < 0.03:
        nu = nv = 1
    cu, cv = lu / nu, lv / nv
    fu, fv = (u / cu), (v / cv)
    iu, iv = np.clip(np.floor(fu), 0, nu - 1).astype(np.int64), np.clip(np.floor(fv), 0, nv - 1).astype(np.int64)
    du = np.minimum(fu - iu, iu + 1 - fu) * cu  # distance to the cell border along u, in tiles
    dv = np.minimum(fv - iv, iv + 1 - fv) * cv
    dist = np.minimum(du, dv)
    jit = 0.94 + 0.12 * hash2(k, iu, iv, 5)
    c = c * jit[:, None]
    # seam
    seam = np.clip(1.0 - (dist - seam_w) / (0.7 / px_tile), 0, 1)
    c = c * (1 - 0.5 * seam)[:, None]
    # bevel: light just inside the cell edge on the upper-left, dark on the lower-right (screen up = +z / -x+y)
    inner = (dist > seam_w) & (dist < seam_w + 1.6 / px_tile)
    c = np.where(inner[:, None], c * 1.10, c)
    # bolts at cell corners
    if mat in {"team", "gunmetal", "darksteel", "trim"} and nu * nv >= 2:
        for ci in (0, 1):
            cu_ = (iu + ci) * cu
            cv_ = (iv + ci) * cv
            bd = np.hypot(u - cu_ - (0.012 if ci == 0 else -0.012), v - cv_ - (0.012 if ci == 0 else -0.012))
            bolt = np.clip(1.0 - bd / (1.15 / px_tile), 0, 1)
            c = c * (1 - 0.55 * bolt)[:, None]
    # chipped paint along panel borders shows bare steel
    if mat == "team":
        n1 = fbm(pos, 38.0, k + 11)
        chip = (dist < 0.03) & (n1 > 0.68)
        steel = hexc("#7A8084")
        c = np.where(chip[:, None], steel[None, :] * (0.85 + 0.3 * n1)[:, None], c)
        n2 = fbm(pos, 70.0, k + 3)
        scratch = n2 > 0.80
        c = np.where(scratch[:, None], c * 0.75, c)
    return c


def shade_ngon(c, pos, p3, f, mat, k, scale):
    centre = p3[:, :2].mean(0)
    rad = np.linalg.norm(p3[:, :2] - centre, axis=1).max()
    rel = pos[:, :2] - centre
    r = np.hypot(rel[:, 0], rel[:, 1]) / max(rad, 1e-6)
    n = len(p3)
    ang = (np.arctan2(rel[:, 1], rel[:, 0]) + 2 * math.pi) % (2 * math.pi)
    sector = ang / (2 * math.pi) * n
    sec_i = np.floor(sector).astype(np.int64)
    d_sec = np.minimum(sector - sec_i, sec_i + 1 - sector) * (2 * math.pi / n) * r * rad
    px_tile = 90.5 * scale
    seam_w = 0.55 / px_tile
    ring = np.minimum(np.abs(r - 0.5), np.abs(r - 0.93)) * rad
    ring_seam = (r > 0.5) & (r < 0.93)
    d = np.where(ring_seam, np.minimum(d_sec, ring), np.abs(r - 0.5) * rad)
    seam = np.clip(1.0 - (d - seam_w) / (0.7 / px_tile), 0, 1)
    seam = np.where(r < 0.5 - 0.01, 0.0, seam)
    jit = 0.95 + 0.1 * hash2(k, sec_i, n, 9)
    c = c * jit[:, None]
    return c * (1 - 0.5 * seam)[:, None]


def ambient_occlusion(P, N, solid, s):
    H, W = solid.shape
    occ = np.zeros((H, W))
    cnt = np.zeros((H, W))
    rng = np.random.RandomState(4)
    radii = [0.012, 0.035]  # in tile units of screen travel (px = r * 90.5 * scale * ss)
    for rfrac in radii:
        rpx = max(2, int(rfrac * 90.5 * s / 1.0 * 1.0))
        for a in range(10):
            ang = a * 2 * math.pi / 10 + rfrac * 40
            dx, dy = int(round(math.cos(ang) * rpx)), int(round(math.sin(ang) * rpx))
            Pq = np.roll(P, (dy, dx), (0, 1))
            sq = np.roll(solid, (dy, dx), (0, 1))
            v = Pq - P
            dist = np.linalg.norm(v, axis=-1) + 1e-6
            h = (v * N).sum(-1) / dist
            contrib = np.clip(h - 0.12, 0, 1) * (1.0 / (1.0 + (dist / 0.11) ** 2))
            occ += np.where(sq & solid, contrib, 0)
            cnt += 1
    return np.clip(occ / cnt * 2.4, 0, 1)


def edges(out, ids, N, prim, solid, r, emissive):
    H, W = ids.shape
    res = out.copy()
    # silhouette outline and part boundaries
    for dy, dx in ((-r, -r), (r, r), (-r, r), (r, -r)):
        sid = np.roll(ids, (dy, dx), (0, 1))
        sp = np.roll(prim, (dy, dx), (0, 1))
        sn = np.roll(N, (dy, dx), (0, 1))
        ssol = np.roll(solid, (dy, dx), (0, 1))
        sil = solid & ~ssol
        res = np.where(sil[..., None], res * 0.45, res)
        part = solid & ssol & (sid != ids) & (sp != prim)
        res = np.where(part[..., None], res * 0.80, res)
        # convex edge of the same primitive: lit where this face points more upward than its neighbour
        convex = solid & ssol & (sid != ids) & (sp == prim) & (N[..., 2] > sn[..., 2] + 0.2)
        res = np.where(convex[..., None] & (dy < 0), np.clip(res * 1.18 + 0.04, 0, 1), res)
    return res
