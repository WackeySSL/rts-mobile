# ADR 0013: C++ GDExtension kernels for the sim's hot phases

Status: accepted, 2026-10-12 (Michael: "1 ja, 2 A, 3 ja, 4 ja"; the web preview stays on the
GDScript twins, option A of §7; see "Acceptance note" at the end). Proposed the same day
(revision 9, after the review of revision 8: a preflight with a
job in flight is refused by a pure check, never a `push_error` (§3); `resolve_impl` is pure and
`start()` logs its fallback (§3); P30n owns `FlowCache.run` (§3); `check-native-tests.sh` runs
as a `ci.yml` step, not inside `verify.sh`, and the `native-clang` job skips gdUnit4 before the
first suite (§10); ADR 0007 §4's status line waits for P41g (§14). Revision 8, after merging `main` and the review of revision 7:
§3's self-check runs from `PerfHud.preflight()` (P50a2's seam), which P50b's arena script calls
before the runner starts, with an order test; §3's table names the INTENTS entry; §5's twin rule
names the GDScript rows that merge after a port (P41); P38j2's skip of `NON_STATE_MEMBERS`
depends on P54; ADR 0005 §8 is named in "It keeps"; the slip is recounted on the merged plan.
Revision 7, after the second merge-readiness review: §1's port
rule gains clause (b) for bursty phases, the one FLOW is ported by; §10's
`check-native-tests.sh` discovers the native suites and holds no list, and P51 adds the
`native-clang` golden step; unrecorded build times now cite the spike's README or the PR that
measures them, and the "not re-run" list is marked complete. Revision 6, after the
merge-readiness review: the lead's docs PR
is P26e, since P26c is taken on `main`, and the plan revision is the next one at acceptance;
P54's checked table holds the fetch lists of the five §1 phases, so its `check_world` and name tests
are not vacuous; the on-device self-check is `NativeKernels.self_check` in P54r, which moves
after P43b to depend on P37n; ADR 0012 §4 gains the `impl` verdict in the supersedes list.
Revision 5, after the completeness check of revision 4: ADR 0005 §1 joins the supersedes list
and both licence notices stay identical; §15's trigger and watch line read named summary keys
and are not verdicts, while the card's `impl` line is one; the boundary write cases move to
P30n; unevidenced figures are marked with the PR that re-proves them. Revision 4: the research is re-run and on record, the accepted ADRs it changes are
listed, and every `core/` function lands with the kernel that calls it). Michael approved
drafting it ("ja til ADR 0013-udkast") and accepted it on 2026-10-12.

Status note (2026-10-13): §2 carries two dated status notes from P26h (after the P30a and P32f
reviews): the checked table's bool kind for FLOW's `complete`, and `FogGrid.listed`, which the
stamp and the FOG kernel write in place with the dirty-list blocks.

