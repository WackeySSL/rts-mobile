extends RefCounted
## The scripted player of the Phase 3 end-to-end matches (plan row P94). Not a test suite.
##
## It plays player 1 of a Kestrel Flats Skirmish against the dummy of the other side, through
## Commands only (CLAUDE.md rule 4): it never writes to the World, and it hands each Command to
## `CommandQueue.submit`, as the HUD does. It reads the World through `PlayerView` (its own rows and
## queues, the enemy rows its fog shows, the placement answer, the map size from which it knows the
## enemy base stands at the half turn of its own) except for two things that it takes from the World
## itself: the charge of its strike building, and the enemy rows that a strike is aimed by.
##
## The plan, the same for both sides with the faction's own ids (`ROLES`):
## - Structures, one at a time down the single STRUCTURES queue: a power plant, a refinery, the
##   radar, the strike building, a second power plant and the barracks, each queued when the queue
##   is empty, its requirement stands and the credits cover it, and placed on the first slot of a
##   spiral round the Headquarters that `PlayerView.placement` accepts. The structure path is the
##   one the UI uses on `main` today (ADR 0026's old path: QUEUE, then PLACE with no type); the two
##   steps are `_queue_structure` and `_place_head`, so the row that retires the old path (P131)
##   changes only them.
## - Army: once the barracks stands, rifle squads up to `ESCORT` (the two it starts with count) and
##   rocket squads up to `ROCKETS`. The rockets hurt buildings, the rifles kill the enemy's own
##   rifle squads.
## - Staging: the whole army walks to a point `STAGE_TILES` from the enemy Headquarters, out of
##   its turrets' reach.
## - The strike: when the army stands at the staging point and the strike building has charged, it
##   fires at the enemy building with the most enemy rows within the strike's radius.
## - The assault: once the strike is fired and a rupture has landed (a blackout works at once),
##   the rifles go after the enemy's fighters that they see and the rockets after its buildings
##   (armed ones first, then the producers), each group attack-moving to the enemy Headquarters
##   while it sees nothing to go after.

const PLAYER: int = 1
const ENEMY: int = 2
## The script thinks when `tick % PERIOD == OFFSET`: the dummy of player 2 thinks at 7.
const PERIOD: int = 15
const OFFSET: int = 3
## Rifle squads and rocket squads that make the army.
const ESCORT: int = 6
const ROCKETS: int = 12
## How far from the enemy Headquarters the army stages (tiles), and how close to the point each
## unit must stand for the army to count as there (milli-tiles).
const STAGE_TILES: int = 14
const STAGE_REACH: int = 4000
## The strike is aimed within this many tiles of the enemy Headquarters, and an armed row counts
## this much in the aim.
const AIM_WINDOW: int = 12
const ARMED_WEIGHT: int = 3
## The attack-move to the enemy Headquarters is sent again after this many thinks.
const RESEND_THINKS: int = 8
## The spiral round the Headquarters, as the dummy's: slots a lattice stride apart.
const PLACE_TRIES: int = 64
const PLACE_STRIDE: int = 4
## The structures in the order the script builds them, by role (a key of `ROLES`).
const BUILD_ORDER: Array[String] = ["power", "refinery", "radar", "strike", "power", "barracks"]
## Per faction id: the types the script builds and trains by role.
const ROLES: Dictionary[String, Dictionary] = {
	"fossil":
	{
		"hq": &"headquarters",
		"power": &"power_plant",
		"refinery": &"refinery",
		"radar": &"fossil_radar",
		"strike": &"fossil_strike",
		"barracks": &"barracks",
		"rifle": &"rifle_squad",
		"rocket": &"rocket_squad",
	},
	"renew":
	{
		"hq": &"renew_hq",
		"power": &"renew_power",
		"refinery": &"renew_refinery",
		"radar": &"renew_radar",
		"strike": &"renew_strike",
		"barracks": &"renew_barracks",
		"rifle": &"renew_rifle",
		"rocket": &"renew_rocket",
	},
}

## What happened, for a failure message: "tick text" lines in order.
var events: Array[String] = []
## The tick of the SUPERWEAPON, -1 until it is sent, the point it was aimed at, and the tick of the
## step from which its effect stands (a blackout: the same tick's step, a rupture: its landing).
var strike_tick: int = -1
var strike_point: Vector2i = Vector2i(-1, -1)
var strike_effect_tick: int = -1
## The id of the strike building that was fired.
var strike_id: int = 0

