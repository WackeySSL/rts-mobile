class_name GuideUnitAnchor
extends RefCounted
## Resolves a `UNIT` step's selector to one unit and gives its screen point (ADR 0048 section 13.3
## and 13.4, plan row P593b-1). It reads only `runner.snapshot`, the camera, the local player and
## the layers' `tap_point`, never the World and never a layer's rigs. Nothing is allocated per
## frame: the pick is made on a new snapshot, a new step or a new match (one scan each) and is held
## while the unit stays a candidate; every frame only projects the held unit's point.
##
## The pick is a pure function of the snapshot, the camera's centre and the selector: integer
## squared distances between tick positions (`NEAREST_CAMERA`) or the highest id (`NEWEST`), ties to
## the lower id. Enemies count only on cells the local player sees; buildings never.

const MIN_HALF_DP: float = 24.0  ## The ring is never smaller than this half size.
const THROUGH_BAND_DP: float = 8.0  ## A card button's rect grows by this to clear (and the card's).

var unit_id: int = -1  ## The held unit, -1 for none.
var point: Vector2 = Vector2.INF  ## Its tap point on the screen, base px; INF: no ring, no hand.
var half: float = 0.0  ## The ring's half size, px.
var flyer: bool = false
var in_field: bool = false  ## The point is on the screen and under no HUD part or card button.
var scans: int = 0  ## Scans made so far (tests).
var lookups: int = 0  ## `index_of` calls made to find the held row (tests).

var _step: TutorialLeadInDef = null
var _serial: int = -1
var _tick: int = -1
var _version: int = -1  ## `rows_version` the held row was read at.
var _row: int = -1
var _type: int = -1
var _under: bool = false  ## The point is under a card button (hysteresis: see `_under_button`).


## Brings the result up to this frame for step `aim`. `rects` are the mark's HUD rects
## (`GuideDock.hud_for_dock`); the economy card is not one that hides the field. `buttons` are the
## global rects of the card's visible Next, Skip and tab: they take a touch even when the card is
## see-through, so a point under one is not in the field (ADR 0048 section 13.5).
func update(
	aim: TutorialLeadInDef,
	runner: MatchRunner,
	camera: RtsCamera,
	ground: UnitLayer,
	air: AirLayer,
	safe: Rect2,
	dp: float,
	rects: Dictionary[StringName, Rect2],
	buttons: Array[Rect2]
) -> void:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	var sel: TutorialUnitPickDef = aim.unit if aim != null else null
	var bare: bool = camera == null or ground == null or air == null
	if snap == null or sel == null or bare or aim.anchor != TutorialBeatDef.Anchor.UNIT:
		_step = aim
		_forget()
		return
	if aim != _step or snap.match_serial != _serial:  # A new step or match: scan on this frame.
		_step = aim
		_serial = snap.match_serial
		_forget()
	if snap.tick != _tick:
		_tick = snap.tick
		if unit_id >= 0 and not _holds(snap, sel, runner):
			unit_id = -1
			_under = false  # The next pick starts clear of a button.
		if unit_id < 0:
			_scan(snap, sel, runner, camera)
	if unit_id < 0:
		point = Vector2.INF
		in_field = false
		_under = false
		return
	flyer = WorldSort.is_flyer(snap, _type)
	var world: Vector2 = air.tap_point(unit_id) if flyer else ground.tap_point(unit_id)
	if world == Vector2.INF:
		point = Vector2.INF
		in_field = false
		_under = false
		return
	point = camera.world_to_screen(world)
	var ring: float = IsoProjection.ellipse_px(snap.type_selection_radius[_type]).x * camera.zoom.x
	half = maxf(ring, MIN_HALF_DP * dp)
	in_field = safe.has_point(point)
	if _under_button(buttons, THROUGH_BAND_DP * dp):
		in_field = false
	for key: StringName in rects:
		if key != HudCorners.CARD and in_field and rects[key].has_point(point):
			in_field = false


## Whether the point is under a button. It is once inside a plain rect and clear only once outside
## every rect grown by `band`, so a unit along a button's edge does not flip the hand.
func _under_button(buttons: Array[Rect2], band: float) -> bool:
	var inside: bool = false
	for rect: Rect2 in buttons:
		if rect.has_point(point) or (_under and rect.grow(band).has_point(point)):
			inside = true
			break
	_under = inside
	return inside


func _forget() -> void:
	_under = false
	unit_id = -1
	point = Vector2.INF
	in_field = false
	_tick = -1
	_version = -1
	_row = -1


## Whether the held unit is still a candidate (its row is reused while `rows_version` holds).
func _holds(snap: MatchSnapshot, sel: TutorialUnitPickDef, runner: MatchRunner) -> bool:
	var ids: PackedInt32Array = snap.unit_id
	var row: int = _row
	if snap.rows_version != _version or row < 0 or row >= ids.size() or ids[row] != unit_id:
		lookups += 1
		row = snap.index_of(unit_id)
	if row < 0:
		return false
	_version = snap.rows_version
	_row = row
	return _fits(snap, sel, row, FogLayer.local_player_of(runner), _type_of(snap, sel))


## One pass over the rows: the best candidate becomes the held unit.
func _scan(
	snap: MatchSnapshot, sel: TutorialUnitPickDef, runner: MatchRunner, camera: RtsCamera
) -> void:
	scans += 1
	var player: int = FogLayer.local_player_of(runner)
	var want: int = _type_of(snap, sel)
	var centre: Vector2i = IsoProjection.px_to_ground(camera.position)
	var ids: PackedInt32Array = snap.unit_id
	var pos_x: PackedInt32Array = snap.pos_x
	var pos_y: PackedInt32Array = snap.pos_y
	var best: int = -1
	var best_gap: int = 0
	for row: int in ids.size():
		if not _fits(snap, sel, row, player, want):
			continue
		var dx: int = pos_x[row] - centre.x
		var dy: int = pos_y[row] - centre.y
		var gap: int = dx * dx + dy * dy
		# Rows ascend by id: a strict "less" keeps the lower id on a tie; NEWEST takes the last.
		if best < 0 or sel.pick == TutorialUnitPickDef.Pick.NEWEST or gap < best_gap:
			best = row
			best_gap = gap
	if best < 0:
		return
	unit_id = ids[best]
	_row = best
	_version = snap.rows_version
	_type = snap.type_index[best]


## The type index the selector names: -1 for any, -2 for a type this match does not have.
static func _type_of(snap: MatchSnapshot, sel: TutorialUnitPickDef) -> int:
	if sel.type_id == &"":
		return -1
	var at: int = snap.type_ids.find(sel.type_id)
	return at if at >= 0 else -2


## Whether row `row` is a candidate: its side, its type, no footprint, and for an enemy a seen cell.
static func _fits(
	snap: MatchSnapshot, sel: TutorialUnitPickDef, row: int, player: int, want: int
) -> bool:
	var owner: int = snap.owner[row]
	var type: int = snap.type_index[row]
	if want != -1 and type != want:
		return false
	if snap.type_foot_w[type] > 0 or owner <= 0:
		return false
	if sel.side == TutorialUnitPickDef.Whose.OWN:
		return owner == player
	return owner != player and FogLayer.is_seen(snap, player, snap.pos_x[row], snap.pos_y[row])
