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
## The squads (`Hull` and `Team`, no turret) are built in `_add_squads`: beside the tank in each
## slot, turning as a whole like a squad rig does in game, and in a row above the zoom row, one
## pair per zoom level. `Grass/ZoomRow` and `Sand/ZoomRow` stay the tank's (tests/project).
## They have no tile square; a unit without a turret can join the list in `_squad_pair`.
##
## `_add_rings_and_atlas` adds a ring row (the tank with its selection ring at the three zooms, at
## the 6-inch phone's ring radius) and the effects atlas at scale 1 to each ground.
##
## To add an asset: add its layers as a rig on both backgrounds, put the rig in a team group and
## keep the layer names. See assets/art/STYLE.md.

const TEAM_A_GROUP: StringName = &"gallery_team_a"
const TEAM_B_GROUP: StringName = &"gallery_team_b"
const TEAM_LAYER: NodePath = ^"Team"
const TURRET_LAYER: String = "Turret"
const UNIT_ART: String = "res://assets/art/svg/units/%s_%s.svg"
const SQUAD_SLOT_OFFSET_PX: float = 80.0  ## Rifle squad left of the tank, rocket squad right.
const SQUAD_ZOOM_OFFSET_PX: float = 34.0  ## From the zoom column's centre, before the rig scale.
const SQUAD_ROW_TOP: float = 0.62  ## Anchor of the squad zoom row (the tank's is 0.78).
const RING_ART: String = "res://assets/art/svg/ui/selection_ring.svg"
const RING_TEX_RADIUS_PX: float = 72.0  ## The ring texture's centre-line radius (STYLE.md).
const RING_MIN_RADIUS_DP: float = 18.0
const PX_PER_DP: float = 1.75  ## Base px per dp on the 6-inch phone profile.
const TANK_RING_RADIUS_PX: float = 35.2  ## World px: (selection_radius / 1000 + 0.05) x 64.
const RING_ROW_TOP: float = 0.3
const ATLAS_ART: String = "res://assets/art/svg/fx/effects_atlas.svg"
const ATLAS_TOP_PX: float = 20.0
const ATLAS_LEFT_PX: Dictionary[String, float] = {"Grass": 190.0, "Sand": 282.0}

@export var team_a_color: Color = Color("2F80ED")
@export var team_b_color: Color = Color("E5484D")
## Turret turn speed in radians per second.
@export var turret_turn_speed: float = 0.5

var _turrets: Array[Sprite2D] = []
var _spinners: Array[Node2D] = []
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
	_add_squads()
	_add_rings_and_atlas()
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
	for rig: Node2D in _spinners:
		rig.rotation = wrapf(rig.rotation + step, 0.0, TAU)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Never change scenes from inside a notification dispatch.
		_go_back.call_deferred()


func _add_squads() -> void:
	for ground_name: String in ["Grass", "Sand"]:
		var ground: Control = get_node(ground_name)
		for slot_name: String in ["SlotA", "SlotB"]:
			var slot: Node = ground.get_node(slot_name)
			var is_a: bool = slot.get_node("Tank").is_in_group(TEAM_A_GROUP)
			for rig: Node2D in _squad_pair("", is_a, Vector2.ZERO, SQUAD_SLOT_OFFSET_PX, 1.0):
				slot.add_child(rig)
				_spinners.append(rig)
		var row: Control = _anchored_row(ground, "SquadZoomRow", SQUAD_ROW_TOP)
		# A pair per tank rig of the zoom row, same column and scale, so the two rows cannot
		# drift apart. The labels under the rigs are Controls.
		for node: Node in ground.get_node("ZoomRow").get_children():
			var tank: Node2D = node as Node2D
			if tank != null:
				var is_a: bool = tank.is_in_group(TEAM_A_GROUP)
				for rig: Node2D in _squad_pair(
					String(tank.name), is_a, tank.position, SQUAD_ZOOM_OFFSET_PX, tank.scale.x
				):
					row.add_child(rig)


func _add_rings_and_atlas() -> void:
	for ground_name: String in ["Grass", "Sand"]:
		var ground: Control = get_node(ground_name)
		var row: Control = _anchored_row(ground, "RingRow", RING_ROW_TOP)
		for node: Node in ground.get_node("ZoomRow").get_children():
			var tank: Node2D = node as Node2D
			if tank == null:
				continue
			# The tank rig again, with the ring the game draws at this zoom: the larger of the
			# tank's own radius and the 18 dp minimum, which is dp / zoom in world px.
			var rig: Node2D = tank.duplicate()
			rig.name = "Ring" + String(tank.name)
			var ring: Sprite2D = Sprite2D.new()
			ring.name = "Ring"
			ring.texture = load(RING_ART)
			var radius: float = maxf(
				TANK_RING_RADIUS_PX, RING_MIN_RADIUS_DP * PX_PER_DP / tank.scale.x
			)
			ring.scale = Vector2.ONE * radius / RING_TEX_RADIUS_PX
			rig.add_child(ring)
			rig.move_child(ring, 0)
			row.add_child(rig)
		var atlas: TextureRect = TextureRect.new()
		atlas.name = "EffectsAtlas"
		atlas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		atlas.texture = load(ATLAS_ART)
		atlas.position = Vector2(ATLAS_LEFT_PX[ground_name], ATLAS_TOP_PX)
		ground.add_child(atlas)


## An empty Control in the middle of `ground`, `top` of the way down, that rigs are added to.
func _anchored_row(ground: Control, row_name: String, top: float) -> Control:
	var row: Control = Control.new()
	row.name = row_name
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	row.anchor_top = top
	row.anchor_bottom = top
	ground.add_child(row)
	return row


## The rifle squad `offset` px left of `centre`, the rocket squad the same distance right.
func _squad_pair(
	suffix: String, is_team_a: bool, centre: Vector2, offset: float, rig_scale: float
) -> Array[Node2D]:
	var group: StringName = TEAM_A_GROUP if is_team_a else TEAM_B_GROUP
	var pair: Array[Node2D] = []
	for squad: String in ["rifle_squad", "rocket_squad"]:
		var rig: Node2D = Node2D.new()
		rig.name = squad.to_pascal_case() + suffix
		rig.position = centre + Vector2(offset if pair.size() > 0 else -offset, 0.0)
		rig.scale = Vector2.ONE * rig_scale
		rig.add_to_group(group)
		for layer: String in ["hull", "team"]:
			var sprite: Sprite2D = Sprite2D.new()
			sprite.name = layer.capitalize()
			sprite.texture = load(UNIT_ART % [squad, layer])
			rig.add_child(sprite)
		pair.append(rig)
	return pair


func _tint_team_layers(group: StringName, color: Color) -> void:
	for rig: Node in get_tree().get_nodes_in_group(group):
		if not is_ancestor_of(rig):
			continue
		var layer: CanvasItem = rig.get_node_or_null(TEAM_LAYER) as CanvasItem
		if layer != null:
			layer.modulate = color


func _go_back() -> void:
	DevRoutes.open(get_tree(), DevRoutes.DEV_MENU_SCENE)
