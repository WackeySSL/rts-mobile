class_name HealthBarLayer
extends Node2D
## Health bars over the units of the runner's published snapshot (assets/art/STYLE.md "Health
## bars"). A bar shows over a unit that is selected (`unit_layer.is_ringed`) and over one that
## lost hp within the last RECENT_MS (`unit_layer.hit_time_ms`, on the unit layer's frame clock).
## Own bars are plain, enemy bars have a notch in the top edge, which is the cue that does not
## rely on colour. Every bar is filled rects only and is drawn in one `_draw()` (ADR 0011 section
## 3, z 110 in ADR 0012 section 6). The layer reads `runner.snapshot` and the unit layer's
## per-row answers, and it brings the unit layer's rows up to the snapshot once at the start of a
## frame (`sync_rows`), so the tree order of the two layers does not matter.
##
## A bar is sized in dp, so it looks the same at every zoom: world px per dp is the base px per dp
## over the camera zoom. It is centred on its unit, and its bottom edge is r x zoom + 1 dp above
## the unit on screen, r the reach of the sprite of its class. The ring does not place it.
## `_process` plans the rects of the frame in reused packed arrays and `_draw` paints that plan
## through the same accessors, so a frame creates no object and tests read the plan (`rect_count`,
## `rect_at`) and what was painted (`drawn_count`).

const VEHICLE_WIDTH_DP: int = 22
const INFANTRY_WIDTH_DP: int = 16
const HEIGHT_DP: int = 6
const GAP_DP: int = 1  ## Between the bar's bottom edge and the sprite.
const VEHICLE_REACH_PX: float = 26.0  ## Sprite reach r in world px: the light tank hull.
const INFANTRY_REACH_PX: float = 14.0  ## Sprite reach r in world px: a rifle squad.
const NOTCH_WIDTH_DP: int = 4  ## An enemy bar's notch, open in the top edge.
const NOTCH_DEPTH_DP: int = 2
const EDGE_DP: int = 1  ## The dark edge round the interior.
const RECENT_MS: int = 3000  ## A hit unit shows its bar for this long (inclusive).
const MAX_RECTS_PER_BAR: int = 6  ## An enemy bar: three edge rects and three fill rects.
const SHAPE_STRIDE: int = 5  ## A shape lists rects as x, y, w, h and 0 (edge) or 1 (fill) in dp.

@export var runner: MatchRunner
@export var unit_layer: UnitLayer  ## Gives the selection, the hit times, the camera and the clock.
## The look: the fills are not team colours (STYLE.md). They are exports of this world-space layer
## and not theme items, like the team tints of `UnitLayer`, so a new palette edits them here.
@export var edge_color: Color = Color("1C2127")
@export var own_color: Color = Color("30A46C")  ## Fill of an own bar (ok).
@export var enemy_color: Color = Color("F5A524")  ## Fill of an enemy bar (warning).

var _dp_px: float = 1.0  ## Base px per dp, read when the window changes.
## Rect `i` of the frame: x, y, width and height in world px at 4i, and its colour. `_bars` holds
## the unit row of bar `k`, and `_bar_first` the first rect of bar `k` (one past the last at `k`
## = the bar count).
var _geometry: PackedFloat32Array = PackedFloat32Array()
var _colors: PackedColorArray = PackedColorArray()
var _bars: PackedInt32Array = PackedInt32Array()
var _bar_first: PackedInt32Array = PackedInt32Array()
var _rects: int = 0
var _bar_count: int = 0
var _drawn: int = 0  ## Rects the last _draw painted.
## The four shapes, own and enemy for each class (index 2 x enemy + infantry), made once: their
## rects (SHAPE_STRIDE ints each), the rect count and the width in dp.
var _shapes: Array[PackedInt32Array] = []
var _shape_rects: PackedInt32Array = PackedInt32Array()
var _shape_width: PackedInt32Array = PackedInt32Array()

