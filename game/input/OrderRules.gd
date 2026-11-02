class_name OrderRules
extends RefCounted
## What the selection and the orders make of a published snapshot (ADR 0019 section 3, plan P87).
## Pure and static: it reads a `MatchSnapshot` and answers; it selects nothing and sends nothing,
## `PlayerController` does both with its answers. It holds the army filter ("All army" and a box
## leave tankers out, a box of tankers alone keeps them), the building a ground tap sets a rally
## point for, and whether a tap is on a field. A tanker is a unit whose type has a harvest capacity
## (`type_harvest`, the sim's own test), so what the player calls a tanker and the sim calls a
## harvester are one thing. Every answer is a guard against a snapshot a test built by hand: a type
## or a column that is not there is not a tanker and not a producer.


## Whether type `type` is a tanker: it loads oil or gas and takes the harvest order.
static func is_tanker(snap: MatchSnapshot, type: int) -> bool:
	return type >= 0 and type < snap.type_harvest.size() and snap.type_harvest[type] > 0


## "All army": the ids of `player`'s units that can move and are not tankers, ascending. A building
## never moves, so it is never in it.
static func all_army(snap: MatchSnapshot, player: int) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	var speeds: PackedInt32Array = snap.type_speed
	for row: int in snap.unit_count():
		var type: int = snap.type_index[row]
		if snap.owner[row] == player and speeds[type] > 0 and not is_tanker(snap, type):
			ids.append(snap.unit_id[row])
	return ids


## The units a box selects: `found` (the own units whose centres lie in it) without its tankers
## when it holds any other unit, and as it is when it holds tankers alone, or none.
static func box_selection(snap: MatchSnapshot, found: PackedInt32Array) -> PackedInt32Array:
	var kept: PackedInt32Array = PackedInt32Array()
	for id: int in found:
		if not _is_tanker_id(snap, id):
			kept.append(id)
	return found if kept.is_empty() else kept


## Whether `ids` is a selection of tankers and nothing else (an empty one is not).
static func only_tankers(snap: MatchSnapshot, ids: PackedInt32Array) -> bool:
	for id: int in ids:
		if not _is_tanker_id(snap, id):
			return false
	return not ids.is_empty()


## The id of the building a ground tap gives a rally point: the selection is that one building,
## `player`'s own, and it produces infantry or vehicles. 0 for any other selection, a Headquarters
## included (it produces structures, which are placed, so the sim refuses its rally: `Outcome`).
static func rally_building(snap: MatchSnapshot, ids: PackedInt32Array, player: int) -> int:
	if snap == null or ids.size() != 1:
		return 0
	var row: int = snap.index_of(ids[0])
	if row < 0 or snap.owner[row] != player:
		return 0
	var tab: int = produced_tab(snap, snap.type_index[row])
	return ids[0] if tab >= World.Tab.INFANTRY and tab < World.TABS else 0


## The tab that type `type` produces (a `World.Tab`), -1 for a type that produces nothing.
static func produced_tab(snap: MatchSnapshot, type: int) -> int:
	if type < 0 or type >= snap.type_produces.size():
		return -1
	return snap.type_produces[type]


## The tab that the building with id `id` produces, -1 for an id that is no row or produces none.
static func rally_tab(snap: MatchSnapshot, id: int) -> int:
	var row: int = snap.index_of(id)
	return produced_tab(snap, snap.type_index[row]) if row >= 0 else -1


## Whether the world point `world` (px) is on an oil or gas field, or within `reach` px of one: the
## diamond of any ore cell grown by `reach` along both of its half diagonals. A fingertip needs the
## room a unit's hit radius gives (48 dp across). Dry cells count: they are still the field; whether
## the sim would take the order is `ore_within`'s question, asked beside this one.
@warning_ignore("integer_division")
static func near_field(snap: MatchSnapshot, world: Vector2, reach: float) -> bool:
	var cols: int = snap.map_cols
	if cols <= 0:
		return false
	var across: float = IsoProjection.HALF_W + reach
	var down: float = IsoProjection.HALF_H + reach
	for cell: int in snap.ore_cell:
		var centre: Vector2 = IsoProjection.cell_centre_px(cell % cols, cell / cols)
		if absf(world.x - centre.x) / across + absf(world.y - centre.y) / down <= 1.0:
			return true
	return false


## Whether oil or gas is left for a HARVEST sent to the ground point `at` (milli-tiles): some ore
## cell with ore in it (`ore_amount` above 0) whose centre is within `pick_milli` of the point,
## which is the sim's own test (`Harvest._scan`: a box test, then the squared distance, both
## inclusive). The sim drops a HARVEST for which there is none, and the tankers would stand where
## they were, so the tap is a move then. `pick_milli` is `harvest_pick_milli` of the match's rules.
@warning_ignore("integer_division")
static func ore_within(snap: MatchSnapshot, at: Vector2i, pick_milli: int) -> bool:
	var cols: int = snap.map_cols
	var reach: int = maxi(pick_milli, 0)
	var amounts: PackedInt32Array = snap.ore_amount
	var cells: PackedInt32Array = snap.ore_cell
	if cols <= 0 or amounts.size() < cells.size():
		return false
	for index: int in cells.size():
		if amounts[index] <= 0:
			continue
		var dx: int = cells[index] % cols * World.MILLI_PER_TILE + World.TILE_CENTRE - at.x
		var dy: int = cells[index] / cols * World.MILLI_PER_TILE + World.TILE_CENTRE - at.y
		if absi(dx) <= reach and absi(dy) <= reach and dx * dx + dy * dy <= reach * reach:
			return true
	return false


static func _is_tanker_id(snap: MatchSnapshot, id: int) -> bool:
	var row: int = snap.index_of(id) if snap != null else -1
	return row >= 0 and is_tanker(snap, snap.type_index[row])
