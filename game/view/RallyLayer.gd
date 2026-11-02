class_name RallyLayer
extends Node2D
## The rally flags of the local player (ADR 0019 section 3, ADR 0023 section 2, STYLE.md "Rally
## flags", plan P87), at z 61 between the placement ghost (60) and the strike marks (65). It draws
## from the published snapshot: a flag for each production tab (infantry, vehicles) whose rally
## point `snap.rally_x/y` is set, the foot of its pole on the point's projected position
## (`IsoProjection.ground_to_px`), and goes with the match. The hulls of all flags are drawn first,
## then their team layers tinted with the player's mid colour (`WorldSort.mid_colour`), as the layer
## contract asks of rigs that overlap. While the one own barracks or vehicle factory that produces a
## flag's tab is selected (`set_selected`, wired to `PlayerController.selection_changed`) a line
## runs from the building's footprint centre to its flag: the marker stroke, a dark pass 2 dp wider
## under the colour pass (STYLE.md "Feedback markers"), 3 dp, kept in dp through any zoom.
## A tap that sets a rally point shows its flag and line at once (`show_pending`, wired to
## `PlayerController.rally_ordered`), at the point as the sim will clamp it, also while the match is
## paused. It gives way to the snapshot's flag as soon as the snapshot holds that point, and is
## dropped when the snapshot has not taken it `PENDING_TICKS` published ticks after the tap (the sim
## refused the order: the building died first), when a new match begins and when the match ends.
## It redraws only when the local player's rally points, a pending flag, the selection or the zoom
## change, never for a tick alone.

const Z_RALLY: int = 61
const ART: String = "res://assets/art/svg/flags/rally_%s_%s.svg"
const TABS: Array[int] = [World.Tab.INFANTRY, World.Tab.VEHICLES]
const NAMES: Array[String] = ["infantry", "vehicles"]  ## The file names of `TABS`, entry by entry.
## A tap's RALLY is applied by the tick after it and published with it, a worker-thread match one
## publish later: four ticks (a quarter of a second) is more than any order that was taken needs.
const PENDING_TICKS: int = 4

@export var runner: MatchRunner
## Where the player's colour comes from. Without one the team layers stay white.
@export var world_sort: WorldSort

var draws: int = 0  ## Frames drawn, for the tests.
## What the last frame drew, for the tests: the foot of each flag by tab, the tabs it drew a line to
## (at most one), that line's two ends, the colour of the team layers and the line (one), and the
## widths of the line's colour pass and dark pass in world px.
var last_flags: Dictionary[int, Vector2] = {}
var last_lines: Array[int] = []
var last_line_from: Vector2 = Vector2.INF
var last_line_to: Vector2 = Vector2.INF
var last_tint: Color = Color.WHITE
var last_stroke_px: float = 0.0
var last_outline_px: float = 0.0

var _hulls: Array[Texture2D] = []  ## By entry of `TABS`.
var _teams: Array[Texture2D] = []
var _selected: PackedInt32Array = PackedInt32Array()
var _zoom: float = 0.0
## Two ints (x, y in milli-tiles) per entry of `TABS`: the rally point of the last snapshot read
## (-2 before the first), and the pending one (-1 for none) with the snapshot tick that showed it.
var _seen: PackedInt32Array = PackedInt32Array()
var _pending: PackedInt32Array = PackedInt32Array()
var _pending_tick: PackedInt32Array = PackedInt32Array()
var _spots: PackedVector2Array = PackedVector2Array()  ## By entry: where the flag stands, or INF.


func _init() -> void:
	z_index = Z_RALLY
	z_as_relative = false
	_seen.resize(TABS.size() * 2)
	_seen.fill(-2)
	_pending.resize(TABS.size() * 2)
	_pending.fill(-1)
	_pending_tick.resize(TABS.size())
	_spots.resize(TABS.size())
	_spots.fill(Vector2.INF)


func _ready() -> void:
	for name_of: String in NAMES:
		_hulls.append(load(ART % [name_of, "hull"]) as Texture2D)
		_teams.append(load(ART % [name_of, "team"]) as Texture2D)


## The selection changed: the line of a selected producer follows. The same ids change nothing.
func set_selected(ids: PackedInt32Array) -> void:
	if ids != _selected:
		_selected = ids.duplicate()
		queue_redraw()


## The player's tap sent a RALLY for `tab` to the point (`x`, `y`) in milli-tiles: its flag is shown
## at once, at the point as the sim clamps it to the map, until the snapshot holds the same point.
func show_pending(tab: int, x: int, y: int) -> void:
	var entry: int = TABS.find(tab)
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if entry < 0 or snap == null:
		return
	_pending[entry * 2] = clampi(x, 0, maxi(snap.map_cols * World.MILLI_PER_TILE - 1, 0))
	_pending[entry * 2 + 1] = clampi(y, 0, maxi(snap.map_rows * World.MILLI_PER_TILE - 1, 0))
	_pending_tick[entry] = snap.tick
	queue_redraw()


