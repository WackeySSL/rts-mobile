class_name RallyLayer
extends Node2D
## The rally flags of the local player (ADR 0019 section 3, ADR 0023 section 2, STYLE.md "Rally
## flags", plan P87), at z 61 between the placement ghost (60) and the strike marks (65). It draws
## from the published snapshot: a flag for each production tab (infantry, vehicles) whose rally
## point `snap.rally_x/y` is set, the foot of its pole on the point's projected position
## (`IsoProjection.ground_to_px`). The point is the sim's, so a flag shows after the tick that
## applied the RALLY and goes with the match. The hulls of all flags are drawn first, then their
## team layers tinted with the player's mid colour (`WorldSort.mid_colour`), as the layer contract
## asks of rigs that overlap. While the one own barracks or vehicle factory that produces a flag's
## tab is selected (`set_selected`, wired to `PlayerController.selection_changed`) a line runs from
## the building's footprint centre to its flag: the marker stroke, a dark pass 2 dp wider under the
## colour pass (STYLE.md "Feedback markers"), 3 dp, kept in dp through any zoom.
## It redraws when the tick, the selection or the zoom changes, and does nothing else.

const Z_RALLY: int = 61
const ART: String = "res://assets/art/svg/flags/rally_%s_%s.svg"
const TABS: Array[int] = [World.Tab.INFANTRY, World.Tab.VEHICLES]
const NAMES: Array[String] = ["infantry", "vehicles"]  ## The file names of `TABS`, entry by entry.

@export var runner: MatchRunner
## Where the player's colour comes from. Without one the team layers stay white.
@export var world_sort: WorldSort

var draws: int = 0  ## Frames drawn, for the tests.
## What the last frame drew, for the tests: the foot of each flag by tab, and the tabs it drew the
## line to.
var last_flags: Dictionary[int, Vector2] = {}
var last_lines: Array[int] = []

var _hulls: Array[Texture2D] = []  ## By entry of `TABS`.
var _teams: Array[Texture2D] = []
var _selected: PackedInt32Array = PackedInt32Array()
var _tick: int = -1
var _zoom: float = 0.0


func _init() -> void:
	z_index = Z_RALLY
	z_as_relative = false


func _ready() -> void:
	for name_of: String in NAMES:
		_hulls.append(load(ART % [name_of, "hull"]) as Texture2D)
		_teams.append(load(ART % [name_of, "team"]) as Texture2D)


## The selection changed: the line of a selected producer follows.
func set_selected(ids: PackedInt32Array) -> void:
	_selected = ids.duplicate()
	queue_redraw()


func _process(_delta: float) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	var zoom: float = get_canvas_transform().get_scale().x
	if snap != null and (snap.tick != _tick or zoom != _zoom):
		_tick = snap.tick
		_zoom = zoom
		queue_redraw()


func _draw() -> void:
	last_flags.clear()
	last_lines.clear()
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null:
		return
	draws += 1
	var player: int = FogLayer.local_player_of(runner)
	var colour: Color = Color.WHITE if world_sort == null else world_sort.mid_colour(player)
	var unit: float = UiScale.base_px_per_dp() / get_canvas_transform().get_scale().x
	var building: int = OrderRules.rally_building(snap, _selected, player)
	var spots: Array[Vector2] = []  # By entry of TABS; INF where the tab has no flag.
	for entry: int in TABS.size():
		spots.append(flag_px(snap, player, TABS[entry]))
	if building != 0:
		var row: int = snap.index_of(building)
		var entry: int = TABS.find(OrderRules.produced_tab(snap, snap.type_index[row]))
		if entry >= 0 and spots[entry].is_finite():
			var from: Vector2 = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
			_line(from, spots[entry], colour, unit)
			last_lines.append(TABS[entry])
	for entry: int in TABS.size():
		if spots[entry].is_finite():
			_stand(_hulls[entry], spots[entry], Color.WHITE)
			last_flags[TABS[entry]] = spots[entry]
	for entry: int in TABS.size():
		if spots[entry].is_finite():
			_stand(_teams[entry], spots[entry], colour)


## The projected position of `player`'s rally point for `tab` in `snap`, the point at infinity
## where none is set (the sim keeps -1 for none).
static func flag_px(snap: MatchSnapshot, player: int, tab: int) -> Vector2:
	var queue: int = player * World.TABS + tab
	if queue < 0 or queue >= snap.rally_x.size() or queue >= snap.rally_y.size():
		return Vector2.INF
	var x: int = snap.rally_x[queue]
	var y: int = snap.rally_y[queue]
	return IsoProjection.ground_to_px(x, y) if x >= 0 and y >= 0 else Vector2.INF


## `texture` with the middle of its canvas, the foot of the pole, on `at`.
func _stand(texture: Texture2D, at: Vector2, tint: Color) -> void:
	if texture != null:
		draw_texture(texture, at - texture.get_size() * 0.5, tint)


## The line from the building to its flag: the dark pass, then the colour.
func _line(from: Vector2, to: Vector2, colour: Color, unit: float) -> void:
	var width: float = FeedbackStyle.STROKE_DP * unit
	draw_line(from, to, FeedbackStyle.OUTLINE, width + FeedbackStyle.OUTLINE_DP * unit, true)
	draw_line(from, to, colour, width, true)
