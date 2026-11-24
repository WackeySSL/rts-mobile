#!/usr/bin/env python3
"""P601 (P637) hand edits of the Figma AI building picture, recorded for CREDITS:
1. the flat green background is keyed out (soft edge, green spill removed);
2. the picture is squashed vertically so the apron is a true 2:1 diamond (the model drew it at
   about 1.55:1, a camera that is too high);
3. it is scaled so the apron is 2.92 tiles wide (373.8 px at scale 1.0, the artgen footprint).
No repainting. Usage: proto_p601_ai_prep.py RAW.png OUT.png -> OUT is RGBA at scale 1.0 and a
JSON beside it holds the ground origin. Exploration only."""
import json
import sys

import numpy as np
from PIL import Image

raw = Image.open(sys.argv[1]).convert("RGB")
a = np.asarray(raw, dtype=np.float64)
r, g, b = a[..., 0], a[..., 1], a[..., 2]
d = g - np.maximum(r, b)
alpha = np.clip((110.0 - d) / 70.0, 0, 1)
g2 = np.where(d > 0, np.maximum(r, b), g)  # despill
rgb = np.dstack([r, g2, b])
rgba = np.dstack([rgb, alpha * 255]).astype(np.uint8)
im = Image.fromarray(rgba, "RGBA")
solid = alpha > 0.5
ys, xs = np.nonzero(solid)
x0, x1 = xs.min(), xs.max()
left_y = ys[xs <= x0 + 3].mean()
right_y = ys[xs >= x1 - 3].mean()
cy = (left_y + right_y) / 2.0
cx = (x0 + x1) / 2.0
width = x1 - x0
# squash about the apron plane's centre row so that the diamond is 2:1
bottom = ys.max()
half_h = bottom - cy
want = width / 4.0
sq = want / half_h
H = im.height
new_h = int(round(H * sq))
im2 = im.resize((im.width, new_h), Image.Resampling.LANCZOS)
cy2 = cy * sq
k = (2.92 * 128.0) / width * (float(sys.argv[3]) if len(sys.argv) > 3 else 1.0)  # to the given scale
final = im2.resize((int(round(im2.width * k)), int(round(im2.height * k))), Image.Resampling.LANCZOS)
box = final.getbbox()
final = final.crop(box)
origin = [cx * k - box[0], cy2 * k - box[1]]
final.save(sys.argv[2], optimize=True)
json.dump({"origin": origin, "squash": sq, "scale": k, "ratio_before": half_h / (width / 2.0), "size": final.size}, open(sys.argv[2] + ".json", "w"))
print(final.size, origin, "squash", round(sq, 3), "ratio before", round(half_h / (width / 2.0), 3))
