class_name UnitLayer
extends Node2D
## Draws every unit of the runner's World as a rig: a Node2D with the Sprite2D layers Hull, Team
## and Turret (assets/art/STYLE.md, layer contract). It only reads the World (ADR 0003): each frame
## a rig stands at prev + (cur - prev) * runner.alpha() in px, and the layers turn toward the last
## direction the unit moved in (the gun follows the hull until a unit has a target). The turn is a
## view effect and never touches the World.
## Rigs are the children of this node in World row order, so rig `i` shows unit row `i`.
## A selected unit has a Ring as the first child of its rig, under the layers.

const ART_DIR: String = "res://assets/art/svg/units/"
const LAYER_FILES: Array[String] = ["hull", "team", "turret"]  ## Draw order, also the node names.
const TEAM_LAYER: int = 1  ## Index of "team" in LAYER_FILES.
const RING_PAD_MILLI: int = 50  ## The ring clears the selection radius by this much.
const RING_MIN_DP: float = 18.0

## Tint of the Team layer by owner id. Index 0 is neutral and also used for any owner past the end.
@export var team_colors: PackedColorArray = PackedColorArray(
	[Color("9AA5B1"), Color("2F80ED"), Color("E5484D")]
)
## How fast a hull turns, in radians per second.
@export var turn_rate: float = 12.0
@export var runner: MatchRunner
@export var camera: RtsCamera

var _world: World = null
var _rigs: Array[Node2D] = []
var _layers: Array[Sprite2D] = []  ## Hull, Team and Turret of rig `i` at 3i, 3i + 1 and 3i + 2.
var _heading: PackedFloat64Array = PackedFloat64Array()  ## Angle the layers show now.
var _aim: PackedFloat64Array = PackedFloat64Array()  ## Last movement direction. East is 0.
var _rings: Array[Ring] = []  ## Ring of row `i`, made the first time that unit is selected.
var _ringed: PackedInt32Array = PackedInt32Array()  ## Rows whose ring shows.
var _ring_zoom: float = 1.0  ## Camera zoom the rings are sized for.
var _dp_px: float = 1.0  ## Base px per dp, read when the selection or the window changes.


## A circle of `radius` world px with strokes of `unit` world px per dp, drawn on a change only.
class Ring:
	extends Node2D

	var radius: float = 0.0
	var unit: float = 1.0

	func _draw() -> void:
		var wide: float = (FeedbackStyle.STROKE_DP + FeedbackStyle.OUTLINE_DP) * unit
		draw_circle(Vector2.ZERO, radius, FeedbackStyle.OUTLINE, false, wide, true)
		draw_circle(Vector2.ZERO, radius, Color.WHITE, false, FeedbackStyle.STROKE_DP * unit, true)


func _ready() -> void:
	get_viewport().size_changed.connect(_resize_rings)
	_sync_rigs()


func _process(delta: float) -> void:
	if _sync_rigs():
		_update_rigs(delta)
		if not _ringed.is_empty() and camera.zoom.x != _ring_zoom:
			_refresh_rings()


func rig_count() -> int:
	return _rigs.size()


## Where unit row `index` is on screen, in base px.
func unit_screen_position(index: int) -> Vector2:
	return camera.world_to_screen(_rigs[index].global_position)


## Rings exactly the units in `ids` at once. Unknown ids are skipped.
func set_selected(ids: PackedInt32Array) -> void:
	if not _sync_rigs():
		return
	for row: int in _ringed:
		_rings[row].visible = false
	_ringed.clear()
	for id: int in ids:
		var row: int = _world.index_of(id)
		if row < 0:
			continue
		if _rings[row] == null:
			_rings[row] = Ring.new()
			_rings[row].name = "Ring"
			_rigs[row].add_child(_rings[row])
			_rigs[row].move_child(_rings[row], 0)
		_rings[row].visible = true
		_ringed.append(row)
	_resize_rings()


## Fills `snap` for the Picker with every unit in row order: id, owner, type, centre on screen (base
## px) and hit radius, the larger of `min_radius_px` and the type's selection radius at the camera
## zoom. The snapshot's arrays are resized in place, so refilling one allocates nothing.
func fill_pick_snapshot(snap: PickSnapshot, min_radius_px: float) -> void:
	var count: int = _rigs.size()
	snap.ids.resize(count)
	snap.owners.resize(count)
	snap.type_index.resize(count)
	snap.screen_pos.resize(count)
	snap.radius_px.resize(count)
	var zoom: float = camera.zoom.x
	for row: int in count:
		var type: int = _world.type_index[row]
		var art_px: float = ViewScale.milli_to_px(_world.type_selection_radius[type]) * zoom
		snap.ids[row] = _world.unit_id[row]
		snap.owners[row] = _world.owner[row]
		snap.type_index[row] = type
		snap.screen_pos[row] = unit_screen_position(row)
		snap.radius_px[row] = maxf(min_radius_px, art_px)


