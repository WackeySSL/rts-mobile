#!/usr/bin/env python3
"""P601 round 2: turns two Figma exports of one frame (on white and on black) into one RGBA PNG
(difference matting). Usage: proto_p601_matte.py WHITE.png BLACK.png OUT.png"""
import sys

import numpy as np
from PIL import Image

w = np.asarray(Image.open(sys.argv[1]).convert("RGB"), dtype=np.float64)
b = np.asarray(Image.open(sys.argv[2]).convert("RGB"), dtype=np.float64)
alpha = 1.0 - (w - b).mean(-1) / 255.0
alpha = np.clip(alpha, 0, 1)
rgb = np.where(alpha[..., None] > 1e-3, b / np.maximum(alpha[..., None], 1e-3), 0)
out = np.dstack([np.clip(rgb, 0, 255), alpha * 255]).astype(np.uint8)
Image.fromarray(out, "RGBA").save(sys.argv[3], optimize=True)
