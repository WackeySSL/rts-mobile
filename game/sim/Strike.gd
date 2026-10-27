class_name Strike
extends RefCounted
## Superweapons (ADR 0023 section 10, plan rows P110 and P111): the charge of a strike building, the
## SUPERWEAPON command and the Deep Bore's rupture. The Blackout Array's effect is P111's: until it
## lands, a SUPERWEAPON of a blackout building is dropped and counted, as the whole command was
## before this row.
##
## Ticks. "Stamp" is `world.tick + 1`, the tick the step in progress produces (the stamp
## `defeated_tick` and `match_end_tick` carry). A command is applied in the step of its own `tick`.
##
## The charge. A strike building (`type_strike_kind` above 0) starts charging when it is placed:
## `start_charge`, called by `Buildings.add` for a PLACE and for a scenario's building alike, sets
## its `ready_tick` to stamp + `type_charge_ticks`. It may fire once the stamp reaches `ready_tick`,
## so a SUPERWEAPON of tick `t + type_charge_ticks` is the first one accepted for a building placed
## in tick `t` (and for one fired in tick `t`), and not a tick earlier. Low power does not pause it.
##
## SUPERWEAPON (`apply_superweapon`, after `Sim._apply`'s playing gate: a defeated player, and every
## command once the match has ended, are dropped before it). Valid when all of these hold, else
## dropped and counted:
## - the payload is empty;
## - the player has no rupture pending (its `strike_tick` is 0): one pending strike per player is
##   all the state there is, so a further SUPERWEAPON of any kind waits for the landing (lead
##   decision of 2026-10-26, an ADR 0023 section 10 note);
## - `target_id` is a row of the player's own whose type is a strike building: kind RUPTURE, the one
##   kind with a rule yet;
## - it has charged (the stamp is `ready_tick` or more) and is not offline (`offline_until` is
##   not above the stamp; P111 writes it, a blacked-out building is back at that stamp).
## A valid RUPTURE writes the player's pending strike: the point, clamped to the map as RALLY clamps
## its point (so that the squared distances of the landing stay small and the point fits its
## int32 column), and `strike_tick = stamp + type_strike_delay`. It sets the building's `ready_tick`
## to stamp + `type_charge_ticks`. A delay of 0 lands in the same step, right after FIRE's shots.
##
## The rupture (`run`, called by `Sim.step` right after `Combat.fire` and before `FogUpdate.begin`
## and `World.remove_dead`, inside the FIRE mark: no new phase, no second `remove_dead`). For every
## player ascending whose pending strike is due (`strike_tick` set and not above the stamp; equal in
## play, the "not above" only keeps a hand-built World from waiting for ever), the strike clears
## (`strike_tick` 0; the point stays, for the view's crater) and every row whose position is within
## the radius of the point, own rows and neutral ones included, by squared distance and in ascending
## row order, loses the weapon's damage times its percent against the row's armour, like a shot
## (`Combat.fire`: at least 1, none when the percent is 0). The rows only lose `hp` here and die at
## this tick's REMOVE, exactly as a row killed by a shot: `FogUpdate.begin` has run, so the unstamp
## lands in the owner's dirty list of this tick, ECONOMY's `Power.run` sums power without them,
## PRODUCTION's `Outcome.run` sees a ruptured producer gone, so its kills count for defeat on the
## same tick, and no ruptured row takes part in the next tick. A rupture in the air is not recalled
## by the loss of its building, a surrender or a defeat of its player.
##
## Which strike: the pending strike stores no type (ADR 0023 section 10's layout), so the landing
## reads the radius and the weapon from `rupture_type`, the first type of kind RUPTURE. The shipped
## rosters have one; a roster with two rupture types with different numbers needs a state column
## (and the re-pin of exception 10) first.
##
## Event cadence. `run` costs the loop over the players on a tick with no strike due, and one pass
## over the rows per landing, over aliased arrays and with no allocation. Integers only, every
## number from the type and weapon tables. No kernel mirrors it (ADR 0023 section 10).

