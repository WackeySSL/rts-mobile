# native/: P26n C++ spike (draft, never merged)

A plain C++ GDExtension port of the P26s perf probe's mock tick (`game/ui/PerfProbeTick.gd`:
`step()` and `flow_slice()`), to answer one question with numbers: how much faster is a
straightforward C++ port of exactly the same tick, on CI x86_64 and on the phone (arm64, release)?
The answer feeds a later ADR on ADR 0012's worker-tick gate. Nothing here is production code and
nothing here touches `game/sim`.

- `probe_tick/src/probe_tick_native.{h,cpp}`: class `ProbeTickNative` (RefCounted), the same
  public surface as `PerfProbeTick`: the properties `tick`, `x`, `y`, `target`, `seen`, `dirty`,
  `dirty_count`, `flow_cost`, `slice_cells`, and `step()` / `flow_slice(budget)` returning their wall
  time in microseconds. Ported function for function: int64 where GDScript holds an int, int32
  storage where it stores into a `PackedInt32Array`, no floats, no allocation and no Godot call
  inside the hot loops, no SIMD, no threads of its own.
- `probe_tick/src/register_types.{h,cpp}`, `probe_tick/SConstruct`: the registration and the build.
- `probe_tick.gdextension`: `res://native/probe_tick.gdextension` (entry `probe_tick_library_init`,
  `compatibility_minimum = "4.5"`), libraries for linux x86_64 and android arm64, debug and release.
- `bin/`: the built libraries (git-ignored). `godot-cpp/`: the fetched bindings (git-ignored).

## Build

```
pip install scons==4.9.1          # exactly this version; the script checks it
bash scripts/build-native.sh      # linux, template_debug, x86_64 (what scripts/verify.sh runs first)
bash scripts/build-native.sh --target template_release
bash scripts/build-native.sh --platform android --target template_release --arch arm64   # CI only
```

Exit codes: 0 ok, 2 bad flag, 3 tool missing (git, scons 4.9.1, the compiler, `ANDROID_NDK_ROOT` or
its toolchain), 4 fetch, SHA check or build failed. Android needs `ANDROID_NDK_ROOT`; a cloud
session has no NDK, so the Android library is built in CI only. `scripts/verify.sh` calls the linux
debug build first on this branch, and the tests that need the library FAIL without it (no skip).

The build passes `native/probe_tick/build_profile.json` (godot-cpp's build profile: only `OS` and
`RefCounted` and their parents are bound), which takes a cold build from minutes to about ten
seconds; it changes no compiler flag. Flags are godot-cpp's defaults per target, untouched: `template_debug` is `optimize=speed_trace`
(`-O2`, `DEBUG_ENABLED`, no debug symbols), `template_release` is `optimize=speed` (`-O3`,
`NDEBUG`); no LTO, `-fno-exceptions`. `ProbeTickNative.get_build_info()` reports the build the
library was made with, and the probe's card prints it.

### First import after a fresh clone

Godot 4.7.2 aborts at the end of a fresh `godot --headless --import` (exit 134 or 139; 4 of 6 runs on
the dev VM, and 6 of 6 even for a bare registered class with no method) when the first scan finds a
GDExtension that registers a class; a project without the extension, and a warm `.godot/`, never
do. `scripts/build-native.sh` therefore lists the extension in `.godot/extension_list.cfg` after a
build, as the editor does after its first scan (0 of 6 aborts). Build before the first import, as
`scripts/verify.sh` does. A checkout without `native/bin/` imports with exit 0 but logs
`ERROR: Can't open dynamic library` on every Godot start, and the tests that need the library fail.

## godot-cpp (pinned, MIT)

| | |
| --- | --- |
| Source | https://github.com/godotengine/godot-cpp |
| Tag | `godot-4.5-stable` (the newest tag; there is no 4.6 or 4.7 tag) |
| Commit | `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77` (checked after the fetch and on every build) |
| Licence | MIT, "Copyright (c) 2017-present Godot Engine contributors." |

GDExtension is forward compatible, so the library built against 4.5 loads in Godot 4.7.2. The
script fetches the commit into `native/godot-cpp` (no git submodule) and writes a `.gdignore` there.
The licence text is committed unchanged in `docs/licenses/godot-cpp-4.5-stable/LICENSE.md`, and
`scripts/export-android.sh` adds it to the `THIRD_PARTY_LICENSES.txt` that ships next to the APK.

## Threads

`step()` and `flow_slice()` run on the probe's worker thread and touch only the object's own
members. The `Packed*Array` properties return copies and, like the setters, belong to the main
thread between jobs, while the worker sleeps (mode 4 does the same with `PerfProbeTick`).
`get_last_step_thread()` and `get_last_slice_thread()` record `OS.get_thread_caller_id()` of the last
call, which is how the tests prove the tick ran off the main thread.

## Web and a missing library

The web preset excludes `native/*`: there is no wasm build, and without the `.gdextension` the web
preview loads as before (the export log has no GDExtension warning; the build reports "no GDExtension
support"). A fresh checkout has no `native/bin/` until the build runs; the probe and the tests check
`ClassDB.class_exists("ProbeTickNative")`, and probe mode 5 then shows "C++ tick not available on
this build" instead of crashing.

## Proof of identity

`tests/perf/test_probe_tick_native.gd` plays 900 ticks of both ticks in lockstep (a flow slice of 512
cells on every 15th) and compares tick, x, y, target, seen, dirty, dirty_count, flow_cost and
slice_cells after every call, failing on the first difference with the tick, the array and the
index. Probe mode 5 plays a 60-tick version of it before its 60 s measurement and prints the result
on the card. `tests/perf/probe_tick.gd` times both on CI and prints the speedup.