## Builds the rigs again when start() gave the runner a new World. False while there is none.
func _sync_rigs() -> bool:
	if runner == null or runner.world == null:
		return false
	if runner.world != _world:
		_build(runner.world)
	return true


func _build(world: World) -> void:
	for rig: Node2D in _rigs:
		remove_child(rig)
		rig.queue_free()
	_rigs.clear()
	_layers.clear()
	_world = world
	var count: int = world.unit_count()
	_rings.clear()
	_rings.resize(count)
	_ringed.clear()
	_heading.resize(count)
	_heading.fill(0.0)
	_aim.resize(count)
	_aim.fill(0.0)
	for row: int in count:
		var type_id: StringName = world.type_ids[world.type_index[row]]
		var rig: Node2D = Node2D.new()
		rig.name = "Unit%d" % world.unit_id[row]
		for file: String in LAYER_FILES:
			var sprite: Sprite2D = Sprite2D.new()
			sprite.name = file.capitalize()
			sprite.texture = load("%s%s_%s.svg" % [ART_DIR, type_id, file])
			rig.add_child(sprite)
			_layers.append(sprite)
		_layers[row * LAYER_FILES.size() + TEAM_LAYER].modulate = _team_color(world.owner[row])
		add_child(rig)
		_rigs.append(rig)
	_update_rigs(0.0)


func _resize_rings() -> void:  # dp changes with the window.
	_dp_px = UiScale.base_px_per_dp()
	_refresh_rings()


## A dp size divided by the zoom is world px, so rings are sized again when the zoom changes.
func _refresh_rings() -> void:
	if _ringed.is_empty():
		return
	_ring_zoom = camera.zoom.x
	var unit: float = _dp_px / _ring_zoom
	for row: int in _ringed:
		var ring: Ring = _rings[row]
		var art: int = _world.type_selection_radius[_world.type_index[row]] + RING_PAD_MILLI
		ring.radius = maxf(ViewScale.milli_to_px(art), RING_MIN_DP * unit)
		ring.unit = unit
		ring.queue_redraw()


func _team_color(owner_id: int) -> Color:
	var known: bool = owner_id >= 0 and owner_id < team_colors.size()
	return team_colors[owner_id if known else 0]


## Places the rigs and turns the layers. Allocates nothing: it only sets properties.
func _update_rigs(delta: float) -> void:
	var alpha: float = runner.alpha()
	var step: float = turn_rate * delta
	var prev_x: PackedInt32Array = runner.prev_pos_x
	var prev_y: PackedInt32Array = runner.prev_pos_y
	var cur_x: PackedInt32Array = _world.pos_x
	var cur_y: PackedInt32Array = _world.pos_y
	for row: int in _rigs.size():
		var from: Vector2 = ViewScale.milli_to_px_vec(prev_x[row], prev_y[row])
		var to: Vector2 = ViewScale.milli_to_px_vec(cur_x[row], cur_y[row])
		var at: Vector2 = from.lerp(to, alpha)
		if _rigs[row].position != at:
			_rigs[row].position = at
		# A unit that stood still last tick keeps its heading. So does one that moved under half a
		# full step: the step onto its goal is an integer remainder and can point anywhere.
		var moved_x: int = cur_x[row] - prev_x[row]
		var moved_y: int = cur_y[row] - prev_y[row]
		var moved: int = moved_x * moved_x + moved_y * moved_y
		var speed: int = _world.type_speed[_world.type_index[row]]
		if moved > 0 and 4 * moved >= speed * speed:
			_aim[row] = atan2(float(moved_y), float(moved_x))
		if _heading[row] != _aim[row]:
			# Not rotate_toward: after a turn through +-PI it ends at the aim +- TAU, never equal.
			var turn: float = angle_difference(_heading[row], _aim[row])
			_heading[row] = _aim[row] if absf(turn) <= step else _heading[row] + signf(turn) * step
			for layer: int in LAYER_FILES.size():
				_layers[row * LAYER_FILES.size() + layer].rotation = _heading[row]
