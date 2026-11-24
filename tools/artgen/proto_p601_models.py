#!/usr/bin/env python3
"""P601 prototype: writes the two richer models (tank and building) as ArtModel .tres files.

Exploration only. Primitive lines use the generator's own grammar (ArtPrim): shape part material
cx cy z0 sx sy sz [axis=] [sides=] [taper=] [slope=]. Loops here replace hand-typing the many
small parts (track links, grille slats). Run: python3 tools/artgen/proto_p601_models.py
"""
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "docs", "proto", "p601", "models")


def f(v):
    return ("%.3f" % v).rstrip("0").rstrip(".") if v != 0 else "0"


def line(shape, part, mat, cx, cy, z0, sx, sy, sz, **opt):
    words = [shape, part, mat, f(cx), f(cy), f(z0), f(sx), f(sy), f(sz)]
    words += ["%s=%s" % (k, v if isinstance(v, str) else f(v)) for k, v in opt.items()]
    return " ".join(words)


def tank(r2=False):
    A = "armour" if r2 else "team"
    L = []
    h = lambda *a, **k: L.append(line("box", "hull", *a, **k))
    pr = lambda *a, **k: L.append(line("prism", "hull", *a, **k))
    wd = lambda *a, **k: L.append(line("wedge", "hull", *a, **k))
    for s in (-1, 1):
        yc = s * 0.40
        # track body, the links on its top run, sprocket, idler and road wheels
        h("rubber", 0, yc, 0.0, 1.22, 0.20, 0.20)
        for i in range(19):
            x = -0.558 + i * 0.062
            h("darksteel" if i % 2 else "rubber", x, yc, 0.20, 0.050, 0.20, 0.028)
            if r2:
                h("gunmetal", x + 0.005, yc, 0.228, 0.014, 0.17, 0.012)
                h("wornsteel", x - 0.02, yc - 0.092, 0.2, 0.008, 0.012, 0.03)
                h("wornsteel", x - 0.02, yc + 0.092, 0.2, 0.008, 0.012, 0.03)
        for x in (-0.56, 0.56):
            pr("darksteel", x, s * 0.515, 0.02, 0.21, 0.03, 0.21, axis="y", sides=10)
            pr("wornsteel", x, s * 0.535, 0.075, 0.09, 0.02, 0.09, axis="y", sides=8)
        for x in (-0.36, -0.18, 0.0, 0.18, 0.36):
            pr("darksteel", x, s * 0.515, 0.03, 0.15, 0.03, 0.15, axis="y", sides=8)
            pr("gunmetal", x, s * 0.535, 0.075, 0.06, 0.02, 0.06, axis="y", sides=6)
        # side skirt: four armour panels with gaps, hazard end plates front and rear
        for x in (-0.42, -0.14, 0.14, 0.42):
            h(A, x, s * 0.545, 0.11, 0.26, 0.035, 0.15)
        h("hazard", 0.605, s * 0.50, 0.07, 0.02, 0.10, 0.11)
        h("hazard", -0.605, s * 0.50, 0.07, 0.02, 0.10, 0.11)
        # front mudguard slope over the track nose
        wd(A, 0.50, s * 0.40, 0.225, 0.22, 0.22, 0.05, slope=1)
        # add-on armour blocks on the hull flank
        for x in (-0.40, -0.22, -0.04, 0.14, 0.32):
            h("gunmetal", x, s * 0.345, 0.21, 0.15, 0.04, 0.09)
        # exhaust
        pr("darksteel", -0.50, s * 0.22, 0.31, 0.075, 0.075, 0.09, sides=8)
        pr("wornsteel", -0.50, s * 0.22, 0.40, 0.05, 0.05, 0.01, sides=8)
    h("gunmetal", 0, 0, 0.03, 1.14, 0.56, 0.17)               # lower tub
    h(A, -0.04, 0, 0.20, 1.0, 0.62, 0.11)                # upper deck
    wd(A, 0.59, 0, 0.20, 0.26, 0.62, 0.11, slope=1)      # glacis
    h("darksteel", 0.725, 0, 0.09, 0.03, 0.52, 0.12)          # lower front plate
    h("hazard", 0.742, 0, 0.115, 0.012, 0.46, 0.05)           # hazard bar
    for s in (-1, 1):
        h("darksteel", 0.70, s * 0.22, 0.215, 0.05, 0.07, 0.05)  # lamp guard
        h("lamp", 0.725, s * 0.22, 0.225, 0.02, 0.05, 0.03)
    # engine deck with grille slats, rear stowage rail, antenna
    h("darksteel", -0.40, 0, 0.31, 0.34, 0.44, 0.03)
    for i in range(7):
        h("gunmetal", -0.40, -0.18 + i * 0.06, 0.34, 0.30, 0.025, 0.014)
    h("gunmetal", -0.575, 0, 0.215, 0.05, 0.50, 0.085)
    pr("darksteel", -0.35, 0.27, 0.31, 0.018, 0.018, 0.34, sides=4)
    if r2:
        h("armourdk", -0.10, 0, 0.31, 0.26, 0.40, 0.008)       # recessed deck plate
        h("team", -0.575, 0, 0.30, 0.05, 0.50, 0.012)           # team marker bar, rear
        h("gunmetal", 0.20, 0, 0.31, 0.10, 0.30, 0.012)
    # turret
    t = lambda shape, *a, **k: L.append(line(shape, "turret", *a, **k))
    t("prism", "darksteel", 0, 0, 0, 0.68, 0.68, 0.035, sides=12)
    t("box", A, -0.06, 0, 0.035, 0.64, 0.54, 0.075)
    t("prism", A, -0.07, 0, 0.11, 0.62, 0.52, 0.085, sides=4, taper=0.74)
    t("wedge", A, 0.29, 0, 0.035, 0.20, 0.54, 0.075, slope=1)
    t("box", "darksteel", 0.405, 0, 0.055, 0.07, 0.26, 0.115)  # mantlet
    t("box", A, -0.44, 0, 0.04, 0.12, 0.46, 0.12)         # bustle
    for x in (-0.47, -0.41):
        t("box", "gunmetal", x, 0, 0.04, 0.02, 0.48, 0.125)
    for s in (-1, 1):
        t("box", "gunmetal", -0.10, s * 0.30, 0.045, 0.30, 0.04, 0.08)  # stowage bins
        t("box", "hazard", 0.12, s * 0.275, 0.05, 0.03, 0.01, 0.06)
    t("prism", "gunmetal", -0.17, 0.10, 0.195, 0.16, 0.16, 0.04, sides=10)   # commander ring
    t("prism", "darksteel", -0.17, 0.10, 0.235, 0.11, 0.11, 0.02, sides=10)
    t("prism", "darksteel", -0.10, 0.10, 0.255, 0.15, 0.03, 0.03, axis="x", sides=6)  # MG
    t("box", "gunmetal", 0.06, -0.14, 0.195, 0.14, 0.12, 0.07)                 # sight head
    t("box", "darksteel", 0.135, -0.14, 0.215, 0.015, 0.09, 0.03)
    t("box", "wornsteel", -0.20, -0.12, 0.195, 0.10, 0.10, 0.025)              # roof hatch
    t("prism", "darksteel", 0.50, 0, 0.0825, 0.12, 0.105, 0.105, axis="x", sides=10)  # recoil sleeve
    t("prism", "gunmetal", 0.80, 0, 0.0925, 0.66, 0.065, 0.065, axis="x", sides=8)    # barrel
    t("prism", "darksteel", 0.72, 0, 0.0775, 0.11, 0.095, 0.095, axis="x", sides=8)   # fume extractor
    t("prism", "hazard", 0.97, 0, 0.088, 0.035, 0.074, 0.074, axis="x", sides=8)      # barrel band
    t("box", "darksteel", 1.145, 0, 0.0825, 0.09, 0.085, 0.075)                # muzzle brake
    if r2:
        t("box", "team", -0.12, 0, 0.195, 0.22, 0.30, 0.012)                   # team roof plate
        for s in (-1, 1):
            t("box", "team", -0.30, s * 0.275, 0.1, 0.16, 0.012, 0.05)         # team side flash
            t("box", "gunmetal", -0.30, s * 0.18, 0.115, 0.12, 0.1, 0.012)
    return L, "heavy_tank_p601b" if r2 else "heavy_tank_p601", "fossil", "veh", 0, (0, 0, 0.31), (
        "Nordvaern-style heavy tank: a low wide slab of dark gunmetal on two broad tracks with"
        " hazard-striped end plates, a stepped orange armour deck and glacis, a faceted orange"
        " turret with a rear bustle and a long gun with a hazard band.")


