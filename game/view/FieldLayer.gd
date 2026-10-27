class_name FieldLayer
extends TileMapLayer
## The oil and gas fields on the ground (ADR 0023 sections 2 and 11, STYLE.md "Fields", plan P116),
## a child of the `GroundLayer`, which hands it the page. A field is a group of edge-adjacent ore
## cells (`snap.ore_cell`, fixed for the match). Each shows a stage tile over its `ore` ground: full
## above two thirds of `ore_cell_max`, half above one third, else dry. A stage is written only when
## it changes, on a new tick. One wellhead stands on the cell nearest the middle of each field (the
## lowest of equals) with its cast shadow, in `Props` at z 1: all the shadows, then all the bodies.

const Z_PROPS: int = 1  ## With the decals: over the ground, under the unit shadows (2).
const STAGE_NONE: int = 255

## The kind of a field, `&"oil"` or `&"gas"`, from its lowest cell. Every field is oil until the
## map data names its kinds (`MapDef.field_kinds`, plan P79): the one place to change then.
var kind_of: Callable = func(_first_cell: int) -> StringName: return &"oil"

var _art: GroundAtlas
var _props: Node2D = Node2D.new()
var _ore_max: int = 1
var _cols: int = 1
var _kind: PackedByteArray = PackedByteArray()  ## Per ore cell: the index into KINDS.
var _stage: PackedByteArray = PackedByteArray()  ## Per ore cell: the stage drawn or STAGE_NONE.
var _fields: Array[PackedInt32Array] = []  ## Per field: its ore indexes, the lowest first.
var _wellheads: PackedInt32Array = PackedInt32Array()  ## Per field: the cell of its wellhead.
var _tick: int = -1
var _writes: int = 0


func _init() -> void:
	_props.name = "Props"
	_props.z_index = Z_PROPS
	_props.z_as_relative = false
	add_child(_props)


## The stage of a cell with `amount` of at most `most`: 0 full, 1 half, 2 dry (an index into
## STAGES), by integer thirds: full above two thirds, half above one third.
static func stage_of(amount: int, most: int) -> int:
	if amount * 3 > most * 2:
		return 0
	return 1 if amount * 3 > most else 2


## Starts a match on the page `art`: the fields of `snap`, their wellheads and every stage.
func begin(snap: MatchSnapshot, art: GroundAtlas, most: int) -> void:
	_art = art
	_ore_max = maxi(most, 1)
	_cols = maxi(snap.map_cols, 1)
	tile_set = art.tile_set
	clear()
	for prop: Node in _props.get_children():
		prop.free()
	_kind.resize(snap.ore_cell.size())
	_stage.resize(snap.ore_cell.size())
	_stage.fill(STAGE_NONE)
	_fields = _group(snap)
	_wellheads.clear()
	for field: PackedInt32Array in _fields:
		var kind: int = maxi(GroundAtlas.KINDS.find(kind_of.call(snap.ore_cell[field[0]])), 0)
		for index: int in field:
			_kind[index] = kind
		_wellheads.append(_middle(snap, field))
	for prop: StringName in [GroundAtlas.WELLHEAD_SHADOW, GroundAtlas.WELLHEAD]:
		for cell: int in _wellheads:
			_stand(prop, cell)
	_tick = -1
	update(snap)


## Brings the stage tiles up to `snap`; nothing while its tick is the one drawn.
func update(snap: MatchSnapshot) -> void:
	if snap.tick == _tick:
		return
	_tick = snap.tick
	for index: int in mini(snap.ore_cell.size(), snap.ore_amount.size()):
		var stage: int = stage_of(snap.ore_amount[index], _ore_max)
		if stage != _stage[index]:
			_stage[index] = stage
			var key: String = "%s_%s" % [GroundAtlas.KINDS[_kind[index]], GroundAtlas.STAGES[stage]]
			set_cell(_at(snap.ore_cell[index]), 0, _art.coords(StringName(key)))
			_writes += 1


## Stage tiles written so far: every ore cell once, then only the changes.
func write_count() -> int:
	return _writes


## Per field its ore indexes (into `ore_cell`), the lowest first, in the order of the lowest cells.
func fields() -> Array[PackedInt32Array]:
	return _fields


## The cell of each field's wellhead, in the order of `fields()`.
func wellhead_cells() -> PackedInt32Array:
	return _wellheads


@warning_ignore("integer_division")
func _at(cell: int) -> Vector2i:
	return Vector2i(cell % _cols, cell / _cols)


## The edge-adjacent groups of ore cells. `ore_cell` ascends, so a group's first member is its
## lowest cell.
func _group(snap: MatchSnapshot) -> Array[PackedInt32Array]:
	var index_of: Dictionary[int, int] = {}
	for index: int in snap.ore_cell.size():
		index_of[snap.ore_cell[index]] = index
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(snap.ore_cell.size())
	var groups: Array[PackedInt32Array] = []
	for first: int in snap.ore_cell.size():
		if seen[first] == 1:
			continue
		seen[first] = 1
		var members: PackedInt32Array = PackedInt32Array([first])
		var head: int = 0
		while head < members.size():
			var cell: int = snap.ore_cell[members[head]]
			head += 1
			var west: int = cell - 1 if cell % _cols > 0 else -1  # No wrap to the row above.
			var east: int = cell + 1 if cell % _cols < _cols - 1 else -1
			for next_cell: int in [west, east, cell - _cols, cell + _cols]:
				var next: int = index_of.get(next_cell, -1)
				if next >= 0 and seen[next] == 0:
					seen[next] = 1
					members.append(next)
		groups.append(members)
	return groups


## The cell of `field` nearest the mean of its cells, compared in integers.
func _middle(snap: MatchSnapshot, field: PackedInt32Array) -> int:
	var sum: Vector2i = Vector2i.ZERO
	for index: int in field:
		sum += _at(snap.ore_cell[index])
	var best: int = -1
	var best_gap: int = 0
	for index: int in field:
		var cell: int = snap.ore_cell[index]
		var off: Vector2i = _at(cell) * field.size() - sum
		var gap: int = off.x * off.x + off.y * off.y
		if best < 0 or gap < best_gap or (gap == best_gap and cell < best):
			best = cell
			best_gap = gap
	return best


## One sprite of `prop` hung by its anchor on the centre of `cell`.
func _stand(prop: StringName, cell: int) -> void:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = _art.texture()
	sprite.region_enabled = true
	sprite.region_rect = Rect2(_art.region(prop))
	sprite.centered = false
	sprite.offset = -GroundAtlas.ANCHORS[prop]
	sprite.position = map_to_local(_at(cell))
	_props.add_child(sprite)
