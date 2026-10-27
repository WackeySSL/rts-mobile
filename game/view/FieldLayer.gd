class_name FieldLayer
extends TileMapLayer
## The oil and gas fields on the ground (ADR 0023 sections 2 and 11, STYLE.md "Fields", plan P116),
## a child of the `GroundLayer`, which hands it the page. A field is a group of ore cells joined
## side to side or corner to corner (`snap.ore_cell`, fixed for the match), numbered by its lowest
## cell: the field of `MapDef.field_kinds` (plan P79). Each shows a stage tile over its `ore`
## ground: full above two thirds of `ore_cell_max`, half above one third, else dry. A stage is
## written only when it changes, on a new tick. One wellhead stands on the cell nearest the middle
## of each field (the lowest of equals) with its cast shadow, in `Props` at z 1: all the shadows,
## then all the bodies.

const Z_PROPS: int = 1  ## With the decals: over the ground, under the unit shadows (2).
const STAGE_NONE: int = 255

## The kind of field number `field` (its place in `fields()`, the numbering of
## `MapDef.field_kinds`), `&"oil"` or `&"gas"`. Every field is oil until the map data names its
## kinds (plan P79), which is this one place to change:
## `StringName(kinds[field]) if field < kinds.size() else &"oil"`.
var kind_of: Callable = func(_field: int) -> StringName: return &"oil"

var _art: GroundAtlas
var _props: Node2D = Node2D.new()
var _ore_max: int = 1
var _cols: int = 1
var _kind: PackedByteArray = PackedByteArray()  ## Per ore cell: the index into KINDS.
var _stage_at: Array[Vector2i] = []  ## The tile of each kind and stage, `kind * 3 + stage`.
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
	_stage_at.clear()
	for kind: StringName in GroundAtlas.KINDS:
		for stage: StringName in GroundAtlas.STAGES:
			_stage_at.append(art.coords(StringName("%s_%s" % [kind, stage])))
	var cells: PackedInt32Array = snap.ore_cell
	_kind.resize(cells.size())
	_stage.resize(cells.size())
	_stage.fill(STAGE_NONE)
	_fields = _group(cells)
	_wellheads.clear()
	for number: int in _fields.size():
		var kind: int = maxi(GroundAtlas.KINDS.find(kind_of.call(number)), 0)
		for index: int in _fields[number]:
			_kind[index] = kind
		_wellheads.append(_middle(cells, _fields[number]))
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
	var cells: PackedInt32Array = snap.ore_cell
	var amounts: PackedInt32Array = snap.ore_amount
	var stages: int = GroundAtlas.STAGES.size()
	for index: int in mini(cells.size(), amounts.size()):
		var stage: int = stage_of(amounts[index], _ore_max)
		if stage != _stage[index]:
			_stage[index] = stage
			set_cell(_at(cells[index]), 0, _stage_at[_kind[index] * stages + stage])
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


## The groups of ore cells `cells` (ascending) joined side to side or corner to corner, as
## `MapDef.field_kinds` counts fields (plan P79). A group's first member is its lowest cell, and the
## groups follow in the order of their lowest cells.
func _group(cells: PackedInt32Array) -> Array[PackedInt32Array]:
	var index_of: Dictionary[int, int] = {}
	for index: int in cells.size():
		index_of[cells[index]] = index
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(cells.size())
	var groups: Array[PackedInt32Array] = []
	for first: int in cells.size():
		if seen[first] == 1:
			continue
		seen[first] = 1
		var members: PackedInt32Array = PackedInt32Array([first])
		var head: int = 0
		while head < members.size():
			var cell: int = cells[members[head]]
			var column: int = cell % _cols
			head += 1
			for across: int in range(-1, 2):
				if column + across < 0 or column + across >= _cols:  # No wrap to another row.
					continue
				for down: int in range(-1, 2):
					var next: int = index_of.get(cell + down * _cols + across, -1)
					if next >= 0 and seen[next] == 0:
						seen[next] = 1
						members.append(next)
		groups.append(members)
	return groups


## The cell of `field` (ore indexes into `cells`) nearest the mean of its cells, in integers.
func _middle(cells: PackedInt32Array, field: PackedInt32Array) -> int:
	var sum: Vector2i = Vector2i.ZERO
	for index: int in field:
		sum += _at(cells[index])
	var best: int = -1
	var best_gap: int = 0
	for index: int in field:
		var cell: int = cells[index]
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
