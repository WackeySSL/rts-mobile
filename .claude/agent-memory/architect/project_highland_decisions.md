---
name: project-highland-decisions
description: ADR 0055 PROPOSED 2026-11-28 (P680, branch claude/p680-highland-plan): playable high ground, woods/houses/bridges, skirmish map generator; rows P680-P699, 16 questions
metadata:
  type: project
---
# Highland landscape + map generator (ADR 0055 proposed 2026-11-28)

- Michael 2026-11-28: no man-made rock; high ground playable now ("B ... ramps"); bridges, trees, abandoned houses; 13:35Z scope change: a generator, no fixed skirmish maps (fixed only for missions/tutorials/perf).
- Sim: World.height LOW 0 / RAMP 1 / HIGH 2 / CLIFF 3 (CLIFF = high cell with a low 8-neighbour, derived, cost 0 ground); cliff as a band of cells, not edges, so NO movement code or movement kernel changes; only FOG changes in both twins (high cells stamped only by ramp/high/air viewers, signature unchanged).
- MapDef.heights layer (`0`/`1`/`r`), MapDef.relief (view-only opt-in), MapDef.symmetry; ramps 2-4 wide x 1-2 long rectangles; no diagonal pinch; ramp_clearance_tiles 1 unbuildable; terrains bridge `=` and house `H` appended; scrub = woods (rule unchanged).
- Hashes: height in MAP_ARRAYS, STATE_FORMAT 8, exception 27 (P681, every golden); exception 28 (P692 perf_bases relief). Next free 29. Replay.FORMAT 4 holds the map spec.
- View: lifted rigs sort at ground y + lift + SORT_PAD 8 (40 px on a plateau); their shadow and ring move into the sorted world (ring art on PAGE_SORTED); no silhouettes for lifted rigs; ground_at gives exact points on tops/ramps; placement uses it (supersedes A8's flat inverse); relief band <= 640 rows (supersedes A5's 224); <= 2,400 relief sprites per 64x64.
- Generator in game/sim/mapgen (pure, main thread before from_scenario), DetRng.create(map_seed, STREAM_MAPGEN 2), MapGen.VERSION covers code + preset data, other versions refused; map seed separate from match seed; catalog ids kestrel_flats/map_2/map_3 become landscape types so trophies/unlocks/wins keep keys.
- Recommended transpose symmetry (screen left-right mirror; starts on the anti-diagonal so AiMemory's point mirror still holds); AI spiral needs a reflected frame (P684); half turn shows one seat the back of all cliffs.
- In-flight: #733 + d4b merge; d3 merges with 4f9c3189 (walls on in main.tscn) reverted; walls on in P691 with per-map opt-in.
- Pitfall: HOW_TO_PLAY "Not yet in the game" rows use `later-` ids and ids never change, so don't draft rows there early; land them in the PR where players first see the feature (P698).
- Pitfall: a mid-task scope change from the lead (generator) replaced the map-redesign rows; fold it into the same row range instead of a second plan.
