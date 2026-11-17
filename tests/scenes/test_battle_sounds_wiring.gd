extends GdUnitTestSuite
## P535: the battle scene and the perf arena carry a BattleSounds node wired to their runner, so
## the battle plays its sounds and the perf card sees their cost.

const MAIN_SCENE: String = "res://scenes/main.tscn"
const ARENA_SCENE: String = "res://scenes/dev/perf_arena.tscn"


func _sounds_of(path: String) -> BattleSounds:
	var scene: Node = auto_free((load(path) as PackedScene).instantiate())
	add_child(scene)
	var found: Array[Node] = scene.find_children("*", "BattleSounds", true, false)
	assert_int(found.size()).is_equal(1)
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