def building():
    L = []
    b = lambda *a, **k: L.append(line("box", "hull", *a, **k))
    p = lambda *a, **k: L.append(line("prism", "hull", *a, **k))
    w = lambda *a, **k: L.append(line("wedge", "hull", *a, **k))
    b("darksteel", 0, 0, 0, 2.92, 2.92, 0.05)                      # apron
    for i in range(10):                                            # hazard edge on the apron front
        b("hazard" if i % 2 == 0 else "rubber", 1.30, -1.2 + i * 0.27, 0.05, 0.12, 0.2, 0.012)
    p("gunmetal", 0, 0, 0.05, 2.62, 2.62, 0.07, sides=8)           # plinth ring
    p("team", 0, 0, 0.12, 2.46, 2.46, 0.26, sides=8)               # lower armour
    p("trim", 0, 0, 0.38, 2.52, 2.52, 0.06, sides=8)               # lower trim band
    p("team", 0, 0, 0.44, 2.46, 2.46, 0.28, sides=8, taper=0.84)   # sloped second tier
    p("trim", 0, 0, 0.72, 2.12, 2.12, 0.05, sides=8)               # upper trim band
    p("team", 0, 0, 0.77, 1.9, 1.9, 0.24, sides=8, taper=0.80)     # third tier
    p("gunmetal", 0, 0, 1.01, 1.55, 1.55, 0.06, sides=8)           # roof ring
    p("team", 0, 0, 1.07, 1.45, 1.45, 0.22, sides=8, taper=0.62)   # crown
    p("darksteel", 0, 0, 1.29, 0.82, 0.82, 0.07, sides=8)          # sensor base
    p("gunmetal", 0, 0, 1.36, 0.68, 0.68, 0.14, sides=8, taper=0.6)
    b("glow", 0, 0, 1.43, 0.12, 0.12, 0.03)
    p("wornsteel", 0, 0, 1.50, 0.04, 0.04, 0.38, sides=6)          # mast
    p("trim", 0, 0, 1.88, 0.12, 0.12, 0.05, sides=6)
    b("glow", 0, 0, 1.93, 0.05, 0.05, 0.03)
    # corner generator pylons
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * 1.20, sy * 1.20
            b("gunmetal", cx, cy, 0.05, 0.40, 0.40, 0.22)
            p("team", cx, cy, 0.27, 0.34, 0.34, 0.10, sides=4, taper=0.7)
            b("glow", cx, cy, 0.37, 0.07, 0.07, 0.025)
    # gate hangar on the +x side: ramp, frame, hazard door, glow slits
    w("darksteel", 1.50, 0, 0.0, 0.44, 0.9, 0.09, slope=1)
    b("gunmetal", 1.26, 0, 0.05, 0.14, 1.0, 0.36)
    b("rubber", 1.345, 0, 0.09, 0.03, 0.62, 0.27)
    b("hazard", 1.365, 0, 0.09, 0.012, 0.62, 0.035)
    for s in (-1, 1):
        b("glow", 1.355, s * 0.40, 0.13, 0.014, 0.03, 0.19)
        b("team", 1.30, s * 0.55, 0.05, 0.16, 0.08, 0.36)
    # +y side service hatch with hazard sill
    b("gunmetal", 0, 1.26, 0.05, 0.9, 0.12, 0.30)
    b("rubber", 0, 1.325, 0.08, 0.6, 0.03, 0.22)
    b("hazard", 0, 1.34, 0.08, 0.6, 0.012, 0.03)
    b("glow", 0.36, 1.335, 0.12, 0.03, 0.014, 0.14)
    # roof vents on the second tier ledge
    for ang in range(4):
        sx = (1, 1, -1, -1)[ang]
        sy = (1, -1, -1, 1)[ang]
        b("darksteel", sx * 0.78, sy * 0.78, 0.72, 0.30, 0.30, 0.05)
        for i in range(4):
            b("gunmetal", sx * 0.78, sy * 0.78 - 0.105 + i * 0.07, 0.77, 0.26, 0.025, 0.014)
    return L, "helix_hq_p601", "renew", "bld", 3, (0, 0, 0), (
        "Helix-style command hold: a low faceted eight-sided armoured hall of stepped, sloped blue"
        " panels with dark trim bands on a gunmetal plinth, a crowned sensor spire, four corner"
        " pylons and a hazard-edged hangar gate.")


