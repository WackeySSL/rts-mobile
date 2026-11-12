extends GdUnitTestSuite
## What EffectsLayer makes of the DIED flag (plan P272, ADR 0037 section 3, `Removal.died_flag`):
## 1 (a cancelled site), 2 (a boarding) and 3 (a sold building) burst nothing, 0 bursts as any
## death. A sold building packs up in `BuildingCollapse`, which test_sale_collapse.gd tests.

const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Rig: GDScript = preload("res://tests/view/support/effects_rig.gd")
const PLACE: Vector2i = Vector2i(15000, 8000)

var _now_ms: int = 0
var _runner: MatchRunner
var _layer: EffectsLayer
var _building: int = 0


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))
	_now_ms = 0
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = Rig.battle()
	_runner.start()
	_layer = auto_free(EffectsLayer.new())
	_layer.runner = _runner
	_layer.reveal_enemies = true
	_layer.clock = func() -> int: return _now_ms
	add_child(_layer)
	_layer.set_process(false)
	_building = _runner.snapshot.type_ids.find(&"rifle_squad")
	_runner.snapshot.type_armour[_building] = World.Armour.BUILDING


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func _died(flag: int) -> void:
	var events: PackedInt32Array = Rig.died(PLACE, _building)
	events[Removal.DIED_FLAG_AT] = flag
	_runner.snapshot.events = events
	_runner.ticked.emit(_runner.snapshot.tick)
	_layer._process(0.0)
	_now_ms += 1000


func test_a_cancelled_a_boarded_and_a_sold_building_burst_nothing() -> void:
	for flag: int in [Removal.FLAG_CANCELLED, Removal.FLAG_BOARDED, Removal.FLAG_SOLD]:
		_died(flag)
		assert_int(_layer.quad_count()).override_failure_message("flag %d" % flag).is_equal(0)


func test_a_death_with_no_flag_bursts() -> void:
	_died(0)
	assert_int(_layer.quad_count()).is_equal(1)
