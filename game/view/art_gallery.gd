extends Control
## Art gallery (developer scene): every asset at gameplay zoom on grass and sand, in both team
## colours, so the art can be judged on a phone through the web preview.
##
## View-only. Each tank is a rig `Node2D` in group `gallery_team_a` or `gallery_team_b` with the
## layers `Hull`, `Team` and `Turret` (draw order hull, team, turret). The team colour is applied
## with `modulate` on the `Team` layer. The turrets turn slowly so both sides of each can be
## judged; `delta` is fine here because nothing in the sim reads this.
##
## The zoom row (bottom) shows the light tank at rig scale 0.75, 1.0 and 1.5, the camera zoom
## levels: team A on grass, team B (the enemy look) on sand. A rig's scale does to the sprite what
## the camera zoom does, so the row shows how soft the 0.5 import scale looks at each level. It
## needs no code: tint and turret turn find its rigs by group and layer name like any other rig.
##
## To add an asset: add its layers as a rig on both backgrounds, put the rig in a team group and
## keep the layer names. See assets/art/STYLE.md.

const TEAM_A_GROUP: StringName = &"gallery_team_a"
const TEAM_B_GROUP: StringName = &"gallery_team_b"
const TEAM_LAYER: NodePath = ^"Team"
const TURRET_LAYER: String = "Turret"

@export var team_a_color: Color = Color("2F80ED")
@export var team_b_color: Color = Color("E5484D")
## Turret turn speed in radians per second.
@export var turret_turn_speed: float = 0.5

var _turrets: Array[Sprite2D] = []
var _previous_quit_on_go_back: bool = true

@onready var _back_button: Button = %BackButton


func _enter_tree() -> void:
	# SceneTree.quit_on_go_back is true by default and would quit the app on the Android back
	# button before the gallery can leave. Switch it off while the gallery is open.
	var tree: SceneTree = get_tree()
	_previous_quit_on_go_back = tree.quit_on_go_back
	tree.quit_on_go_back = false


func _exit_tree() -> void:
	get_tree().quit_on_go_back = _previous_quit_on_go_back


func _ready() -> void:
	_tint_team_layers(TEAM_A_GROUP, team_a_color)
	_tint_team_layers(TEAM_B_GROUP, team_b_color)
	for node: Node in find_children(TURRET_LAYER, "Sprite2D", true, false):
		var turret: Sprite2D = node as Sprite2D
		if turret != null:
			_turrets.append(turret)
	_back_button.pressed.connect(_go_back)


func _process(delta: float) -> void:
	var step: float = turret_turn_speed * delta
	for turret: Sprite2D in _turrets:
		turret.rotation = wrapf(turret.rotation + step, 0.0, TAU)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Never change scenes from inside a notification dispatch.
		_go_back.call_deferred()


func _tint_team_layers(group: StringName, color: Color) -> void:
	for rig: Node in get_tree().get_nodes_in_group(group):
		if not is_ancestor_of(rig):
			continue
		var layer: CanvasItem = rig.get_node_or_null(TEAM_LAYER) as CanvasItem
		if layer != null:
			layer.modulate = color


func _go_back() -> void:
	DevRoutes.open(get_tree(), DevRoutes.DEV_MENU_SCENE)
