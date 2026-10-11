class_name UnitLayer
extends Node2D
## Draws every unit of the runner's World as a rig: a Node2D with the Sprite2D layers Hull, Team
## and Turret (assets/art/STYLE.md, layer contract). It only reads the World (ADR 0003): each frame
## a rig stands at prev + (cur - prev) * runner.alpha() in px, and the layers turn toward the last
## direction the unit moved in (the gun follows the hull until a unit has a target). The turn is a
## view effect and never touches the World.
## Rigs are the children of this node in World row order, so rig `i` shows unit row `i`.

const ART_DIR: String = "res://assets/art/svg/units/"
const LAYER_FILES: Array[String] = ["hull", "team", "turret"]  ## Draw order, also the node names.
const TEAM_LAYER: int = 1  ## Index of "team" in LAYER_FILES.

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


func _ready() -> void:
	_sync_rigs()


func _process(delta: float) -> void:
	if _sync_rigs():
		_update_rigs(delta)


func rig_count() -> int:
	return _rigs.size()


## Where unit row `index` is on screen, in base px.
func unit_screen_position(index: int) -> Vector2:
	return camera.world_to_screen(_rigs[index].global_position)


## Builds the rigs again when the runner has a new World (start() ran again) or another unit count.
## Returns false while there is no World to draw.
func _sync_rigs() -> bool:
	if runner == null or runner.world == null:
		return false
	if runner.world != _world or _rigs.size() != runner.world.unit_count():
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
		# A unit that stood still last tick keeps the heading it had.
		var moved_x: int = cur_x[row] - prev_x[row]
		var moved_y: int = cur_y[row] - prev_y[row]
		if moved_x != 0 or moved_y != 0:
			_aim[row] = atan2(float(moved_y), float(moved_x))
		if _heading[row] != _aim[row]:
			_heading[row] = rotate_toward(_heading[row], _aim[row], step)
			for layer: int in LAYER_FILES.size():
				_layers[row * LAYER_FILES.size() + layer].rotation = _heading[row]
