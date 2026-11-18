class_name TutorialConditions
extends RefCounted
## The conditions that end a tutorial beat (ADR 0044 section 2, plan row P541): pure checks of a
## `TutorialContext` (the snapshot, the selection, `HudState`, the camera, the placement and strike
## modes) against a beat's parameters. They read, never write, and keep no state: what a check
## compares with from before the beat (the camera) is in `start`, the context taken when the beat's
## prompt showed. A condition of a sim row never matches before the snapshot has one.
##
## Parameters per kind (`TutorialBeatDef`): `type_id` names a type (any when empty), `count` a
## number, `area` a tile rectangle, `value` one int.
## - NEXT: never true here; the player's Next ends it (`TutorialDirector.next`).
## - SELECTED: at least `count` selected rows of `type_id` (any type when empty).
## - UNITS_IN_AREA: at least `count` own units of `type_id` with their centre in `area`.
## - BUILDING_PLACED: at least `count` own buildings of `type_id`, finished or not.
## - BUILDING_DONE: the same, finished.
## - OWN_AT_LEAST: at least `count` own rows of `type_id` (a trained unit is one more row).
## - HARVESTED: the player has harvested at least `count` credits.
## - ENEMY_LOSSES: the other players have lost at least `count` units and buildings together.
## - ZOOM_LEVEL: the camera's nearest zoom level is `value`.
## - CAMERA_PANNED: the camera's centre moved at least `count` world px since `start`, at the zoom
##   it had then (a pinch about a point also moves the centre, and does not count).
## - UNFOLD_OPEN: the open `HudState.Unfold` is `value`.
## - DRAWER_TAB: the drawer is open on tab `value`.
## - PLACING: a placement of `type_id` (any when empty) is on.
## - STRIKE_AIMED: the strike aim is on with a point set.
## - STRIKE_PENDING: the player's strike is in flight.
## - GROUP_SAVED: control group `value` holds at least `count` units.
## - MATCH_WON: the match ended with the local player the winner.
## Append only: the values are stored in `data/tutorial/*.tres`.
enum Kind {
	NEXT,
	SELECTED,
	UNITS_IN_AREA,
	BUILDING_PLACED,
	BUILDING_DONE,
	OWN_AT_LEAST,
	HARVESTED,
	ENEMY_LOSSES,
	ZOOM_LEVEL,
	CAMERA_PANNED,
	UNFOLD_OPEN,
	DRAWER_TAB,
	PLACING,
	STRIKE_AIMED,
	STRIKE_PENDING,
	GROUP_SAVED,
	MATCH_WON,
}

## The kinds that only the sim's ticks can make true: a beat that pauses the match cannot use them.
const NEEDS_TICKS: Array[Kind] = [
	Kind.UNITS_IN_AREA,
	Kind.BUILDING_PLACED,
	Kind.BUILDING_DONE,
	Kind.OWN_AT_LEAST,
	Kind.HARVESTED,
	Kind.ENEMY_LOSSES,
	Kind.STRIKE_PENDING,
	Kind.MATCH_WON,
]


## Whether only ticks of the sim can make `kind` true.
static func needs_ticks(kind: Kind) -> bool:
	return NEEDS_TICKS.has(kind)


