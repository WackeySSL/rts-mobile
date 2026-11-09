class_name DevRoutes
extends RefCounted
## Scene paths and gating for the developer-only screens (dev menu, art gallery, touch probe, perf
## arena and its base arena), the main scene's scenario for the "Strike test" route and the two
## Skirmish routes (a scenario and the computer of the other side at a level, plan P183).
##
## The dev menu is available in debug builds and in any export that sets the custom feature
## `dev_menu` (the Web preview preset does). Store presets must not set it.

const MAIN_SCENE: String = "res://scenes/main.tscn"
const DEV_MENU_SCENE: String = "res://scenes/dev/dev_menu.tscn"
const ART_GALLERY_SCENE: String = "res://scenes/dev/art_gallery.tscn"
const TOUCH_PROBE_SCENE: String = "res://scenes/dev/touch_probe.tscn"
const PERF_ARENA_SCENE: String = "res://scenes/dev/perf_arena.tscn"
## The base arena of the perf arena scene (plan P93c): P80's scenario, run by the same scene and
## card, checked against the gate's `bases_golden_*` fields.
const PERF_BASES_SCENARIO: String = "res://data/scenarios/perf_bases.tres"
## The AI arena of the perf arena scene (plan P185, ADR 0030 section 4): the two mirror bases of
## `perf_ai.tres` on frozen defs, a Normal `OpponentAi` on each player, no golden pair.
const PERF_AI_SCENARIO: String = "res://data/scenarios/perf_ai.tres"
## The computers of that arena play the frozen AI defs with early contact (plan P189b: an early
## scout and first wave), the same files as `tests/perf/test_ai_perf.gd`, so the card times what
## the suite times. The Skirmish routes keep the shipped defs below.
const PERF_AI_FOSSIL: String = "res://data/dev/arena/ai/opponent_fossil.tres"
const PERF_AI_RENEW: String = "res://data/dev/arena/ai/opponent_renew.tres"
const PERF_AI_LEVEL: String = "res://data/dev/arena/ai/difficulty/normal.tres"
## The "Strike test" scenario (plan P112d): the local player owns a Deep Bore and a Dusk Array
## with a short charge, facing a still enemy base, so the phone preview can fire both strikes.
const STRIKE_TEST_SCENARIO: String = "res://data/scenarios/dev_strikes.tres"
## The two Skirmish routes (plan P90), one per side: Kestrel Flats with the player on the Derrick
## League, or on the Lumen Accord (player 1 is local in both), and the computer of the other side.
const SKIRMISH_DERRICK: String = "res://data/scenarios/skirmish_kestrel_flats.tres"
const SKIRMISH_LUMEN: String = "res://data/scenarios/skirmish_kestrel_flats_mirrored.tres"
## The dummies stay the test opponents of `tests/e2e` and the balance run's yardstick (ADR 0030).
const DUMMY_FOSSIL: String = "res://data/ai/dummy_fossil.tres"
const DUMMY_RENEW: String = "res://data/ai/dummy_renew.tres"
## The computer of each side (`OpponentAi`, plan P183) and the three levels it plays at.
const OPPONENT_FOSSIL: String = "res://data/ai/opponent_fossil.tres"
const OPPONENT_RENEW: String = "res://data/ai/opponent_renew.tres"
const LEVEL_EASY: String = "res://data/ai/difficulty/easy.tres"
const LEVEL_NORMAL: String = "res://data/ai/difficulty/normal.tres"
const LEVEL_HARD: String = "res://data/ai/difficulty/hard.tres"


static func is_enabled() -> bool:
	return OS.is_debug_build() or OS.has_feature("dev_menu")


## Changes to `scene_path`. Reports a missing scene with push_error instead of crashing.
static func open(tree: SceneTree, scene_path: String) -> Error:
	if not ResourceLoader.exists(scene_path):
		push_error("DevRoutes: scene not found: %s" % scene_path)
		return ERR_FILE_NOT_FOUND
	return tree.change_scene_to_file(scene_path)


