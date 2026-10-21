extends GdUnitTestSuite
## The edges of what the fog hides (plan P47, fix round 1; the main cases are in test_fog_hiding.gd,
## which gdlint's limit of 20 public methods per file keeps full). Local player 2 on a map that is
## not square (the block of its grid starts at cells, and cols * cols is not cells), a neutral
## owner 0 (an enemy to the fog: hidden on an unseen tile, and a death there is not an own
## unit's), and a local player the fog has no grid for (nothing to hide behind: everything shows).
## Exact cases write the published snapshot's fog, positions and owners (allowed in SYNC, ADR 0012
## section 3). The runner is not in the tree; pixels cannot be read headless, so the cases read
## `UnitLayer.is_shown`, the rigs' `visible`, the projectile plan and the effect ring.
## On controls_test (Rig): blue light tanks (ids 1-30, rows 0-29), red ones (ids 31-40, rows 30-39).
## On EffectsRig.battle(): 40 x 24 tiles, tanks and rifle squads of both sides, player 2 from tile
## (26, 6), 18 tiles from player 1.

const Rig: GDScript = preload("res://tests/view/support/fog_rig.gd")
const EffectsRig: GDScript = preload("res://tests/view/support/effects_rig.gd")
## Milli-tile points on controls_test: a seen tile (tank 1's, tile (8, 18)) and an unseen one.
const SEEN: Vector2i = Vector2i(8500, 18500)
const DARK: Vector2i = Vector2i(40500, 40500)
## Milli-tile points on the battle map: a tile player 2 sees (its tank's, (26, 6)) and one it does
## not (26, 20), both well inside the map.
const RED_SEES: Vector2i = Vector2i(26500, 6500)
const RED_BLIND: Vector2i = Vector2i(26500, 20500)

var _runner: MatchRunner
var _units: UnitLayer
var _shells: ProjectileLayer
var _effects: EffectsLayer


func before_test() -> void:
	_build(Rig.scenario(1))


func after_test() -> void:
	CommandQueue.clear()


func test_player_2_on_a_map_that_is_not_square_hides_by_the_tile_of_its_own_block() -> void:
	var scenario: ScenarioDef = EffectsRig.battle()
	scenario.local_player = 2
	_build(scenario)
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(snap.fog.cells).is_equal(40 * 24)
	var hidden: int = 0
	var shown: int = 0
	for tick: int in 120:
		if tick % 10 == 0:
			_units._process(0.0)
			snap = _runner.snapshot  # The runner may publish another object each tick.
			for row: int in snap.owner.size():
				var cell: int = snap.cell_of(snap.pos_x[row], snap.pos_y[row])
				var expected: bool = snap.owner[row] == 2 or snap.fog.is_visible(2, cell)
				var text: String = "tick %d row %d" % [tick, row]
				assert_bool(_units.is_shown(row)).override_failure_message(text).is_equal(expected)
				assert_bool(_rig(row).visible).override_failure_message(text).is_equal(expected)
				if snap.owner[row] == 1:
					hidden += int(not expected)
					shown += int(expected)
		_runner.run_ticks(1)
	assert_int(hidden).is_greater(0)  # Player 1's units were out of sight at times,
	assert_int(shown).is_greater(0)  # and in sight at others: neither is a vacuous answer.


func test_a_projectile_on_the_map_that_is_not_square_follows_the_tile_of_player_2s_block() -> void:
	var scenario: ScenarioDef = EffectsRig.battle()
	scenario.local_player = 2
	_build(scenario)
	var snap: MatchSnapshot = _runner.snapshot
	assert_bool(FogLayer.is_seen(snap, 2, RED_SEES.x, RED_SEES.y)).is_true()
	assert_bool(FogLayer.is_seen(snap, 2, RED_BLIND.x, RED_BLIND.y)).is_false()
	_set_slot(0, 11, RED_SEES, RED_SEES + Vector2i(100, 0), 1)
	_set_slot(1, 12, RED_BLIND, RED_BLIND + Vector2i(100, 0), 1)
	_shells._process(0.0)
	assert_int(_shells.active_count()).is_equal(1)
	assert_int(_shells.quad_slot(0)).is_equal(0)