@warning_ignore("integer_division")
func _init() -> void:
	for enemy: bool in [false, true]:
		for width: int in [VEHICLE_WIDTH_DP, INFANTRY_WIDTH_DP]:
			var shape: PackedInt32Array = _make_shape(enemy, width)
			_shapes.append(shape)
			_shape_rects.append(shape.size() / SHAPE_STRIDE)
			_shape_width.append(width)


func _ready() -> void:
	get_viewport().size_changed.connect(_read_dp)
	_read_dp()


func _process(_delta: float) -> void:
	var had_rects: bool = _rects > 0
	_plan()
	if had_rects or _rects > 0:
		queue_redraw()


## The end (exclusive, in dp from the bar's left edge) of the fill of a unit with `hp` of `max_hp`
## on a bar `width` dp wide: the interior scaled by hp / max_hp and rounded, at least 1 dp while
## the unit lives, so a living unit always shows some fill. Integer rounding, halves up.
@warning_ignore("integer_division")
static func fill_end_dp(hp: int, max_hp: int, width: int) -> int:
	if hp <= 0 or max_hp <= 0:
		return EDGE_DP
	var inner: int = width - 2 * EDGE_DP
	return EDGE_DP + maxi(1, (2 * inner * mini(hp, max_hp) + max_hp) / (2 * max_hp))


## Rects planned for the last frame, and the bars they belong to.
func rect_count() -> int:
	return _rects


## Rects the last `_draw` painted: the plan of the frame it ran after.
func drawn_count() -> int:
	return _drawn


func bar_count() -> int:
	return _bar_count


## Rect `index` of the plan in world px (layer coordinates), and its colour.
func rect_at(index: int) -> Rect2:
	var at: int = index * 4
	return Rect2(_geometry[at], _geometry[at + 1], _geometry[at + 2], _geometry[at + 3])


func rect_color(index: int) -> Color:
	return _colors[index]


## The unit row of bar `bar`, and the range [first, end) of its rects in the plan.
func bar_row(bar: int) -> int:
	return _bars[bar]


func bar_first_rect(bar: int) -> int:
	return _bar_first[bar]


func bar_end_rect(bar: int) -> int:
	return _bar_first[bar + 1]


## The rects of a bar `width` dp wide, own or enemy (STYLE.md "Health bars"), as SHAPE_STRIDE ints
## each: the edge rects, then the fill rects of a full bar. Own: the box and its interior. Enemy:
## two shoulders and the foot of a notch (NOTCH_WIDTH_DP wide, NOTCH_DEPTH_DP deep, open in the
## top edge) for the edge, and for the fill a shoulder on each side of the notch over one strip.
@warning_ignore("integer_division")
static func _make_shape(enemy: bool, width: int) -> PackedInt32Array:
	var inner: int = width - 2 * EDGE_DP
	if not enemy:
		return PackedInt32Array(
			[0, 0, width, HEIGHT_DP, 0, EDGE_DP, EDGE_DP, inner, HEIGHT_DP - 2 * EDGE_DP, 1]
		)
	var shoulder: int = (width - NOTCH_WIDTH_DP) / 2
	var arm: int = shoulder - 2 * EDGE_DP
	var right: int = shoulder + NOTCH_WIDTH_DP
	var strip_y: int = NOTCH_DEPTH_DP + EDGE_DP
	return PackedInt32Array(
		(
			[0, 0, shoulder, HEIGHT_DP, 0]
			+ [right, 0, shoulder, HEIGHT_DP, 0]
			+ [shoulder, NOTCH_DEPTH_DP, NOTCH_WIDTH_DP, HEIGHT_DP - NOTCH_DEPTH_DP, 0]
			+ [EDGE_DP, EDGE_DP, arm, NOTCH_DEPTH_DP, 1]
			+ [right + EDGE_DP, EDGE_DP, arm, NOTCH_DEPTH_DP, 1]
			+ [EDGE_DP, strip_y, inner, HEIGHT_DP - strip_y - EDGE_DP, 1]
		)
	)