## Changes to the perf arena scene with its base arena scenario (`PerfArena.arena_kind` is set on
## the new scene before it enters the tree, as `open_main_with` does for the runner). Reports a
## missing scene with push_error instead of crashing.
static func open_perf_bases(tree: SceneTree) -> Error:
	if not ResourceLoader.exists(PERF_ARENA_SCENE):
		push_error("DevRoutes: scene not found: %s" % PERF_ARENA_SCENE)
		return ERR_FILE_NOT_FOUND
	var arena: Node = (load(PERF_ARENA_SCENE) as PackedScene).instantiate()
	arena.arena_kind = PerfHud.ARENA_BASES
	return tree.change_scene_to_node(arena)


## Changes to the perf arena scene with the AI arena (plan P185): like `open_perf_bases`, with
## `PerfArena.arena_kind` set before the scene enters the tree; the scene seats the two computer
## players. Reports a missing scene or scenario with push_error instead of crashing.
static func open_perf_ai(tree: SceneTree) -> Error:
	if not ResourceLoader.exists(PERF_ARENA_SCENE):
		push_error("DevRoutes: scene not found: %s" % PERF_ARENA_SCENE)
		return ERR_FILE_NOT_FOUND
	if not ResourceLoader.exists(PERF_AI_SCENARIO):
		push_error("DevRoutes: scenario not found: %s" % PERF_AI_SCENARIO)
		return ERR_FILE_NOT_FOUND
	var arena: Node = (load(PERF_ARENA_SCENE) as PackedScene).instantiate()
	arena.arena_kind = PerfHud.ARENA_AI
	return tree.change_scene_to_node(arena)


## Changes to the main scene with `scenario_path` in the MatchRunner in place of the scene's own
## scenario (Test map's), and `opponents` as its computer players with their `levels` and the player
## of the first (`MatchRunner`'s three fields are not exported, so they are set here; a restart
## passes the old runner's, so the new match has the same opponent at the same level). The runner
## starts its match in its own `_ready`, so all four are set on the new scene before it enters the
## tree.
## Reports a missing scenario with push_error instead of crashing.
static func open_main_with(
	tree: SceneTree,
	scenario_path: String,
	opponents: Array[AiDef] = [],
	levels: Array[AiDifficultyDef] = [],
	first_opponent: int = MatchRunner.FIRST_OPPONENT
) -> Error:
	var scenario: ScenarioDef = (
		load(scenario_path) as ScenarioDef if ResourceLoader.exists(scenario_path) else null
	)
	if scenario == null:
		push_error("DevRoutes: scenario not found: %s" % scenario_path)
		return ERR_FILE_NOT_FOUND
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	var runner: MatchRunner = main.get_node("MatchRunner")
	runner.scenario = scenario
	runner.opponents = opponents
	runner.opponent_levels = levels
	runner.first_opponent = first_opponent
	return tree.change_scene_to_node(main)


## A Skirmish: `scenario_path` against the computer `opponent_path` as player 2, at the level in
## `level_path` (a dummy takes no level). Reports a missing file with push_error instead of
## crashing.
static func open_skirmish(
	tree: SceneTree, scenario_path: String, opponent_path: String, level_path: String = LEVEL_NORMAL
) -> Error:
	var opponent: AiDef = (
		load(opponent_path) as AiDef if ResourceLoader.exists(opponent_path) else null
	)
	if opponent == null:
		push_error("DevRoutes: opponent not found: %s" % opponent_path)
		return ERR_FILE_NOT_FOUND
	var level: AiDifficultyDef = (
		load(level_path) as AiDifficultyDef if ResourceLoader.exists(level_path) else null
	)
	if level == null:
		push_error("DevRoutes: level not found: %s" % level_path)
		return ERR_FILE_NOT_FOUND
	var opponents: Array[AiDef] = [opponent]
	var levels: Array[AiDifficultyDef] = [level]
	return open_main_with(tree, scenario_path, opponents, levels)