func test_a_neutral_rig_is_hidden_on_an_unseen_tile_and_shown_on_a_seen_one() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.owner[30] = 0  # Red tank 31 at tile (34, 10), unseen, with no owner.
	_units._process(0.0)
	assert_bool(_units.is_shown(30)).is_false()
	assert_bool(_rig(30).visible).is_false()
	assert_bool(_units.is_shown(31)).is_false()  # And an enemy of the player is hidden as before.
	Rig.set_seen(snap, 1, Vector2i(34, 10), true)
	_units._process(0.0)
	assert_bool(_units.is_shown(30)).is_true()
	assert_bool(_rig(30).visible).is_true()


func test_a_neutral_death_in_the_dark_shows_no_burst() -> void:
	_tick_with(EffectsRig.died(DARK, 0, 5, 0))
	assert_int(_effects.active_count()).is_equal(0)
	_tick_with(EffectsRig.died(SEEN, 0, 5, 0))  # In sight, a neutral one shows like any enemy's.
	assert_int(_effects.active_count()).is_equal(1)
	_tick_with(EffectsRig.died(DARK, 0, 6, 1))  # An own unit's shows wherever it died.
	assert_int(_effects.active_count()).is_equal(2)


func test_a_local_player_the_fog_has_no_grid_for_sees_everything_in_every_layer() -> void:
	_runner.scenario.local_player = 3  # Two players: the fog has no grid for a third.
	_units._process(0.0)
	for row: int in 40:
		assert_bool(_units.is_shown(row)).is_true()
		assert_bool(_rig(row).visible).is_true()
	_set_slot(0, 11, DARK, DARK + Vector2i(100, 0), 2)  # An enemy shell on an unseen tile.
	_shells._process(0.0)
	assert_int(_shells.active_count()).is_equal(1)
	_tick_with(EffectsRig.impact(DARK, 0))
	assert_int(_effects.active_count()).is_equal(1)
	_tick_with(EffectsRig.died(DARK, 0, 5, 2))
	assert_int(_effects.active_count()).is_equal(2)


func _build(scenario: ScenarioDef) -> void:
	for node: Variant in [_effects, _shells, _units, _runner]:
		if is_instance_valid(node):
			node.free()
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = scenario
	_runner.start()
	_units = auto_free(UnitLayer.new())
	_units.runner = _runner
	add_child(_units)
	_units.set_process(false)
	_shells = auto_free(ProjectileLayer.new())
	_shells.runner = _runner
	add_child(_shells)
	_shells.set_process(false)
	_effects = auto_free(EffectsLayer.new())
	_effects.runner = _runner
	_effects.clock = func() -> int: return 0  # Nothing expires between calls.
	add_child(_effects)
	_effects.set_process(false)


func _rig(row: int) -> Node2D:
	return _units.get_child(row) as Node2D


## Projectile slot `slot` live with id `id`, going from `from` to `to` (milli-tiles), in the
## published snapshot and in the previous tick.
func _set_slot(slot: int, id: int, from: Vector2i, to: Vector2i, owner_id: int = 1) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.proj_id[slot] = id
	snap.prev_proj_id[slot] = id
	snap.proj_owner[slot] = owner_id
	snap.proj_weapon[slot] = 0
	snap.prev_proj_x[slot] = from.x
	snap.prev_proj_y[slot] = from.y
	snap.proj_x[slot] = to.x
	snap.proj_y[slot] = to.y


## Delivers `events` as the events of a tick, the way the runner does, then plans a frame.
func _tick_with(events: PackedInt32Array) -> void:
	_runner.snapshot.events = events
	_runner.ticked.emit(_runner.snapshot.tick)
	_effects._process(0.0)
