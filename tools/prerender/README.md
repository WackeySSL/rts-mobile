# tools/prerender: the pre-render bake tool

Renders our own 3D models to raw frames (ADR 0053, plan row P656a). Code here is MIT, like
`tools/artgen`. The model data it reads, `assets/art/models/<faction>/<id>_detail.tres`, is
(c) AppCode ApS, all rights reserved (ADR 0046). This row ships the core only: no building data,
no PNG post-processing and no manifest (P656b), no terrain kit (P656c).

## What is here

| File | Job |
| --- | --- |
| `BakeMesh.gd` | Mesh builder: `ArtMesh` faces and plane-clipped solids with bevel strips, outward normals, the 60,000-triangle cap (refused with the id and count, never cut short). |
| `BakeShapes.gd` | Boxes, bars, cylinders and cones, domes, tori on top of `BakeMesh`. |
| `DetailModel.gd`, `DetailPart.gd`, `DetailMaterial.gd` | The `_detail.tres` schema: materials, parts (shape, place, mirror, repeat, seeded jitter) and a variation seed. Data only. |
| `BakeMaterials.gd`, `detail.gdshader` | One shader for every material: weathering from position and normal, team paint stays in hue. |
| `BakeRig.gd` | Orthographic camera at `IsoProjection`'s 2:1 view, sun along `ArtShadow`'s reach, fill, sky, SSAO. Every projection constant is read, not typed. |
| `bake_model.gd` | The scene entry: one model, every part and direction of its sheet, raw PNG frames. |

Units are ready: a hull and turret (or head) rig, 16 directions (8 for a squad, from the sheet's
`counts`), and the turret seated by `IsoSheetDef.mounts`.

## Run it

```
bash scripts/prerender.sh --preflight
bash scripts/prerender.sh --model res://assets/art/models/fossil/heavy_tank_detail.tres \
    --sheet res://assets/art/iso/fossil/veh/heavy_tank_sheet.tres --out /tmp/prerender \
    [--dirs all|6,7] [--scale 8] [--team "#D234D2"] [--composite] [--no-ssao]
```

Frames are `<out>/<id>_<part>_dNN.png` at `--scale` texels per art px (default 8, for the box
filter of P656b), transparent background. `--composite` adds `<id>_both_dNN.png`, hull and turret
together. The run prints the renderer line, for example `Vulkan 1.4.318 - Forward+ - llvmpipe`.

## The pinned image

`scripts/prerender.sh` checks it before any render and installs nothing: Ubuntu 24.04.5 LTS;
`mesa-vulkan-drivers`, `libgl1-mesa-dri`, `libglx-mesa0`, `libgbm1`, `mesa-libgallium`
25.2.8-0ubuntu0.24.04.5; `libllvm20` 1:20.1.2-0ubuntu1~24.04.3; `xvfb`
2:21.1.12-1ubuntu1.9; Python 3.13, numpy 2.5.3, Pillow 12.3.0; Godot 4.7.2. The Python pins
live in the script until P656b adds `requirements.txt`. The bake runs Forward+ over Vulkan
(lavapipe) under `xvfb-run`; the game stays on Compatibility.

| Exit | Meaning |
| --- | --- |
| 0 | Done (preflight: the image is the pin) |
| 1 | The bake failed (Godot error, SCRIPT ERROR, no frame) |
| 2 | Usage |
| 3 | A tool is missing (Godot, xvfb-run, dpkg-query, python3) |
| 4 | A version differs; one line per package, expected and found |

`PRERENDER_VERSIONS_FILE` and `PRERENDER_TOOLS` make the checks testable without the real
packages (`tests/tools/prerender/test_prerender_script.gd`).
