extends GdUnitTestSuite
## P535: the battle scene and the perf arena carry a BattleSounds node wired to their runner, so
## the battle plays its sounds and the perf card sees their cost.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const MAIN_SCENE: String = "res://scenes/main.tscn"
const ARENA_SCENE: String = "res://scenes/dev/perf_arena.tscn"


func before_test() -> void:
	MenuRig.begin()


## The slide override is static state: leaving it changes every later suite.
func after_test() -> void:
	MenuRig.end()


func _sounds_of(path: String) -> BattleSounds:
	var scene: Node = auto_free((load(path) as PackedScene).instantiate())
	add_child(scene)
	var found: Array[Node] = scene.find_children("*", "BattleSounds", true, false)
	assert_int(found.size()).is_equal(1)
	if found.size() != 1:
		return null
	return found[0] as BattleSounds


func test_main_scene_has_battle_sounds_on_its_runner() -> void:
	var sounds: BattleSounds = _sounds_of(MAIN_SCENE)
	assert_object(sounds.runner).is_not_null()
	assert_object(sounds.runner).is_same(sounds.get_node(^"../MatchRunner"))
	assert_bool(sounds.runner.ticked.is_connected(sounds._on_ticked)).is_true()
	assert_bool(sounds.reveal_enemies).is_false()


func test_perf_arena_has_battle_sounds_on_its_runner() -> void:
	var sounds: BattleSounds = _sounds_of(ARENA_SCENE)
	assert_object(sounds.runner).is_same(sounds.get_node(^"../MatchRunner"))
	assert_bool(sounds.runner.ticked.is_connected(sounds._on_ticked)).is_true()
	assert_bool(sounds.reveal_enemies).is_true()


func test_main_scene_wires_ui_sounds_to_the_local_player_and_cues() -> void:
	var scene: Node = auto_free((load(MAIN_SCENE) as PackedScene).instantiate())
	add_child(scene)
	var ui: UiSounds = scene.get_node(^"UiSounds") as UiSounds
	var runner: MatchRunner = scene.get_node(^"MatchRunner") as MatchRunner
	var cues: AttackCues = scene.get_node(^"Hud/AttackCues") as AttackCues
	assert_int(ui.local_player).is_equal(runner.scenario.local_player)
	assert_bool(cues.cue_changed.is_connected(ui._on_cue_changed)).is_true()
