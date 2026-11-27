"""The bake's post (ADR 0053 section 5, plan row P656b): raw frames to 1x texels, MIT.

Usage: python3 -I tools/prerender/post.py OUT [--exposure G]
Reads OUT/*.png and OUT/bake_info.json (written by bake_model.gd), writes OUT/post/*.png.
Per frame: a box filter from the bake scale to 1x in linear light on premultiplied colour, one
exposure gain (linear, no tone curve, no sharpen, no grade), then an 8-bit RGBA PNG whose bytes
depend only on the pixels. A `*_shadow.png` is black at the shadow band's alpha. A frame with a
clipped sentinel pixel is refused: nothing is written and the exit code is 6.
"""
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# A clipped pixel, defined on the 1x output: opaque (alpha 255), in the key band (hue 300 +-20
# degrees, HSV saturation >= 0.30, ArtPalette.BAND_*), and R or B at 255 (the light is lost above
# it), or any channel at 0 while R and B are both >= 8 (a lost channel, not deep shade).
HUE, HALF_BAND, MIN_SAT, DARK = 300.0, 20.0, 0.30, 8
SAVE_ARGS = {"format": "PNG", "optimize": False, "compress_level": 9}


def to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c):
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.maximum(c, 0.0), 1 / 2.4) - 0.055)


def box_filter(raw, factor, exposure):
    """raw: HxWx4 uint8 at `factor` texels per output texel; returns the 1x uint8 RGBA."""
    h, w = raw.shape[0] // factor * factor, raw.shape[1] // factor * factor
    a = raw[:h, :w].astype(np.float64) / 255.0
    alpha = a[..., 3]
    lin = to_linear(a[..., :3]) * alpha[..., None]
    n = factor * factor
    lin = lin.reshape(h // factor, factor, w // factor, factor, 3).sum(axis=(1, 3)) / n
    alpha = alpha.reshape(h // factor, factor, w // factor, factor).sum(axis=(1, 3)) / n
    rgb = np.where(alpha[..., None] > 0, lin / np.maximum(alpha[..., None], 1e-12), 0.0)
    rgb = to_srgb(np.clip(rgb * exposure, 0.0, 1.0))
    return np.concatenate([np.round(rgb * 255), np.round(alpha[..., None] * 255)], axis=-1).astype(np.uint8)


def clipped(frame):
    """The mask of clipped sentinel pixels of a 1x frame (see the definition above)."""
    rgb = frame[..., :3].astype(np.int32)
    top, low = rgb.max(axis=-1), rgb.min(axis=-1)
    sat = (top - low) / np.maximum(top, 1)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hue = (np.degrees(np.arctan2(np.sqrt(3.0) * (g - b), 2.0 * r - g - b)) + 360.0) % 360.0
    key = (frame[..., 3] == 255) & (sat >= MIN_SAT) & (np.abs(hue - HUE) <= HALF_BAND)
    lost = (np.maximum(r, b) == 255) | ((low == 0) & (np.minimum(r, b) >= DARK))
    return key & lost


def main(argv):
    out = Path(argv[1])
    exposure = float(argv[argv.index("--exposure") + 1]) if "--exposure" in argv else 1.0
    info = json.loads((out / "bake_info.json").read_text())
    done, refused = {}, []
    for path in sorted(out.glob("*.png")):
        with Image.open(path) as image:
            frame = box_filter(np.asarray(image.convert("RGBA")), int(info["scale"]), exposure)
        if re.search(r"_shadow(_d\d\d)?$", path.stem):
            frame[..., :3] = 0
            frame[..., 3] = np.round(frame[..., 3] * float(info["shadow_alpha"]))
        bad = int(clipped(frame).sum())
        if bad:
            refused.append("post: REFUSED %s: %d clipped sentinel pixels" % (path.name, bad))
        done[path.name] = frame
    if refused or not done:
        print("\n".join(refused or ["post: no frames in %s" % out]), file=sys.stderr)
        return 6
    (out / "post").mkdir(exist_ok=True)
    for name, frame in done.items():
        Image.fromarray(frame, "RGBA").save(out / "post" / name, **SAVE_ARGS)
    print("post: %d frames in %s" % (len(done), out / "post"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