def nord():
    """A Nordvaern vehicle works in the same style (fixed orange armour, gunmetal, hazard)."""
    L = []
    b = lambda *a, **k: L.append(line("box", "hull", *a, **k))
    p = lambda *a, **k: L.append(line("prism", "hull", *a, **k))
    w = lambda *a, **k: L.append(line("wedge", "hull", *a, **k))
    b("darksteel", 0, 0, 0, 2.92, 2.92, 0.05)
    for i in range(10):
        b("hazard" if i % 2 == 0 else "rubber", -1.32 + i * 0.29, 1.36, 0.05, 0.2, 0.1, 0.012)
        b("hazard" if i % 2 == 0 else "rubber", 1.36, -1.32 + i * 0.29, 0.05, 0.1, 0.2, 0.012)
    # main hall
    b("gunmetal", -0.35, -0.1, 0.05, 2.0, 2.0, 0.16)                 # plinth course
    b("armour", -0.35, -0.1, 0.21, 2.0, 2.0, 0.62)                   # hall walls
    b("armourdk", -0.35, -0.1, 0.83, 2.04, 2.04, 0.05)               # eave band
    b("gunmetal", -0.35, -0.1, 0.88, 1.8, 1.8, 0.08)                 # roof deck
    for i in range(3):                                               # roof vent blocks with slats
        cx = -0.95 + i * 0.6
        b("darksteel", cx, -0.55, 0.96, 0.4, 0.5, 0.14)
        for k in range(4):
            b("gunmetal", cx, -0.7 + k * 0.1, 1.1, 0.36, 0.03, 0.014)
    b("armour", -0.2, 0.55, 0.96, 1.2, 0.5, 0.2)                     # roof annex
    b("team", -0.2, 0.55, 1.16, 0.5, 0.3, 0.014)                     # team marker plate
    for cx, cy in ((-1.0, 0.1), (-0.55, 0.1)):                       # twin stacks
        p("darksteel", cx, cy, 0.96, 0.3, 0.3, 0.7, sides=10)
        p("hazard", cx, cy, 1.5, 0.32, 0.32, 0.06, sides=10)
        p("wornsteel", cx, cy, 1.66, 0.26, 0.26, 0.02, sides=10)
    # loading bay on +x: big doors, gantry, ramp
    b("darksteel", 0.67, -0.1, 0.05, 0.1, 1.5, 0.52)
    b("rubber", 0.73, -0.1, 0.08, 0.04, 1.3, 0.42)
    b("hazard", 0.76, -0.1, 0.08, 0.012, 1.3, 0.05)
    for sy in (-0.5, 0.5):
        b("gunmetal", 0.78, -0.1 + sy, 0.05, 0.16, 0.16, 0.7)
    b("gunmetal", 0.78, -0.1, 0.75, 0.16, 1.2, 0.1)
    w("darksteel", 1.2, -0.1, 0.0, 0.7, 1.3, 0.1, slope=1)
    # fuel tanks in the +x/-y corner
    p("gunmetal", 1.05, -0.95, 0.05, 0.5, 0.9, 0.5, axis="y", sides=12)
    p("darksteel", 1.05, -0.95, 0.3, 0.12, 0.92, 0.1, axis="y", sides=8)
    p("hazard", 1.05, -1.27, 0.05, 0.5, 0.05, 0.5, axis="y", sides=12)
    # side crane arm on +y
    b("gunmetal", -1.3, 1.1, 0.05, 0.2, 0.2, 1.1)
    b("gunmetal", -0.6, 1.1, 1.05, 1.5, 0.16, 0.12)
    b("hazard", -0.6, 1.1, 1.17, 1.5, 0.16, 0.014)
    return L, "nord_works_p601", "fossil", "bld", 3, (0, 0, 0), (
        "Nordvaern-style vehicle works: a broad low orange armoured hall with a dark eave band, a flat roof"
        " with slatted vent blocks and twin hazard-banded stacks, a loading bay with a gantry on one side"
        " and a fuel tank in a corner, on a hazard-edged apron.")


def write(model):
    L, art_id, faction, cat, foot, mount, sil = model
    prims = ",\n".join('"%s"' % x for x in L)
    parts = [
        '[gd_resource type="Resource" script_class="ArtModel" format=3]\n',
        '[ext_resource type="Script" path="res://tools/artgen/ArtModel.gd" id="1_model"]\n',
        "[resource]", 'script = ExtResource("1_model")',
        'art_id = &"%s"' % art_id, 'faction = &"%s"' % faction, 'category = &"%s"' % cat,
    ]
    if foot:
        parts.append("footprint = %d" % foot)
    parts.append('silhouette = "%s"' % sil)
    parts.append("mount = Vector3(%s, %s, %s)" % tuple(f(v) for v in mount))
    parts.append("prims = PackedStringArray(\n%s\n)" % prims)
    path = os.path.join(OUT, art_id + ".tres")
    open(path, "w").write("\n".join(parts) + "\n")
    print(path, len(L), "prims")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write(tank())
    write(tank(True))
    write(nord())
    write(building())
