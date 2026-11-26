import sys, os, time, json, glob
sys.path.insert(0, '/tmp/p653/docs/proto/p653/tools')
from compose import *
OUTP = SC + 'final/'
os.makedirs(OUTP, exist_ok=True)
res = {}
def bbox_area(im, clear=1):
    bb = im.getchannel('A').point(lambda v: 255 if v > 8 else 0).getbbox()
    if not bb: return 0
    return (bb[2] - bb[0] + 2 * clear) * (bb[3] - bb[1] + 2 * clear)
for dens, f in (('1x', 8), ('2x', 4)):
    t0 = time.time(); size = 0; area = {'hull': 0, 'turret': 0, 'shadow': 0}; canvas = 0
    for d in range(16):
        for part in ('hull', 'turret', 'shadow'):
            p = f'{RAW}heavy_tank_{part}_d{d:02d}.png'
            if part == 'shadow':
                lin, a = box_down(*load_lin(p), f); img = to_image(np.zeros(a.shape + (3,)), a * 0.35)
            else:
                img = frame(p, f, SIGNAL[1])
            fn = f'{OUTP}tank_{dens}_{part}_d{d:02d}.png'
            img.save(fn, optimize=True)
            size += os.path.getsize(fn)
            area[part] += bbox_area(img) if part != 'shadow' else img.width * img.height
    dt = time.time() - t0
    res[f'tank_{dens}'] = dict(png_bytes=size, tight_texels_hull_turret=area['hull'] + area['turret'], shadow_texels=area['shadow'], post_seconds=dt)
    for bn in ('vehicle_factory',):
        bsz = 0; tex = 0
        fb = 2 if dens == '2x' else 4
        for part in ('hull', 'shadow'):
            p = f'{RAW}{bn}_{part}.png'
            if part == 'shadow':
                lin, a = box_down(*load_lin(p), fb); img = to_image(np.zeros(a.shape + (3,)), a * 0.35)
            else:
                img = frame(p, fb, SIGNAL[1])
            fn = f'{OUTP}{bn}_{dens}_{part}.png'; img.save(fn, optimize=True); bsz += os.path.getsize(fn); tex += img.width * img.height
        res[f'{bn}_{dens}'] = dict(png_bytes=bsz, texels_hull_shadow=tex)
# terrain patch final sizes
for dens, f in (('1x', 4), ('2x', 2)):
    lin, a = load_lin(RAW + 'terrain_patch.png'); lin, a = box_down(lin, a, f)
    c, a = grade(lin, a); img = to_image(c, a); fn = f'{OUTP}terrain_patch_{dens}.png'; img.save(fn, optimize=True)
    res[f'terrain_patch_{dens}'] = dict(png_bytes=os.path.getsize(fn), size=img.size, rgba_mb=img.width * img.height * 4 / 1e6)
def dsz(pattern): return sum(os.path.getsize(p) for p in glob.glob(pattern) if not p.endswith('.import'))
R = '/tmp/p653/assets/art/'
res['today_svg_bytes'] = dict(heavy_tank=dsz(R + 'iso/fossil/veh/heavy_tank_*'), vehicle_factory=dsz(R + 'iso/fossil/bld/vehicle_factory_*'),
    heavy_tank_model_tres=os.path.getsize(R + 'models/fossil/heavy_tank.tres'), vehicle_factory_model_tres=os.path.getsize(R + 'models/fossil/vehicle_factory.tres'))
res['tools_bytes'] = dict(prerender=dsz('/tmp/p653/tools/prerender/*.gd'), post=dsz('/tmp/p653/docs/proto/p653/tools/*.py'))
json.dump(res, open(SC + 'numbers.json', 'w'), indent=1, default=str)
print(json.dumps(res, indent=1, default=str))