## Whether the flag of `tab` is a pending one (the snapshot does not hold its point yet).
func has_pending(tab: int) -> bool:
	var entry: int = TABS.find(tab)
	return entry >= 0 and _pending[entry * 2] >= 0


func _process(_delta: float) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null:
		return
	var changed: bool = false
	var zoom: float = get_canvas_transform().get_scale().x
	if zoom != _zoom:
		_zoom = zoom
		changed = true
	var player: int = FogLayer.local_player_of(runner)
	for entry: int in TABS.size():
		var point: Vector2i = rally_of(snap, player, TABS[entry])
		if point.x != _seen[entry * 2] or point.y != _seen[entry * 2 + 1]:
			_seen[entry * 2] = point.x
			_seen[entry * 2 + 1] = point.y
			changed = true
		if _pending[entry * 2] >= 0 and _settled(snap, entry, point):
			_pending[entry * 2] = -1
			_pending[entry * 2 + 1] = -1
			changed = true
	if changed:
		queue_redraw()


func _draw() -> void:
	last_flags.clear()
	last_lines.clear()
	last_line_from = Vector2.INF
	last_line_to = Vector2.INF
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null:
		return
	draws += 1
	var player: int = FogLayer.local_player_of(runner)
	var colour: Color = Color.WHITE if world_sort == null else world_sort.mid_colour(player)
	var unit: float = UiScale.base_px_per_dp() / get_canvas_transform().get_scale().x
	last_tint = colour
	for entry: int in TABS.size():
		_spots[entry] = _spot(snap, player, entry)
	var building: int = OrderRules.rally_building(snap, _selected, player)
	if building != 0:
		var entry: int = TABS.find(OrderRules.rally_tab(snap, building))
		if entry >= 0 and _spots[entry].is_finite():
			var row: int = snap.index_of(building)
			last_line_from = IsoProjection.ground_to_px(snap.pos_x[row], snap.pos_y[row])
			last_line_to = _spots[entry]
			last_lines.append(TABS[entry])
			_line(last_line_from, last_line_to, colour, unit)
	for entry: int in TABS.size():
		if _spots[entry].is_finite():
			_stand(_hulls[entry], _spots[entry], Color.WHITE)
			last_flags[TABS[entry]] = _spots[entry]
	for entry: int in TABS.size():
		if _spots[entry].is_finite():
			_stand(_teams[entry], _spots[entry], colour)


## `player`'s rally point for `tab` in `snap` in milli-tiles, (-1, -1) where none is set (the sim
## keeps -1 for none) or the queue is not in the snapshot.
static func rally_of(snap: MatchSnapshot, player: int, tab: int) -> Vector2i:
	var queue: int = player * World.TABS + tab
	if queue < 0 or queue >= snap.rally_x.size() or queue >= snap.rally_y.size():
		return Vector2i(-1, -1)
	var x: int = snap.rally_x[queue]
	var y: int = snap.rally_y[queue]
	return Vector2i(x, y) if x >= 0 and y >= 0 else Vector2i(-1, -1)


## The projected position of `player`'s rally point for `tab` in `snap`, the point at infinity
## where none is set.
static func flag_px(snap: MatchSnapshot, player: int, tab: int) -> Vector2:
	var point: Vector2i = rally_of(snap, player, tab)
	return IsoProjection.ground_to_px(point.x, point.y) if point.x >= 0 else Vector2.INF


## Where the flag of entry `entry` stands: the pending point when there is one, else the snapshot's.
func _spot(snap: MatchSnapshot, player: int, entry: int) -> Vector2:
	if _pending[entry * 2] >= 0:
		return IsoProjection.ground_to_px(_pending[entry * 2], _pending[entry * 2 + 1])
	return flag_px(snap, player, TABS[entry])


## Whether the pending flag of `entry` has done its work: the snapshot holds its point (`point`),
## or has not taken it in `PENDING_TICKS` ticks, or is of an earlier tick (a new match), or ended.
func _settled(snap: MatchSnapshot, entry: int, point: Vector2i) -> bool:
	var waited: int = snap.tick - _pending_tick[entry]
	return (
		(point.x == _pending[entry * 2] and point.y == _pending[entry * 2 + 1])
		or waited > PENDING_TICKS
		or waited < 0
		or snap.match_end_tick != 0
	)


## `texture` with the middle of its canvas, the foot of the pole, on `at`.
func _stand(texture: Texture2D, at: Vector2, tint: Color) -> void:
	if texture != null:
		draw_texture(texture, at - texture.get_size() * 0.5, tint)


## The line from the building to its flag: the dark pass, then the colour.
func _line(from: Vector2, to: Vector2, colour: Color, unit: float) -> void:
	last_stroke_px = FeedbackStyle.STROKE_DP * unit
	last_outline_px = last_stroke_px + FeedbackStyle.OUTLINE_DP * unit
	draw_line(from, to, FeedbackStyle.OUTLINE, last_outline_px, true)
	draw_line(from, to, colour, last_stroke_px, true)
