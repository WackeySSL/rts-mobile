extends GdUnitTestSuite
## The wrench over a mending building (plan P272, ADR 0037 section 4): an own complete building
## whose repair switch is on (`cargo` 1) wears the repair map glyph, green, in the bar layer after
## the power glyphs. An enemy building with its switch on shows none, and neither does a site, a
## dead row or a unit whose `cargo` is its load. A wrench over a building that wears a power glyph
## stands one glyph higher. On a 32 x 32 map: player 1's Headquarters (row 0), power plant (1),
## Bunkhouse (2), defence (3) and rifle squad (4), and player 2's Bunkhouse (5).

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const SPAWNS: Array[Array] = [
	[1, "headquarters", 4, 4],
	[1, "power_plant", 10, 4],
	[1, "barracks", 16, 4],
	[1, "defence_turret", 22, 4],
	[1, "rifle_squad", 20, 20],
	[2, "renew_barracks", 10, 22],
]
const WRENCH_ART: String = "res://assets/art/svg/icons/glyph_repair_map.svg"
const PLAYER: int = 1

var _runner: MatchRunner
var _camera: RtsCamera
var _units: UnitLayer
var _buildings: BuildingLayer
var _bars: HealthBarLayer


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))
	var spawns: Array[SpawnDef] = []
	for entry: Array in SPAWNS:
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	_runner = auto_free(Rig.runner(Rig.scenario(spawns)))
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	var sort: WorldSort = auto_free(WorldSort.new())
	sort.runner = _runner
	add_child(sort)
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	_units.camera = _camera
	_units.world_sort = sort
	_units.clock = func() -> int: return 0
	add_child(_units)
	_buildings = auto_free(BuildingLayer.new())
	_buildings.runner = _runner
	_buildings.world_sort = sort
	_buildings.reveal_enemies = true
	add_child(_buildings)
	_bars = auto_free(HealthBarLayer.new())
	_bars.runner = _runner
	_bars.unit_layer = _units
	_bars.building_layer = _buildings
	add_child(_bars)
	for layer: Node in [_units, _buildings]:
		layer.set_process(false)


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func _frame() -> void:
	_units._process(0.0)
	_buildings._process(0.0)
	_bars._process(0.0)


func _id(row: int) -> int:
	return _runner.snapshot.unit_id[row]


func test_an_own_building_with_the_switch_on_wears_the_green_wrench_over_its_place() -> void:
	_frame()
	assert_int(_bars.glyph_count()).is_equal(0)  # The switch is off.
	_runner.snapshot.cargo[2] = 1
	_frame()
	assert_int(_bars.glyph_count()).is_equal(1)
	assert_str(_bars.glyph_texture(0).resource_path).is_equal(WRENCH_ART)
	assert_that(_bars.glyph_tint(0)).is_equal(_bars.mend_color)
	var unit: float = UiScale.base_px_per_dp() / _camera.zoom.x
	var rect: Rect2 = _bars.glyph_rect(0)
	assert_float(rect.size.x).is_equal_approx(32.0 * unit, 0.01)
	assert_float(rect.get_center().x).is_equal_approx(_buildings.building(_id(2)).position.x, 0.01)
	_runner.snapshot.cargo[2] = 0
	_frame()
	assert_int(_bars.glyph_count()).is_equal(0)  # It goes with the switch.


## The row's switch may be on in the snapshot for an enemy building (the sim keeps it per row): the
## view never reads it, so no wrench shows for the enemy.
func test_an_enemy_building_with_the_switch_on_shows_no_wrench() -> void:
	_runner.snapshot.cargo[5] = 1
	_frame()
	assert_int(_runner.snapshot.owner[5]).is_not_equal(PLAYER)
	assert_int(_bars.glyph_count()).is_equal(0)
	_runner.snapshot.cargo[2] = 1  # An own one beside it still shows.
	_frame()
	assert_int(_bars.glyph_count()).is_equal(1)
	assert_float(_bars.glyph_rect(0).get_center().x).is_equal_approx(
		_buildings.building(_id(2)).position.x, 0.01
	)


func test_a_unit_a_site_and_a_dead_row_show_no_wrench() -> void:
	_runner.snapshot.cargo[4] = 1  # A rifle squad's cargo is its load, not a switch.
	_runner.snapshot.cargo[1] = 1
	_runner.snapshot.build_left[1] = 30  # A site.
	_runner.snapshot.cargo[3] = 1
	_runner.snapshot.hp[3] = 0
	_frame()
	assert_int(_bars.glyph_count()).is_equal(0)


func test_the_wrench_follows_the_power_glyphs_and_stands_higher_over_a_building_that_wears_one(
) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.power_used[PLAYER] = 200  # Low power: the defence (3) wears the offline glyph.
	snap.power_made[PLAYER] = 100
	snap.cargo[3] = 1
	snap.cargo[2] = 1
	_frame()
	var power: int = _bars.glyph_count() - 2
	assert_int(power).is_greater(0)
	assert_int(_bars.offline_glyph_count()).is_equal(1)
	# The wrenches are the last two; the defence's is stacked over its offline glyph.
	var defence: Rect2 = _bars.glyph_rect(0)
	var found: int = 0
	for at: int in range(power, _bars.glyph_count()):
		assert_str(_bars.glyph_texture(at).resource_path).is_equal(WRENCH_ART)
		var rect: Rect2 = _bars.glyph_rect(at)
		if is_equal_approx(rect.get_center().x, defence.get_center().x):
			found += 1
			assert_float(rect.position.y).is_less(defence.position.y - defence.size.y + 0.5)
	assert_int(found).is_equal(1)
