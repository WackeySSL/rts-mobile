extends GdUnitTestSuite
## Where the music is asked for (plan row P506, ADR 0041 section 5): the menu music starts when the
## main menu is ready, the battle music with the first published tick and only once.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/input/support/placement_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ROSTER: Array = ["power_plant", "barracks", "vehicle_factory", "defence_turret", "light_tank"]

var _main: Node2D
var _menu: Control
var _window_size_before: Vector2i


## Stands in for `AudioService`: remembers the ids `play_music` was asked for.
class FakeAudio:
	extends Node
	var asked: Array[StringName] = []

	func play_music(id: StringName) -> bool:
		asked.append(id)
		return true


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	if is_instance_valid(_main):
		_main.free()
	if is_instance_valid(_menu):
		_menu.free()


func test_the_menu_asks_for_the_menu_music_when_it_is_ready() -> void:
	var fake: FakeAudio = auto_free(FakeAudio.new())
	var profile: UiMetrics = _profile_with_window(ScreenSizes.LANDSCAPE[0])
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	_menu = (load("res://scenes/menu/menu.tscn") as PackedScene).instantiate()
	var root: MenuRoot = MenuRoot.new()
	root.routes = MenuRoutes.new()
	root.register_defaults = false
	root.take_pending = func() -> StringName: return &""
	root.audio = fake
	_menu.add_child(root)
	assert_array(fake.asked).is_empty()
	add_child(_menu)
	await await_idle_frame()
	assert_array(fake.asked).is_equal([&"menu"])


func test_the_first_published_tick_asks_for_the_battle_music_once() -> void:
	var fake: FakeAudio = auto_free(FakeAudio.new())
	var runner: MatchRunner = _new_main(fake)
	add_child(_main)
	await await_idle_frame()
	assert_array(fake.asked).is_empty()
	runner.ticked.emit(1)
	runner.ticked.emit(2)
	assert_array(fake.asked).is_equal([&"battle"])


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	return null


func test_a_restored_match_asks_for_the_battle_music_when_it_enters_the_tree() -> void:
	var fake: FakeAudio = auto_free(FakeAudio.new())
	var runner: MatchRunner = _new_main(fake)
	runner.restored = true  # As the Restorer plays it: off the tree, up to the stored tick.
	runner.start()
	runner.run_ticks(3)
	assert_array(fake.asked).is_empty()
	add_child(_main)
	await await_idle_frame()
	assert_array(fake.asked).is_equal([&"battle"])
	runner.ticked.emit(4)
	assert_array(fake.asked).is_equal([&"battle"])


## The main scene with `fake` as its music service, its runner paused and not started.
func _new_main(fake: FakeAudio) -> MatchRunner:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.set("audio", fake)
	var runner: MatchRunner = _main.get_node("MatchRunner")
	runner.scenario = Rig.scenario_for(1, "headquarters", [], ROSTER)
	runner.paused = true
	return runner