var _roles: Dictionary = {}
var _list: Array[StringName] = []
var _next: int = 0
var _spiral: PackedInt32Array = PlacementSpiral.cells(PLACE_TRIES)
var _staged: bool = false
var _foe: int = 0
var _building: int = 0
var _resend_tick: int = -100000


## A player of the faction `faction` (`fossil` or `renew`).
func _init(faction: String) -> void:
	_roles = ROLES[faction]
	for role: String in BUILD_ORDER:
		_list.append(_roles[role])


## How many structures the script builds.
static func structures() -> int:
	return BUILD_ORDER.size()


## The Commands of the tick that `world` is about to step, appended to `out`: none unless it is
## this player's turn.
func think(world: World, out: Array[Command]) -> void:
	if world.match_end_tick > 0 or world.tick % PERIOD != OFFSET:
		return
	var view: PlayerView = PlayerView.of(world, PLAYER)
	if view.structure_ready():
		_place_head(view, out)
	else:
		_queue_next(view, out)
	_train(view, out)
	_march(view, out)
	_strike(world, view, out)
	_assault(view, out)


## The row of the player's complete strike building, -1 for none.
func strike_row(world: World) -> int:
	var type: int = world.type_ids.find(_roles["strike"])
	for row: int in world.unit_count():
		if world.owner[row] == PLAYER and world.type_index[row] == type:
			return row if world.build_left[row] == 0 else -1
	return -1


# --- Structures ---


## The next structure of the list, when the STRUCTURES queue is empty, its requirement stands and
## the credits cover it.
func _queue_next(view: PlayerView, out: Array[Command]) -> void:
	if _next >= _list.size() or view.queue_count[PlayerView.Tab.STRUCTURES] > 0:
		return
	var type: int = view.type_index_of(_list[_next])
	if view.credits < view.type_cost[type] or not _owns(view, view.type_requires[type]):
		return
	_queue_structure(type, out)
	_note(view.tick, "queue %s" % _list[_next])
	_next += 1


## QUEUE of a structure (the old path: the item is paid and built, then placed).
func _queue_structure(type: int, out: Array[Command]) -> void:
	out.append(Command.queue(PLAYER, type))


## PLACE of the built head of the STRUCTURES queue on the first slot of the spiral that the
## placement rule accepts.
func _place_head(view: PlayerView, out: Array[Command]) -> void:
	var head: int = view.queue_type[PlayerView.Tab.STRUCTURES * view.queue_slots]
	var centre: Vector2i = _origin_of(view, view.type_index_of(_roles["hq"]))
	for step: int in PLACE_TRIES:
		var col: int = centre.x + _spiral[step * 2] * PLACE_STRIDE
		var line: int = centre.y + _spiral[step * 2 + 1] * PLACE_STRIDE
		if view.placement(head, col, line) == Placement.Reason.OK:
			out.append(
				Command.place(
					PLAYER,
					col * PlayerView.MILLI_PER_TILE + PlayerView.TILE_CENTRE,
					line * PlayerView.MILLI_PER_TILE + PlayerView.TILE_CENTRE
				)
			)
			_note(view.tick, "place at %d,%d" % [col, line])
			return


# --- Army ---


## Rifle squads, then rocket squads, while the barracks stands: two items in the queue at most,
## and what is queued counts as had.
func _train(view: PlayerView, out: Array[Command]) -> void:
	if not _owns(view, view.type_index_of(_roles["barracks"])):
		return
	var rifle: int = view.type_index_of(_roles["rifle"])
	var rocket: int = view.type_index_of(_roles["rocket"])
	var queued: int = view.queue_count[PlayerView.Tab.INFANTRY]
	var have: Dictionary[int, int] = {rifle: 0, rocket: 0}
	for role: String in ["rifle", "rocket"]:
		have[view.type_index_of(_roles[role])] = _ids_of(view, role).size()
	for slot: int in queued:
		var item: int = view.queue_type[PlayerView.Tab.INFANTRY * view.queue_slots + slot]
		have[item] = have.get(item, 0) + 1
	var budget: int = view.credits
	while queued < 2:
		var type: int = rifle if have[rifle] < ESCORT else rocket
		if type == rocket and have[rocket] >= ROCKETS:
			return
		if budget < view.type_cost[type]:
			return
		budget -= view.type_cost[type]
		have[type] += 1
		queued += 1
		out.append(Command.queue(PLAYER, type))