## Whether the beat's condition holds in `ctx`; `start` is the context from when the beat showed.
static func check(beat: TutorialBeatDef, ctx: TutorialContext, start: TutorialContext) -> bool:
	var snap: MatchSnapshot = ctx.snapshot
	match beat.kind:
		Kind.ZOOM_LEVEL:
			return ctx.zoom_level == beat.value
		Kind.CAMERA_PANNED:
			return (
				is_equal_approx(ctx.camera_zoom, start.camera_zoom)
				and ctx.camera_centre.distance_to(start.camera_centre) >= float(beat.count)
			)
		Kind.UNFOLD_OPEN:
			return ctx.hud != null and int(ctx.hud.current) == beat.value
		Kind.DRAWER_TAB:
			return (
				ctx.hud != null
				and ctx.hud.is_open(HudState.Unfold.DRAWER)
				and ctx.drawer_tab == beat.value
			)
		Kind.STRIKE_AIMED:
			return ctx.strike_aiming and ctx.strike_has_point
		Kind.GROUP_SAVED:
			return ctx.selection != null and ctx.selection.group_size(beat.value) >= beat.count
		Kind.NEXT:
			return false
	if snap == null or snap.type_ids.is_empty():
		return false
	var type: int = _type_of(snap, beat.type_id)
	match beat.kind:
		Kind.SELECTED:
			return ctx.selection != null and _selected(snap, ctx.selection, type) >= beat.count
		Kind.UNITS_IN_AREA:
			return _own(snap, ctx.local_player, type, 0, beat.area) >= beat.count
		Kind.BUILDING_PLACED:
			return _own(snap, ctx.local_player, type, 1, Rect2i()) >= beat.count
		Kind.BUILDING_DONE:
			return _own(snap, ctx.local_player, type, 2, Rect2i()) >= beat.count
		Kind.OWN_AT_LEAST:
			return _own(snap, ctx.local_player, type, 3, Rect2i()) >= beat.count
		Kind.HARVESTED:
			return _at(snap.stat_harvested, ctx.local_player) >= beat.count
		Kind.ENEMY_LOSSES:
			return _enemy_losses(snap, ctx.local_player) >= beat.count
		Kind.PLACING:
			return ctx.placement_type >= 0 and (type == -1 or ctx.placement_type == type)
		Kind.STRIKE_PENDING:
			return _at(snap.strike_tick, ctx.local_player) > 0
		Kind.MATCH_WON:
			return snap.match_end_tick > 0 and snap.winner == ctx.local_player
	return false


## The type index of `id`, -1 for any type (empty id), -2 for an id the roster lacks (matches none).
static func _type_of(snap: MatchSnapshot, id: StringName) -> int:
	if id == &"":
		return -1
	var found: int = snap.type_ids.find(id)
	return found if found >= 0 else -2


static func _at(column: PackedInt32Array, player: int) -> int:
	return column[player] if player >= 0 and player < column.size() else 0


## Selected rows of `type` (any type when -1).
static func _selected(snap: MatchSnapshot, selection: SelectionModel, type: int) -> int:
	var found: int = 0
	for id: int in selection.selected:
		var row: int = snap.index_of(id)
		if row >= 0 and (type == -1 or snap.type_index[row] == type):
			found += 1
	return found


## The player's rows of `type` (any when -1) by `mode`: 0 units in `area` (tiles), 1 buildings,
## 2 finished buildings, 3 any row.
static func _own(snap: MatchSnapshot, player: int, type: int, mode: int, area: Rect2i) -> int:
	var found: int = 0
	for row: int in snap.unit_count():
		var kind: int = snap.type_index[row]
		if snap.owner[row] != player or (type != -1 and kind != type):
			continue
		var building: bool = snap.type_foot_w[kind] > 0
		if mode == 0 and (building or not _in_area(snap, row, area)):
			continue
		if mode >= 1 and mode <= 2 and not building:
			continue
		if mode == 2 and snap.build_left[row] > 0:
			continue
		found += 1
	return found


static func _in_area(snap: MatchSnapshot, row: int, area: Rect2i) -> bool:
	var tile: Vector2i = Vector2i(
		snap.pos_x[row] / Sim.MILLI_PER_TILE, snap.pos_y[row] / Sim.MILLI_PER_TILE
	)
	return area.has_point(tile)


## Units and buildings lost by every player but the local one and neutral.
static func _enemy_losses(snap: MatchSnapshot, local: int) -> int:
	var lost: int = 0
	for player: int in range(1, snap.stat_lost_units.size()):
		if player != local:
			lost += snap.stat_lost_units[player] + _at(snap.stat_lost_buildings, player)
	return lost
