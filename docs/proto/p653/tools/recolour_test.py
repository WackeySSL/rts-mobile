import sys, json
sys.path.insert(0, '/tmp/p653/docs/proto/p653/tools')
from pipeline import *
import colorsys

def srgb8(lin_pm, a):
    s = np.where(a[..., None] > 1e-4, lin_pm / np.maximum(a[..., None], 1e-4), 0)
    return np.round(to_srgb(s) * 255).astype(np.int32)

res = {}
for f, dens in ((8, '1x'), (4, '2x')):
    for tag, hexmid, truth in (('Kobolt', KOBOLT[1], 'truthB_'), ('Signal', SIGNAL[1], 'truthO_')):
        for part in ('hull', 'turret'):
            for d in (3, 9):
                src = f'{RAW}heavy_tank_{part}_d{d:02d}.png'
                lin, a = box_down(*load_lin(src), f)
                tl, ta = box_down(*load_lin(f'{RAW}{truth}heavy_tank_{part}_d{d:02d}.png'), f)
                s8 = srgb8(lin, a)
                t8 = srgb8(tl, ta)
                vis = a > 0.5
                team = vis & (np.abs(s8 - t8).max(-1) > 3)       # pixels the team colour touches
                rl, ra = (recolour2 if len(sys.argv)>1 and sys.argv[1]=='2' else recolour)(lin, a, hexmid)
                r8 = srgb8(rl, ra)
                err = np.abs(r8 - t8).max(-1)
                # exact-hex match of the existing swap on the sentinel's three hexes
                keys = [tuple(int(h[i:i+2], 16) for i in (1, 3, 5)) for h in ('#F07AF0', '#D234D2', '#9A1F9A')]
                exact = np.zeros(vis.shape, bool)
                for k in keys:
                    exact |= (s8 == np.array(k)).all(-1)
                # remaining magenta fringe: hue 270..340, sat>0.25, value>0.12 after recolour
                hsv = np.zeros(r8.shape)
                mx = r8.max(-1) / 255.0; mn = r8.min(-1) / 255.0
                sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
                R, G, B = [r8[..., i] / 255.0 for i in range(3)]
                hue = np.degrees(np.arctan2(np.sqrt(3) * (G - B), 2 * R - G - B)) % 360
                fring = vis & (hue > 270) & (hue < 345) & (sat > 0.25) & (mx > 0.12)
                if tag == 'Kobolt':
                    fring &= (r8[..., 1] < np.minimum(r8[..., 0], r8[..., 2]) - 8)
                else:
                    fring &= (r8[..., 1] < np.minimum(r8[..., 0], r8[..., 2]) - 8)
                e = err[team]
                if e.size == 0:
                    continue
                res[f'{dens}/{tag}/{part}/d{d}'] = dict(
                    team_px=int(team.sum()), exact_hex_px=int((exact & vis).sum()),
                    mean_err=float(e.mean()), p95=float(np.percentile(e, 95)), p99=float(np.percentile(e, 99)),
                    max=int(e.max()), over12=int((e > 12).sum()), over24=int((e > 24).sum()),
                    fringe_px=int(fring.sum()))
for k, v in res.items():
    print(k, v)
tot = {}
for dens in ('1x', '2x'):
    sel = [v for k, v in res.items() if k.startswith(dens)]
    print(dens, 'TOTAL team_px', sum(v['team_px'] for v in sel), 'exact_hex', sum(v['exact_hex_px'] for v in sel),
          'over12', sum(v['over12'] for v in sel), 'over24', sum(v['over24'] for v in sel), 'fringe', sum(v['fringe_px'] for v in sel),
          'mean_err', np.mean([v['mean_err'] for v in sel]), 'worst_p99', max(v['p99'] for v in sel), 'max', max(v['max'] for v in sel))
json.dump(res, open(SC + 'recolour_numbers.json', 'w'), indent=1)
