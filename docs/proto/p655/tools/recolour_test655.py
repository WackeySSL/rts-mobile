"""Recolour error of P653's hue-key recolour2 on the detailed tank, against a full re-render with the team material set to the target."""
import sys, json
sys.path.insert(0, '/tmp/p655/docs/proto/p655/tools')
from build655 import *

def srgb8(lin_pm, a):
    s = np.where(a[..., None] > 1e-4, lin_pm / np.maximum(a[..., None], 1e-4), 0)
    return np.round(to_srgb(s) * 255).astype(np.int32)

res = {}
for f, dens in ((8, '1x'), (4, '2x')):
    for tag, hexmid, truth in (('Kobolt', KOBOLT[1], 'truth_B_'), ('Signal', SIGNAL[1], 'truth_O_')):
        for part in ('hull', 'turret'):
            for d in (3, 9):
                lin, a = box_down(*load_lin(f'{RAW5}heavy_tank_{part}_d{d:02d}.png'), f)
                tl, ta = box_down(*load_lin(f'{RAW5}{truth}heavy_tank_{part}_d{d:02d}.png'), f)
                s8, t8 = srgb8(lin, a), srgb8(tl, ta)
                vis = a > 0.5
                team = vis & (np.abs(s8 - t8).max(-1) > 3)
                rl, ra = recolour2(lin, a, hexmid)
                r8 = srgb8(rl, ra)
                err = np.abs(r8 - t8).max(-1)
                R, G, B = [r8[..., i] / 255.0 for i in range(3)]
                mx = r8.max(-1) / 255.0; mn = r8.min(-1) / 255.0
                sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
                hue = np.degrees(np.arctan2(np.sqrt(3) * (G - B), 2 * R - G - B)) % 360
                fring = vis & (hue > 270) & (hue < 345) & (sat > 0.25) & (mx > 0.12) & (r8[..., 1] < np.minimum(r8[..., 0], r8[..., 2]) - 8)
                sraw = np.where(a[..., None] > 1e-4, lin / np.maximum(a[..., None], 1e-4), 0)
                clip = team & (np.maximum(sraw[..., 0], sraw[..., 2]) > 0.995)
                e = err[team]
                if e.size == 0:
                    continue
                res[f'{dens}/{tag}/{part}/d{d}'] = dict(team_px=int(team.sum()), mean_err=float(e.mean()), p95=float(np.percentile(e, 95)), p99=float(np.percentile(e, 99)), max=int(e.max()), over12=int((e > 12).sum()), over24=int((e > 24).sum()), fringe_px=int(fring.sum()), clipped_sentinel_px=int(clip.sum()))
for k, v in res.items():
    print(k, v)
for dens in ('1x', '2x'):
    sel = [v for k, v in res.items() if k.startswith(dens)]
    tp = sum(v['team_px'] for v in sel)
    print(dens, 'TOTAL team_px', tp, 'mean_err(weighted)', sum(v['mean_err'] * v['team_px'] for v in sel) / tp, 'worst_p99', max(v['p99'] for v in sel), 'max', max(v['max'] for v in sel), 'over12', sum(v['over12'] for v in sel), 'over24', sum(v['over24'] for v in sel), 'fringe', sum(v['fringe_px'] for v in sel), 'clipped', sum(v['clipped_sentinel_px'] for v in sel))
json.dump(res, open(SC5 + 'recolour_numbers.json', 'w'), indent=1)