func _read_dp() -> void:  # dp changes with the window.
	_dp_px = UiScale.base_px_per_dp()


## Plans the bars of the frame from the snapshot, the selection and the hit times. Allocates
## nothing in steady state: the arrays are only resized when there are more units than before.
func _plan() -> void:
	_rects = 0
	_bar_count = 0
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null or unit_layer == null or unit_layer.camera == null:
		return
	unit_layer.sync_rows()  # One sync for the loop: the per-row answers below do not sync.
	var count: int = snap.unit_id.size()
	# Sized by _bar_first, which the closing write below reaches at [bar count] even for 0 units.
	if _bar_first.size() < count + 1:
		_bars.resize(count)
		_bar_first.resize(count + 1)
		_geometry.resize(count * MAX_RECTS_PER_BAR * 4)
		_colors.resize(count * MAX_RECTS_PER_BAR)
	var unit: float = _dp_px / unit_layer.camera.zoom.x  # World px per dp.
	var recent_since: int = int(unit_layer.clock.call()) - RECENT_MS
	var local_player: int = runner.scenario.local_player if runner.scenario != null else 1
	var alpha: float = runner.alpha()
	var px_per_milli: float = ViewScale.milli_to_px(1)
	var owners: PackedInt32Array = snap.owner
	var types: PackedInt32Array = snap.type_index
	var hps: PackedInt32Array = snap.hp
	var max_hps: PackedInt32Array = snap.type_max_hp
	var armours: PackedInt32Array = snap.type_armour
	var prev_x: PackedInt32Array = snap.prev_pos_x
	var prev_y: PackedInt32Array = snap.prev_pos_y
	var cur_x: PackedInt32Array = snap.pos_x
	var cur_y: PackedInt32Array = snap.pos_y
	var geometry: PackedFloat32Array = _geometry
	var colors: PackedColorArray = _colors
	for row: int in count:
		var hit: int = unit_layer.hit_time_ms(row)
		if not (unit_layer.is_ringed(row) or (hit >= 0 and hit >= recent_since)):
			continue
		var type: int = types[row]
		var infantry: int = 1 if armours[type] == World.Armour.INFANTRY else 0
		var shape: int = (2 if owners[row] != local_player else 0) + infantry
		var width: int = _shape_width[shape]
		var fill_end: int = fill_end_dp(hps[row], max_hps[type], width)
		var fill_color: Color = enemy_color if shape >= 2 else own_color
		var reach: float = INFANTRY_REACH_PX if infantry == 1 else VEHICLE_REACH_PX
		# The unit's place now, the way UnitLayer puts its rig, and the bar's top-left corner.
		var x: float = lerpf(prev_x[row], cur_x[row], alpha) * px_per_milli
		var y: float = lerpf(prev_y[row], cur_y[row], alpha) * px_per_milli
		var left: float = x - 0.5 * width * unit
		var top: float = y - reach - (GAP_DP + HEIGHT_DP) * unit
		_bars[_bar_count] = row
		_bar_first[_bar_count] = _rects
		_bar_count += 1
		var rects: PackedInt32Array = _shapes[shape]
		for at: int in range(0, _shape_rects[shape] * SHAPE_STRIDE, SHAPE_STRIDE):
			var from: int = rects[at]
			var to: int = from + rects[at + 2]
			var is_fill: bool = rects[at + 4] == 1
			if is_fill:
				to = mini(to, fill_end)  # A fill rect is clipped to x < fill_end.
				if to <= from:
					continue
			var out: int = _rects * 4
			geometry[out] = left + from * unit
			geometry[out + 1] = top + rects[at + 1] * unit
			geometry[out + 2] = (to - from) * unit
			geometry[out + 3] = rects[at + 3] * unit
			colors[_rects] = fill_color if is_fill else edge_color
			_rects += 1
	_bar_first[_bar_count] = _rects


func _draw() -> void:
	_drawn = 0
	for index: int in _rects:
		draw_rect(rect_at(index), rect_color(index))
		_drawn += 1
