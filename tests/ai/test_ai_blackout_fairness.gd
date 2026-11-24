extends GdUnitTestSuite
## ADR 0047 section 4 and 9 (plan row P576): a Dusk Array's vision cut takes from the AI victim
## exactly what it takes from a human. In a hand-built World with the real fog (the strike rig of
## `tests/sim/support/strike_worlds.gd`), player 2's shed alone sees player 1's tank. Before the
## strike the victim's `AiIntel` lists the tank; while the shed is cut they do not, and every id the
## lists hold stands in a cell the victim's fog shows. The AI has no handicap on top of that.

const Rig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")

var _world: World = null
var _intel: AiIntel = null
var _memory: AiMemory = null
var _tank: int = 0


func before_test() -> void:
	_world = Strikes.world(false)
	SimImpls.attach(_world, SimImpls.Impl.GDSCRIPT, SimProbe.Phase.FOG)
	_world.blackout_sight_cut = 1
	Strikes.run_to(_world, Strikes.fire_tick(_world, Strikes.ARRAY))
	_world.add_building(2, Strikes.type_of(_world, "shed"), 15, 10)
	_tank = Strikes.add(_world, 1, "tank", 17500, 10500)
	Strikes.stamp(_world)
	var def: OpponentDef = Rig.def_of("fossil")
	_intel = AiIntel.create(def, Rig.level_of("normal"), 2)
	_memory = AiMemory.create(def)


func test_the_victims_intel_loses_the_enemy_only_a_cut_building_saw() -> void:
	_refresh()
	assert_array(_seen()).contains([_tank])
	assert_int(PlayerView.of(_world, 2).row_of(_tank)).is_not_equal(PlayerView.MISSING)
	Strikes.step(_world, [Strikes.fire(Strikes.ARRAY)])
	for _step: int in 8:
		Strikes.step(_world)
	_refresh()
	assert_array(_seen()).not_contains([_tank])
	assert_int(PlayerView.of(_world, 2).row_of(_tank)).is_equal(PlayerView.MISSING)


func test_the_ai_reads_only_cells_its_fog_shows_before_and_during_the_cut() -> void:
	for fired: bool in [false, true]:
		if fired:
			Strikes.step(_world, [Strikes.fire(Strikes.ARRAY)])
			for _step: int in 8:
				Strikes.step(_world)
		_refresh()
		for id: int in _seen():
			var row: int = _world.index_of(id)
			assert_bool(Targeting.sees(_world, 2, _world.pos_x[row], _world.pos_y[row])).is_true()
		for id: int in _memory.seen_site_id:
			var row: int = _world.index_of(id)
			assert_bool(Targeting.sees(_world, 2, _world.pos_x[row], _world.pos_y[row])).is_true()


func _refresh() -> void:
	var view: PlayerView = PlayerView.of(_world, 2)
	_memory.commands_left = 8
	_intel.refresh(view, _memory)
	_intel.run(view, _memory, DetRandom.create(1, DetRandom.STREAM_AI_BASE + 2), [])


## The enemy units the lists hold (the rig's tank has no weapon, so intel lists it as a tanker).
func _seen() -> Array[int]:
	var ids: Array[int] = []
	ids.append_array(_memory.seen_unit_id)
	ids.append_array(_memory.seen_mobile_id)
	return ids