Status note (2026-10-13, P26i): after the P53 (#59) and P53b (#60) reviews and Michael's NDK
answer, dated status notes from P26i sit in Context ("Pins and toolchain" and "The template's own
NDK"), §4 (`-fwrapv`), §8 (the Android, Targets, Build profile and C++ format rows), §9 (the
fallback and the fresh-clone proof), §12, "Open after this draft" and the acceptance note. Michael
answered in chat on 2026-10-13, verbatim: **"NDK r29"**: the kernels are built with NDK
29.0.14206865, not 28.1.13356709 (§8).

Status note (2026-10-13, P26j): after the P55 review (#63), dated status notes from P26j sit in
§8 (the CI cache key) and §10 (`check-native-tests.sh` as merged).

Status note (2026-10-13, P26k): after the real runs of P55a (#67) and P55a2 (#68), dated status
notes from P26k sit in Context ("The template's own NDK"), §8 (NDK r29's clean build, the
common-page-size flag, the measured build times, which answer the Targets row's "P55a measures
it", and Michael's two answers of 2026-10-13 on "Sessions": **"ja til install-android"** and
**"ja til SDK-licens"**) and §10 (the Android job as merged). In §8 the P26i and P26j status notes
now follow the "Sessions" bullet, so the two accepted bullets before them no longer render inside
a status note's list; no text changed.

Status note (2026-10-13, P26l docs): after the merges and reviews of P55b (#69) and P54 (#70),
dated status notes from "P26l docs" (a docs PR whose name repeats the licence row P26l, #55) sit
in §2 (P54 as merged), §3 (`sim_impls.gd` returns its problems), §8 ("Sessions": P55b as
merged), §10 (what the sanitizer job cannot see) and §14 (`CLAUDE.md`'s `build-native.sh` line,
after Michael's answer in chat on 2026-10-13, verbatim: **"ok til CLAUDE.md-linjen"**). No
accepted text changed.

Status note (2026-10-14, P26m): after the merges of P30n (#74) and P30n2 (#75), the first kernel
(FLOW), dated status notes from P26m sit in Context (PRs #35 and #41 closed unmerged on Michael's
word in chat on 2026-10-14, verbatim: **"luk #35 og #41"**), §2 (`WorldView` as realised by
`ArrayView<T>` and `flow::Slot`, the entry check, and one recorded exception), §3 (what
`sim_impls.gd`'s `use()` attaches) and §5 (Michael's port-size rule, in chat on 2026-10-14,
verbatim: **"ja til port-reglen"**). No accepted text changed.

Status note (2026-10-14, P26n docs): after the merges of P33 (#77), P56b (#78) and P26m (#79),
dated status notes from "P26n docs" (a docs PR whose name repeats the spike P26n, #41) sit in §2
(private view pointers and P56b's `view_pointer` rule supersede "a struct of raw pointers and
sizes"; the P26m note there is rewrapped with no word changed) and §5 (P42n with both kernels).
No accepted text changed.

Status note (2026-10-14, P26s docs): after the merge of P57 (#96, the sanitizer job), dated status
notes from "P26s docs" sit in §8 (the cache key's sanitizer part), §10 (the sanitizer job's
decisions as merged, its blind spots, and the lead's row P57b) and "Open after this draft" (the
sanitizer job's item closed). No accepted text changed.

Status note (2026-10-19, P26x docs): after the merges of P57b (#104), P37n (#108, the second
kernel, INTEGRATE) and P37n3 (#109, its lockstep), dated status notes from "P26x docs" sit in §2
(the second recorded exception, INTEGRATE's slot reads; the `isqrt` shift table accepted as
structure; the checked table's counts; `step_toward`) and §10 (the sanitizer job's path filter
and dump step as P57b merged them). No accepted text changed.

Status note (2026-10-20, P26y docs): after the merge of P39n (#113, the third kernel,
SEPARATION), a dated status note from "P26y docs" sits in §2 (SEPARATION's checked list trimmed
from 28 to 20 names, the empty-grid return, the divisor's recorded range). No accepted text
changed.

Status note (2026-10-20, P26z docs): after the merge of P54r (#116, `NativeKernels` and
`MatchRunner.sim_impl`), a dated status note from "P26z docs" sits in §3 (what `self_check`'s
hash comparison sees of FLOW, and where the OS rule of the fallback lives). No accepted text
changed.

Status note (2026-10-20, P26aa docs): after the merge of P42b (#122, the PROJECTILES phase), a
dated status note from "P26aa docs" sits in §1 (clause (a) read for `PROJECTILES` and `FIRE` at
P42b's `PERF` line: P42n is not triggered there). No accepted text changed.

Status note (2026-10-21, P26ac docs): after the merges of P46 (#129, the fog update) and P41n
(#132, the fourth kernel, TARGETING), dated status notes from "P26ac docs" sit in §1 (the lead's
reading of P46's `PERF` line: only TARGETING meets clause (a) and P41n ports it, FOG meets clause
(b) and P46n ports it, P37n2, P41g and P42n are not triggered) and §2 (the library's mask 0x6A,
TARGETING's checked list of 35 names, `line_clear` in `core/`, the empty-grid guard). No accepted
text changed.

Status note (2026-10-21, P26ad docs): after the merge of P46n (#134, the fifth kernel, FOG),
dated status notes from "P26ad docs" sit in §2 (the library's mask is now 0x46A, FOG's checked
list of 25 names, the mask pick and the twin's guard; the P26ac note's mask 0x6A and its "no
library reports it" were true on `f1494a5` and stay as dated records) and §3 (what `self_check`'s
hash comparison cannot see of FOG on a device: an open item). No accepted text changed.

Status note (2026-10-21, P26ae docs): after the merges of P46n2 (#141, the FOG lockstep), P46b
(#144, the fog rules in both `Targeting` versions), P49a (#143) and P50a (#142), dated status
notes from "P26ae docs" sit in §2 (TARGETING's checked list grows from 35 to 40 names), §3 (P46n2
covers FOG's unhashed outputs in CI; the device side stays open) and §15 (its four summary keys
land in P50a2, not P50a; P49a's watch lines use their names). No accepted text changed.

Status note (2026-10-21, P26af docs): after the merges of P51b (#149, the arm64 determinism job)
and P51r (#153, the release-template perf APK), a dated status note from "P26af docs" sits in §10
on its line "`install-godot.sh`: unchanged" (the script now picks the editor per architecture and
fetches the release template on request). No accepted text changed.

Status note (2026-10-22, ADR 0016 accepted): a dated status note sits in §15 on its engine-side
watch line (Michael's answer 2A keeps 3.325 ms; two corrections; a native state hash only by its
own ADR). No accepted text changed.

Status note (2026-10-22, P26ag docs): after the Phase 2 gate (issue #157) and PR #158, a dated
status note from "P26ag docs" sits in §15: the native ratios re-derived to 11.1 and 12.1 by the
plan's exception 5, and the two rules' readings on the gate cards. No accepted text changed.

Status note (2026-10-22, P68b docs; ADRs 0017 and 0021 accepted 2026-10-22): §1 carries a dated
status note: Phase 3's three new phases start as GDScript, and the lead reads the port clauses at
the Phase 3 plan's row P93. No accepted text changed.

Status note (2026-10-26, P26ai docs): §2 carries a dated status note: TARGETING's checked list
holds 41 names since P71b (#185), and P71's building-world lockstep runs 450 ticks. No accepted
text changed.

From its acceptance (2026-10-12) it supersedes in part:
- ADR 0012 §7: "GDExtension (C++) is not adopted now" and its trigger (a release perf-arena card
  miss after remedy steps 1 and 2). §15 below replaces them.
- ADR 0012 §5: the P27f value, and the wording "`Sim.step` passes 0 cells to
  `FlowCache.advance`", which becomes `FlowCache.run(world, budget)` (§3). The rule stays, and
  with the C++ slice it gives 512.
- ADR 0012 §4: the P46 decision point ("start drafting the GDExtension ADR when P46's
  `est_phone_p95_ms` is above 26.6 ms"). It also extends §4's verdict list by one: the APK
  card's `impl` verdict (§3) makes `GATE: FAIL` on its own, like `build`. No threshold changes.
- ADR 0011 §6 step 5: adopted here for the sim's hot phases.
- ADR 0008 §3: "the buckets are preallocated rings, so integrating allocates nothing after the
  first field" becomes "`configure()` allocates every slot's arrays; nothing allocates after it"
  (§2).
- ADR 0007 §8: "every helper object reachable from a World property declares its own `HASHED`
  and `UNHASHED` lists". `World.kernels` is reachable and declares none; it is the one member of
  `World.NON_STATE_MEMBERS`, which the coverage test, the hash walk and P38j2's reachability
  walk skip (§3).
- ADR 0007 §4, only if `GRIDS`'s rule fires (§1, plan row P41g): "The `GRIDS` phase holds one
  rebuild line per spatial grid" becomes one `SpatialGrid.rebuild_grids(world)` line that holds
  one `_rebuild_one` line per grid.
- ADR 0001 Consequences ("hot paths may move to GDExtension later through a new ADR"): this is
  that ADR.
- ADR 0005 §1: the Android preset no longer has "the same `exclude_filter` as the Web preset".
  The Web preset gains `native/*` (§7); the Android preset keeps `tests/*, addons/gdUnit4/*` and
  must never exclude `native/*`, or the APK silently loses the library.
  `tests/project/test_export_presets.gd` pins both (as the spike's version already does).
- CLAUDE.md, the Stack line "GDScript 2.0 with static typing everywhere. No C#.", the Format/lint
  line and the Tests line "gdUnit4 in `tests/`" (new text in §14; the sanitizer harness of §10 is
  C++ and lives outside `tests/`).

It keeps:
- ADR 0012 §1-§3, and §4's thresholds and ratio formula: the worker thread, the thread-safety
  rules, `MatchSnapshot`, and the gate values, except the rows ADR 0014 changes if Michael
  accepts it;
- CLAUDE.md rules 1-6 (rule 1 gains §14's `native/` sentence);
- ADR 0005 §5: the APK's `THIRD_PARTY_LICENSES.txt` keeps the web build's content; godot-cpp's
  notice goes into both (§11);
- ADR 0005 §8 ("`preview.yml` and `export-web.sh` are unchanged"): that sentence scoped Phase
  1's delivery work; what §8 decides stays (`main.tscn` is the boot scene of every build, every
  PR keeps its web preview). `export-web.sh` changes in P26l (the libc++ notice, in any outcome),
  P53 (the seed call, the check that no `.gdextension` is packed) and P55a (the godot-cpp
  notice); `preview.yml` changes only if P53 falls back to a committed `.gdextension` (P55);
- ADR 0005 §7 ("`toolchain-mirror.yml` and `scripts/cloud/setup.sh` are unchanged"): P53 changes
  `setup.sh` to install SCons and `clang-format` (§8), not to build APKs, and cloud sessions still
  build none;
- Michael's answer 1: the gate runs on his Pixel 9a for good, with the 2021 limits divided by
  k = 2.5.

ADR 0014 (frame pacing and the CPU-time limits) was a separate proposal, so Michael could answer
each one on its own; both were accepted on 2026-10-12 (see "Acceptance note").

## Context

### What the phone measured
Source: Pixel 9a, release template, same session, 2026-10-12. Spike PR #41
(https://github.com/WackeySSL/rts-mobile/pull/41#issuecomment-6125124810), on top of probe PR #35.
The spike ported the probe's mock tick to C++ function for function: `int64_t` where GDScript
holds an int, `int32` stores where GDScript stores into a `PackedInt32Array`, no floats, and no
allocation or Godot call in the loops.

| | GDScript worker (mode 4) | C++ worker (mode 5) | Ratio |
| --- | --- | --- | --- |
| Mock tick mean / p95 / max | 11.39 / 19.16 / 22.56 ms | 0.25 / 0.43 / 2.72 ms | 45x |
| Flow slice, 512 cells, mean | 3.15 ms | 0.21 ms | 15x |
| Job post to done, mean / p95 | 11.87 / 20.10 ms | 0.44 / 0.88 ms | 27x / 23x |
| Late / held ticks | 0 / 0 | 0 / 0 | |
| Lockstep self-check on arm64 | - | matches (60 ticks) | |

The two modes ran one after the other and timed different stretches of the same deterministic
run: mode 4 from tick 2905, mode 5 from tick 3978 (the spike's phone comment). The spike's own
code says the stretches differ in load ("the first 900 ticks are the lightest at p95"), so the
45x, 15x and 27x ratios are approximate. The conclusion rests on the absolute C++ job p95 of
0.88 ms, which no plausible stretch effect brings near 13.3 ms.

- **Release run 2** (PR #35, https://github.com/WackeySSL/rts-mobile/pull/35#issuecomment-6123305154):
  - the GDScript worker mock took 10.49 / 18.88 ms (mean / p95), and the job 11.03 / 19.75 ms;
  - the in-frame mock took 9.04 / 12.69 ms.
- **CI x86_64:**
  - the C++ mock takes about 0.047 ms mean and 0.063 ms p95, against about 2.4 ms mean for
    GDScript;
  - CI compares the debug editor's GDScript VM with a `template_debug -O2` library;
  - the phone compares release GDScript with `-O3`.

Status note (2026-10-14, P26m): the probe PR #35 (P26s) and the spike PR #41 (P26n, which also
carried the calibration build P26n2) were closed unmerged on 2026-10-14 on Michael's word in
chat, verbatim: **"luk #35 og #41"**. This ADR's records of them stay valid: the comments it
links (the phone runs above, and the evidence comment on PR #41 that "Engineering facts" and §2,
§6 and §9 cite) stay readable on the closed PRs, the calibration reports are embedded verbatim in
ADR 0014's acceptance note, and the branches `claude/p26s-perf-probe` and `claude/p26n-cpp-spike`
stay unmerged.

### What that means for the gate
- `sim_p95_ms` is 13.3 ms (ADR 0012 §4).
- **GDScript misses it.** The mock alone misses it on the worker before the real tick's combat,
  projectiles, line checks and orders are added: the mock tick p95 (18.88-19.16 ms) by 42-44 %,
  and the gated quantity, the job p95 (`job_usec`, 19.75-20.10 ms), by 48-51 %.
- **Remedy step 1 (data) cannot close that gap.** ADR 0012 §5's headroom rule already gives the
  minimum of 64 flow cells per tick at that job p95. The arena opening's four fields would then
  take about 18 s. The other data levers, `retarget_period_ticks` and `fog_period_ticks`, would
  have to cut about a third of the mock's p95 ((19.16 − 13.3) / 19.16 = 31 %) before the real
  tick's extra phases are added: acquisition and the fog stamps together are about two thirds
  of the mock (table below), so both cadences would roughly halve. Slower retargeting and
  laggier fog change how the game feels, which data tuning is not meant to do.
- **Remedy step 2 (GDScript fixes) cannot close it either.** The mock is already written in the
  aliased, allocation-free style of ADR 0007 §1.
- **C++ fits with room to spare.** The C++ job p95 is 0.88 ms. Even a real tick three times the
  mock would sit near 2.6 ms.

### Where the mock's time goes
Timed by calling the spike mock's functions one at a time (`PerfProbeTick` on branch
`claude/p26n-cpp-spike`, 83998f7; `_move` and `_tile_events` cut into their two halves with the
same code). Cloud VM (4 cores), the official 4.7.2 editor binary, the same build type as CI.
Three runs of 900 ticks; min of 3 per column. The table is the re-run posted with its scripts in
the evidence comment on PR #41
(https://github.com/WackeySSL/rts-mobile/pull/41#issuecomment-6128912281, section 5); an earlier
run of the same scripts gave means within 0.01-0.02 ms. The whole mock tick took 2.36-2.43 ms
mean here, against 2.4-2.51 ms on CI, so the split is representative. The phone estimate
multiplies by the release worker ratios 4.4 (mean) and 5.9 (p95), on the unrounded VM values;
per-phase ratios differ (the 512-cell slice measured 3.15 ms on the phone against 0.96-1.26 ms
here in two sessions, a ratio of 2.5-3.3), so the estimates are rough.

| Mock part | Real phase | Mean / p95 here (ms) | Share of the mock mean | Phone estimate, mean / p95 (ms) |
| --- | --- | --- | --- | --- |
| Both grid rebuilds | `GRIDS` | 0.035 / 0.061 | 1.5 % | 0.15 / 0.36 |
| Separation pushes (3x3 cells, the 16 and 8 caps) | `SEPARATION` | 0.44 / 0.65 | 18.5 % | 1.9 / 3.8 |
| Goal step (`isqrt`) and clamps | `INTEGRATE` | 0.31 / 0.48 | 13 % | 1.4 / 2.8 |
| Acquisition (a fifth of the units, 5x5 cells) | `TARGETING` | 0.64 / 0.94 | 27 % | 2.8 / 5.5 |
| Fog stamps (two 13x13 squares per unit that changed tile) | `FOG` | 0.92 / 1.88 | 39 % | 4.0 / 11.1 |
| Flow lookup (9 reads per unit that changed tile) | `INTEGRATE` (FIELD) | 0.020 / 0.044 | 1 % | 0.09 / 0.26 |
| Flow slice, 512 cells (its own call, 64 slices) | `FLOW` | 0.96 / 1.07 | - | 3.15 mean, measured |

The mock has no line checks (`INTENTS`), no engagement, no `FIRE`, no `PROJECTILES`, and no
`COMMANDS` or `REMOVE` work, so this split says nothing about them. §1 uses it to choose the
phases ported now.

ADR 0012 §7 asked for this ADR only after a release perf-arena card misses. That card exists only
after P50b and P51r, about 40 PRs from now. Waiting means writing every hot phase in GDScript,
failing at the gate, and then porting on the critical path. The GDScript versions are kept anyway
as the reference and the web path (§5), so deciding now adds no GDScript work. It does let each
port land next to its module, measured from the first `PERF` line.

### Engineering facts this ADR builds on
Three sources:
- the spike (branch `claude/p26n-cpp-spike`, 83998f7: `native/README.md`, `scripts/build-native.sh`,
  `ci.yml`, `export-android.sh`);
- research for this draft (2026-10-12). Its first scratch projects were deleted, so the lead
  re-ran it before the questions went to Michael and posted the commands, sources and outputs
  as the **evidence comment on PR #41**
  (https://github.com/WackeySSL/rts-mobile/pull/41#issuecomment-6128912281). That comment's
  "Not re-run here" section names only the dlink, release-template and upstream-status items;
  the complete list is this ADR's "Research facts not re-run" (Open after this draft), and each
  of those facts is marked where it is used;
- the Godot 4.7.2 source.

The facts:
- **Packed arrays across the boundary** (evidence comment, section 1; official 4.7.2 editor,
  `template_debug` library):
  - A godot-cpp method that takes a `PackedInt32Array` by value or by `const &` writes to a
    private copy. The World never sees the write, and nothing reports an error. The cause:
    godot-cpp's `PtrToArg<const T&>::convert` returns by value, so `ptrw()` forks the array.
  - A `const Variant &` argument, or `Object::get(name)`, with
    `VariantInternal::get_internal_value<PackedInt32Array>()->ptrw()` writes in place. GDScript
    aliases see the write. A held `duplicate()` (the snapshot) forks once and keeps its old
    values.
  - Details and costs are in §2.
- **Fresh import aborts** (evidence comment, section 3). Godot 4.7.2 aborts (exit 134) at the end
  of a fresh `--headless --import` when the first scan finds a GDExtension that registers a
  class: the minimal repro, one registered class with no methods, crashed in 20 of 20 fresh
  imports and 10 of 10 fresh `--editor --quit` runs, and in 0 of 20 with a seeded extension list
  and 0 of 10 with a library that registers no class. The first research run reported 70 of 90
  across mixed cases, and the spike saw 134 and 139. This is an editor bug (§9).
- **Every checkout needs the library.** With a committed `.gdextension` and no built library,
  Godot logs `Can't open dynamic library` on every start, and the error scans of `verify.sh` and
  `export-web.sh` fail (spike finding 2).
- **Web.** The plain `web_nothreads` template the project uses refuses to start when the pack
  lists any GDExtension. A research task reported that the official `web_dlink_nothreads`
  template loads one with no cross-origin isolation headers (§7); that was **not re-run** for the
  record, and nothing decided here depends on it (option B is not adopted). If it holds, spike
  finding 3 ("no GDExtension on the single-threaded web export") is true only of the plain
  template.
- **Pins and toolchain** (spike, CI-proven in run 38245066556):
  - godot-cpp `godot-4.5-stable` = `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77`;
  - SCons 4.9.1;
  - NDK 28.1.13356709, installed by sdkmanager in CI;
  - `build_profile.json` keeps a cold godot-cpp build at "about ten seconds" (the spike's
    `native/README.md`; not timed in CI for the record, P53 measures it);
  - the arm64 library is 480,280 bytes and needs `libc++_shared.so`, which Godot's Android
    template already ships;
  - the spike's Android job, uncached NDK install included, took 1m42s in total (run
    38245066556). That job exported a release APK on the probe branch (`--export-release`);
    `main` exports a debug APK, which §8 and §10 handle.

  Status note (2026-10-13, P26i, P53 review): P53 measured a cold godot-cpp build (g++ 13.3.0,
  `-j4`, 63 compile units) at 23-34 s wall on the 4-core VM, depending on the load from other
  lanes, not "about ten seconds"; that holds wherever this ADR quotes the figure (§8's Build
  profile row, Consequences). `build_profile.json` enables `OS` and `RefCounted` (§8's status
  notes). NDK 28.1.13356709 stays what the spike proved; the kernels move to NDK 29.0.14206865
  (Michael, 2026-10-13, §8).
- **The template's own NDK** (read from `.note.android.ident` in the android-dev-latest APK,
  Godot 4.7.2): `libgodot_android.so` was built with NDK r29 (29.0.14206865) and the
  `libc++_shared.so` it ships with r28 (28.0.13004108), linked with LLD 21. Godot's own `.so`
  files have 16 KB-aligned LOAD segments. (From the first research run; not re-run and not in the
  evidence comment. P55a re-reads both in CI, see "Open after this draft".)

  Status note (2026-10-13, P26i): the r28 reading of the template's `libc++_shared.so` does not
  hold. P26l (`docs/licenses/llvm-libc++/README.md`) attributed its `.note.android.ident` (most
  likely) to NDK r28 sysroot objects linked into it; the conclusion does not rest on that
  attribution: its `.comment` names Android clang 21.0.0 (r563880c) and LLD
  21.0.0, its exported symbols match the LLVM 21 line of upstream's libc++ ABI list, and Godot
  4.7.2 pins NDK 29.0.14206865 and copies `libc++_shared.so` out of that NDK. So the library is
  r29 / LLVM 21, like `libgodot_android.so`, and Michael chose NDK 29.0.14206865 for the kernels
  (§8's status notes).

  Status note (2026-10-13, P26k, P55a2's real run on an APK, #68): the Godot 4.7.2 template's
  `libgodot_android.so` carries `.note.android.ident` "Android r29 14206865", so it is built with
  exactly the pinned NDK, and its `libc++_shared.so` carries "Android r28 13004108". That r28
  note is expected: the file is byte-identical to NDK r29's own sysroot `libc++_shared.so` after
  `llvm-strip --strip-unneeded`, and that copy carries the same note. Both libraries have three
  `PT_LOAD` segments aligned to 0x4000. Since P55a2, `export-android.sh` logs both notes and the
  alignment (`check-android-elf.sh describe`, no verdict) on every Android export, CI's included,
  which is the re-read that "Open after this draft" left to P55a ("Still to come").
- **Spike review:**
  - a 200k-tick ASan and UBSan run of the whole mock tick in C++ was clean;
  - g++ -O3 and clang++ -O3 gave the same checksum (x86_64, one mock run);
  - the suite killed 14 of 17 mutants at review, and the fix's new tests killed one more. Of the
    two left, the 20,000-tick lockstep catches one (an exact distance tie), and a stale
    flow-queue entry is covered only by reading.

## Decision

### 1. Scope: what moves to C++ and what stays GDScript
Every ported phase is maintained twice for good (§5), so each one needs a measured reason. The
rule has two clauses; a hot phase is ported when either holds:
- **(a) Mean:** its estimated phone mean, the phase's mean times `ci_ratio_mean` (4.4), is above
  5 % of `sim_p95_ms`, that is 0.67 ms (a CI mean of 0.15 ms at 4.4).
- **(b) Burst:** the phase runs on only some ticks (a time slice, or a periodic or event-cadence
  update), and its cost per active tick decides a headroom value of the ADR 0012 §5 kind, so that
  in GDScript that value falls below the default its data row ships. FLOW is the case: its slice
  runs on about 6 % of arena ticks (ADR 0012 §5), so its run mean is about 0.06 ms on CI and about
  0.25 ms phone-equivalent, below (a); but at 3.15 ms per 512-cell slice on the phone, ADR 0012
  §5's headroom rule gives 64 cells per tick and an 18 s arena opening in GDScript, against 512
  with the C++ slice. The lead reads (b) from the phase's per-active-tick timing (for FLOW,
  `flow_slice_p95_ms` and the job p95 the headroom rule reads), never from the run mean.

Clause (a) uses the mean because the `PERF` line's `phases=` split prints per-phase means over all
measured ticks (P38p; the plan's amendment pins that), which is also why it cannot see a bursty
phase and (b) exists. At the p95 the line sits higher: the p95 ratio (5.9) is
above the mean ratio (4.4), and the mock's phase p95s are 1.5-2.2 times their means on the VM,
so a phase exactly on the line has an estimated phone p95 of about 10-15 % of the limit. Four
phases each just below the line would add at most about 2.7 ms of mean, which the 13.3 ms limit
absorbs next to the C++ phases.

- **Ported now** (the mock split in Context puts the last four above clause (a); FLOW qualifies by
  clause (b), measured on the phone):
  - `FLOW` (phone: 3.15 ms per 512-cell slice; clause (b)): `FlowField.advance` (Dial buckets,
    corner rule, padded grid, buffer swap) and `FlowCache.recount` and `advance`;
  - `SEPARATION` (estimate 1.9 ms mean);
  - `INTEGRATE` (estimate 1.4 ms mean): integrate, slide, arrival, FIELD with `nav_next`, stall,
    and the ATTACK field re-key, with `isqrt`, `step_toward`, `FlowField.best_neighbour` and
    `FlowCache.acquire` as internal `core/` functions of this kernel. GDScript callers
    (`COMMANDS`) keep calling the GDScript `acquire`, and the INTEGRATE lockstep compares the
    slot tables both produce;
  - `TARGETING` (estimate 2.8 ms mean for acquisition): acquisition and engagement, one module and
    one kernel;
  - `FOG` (estimate 4.0 ms mean): `FogUpdate` and `FogGrid.stamp` (an internal `core/` function
    of this kernel).
- **Ported only when measured to meet a clause** (no port row now):
  - `GRIDS`: 0.15 ms estimated mean (1.5 % of the mock), below the line. The kernels of
    `SEPARATION` and `TARGETING` read the grids the GDScript rebuild wrote, through
    `world_access.h` like any other array;
  - `INTENTS` (staggered line checks with `line_clear`), `FIRE` and `PROJECTILES`: the mock has
    none of them, so there is no evidence either way.

  The lead applies both clauses in review to the `PERF` line of the module's last GDScript PR
  (P37b for `INTENTS`, P41 for `GRIDS`, P42b for `FIRE` and `PROJECTILES`) and again to P46's
  line, the first with the full tick; clause (b) only for a phase that runs on some ticks and
  sets a headroom value. A phase that meets either clause gets its port row, already estimated
  in the plan (P37n2, P41g, P42n), in the slot right after that PR. A phase that meets neither
  stays GDScript.

  Status note (2026-10-20, P26aa docs, P42b as merged, #122; the text above stays as accepted):
  at P42b's `PERF` line (PR #122's run) `projectiles` is 0.028 ms and `fire` 0.015 ms, so clause
  (a) gives about 0.12 and 0.07 ms against 0.67 ms for the two phases. P42n is not triggered at
  P42b's line; both phases are read again at P46's line.

  Status note (2026-10-21, P26ac docs, P46 as merged, #129; the text above stays as accepted):
  the lead's decision at P46's `PERF` line, the first with the full tick (both lines, the seed-42
  arena with fog, PR #129's clause (a) table). Only `TARGETING` sits on clause (a)'s line
  (0.146-0.161 ms, a phase mean x 4.4 of about 0.64-0.71 ms against 0.67 ms), and P41n (#132)
  ports it. `INTENTS` (about 0.021 ms), `GRIDS` (0.045), `FIRE` (0.017) and `PROJECTILES` (0.027)
  stay far below, so the conditional rows P37n2, P41g and P42n are not triggered, and by the rule
  above those four phases stay GDScript. `FOG` misses (a) on its mean (0.060 ms) but meets
  clause (b): it is bursty (an active-tick mean of 0.29 ms and a p95 of 0.74 ms; it adds about
  0.3-0.4 ms to the CI p95, which is +2.5-4.5 ms on `est_phone_p95_ms`), and P46n ports it
  unconditionally, as planned. The plan's rows P37n2, P41g and P42n and its section P46 "As
  merged" record it.
- **GDScript only:**
  - `COMMANDS`: validation, `Formation.assign`;
  - `REMOVE`: `remove_dead`, a stable compaction over the shape lists through `get(name)`;
  - `World` itself, `from_scenario`, `prepare` and defs loading;
  - `state_hash`, which already runs in the engine's C++ (`HashingContext`);
  - `MatchSnapshot.capture`, `MatchLoop`, `Replay` and `ScenarioOrders`;
  - `DetRandom` (no Phase 2 kernel draws random numbers);
  - all of `game/core`, `game/view`, `game/input`, `game/ui`, `game/ai` and `game/meta`.
- **Later ports** (Phase 3 onwards) follow both clauses above for hot phases and the trigger in
  §15 for the GDScript-only phases. They need a plan row under this ADR's rules, not a new ADR.

  Status note (2026-10-22, P68b docs, ADRs 0017 and 0021 accepted; the text and the notes above
  stay as accepted): Phase 3 adds `ECONOMY` (11), `PRODUCTION` (12) and `MEMORY` (13) as GDScript
  phases (ADR 0017 §5, §8); `COMMANDS` grows by the new Command types and stays GDScript only.
  The lead applies clauses (a) and (b) to the three at the first `PERF bases` line with all three
  filled (the base arena, `docs/plans/2026-10-22-phase-3.md` row P93, ADR 0021 §4), and §15's
  trigger on the base-arena gate cards; a phase that meets one gets a port row right after P93.
  The one planned twin change of Phase 3 is the `ATTACK` goal on a building in `TARGETING` (both
  twins, a lockstep case, §5; ADR 0017 §1, plan row P71); every other kernel gets building-world
  lockstep cases only.

### 2. Data across the boundary: the World stays GDScript
- **The merged P29a World stays valid, unchanged.** It stays the GDScript class
  `game/sim/World.gd` with its Packed arrays and the shape lists (`ROW_ARRAYS` and the others).
  The following stay too:
  - `remove_dead` compacting through `get(name)`;
  - the coverage tests;
  - `state_hash` in GDScript;
  - `MatchSnapshot.capture` by `duplicate()`;
  - the ADR 0012 hand-off.

  P29a2 continues in GDScript exactly as scoped.
- **Kernels borrow the World's arrays in place, for the length of one call.** A kernel is a
  method of one stateless class, `SimKernels` (`RefCounted`). It receives the World as an
  `Object`, and a helper object (`world.flow`, `world.fog`, the grids) through the World. On
  entry it fetches each array it uses once, through the one header
  `native/sim_kernels/src/bind/world_access.h`:
  1. `Object::get(StringName)` returns a Variant;
  2. the helper checks `get_type()` against the expected Packed type and the size against the
     expected length (rows, `max_rows`, cells, slots);
  3. it returns `VariantInternal::get_*_array(&v)->ptrw()` for an array the kernel writes, or
     `ptr()` for one it only reads. A read never forks.

  This check is mandatory, because the internal getter on a Variant of the wrong type is
  undefined behaviour (a crash, not an error).
- **The check is a pure function; the error path only logs.** `world_access.h` runs every check
  of a kernel's fetch list through one function that returns a status code and prints nothing
  (`SimKernels.check_world(world, phase) -> int`, 0 = ok, otherwise the index of the first bad
  name and the kind of fault). The kernel calls it on entry; on a non-zero status it logs one
  error naming the property and returns without writing, and `verify.sh` fails on that `ERROR:`
  line. The boundary test (P54) calls `check_world` directly on wrong types and sizes and
  asserts the status codes; it never triggers the logging path, which is covered by reading (the
  ADR 0012 §1 precedent). **No mismatch message is ever allowlisted** in
  `scripts/verify-allowlist.txt`: the allowlist applies to the whole log, so a pattern there would
  hide a real mismatch in the lockstep suites or the sim smoke run.
- **The checked table holds the lists of the five phases from P54 on.** `world_access.h` keeps,
  as data, one list per kernel phase of every name the kernel gets or sets: its owner (the World,
  a helper reached through it, or each slot of `world.flow`), its kind (a Packed array type, a
  typed `Array` of slot objects, or an int scalar) and its expected size (`max_rows`, cells,
  slots, `player_count` blocks, or none for a scalar). P54 commits the lists of the five phases
  of §1 (`FLOW`, `SEPARATION`, `INTEGRATE`, `TARGETING`, `FOG`) against the members that exist
  when it opens: its Depends cell names P31b, whose chain brings the World's shape lists
  (P29a2), the flow cache and its slots (P30b) and the spatial and fog grids (P32 with P32f), all
  held in the World by P31a. FLOW's list includes the typed `Array` of slot objects with each
  slot's arrays and scalars, so every kind the lists use is checked before any kernel exists.
  `check_world(world, phase)` checks exactly that phase's list. A port PR fetches only through its
  phase's list and adds the names its GDScript module introduced after P54; a conditional port
  (P37n2, P41g, P42n) adds its phase's list. The name test below covers every addition with no
  new case.

  Status note (2026-10-13, P26h, after the P30a review): the kinds above name only int scalars,
  but FLOW's list also needs a **bool** kind: each slot's `complete` (`FlowField.complete`, P30a),
  which the completion swap sets. The checked table therefore has a bool scalar kind next to the
  int one, with the same wrong-type case in P54's boundary test. The plan's P54 and P30n rows
  carry it.
- **Arrays of helper objects.** `FlowCache` serves one `FlowField` per slot (P30a, P30b). A kernel
  fetches the typed `Array` of slot objects once (type and size checked like a Packed array), then
  for each slot it touches, the slot's arrays and scalars once, through the same checked table.
  That is a fetch per slot, bounded by `flow_cache_size`, never per row or per cell. Two named
  exceptions to "fetch on entry, set on exit", both for FLOW only:
  - **the buffer swap** on a field's completion exchanges the slot's `cost` and `next` Variants
    with two `set` calls (a reference swap, no copy). The kernel then fetches both pointers again
    and holds no pointer from before the swap;
  - **no resize inside a tick.** P30b's `configure()` sizes every slot's `cost`, `next` and
    buckets once, so `begin` and the kernel never resize a slot array (ADR 0008 §3's "integrating
    allocates nothing after the first field" becomes "`configure()` allocates every slot's arrays;
    nothing allocates after it"; see the plan's P30b row).
- **Fixed blocks for the fog dirty lists.** The same no-resize rule holds for `FogGrid` (P32). ADR
  0010 §1 gives each player's dirty list a capacity of a quarter of the cells and a "full" flag.
  Each player's list is a fixed block of one flat `PackedInt32Array` (`player_count` blocks of
  `cells / 4` entries), sized in `configure()`, with a `PackedInt32Array` of counts and one of
  "full" flags. `begin_update` resets that player's count and flag and never resizes; a stamp
  writes at `block + count` while the count is below the capacity and sets the flag otherwise.
  There is no `Array` of Packed arrays. `dirty_cells(player)` keeps its contract signature and
  returns a copy of the used part of the block; only the view calls it, on the snapshot's copy
  on the main thread, never the sim. The kernel for FOG (P46n) then writes the lists in place.

  Status note (2026-10-13, P26h, after the P32f review): the merged `FogGrid` (P32f) adds
  `listed`, a `PackedByteArray` with one mark per player and cell (the layout of `visible`), so
  a flipped cell is listed once per update. A stamp writes a flipped cell at `block + count`
  only while its mark is 0 and then sets the mark; a cell that finds the block full sets the
  flag and is not marked; `begin_update` clears the marks of its listed cells (O(count)) and
  never resizes. So the stamp writes the block, the count **and the `listed` marks**, and the FOG
  kernel (P46n) writes `listed` in place with the lists; FOG's list in the checked table holds
  it. The plan's P46n and P54 rows carry it.
- **Scalars and counters.** A kernel reads scalars with `get` on entry and writes them with `set`
  on exit, or returns them. Every name it gets or sets comes from the same checked table in
  `world_access.h`, because `Object::set` on an unknown name fails silently. `stats` is an array,
  so it is written in place.
- **Rule ints come from the World.** A kernel reads every rule int (the 15 ints of `RulesDef`:
  `World._init()` copies the `RulesDef.new()` defaults, P29a, and `from_scenario` copies the
  scenario's rules through `_copy_rules`, P29c) and every def column from the World on entry,
  never from a C++ literal (CLAUDE.md rule 5). The only literals in `core/` are 0, 1 and -1, and
  `constexpr` values that mirror a GDScript `const` of the twin (each names it in a comment, for
  example `UNREACHED`, `EVENT_STRIDE` and the `Phase` ids). P56 scans for other literals.
- **Forbidden:**
  - a parameter of type `PackedInt32Array`, `PackedByteArray` or any Packed type, by value or by
    reference, anywhere in `bind/` (bound methods and internal helpers alike): both forms write to
    a silent copy. P56's `bind/` scan and a `ClassDB.class_get_method_list` check in the boundary
    test (§4, §6) catch it;
  - keeping any pointer, Variant, array reference or Object between calls ("bind once"). It saves
    about 3 µs per tick and breaks silently when GDScript reassigns a member;
  - `get` or `set` per row;
  - calling back into GDScript while holding a pointer from `ptrw()`;
  - resizing an array whose pointer is held. The only resizes inside a tick are the event
    appends: one per appending kernel (FIRE: `SHOT`, PROJECTILES: `IMPACT`), each once after its
    loop, through `world_access.h`, with the pointer fetched again afterwards.
- **Two layers in `native/sim_kernels/src/`:**
  - `core/` is plain C++17 over a struct of raw pointers and sizes (`WorldView`), and includes
    no Godot header. `WorldView` hands `core/` `int64_t` accessors (for example
    `int64_t pos_x(int64_t row)`), never raw `int32_t` or `uint8_t` pointers, so every element is
    widened before any arithmetic (§4). All the rules of §4 and §6 are scanned here;
  - `bind/` holds `SimKernels`, `world_access.h` and `register_types`, the only files that touch
    Godot types. Each kernel has its own file (`bind/kernel_<phase>.cpp`), and registration is
    one line per kernel in `bind/kernel_list.h`, so two port PRs touch disjoint files except that
    one line each.

  The split makes the purity scan simple, allows a standalone sanitizer harness (§10), and keeps
  the rule code portable to wasm and iOS.
- **Every `core/` function lands with the kernel that calls it.** gdUnit4 can call only bound
  methods, and the sanitizer harness (P57) comes later, so a `core/` function that no bound kernel
  calls would merge untested. A port PR therefore adds a `core/` function only together with the
  kernel that calls it, and that kernel's lockstep or module tests under both implementations run
  in the same PR. That is why `best_neighbour` and `acquire` land with INTEGRATE (P37n), not with
  FLOW, and `FogGrid.stamp` with FOG (P46n). A split part of a port that holds a kernel also
  holds tests that run it (the module's tests under both implementations); the second part adds
  the 900-tick lockstep and the crafted cases. There are no test-only bound entries.
- **Measured cost** (evidence comment on PR #41, section 2: the official 4.7.2 editor binary,
  `template_debug` library, cloud VM; mean µs per tick, 42 written arrays of 256 rows; three runs):

  | Pattern | µs per tick | Notes |
  | --- | --- | --- |
  | `Object::get` by name, in place | 4.6-5.7 | about 0.1 µs per array |
  | `const Variant &` arguments, in place | 7.8-8.3 | includes building the GDScript `Array` of 42 arrays |
  | Copy-in / copy-out | 14.4-15.4 per pass | also loses writes made through earlier aliases (section 1) |

  The first research run reported 8.5, 7.2 and 18-31 µs on the `linux_release` template; that
  was not re-run. Phone costs are not measured. About 5x the VM is an extrapolation from the
  spike's C++ ratio.
- **Why `Object::get` and not array arguments.** Both are in place and cost a few µs per tick.
  `Object::get`:
  - keeps every entry's signature to the World plus plain ints (§3);
  - reads the member at call time, so it survives a reassignment;
  - uses the same names as the shape lists, which a test can check (P54).
- **Why the World does not move into C++.** Measured on a C++-owned array exposed as a property
  (evidence comment, section 1):
  - GDScript writes through it are lost silently, on typed and untyped paths alike
    (`w.owned[0] = 5`, `append`, `fill`). That would silently break `add_unit`, `prepare`,
    `remove_dead` and every test that builds a World;
  - the web would need a second World;
  - the editor constructs a registered class during the import (once per seeded `--import`), so a
    C++ World's constructor and getters would also run inside the editor;
  - the snapshot capture would gain only about 3 µs (first research run, not re-run).
- **Boundary tests**, in two PRs, because the write cases need a kernel that writes and there
  are no test-only bound entries:
  - **P54** (`tests/sim/native/test_kernel_abi.gd`, no kernel yet; the checked table holds the
    five phases' lists, above):
    - on a prepared arena World, `check_world` returns 0 for each of the five phases;
    - it returns the expected status for a wrong type and for a wrong size of each kind the lists
      use (each Packed array type, FLOW's typed `Array` of slot objects, and one slot's array
      inside it), and a World it rejects is left unchanged (no log line is produced or
      allowlisted);
    - the same `check_world` cases on a worker `Thread`;
    - every name in the table, fetched **or set**, exists in the World's shape and scalar lists
      or the helpers' `HASHED`/`UNHASHED` lists, with the expected type, and each of the five
      lists is non-empty, so the test cannot pass on an empty table;
    - no bound `SimKernels` method has a Packed-typed argument (`ClassDB.class_get_method_list`).
  - **P30n**, the first kernel, through the FLOW kernel (`tests/sim/native/test_kernel_abi.gd`
    gains these, each also on a worker `Thread`):
    - an in-place write is visible on the slot's member and through a GDScript alias taken
      before the call (an array the call writes but does not swap: a budget below the field's
      remaining cells);
    - with a `duplicate()` of that array held, the member forks once and the copy keeps its old
      values;
    - the `FlowCache` and slot scalars the kernel sets on exit arrive (the same values as the
      GDScript twin's);
    - a budget-0 call (the checkpoint-tick case) after an ordinary FLOW call (a non-zero
      budget through `FlowCache.run`; P30n has no `Sim.step` tick to call) leaves `state_hash`
      unchanged.

  They rerun on every Godot or godot-cpp pin change, because in-place writes rely on the
  internal-pointer getter (interface since 4.4, "can be used to modify it in-place") and on the
  layout of the Variant's Packed array.

  Status note (2026-10-13, P26l docs, P54 as merged, #70), the text above stays as accepted:
  - `SimKernels.check_world(world, phase)` returns 0 or `table_index * 5 + fault`, where
    `table_index` is the first bad name's index in the table (`status_of` and the `Fault` enum
    in `src/core/world_status.h`): 1 unknown phase, 2 missing owner object, 3 wrong Variant
    type, 4 wrong length. A null World gives fault 2 at the phase's first name. It prints
    nothing.
  - The five lists are one table, `SIM_CHECKED_TABLE` in `bind/world_access.h`: 106
    `X(owner, name, kind, size, phases)` entries, each with a phase bitmask (FLOW 30 names,
    TARGETING 32, SEPARATION 28, INTEGRATE 53, FOG 29). `tests/sim/native/test_kernel_abi.gd`
    reads the table from `world_access.h` itself, so there is no test-only binding.
  - `bind/kernel_list.h` is `SIM_KERNEL_LIST(K0, K1)`: each line generates the method's
    declaration in `sim_kernels.h`, its `ClassDB` binding and its bit in `phases()` (with a
    `static_assert` that the phase has a list). P54 has no line.
  - `core/` starts with `world_status.h` (the `Fault` enum and `status_of`), which no kernel
    calls yet; its header records this one exception to "every `core/` function lands with the
    kernel that calls it" (the purity scan must see `core/`, and the status encoding is
    shared). `WorldView` and the internal-pointer fetch (`ptr`/`ptrw`, steps 1-3 above) land
    with P30n's first kernel. The event-resize helper ("Forbidden" above: the event appends go
    through `world_access.h`) moves to P42n, with a case that the resized array is written back
    and its pointer fetched again.
  - `check_world` is a diagnostic, not a hot-path call: each call checks its phase's whole list,
    fetching each helper, the slot `Array` and each length rule once (FLOW about 8.7 µs on the
    arena, all five phases about 25 µs). Which check a kernel runs on entry ("The kernel calls
    it on entry" above), given that cost, is open for P30n, the first kernel; no decision
    here.
  - The review fixed a use-after-free: an `Object*` taken from a Variant that died on return.
    The merged check holds each helper's Variant for the whole call. §10's status note records
    why the sanitizers cannot see that class.

  Status note (2026-10-14, P26m, P30n as merged, #74, and P30n2, #75), the text above stays as
  accepted:
  - **`WorldView` as realised.** The struct of raw pointers and sizes that "Two layers" names is
    `ArrayView<T>`, one per array (`src/core/array_view.h`), with `flow::Slot` as the aggregate
    (`src/core/flow.h`: "One FlowField: its arrays as views and its int and bool members", which
    the kernel loads from the slot object and stores back per slot turn). The kernel's World and
    cache arrays (`unit_id`, `field`, `stats`, `move_cost`, `status`, `requested`, `ref_count`
    and the others) reach `core/` as separate `ArrayView`s and ints, not inside a `Slot`, so
    `Slot` is one slot's aggregate, not a per-kernel one. The header says, in its own words: "A
    window over one of the World's arrays, for core/ (ADR 0013 section 2): the per-array piece of
    the contract's WorldView, with flow::Slot as the aggregate. The raw pointer is private, so
    core/ reaches an element only through get() and set(): an element is widened to int64_t on
    the way out and narrowed with an explicit cast on the way in (section 4), and the compiler
    enforces that, whatever the element type. An index outside the window reads 0 and writes
    nothing, so the contents of a queue that check_world cannot vouch for never reach memory
    outside the array. Only bind/world_access.h builds a view from a pointer." So §4's "through
    `WorldView`'s accessors" reads `ArrayView<T>::get` and `set`, and the raw `int32_t`/`uint8_t`
    pointer and its `static_cast` stay private to `ArrayView`.
  - **The fetch.** `world_access.h` holds `Borrowed<T>` (the Variant that keeps a Packed array
    alive, with its view) and `read_i32`/`read_bytes` (`ptr()`) and `write_i32`/`write_bytes`
    (`ptrw()`), steps 1-3 above; an empty array or a Variant of another type gives an empty
    view. FLOW's list holds the 26 names `SimKernels.flow` gets or sets: `max_rows`, `map_cols`,
    `map_rows` and `flow_cache_size` lost FLOW's bit (the length rules of `check()` still read
    them; the plan's "Answers and follow-ups (P26m)").
  - **The entry check (the question the P26l docs note left open).** `SimKernels.flow` calls
    `check_world` for FLOW on every call and, on a non-zero status, raises one `push_error`
    naming the property and writes nothing, as "The kernel calls it on entry" says. P30n
    measured an idle FLOW call as costlier natively than in GDScript for that reason, against
    about 10x faster per call overall (0.025 against 0.25 ms on the arena) and about 15x on busy
    calls (PR #74); the plan's row P38pn carries it.
  - **One recorded exception** to "for each slot it touches, the slot's arrays and scalars once"
    ("Arrays of helper objects"): to pick the next slot, the kernel reads `pending` of every
    `ACTIVE` slot through `Object::get` on each pick (`flow::oldest_request` with `pending_of`),
    bounded by `flow_cache_size`, never per row or cell. Reading each once would need a
    capacity literal in C++, which CLAUDE.md rule 1 forbids. It stays; the plan's "Answers and
    follow-ups (P26m)" records it.
  - **The split.** P30n's part 1 held the whole kernel with the module's tests under both
    implementations, and part 2 (P30n2) the 900-tick lockstep, as "Every `core/` function lands
    with the kernel that calls it" above says for a split port.

  Status note (2026-10-14, P26n docs, P56b as merged, #78), the text above stays as accepted:
  "a struct of raw pointers and sizes" in "Two layers" is superseded. A `core/` view keeps its
  raw pointer private (`ArrayView<T>`, P26m's note above), and `core/` reads only through the
  view's `int64_t` accessors. P56b's `view_pointer` rule in `tests/project/test_native_purity.gd`
  flags a raw pointer member of any element type (`T *`, `int64_t *`, a template parameter)
  declared public or protected in a `core/` `*View` struct or class, templates included (a struct
  is public until a `private:`, a class private until a `public:`), and its `raw_pointer` rule
  flags a use of a view's pointer member outside the view, across `core/` files. Private
  pointers, accessors and friends defined in the view body stay legal, and so do the merged
  `array_view.h`, `flow.h`, `flow.cpp` and `world_status.h`. The scan header names the view
  blind spots left to review (a method that returns the pointer, a `using` alias of it, a
  pointer in a struct nested in a view, a member defined outside the view body, a view that
  `VIEW` does not name); the qa follow-ups of P56b's review are the plan's row P56c.

  Status note (2026-10-19, P26x docs, P37n as merged, #108, and P37n3, #109), the text above
  stays as accepted:
  - **The second recorded exception** to "for each slot it touches, the slot's arrays and
    scalars once" ("Arrays of helper objects"), beside FLOW's re-read of `pending` (P26m's note
    above). The INTEGRATE pass asks a slot for `complete` once per slot and call and keeps the
    answer in a 63-slot mask (`integrate::MEMO_SLOTS` in `core/integrate.h`,
    `std::numeric_limits<int64_t>::digits`, pinned by
    `tests/sim/native/test_integrate_kernel_slots.gd`, which reads the line as text and checks
    `flow_cache_size` against it); a recycle (`flow::acquire` handing a slot a new key) updates
    the answer. The rest of a slot (`cost`, `grid_cols`, `cell_count`, `stride`) is fetched at
    event cadence, where a FIELD unit looks up its next tile. A slot past 63 is asked on each use
    (`flow_cache_size` is 8 in `data/rules.tres`). No `Object::get` per row. The reason, in
    `bind/kernel_integrate.cpp`'s header: holding the cost array of every slot for the whole call
    needs room for as many as there are, and `flow_cache_size` has no upper bound to size it by.
    The plan's section P37n "As merged" records it.
  - **The `isqrt` shift table is accepted as structure, not a rule value.** `SHIFTS` in
    `core/fixed_math.cpp` (32, 16, 8, 4 and 2) are the five steps that `FixedMath.isqrt` writes
    as literals: they mirror the twin's code, not a rule int, and change only with it.
  - **The checked table** holds 107 entries (P54's note above: 106). INTEGRATE's list holds the
    49 names the kernel gets or sets (P54's note: 53): `max_rows`, `flow_cache_size`,
    `order_target`, `target` and `stats` lost its bit, and `group_cell` (P37b) is new.
  - **`step_toward`**, which §1 names among INTEGRATE's `core/` functions, is not in `core/`:
    `Movement.integrate` does not call it (the step is `Movement.run`'s, in INTENTS), and a
    `core/` function lands with the kernel that calls it, so it comes with P37n2 if INTENTS's
    rule fires. `isqrt`, `best_neighbour` and `acquire` landed with INTEGRATE, and FLOW's
    per-call loop moved into `core/flow.h` as `flow::run` (the plan's "Answers and follow-ups
    (P26s docs)", decision 3).

  Status note (2026-10-20, P26y docs, P39n as merged, #113), the text above stays as accepted:
  - **SEPARATION's checked list** holds the 20 names `Separation.run` reads (P54's note above:
    28): the five rule ints `separation_neighbours`, `separation_scan`, `separation_idle_share`,
    `separation_push_max` and `separation_coincident_divisor`, the World's `unit_id`,
    `type_index`, `type_radius`, `pos_x`, `pos_y`, `intent_x`, `intent_y`, `push_x`, `push_y` and
    `stats`, and `sep_grid`'s `cols`, `rows`, `cell_milli`, `head` and `next`. `max_rows`,
    `map_cols`, `map_rows`, `map_w`, `map_h`, `move_cost`, `type_speed` and `type_move_class`
    lost its bit, as INTEGRATE's list was trimmed in P37n. No name was added; the table still
    holds 107 entries.
  - **The empty-grid return.** The twin and the kernel both return with every push 0 when the
    grid has no cells or a cell side below 1 (`cols == 0 or side < 1`): in C++ a cell side below 1
    would divide by zero.
  - **The divisor's range is recorded, not clamped** (P39n's call, as the plan left it):
    `core/separation.h` states the pass exact in `int64` while the positions stay within 10^9
    milli-tiles, a pair's reach is at most 2,097,151 and `reach * coincident_divisor` is at most
    3,037,000,499. Past that the production build wraps like the twin (`-fwrapv`) and the
    sanitizer build aborts.

  Status note (2026-10-21, P26ac docs, P41n as merged, #132), the text above stays as accepted:
  - **The fourth kernel.** `bind/kernel_list.h` gains `K0(targeting,
    world_access::PHASE_TARGETING)`, so the library's phase mask is 0x6A (FLOW 1, TARGETING 3,
    SEPARATION 5, INTEGRATE 6), the mask `tests/sim/support/sim_impls.gd`'s `EXPECTED_PHASES`
    gives. 0x46A is this ADR's five-phase mask with FOG (bit 10): `tests/sim/test_kernel_dispatch.gd`
    uses it, less one phase's bit, as a spy mask, and `tests/sim/native/test_kernel_abi.gd` pins
    it as the table's `PH_ALL` and as the mask of the five phases; no library reports it.
  - **TARGETING's checked list** holds the 35 names the kernel gets or sets (it held 32 before P41n):
    `nav_cell`, `field`, `nav_next`, `best_dist`, `stall` and `line_check_period_ticks` gain
    `PH_T`, and `max_rows`, `hp` and `type_speed`, which the kernel never reads, lose it, as
    INTEGRATE's and SEPARATION's lists were trimmed in P37n and P39n. The table still holds 107
    entries, and `hp` now carries no phase bit.
  - **`line_clear` in `core/`.** `FixedMath.line_clear` landed with the kernel that calls it, in
    `native/sim_kernels/src/core/fixed_math.h` and `.cpp`; an INTENTS port (P37n2, not triggered
    at P46's line, §1's note above) would take it as it is.
  - **The empty-grid guard.** The twin's empty-map test changed from `cols == 0` to `cols >= 1
    and lines >= 1 and side >= 1` (`cells` in `Targeting.run`, and the same `cells` in
    `Pass::acquire` of `core/targeting.cpp`): a grid with no rows of cells or a cell side below 1
    finds nobody, because C++ cannot divide by the side; `SpatialGrid.configure` never makes such
    a grid. It is the one change to the twin's rule.
  - The `check_world` refusal path has no test for any of the four kernels (the log scan rejects
    the `ERROR` line), as P26y docs' note recorded for three. The plan's section P41n "As merged"
    holds the details.

  Status note (2026-10-21, P26ad docs, P46n as merged, #134), the text and the notes above stay
  as accepted and as dated:
  - **The fifth kernel.** `bind/kernel_list.h` gains `K0(fog, world_access::PHASE_FOG)`, so the
    library's phase mask is 0x46A (FLOW 1, TARGETING 3, SEPARATION 5, INTEGRATE 6, FOG 10), the
    mask of `tests/sim/support/sim_impls.gd`'s five `EXPECTED_PHASES`. The P41n note's "the
    library's phase mask is 0x6A" and "no library reports it" (0x46A) were true on `main` at
    `f1494a5`; since P46n the library reports 0x46A. The first line of `FogUpdate.run` is the
    dispatch (bit 10). `FogUpdate.begin`, `World.remove_dead`'s unstamp, `World.prepare()`'s
    initial stamp and `FogGrid.begin_update` stay GDScript (REMOVE is not a ported phase) and
    keep calling `FogGrid.stamp`, which stays the reference; its C++ twin is `fog::stamp` in
    `core/fog.cpp`, which writes the visible counts, the explored bytes, the fixed dirty-list
    blocks with their counts and flags, the `listed` marks and the version in place (P26h's
    note above).
  - **FOG's checked list** holds the 25 names the kernel gets or sets (P54's note above: 29):
    `max_rows`, `map_cols`, `map_rows` and `type_speed` lose its bit, so `max_rows` now carries no
    phase bit. `type_sight` keeps it: `run` reads only its size, the id of the pad mask. The
    table still holds 107 entries.
  - **The mask pick** is the twin's `mini(type_index, type_sight.size())` (in C++
    `smaller(type_index, rules.pad_mask)`, with `pad_mask` the size of `type_sight`): the pad
    mask's id is fixed at `prepare()`, so a mask added after it changes no id.
  - **The twin's guard.** `FogUpdate.run`'s `fog.cells == 0` test became "the sides make the
    cells" (`cols >= 1`, `rows >= 1` and `cells == cols x rows`, tested by division so that it
    cannot overflow; `usable(grid)` in `core/fog.cpp` is the same test), because C++ cannot divide
    by a side of 0. `FogGrid.configure` never makes such a grid. It is the one change to the
    twin's rule.
  - Native timing (PR #134's text, seed-42 arena): the FOG phase about 0.054 -> 0.010 ms, the
    native `est_phone_p95_ms` about 8.9 -> 6.2. The plan's section P46n "As merged" holds the
    details; the 900-tick lockstep and the crafted cases are P46n2's.

  Status note (2026-10-21, P26ae docs, P46n2 as merged, #141, and P46b as merged, #144), the text
  and the notes above stay as accepted and as dated:
  - **TARGETING's checked list** holds 40 names (the P41n note above: 35): FOG's `cols`, `rows`,
    `cells`, `player_count` and `visible` gain `PH_T`, because the kernel applies P46b's vision
    rule and reads them from the World (`bind/kernel_targeting.cpp`); `core/` holds no fog
    literal, only the `TILE` mirror of `Targeting.TILE`. The twin and the kernel see every cell
    for owner 0, an owner past `player_count` and a fog whose sides do not make its cells.
    `tests/sim/native/test_kernel_abi.gd` pins the list sizes (`LIST_SIZES`).
  - **The FOG lockstep** (P46n2): `tests/sim/native/test_fog_lockstep.gd`,
    `test_fog_lockstep_cases.gd` and `test_fog_lockstep_random.gd` compare the twin and the kernel
    after every tick, the full fog state included; `bind/kernel_fog.cpp` and `core/fog.h` name
    them. The plan's sections P46n2 and P46b "As merged" hold the details.

  Status note (2026-10-26, P26ai docs, P71 as merged, #184, and P71b, #185; the text and the
  notes above stay as accepted and as dated):
  - **TARGETING's checked list** holds 41 names (P46b's note above: 40): `type_speed` gains `PH_T`
    again, because a lock on a target that stands still keeps the row's goal (ADR 0017 §1 and its
    note of the same date). `tests/sim/native/test_kernel_abi.gd` pins it (`LIST_SIZES` 3: 41).
  - **The building worlds:** `tests/sim/native/test_building_lockstep.gd` runs every ported
    kernel on a world with buildings for 450 ticks, not §4's 900; the 900-tick locksteps of each
    kernel stand as they are. `tests/sim/native/test_building_attack_lockstep.gd` is P71b's
    lockstep for an `ATTACK` on a 1x1, a 2x2 and a 3x3 building with TARGETING alone, INTEGRATE
    alone or every kernel in C++ (the artillery cases: TARGETING alone and every kernel).

### 3. Dispatch and the implementation switch
- **`World` gains two members (P54):**
  - `kernels: Object`, where null means GDScript;
  - `native_phases: int`, one bit per `SimProbe.Phase`, listed in `UNHASHED_SCALARS`.

  The choice of implementation is therefore never hashed. The golden hashes are the same in both.
  `kernels` is not state: P54 adds `const NON_STATE_MEMBERS: Array[StringName] = [&"kernels"]` to
  the World. ADR 0007 §8's coverage test, the `state_hash` walk and P38j2's reachability walk
  skip exactly the members of that list (P38j and P38j2 depend on P54, which creates it), and a test pins that it holds only `kernels` (an object
  member outside it still fails the coverage test). The snapshot's `COPIED`/`NOT_COPIED`
  coverage spans only the five shape lists, which hold neither `kernels` nor `native_phases`, so
  P38s does not change.
- **One entry per phase, and the dispatch is its first line.** The entry is the function whose
  call line `Sim.step` holds:

  | Phase | GDScript entry (the `Sim.step` line) | Kernel |
  | --- | --- | --- |
  | `FLOW` | `FlowCache.run(world, budget)` (static: the recount, then `world.flow.advance`) | `flow(world, budget)` |
  | `GRIDS` (only if its rule fires, §1) | `SpatialGrid.rebuild_grids(world)` (static: one `_rebuild_one(world, which)` line per grid) | `grids(world, which)` |
  | `TARGETING`, `SEPARATION`, `INTEGRATE`, `FOG`; `INTENTS`, `PROJECTILES`, `FIRE` only if their rule fires | the module's `run(world)`: `Targeting.run`, `Separation.run`, `Movement.integrate`, `FogUpdate.run`; `Movement.run` for `INTENTS` (the plan's `Sim` contract row: "`Movement.run` (intents)"); `Combat.advance_projectiles` and `Combat.fire` | `targeting(world)`, `separation(world)`, `integrate(world)`, `fog(world)`, `intents(world)`, `projectiles(world)`, `fire(world)` |

  The dispatch is
  `if ((world.native_phases >> SimProbe.Phase.X) & 1) == 1: world.kernels.x(world[, int]); return`
  (for GRIDS inside `_rebuild_one`). Kernels take the World and plain ints only; `budget` and
  `which` are ints computed in GDScript (the budget stays 0 on checkpoint ticks, ADR 0012 §5).
  The probe marks do not change. FLOW changes one contract:
  - the `Sim` contract row: `Sim.step`'s FLOW line calls `FlowCache.run(world, budget)`, so ADR
    0012 §5's "`Sim.step` passes 0 cells to `FlowCache.advance`" reads "passes a budget of 0 to
    `FlowCache.run`";
  - P30n adds the entry with its dispatch, and P37b, which adds that `Sim.step` line, calls it
    (the plan's model merges P30n first). Only if P30n has not merged when P37b opens does P37b
    add the entry without the dispatch, which P30n then adds; if P37b merged before this ADR was
    accepted, with the `FlowCache.advance` line, P30n also changes that one line.

  GRIDS keeps its plan contract (one rebuild line per grid in `Sim.step`) unless its rule fires.
  Then its port row (P41g) adds `rebuild_grids` and turns the two `Sim.step` lines into one line
  with the `GRIDS` mark.

  The FLOW kernel can be ported before its `Sim.step` line exists: its lockstep test calls the
  kernel directly against the GDScript call, and the dispatch lands with the entry (plan row
  P30n).
- **`game/sim` never names `SimKernels` or `ClassDB`:**
  - a project without the library could not parse such a script;
  - the call is dynamic on an untyped `Object` (0.48-0.53 µs per call, evidence comment section
    2). That is 5 calls per tick now (FLOW, TARGETING, SEPARATION, INTEGRATE, FOG), and at most
    10 if every rule of §1 fires: INTENTS, FIRE and PROJECTILES add one each, and GRIDS two,
    because it dispatches inside `_rebuild_one`, once per grid;
  - `test_sim_purity` bans both names in `game/sim`.
- **`game/core/NativeKernels.gd` (lead, P54r):**
  - `create() -> Object` returns null when `ClassDB.class_exists(&"SimKernels")` is false or the
    library's `abi_version()` differs from the GDScript constant;
  - `MatchRunner.sim_impl` is `GDSCRIPT`, `NATIVE` or `AUTO`. **The default is `GDSCRIPT`**,
    mirroring `tick_mode = SYNC`: a runner a test builds runs the twins unless the test asks
    otherwise;
  - `self_check(scenario: ScenarioDef, seed: int, ticks: int, kernels: Object, mask: int) -> bool`
    is the on-device lockstep. It builds two Worlds from the scenario and seed
    (`World.from_scenario`, then `prepare()`), A with no kernels and B with `kernels` and
    `native_phases = mask`, steps each through its own `MatchLoop` in `SYNC` with the scenario's
    orders for `ticks` ticks, compares `state_hash()` after every tick, and returns false at the
    first difference. It touches no runner, World or snapshot of the match.
- **When the self-check runs.** Only in the perf arena, through `PerfHud.preflight(runner)`:
  P50a2 adds the self-check seam (and the entry, if P50a has not added it for ADR 0014), and
  P50b's `perf_arena.gd` calls `preflight()` in its `_ready`, before it starts the arena's
  runner (the scene's runner has no `scenario`, so it does not start itself). So it runs on the
  main thread, with no World and no job in flight, and before ADR 0014's reference burst (the
  next seam) if that ADR is accepted; P50b's headless test pins the order (self-check, burst,
  runner start) and that no job is in flight. A preflight with a job in flight is refused by a
  pure check (`PerfHud.preflight_allowed`): the run is `INVALID` with a reason, and nothing
  calls `push_error`, so no test prints `ERROR:` (plan, P50a row). Its inputs: the seed-42 arena, 60 ticks,
  `NativeKernels.create()` and its `phases()`. It runs only when the resolved implementation is
  `NATIVE`; otherwise the card's `self_check` reads `not run` (on Android the `impl` verdict
  fails anyway). It never runs in ordinary matches. It takes about 1-3 s on the gate phone (an
  estimate: 60 ticks on each of two Worlds with a hash per tick, the GDScript World at up to
  2.4 times the mock's 11-19 ms per tick, so up to about 2.7 s), outside every timed window.
- **Its tests (P54r, headless, library loaded).** P54r depends on P37n, so FLOW (P30n, in the
  tick through P37b's line) and INTEGRATE run natively by then:
  - the seed-42 arena for 60 ticks with `kernels.phases()` returns true, and the test asserts
    that the mask holds FLOW and INTEGRATE and that `kernels.get_class() == "SimKernels"`;
  - the mutated case: a GDScript spy kernels object (like P54's dispatch spy) whose
    `integrate(world)` adds 1 to `pos_x[0]` instead of running the phase, with the INTEGRATE bit
    set, returns false;
  - mask 0 returns true.
- **The three settings:**
  - `NATIVE` on a build without the library is an error;
  - `AUTO` means `NATIVE` whenever the class exists. Without it, `AUTO` falls back to `GDSCRIPT`:
    with one `push_error` on Android, where the library is required (below), so the dev APK's log
    and the card show it; with one warning on Linux and other desktops; silently on the web.
    `resolve_impl` itself is pure; `start()` logs the result, and tests call `resolve_impl` with
    the OS name injected, so no test triggers the Android `push_error`;
  - headless CI runs `NATIVE` in the native suites and both implementations in the twin suites
    (`tests/sim/support/sim_impls.gd`).
- **Who sets what:**
  - **P50b** sets `sim_impl = AUTO` in `scenes/main.tscn` and `scenes/dev/perf_arena.tscn`, next
    to `tick_mode = AUTO`, and its scene test asserts both. It also adds the `preflight()` call
    before the arena's runner starts ("When the self-check runs" above). Before P50b no scene runs the native
    path, and the gate card cannot show `sim impl: native` without it. By P50b every port row
    that exists has merged (P49a's Depends cell names every port row, conditional rows that fired
    included, and P50b needs P49a);
  - **ordinary runner tests** (a runner built in code) keep the default `GDSCRIPT`, as they keep
    `SYNC`. Tests that load `main.tscn` or `perf_arena.tscn` get the scene's `AUTO` from P50b on,
    so they run native headless (`verify.sh` always builds the library), while `tick_mode = AUTO`
    still resolves to `SYNC` there. The native runner path is also proven by P54r's runner tests,
    P38w's lockstep with `NATIVE`, and P50w's main-scene worker run (native against GDScript
    checkpoints);
  - **`run-sim-smoke.sh`** is a stub in Phase 2 ("no sim yet"; it starts no Godot), so it uses
    neither. When Phase 4 replaces its body, it runs `AUTO` and prints the resolved
    implementation in its report; `verify.sh` always builds the library first, so that means
    native, while the twin suites and the golden hashes cover GDScript. The Phase 4 plan
    records this.
- **One source for the native mask.** The library reports the phases it implements
  (`SimKernels.phases() -> int`, derived from `bind/kernel_list.h`). `MatchRunner` (for
  `NATIVE`) and `sim_impls.gd` both set `world.native_phases = kernels.phases()`, so CI tests the
  mask that ships. `sim_impls.gd` also holds `EXPECTED_PHASES` (one entry per line) and asserts
  that the library reports exactly that, so a port PR that forgets its registration line fails.
  The perf card and the `PERF` line print the mask as phase names.
- **Test Worlds.** A World is GDScript by default (`kernels == null`); that holds for every
  hand-built World a test makes. `sim_impls.gd` attaches the kernels and the full native mask to
  any World, hand-built ones included, after `prepare()`. `prepare()` is a precondition of every
  native call (without it `check_world` rejects the sizes). The module tests that run "under both"
  go through `sim_impls.gd`, so their native pass really runs C++.
- **Proof that C++ ran (no vacuous pass).**
  - P54's dispatch test: a World whose `kernels` is a GDScript spy object (the member is an untyped
    `Object`). For each phase bit it asserts that the entry calls exactly the matching spy method
    once and skips the GDScript body; with the mask 0 it calls nothing. P54 ships the harness
    and the mask-0 case; each port PR adds its phase's case.
  - Every lockstep test and `sim_impls.gd`'s native pass assert
    `world_b.kernels.get_class() == "SimKernels"` and that the phase's bit is set.

  Status note (2026-10-13, P26l docs, P54 as merged, #70): `sim_impls.gd`'s
  `use(world, impl, kernels)` returns its problems as an `Array[String]` (no library, a mask
  other than `EXPECTED_PHASES`, kernels whose `get_class()` is not `SimKernels`) instead of
  asserting, and attaches the kernels either way; `is_native(world, phase)` is the check of the
  bullet above. So the module tests of P30n, P37n, P41n and P46n assert that `use()` returned an
  empty list and that `is_native(world, phase)` holds (through the preload name `SimImpls`, as
  `test_kernel_abi.gd` does).

  Status note (2026-10-14, P26m) on the note above: "attaches the kernels either way" holds only
  for kernels that exist. With a mask other than `EXPECTED_PHASES` or kernels of another class,
  `use()` attaches them and the mask and lists the problem; with no library
  (`create_kernels()` gives null) it attaches nothing, leaves `kernels` null and
  `native_phases` 0, and returns its problem list. Either way a caller asserts the list is
  empty.
- **The bitmask** lets a lockstep test switch one phase at a time: World A runs all GDScript,
  World B runs only that phase in C++.
- **On Android the library is required.** `export-android.sh` checks that the APK holds the
  library of the export mode it runs (§8: the debug APK the `template_debug` library, the release
  APK the `template_release` one), with the bytes CI built. The perf card prints
  `sim impl: native (<build info>, phases <names>)` and a 60-tick lockstep self-check line
  (`NativeKernels.self_check`, above), as the spike's mode 5 did. Three checks catch a missing
  library: the APK check at export, the `push_error` of `AUTO` on Android, and the card's `impl`
  verdict (P50a). Like `release_only`'s
  `build: FAIL (debug template)` line, it fails the run by itself: on Android (the platform where
  `resolve_impl` treats a missing library as an error), a resolved implementation other than
  `NATIVE` gives `impl: FAIL (gdscript)`, and a self-check other than a match gives
  `impl: FAIL (self-check mismatch)`; either makes `GATE: FAIL`. Elsewhere the line reads
  `impl: n/a`.

  Status note (2026-10-20, P26z docs, P54r as merged, #116), the text above stays as accepted:
  `NativeKernels.self_check` compares `state_hash()` after every tick, as written. `FlowCache`
  and `FlowField` are derived state that the hash leaves out (their `HASHED` lists are empty), so
  a divergence in FLOW alone shows in the self-check only once it changes a route, that is a
  unit's step; `tests/sim/native/test_flow_lockstep.gd`, which compares the full state after
  every call, stays the per-call check of the FLOW kernel. The OS rule of the fallback lives in
  a second pure function: `MatchRunner.resolve_impl(impl, has_library, _os_name)` does not use
  the OS name (the web runs the twins because its export packs no library), and
  `MatchRunner.fallback_log(impl, resolved, os_name)` returns an `ImplLog` (`NONE`, `WARNING`,
  `ERROR`): `NATIVE` without the library is an error on every OS, and `AUTO`'s fallback is an
  error on Android, nothing on the web and a warning elsewhere. So "the platform where
  `resolve_impl` treats a missing library as an error" above reads `fallback_log`. `start()`
  logs through the seam `MatchRunner._use_impl(target, kernels, os_name)`, and the ABI check is
  `NativeKernels.abi_matches` (`ABI_VERSION = 1`) behind the seam
  `NativeKernels._create(kernel_class)`; plan contract rows `MatchRunner` v1 and Native kernels,
  "P54r as merged".

  Status note (2026-10-21, P26ad docs, after P46n, #134; the text above stays as accepted): like
  FLOW (the P26z note above), FOG has outputs that the hash leaves out. `self_check` compares only
  `state_hash()`, and of the fog the hash covers `visible` and `explored` (`FogGrid.HASHED`);
  `version`, the dirty lists (`dirty`, `dirty_count`), `dirty_full` and `listed` are unhashed.
  On a device the self-check therefore cannot see a fault of the FOG kernel in those outputs,
  which `FogLayer` reads (`version_of`, `dirty_cells`, `dirty_overflowed`; `listed` decides what
  the lists hold). In CI they are P46n2's to cover (the plan's row P46n: the 900-tick lockstep of
  `visible`, `explored`, `version`, the dirty lists and `listed`). The device side is an open
  item: no decision here; a later core PR or a later note takes it.

  Status note (2026-10-21, P26ae docs, after P46n2, #141; the text and the note above stay as
  accepted and as dated): P46n2 merged, so CI covers those outputs (its rig compares the whole
  fog after every tick). The device side is unchanged and open: a small `game/core` follow-up
  that compares the `FogGrid` arrays when FOG is in the mask would close it; no decision here.

### 4. Determinism rules for C++
- **Language and types:**
  - C++17;
  - `int64_t` wherever GDScript holds an `int`;
  - `int32_t` or `uint8_t` exactly where the World stores into a `PackedInt32Array` or
    `PackedByteArray`, with an explicit `static_cast` at the store;
  - indices are `int64_t`;
  - **every element read from an `int32` or `uint8` array is widened to `int64_t` before any
    arithmetic**, through `WorldView`'s accessors (§2). C++ would otherwise compute
    `(px[i] - px[j]) * (px[i] - px[j])` in 32-bit `int` and wrap, where GDScript computes in
    int64: squared distances in milli-tiles reach about 8e9 on a 64x64 map (ADR 0007 Facts).
    `-Wconversion` does not flag that, because nothing narrows. Raw `int32_t` pointers appear
    only at the store, with its `static_cast`;
  - no plain `char`, `short`, `long` or `int` as a type in `core/`. `char` is signed on x86_64
    and unsigned on arm64 Linux and Android; `long` is 32-bit on wasm32.
- **No floating point:** no `float`, `double`, `<cmath>` or float literals.
- **No undefined behaviour:**
  - no signed overflow (ADR 0007 §1 already bans int64 overflow in the sim);
  - shifts only on non-negative values, by 0-62;
  - no division by zero, and no `INT64_MIN / -1`;
  - no index outside the size checked on entry;
  - no uninitialised read;
  - no type punning (`reinterpret_cast` and `const_cast` only in `world_access.h`).
- **Division:** `/` and `%` truncate toward zero in C++ and in GDScript, so they port one to one.
  Each port's crafted cases include a negative operand.
- **`-fwrapv`** in every production and test build. It turns signed overflow from undefined
  behaviour into a defined wrap, so an overflow cannot be optimised into something else. It
  keeps the twins equal only for `int64_t` overflow, which ADR 0007 §1 bans anyway; it does not
  help 32-bit arithmetic, which GDScript never does (hence the widening rule above). The
  sanitizer build drops it, so an overflow fails there. Its speed cost is not measured; P53
  measures it on the mock. `-fwrapv` stays in every production build until Michael decides
  otherwise: above 5 % the lead brings the number to him in P53's review with a recommendation,
  and dropping it would need a new ADR that supersedes this rule.

  Status note (2026-10-13, P26i, P53 review): P53 measured it on a scratch copy of the spike's
  mock. The tick mean rose by at most 1.9 % (g++ `-O2`; its flow slice mean +4.1 %), by 0.5 %
  with g++ `-O3` (slice +0.6 %), and fell by 1.6 % with clang++ `-O3`, the shipped build (slice
  -0.1 %). That is under the 5 % rule, so nothing went to Michael and `-fwrapv` stays.
- **Order:**
  - the same loops in the same ascending row order as the twin;
  - no unordered containers, no `std::hash`, no ordering by pointer value;
  - no threads and no SIMD intrinsics. Compiler auto-vectorisation of integer code is allowed,
    since it cannot change integer results.
- **No randomness in Phase 2 kernels.** A later kernel that draws numbers gets a C++
  xoshiro128\*\* twin, checked against `det_random_ref.py` and `DetRandom`. The streams stay in
  the World.
- **Identity is proven six ways:**
  1. a per-kernel lockstep test against the GDScript twin: 900 ticks of the seed-42 arena. After
     every call it compares the full state, not only the arrays the phase writes: every
     `hash_parts()` section, the runtime and scratch arrays, every `HASHED`/`UNHASHED` scalar of
     the World and its helpers (except `native_phases` and the `NON_STATE_MEMBERS`), so a missed
     or misnamed scalar `set` fails it. Each suite also runs once with a non-default
     `rules.tres` (every rule int changed), so a hard-coded rule value fails;
  2. crafted states for every tie-break and cap (exact distance ties, stale queue entries, the
     8-hit and 16-looked-at separation caps), a negative operand for each division, and units at
     opposite map corners (the largest squared distances);
  3. the module's existing tests under both implementations, through `sim_impls.gd` (§3);
  4. golden hashes under both implementations on x86_64 (verify: g++, `template_debug -O2`), on
     x86_64 with clang at the release optimisation (P55's `native-clang` job; P51 adds its golden
     step, §10), and on arm64 Linux with clang at the release optimisation (P51b). On the phone,
     the APK runs a 60-tick lockstep against the GDScript twin (NDK clang;
     `NativeKernels.self_check`, §3: P50a2's preflight seam, called by P50b's arena); the
     full golden check on the device is the gate's checkpoint match, which compares the APK (C++)
     and the web build (GDScript) with the same golden values;
  5. the sanitizer job (§10);
  6. mutants of the port, run by the reviewer, plus a 20,000-tick lockstep run.

### 5. The GDScript twin is kept
- **Every kernel keeps its GDScript version in `game/sim`.** It is the module the plan already
  writes first. It is not deleted after the port, because it has three jobs:
  - the web path (§7);
  - the readable spec of the rule;
  - the lockstep oracle.
- **Order:** the GDScript PR first, as planned. The port PR follows straight after the module's
  last main GDScript PR. Once a port has merged, any change to that rule edits both versions and
  passes the lockstep test in the same PR. This binds every GDScript row whose file list edits
  a module with a merged port, whatever its title: in Phase 2 P41 (`Movement.gd`, after P37n),
  P46b (`Targeting.gd`, after P41n), and Phase 3 onwards. The plan's amendment states it as a
  general line and amends P41's row.
- **Cost:**
  - about twice the code in the hot phases (the spike: about 550 C++ lines for a mock of about
    250 GDScript lines, bind boilerplate included; with the bind layer shared after P54, the
    plan estimates each port at about 1.2-1.5 times the GDScript code lines, plus its lockstep
    test and crafted cases);
  - about 1,800 lines of ports now (about 900 more if all three conditional rows of §1 fire)
    and about 2,200 lines of build, CI and test infrastructure;
  - lane A gets 4 port rows plus P54 before P49a (up to 9 with splits), plus up to 3 conditional
    rows (5 with splits);
  - every later rule change in a hot phase is two edits.

  Status note (2026-10-14, P26m), the cost above stays as accepted: P30n, the first port, came
  to 1,089 changed lines (#74: about 460 of C++ and about 600 of the module's tests under both
  implementations, which §2 requires to land with the kernel) plus 280 for its lockstep (P30n2,
  #75), against the plan's 340. Michael decided in chat on 2026-10-14, verbatim: **"ja til
  port-reglen"**: the native port rows P37n, P39n, P41n, P42n and P46n are re-estimated to their
  real size, about 1,000 changed lines each (about 450 of C++ and about 600 of module tests;
  P42n about 1,000 per kernel it holds), and each splits at the lockstep (part 2 is the
  lockstep test), as P30n and P30n2 did. This sizing rule is not §1's port rule, which is
  unchanged. The plan's rows, "Split triggers" and "Totals" carry it.

  Status note (2026-10-14, P26n docs), the cost above and P26m's note stay: if both FIRE and
  PROJECTILES meet §1's rule, P42n holds two kernels, about 2,000 changed lines (about 1,000 per
  kernel). It is then split per kernel first and each part at its lockstep, in four parts: P42n
  (the FIRE kernel with `test_combat` and `test_counter_triangle` under both implementations),
  P42n2 (its lockstep test), P42n3 (the PROJECTILES kernel with the same module tests under
  both) and P42n4 (its lockstep test). With one kernel it is P42n and P42n2, as P26m's note
  says. The plan's P42n rows, "Split triggers" and lane-A notes carry the same split.
- **Exit route:** web on C++ (§7, option B). It would allow deleting the twins and needs its own
  ADR after the Phase 2 gate. It is not adopted now.

### 6. Threading
ADR 0012 §2 applies to kernels unchanged: they run inside `Sim.step`, on the worker in `WORKER`
mode or inline in `SYNC`, with the same code. In addition:
- **No Godot API inside a kernel**, except `world_access.h` on entry and on exit: `Object::get`
  and `set` on objects reachable from the World, and the one `events` resize. Banned:
  - `OS`, `Time`, `Engine` and print on non-error paths;
  - signals, `call_deferred`, `ClassDB`, resource loading, Nodes and singletons.
- **No shared mutable state:**
  - no mutable statics (static locals included) and no `thread_local`;
  - no threads, atomics, mutexes, futures or OpenMP;
  - `SimKernels` holds no mutable state. Its `StringName`s are made once, in the constructor, on
    the main thread, and only read afterwards.
- **No heap allocation inside a kernel:** no `new`, `malloc` or std containers, and no resize
  except the event appends of §2. Fixed scratch lives in the World's `SCRATCH_ARRAYS` or in
  helper arrays, so tests and the coverage lists see it.
- **The ownership rule stays load-bearing.**
  - Measured (evidence comment on PR #41, section 4; GDScript worker, official editor binary):
    when the main thread read the live arrays during jobs that capture by `duplicate()` and then
    write, 3 of 3 runs hit a torn read: an index failed right after its own size check, because
    the buffer was being replaced. The debug-enabled binary reports that as a script error; the
    first research run saw SIGSEGV in 3 of 3 runs on the release template as well (not re-run).
    The mechanism does not depend on who writes, so GDScript and in-place C++ are alike.
  - The cause: `cowdata.h`'s `_copy_to_new_buffer_exact` sets `_ptr` to null before it
    allocates.
  - A `duplicate()` is a separate Vector, so the snapshot is safe: 3 runs of 2000 hand-offs
    gave 0 wrong values in 530,208-663,904 snapshot reads.
  - Release builds have no engine guard, so the runner's guarded getters and ADR 0012's scans
    stay mandatory. C++ in place adds no risk compared with today's GDScript tick.
- **The reachability walk** (P38j2) accepts the kernels object as a leaf: it is a `RefCounted`,
  neither a Node nor a Resource, and it is listed in `World.NON_STATE_MEMBERS` (§3).

### 7. Web preview, and iOS later
- **The web preview runs the GDScript twins** (option A).
  - Unchanged: the plain `web_nothreads` template, `variant/extensions_support=false`, and no
    emsdk.
  - **Changed (P53):** the Web preset's `exclude_filter` gains `native/*` (main has only
    `tests/*, addons/gdUnit4/*`), with the pin in `tests/project/test_export_presets.gd` updated.
    The Android preset does not get it (ADR 0005 §1 superseded in part, header): the pin asserts
    that its filter holds no `native`, because an excluded library would leave the APK without
    the kernels and with no export error.
    Godot 4.7.2 filters the packed extension list by the preset's exclusions
    (`editor_export_platform.cpp`, `_get_filtered_cache`), so the exclusion is enough. Without
    it, the CI verify job (which builds the library and generates the `.gdextension` before
    `export-web.sh` runs) would pack the extension, and the plain template refuses to start at
    runtime, which no log scan sees;
  - **Changed (P53):** `export-web.sh` seeds the extension list first (§9) and fails when the
    exported pack lists a `.gdextension`, which turns that runtime refusal into a loud error.

  ADR 0012 §7 stays ("the web preview runs `SYNC`; its hashes must match"). It now also checks
  the GDScript twins against golden values that CI computes natively.
- **Cost of option A:** the preview runs the tick at GDScript speed in the frame. The estimate is
  12-18 ms per mock tick in Pixel Chrome (extrapolated, not measured), so preview matches hitch at
  150 units. The preview is for look and controls, and the gate uses the APK. Without
  cross-origin isolation, Chromium rounds `Time.get_ticks_usec()` to 100 µs, so only web means
  are usable.
- **Option B is kept as the exit route, not adopted now.** A research task reported the
  following; its project was deleted and these findings were **not re-run** for the record (the
  evidence comment lists them as such), so P26w measures them again before any ADR relies on
  them:
  - the official 4.7.2 `web_dlink_nothreads_debug.zip` (SHA-256
    `2e7256717078c829ec7b02dadf9e20c490d7ae861b12903b8c7637ba50da554c`) and
    `web_dlink_nothreads_release.zip` (SHA-256
    `555acaddcfde759a431f326a244cb7e20209ef534f7d221b3e2f10879821d8ee`) loaded a side-module
    GDExtension in headless Chromium with no COOP/COEP headers, which is the GitHub Pages
    situation;
  - its int64 checksum matched x86_64;
  - the real game booted on the template;
  - the download grew by 8.65 MB raw / 1.30 MB gzip, and boot by 0.3-0.4 s;
  - GDScript speed was unchanged within noise.

  Why not now:
  - godot-cpp has not been built with emsdk 4.0.20 and `threads=no` (a 354.6 MB toolchain);
  - wasm32 is a third ABI and would need a lockstep run in Chrome in CI;
  - the 4.7 docs say extensions need isolation headers; only the engine code says otherwise;
  - `index.side.wasm` is 44.08 MB against `export-web.sh`'s 50 MiB check;
  - the preview job would need two libraries and the import workaround.

  Adopting it needs a spike (P26w: pinned emsdk, the dlink zips pinned by SHA-256, a Chrome
  lockstep run, Michael on Pixel Chrome) and a new ADR.
- **Option C (no sim in the web preview) is rejected.** Every PR's "how to test on the phone
  preview" relies on playing matches there.
- **iOS** (a later phase; its own plan section before any iOS work):
  - the same sources are built on a macOS runner, which the `.ipa` needs anyway: Godot builds the
    `.ipa` only on macOS. Standard runners are free for public repos, with at most 5 concurrent
    macOS jobs;
  - the build is `scons platform=ios arch=arm64 target=template_release`;
  - it ships either as a static `.xcframework` (loaded through `RTLD_SELF`) or as a `.dylib` that
    the exporter turns into an embedded `.framework`;
  - the `.gdextension` file gets `ios.*` entries;
  - lockstep and golden hashes run on macOS arm64 (Apple clang), plus an on-device self-check.

  A Linux cross-build would need the Apple SDK and is not planned. The risk is the compiler
  (Apple clang against NDK clang), not the architecture.

### 8. Toolchain and pins
| Item | Pin or rule |
| --- | --- |
| Language | C++17 (godot-cpp's standard) |
| Bindings | godot-cpp tag `godot-4.5-stable`, commit `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77`. Fetched by `scripts/build-native.sh` into git-ignored `native/godot-cpp/` (with a `.gdignore`); SHA checked on every build; no submodule |
| API level | `compatibility_minimum = "4.5"` |
| Build tool | SCons 4.9.1 (CI: `pipx install scons==4.9.1`, because the runner's Python is externally managed; sessions: §8 "Sessions"; the script checks the version) |
| C++ format | `clang-format`, one exact version from the PyPI wheel, chosen in P53. `verify.sh` checks the version as `build-native.sh` checks SCons (exit 3 on a mismatch) |
| Linux compiler | the host g++ (godot-cpp ignores `CXX`; `use_llvm=yes` selects clang). Its version goes into the cache key and the library's build info. The Linux library is only for tests and the editor and is never shipped. `build-native.sh` also needs binutils (`readelf`, `nm`) |
| Android | NDK 28.1.13356709 (godot-cpp's default at the pin), installed by sdkmanager in CI (`scripts/ci/install-ndk.sh`); arm64 only; links Godot's `libc++_shared.so`. The template's own `.so` files were built with r29 and its `libc++_shared.so` with r28.0 (Context). 28.1 is kept: it is the same r28 release as the `libc++_shared.so` our library links against, godot-cpp's default, and CI-proven. P55a checks that every undefined libc++ symbol of our library (`llvm-nm -D --undefined-only`) is defined by the APK's `libc++_shared.so`, and the check reruns on every Godot or godot-cpp bump |
| Android page size | `-Wl,-z,max-page-size=16384` passed explicitly in `native/sim_kernels/SConstruct` (godot-cpp's `android.py` sets none). Google Play requires 16 KB page support for apps that target Android 15 (API 35) or higher. Which target SDK our export uses and Google's current deadline are checked in Phase 6, when the AAB ships (ADR 0005); the flag costs nothing either way, so the decision does not depend on the date |
| Targets | `template_debug` (`-O2`, `DEBUG_ENABLED`) for the editor, the tests and the debug APK; `template_release` (`-O3`, `NDEBUG`) for release exports. Android builds both for arm64: the dev APK (`--export-debug`, android-dev-latest) packs the `android.debug.arm64` entry and the release APK (P51r) packs `android.release.arm64`. The second NDK build is a second cold build (its time is not on record; P55a measures it) and is cached under its own key. No LTO, `-fno-exceptions` (godot-cpp defaults), plus `-fwrapv` (§4) and the warning flags (§12) |
| Build profile | `native/sim_kernels/build_profile.json` binds only the classes the bind layer uses (the spike's `native/README.md`: a cold godot-cpp build of "about ten seconds"; P53 measures it) |
| Caches | CI caches `native/godot-cpp` and `SCONS_CACHE`, keyed on the godot-cpp SHA, the SCons version, the compiler version, the platform and the target |

- **The 4.5 against 4.7 API question.**
  - godot-cpp has no 4.6 or 4.7 tag. GDExtension is forward compatible, and the library built
    against 4.5 loaded in 4.7.2 on the x86_64 editor, on the release template and on the arm64
    Pixel 9a.
  - Kernels use only API from 4.4 or older: the internal-pointer getter (since 4.4),
    `Object::get` and `set`, `RefCounted`, and class registration.
  - Moving to a newer godot-cpp tag is a release-engineer PR that reruns the boundary, lockstep,
    import and APK tests and names this ADR. Changing the language, the binding library or the
    build tool needs a new ADR.
- **Sessions.** `verify.sh` needs SCons 4.9.1, g++, binutils and the pinned `clang-format`.
  Without one of them it exits RED and names the missing tool (`build-native.sh` exit 3, the
  format step likewise), never a skip.
  - `scripts/cloud/setup.sh` and `scripts/hooks/session-start.sh` change in P53
    (release-engineer). The hook checks SCons and `clang-format` separately from Godot (today it
    runs the setup only when Godot is missing, so a cached environment would never install them)
    and installs the pinned versions with the setup script's fallback chain (pipx, then pip, then
    `pip --break-system-packages`, then `uv tool`), because the session's Python is externally
    managed.
  - `setup.sh` is pasted into the cloud environment's settings by hand, so Michael re-pastes it
    after P53 merges.
  - These are part of accepting this ADR (question 1): accepting it without them would leave every
    session RED once P53 merges.

Status notes (2026-10-13, P26i) on the rows above, which stay as accepted:
- **Android.** Michael answered in chat on 2026-10-13, verbatim: **"NDK r29"**. The kernels are
  built with NDK **29.0.14206865**, the NDK Godot 4.7.2's Android template is built with. Its
  `libc++_shared.so` is LLVM 21 / Android clang r563880c (`docs/licenses/llvm-libc++/README.md`),
  not r28: P26l attributed the r28 in its `.note.android.ident` (most likely) to r28 sysroot
  objects linked into it (Context's status note). So the row's reason for 28.1 ("the same r28 release as the `libc++_shared.so` our
  library links against") does not hold. P55a applies the pin: `NDK_VERSION` in
  `scripts/build-native.sh`, which P55a's `scripts/ci/install-ndk.sh` reads. P55a's libc++ symbol check
  stays. godot-cpp's own default at the pin stays 28.1.13356709 (`tools/android.py`);
  `build-native.sh` passes `ndk_version=${NDK_VERSION}` to SCons, and building with r29 is P55a's
  to prove in CI.
- **Targets.** godot-cpp gives both targets `-DNDEBUG` (it sets it on every non-dev build), so
  `template_debug` is `DEBUG_ENABLED` plus `NDEBUG`, and C++ `assert()` is compiled out in both
  (P53 review; the header of `native/sim_kernels/SConstruct`).
- **Build profile.** `build_profile.json` enables `OS` and `RefCounted`, and both are needed:
  godot-cpp's `print_string.cpp` includes `os.hpp`. A cold godot-cpp build measured 23-34 s wall
  on the 4-core VM (P53), not "about ten seconds".
- **C++ format.** P53 chose `clang-format` **20.1.8**, the last 20.x patch (godot-cpp's own
  pre-commit hook pins the 20 series), pinned in `scripts/ci/check-cpp-format.sh`, which exits 3
  on any other version.

Status note (2026-10-13, P26j, P55 review, #63) on the Caches row, which stays as accepted:
- **The key.** `bash scripts/build-native.sh --print-cache-key` prints the CI cache key alone on
  stdout and exits 0 before the fetch and the build (after the toolchain checks). Its fields:
  the platform, the arch, the target, the compiler with its version (`gcc` or `clang` plus the
  version on Linux, `ndk` plus the NDK revision on Android), `optimize` when set (`-speed`), the
  godot-cpp SHA and the SCons version, as
  `native-<platform>-<arch>-<target>-<compiler><version>[-speed]-godotcpp-<sha>-scons<version>`.
  `ci.yml` reads it in a step of its own and passes it to `actions/cache` for `native/godot-cpp`
  and `SCONS_CACHE`.
- **No source hash.** No hash of `native/**` joins the key: the SCons cache is content-addressed,
  so a changed source misses on its own objects and the rest still hit.
- **`native-clang`** builds `template_debug` (the script's default target) with clang and
  `optimize=speed` (`--compiler clang --optimize speed`), under its own key.

Status note (2026-10-14, P26s docs, P57 as merged, #96) on the Caches row and the P26j note above,
which stay as written: the key gains the sanitizer part. `--print-cache-key` now prints
`native-<platform>-<arch>-<target>-<compiler><version>[-speed][-sanitize-undefined]-godotcpp-<sha>-scons<version>`,
so the sanitizer job's UBSan build (`--sanitize undefined`) caches `native/godot-cpp` and
`SCONS_CACHE` under its own key. In the SCons build its objects also get a `.ubsan` suffix, and
the library's build info gives `ubsan-O1` where a plain build gives its optimisation (§10's
status note of P26s docs).

Status notes (2026-10-13, P26k, from the real runs of P55a, #67, and P55a2, #68) on the Android,
Android page size and Targets rows, which stay as accepted:
- **Android.** NDK r29's clang 21 compiles the kernel sources under the `SConstruct` warning set
  (with `-Werror`) with zero warnings, for `template_debug` and `template_release` (P55a). Every
  undefined libc++ symbol of our library (14 of them) is defined by the template's
  `libc++_shared.so` (P55a2's `check-android-elf.sh`).
- **Android page size.** NDK r29's LLD already defaults max-page-size to 16 KB on arm64, but not
  common-page-size, and LLD ends `PT_GNU_RELRO` on the common page size. `-z common-page-size=16384`
  is the flag that ends it on a 16 KB boundary, so P55a2 added `-Wl,-z,common-page-size=16384`
  next to `-Wl,-z,max-page-size=16384` in `native/sim_kernels/SConstruct`. A real build without
  it ends RELRO at 0x6d000 and fails the RELRO check; with it RELRO ends at 0x70000 (debug) and
  0x6c000 (release), and all three `PT_LOAD` segments have `p_align` at least 0x4000.
- **Targets: the second cold NDK build's time** (the row's "P55a measures it"). Measured by P55a
  on a 4-CPU VM with an empty SCons cache: the NDK install through sdkmanager 161.7 s, the host
  library 14.3 s, Android `template_debug` 13.4 s and `template_release` 13.1 s. The CI
  android-debug-apk job of P55a's PR (run 38417308180) took 92 s in total, with the runner image
  already holding NDK 29.0.14206865 (`install-ndk.sh`'s installed path, no sdkmanager call) and
  Godot signing with build-tools 36.0.0. Cold on the runner, from the step times of the same run
  (its first CI run; both Android keys were new, and their cache steps have no restore keys):
  Android `template_debug` 28 s and `template_release` 18 s. Its host step (10 s) is not a cold
  time, because the host key was not new in that PR. This answers the row's open item.

Status note (2026-10-13, P26k) on "Sessions", which stays as accepted: Michael answered in chat
on 2026-10-13, verbatim, **"ja til install-android"** and **"ja til SDK-licens"**.
- **"ja til install-android"**: the plan's row P55b (release-engineer, lane B right after P55a2)
  adds `scripts/cloud/install-android.sh`, an on-demand installer of JDK 17, the Android SDK
  pieces and the pinned NDK (through `scripts/ci/install-ndk.sh`), so a cloud session can build
  and export Android. It is never part of `setup.sh`, the session-start hook or CI, so the
  session tools above are unchanged.
- **"ja til SDK-licens"**: AppCode ApS accepts the Android SDK License Agreement. The script
  accepts the SDK licences only with an explicit flag, used only when a session needs Android;
  `install-ndk.sh` itself still never accepts a licence.
- P55b is in flight; this note records the two answers, not its code. How this meets ADR 0005 §7
  ("Cloud sessions do not build APKs"), which "It keeps" above repeats, is open for the lead
  (the plan's P26k section).

Status note (2026-10-13, P26l docs, P55b as merged, #69), on "Sessions" and the note above:
- P55b adds `scripts/cloud/install-android.sh [--accept-android-sdk-licenses]`, never part of
  `setup.sh`, the session-start hook or CI, with its offline test
  `scripts/ci/test-install-android.sh` (a verify-job step).
- The sdkmanager of cmdline-tools 23.0 records the licence acceptance by itself on any install,
  without asking. So the script's gate, before any sdkmanager call, is the only licence control
  (without the flag a missing SDK piece is exit 5), and `install-ndk.sh` gains `--check` for it.
  `install-ndk.sh` accepts no licence itself, but the sdkmanager it calls records one, as its
  header now says.
- The Android CLI that the sdkmanager shim runs is pinned by version and SHA-256 and passed in
  through `ANDROID_CLI_BIN`.
- The export runs with `XDG_CONFIG_HOME=<sdk>/.godot-config`, because Godot copies `JAVA_HOME`
  and `ANDROID_HOME` only into a new settings file; that folder is one to delete if `JAVA_HOME`
  or `ANDROID_HOME` change.
- The real run, with the flag on Michael's consent: install exit 0 in 77 s, `export-android: OK`,
  and a rerun in 0 s that downloads nothing. `CLAUDE.md`'s `build-native.sh` line now names the
  installer (§14's status note).

### 9. The fresh-import crash, and a checkout without the library
- **Root cause** (Godot 4.7.2 source; evidence comment on PR #41, section 3): the bug is in the
  editor's documentation code (EditorHelp). gdb on the official, stripped binary shows a
  `SIGSEGV` on the main thread after the editor layout has loaded, a read at address `0x28`
  through a null object pointer; the frames are unnamed, so the steps below come from the
  source.
  1. On a fresh `.godot` the first scan discovers the extension at runtime and emits
     `extensions_reloaded`.
  2. `EditorNode` then starts a late doc-generation thread.
  3. `--import` quits right after the scan. `~EditorNode` runs `cleanup_doc()`, which sets `doc`
     to null.
  4. `Main::cleanup` flushes the deferred `_gen_extensions_docs`, which dereferences that null
     pointer.
  5. It faults only when ClassDB holds at least one extension class.
  6. Godot's crash handler aborts without printing a backtrace, so the log just ends with exit 134.
- **Upstream status:**
  - known bugs, as the first research run found them: godotengine/godot #111048 and #111645,
    with fix PR #123658 open and unreviewed (milestone 4.x). This session could not reach the
    godotengine repository's issues, so the status is not re-checked;
  - checked for the record: `_gen_extensions_docs` still starts with an unguarded
    `doc->generate(...)` in `editor/doc/editor_help.cpp` on `master` and on the `4.7` branch
    (fetched 2026-10-12), so neither has a fix.
- **Scope:** headless editor sessions that quit after the first scan (`--import`,
  `--editor --quit`, `--export-*` on a fresh `.godot`). Export templates, the phone, the web build
  and the interactive editor are not affected.
- **Measured** (evidence comment on PR #41, section 3; 4-core x86_64 VM, official editor binary).
  The **minimal repro** is a project whose only extension registers one class with no methods
  (`EvBare`), imported with `godot --headless --path <project> --import` after `rm -rf .godot`:

  | Case | Crashes (exit 134) |
  | --- | --- |
  | The minimal repro, fresh `--import` | 20 of 20 |
  | The minimal repro, fresh `--editor --quit` | 10 of 10 |
  | The minimal repro with a seeded `extension_list.cfg` | 0 of 20 |
  | The minimal repro, warm `.godot` | 0 of 10 |
  | A library that registers no class, fresh `--import` | 0 of 10 |
  | No extension, fresh `--import` | 0 of 10 |

  The first research run (deleted) reported 70 of 90 across mixed unseeded cases, 0 of 80
  seeded (one-core and no-doc-cache runs included) and 9 of 10 for the bare class. The spike's
  `native/README.md` reports 4 of 6 unseeded runs aborting, 6 of 6 for a bare registered class
  with no method, 0 of 6 seeded, and that a warm `.godot/` "never" aborts (no count given).
- **Decision: seed the extension list before every headless editor start.**
  - `scripts/seed-extension-list.sh` (release-engineer, P53) writes `.godot/extension_list.cfg`.
    It lists every `*.gdextension` that the first scan would see and skips folders that hold a
    `.gdignore`, so `native/godot-cpp/test/project/example.gdextension` stays out. It is
    idempotent and has an offline test.
  - It runs first in every headless editor start: the imports in `verify.sh` and
    `run-tests.sh`, `export-web.sh` and `export-android.sh`, and `run-sim-smoke.sh` once Phase 4
    makes it start Godot (in Phase 2 it is a stub that starts none).
  - Running it only from `build-native.sh` is not enough: `rm -rf .godot` with `native/bin`
    present skips the build, and the next import crashes.
  - CI keeps a fresh-clone build, seed and import at exit 0, with no retry, as the canary.
- **Rejected workarounds:**
  - a retry or `|| true`: it hides real import failures;
  - `--frame-delay`: it depends on timing;
  - `--editor --quit`: 10 of 10 runs of the minimal repro crash;
  - a minimal `register_types`: any registered class triggers the crash (the minimal repro has
    one class with no methods);
  - relying on a missing doc cache: the fresh imports above have none, and they crash.
- **Fallback** if the list file's format changes: `--recovery-mode --import`, then `--import`.
  The first research run reported 0 of 10 on both passes, at about +5 s per job (not re-run);
  P53 measures it before relying on it.

  Status note (2026-10-13, P26i, P53 review): P53 measured it at 0 of 10 failures, costing about
  6-7 s per job. It is not used: the seed holds.
- **Exit:** the seed goes only in a future Godot-bump ADR, after the minimal repro above, run 10
  times unseeded with fresh `--import`, crashes in 0 of 10 on the new version. Its baseline on
  4.7.2 is 20 of 20.
- **Not covered:** godotengine/godot #123712, a separate shutdown crash on 4.7.2 after an export
  with AdMob and gdUnit4 installed. The release-engineer watches for it when the AdMob plugin
  arrives.
- **A checkout without the library.**
  - `build-native.sh` generates `native/sim_kernels.gdextension` (and git-ignores it and its
    `.uid`) instead of committing it.
  - A checkout without a build is then a plain GDScript project: no `Can't open dynamic library`
    error, no import crash, `AUTO` resolves to GDScript, and the web preview job needs no C++
    build.
  - Not proven yet: P53 must show a fresh clone importing cleanly 6 of 6 times without a build,
    and 6 of 6 times with a build and the seed.
  - If that fails, the fallback is the spike's way: commit the `.gdextension` and build in every
    job that starts Godot, preview included.

    Status note (2026-10-13, P26i, P53 review): proven, so the fallback is not taken. With `rm -rf
    .godot` before each fresh `godot --headless --import` and no retry, P53 measured 6 of 6 clean
    imports (exit 0, no error line) without a build and 6 of 6 with a build and the seed; the
    control, a build with no seed, aborted 2 of 6 times (exit 134).
  - **`bash scripts/run-tests.sh` on such a checkout** does not build (it stays the gdUnit4-only
    command CLAUDE.md lists, with its flags unchanged). Before Godot starts, it checks for the
    generated `native/sim_kernels.gdextension` and the host library it names; if either is
    missing it prints `NATIVE LIBRARY MISSING: run bash scripts/build-native.sh first` and exits
    3, the code it already uses for a missing Godot or gdUnit4. It never skips the native suites
    or the native pass of the twin suites. `verify.sh` builds first, so it never hits this. P53
    adds the check with an offline test (named exception 6 of the plan).

### 10. CI and export changes
- **`verify.sh`**, in this order:
  1. build the Linux `template_debug` library;
  2. seed the extension list;
  3. import;
  4. run the tests, where the native suites must run and never skip;
  5. check the `clang-format` version, then the C++ format (§12).

  `scripts/ci/check-native-tests.sh` is not a `verify.sh` step: it is a `ci.yml` step that runs
  after `verify.sh` in the verify job and reads its `results.xml` (P55, release-engineer's
  file), as in the spike. Only P53 edits qa's `verify.sh` (the plan's exception 6), and the
  script arrives in P55.
- **`check-native-tests.sh` discovers its suites; it holds no list** (P55). The spike's version
  named its suites and cases in a hard-coded list, which every later suite would have to edit in
  release-engineer's file, and which before the first suite would be either empty (a vacuous
  proof) or name files that do not exist (a red check). Instead:
  - the required suites are every `tests/sim/native/**/test_*.gd` file in the checkout, except
    `tests/sim/native/sanitizer/**` (the dump step, which only the sanitizer job runs). Each must
    appear exactly once in `results.xml` under its file's base name (the suite name gdUnit4
    writes, as in the spike), with at least one case, and no suite or case may report a failure,
    an error or a skip;
  - **the floor:** once `native/sim_kernels/src/bind/kernel_list.h` exists (P54 adds it in the
    same PR as the first suite, `test_kernel_abi.gd`), zero discovered suites fails. Before P54
    the script passes with zero suites and prints `check-native-tests: no native suites yet (before
    P54)`, so P55 is green on its own and nothing is required that does not exist;
  - `--require <suite>` adds a suite outside `tests/sim/native` (the golden hashes in the
    `native-clang` job, below); P55 builds and tests the option;
  - P55's offline tests feed fixture `results.xml` files and fixture trees: a discovered suite
    missing, one with zero cases, a skipped case, a failed suite, zero suites with and without
    `kernel_list.h`, and a `--require` suite missing;
  - so no later PR edits the script: a port PR's suite is required because its file exists.
    Deleting a suite file shows in the PR's diff, and the module tests under both implementations
    keep `sim_impls.gd`'s non-vacuity assert.

  Status note (2026-10-13, P26j, P55 review, #63): as merged, `check-native-tests.sh` matches a
  discovered suite by its base name plus its gdUnit4 package (the suite's folder, such as
  `tests/sim/native`), so a suite elsewhere with the same base name is not counted for it; a
  `--require` suite is matched by name alone. It fails when two discovered files share a base
  name. `--list` prints the discovered suite files and exits 0 without reading `results.xml`
  (`native-clang` uses it to decide whether its gdUnit4 step runs). It reads one `results.xml`
  (`reports/gdunit/report_1/results.xml` by default), and `run-tests.sh` deletes `reports/gdunit`
  on each call, so a `--require` suite must run in the same `run-tests.sh` call as the native
  suites. Its exit codes: 0 ok; 1 a suite is missing, empty or not passed, the floor failed, or two
  discovered files share a base name; 2 a bad argument; 3 Python (`python3`, or `PYTHON`) is
  missing; 4 `results.xml` is missing, empty or not XML.
- **`ci.yml`, verify job:** P53 installs SCons (pipx), the pinned `clang-format` and binutils,
  so P53's own verify job is green; P55 adds the caches (§8) and `check-native-tests.sh`.
- **`ci.yml`, `native-clang` job** (P55): an x86_64 library built with clang at the release
  optimisation (`use_llvm=yes`, `optimize=speed`, the release flags apart from `DEBUG_ENABLED`),
  running the `tests/sim/native` suites, checked by `check-native-tests.sh`. Its gdUnit4 step
  runs only when discovery finds a suite: `run-tests.sh -a res://tests/sim/native` exits 1 when
  no test ran, so before P54 the job skips that step and runs only the check, which prints its
  "no native suites yet" line. So P55 is green on its own. **P51**
  (release-engineer, which already edits `ci.yml` and depends on P49a) adds the
  `test_golden_hashes` step to this job and passes `--require test_golden_hashes` to the check;
  P49a (qa-engineer) does not edit `ci.yml`. Every other CI determinism run uses g++ `-O2`, and
  the shipped build is NDK clang `-O3`.
- **`ci.yml`, Android job:**
  - install the NDK and build `template_debug` and `template_release` arm64 (§8);
  - `export-android.sh` checks that the APK holds the library of its export mode (`--export-debug`
    packs `android.debug.arm64`) with the bytes CI built, and holds `libc++_shared.so`;
  - ELF checks on our library: machine, type, `NEEDED` only system libraries or
    `libc++_shared.so`, the entry symbol, every `PT_LOAD` `p_align` at least `0x4000`, and
    Google's RELRO end check (`(VirtAddr + MemSiz) % 0x4000 == 0`), plus the libc++ symbol check
    of §8;
  - it then writes the notices (§11).
  - Phase 6's Gradle/AAB switch (ADR 0005) re-checks alignment with `zipalign -c -P 16` and
    bundletool. Optionally, one run on a 16 KB device or emulator image.

  Status note (2026-10-13, P26k, as P55a, #67, and P55a2, #68, merged them; the text above stays
  as accepted): the job installs the NDK with `scripts/ci/install-ndk.sh`, builds the host's
  Linux library first and then Android arm64 `template_debug` and `template_release`. The APK
  packs the library as `lib/arm64-v8a/<basename of the .gdextension entry>`
  (`libsim_kernels.android.template_debug.arm64.so` in the debug APK); `export-android.sh`
  compares those bytes with the built file, checks that `libc++_shared.so` is packed, runs
  `scripts/ci/check-android-elf.sh check` on the packed copy (it reports every failing check,
  then exits 1) and logs the template's two libraries with `describe` (Context's status note).
  Both notices end with the godot-cpp section from `scripts/ci/godot-cpp-notice.sh`; P55a2's real
  run measured them at 121,039 B (Android) and 121,029 B (web), identical apart from the header
  line. The offline tests `scripts/ci/test-android-elf.sh` and `scripts/ci/test-export-notices.sh`
  run in this job, not in `verify.sh` (an open item in the plan's P26k section). The real export
  took 18.4 s with a throwaway debug keystore, and apksigner's v2/v3 verify passed.
- **Sanitizer job** (P57). It runs on PRs that touch `native/**`, `game/sim/**`, `data/**` or
  `tests/sim/native/**`, because a World column, rule or twin change can break a kernel without
  touching `native/`:
  - **UBSan in the engine (mandatory):** a UBSan-instrumented library (shared libubsan, no
    `-fwrapv`, `-O1`, `-fno-sanitize-recover=all`), loaded by headless Godot to run the real
    `tests/sim/native` lockstep suites. That plays real tick sequences, with the GDScript phases
    in between, which a standalone harness cannot;
  - **ASan:** a standalone harness over `core/` (no Godot header, so no engine and no
    `LD_PRELOAD`). Its states are dumped in the same job by a GDScript step that runs the seed-42
    arena and writes a binary dump every 15 ticks, versioned with `World.STATE_FORMAT`, plus the
    crafted cases. Nothing is committed, so the states are never stale. The harness
    (`native/sim_kernels/sanitizer/**`) is C++ and CI-only, so it is the one test that is neither
    gdUnit4 nor under `tests/`; it stays next to `core/` because it compiles `core/` without
    Godot. CLAUDE.md's Tests line names it (§14);
  - loading an ASan library into Godot (`LD_PRELOAD`) stays optional; P57 decides.

  Status note (2026-10-13, P26l docs, P54 review, #70), the text above stays as accepted: the
  job cannot see the use-after-free class P54 fixed (an `Object*` taken from a Variant that
  died on return), because the freed memory is read inside engine code, which neither the UBSan
  library nor the ASan harness over `core/` instruments. Valgrind with a fresh-copy probe found
  it. The plan's row P57 records this; no decision on the job here.

  Status note (2026-10-14, P26s docs, P57 as merged, #96), the text above stays as accepted:
  - **`LD_PRELOAD` not taken.** No ASan library is loaded into Godot; ASan runs only in the
    standalone harness over `core/`.
  - **Two jobs, not a required check** (`verify` stays the only one). `sanitizer-changes` runs
    on pull requests only and diffs the merge commit against its first parent with
    `--no-renames --name-only` (a file moved out of a folder counts; a diff that cannot be read
    counts as relevant) against `PATTERN: '^(native/|game/sim/|data/|tests/sim/native/)'`.
    `sanitizers` needs it and runs only when it matched, so it ends skipped otherwise, and a
    push to `main` or a manual run skips both. Its steps: build the UBSan library,
    `run-tests.sh -a res://tests/sim/native` on it, `check-native-tests.sh`,
    `sysctl -w vm.mmap_rnd_bits=28` (g++ 13's ASan cannot place its shadow under the runner's 32
    bits), then `scripts/ci/run-sanitizer-harness.sh`.
  - **The UBSan library** is `build-native.sh --sanitize undefined` (SConstruct
    `sanitize=undefined`): g++ on Linux only (the script refuses clang, "clang links no UBSan
    runtime into a shared library", and any other platform), our sources at `-O1` with
    `-fsanitize=undefined`, `-fno-sanitize-recover=all` and no `-fwrapv`, linked to the shared
    libubsan; it refuses `--optimize`. The library keeps the standard name, so it replaces a
    plain build of the same platform, target and arch. The ELF check requires libubsan in
    `NEEDED`, `__ubsan_handle_` calls, a fatal signed-overflow handler (no `-fwrapv`), no handler
    that returns after a report (`-fno-sanitize-recover=all`) and `-O1` read back from the
    compile line that `-frecord-gcc-switches` keeps in the library.
  - **The dump step** is `tests/sim/native/sanitizer/dump_states.gd`, a plain
    `extends SceneTree` script run with `godot --headless --path . -s
    res://tests/sim/native/sanitizer/dump_states.gd -- <out dir>`, not a gdUnit4 suite, so
    neither `verify.sh`'s run nor `native-clang`'s picks it up (verify's `results.xml` held 71
    suites, none from it; `run-tests.sh -a res://tests/sim/native` runs 2). Until P37b steps
    FLOW in `Sim.step`, it drives the flow cache itself with the stand-in of
    `test_flow_lockstep.gd`.
  - **The harness** (`native/sim_kernels/sanitizer/`) is built by the runner with g++
    `-fsanitize=address,undefined`, `-fno-sanitize-recover=all` and no `-fwrapv`. It refuses a
    `World.STATE_FORMAT` it does not know (exit 2), and the runner fails unless the harness took
    every dump the step wrote. It takes 1024 x 1024 as the largest map, because no bound on the
    map size is written down (the GDD plans 56 to 64 tiles).
  - **Blind spots**, written down in `main.cpp` and `ci.yml`: `ArrayView` clamps an index
    outside its window (reads 0, writes nothing), so a single index bug in `core/` is a wrong
    answer that only the lockstep suites see, never an ASan report (the corrupted-queue crafted
    case shows the clamp itself failing); engine-side use-after-free as in the note above; and no
    sanitizer here sees a read of memory never written (MemorySanitizer needs clang).
  - **Path filter** (lead decision, 2026-10-14, the plan's row P57b): the files that drive the
    job are outside the four folders (`scripts/build-native.sh`,
    `scripts/ci/run-sanitizer-harness.sh`, `.github/workflows/ci.yml`, `tests/sim/support/**`),
    so a pull request that changes only those skips it. P57b widens the filter to them and
    removes the dump step's FLOW stand-in once P37b has merged.

  Status note (2026-10-19, P26x docs, P57b as merged, #104), the text above and the P26s note
  stay as written:
  - **The path filter as merged** (`.github/workflows/ci.yml`, pinned by
    `tests/project/test_ci_workflow.gd`):
    `PATTERN: '^(native/|game/sim/|data/|tests/sim/native/|tests/sim/support/|scripts/build-native\.sh$|scripts/ci/run-sanitizer-harness\.sh$|\.github/workflows/ci\.yml$)'`.
    The other scripts the job runs stay out of `PATTERN`, because the required verify job runs
    them on every pull request, as `ci.yml`'s comment on the job says: `install-godot.sh` (with
    `remote_zip.py`), `run-tests.sh`, `check-native-tests.sh` and `seed-extension-list.sh`.
  - **The dump step plays real orders.** `tests/sim/native/sanitizer/dump_states.gd` plays the
    seed-42 arena through `MatchLoop` with the arena's own orders and, from tick 120 every 30
    ticks (`WAVE_FIRST`, `WAVE_EVERY`), a wave of `MOVE` orders that sends about one in five
    (`WAVE_SHARE`) of one player's units across the arena's rock wall; three `World.set_terrain`
    repaints (`REPAINT_TICKS` 206, 446 and 701, each three ticks before a dump) re-integrate the
    fields in use. `Sim.step` steps FLOW itself (P37b), so the step calls no `FlowCache`: the
    FLOW stand-in is gone. The run fails if no dump caught a waiting, a half-integrated, a served
    and a re-integrating field. Since P37n (#108) it also writes the INTEGRATE kernel's records
    (`_write_integrate`).
  - So the P26s note's "Until P37b steps FLOW in `Sim.step`, it drives the flow cache itself
    with the stand-in of `test_flow_lockstep.gd`" and "P57b widens the filter to them and
    removes the dump step's FLOW stand-in once P37b has merged" are done.
- **Preview (`preview.yml`):** unchanged with the generated `.gdextension`. With the fallback,
  the preview job builds the Linux library and seeds first, as the spike did. `export-web.sh`
  changes (§7).
- **`install-godot.sh`:** unchanged. The dlink templates come only with option B.

  Status note (2026-10-21, P26af docs, after P51b, #149, and P51r, #153; the line above stays as
  accepted): `scripts/ci/install-godot.sh` did change, twice, and neither change adds dlink
  templates. P51b: it picks the editor from `uname` (the Linux arm64 build on an arm64 Linux
  machine, the Linux x86_64 build everywhere else), each pinned by SHA-512
  (`EDITOR_SHA512_X86_64`, `EDITOR_SHA512_ARM64`, the lines of the official godot-builds
  4.7.2-stable `SHA512-SUMS.txt`); `scripts/ci/test-native-scripts.sh` repeats both SHAs as
  literals and checks the pick per architecture against a stub `curl`. P51r: `--android-release`
  also fetches `templates/android_release.apk` under a SHA-256 pin (`ANDROID_RELEASE_SUM`), the
  template of the perf APK. The arm64 item of the bullet below as merged: the job
  `determinism-arm64` on `ubuntu-24.04-arm` (not required, no job needs it) builds the library
  with `build-native.sh --arch arm64 --compiler clang --optimize speed` and runs
  `tests/sim/native`, `test_determinism.gd`, `test_world_hash.gd` and
  `tests/perf/test_golden_hashes.gd` in one `run-tests.sh` call (plan section P51b "As merged").
- **Determinism suites:** golden hashes under both implementations on x86_64 with g++ (P49a),
  on x86_64 with clang `-O3` (`native-clang`), and on arm64 Linux with clang `-O3` (P51b, which
  builds a Linux arm64 library).

### 11. Licences
- **godot-cpp is MIT.** Its licence is committed unchanged in
  `docs/licenses/godot-cpp-4.5-stable/LICENSE.md`. `export-android.sh` appends it to the
  `THIRD_PARTY_LICENSES.txt` it writes next to the APK, reading the tag and SHA from
  `build-native.sh` (the one owner of the pin), and an offline test checks this (the spike's
  `test-export-android-pins.sh`). `export-web.sh` appends the same text, so the two notices
  stay identical, as ADR 0005 §5 requires ("the same content as the web build's"). The web build
  packs no C++; naming a component it does not contain over-attributes, which is harmless,
  whereas two diverging notices would need ADR 0005 §5 superseded. Both appends land in P55a. Our
  C++ is MIT like the rest of the repository.
- **`libc++_shared.so`** (LLVM libc++, Apache-2.0 WITH LLVM-exception) is already in every APK,
  because Godot's Android template ships it. `docs/licenses/godot-4.7.2/COPYRIGHT.txt` does not
  mention libc++ (checked: no match for "libc++" or "LLVM"). So this gap exists today, with or
  without our C++, and its fix does not wait for this ADR: the plan's P26l (release-engineer, in
  any outcome) commits the upstream LLVM licence text and appends it to both notice files, the
  APK's and the web build's, so ADR 0005 §5 ("the same content as the web build's") stays true
  and P26l needs no ADR. This is a conservative choice, not a legal opinion.
- **The in-game licences screen (Phase 5).** A store install contains only the APK or AAB, not the
  file next to it. ROADMAP Phase 5's licences screen shows `Engine.get_license_text()`,
  `get_copyright_info()` and `get_license_info()`, which cover Godot only. It must also show the
  LLVM libc++ text (every Android build) and godot-cpp's MIT text (builds that contain the
  library), for example from a `res://` text file that only the Android preset packs. The lead
  adds this to the ROADMAP line: libc++ in this ADR's docs PR (P26b), which merges in any outcome
  because it carries the plan's "Recorded now" block, and godot-cpp in P26e.
- **Legal:**
  - the CLAUDE.md legal rules apply to C++ unchanged. In particular, no code from EA's C&C
    release or from OpenRA;
  - godot-cpp's example and test code is not copied into `native/sim_kernels`.

### 12. C++ code style and review
- **Format:** `native/sim_kernels/.clang-format` in Godot's style (tabs, as godot-cpp and the
  spike). The `clang-format` version is pinned in P53 (the PyPI wheel; which version is still
  open), and `verify.sh` checks it (§8). `verify.sh` fails on a diff (`--dry-run --Werror`).
- **Warnings:** `-Wall -Wextra -Wshadow -Wconversion -Wsign-compare -Werror`, for our sources
  only. Two build rules make that hold:
  - godot-cpp's include directories reach our sources through `CPPEXTPATH`, which godot-cpp
    already emits as `-isystem`. Through plain `-I` the pinned headers give 100 errors with
    g++ 13.3 and 20 with clang++ under these flags (`-Wunused-parameter` in `wrapped.hpp`,
    `-Wconversion` in `vector4i.hpp`, `-Wsign-conversion` in `cowdata.hpp`), and none with
    `-isystem` (first research run; the counts are not re-run, P53 re-counts them);
  - `-fwrapv` and the warning set go on an `env.Clone()` used only for `native/sim_kernels`.
    Appending them to the `env` that godot-cpp's SConstruct returns would also reach godot-cpp's
    own sources, because SCons expands flags when a target is built.

  P53 checks the build log: godot-cpp's compile lines carry neither `-Werror` nor `-fwrapv`, and
  ours carry both. `-Wconversion` forces the explicit cast at every int32 store (§4).

  Status notes (2026-10-13, P26i, P53 review), the text above stays as accepted:
  - **How the headers become `-isystem`.** The cause in the text above is wrong. At the pinned
    commit godot-cpp declares `CPPEXTPATH` as an empty list that nothing appends to
    (`tools/godotcpp.py:455`) and keeps its include directories in `CPPPATH`
    (`tools/godotcpp.py:566-571`), so they arrive as plain `-I`; and SCons 4.9.1 would not
    expand `CPPEXTPATH` even if it were filled (no occurrence of `CPPEXTPATH` or `EXTINCPREFIX` in
    its package). So `native/sim_kernels/SConstruct` adds each of godot-cpp's include directories
    as an `-isystem` flag to `CCFLAGS` on the `env.Clone()`, and keeps them in `CPPPATH` so that
    SCons still scans their headers (a compiler drops an `-I` directory that is also an
    `-isystem` one). The SConstruct's comment at `ebb3b91` repeats "godot-cpp fills
    CPPEXTPATH"; the next PR that edits `SConstruct` corrects that comment. The outcome this section wants holds: 0 warnings with `-Werror` on
    g++ 13.3.0 and clang++ 18.1.3. P53's build log showed godot-cpp's 61 compile lines without
    `-Werror` and `-fwrapv` and our 2 with both.
  - **The warning set gains `-Wsign-conversion`**, which is in clang's `-Wconversion` and not in
    g++'s, so g++ (`verify.sh`) is as strict as the clang jobs.
  - **The counts with plain `-I`**, re-counted for our two translation units under the warning set:
    g++ 13.3.0 gives 200 warning lines (83 distinct), clang++ 18.1.3 333 (178 distinct). The 100
    and 20 above were the first research run's.
  - **Format:** the pinned version is `clang-format` 20.1.8 (§8's status note).
- **Not in Phase 2:** clang-tidy and coverage tooling.
- **Each kernel file** names its GDScript twin and its lockstep test in a header comment.
- **The `godot-code-review` skill gains a C++ checklist** (at acceptance: in `rts-sim-conventions`
  instead; see "Acceptance note"):
  - signatures, and the type and size check on every fetched array;
  - pointer lifetime;
  - integer widths;
  - undefined behaviour;
  - order;
  - allocation;
  - a line-by-line mirror of the twin.
- **The lead reviews every C++ PR** and runs mutants and a 20,000-tick lockstep, as in the spike
  review.

### 13. Who writes C++
- **gameplay-dev writes both versions of a rule:** one owner per rule, so both come from the same
  understanding of it. It gains `native/sim_kernels/src/**` and `tests/sim/native/**` (except
  the sanitizer dump step, below).
- **release-engineer** owns:
  - `scripts/build-native.sh` and `scripts/seed-extension-list.sh`;
  - `native/sim_kernels/SConstruct`, `build_profile.json`, `.gdignore` and `.clang-format`;
  - `scripts/ci/install-ndk.sh` and `scripts/ci/check-native-tests.sh` (qa-engineer reviews its
    discovery rule and floor in P55, §10; it holds no list, so no later PR edits it);
  - `scripts/cloud/setup.sh`, `scripts/hooks/session-start.sh` and the native lines of
    `.gitignore`;
  - `docs/licenses/godot-cpp-4.5-stable/` and `docs/licenses/llvm-libc++/`, and the build and
    licence lines of `README.md` (§14);
  - the CI jobs and the export scripts.
- **P53's skeleton** (`register_types`, an empty `SimKernels` with `abi_version()`, `phases()` and
  `build_info()`) is a named exception: release-engineer writes it, gameplay-dev reviews it, and
  gameplay-dev owns it from P54 on.
- **qa-engineer** owns the C++ purity scan, the sanitizer harness (`native/sim_kernels/sanitizer/**`)
  and its dump step (`tests/sim/native/sanitizer/**`).
- **The lead** owns `game/core/NativeKernels.gd`, `MatchRunner.sim_impl` and the C++ review.
- **No new native-dev agent:** it would split every rule across two owners.
- **Risk:** gameplay-dev runs on Sonnet, so the risk of undefined behaviour is higher. The
  mitigations are the sanitizer job, mutants, the lead's review and `-fwrapv`.
- **Agent files** (`gameplay-dev.md`, `release-engineer.md`, `qa-engineer.md`) change only with
  Michael's approval (question 4). A yes to this ADR does not cover them. A yes to this ADR with
  a no to question 4 leaves P53 and every later C++ PR blocked, because no agent may then write
  `native/sim_kernels/src/` (gameplay-dev.md: "Stay inside `game/sim/`, `data/` and
  `tests/sim/`"; release-engineer.md: "Never changes game code").

### 14. Docs on acceptance (lead, PR P26e)
- **CLAUDE.md, Stack line**, new text:

  > Godot **4.7.x** (pinned: 4.7.2), GDScript 2.0 with **static typing everywhere**. C++17 only
  > for the sim's hot-phase kernels in `native/sim_kernels/` (GDExtension, godot-cpp pinned, ADR
  > 0013), each with a GDScript twin in `game/sim/` that stays the reference and the web path.
  > No C#.
- **CLAUDE.md, Layout:** a new line `native/      C++ sim kernels (GDExtension) and their build;
  godot-cpp is fetched, not committed`.
- **CLAUDE.md, Commands:** a new line `bash scripts/build-native.sh - builds the C++ kernels
  (scons 4.9.1, g++, binutils; the NDK for Android, CI only). verify.sh runs it first and checks
  the C++ format with the pinned clang-format.`

  Status note (2026-10-13, P26l docs), the text above stays as accepted: after P55b (#69),
  Michael approved in chat on 2026-10-13, verbatim, **"ok til CLAUDE.md-linjen"**, so the line
  now ends "(scons 4.9.1, g++, binutils; the NDK for Android: CI, or a cloud session after
  `bash scripts/cloud/install-android.sh`)". Nothing else in `CLAUDE.md` changed.
- **CLAUDE.md, Stack, the Format/lint line** gains: "C++: `clang-format` <pinned version>
  (`native/sim_kernels/.clang-format`)." P26e comes before P53, which chooses the version, so
  P26e writes "the version `verify.sh` pins (P53)" in its place. After P53 merges, the lead puts
  the number in with a one-line CLAUDE.md follow-up; P53 does not edit CLAUDE.md.
- **CLAUDE.md, Stack, the Tests line** ("gdUnit4 in `tests/`") gains: "plus a CI-only C++
  sanitizer harness in `native/sim_kernels/sanitizer/` (ADR 0013 §10)."
- **`README.md`** changes in P53 (release-engineer), not in P26e, because P53 is the PR that
  makes `verify.sh` need the tools:
  - "Build and test" gains SCons 4.9.1, g++, binutils and the pinned `clang-format` next to
    Godot 4.7.2, the line `bash scripts/build-native.sh` (which `verify.sh` runs first), and that
    godot-cpp is fetched by that script, not committed (the NDK only in CI);
  - "Licence" gains a line next to the Godot paragraph: godot-cpp (MIT, in
    `docs/licenses/godot-cpp-4.5-stable/`), shipped in both notices (APK and web) from P55a.
    P26l adds the LLVM libc++ line (Apache-2.0 WITH LLVM-exception,
    `docs/licenses/llvm-libc++/`) in any outcome.
- **CLAUDE.md, Architecture rule 1** gains: "`native/sim_kernels/` follows the same rules, and
  rules 2, 3 and 5 apply to it: kernels read every rule value from the World, never from a C++
  literal (ADR 0013 §2, §4, §6)."
- **`rts-sim-conventions`** gets a "Native kernels" section: the scope (§1), `world_access.h` and
  the forbidden signatures (§2), the dispatch (§3), the determinism rules (§4), the twin rule
  (§5), and the threading rules (§6).
- **`godot-code-review`** gets the C++ checklist (§12). (At acceptance: in `rts-sim-conventions`
  instead; see "Acceptance note".)
- **Status lines**, replacing the one-line pointers the draft added:
  - ADR 0001 (Consequences);
  - ADR 0005 §1 (the Web preset alone excludes `native/*`; the Android preset must not). §5 is
    kept, not superseded: both notices gain godot-cpp in P55a, as both gained libc++ in P26l.
    §7 is kept: P53 changes `scripts/cloud/setup.sh` for SCons and `clang-format`, and cloud
    sessions still build no APK;
  - ADR 0007: §8 (`World.kernels` and `NON_STATE_MEMBERS` are the one exception to the helper
    `HASHED`/`UNHASHED` rule). §4's line (the one `rebuild_grids` line) is not in P26e: the
    lead adds it in a one-line docs PR when P41g's rule fires, which P26e cannot know;
  - ADR 0008 §3 ("`configure()` allocates every slot's arrays; nothing allocates after it");
  - ADR 0011 §6;
  - ADR 0012 §4 (the P46 decision point, and the `impl` verdict added to the verdict list), §5
    (the P27f value, and `FlowCache.run` in place of `FlowCache.advance`) and §7.
- **`docs/ROADMAP.md`**, Phase 5's licences screen: godot-cpp's MIT text on builds with the
  library (§11).
- **The plan** goes to the next plan revision at acceptance (15: P26d took revisions 12 and 13, and this PR, P26b, revision 14), folding in
  its "Amendment (ADR 0013/0014, proposed)" section.

The CLAUDE.md and skill changes and the session tool install (§8) are part of question 1; the
agent changes are question 4. They are made only after Michael's yes. An agent message is never
that approval.

### 15. What changes in ADR 0011 §6 and ADR 0012 §4, §5 and §7
- **ADR 0011 §6:**
  - step 5 (GDExtension) is adopted for the hot phases of §1, before steps 1 and 2 are exhausted,
    because the measurements show those steps cannot close the mock's own miss (42-44 % on the
    tick p95, 48-51 % on the gated job p95);
  - steps 1 and 2 stay the remedies for everything else (the main thread, the view and the
    GDScript-only phases);
  - step 3 (MultiMesh) is unchanged.
- **ADR 0012 §7** is replaced by two rules, judged on a release perf-arena card. Both read
  summary keys that P50a adds (`phases_ms` holds per-phase means over the run, ADR 0012 §5, so it
  cannot carry a p95). A checkpoint tick is a published tick with
  `tick % Replay.CHECKPOINT_PERIOD == 0`, the ticks `MatchLoop` hashes; the samples are the
  snapshot's `phase_usec`, `step_usec` and `job_usec`, one per published tick (ADR 0012 §3):
  - `phases_p95_noncp_ms`: an `Array` of `Phase.COUNT` floats, each phase's p95 over the
    non-checkpoint ticks, in id order like `phases_ms`;
  - `job_p95_noncp_ms`: the job p95 over the same ticks;
  - `job_minus_step_p95_cp_ms` and `job_minus_step_p95_noncp_ms`: the p95 of
    `job_usec - step_usec` over the checkpoint ticks and over the others.

  **Neither rule is a verdict.** The card prints the four keys without `PASS`/`FAIL`, and no
  `PerfGateDef` field holds 25 % or 3.3 ms (CLAUDE.md rule 5 covers values code compares
  against; no code compares these). The lead applies both rules in the review of each release
  perf-arena card and records the numbers there. The gate's sim verdicts stay `sim_p95_ms` and
  `job_p99_ms` (ADR 0012 §4).
  - **Port trigger (GDScript phases).** A GDScript-only phase (`COMMANDS`, `REMOVE`) whose entry
    in `phases_p95_noncp_ms` is above 25 % of `job_p95_noncp_ms` gives a port row in the plan
    under this ADR. Checkpoint ticks are 60 of every 900 (6.7 %, more than the 5 % a p95
    ignores), so a job p95 over all ticks would land on a hash tick and fire this trigger by
    construction.
  - **Engine-side watch line (capture and hash).** `MatchSnapshot.capture` (`duplicate()`) and
    `state_hash` (SHA-256 through `HashingContext`) already run in the engine's C++, so a port
    cannot speed them up. `job_minus_step_p95_cp_ms` and `job_minus_step_p95_noncp_ms` should
    each stay at or below 25 % of `sim_p95_ms` (3.3 ms). Above it, the remedies are fewer copied
    arrays (ADR 0012 §3), fewer hashed bytes or a longer `CHECKPOINT_PERIOD` (ADR 0007), each
    through its own ADR, never a port row.
  - Named watch items (both VM figures are from deleted scratch research, not re-run; P49a's
    report lines measure them): `Formation.assign` for 150 units, 3.15 ms on the VM, about
    14-19 ms on the gate phone by the 4.4-5.9 ratios (an estimate), on a large-order tick inside
    `COMMANDS`; the checkpoint hash, about 380 µs on the VM every 15th tick, perhaps 1.7-2.2 ms on
    the phone.
- **ADR 0012 §5:** the rule is unchanged.
  - With the C++ slice (0.21 ms per 512 cells on the phone) and the C++ job p95 (0.88 ms), both
    halves of the rule allow the 512 cap: the 2 ms rule allows far more than 512, and
    0.88 + 0.21 ms is far below 12.0 ms.
  - P27f is withdrawn, and P27b's 512 stays.
  - This holds once the §1 ports have merged (P49a's Depends cell names them all), before any
    gate judges it: the headroom half reads the worker job p95, and 0.88 ms is the all-C++ mock.
    With only FLOW ported, the GDScript phases would still miss it. Until then 512 runs on
    phases that are partly GDScript, which no gate judges.
- **ADR 0012 §4:** every threshold is unchanged. The verdict list gains one verdict, `impl` (§3),
  which fails the gate on its own like `build`. `PerfGateDef` gains two printed estimates that
  are not thresholds (P54r), derived with ADR 0012 §4's own formula, the release worker job
  over the CI mock tick, so both impl lines estimate the gated quantity (`job_usec`):
  - `ci_ratio_native_mean` 9.4 (job mean 0.44 / CI mock mean 0.047 = 9.36, rounded up to one
    decimal);
  - `ci_ratio_native_p95` 14.0 (job p95 0.88 / CI mock p95 0.063 = 13.97).

  The native job is mostly the GDScript-side capture and the hand-off, which scale like
  GDScript (about 4-6 from CI to phone), not like the kernels. Applied to a CI time that is
  mostly GDScript, 14.0 therefore overestimates, which errs on the safe side for an early
  warning. CI's library is `template_debug -O2` and the phone's is `template_release -O3`, so
  this is not an architecture ratio either. The first release perf-arena card re-derives both by
  ADR 0012's 10 % rule, on the same quantities.
- **ADR 0012 §1-§3:** unchanged.
- **The P46 decision point** ("start drafting the GDExtension ADR above 26.6 ms") is dropped.

Status note (2026-10-21, P26ae docs, after P50a, #142, and P49a, #143; the text above stays as
accepted): "summary keys that P50a adds" reads P50a2. P50a took its named split up front (the
lead's decision of P26ad docs), and as merged `PerfHud.summary()` holds `phases_ms` but none of
the four keys (`phases_p95_noncp_ms`, `job_p95_noncp_ms`, `job_minus_step_p95_cp_ms`,
`job_minus_step_p95_noncp_ms`); P50a2 adds them, with the checkpoint split on
`Replay.CHECKPOINT_PERIOD` as `PerfReport.job_minus_step_ms` (`tests/perf/support/perf_report.gd`)
does. P49a's `WATCH sim job_minus_step` line already prints the two `job_minus_step` keys under
these names, so a CI line and a card compare key by key; `WATCH sim commands` is the watch line of
`Formation.assign` above.

Status note (2026-10-22, ADR 0016 accepted; the text and the note above stay as accepted): ADR
0016 (`docs/adr/0016-checkpoint-hash-cost.md`) answers the engine-side watch line after the gate
runs of issue #157 put `job_minus_step_p95_cp_ms` at 3.325-3.587 ms.
- **The line** (Michael's answer 2A): it stays 25 % of `sim_p95_ms`, 3.325 ms (the "3.3 ms"
  above, unrounded), on both `job_minus_step_p95_cp_ms` and `job_minus_step_p95_noncp_ms`. It
  stays a watch line without a verdict, applied by the lead in each card's review.
- **Correction 1:** "fewer copied arrays" acts mostly on `step_usec`, not on this line.
  `MatchSnapshot.capture`'s `duplicate()` calls are O(1) copy-on-write, so the buffer copies land
  in the next tick's `Sim.step`.
- **Correction 2:** "already run in the engine's C++, so a port cannot speed them up" holds only
  for the digest and the `duplicate()` calls. `state_hash` builds the blocks the digest reads in
  GDScript.
- **The remedy chosen** is "fewer hashed bytes": P65 will take the derived `fog.visible` out of
  the hash (ADR 0007 §8's note of the same date). If the first gate card after P65 is still above
  the line, P66 and P66b add the timing split (answer 4), and P67 then chooses between a cheaper
  digest and a native state hash.
- **A native state hash**, if ever, comes by its own ADR with a kernel row (locksteps, the
  sanitizer, the twin rule of §5), not as a port row under this ADR: §1 lists `state_hash` as
  GDScript-only, and the remedies above stay "never a port row".

Status note (2026-10-22, P26ag docs, after the Phase 2 gate, issue #157, and PR #158; the text and
the notes above stay as accepted):
- **The native ratios** ("The first release perf-arena card re-derives both by ADR 0012's 10 %
  rule"): done by plan exception 5 in PR #158 (`80c4006`). The first release card (run 1 on the
  perf APK of `2a0ffe0`) against CI run 370 of the same commit (native 0.277 ms mean, 0.484 ms
  p95): job mean 3.070 / 0.277 = 11.08 and job p95 5.834 / 0.484 = 12.05, so
  `ci_ratio_native_mean` 9.4 -> 11.1 and `ci_ratio_native_p95` 14.0 -> 12.1, rounded up to one
  decimal. They stay printed estimates, not thresholds, and no `budget.cfg` value moved.
- **The two rules on the gate cards:** the port trigger never fired (`COMMANDS` about
  0.09-0.14 ms, `REMOVE` 0.66-0.83 ms, against 25 % of `job_p95_noncp_ms`). The watch line
  `job_minus_step_p95_cp_ms` read 3.31-4.02 ms against 3.325 ms (non-checkpoint 0.61-0.80 ms),
  answered by ADR 0016 (the note above).

## Options considered
1. **Stay GDScript (ADR 0012 remedy steps 1 and 2 only).** Rejected. The mock alone misses
   `sim_p95_ms` on the worker by 42-44 % on its tick p95 and by 48-51 % on the gated job p95. The
   headroom rule gives 64 flow cells per tick, about 18 s for the arena opening's four fields.
2. **Port all nine hot phases now** (revision 2 of this draft). Rejected. Dual maintenance is
   permanent, and `GRIDS` measured 1.5 % of the mock (about 0.15 ms estimated on the phone), while
   `INTENTS`, `FIRE` and `PROJECTILES` have no measurement at all. §1's rule ports them when their
   own `PERF` line shows a reason.
3. **Port `FLOW` only.** Rejected. Separation, integration, acquisition and the fog stamps made up
   about 97-98 % of the mock tick by the table in Context (about 10 ms estimated mean on the
   phone), so the job would still
   miss `sim_p95_ms`.
4. **Wait for ADR 0012 §7's trigger (a release perf-arena card).** Rejected. The card comes about
   40 PRs from now, and the ports would then sit on the critical path before the gate. The
   GDScript versions are needed anyway as twins, so deciding now adds no GDScript work.
5. **The whole World in C++ (C1: Packed members; C2: `std::vector` as in the spike).** Rejected:
   - GDScript writes through native properties are lost silently;
   - the web would need a second World;
   - the getters must survive instantiation at import;
   - the capture gains only about 3 µs.
6. **Copy-in and copy-out at the boundary.** Rejected:
   - every writing call copies the whole array (14.4-15.4 µs per pass against 4.6-5.7 µs in
     place, §2's table; more for several passes per tick);
   - writes made through aliases taken earlier are lost (evidence comment, section 1), which
     breaks ADR 0012 §2's alias-before-the-loop rule.
7. **Bind once** (C++ keeps array references across calls). Rejected. It saves about 3 µs per
   tick and breaks silently on a reassignment.
8. **C++ only, with the web on C++ through the dlink template (option B).** Deferred (§7). It is
   the measured exit route if the twins ever cost more than they protect.
9. **C++ only, with no sim in the web preview (option C).** Rejected: the per-PR phone preview
   would lose matches.
10. **All ports in one batch after P46.** Rejected. A divergence would be found late, in several
    modules at once, right before P49a, and no `PERF` line would show progress until then.
11. **A new native-dev agent.** Rejected (§13).
12. **Rust (godot-rust).** Not evaluated: every measurement, pin and import finding here is for
    godot-cpp, and it would need its own spike. C# is banned by CLAUDE.md, and Godot 4's C# has
    no web export.
13. **An ADPF performance-hint session.** Dropped (PR #41 finding 2). It steers clocks and is no
    sim fix. If frame pacing fails, it belongs to ADR 0014's remedies, through its own ADR.

## Consequences
- **Performance:** the measured C++ mock leaves the worker job about 15 times below
  `sim_p95_ms`. Leaving `GRIDS` in GDScript adds about 0.15 ms (estimated mean), and §1's rule
  bounds what any phase left in GDScript can add. The main thread is not helped: other-frame
  work p95 was 6.93 ms with the C++ worker, against 6.60 ms with the GDScript worker. That is ADR
  0014's subject, and the view PRs'.
- **The conditional rows are likely to fire.** ADR 0012 Context extrapolated the real tick to
  about 6 ms mean on CI, about 2.4 times the mock, and the mock has no line checks, no `FIRE` and
  no `PROJECTILES`. Most of that extra time has to sit in exactly the phases §1 leaves
  conditional, so P37n2 and P42n (and with them their splits) should be expected. Michael should
  read the gate slip below as nearer its upper bound.
- **More PRs:**
  - lane A gets 5 rows, P54 and four ports (up to 9 with their named splits), plus up to 3
    conditional ports (§1; 5 with splits); lane B gets 8 infrastructure, port and perf rows (up
    to 11 with splits);
  - **the slip, counted with the plan's Depends cells** (a model in which each lane merges one PR
    per slot, on the merged plan, `main` at `038392d` with P34c merged; plan amendment, "the
    slip"): the gate becomes ready at slot 35 instead of 30 if ADR 0014 is accepted too (5 slots;
    the PerfHud split P50a3 is expected on acceptance of either ADR), or instead of 29 if this
    ADR is accepted alone (6 slots, P50a3 then charged to it). With every named port and
    infrastructure split it is 38 (8-9 slots; 39 if P41's twin edit makes its split P41b
    expected). Each conditional row that fires adds its slots on
    lane A on top: up to 5 more with their splits (43), 1 more without. Lane B's rows before
    P38 (P53, P55, P55a, P56) and between P38p and P38s (P30n) move P40 from slot 15 to 17 (19
    with splits), and lane A waits for P40 at P39b (P42a needs it too), so the critical path
    runs through lane B up to P40 and through lane A's ports after it. P54r, P38pn and P57 sit
    after P43b: P54r needs P37n for its self-check tests, and only P38pn, P38w and P50a, all
    later, need P54r. The plan's lane order is built for this (amendment, "Lanes on
    acceptance");
  - one release-engineer PR, P26l (the libc++ notice), lands in any outcome;
  - details are in the plan's amendment.
- **Permanent dual maintenance** of the hot phases, and lockstep tests in every PR that touches
  them.
- **Toolchain in every session and job:**
  - SCons 4.9.1, g++, binutils and the pinned `clang-format`, plus the NDK in the Android job;
  - CI gets slower by a cold godot-cpp build ("about ten seconds" by the spike's README; P53
    measures it), less with the cache, plus the `native-clang` job and a second Android target
    (P55a measures it);
  - the spike's Android job, uncached NDK install included, took 1m42s (run 38245066556).
- **Reliance on engine internals:**
  - in-place writes depend on the internal-pointer getter and on the Variant's Packed array
    layout;
  - the import workaround depends on `.godot/extension_list.cfg`.

  The boundary tests and the fresh-clone canary rerun on every pin change.
- **The APK grows by about 0.5 MB.** The godot-cpp and LLVM notices ship next to it, and in
  the Phase 5 licences screen (§11).
- **The web preview stays GDScript-speed** and hitches at 150 units (an estimate), as ADR 0012
  already accepted for `SYNC` on the web.
- **iOS** needs a macOS runner job for the library. That job is needed for the `.ipa` anyway.

### Open after this draft
- **The generated `.gdextension`:** that it avoids both the missing-library error and the
  import crash is unproven (P53).
- **The cost of `-fwrapv`:** not measured (P53).
- **The `clang-format` version:** not chosen (P53).
- **Phone costs of the boundary:** extrapolated about 5x from VM numbers, not measured. The
  first native `PERF` line and the release card measure them.
- **The sanitizer job:** that a UBSan library runs inside headless Godot is unproven (P57);
  loading an ASan library there (`LD_PRELOAD`) stays optional.
- **The debug APK with the `template_debug` arm64 library:** built and packed by P55a, not yet
  run on the phone; the dev APK's self-check line shows it.
- **godot-cpp under emcc 4.0.20:** unbuilt. This matters only for option B.
- **Research facts not re-run.** The evidence comment on PR #41
  (https://github.com/WackeySSL/rts-mobile/pull/41#issuecomment-6128912281) re-ran the
  boundary semantics, the cost table (on the editor binary), the import crash with its gdb
  check, the live-World read, the dynamic-call cost and the per-phase split. Not re-run, and
  marked where used, each with the PR that re-proves it after acceptance:
  - the dlink template findings (§7, option B only; the P26w spike if B is chosen);
  - the release-template numbers of §2 and §6 (the first native `PERF` line and release card);
  - the `--recovery-mode` fallback and the upstream issue status (§9; P53);
  - the template's NDK notes (r29 / r28.0, LLD 21, from `.note.android.ident`) and the 16 KB
    LOAD alignment of Godot's own `.so` files (Context, §8): P55a logs both from the APK it
    checks;
  - the 100 and 20 header-warning counts under plain `-I` (§12): P53 re-counts them once and
    records them in its PR;
  - `Formation.assign` at 3.15 ms for 150 units and the checkpoint hash at about 380 µs on the
    VM (§15): P49a's report lines measure both;
  - the snapshot capture's gain of about 3 µs from a C++ World (§2, option 5): no PR re-proves
    it, because option 5 is rejected and nothing depends on the figure.

  This list is complete: the evidence comment's own "Not re-run here" section names only the
  dlink, release-template and upstream-status items.
  P53 re-proves the import facts in CI after acceptance, P54 the `check_world` and name facts,
  and P30n the in-place write, fork, scalar and no-op facts through the FLOW kernel.

Status note (2026-10-13, P26i): these items are closed by P53 (#59) and P53b (#60), except where a
bullet names another source:
- **the generated `.gdextension`:** proven, 6 of 6 fresh-clone imports without a build and 6 of 6
  with a build and the seed (§9's status note);
- **the cost of `-fwrapv`:** at most +1.9 % on the mock's tick mean (+4.1 % on one slice mean,
  g++ `-O2`; clang++ `-O3`, the shipped build, -1.6 %), under the 5 % rule (§4's status note);
- **the `clang-format` version:** 20.1.8, the last 20.x patch; godot-cpp's own pre-commit hook pins
  the 20 series (§8's status note);
- **the `--recovery-mode` fallback:** 0 of 10 failures at about +6-7 s per job, not used (§9).
  The other half of that list item, the upstream issue status, stays open: no PR re-checked
  #111048, #111645 or fix PR #123658. Nothing waits on it, because the seed stays until a
  Godot-bump ADR shows the minimal repro at 0 of 10 (§9, Exit);
- **the plain `-I` warning counts:** 200 lines (83 distinct) on g++ 13.3.0 and 333 (178) on
  clang++ 18.1.3 (§12's status note);
- **the template's NDK notes:** settled by P26l and Michael's answer of 2026-10-13 ("NDK r29"),
  not by P53: the `libc++_shared.so` is r29 / LLVM 21, not r28 (Context's status note), and the
  kernels are built with NDK 29.0.14206865 (§8). Still to come: P55a re-reads the notes and the
  16 KB alignment in CI from the APK it checks.

Status note (2026-10-14, P26s docs): the sanitizer job's item is closed by P57 (#96). The UBSan
library runs the `tests/sim/native` suites inside headless Godot (the `sanitizers` job, green on
the PR's last commit), and loading an ASan library there (`LD_PRELOAD`) was not taken; ASan runs
only in the standalone harness over `core/` (§10's status note of P26s docs).

## Acceptance note (2026-10-12)
Michael answered the four questions of the plan's amendment ("Open questions for Michael (ADR
0013/0014)") in chat on 2026-10-12, verbatim: **"1 ja, 2 A, 3 ja, 4 ja"**.
1. **Yes: this ADR is accepted:** C++17 kernels for the measured hot phases of §1, each with its
   GDScript twin kept for good (§5), including its CLAUDE.md lines (§14) and the session tools of
   §8 (SCons 4.9.1, g++, binutils and the pinned `clang-format` in `setup.sh` and the session
   hook, P53). This ADR is the "new ADR" that CLAUDE.md's Stack heading requires for the change.
2. **A: the web preview stays on the GDScript twins** (§7, option A): the plain `web_nothreads`
   template, no emsdk, the Web preset excluding `native/*` (P53). Option B (the dlink template)
   stays the recorded exit route of §5 and §7. Adopting it needs the P26w spike and a new ADR
   after the Phase 2 gate. No PR works on it before then.
3. ADR 0014 is accepted too, with the calibration run; see its own acceptance note. The slip
   therefore counts with P50a3 charged to both ADRs: the gate becomes ready at slot 35 instead of
   30 (38 with every named split, 39 if P41b is expected, up to 44 if every conditional row fires
   with its splits; the plan's amendment, "the slip").
4. **Yes: the agent-file changes of §13.** `gameplay-dev.md` (both versions of a rule,
   `native/sim_kernels/src/**` and `tests/sim/native/**`), `release-engineer.md` (the native
   build, the seed script, the NDK, the session tools, the licence files, the P53 skeleton as a
   named exception) and `qa-engineer.md` (the C++ scan, the sanitizer harness and its dump step,
   the review of `check-native-tests.sh`) changed with this note.

**Applied on acceptance (§14), in P26b.** The lead applied §14's docs list in P26b, the PR that
carried the proposal, instead of a separate P26e (the plan's revision 15 folds P26e's row into
P26b; nothing that waited for P26e waits any longer, and P53 now depends on P26b):
- `CLAUDE.md`: the Stack line, the Tests and Format/lint line (the `clang-format` version reads
  "the version `verify.sh` pins (P53)"), the Layout line for `native/`, the Commands line for
  `build-native.sh`, and the addition to Architecture rule 1, each with §14's text;
- the three agent files (§13, answer 4);
- `rts-sim-conventions`: the "Native kernels" section (§1-§6, §12's checklist) and the flow line
  (P27f withdrawn, 512 stays, §15);
- the status lines in ADRs 0001, 0005 (§1), 0007 (§8), 0008 (§3), 0011 (§6) and 0012 (§4, §5,
  §7), replacing the one-line pointers of the draft;
- `docs/ROADMAP.md`, Phase 5's licences screen: godot-cpp's MIT text on builds with the library;
- the plan's revision 15.

Two follow-ups stay as §14 named them: the lead puts the `clang-format` version number into
`CLAUDE.md` in a one-line docs PR after P53 merges, and adds ADR 0007 §4's status line in a
one-line docs PR only if P41g's rule fires.

Status note (2026-10-13, P26i): the first follow-up is done. P26i changes CLAUDE.md's Stack line
from "C++: `clang-format` the version `verify.sh` pins (P53)" to "C++: `clang-format` 20.1.8,
pinned in `scripts/ci/check-cpp-format.sh`", and nothing else in CLAUDE.md. ADR 0007 §4's line
still waits for P41g.

**One correction to §12 and §14: the C++ review checklist lives in `rts-sim-conventions`, not in
`godot-code-review`.** `godot-code-review` is one of the GodotPrompter skills copied unchanged
under `.claude/skills/THIRD_PARTY_NOTICES.md`, which says "Do not edit these folders locally; put
project-specific rules in our own skills". §12's checklist (signatures and the checked fetch,
pointer lifetime, integer widths, undefined behaviour, order, allocation, the line-by-line mirror
of the twin) is therefore the last part of the skill's "Native kernels" section, and a reviewer of
a C++ PR loads `rts-sim-conventions` next to `godot-code-review`. The plan's "File ownership"
row for the lead names the skill instead. What is checked does not change, only where the text
lives. The skill's `paths` include `native/**`, so it loads for any edit there.

**CLAUDE.md's review line (answered).** CLAUDE.md's "Review with `/code-review` plus the
`godot-code-review` skill" lay outside §14's approved text, so P26b left it unchanged and the lead
asked Michael whether to extend it to "... plus the `godot-code-review` skill (and
`rts-sim-conventions`' "Native kernels" checklist for any PR that touches `native/`)". He answered
in chat on 2026-10-12, verbatim: **"Ja"**. P26f applies that exact text to CLAUDE.md.

**CLAUDE.md describes the state from P53 on.** §14's lines land before the tooling they name:
`scripts/build-native.sh`, `native/` and the `verify.sh` build and format step arrive in P53, the
sanitizer harness in P57. Until P53 merges, agents run `verify.sh` as before and do not run
`build-native.sh`; its absence is not a missing tool. The one-line `clang-format` follow-up after
P53 confirms the Commands line has become true.

**Consequences recorded at acceptance:**
- **P27f is withdrawn** and P27b's 512 stays (§15, ADR 0012 §5's rule with the C++ slice). The
  value holds from the moment the §1 ports have merged (P49a's Depends cell names them all);
  until then 512 runs on phases that are partly GDScript, which no gate judges.
- **Michael re-pastes `scripts/cloud/setup.sh`** into the cloud environment's settings after P53
  merges (§8, "Sessions"). Until he does, the session hook that P53 changes installs SCons and
  `clang-format` at session start; if an install fails, `verify.sh` is RED and names the missing
  tool, never a skip.
- **`-fwrapv` stays in every production build** until Michael decides otherwise (§4). P53 measures
  its cost on the mock; above 5 % the lead brings the number to him with a recommendation.
- P26l (the LLVM libc++ notice) lands as planned, independent of this answer.
