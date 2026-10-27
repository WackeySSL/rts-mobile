extends GdUnitTestSuite
## The two strikes of the base arena (plan row P80, ADR 0023 sections 10 and 14): each side's
## scenario SUPERWEAPON order fires the strike building of its faction once, inside the 900-tick
## run, on a tick that the charge has ended by (the scenario starts the building
## `charge_elapsed_ticks` into its charge of `charge_ticks`, see test_spawn_charge_elapsed). The
## Derrick League's Deep Bore ruptures the Lumen Accord's base and the Lumen Accord's Blackout
## Array takes the Derrick League's buildings offline. The arena is played to the end of the
## blackout (a few ticks past the 900) in the GDScript phases and in the C++ kernels; rows are
## counted before and after the strikes, never time. Every number (ticks, radius, damage, percents)
## is read from the data files and the World's tables, so a retune moves no case; the 900-tick part
## is test_base_arena_run's.

const BaseArena: GDScript = preload("res://tests/sim/support/base_arena.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const HashReport: GDScript = preload("res://tests/sim/support/hash_report.gd")

## What the cases read from the scenario's two SUPERWEAPON orders and their buildings' data.
var _fire: Dictionary[int, int] = {}
var _point: Dictionary[int, Vector2i] = {}
var _def: Dictionary[int, BuildingDef] = {}
var _gd: BaseArena.Run
var _native: BaseArena.Run


func before() -> void:
	var scenario: ScenarioDef = load(BaseArena.PATH) as ScenarioDef
	for order: OrderDef in scenario.orders:
		if order.type == Command.Type.SUPERWEAPON:
			_fire[order.player] = order.tick
			_point[order.player] = order.target_tile * World.MILLI_PER_TILE + Vector2i(500, 500)
			_def[order.player] = order.unit as BuildingDef
	var ticks: Array = [0]
	for player: int in _fire:
		ticks.append_array(_watch_ticks(player))
	_gd = BaseArena.play(SimImpls.Impl.GDSCRIPT, _end_tick(), ticks)
	_native = BaseArena.play(SimImpls.Impl.NATIVE, _end_tick(), ticks)


func test_each_side_fires_its_strike_building_once_and_no_command_is_dropped() -> void:
	assert_array(_fire.keys()).is_equal([1, 2])
	assert_int(_def[1].strike_kind).is_equal(Strike.Kind.RUPTURE)
	assert_int(_def[2].strike_kind).is_equal(Strike.Kind.BLACKOUT)
	for run: BaseArena.Run in [_gd, _native]:
		assert_array(run.problems).is_empty()
		for player: int in [1, 2]:
			var before: BaseArena.Snap = run.snaps[_fire[player]]
			var after: BaseArena.Snap = run.snaps[_fire[player] + 1]
			var row: int = before.ids.find(_building(before, player))
			# Charged by the order's tick, and charging again right after (ready_tick moved up).
			assert_int(before.ready_tick[row]).is_less_equal(_fire[player] + 1)
			assert_int(after.ready_tick[row]).is_equal(
				_fire[player] + 1 + _def[player].charge_ticks
			)
			assert_int(after.dropped).is_equal(0)
		assert_int(run.world.dropped_commands).is_equal(0)
		assert_int(run.world.match_end_tick).is_equal(0)
		assert_array(Array(run.world.defeated_tick)).is_equal([0, 0, 0])


## The rupture writes the player's pending strike when it is fired, lands on exactly `strike_tick`
## and takes the weapon's damage times the armour percent from every row within the radius of the
## point (squared distances), whoever owns it, and from no row outside it.
func test_the_rupture_lands_on_its_tick_and_hits_every_row_within_its_radius() -> void:
	var def: BuildingDef = _def[1]
	var landing: int = _fire[1] + 1 + def.strike_delay
	for run: BaseArena.Run in [_gd, _native]:
		var world: World = run.world
		var fired: BaseArena.Snap = run.snaps[_fire[1] + 1]
		var before: BaseArena.Snap = run.snaps[landing - 1]
		var after: BaseArena.Snap = run.snaps[landing]
		assert_int(fired.strike_tick[1]).is_equal(landing)
		assert_int(before.strike_tick[1]).is_equal(landing)
		assert_int(after.strike_tick[1]).is_equal(0)
		assert_int(world.strike_x[1]).is_equal(_point[1].x)
		assert_int(world.strike_y[1]).is_equal(_point[1].y)
		var weapon: int = world.type_strike_weapon[world.type_ids.find(def.type_id)]
		var reach: int = world.type_strike_radius[world.type_ids.find(def.type_id)]
		var hit: int = 0
		var hit_buildings: int = 0
		var problems: Array[String] = []
		for row: int in before.ids.size():
			var id: int = before.ids[row]
			var dx: int = before.pos_x[row] - _point[1].x
			var dy: int = before.pos_y[row] - _point[1].y
			var inside: bool = dx * dx + dy * dy <= reach * reach
			var armour: int = world.type_armour[before.type_index[row]]
			var percent: int = world.weapon_vs_armour[weapon * World.Armour.size() + armour]
			var loss: int = 0
			if inside and percent > 0:
				loss = maxi(1, world.weapon_damage[weapon] * percent / Combat.PERCENT)
			var left: int = before.hp[row] - loss
			var now: int = after.row_of(id)
			if left <= 0 and now >= 0:
				problems.append("id %d survived with %d" % [id, after.hp[now]])
			elif left > 0 and (now < 0 or after.hp[now] != left):
				problems.append(
					"id %d: %d expected, %d" % [id, left, after.hp[now] if now >= 0 else 0]
				)
			hit += 1 if loss > 0 else 0
			hit_buildings += 1 if loss > 0 and world.type_foot_w[before.type_index[row]] > 0 else 0
		assert_array(problems).is_empty()
		# Not vacuous: the point is over the Lumen Accord's refinery, with its neighbours.
		assert_int(hit).is_greater_equal(3)
		assert_int(hit_buildings).is_greater_equal(1)


## The blackout needs no warning: in the step that applies the order every building of another
## owner within the radius is offline until the stamp plus `strike_ticks`, the firing player's own
## buildings and every building outside the radius are not, and the power use of the blacked-out
## player falls for exactly that long.
func test_the_blackout_lands_at_once_for_the_enemy_buildings_within_its_radius() -> void:
	var def: BuildingDef = _def[2]
	var until: int = _fire[2] + 1 + def.strike_ticks
	for run: BaseArena.Run in [_gd, _native]:
		var world: World = run.world
		var before: BaseArena.Snap = run.snaps[_fire[2]]
		var after: BaseArena.Snap = run.snaps[_fire[2] + 1]
		var reach: int = world.type_strike_radius[world.type_ids.find(def.type_id)]
		var hit: int = 0
		for row: int in after.ids.size():
			var type: int = after.type_index[row]
			var dx: int = after.pos_x[row] - _point[2].x
			var dy: int = after.pos_y[row] - _point[2].y
			var hits: bool = (
				world.type_foot_w[type] > 0
				and after.owner[row] != 2
				and dx * dx + dy * dy <= reach * reach
			)
			var label: String = "id %d" % after.ids[row]
			assert_int(after.offline_until[row]).override_failure_message(label).is_equal(
				until if hits else 0
			)
			hit += 1 if hits else 0
		for row: int in before.ids.size():
			assert_int(before.offline_until[row]).is_equal(0)
		assert_int(hit).is_greater_equal(3)
		# The blacked-out buildings use no power while it lasts (the plants are out of reach of the
		# point, so the output stays): the use of player 1 is lower until the stamp that reaches
		# `until`, and the firing player's totals do not move.
		assert_int(run.snaps[until - 1].power_used[1]).is_less(before.power_used[1])
		assert_int(run.snaps[until].power_used[1]).is_equal(before.power_used[1])
		assert_int(after.power_used[2]).is_equal(before.power_used[2])
		assert_int(after.power_made[2]).is_equal(before.power_made[2])


func test_the_kernels_and_the_twins_agree_through_both_strikes() -> void:
	assert_array(Array(_native.replay.checkpoint_ticks)).is_equal(
		Array(_gd.replay.checkpoint_ticks)
	)
	assert_array(Array(_native.replay.checkpoint_hashes)).is_equal(
		Array(_gd.replay.checkpoint_hashes)
	)
	assert_int(_native.replay.final_hash).is_equal(_gd.replay.final_hash)
	assert_str(HashReport.mismatch(_native.world, _gd.world)).is_empty()
	for tick: int in _gd.snaps:
		var left: BaseArena.Snap = _gd.snaps[tick]
		var right: BaseArena.Snap = _native.snaps[tick]
		assert_array(Array(right.hp)).override_failure_message(str(tick)).is_equal(Array(left.hp))
		assert_array(Array(right.offline_until)).is_equal(Array(left.offline_until))
	for phase: int in SimImpls.EXPECTED_PHASES:
		assert_bool(SimImpls.is_native(_native.world, phase)).is_true()
		assert_bool(SimImpls.is_native(_gd.world, phase)).is_false()


## The World ticks to look at for `player`'s strike, after the step that reaches them: just before
## and after the order, and for a rupture just before and after the landing, for a blackout just
## before and after it ends.
func _watch_ticks(player: int) -> Array:
	var def: BuildingDef = _def[player]
	var fire: int = _fire[player]
	var found: Array = [fire, fire + 1]
	if def.strike_kind == Strike.Kind.RUPTURE:
		var landing: int = fire + 1 + def.strike_delay
		found.append_array([landing - 1, landing])
	else:
		var until: int = fire + 1 + def.strike_ticks
		found.append_array([until - 1, until])
	return found


## The step count that ends the latest thing watched.
func _end_tick() -> int:
	var last: int = 0
	for player: int in _fire:
		last = maxi(last, _watch_ticks(player).max())
	return last


## The id of `player`'s row in `snap` whose type is the strike building of the order.
func _building(snap: BaseArena.Snap, player: int) -> int:
	var type: int = _gd.world.type_ids.find(_def[player].type_id)
	for row: int in snap.ids.size():
		if snap.owner[row] == player and snap.type_index[row] == type:
			return snap.ids[row]
	return 0