## The army walks to the staging point once it is whole.
func _march(view: PlayerView, out: Array[Command]) -> void:
	if (
		_staged
		or _ids_of(view, "rifle").size() < ESCORT
		or _ids_of(view, "rocket").size() < ROCKETS
	):
		return
	var stage: Vector2i = _stage_point(view)
	_staged = true
	out.append(Command.attack_move(PLAYER, _army(view), stage.x, stage.y))
	_note(view.tick, "army marches to %d,%d" % [stage.x, stage.y])


# --- The strike ---


## Fires the strike building once, when it has charged and the army is at the staging point.
func _strike(world: World, view: PlayerView, out: Array[Command]) -> void:
	var row: int = strike_row(world)
	if strike_tick >= 0 or row < 0 or not _staged or not _army_at_stage(view):
		return
	var type: int = world.type_index[row]
	if world.tick + 1 < world.ready_tick[row] or world.offline_until[row] > world.tick + 1:
		return
	var point: Vector2i = _aim(world, view, world.type_strike_radius[type])
	out.append(Command.superweapon(PLAYER, world.unit_id[row], point.x, point.y))
	strike_tick = world.tick
	strike_id = world.unit_id[row]
	strike_point = point
	strike_effect_tick = world.tick + 1
	if world.type_strike_kind[type] == Strike.Kind.RUPTURE:
		strike_effect_tick += world.type_strike_delay[type]
	_note(view.tick, "strike at %d,%d" % [point.x, point.y])


## The point (a tile centre, in milli-tiles) within `AIM_WINDOW` tiles of the enemy Headquarters
## whose circle of `radius` holds the most enemy rows by weight: an armed row (a turret or a unit
## with a weapon) counts `ARMED_WEIGHT`, any other building 1, a unit that is no fighter 0; the
## first of equals in row-major order wins. It reads the enemy rows off the World, as a player who
## had scouted the base would know them (the view shows only what the fog does).
func _aim(world: World, view: PlayerView, radius: int) -> Vector2i:
	var hq: Vector2i = _enemy_hq(view)
	var best: Vector2i = hq
	var best_score: int = -1
	var reach: int = radius * radius
	var low_x: int = maxi(hq.x / World.MILLI_PER_TILE - AIM_WINDOW, 0)
	var low_y: int = maxi(hq.y / World.MILLI_PER_TILE - AIM_WINDOW, 0)
	var high_x: int = mini(hq.x / World.MILLI_PER_TILE + AIM_WINDOW, view.map_cols - 1)
	var high_y: int = mini(hq.y / World.MILLI_PER_TILE + AIM_WINDOW, view.map_rows - 1)
	for tile_y: int in range(low_y, high_y + 1):
		for tile_x: int in range(low_x, high_x + 1):
			var at: Vector2i = Vector2i(
				tile_x * World.MILLI_PER_TILE + World.TILE_CENTRE,
				tile_y * World.MILLI_PER_TILE + World.TILE_CENTRE
			)
			var score: int = 0
			for row: int in world.unit_count():
				if world.owner[row] != ENEMY:
					continue
				var dx: int = world.pos_x[row] - at.x
				var dy: int = world.pos_y[row] - at.y
				if dx * dx + dy * dy <= reach:
					score += _weight(world, row)
			if score > best_score:
				best_score = score
				best = at
	return best


## What a row of the enemy is worth to a strike (see `_aim`).
func _weight(world: World, row: int) -> int:
	var type: int = world.type_index[row]
	if world.type_weapon[type] >= 0:
		return ARMED_WEIGHT
	return 1 if world.type_foot_w[type] > 0 else 0


# --- The assault ---


## After the strike has landed, the rifles go after the enemy's fighters and the rockets after its
## buildings, each group on what it sees, else both attack-move to the enemy Headquarters. An
## order is sent when the target changes and again every `RESEND_THINKS` thinks.
func _assault(view: PlayerView, out: Array[Command]) -> void:
	if strike_effect_tick < 0 or view.tick < strike_effect_tick:
		return
	var resend: bool = view.tick - _resend_tick >= RESEND_THINKS * PERIOD
	if resend:
		_resend_tick = view.tick
	var hq: Vector2i = _enemy_hq(view)
	var foe: int = _pick_target(view, false)
	var building: int = _pick_target(view, true)
	_order_group(view, "rifle", foe, hq, _foe != foe or resend, out)
	_order_group(view, "rocket", building, hq, _building != building or resend, out)
	_foe = foe
	_building = building


