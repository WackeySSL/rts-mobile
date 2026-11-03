extends GdUnitTestSuite
## The low-power glyph (plan P89 revision 5, ADR 0023 section 2, ADR 0025 section 8): while the
## local player's published `power_used` is above its `power_made`, every own building that uses
## power wears the low-power glyph in the bar layer at z 30, no dim and no sprite touched. The rows
## are `PowerConsumers`' (the economy card's too, and `Power.run`'s): not a construction site, not
## held offline by a blackout, not a producer, not a unit, not the enemy's. The squares are the
## offline glyph's (GLYPH_DP square, over the place of the bar) and follow the offline ones in the
## plan. On a 32 x 32 map: player 1's Headquarters (row 0), power plant (1), Bunkhouse (2), defence
## (3), refinery (4) and rifle squad (5), and player 2's Bunkhouse (6).

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const SPAWNS: Array[Array] = [
	[1, "headquarters", 4, 4],
	[1, "power_plant", 10, 4],
	[1, "barracks", 16, 4],
	[1, "defence_turret", 22, 4],
	[1, "refinery", 4, 12],
	[1, "rifle_squad", 20, 20],
	[2, "renew_barracks", 10, 22],
]
const CONSUMERS: Array[int] = [2, 3, 4]
const GLYPH_DP: int = 32
const DANGER: Color = Color("FF5A3C")
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


func test_every_own_consumer_wears_the_glyph_on_low_power_and_nothing_else_does() -> void:
	_power(60, 100)
	_frame()
	assert_int(_bars.offline_glyph_count()).is_equal(0)
	assert_int(_bars.glyph_count()).is_equal(CONSUMERS.size())
	var unit: float = UiScale.base_px_per_dp() / _camera.zoom.x
	for at: int in CONSUMERS.size():
		var rect: Rect2 = _bars.glyph_rect(at)
		var node: Node2D = _buildings.building(_id(CONSUMERS[at]))
		assert_float(rect.size.x).is_equal_approx(GLYPH_DP * unit, 0.01)
		assert_float(rect.get_center().x).is_equal_approx(node.position.x, 0.01)


func test_no_glyph_while_power_is_enough_and_it_goes_with_the_shortage() -> void:
	_power(100, 100)  # Using exactly what is made is not low power.
	_frame()
	assert_int(_bars.glyph_count()).is_equal(0)
	_power(100, 101)
	_frame()
	assert_int(_bars.glyph_count()).is_equal(CONSUMERS.size())
	_power(120, 100)
	_frame()
	assert_int(_bars.glyph_count()).is_equal(0)


func test_it_reads_the_local_players_totals_not_the_enemys() -> void:
	_power(200, 100)
	_runner.snapshot.power_used[2] = 500  # The enemy is short; the local player is not.
	_runner.snapshot.power_made[2] = 0
	_frame()
	assert_int(_bars.glyph_count()).is_equal(0)
	_power(60, 100)
	_runner.snapshot.power_used[2] = 0
	_runner.snapshot.power_made[2] = 100  # The enemy is fine; the local player is short.
	_frame()
	assert_int(_bars.glyph_count()).is_equal(CONSUMERS.size())  # The enemy Bunkhouse has none.


func test_a_site_and_a_blacked_out_building_are_no_consumers() -> void:
	_power(60, 100)
	var snap: MatchSnapshot = _runner.snapshot
	snap.build_left[2] = 30  # Still a site: Power.run does not count it.
	snap.offline_until[3] = snap.tick + 100  # A blackout: it has the offline glyph instead.
	_frame()
	assert_int(_bars.offline_glyph_count()).is_equal(1)
	assert_int(_bars.glyph_count()).is_equal(2)  # The offline one first, then the refinery's.
	assert_float(_bars.glyph_rect(0).get_center().x).is_equal_approx(
		_buildings.building(_id(3)).position.x, 0.01
	)
	assert_float(_bars.glyph_rect(1).get_center().x).is_equal_approx(
		_buildings.building(_id(4)).position.x, 0.01
	)


func test_the_consumers_are_the_rows_the_power_rule_counts() -> void:
	var world: World = _runner.world
	world.build_left[2] = 30
	world.offline_until[3] = world.tick + 100
	Power.run(world)
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.capture(world, null)
	assert_int(_consumed(snap)).is_greater(0)
	assert_int(_consumed(snap)).is_equal(snap.power_used[PLAYER])
	world.build_left[2] = 0
	world.offline_until[3] = 0
	Power.run(world)
	snap.capture(world, null)
	assert_int(_consumed(snap)).is_equal(snap.power_used[PLAYER])


func test_the_economy_card_sums_the_same_rows() -> void:
	var card: EconomyCard = auto_free(EconomyCard.new())
	add_child(card)
	_power(60, 100)
	var snap: MatchSnapshot = _runner.snapshot
	snap.build_left[2] = 30
	snap.offline_until[3] = snap.tick + 100
	card.show_from(snap, PLAYER, 0)
	var shown: int = 0
	for chip: Node in card.find_child("CardChips", true, false).get_children():
		if chip.visible:
			shown += (chip.find_child("Sum", true, false) as DigitRow).text.to_int()
	assert_int(shown).is_equal(_consumed(snap))
	assert_int(shown).is_equal(30)  # Only the refinery.


func test_the_plan_allocates_nothing_after_the_first_low_power_frame() -> void:
	_power(60, 100)
	_frame()
	var size_before: int = _bars._glyph_at.size()
	for step: int in 20:
		_frame()
	assert_int(_bars._glyph_at.size()).is_equal(size_before)
	assert_int(_bars.glyph_count()).is_equal(CONSUMERS.size())


func test_no_sprite_is_dimmed_and_the_glyph_is_painted_danger_red_from_the_art() -> void:
	var before: Array[Color] = []
	for row: int in CONSUMERS:
		before.append(_buildings.building(_id(row)).modulate)
	_power(60, 100)
	_frame()
	for at: int in CONSUMERS.size():
		var node: Node2D = _buildings.building(_id(CONSUMERS[at]))
		assert_that(node.modulate).is_equal(before[at])
		assert_that(node.self_modulate).is_equal(Color.WHITE)
	assert_str(HealthBarLayer.LOW_GLYPH.resource_path).is_equal(
		"res://assets/art/svg/icons/glyph_low_power.svg"
	)
	assert_that(_bars.low_power_color).is_equal(DANGER)
	await await_idle_frame()
	assert_int(_bars.drawn_glyphs()).is_equal(CONSUMERS.size())


## The power the local player's consumers use together, by `PowerConsumers`.
func _consumed(snap: MatchSnapshot) -> int:
	var sum: int = 0
	for row: int in snap.unit_count():
		if snap.owner[row] == PLAYER and PowerConsumers.is_consumer(snap, row):
			sum -= snap.type_power[snap.type_index[row]]
	return sum


## Sets the local player's published power.
func _power(made: int, used: int) -> void:
	_runner.snapshot.power_made[PLAYER] = made
	_runner.snapshot.power_used[PLAYER] = used


func _frame() -> void:
	_units._process(0.0)
	_buildings._process(0.0)
	_bars._process(0.0)


func _id(row: int) -> int:
	return _runner.snapshot.unit_id[row]
