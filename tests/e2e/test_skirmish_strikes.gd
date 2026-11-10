extends GdUnitTestSuite
## Phase 3 end to end, each strike once (plan row P94, ADR 0023 section 10): in its full match the
## scripted player of `skirmish_player.gd` builds its faction's strike building, waits for the
## charge with its army at the staging point, and fires one SUPERWEAPON at the dummy's base. The
## Derrick League's Deep Bore ruptures the Lumen Accord's base after its delay; the Lumen Accord's
## Dusk Array takes the Derrick League's buildings offline at once. The rows are looked at
## before and after the steps that matter (`BaseArena.snap`, taken by `skirmish_match.gd` for each
## tick from the one before the order to the end of the effect), and every number (ticks, radius,
## damage, percents) is read from the data files and the World's tables, so a retune moves no case.
## The strike rules on hand-built Worlds are test_strike_rupture's and test_strike_blackout's, the
## base arena's two scenario strikes are test_base_arena_strikes'; what is new here is that a
## player's Command, in a match that goes on to a result, does the same.

const BaseArena: GDScript = preload("res://tests/sim/support/base_arena.gd")
const Match: GDScript = preload("res://tests/e2e/support/skirmish_match.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
## The faction whose strike building is a rupture, and the one whose is a blackout.
const RUPTURE: String = "fossil"
const BLACKOUT: String = "renew"


func before() -> void:
	for faction: String in [RUPTURE, BLACKOUT]:
		Match.played(self, faction, SimImpls.Impl.GDSCRIPT)


## One SUPERWEAPON in the log, the player's, naming the strike building and the point the script
## chose; the sim took it (nothing dropped) and the building charges again from that step.
func test_each_side_fires_its_strike_building_once_and_it_starts_charging_again() -> void:
	for faction: String in [RUPTURE, BLACKOUT]:
		var played: Match.Played = _played(faction)
		var fired: Array[Command] = []
		for command: Command in played.commands():
			if command.type == Command.Type.SUPERWEAPON:
				fired.append(command)
		assert_int(fired.size()).override_failure_message(faction).is_equal(1)
		var order: Command = fired[0]
		var tick: int = played.player.strike_tick
		assert_array([order.player_id, order.tick, order.target_id]).is_equal(
			[1, tick, played.player.strike_id]
		)
		assert_array([order.target_x, order.target_y]).is_equal(
			[played.player.strike_point.x, played.player.strike_point.y]
		)
		var before: BaseArena.Snap = played.snaps[tick]
		var after: BaseArena.Snap = played.snaps[tick + 1]
		var row: int = before.row_of(order.target_id)
		var type: int = before.type_index[row]
		var strike_kind: int = played.world.type_strike_kind[type]
		assert_int(strike_kind).override_failure_message(faction).is_greater(0)
		# Charged: ready at the stamp of the order or earlier, and not by a think's span (the script
		# fires on the first think it can: the first one at which the building has charged and the
		# army stands at the staging point, `stage_tick` the first think of the latter). Then the
		# clock starts again from the order's step.
		var ready: int = before.ready_tick[row]
		assert_int(tick + 1).override_failure_message(faction).is_greater_equal(ready)
		# The army must have stood at the staging point (the strike waits for it). Since ADR 0033
		# (P195d-2) the ties of targeting, formation and the flow field go by the half-turn rules, the
		# fights on the way differ from the old scan-order ones, and a squad of the army can fall
		# before it arrives: the script then trains and sends a replacement, so the staging comes
		# later than the charge and `possible` is the later of the two.
		assert_int(played.player.stage_tick).override_failure_message(faction).is_greater_equal(0)
		var possible: int = maxi(ready, played.player.stage_tick + 1)
		assert_int(tick + 1 - possible).override_failure_message(faction).is_less(15)
		var charge: int = played.world.type_charge_ticks[type]
		assert_int(after.ready_tick[after.row_of(order.target_id)]).is_equal(tick + 1 + charge)
		assert_int(after.dropped).override_failure_message(faction).is_equal(0)
		assert_int(played.world.dropped_commands).is_equal(0)
	assert_int(_kind(RUPTURE)).is_equal(Strike.Kind.RUPTURE)
	assert_int(_kind(BLACKOUT)).is_equal(Strike.Kind.BLACKOUT)


## The Deep Bore: the player's pending strike is written in the order's step and lands on exactly
## the tick the delay says, and that step takes the weapon's damage times the armour percent from
## every row within the radius of the point, whoever owns it, and from no row outside it.
func test_the_deep_bore_lands_on_its_tick_and_hits_every_row_within_its_radius() -> void:
	var played: Match.Played = _played(RUPTURE)
	var world: World = played.world
	var tick: int = played.player.strike_tick
	var type: int = world.type_ids.find(_strike_id(RUPTURE))
	var landing: int = tick + 1 + world.type_strike_delay[type]
	var point: Vector2i = played.player.strike_point
	assert_int(played.snaps[tick].strike_tick[1]).is_equal(0)
	assert_int(played.snaps[tick + 1].strike_tick[1]).is_equal(landing)
	assert_int(played.snaps[landing - 1].strike_tick[1]).is_equal(landing)
	assert_int(played.snaps[landing].strike_tick[1]).is_equal(0)
	assert_array([world.strike_x[1], world.strike_y[1]]).is_equal([point.x, point.y])
	var weapon: int = world.type_strike_weapon[type]
	var reach: int = world.type_strike_radius[type]
	var before: BaseArena.Snap = played.snaps[landing - 1]
	var after: BaseArena.Snap = played.snaps[landing]
	var hit: int = 0
	var hit_buildings: int = 0
	var own_hit: int = 0
	var problems: Array[String] = []
	for row: int in before.ids.size():
		var id: int = before.ids[row]
		var dx: int = before.pos_x[row] - point.x
		var dy: int = before.pos_y[row] - point.y
		var armour: int = world.type_armour[before.type_index[row]]
		var percent: int = world.weapon_vs_armour[weapon * World.Armour.size() + armour]
		var loss: int = 0
		if dx * dx + dy * dy <= reach * reach and percent > 0:
			loss = maxi(1, world.weapon_damage[weapon] * percent / Combat.PERCENT)
		var left: int = before.hp[row] - loss
		var now: int = after.row_of(id)
		if left <= 0 and now >= 0:
			problems.append("id %d survived with %d" % [id, after.hp[now]])
		elif left > 0 and (now < 0 or after.hp[now] != left):
			problems.append("id %d: %d expected, %d" % [id, left, after.hp[now] if now >= 0 else 0])
		if loss > 0:
			hit += 1
			hit_buildings += 1 if world.type_foot_w[before.type_index[row]] > 0 else 0
			own_hit += 1 if before.owner[row] == 1 else 0
	assert_array(problems).is_empty()
	# Not vacuous: a building and a fighter or two of the dummy, and none of the player's own.
	assert_int(hit_buildings).is_greater_equal(1)
	assert_int(hit).is_greater_equal(3)
	assert_int(own_hit).is_equal(0)
	assert_int(world.match_end_tick).is_greater(landing)


## The Dusk Array: at once, in the order's step, every building of the other side within the
## radius is offline until the stamp plus the length, the player's own buildings and every building
## outside the radius are not, and the dummy's power falls by exactly what those buildings made and
## used. It covers the turrets (the point is chosen for them), so something armed goes dark.
func test_the_blackout_takes_the_dummys_buildings_in_its_radius_offline_at_once() -> void:
	var played: Match.Played = _played(BLACKOUT)
	var world: World = played.world
	var tick: int = played.player.strike_tick
	var type: int = world.type_ids.find(_strike_id(BLACKOUT))
	var until: int = tick + 1 + world.type_strike_ticks[type]
	var reach: int = world.type_strike_radius[type]
	var point: Vector2i = played.player.strike_point
	var before: BaseArena.Snap = played.snaps[tick]
	var after: BaseArena.Snap = played.snaps[tick + 1]
	var hit: int = 0
	var armed: int = 0
	var lost_made: int = 0
	var lost_used: int = 0
	for row: int in after.ids.size():
		var kind: int = after.type_index[row]
		var dx: int = after.pos_x[row] - point.x
		var dy: int = after.pos_y[row] - point.y
		var goes_dark: bool = (
			world.type_foot_w[kind] > 0
			and after.owner[row] != 1
			and dx * dx + dy * dy <= reach * reach
		)
		var label: String = "id %d" % after.ids[row]
		assert_int(after.offline_until[row]).override_failure_message(label).is_equal(
			until if goes_dark else 0
		)
		if goes_dark:
			hit += 1
			armed += 1 if world.type_weapon[kind] >= 0 else 0
			lost_made += maxi(world.type_power[kind], 0)
			lost_used += maxi(-world.type_power[kind], 0)
	for row: int in before.ids.size():
		assert_int(before.offline_until[row]).is_equal(0)
	assert_int(hit).is_greater_equal(3)
	assert_int(armed).is_greater_equal(2)
	assert_int(after.power_made[2]).is_equal(before.power_made[2] - lost_made)
	assert_int(after.power_used[2]).is_equal(before.power_used[2] - lost_used)
	assert_array([after.power_made[1], after.power_used[1]]).is_equal(
		[before.power_made[1], before.power_used[1]]
	)


## An offline defence keeps its target but does not shoot: no building of the dummy that went dark
## fires from the order's step until the step before the one that brings it back, and the
## turrets that lived to see it end fire again, so the silence was the blackout's.
func test_no_dark_turret_fires_until_the_blackout_ends_and_it_fires_after() -> void:
	var played: Match.Played = _played(BLACKOUT)
	var world: World = played.world
	var tick: int = played.player.strike_tick
	var type: int = world.type_ids.find(_strike_id(BLACKOUT))
	var until: int = tick + 1 + world.type_strike_ticks[type]
	var after: BaseArena.Snap = played.snaps[tick + 1]
	var dark: Dictionary[int, bool] = {}
	for row: int in after.ids.size():
		if after.offline_until[row] == until and world.type_weapon[after.type_index[row]] >= 0:
			dark[after.ids[row]] = true
	assert_int(dark.size()).is_greater_equal(2)
	var silent: int = 0
	var loud_after: int = 0
	for shot: Vector2i in played.building_shots:
		if not dark.has(shot.y):
			continue
		# The step that makes World tick t has the stamp t: dark while tick + 1 <= t < until.
		if shot.x > tick and shot.x < until:
			silent += 1
		elif shot.x >= until:
			loud_after += 1
	assert_int(silent).is_equal(0)
	assert_int(loud_after).is_greater(0)


func _played(faction: String) -> Match.Played:
	return Match.played(self, faction, SimImpls.Impl.GDSCRIPT)


## The strike kind of the type that `faction` builds.
func _kind(faction: String) -> int:
	var world: World = _played(faction).world
	return world.type_strike_kind[world.type_ids.find(_strike_id(faction))]


func _strike_id(faction: String) -> StringName:
	return (_played(faction).player.ROLES as Dictionary)[faction]["strike"]