## Sends the units of the role `role` after `target` (an id, 0 for none seen) when `send`, or to
## attack-move to `goal` when there is none.
func _order_group(
	view: PlayerView, role: String, target: int, goal: Vector2i, send: bool, out: Array[Command]
) -> void:
	var ids: PackedInt32Array = _ids_of(view, role)
	if not send or ids.is_empty():
		return
	if target != 0:
		out.append(Command.attack(PLAYER, ids, target))
		_note(view.tick, "%s attack %d" % [role, target])
	else:
		out.append(Command.attack_move(PLAYER, ids, goal.x, goal.y))
		_note(view.tick, "%s attack-move to the enemy Headquarters" % role)


## The id of the seen enemy row to attack, 0 for none: with `buildings` the armed buildings first,
## then the producers (a site is none); else the fighting units. The first of equals by
## the corner of the map the army comes from.
func _pick_target(view: PlayerView, buildings: bool) -> int:
	var best: int = 0
	var best_key: int = 1 << 40
	for row: int in view.seen_rows:
		var type: int = view.row_type(row)
		if view.row_owner(row) != ENEMY or (view.type_foot_w[type] > 0) != buildings:
			continue
		var rank: int = 0
		if buildings and view.row_build_left(row) != 0:
			continue
		if view.type_weapon[type] < 0:
			rank = 1
			if not buildings or view.type_produces[type] < 0:
				continue
		var at: Vector2i = view.row_pos(row)
		var key: int = rank * (1 << 30) + at.x + at.y
		if key < best_key:
			best_key = key
			best = view.row_id(row)
	return best


# --- Helpers ---


## The ids of the own rows of the role `role` (a key of `ROLES`), ascending.
func _ids_of(view: PlayerView, role: String) -> PackedInt32Array:
	var type: int = view.type_index_of(_roles[role])
	var found: PackedInt32Array = PackedInt32Array()
	for row: int in view.own_rows:
		if view.row_type(row) == type:
			found.append(view.row_id(row))
	return found


## The army: every own rifle squad and rocket squad, ascending.
func _army(view: PlayerView) -> PackedInt32Array:
	var ids: PackedInt32Array = _ids_of(view, "rifle")
	ids.append_array(_ids_of(view, "rocket"))
	ids.sort()
	return ids


## Whether the player owns a complete building (or any row) of the type `type` (-1: none needed).
func _owns(view: PlayerView, type: int) -> bool:
	if type < 0:
		return true
	for row: int in view.own_rows:
		if view.row_type(row) == type and view.row_build_left(row) == 0:
			return true
	return false


## The top-left tile of the player's first building of the type `type`, else (0, 0).
@warning_ignore("integer_division")
func _origin_of(view: PlayerView, type: int) -> Vector2i:
	for row: int in view.own_rows:
		if view.row_type(row) == type:
			var at: Vector2i = view.row_pos(row)
			return Vector2i(
				(
					(at.x - view.type_foot_w[type] * PlayerView.TILE_CENTRE)
					/ PlayerView.MILLI_PER_TILE
				),
				(at.y - view.type_foot_h[type] * PlayerView.TILE_CENTRE) / PlayerView.MILLI_PER_TILE
			)
	return Vector2i.ZERO


## The enemy Headquarters' centre in milli-tiles: the half turn of the player's own (the two sides
## of both scenarios are a half turn of each other on the map).
func _enemy_hq(view: PlayerView) -> Vector2i:
	var hq: int = view.type_index_of(_roles["hq"])
	for row: int in view.own_rows:
		if view.row_type(row) == hq:
			var at: Vector2i = view.row_pos(row)
			return Vector2i(
				view.map_cols * PlayerView.MILLI_PER_TILE - at.x,
				view.map_rows * PlayerView.MILLI_PER_TILE - at.y
			)
	return Vector2i.ZERO


## The staging point: `STAGE_TILES` from the enemy Headquarters on the diagonal to the player's own.
func _stage_point(view: PlayerView) -> Vector2i:
	var enemy: Vector2i = _enemy_hq(view)
	var step: int = STAGE_TILES * PlayerView.MILLI_PER_TILE * 7071 / 10000
	return Vector2i(enemy.x - step, enemy.y - step)


## Whether every unit of the army stands within `STAGE_REACH` of the staging point.
func _army_at_stage(view: PlayerView) -> bool:
	var stage: Vector2i = _stage_point(view)
	var army: PackedInt32Array = _army(view)
	for id: int in army:
		var at: Vector2i = view.row_pos(view.row_of(id))
		var dx: int = at.x - stage.x
		var dy: int = at.y - stage.y
		if dx * dx + dy * dy > STAGE_REACH * STAGE_REACH:
			return false
	return not army.is_empty()


func _note(tick: int, text: String) -> void:
	events.append("%d %s" % [tick, text])