## The strike kinds, as `type_strike_kind` and BuildingDef.strike_kind hold them.
enum Kind { NONE = 0, RUPTURE = 1, BLACKOUT = 2 }


## Starts the charge of the new building row `row`: `ready_tick` is the stamp plus its type's
## `type_charge_ticks`. A row whose type is no strike building keeps 0. `Buildings.add` calls it
## once the row exists.
static func start_charge(world: World, row: int) -> void:
	var type: int = world.type_index[row]
	if type < mini(world.type_strike_kind.size(), world.type_charge_ticks.size()):
		if world.type_strike_kind[type] > Kind.NONE:
			world.ready_tick[row] = world.tick + 1 + world.type_charge_ticks[type]


## SUPERWEAPON: true when the command fired the player's strike building (see the header for the
## rules and what a rupture writes). A kind without a rule yet (the blackout, P111) is dropped.
static func apply_superweapon(world: World, command: Command) -> bool:
	var player: int = command.player_id
	var pending: PackedInt32Array = world.strike_tick
	if not command.payload.is_empty() or player >= pending.size() or pending[player] != 0:
		return false
	var row: int = world.index_of(command.target_id)
	if row < 0 or world.owner[row] != player:
		return false
	var type: int = world.type_index[row]
	var stamp: int = world.tick + 1
	if type >= world.type_strike_kind.size() or type >= world.type_charge_ticks.size():
		return false
	if stamp < world.ready_tick[row] or world.offline_until[row] > stamp:
		return false
	if world.type_strike_kind[type] != Kind.RUPTURE:
		return false
	world.strike_x[player] = clampi(command.target_x, 0, maxi(world.map_w - 1, 0))
	world.strike_y[player] = clampi(command.target_y, 0, maxi(world.map_h - 1, 0))
	pending[player] = stamp + world.type_strike_delay[type]
	world.ready_tick[row] = stamp + world.type_charge_ticks[type]
	return true


## The rupture, in FIRE after the shots (see the header): lands the pending strike of every player
## whose turn has come, players ascending.
static func run(world: World) -> void:
	var pending: PackedInt32Array = world.strike_tick
	var stamp: int = world.tick + 1
	for player: int in range(1, pending.size()):
		if pending[player] != 0 and pending[player] <= stamp:
			_land(world, player)


## The type the landing reads its radius and weapon from: the lowest type index of kind RUPTURE,
## -1 when the World has none.
static func rupture_type(world: World) -> int:
	var kinds: PackedInt32Array = world.type_strike_kind
	for type: int in kinds.size():
		if kinds[type] == Kind.RUPTURE:
			return type
	return -1


## One landing: clears the player's pending strike and hits the rows around its point. A World with
## no rupture type, or one whose type has no weapon (-1) or a weapon past the tables, hits nothing.
@warning_ignore("integer_division")
static func _land(world: World, player: int) -> void:
	var point_x: int = world.strike_x[player]
	var point_y: int = world.strike_y[player]
	world.strike_tick[player] = 0
	var type: int = rupture_type(world)
	if type < 0:
		return
	var weapon: int = world.type_strike_weapon[type]
	if weapon < 0 or weapon >= world.weapon_damage.size():
		return
	var radius: int = world.type_strike_radius[type]
	var reach: int = radius * radius
	var damage: int = world.weapon_damage[weapon]
	var percents: int = weapon * World.Armour.size()
	var percent_of: PackedInt32Array = world.weapon_vs_armour
	var armour_of: PackedInt32Array = world.type_armour
	var types: PackedInt32Array = world.type_index
	var pos_x: PackedInt32Array = world.pos_x
	var pos_y: PackedInt32Array = world.pos_y
	var hit_points: PackedInt32Array = world.hp
	for row: int in hit_points.size():
		var dx: int = pos_x[row] - point_x
		var dy: int = pos_y[row] - point_y
		if dx * dx + dy * dy > reach:
			continue
		var percent: int = percent_of[percents + armour_of[types[row]]]
		if percent > 0:
			hit_points[row] -= maxi(1, damage * percent / Combat.PERCENT)
