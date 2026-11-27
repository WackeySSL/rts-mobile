# tools/prerender: the pre-render bake tool

Renders our own 3D models to raw frames (ADR 0053, plan row P656a). Code here is MIT, like
`tools/artgen`. The model data it reads, `assets/art/models/<faction>/<id>_detail.tres`, is
(c) AppCode ApS, all rights reserved (ADR 0046). P656a shipped the core, P656b the post and the
manifest. No building data and no terrain kit yet (P656c).

## What is here

| File | Job |
| --- | --- |
| `BakeMesh.gd` | Mesh builder: `ArtMesh` faces and plane-clipped solids with bevel strips, outward normals, the 60,000-triangle cap (refused with the id and count, never cut short). |
| `BakeShapes.gd` | Boxes, bars, cylinders and cones, domes, tori on top of `BakeMesh`. |
| `DetailModel.gd`, `DetailPart.gd`, `DetailMaterial.gd` | The `_detail.tres` schema: materials, parts (shape, place, mirror, repeat, seeded jitter) and a variation seed. Data only. |
| `BakeMaterials.gd`, `detail.gdshader` | One shader for every material: weathering from position and normal, team paint stays in hue. |
| `BakeRig.gd` | Orthographic camera at `IsoProjection`'s 2:1 view, sun along `ArtShadow`'s reach, fill, sky, SSAO. Every projection constant is read, not typed. |
| `bake_model.gd` | The scene entry: one model, every part and direction of its sheet, raw PNG frames, the shadow frame and `bake_info.json`. |
| `post.py` | The post: box filter to 1x, exposure gain, PNG write, the clipped-sentinel refusal. |
| `ArtManifest.gd`, `write_manifest.gd` | The manifest resource and its writer. |
| `requirements.txt` | The Python pins, read by `prerender.sh`'s preflight. |

Units are ready: a hull and turret (or head) rig, 16 directions (8 for a squad, from the sheet's
`counts`), and the turret seated by `IsoSheetDef.mounts`.

## Run it

```
bash scripts/prerender.sh --preflight
bash scripts/prerender.sh --model res://assets/art/models/fossil/heavy_tank_detail.tres \
    --sheet res://assets/art/iso/fossil/veh/heavy_tank_sheet.tres --out /tmp/prerender \
    [--dirs all|6,7] [--scale 8] [--team "#D234D2"] [--composite] [--no-ssao]
```

Frames are `<out>/<id>_<part>_dNN.png` at `--scale` texels per art px (default 8), transparent
background. `--exposure G` (default 1.0) is the post's one gain; `--publish res://RES_DIR` copies
the posted frames there and lists them in the manifest. `--composite` adds `<id>_both_dNN.png`, hull and turret
together. The run prints the renderer line, for example `Vulkan 1.4.318 - Forward+ - llvmpipe`.

## The pinned image

`scripts/prerender.sh` checks it before any render and installs nothing: Ubuntu 24.04.5 LTS;
`mesa-vulkan-drivers`, `libgl1-mesa-dri`, `libglx-mesa0`, `libgbm1`, `mesa-libgallium`
25.2.8-0ubuntu0.24.04.5; `libllvm20` 1:20.1.2-0ubuntu1~24.04.3; `xvfb`
2:21.1.12-1ubuntu1.9; Python 3.13, numpy 2.5.3, Pillow 12.3.0; Godot 4.7.2. The Python pins
are in `requirements.txt`, which the script reads. The bake runs Forward+ over Vulkan
(lavapipe) under `xvfb-run`; the game stays on Compatibility.

| Exit | Meaning |
| --- | --- |
| 0 | Done (preflight: the image is the pin) |
| 1 | The bake failed (Godot error, SCRIPT ERROR, no frame) |
| 2 | Usage |
| 3 | A tool is missing (Godot, xvfb-run, dpkg-query, python3) |
| 4 | A version differs; one line per package, expected and found |
| 5 | `--check` only: this machine's renderer stamp is not the manifest's; nothing is compared |
| 6 | The post refused the frames (a clipped sentinel pixel); frame and count are named |

`PRERENDER_VERSIONS_FILE` and `PRERENDER_TOOLS` make the checks testable without the real
packages (`tests/tools/prerender/test_prerender_script.gd`).

## The shadow frame

`bake_model.gd` flattens the model's solid parts along +gx by `ArtShadow.REACH` per tile of
height and renders them unlit black (it is in the bake because the geometry is only there). It
writes `bake_info.json` with the scale and the alpha, the midpoint of `same_scene.tres`'s
`shadow_alpha` band (0.35 now, read, never typed). The post turns the frame's coverage into that
alpha.

## The post

`python3 -I tools/prerender/post.py OUT [--exposure G]` reads only `OUT`, uses no network and
writes `OUT/post/`. Per frame: sRGB to linear, premultiply, box filter from the bake scale to 1x,
one exposure gain in linear light (no tone curve, sharpen or grade), un-premultiply, back to sRGB,
8-bit RGBA with straight alpha. The PNG is saved with
`Image.save(path, format="PNG", optimize=False, compress_level=9)` from a bare array: the file
holds IHDR, IDAT and IEND only (no tIME, gAMA, iCCP, sRGB, pHYs or text), so the bytes depend on
the pixels alone.

**Clipped sentinel pixel**, tested on the 1x frame: alpha 255; hue within 300 +- 20 degrees and
HSV saturation at least 0.30 (`ArtPalette.BAND_*`); and either R or B at 255 (the light above it
is lost, the recolour cannot restore it), or any channel at 0 while R and B are both at least 8
(a lost channel, not deep shade). Any such pixel refuses the whole run: exit 6, nothing written,
each frame named with its pixel count.

## The manifest

`assets/art/prerender/manifest.tres` is an `ArtManifest`: a `stamp` and sorted `entries`, one per
PNG, `path|sha256|bytes|WxH|source=sha256;...|exposure`. The sources are the model's
`_detail.tres`, its sheet and its `ArtModel`. The stamp is Godot's renderer line plus the Mesa
version, for example `Vulkan 1.4.318 - Forward+ - llvmpipe / Mesa 25.2.8-0ubuntu0.24.04.5`. The
file is written as text, so the same inputs give the same bytes. It is empty until the first art
row (P656c). `tests/art/test_prerender_manifest.gd` checks hashes, bytes, sizes, unlisted PNGs
under `assets/art/iso` and `assets/art/terrain`, the per-frame byte budgets, the kit total,
each frame's size against its sheet and a source hash that moved.

`bash scripts/prerender.sh --check` asks Godot for this machine's stamp. If it is the manifest's,
it re-bakes every listed model with the default flags and its recorded exposure and compares the
bytes (exit 1 on a difference). Any other stamp exits 5 and renders nothing: a new image is a
re-bake row (ADR 0053 section 5).

Caveat: `--check` re-bakes with the default flags plus the recorded exposure. Any other flag
(`--scale`, `--no-ssao`, `--dirs`, `--team`) is not recorded in the manifest, so art baked with a
non-default flag will show as a difference.

CI installs the post's Python pins (`python3 -m pip install -r tools/prerender/requirements.txt`
in a Python 3.13 setup-python step); `verify.sh` installs nothing and fails with that command if
numpy or Pillow is missing.
