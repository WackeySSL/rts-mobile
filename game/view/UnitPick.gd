class_name UnitPick
extends RefCounted
## The picking side of the `UnitLayer`: which units are shown, where a unit is on screen and what
## the Picker reads of every unit (`PickSnapshot`). Static and stateless: the layer passes its rigs,
## sheets and snapshot in, and keeps the public entry points that call these (P307, split from the
## layer so that the picking rules grow here).


## Whether unit row `row` of `runner.snapshot` is drawn: an own unit always, an enemy one when its
## tile is visible to the local player (the tile from `snapshot.cell_of`, at the unit's position
## in the tick) or `reveal_enemies` is set. Both are read at the call, nothing is cached. Like
## `hit_time_ms` it does not sync, and a row out of range is not shown.
static func is_shown(runner: MatchRunner, reveal_enemies: bool, row: int) -> bool:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null or row < 0 or row >= snap.owner.size():
		return false
	var player: int = FogLayer.local_player_of(runner)
	return (
		reveal_enemies
		or snap.owner[row] == player
		or FogLayer.is_seen(snap, player, snap.pos_x[row], snap.pos_y[row])
	)


## Fills `snap` for the Picker with every unit in row order: id, owner, type, centre on screen
## (base px) and hit radius, the larger of `min_radius_px` and the horizontal semi-axis of the
## type's selection ellipse at the camera zoom. The centre is the lifted one of ADR 0023 section 3:
## the rig's ground point raised by the sheet's `pick_lift_px` (`SpriteLift.centre_lift_px`), at
## the camera zoom. An enemy that `is_shown` would not draw is filled like any other row, with its
## `pickable` entry 0, so the Picker skips it (P47p). The snapshot's arrays are resized in place,
## so refilling one allocates nothing. `UnitLayer.fill_pick_snapshot` syncs the rigs first and
## passes the `source` snapshot (null while there is none) with its `rigs` and `sheets`.
static func fill(
	snap: PickSnapshot,
	source: MatchSnapshot,
	layer: UnitLayer,
	rigs: Array[Node2D],
	sheets: Array[IsoSheetDef],
	min_radius_px: float
) -> void:
	var count: int = 0 if source == null else rigs.size()
	# Packed arrays are shared, not copied, by an assignment: the writes land in the PickSnapshot.
	var out_ids: PackedInt32Array = snap.ids
	var out_owners: PackedInt32Array = snap.owners
	var out_types: PackedInt32Array = snap.type_index
	var out_pos: PackedVector2Array = snap.screen_pos
	var out_lift: PackedFloat32Array = snap.lift_px
	var out_radius: PackedFloat32Array = snap.radius_px
	var out_pickable: PackedByteArray = snap.pickable
	var out_flyer: PackedByteArray = snap.flyer
	out_ids.resize(count)
	out_owners.resize(count)
	out_types.resize(count)
	out_pos.resize(count)
	out_lift.resize(count)
	out_radius.resize(count)
	out_pickable.resize(count)
	out_flyer.resize(count)
	if count == 0:
		return
	var ids: PackedInt32Array = source.unit_id
	var owners: PackedInt32Array = source.owner
	var types: PackedInt32Array = source.type_index
	var radii: PackedInt32Array = source.type_selection_radius
	var armours: PackedInt32Array = source.type_armour
	var camera: RtsCamera = layer.camera
	var runner: MatchRunner = layer.runner
	var zoom: float = camera.zoom.x
	# `is_shown`'s rule with the arrays aliased: an enemy is hidden when the tile of its position in
	# this tick (`snapshot.cell_of`) is not visible to the local player.
	var pos_x: PackedInt32Array = source.pos_x
	var pos_y: PackedInt32Array = source.pos_y
	var player: int = FogLayer.local_player_of(runner)
	var fog: FogGrid = source.fog
	var fogged: bool = not layer.reveal_enemies and FogLayer.covers(fog, player)
	var counts: PackedInt32Array = fog.visible
	var counts_at: int = (player - 1) * fog.cells
	for row: int in count:
		var type: int = types[row]
		var art_px: float = IsoProjection.ellipse_px(radii[type]).x * zoom
		out_ids[row] = ids[row]
		out_owners[row] = owners[row]
		out_types[row] = type
		var lift: float = 0.0  # A building's row is not picked here: P115b picks it on its silhouette.
		if rigs[row] != null:
			var armour: int = armours[type] if type < armours.size() else World.Armour.LIGHT
			lift = SpriteLift.centre_lift_px(sheets[row], armour)
		out_pos[row] = camera.world_to_screen(
			row_position(layer, runner, rigs, row) - Vector2(0.0, lift)
		)
		out_lift[row] = lift * zoom
		out_radius[row] = maxf(min_radius_px, art_px)
		var seen: bool = not fogged or owners[row] == player
		if not seen:
			seen = counts[counts_at + source.cell_of(pos_x[row], pos_y[row])] > 0
		out_pickable[row] = 1 if seen and rigs[row] != null else 0
		# A flyer has no rig here: `AirLayer.fill_pick_snapshot` lifts it and makes it pickable.
		out_flyer[row] = 1 if rigs[row] == null and WorldSort.is_flyer(source, type) else 0


## Where row `row` is in world px: its rig's place, or its position for a row with no rig.
static func row_position(
	layer: UnitLayer, runner: MatchRunner, rigs: Array[Node2D], row: int
) -> Vector2:
	if rigs[row] != null:
		return rigs[row].global_position
	var snap: MatchSnapshot = runner.snapshot
	return layer.to_global(IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row]))
