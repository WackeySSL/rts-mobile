# ADR 0001: Engine, rendering and simulation architecture

Status: accepted, 2026-10-10

Status note (2026-10-12): the Consequences line "hot paths may move to GDExtension later through a
new ADR" is taken up by ADR 0013 (accepted 2026-10-12): C++17 kernels for the sim's measured hot
phases in `native/sim_kernels/`, each with a GDScript twin kept in `game/sim/`.

## Context
rts-mobile is built entirely by Claude Code, mostly in cloud sessions, published as open source
and built by GitHub Actions. It is a 2D RTS for phones with up to about 150 units, funded by ads,
Android first.

## Decision
1. Godot 4.7.x (pinned 4.7.2) with statically typed GDScript. Scenes and scripts are text that
   agents can write and diff, and the engine runs headless in cloud VMs and CI without a licence.
   Unity was rejected: CI needs licence activation and its scenes need the editor.
2. Compatibility renderer, required for the web preview and the widest Android support.
3. 2D top-down art as hand-written SVG imported by Godot. Purchased asset packs cannot live in a
   public repository.
4. Deterministic simulation separated from presentation: 15 Hz fixed tick, integer fixed-point
   state, seeded DetRng, every action as a Command, state hash and replays.
5. Code under MIT; the game's name and logo are reserved by AppCode ApS.

## Consequences
- AI-vs-AI balance runs, replays and determinism tests are cheap, and online multiplayer stays
  possible later.
- Integer maths needs helpers (sine table, integer direction), and GDScript performance must be
  watched; hot paths may move to GDExtension later through a new ADR.
- Art quality is bounded by what can be drawn as SVG code. A human illustrator would need assets
  kept outside the public repository.
- Forks can republish the code; protection relies on the trademark, store presence and update pace.
