"""P653 prototype post-process: downsample the raw renders, recolour the team sentinel in linear
light, grade, and compose scenes. Pure numpy and PIL; nothing here ships."""
import numpy as np
from PIL import Image

SC = '/tmp/claude-0/-home-user-rts-mobile/f4088c2f-7ea6-5710-9456-77d97126fbd5/scratchpad/p653/'
RAW = SC + 'raw/'
SENT = np.array([0xD2, 0x34, 0xD2]) / 255.0  # sentinel mid
SIGNAL = ['#FF9446', '#E8681F', '#B04B12']
KOBOLT = ['#7AA2F7', '#3F6FE0', '#27479E']
TOP_DIV = 0.82


def hexrgb(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)]) / 255.0


def to_lin(c):
    c = np.asarray(c, dtype=np.float32)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def load_lin(path):
    """RGBA float arrays: linear premultiplied rgb (h,w,3), alpha (h,w)."""
    im = np.asarray(Image.open(path).convert('RGBA'), dtype=np.float32) / 255.0
    a = im[..., 3]
    lin = to_lin(im[..., :3]) * a[..., None]
    return lin, a


def box_down(lin, a, f):
    h, w = a.shape
    h2, w2 = h // f, w // f
    lin = lin[:h2 * f, :w2 * f].reshape(h2, f, w2, f, 3).mean(axis=(1, 3))
    a = a[:h2 * f, :w2 * f].reshape(h2, f, w2, f).mean(axis=(1, 3))
    return lin, a


def team_albedo(hexmid):
    return to_lin(hexrgb(hexmid))


A_SENT = team_albedo('#D234D2')


def recolour(lin_pm, a, hexmid, bias=0.0):
    """Key-subtract recolour on straight (unpremultiplied) linear light."""
    s = np.where(a[..., None] > 1e-4, lin_pm / np.maximum(a[..., None], 1e-4), 0.0)
    t = np.minimum(s[..., 0], s[..., 2]) - s[..., 1] * (1 + bias)
    t = np.maximum(t, 0.0)
    ref = min(A_SENT[0], A_SENT[2]) - A_SENT[1]
    k = (t / ref)[..., None]
    At = team_albedo(hexmid)
    out = s + k * (At - A_SENT)
    return np.clip(out, 0, None) * a[..., None], a


def recolour2(lin_pm, a, hexmid, g_floor=0.0):
    """Hue-keyed recolour that keeps the light's colour: the team share w of a pixel is the excess of
    min(R, B) over G (the sentinel is the only magenta), the team part is split into per-channel
    light E_c, and each E_c is multiplied by the target albedo instead of the sentinel's."""
    s = np.where(a[..., None] > 1e-4, lin_pm / np.maximum(a[..., None], 1e-4), 0.0)
    R, G, B = s[..., 0], s[..., 1], s[..., 2]
    mn = np.minimum(R, B)
    ref = (A_SENT[0] - A_SENT[1]) / A_SENT[0]
    w = np.clip((mn - G) / np.maximum(mn, 1e-5) / ref, 0.0, 1.0)
    w = np.where(mn > 1e-4, w, 0.0)
    ER = w * R / A_SENT[0]
    EB = w * B / A_SENT[2]
    EG = 0.5 * (ER + EB)
    E = np.stack([ER, EG, EB], axis=-1)
    At = team_albedo(hexmid)
    out = s + E * (At - A_SENT)
    return np.clip(out, 0, None) * a[..., None], a


GRADE = dict(contrast=0.12, sat=1.15, gain=1.35)


def grade(lin_pm, a, g=GRADE):
    s = np.where(a[..., None] > 1e-4, lin_pm / np.maximum(a[..., None], 1e-4), 0.0)
    c = to_srgb(s * g['gain'])
    lum = (c * np.array([0.299, 0.587, 0.114])).sum(-1, keepdims=True)
    c = lum + (c - lum) * g['sat']
    c = np.clip(c, 0, 1)
    c = c + g['contrast'] * (c - 0.5) * (1 - np.abs(2 * c - 1)) * 2  # gentle S curve
    return np.clip(c, 0, 1), a


def to_image(srgb, a):
    arr = np.concatenate([srgb, a[..., None]], axis=-1)
    return Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA')


def frame(path, f, hexmid=None, do_grade=True):
    lin, a = load_lin(path)
    lin, a = box_down(lin, a, f)
    if hexmid:
        lin, a = recolour2(lin, a, hexmid)
    if do_grade:
        c, a = grade(lin, a)
    else:
        c = to_srgb(np.where(a[..., None] > 1e-4, lin / np.maximum(a[..., None], 1e-4), 0))
    return to_image(c, a)
