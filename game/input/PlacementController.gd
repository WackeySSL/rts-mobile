class_name PlacementController
extends Node
## Placement mode (plan P86 and P86b, ADR 0019 section 2, ADR 0023 section 3): the local state of
## putting a finished structure on the map. A tap on a READY card calls `begin`; the ghost then
## stands on a tile, judged by `Placement.reason` over the latest snapshot, and no Command is sent
## until the check mark (`confirm`: one PLACE through `controller.command_sink`). It reads the
## snapshot afresh and writes nothing to the sim. `tile` is the tile that holds the footprint's
## centre, as the sim names a remembered building (`ghost_cell`); `origin()`, that less half the
## footprint, is the PLACE tile.
## Pending and "Blocked" (P86b): after the PLACE the mode stays and the ghost is held (`pending`: it
## does not move, the check mark cannot send a second PLACE). The runner stamps the Command with the
## tick it is applied at, and the first snapshot published after that tick holds the sim's answer: a
## building of the type at the ghost's centre ends the mode; no building and the structure still
## ready at the head of the queue means the sim refused (a unit rolled onto the footprint after the
## snapshot the ghost was judged on) and the ghost turns `blocked`: red, with the word, until the
## player moves it, then confirms again or cancels; no building and no ready structure (an earlier
## PLACE used it up) ends the mode. The X ends the mode in either state, also while pending (the
## PLACE is then already on its way). While the match is paused no tick runs, so the ghost stays
## pending and the X works; the answer comes when the ticks do. The end of the match ends the mode.
## Gestures (`PlayerController` hands them over while the mode is on): a drag that starts within
## `ghost_grab_dp` of the ghost's silhouette moves it, the ghost `ghost_lift_dp` above the finger
## and snapping to tiles (`grabs` is the recognizer's test, GHOST_DRAG its events); a drag elsewhere
## pans; a tap anywhere but on the ghost itself moves it to the tile under the finger; a release
## alone never places and a hold draws no box. A turn keeps the tile (the recognizer cancels the
## drag with no event). A new match, a strike aim and the X end the mode with no Command.
## The build menu goes down while the mode runs (P85f, `BuildSidebar`), but its Build button stays
## live: brought up with it (or, from P85f2, kept up by a pin), the cards are on show and a tap on
## the READY card reaches `begin` again: outside pending it puts the ghost back at the view's
## centre; while a PLACE is in flight it changes nothing (the ghost is held, `begin` refuses). A
## hold on that card cancels the last one of that building queued (refunded): `refresh` ends the
## mode when the structure is no longer ready at the head of the queue, whatever the cause, outside
## pending too.
## Edge pan (P86b): while a ghost drag's finger is in the edge band, `TouchInput` calls `edge_pan`
## every frame, which scrolls the map that way and keeps the ghost on the tile under the finger's
## lifted point. The bands lie inside the map view: the safe area, less the build menu below it
## (`HudLayout.menu_top_px`, its real top). The dp and the safe area are read when the window
## changes (`read_metrics`), not per frame.
## Beside the ghost (P86c, ADR 0024 section 10) stand the check mark and the X (`GhostControls`):
## they hide while the ghost is dragged (`dragging`, set by `TouchInput`) and find their place from
## the ghost's silhouette box (`silhouette_rect`).

signal changed  ## The mode began or ended, or the ghost's tile, verdict or answer changed.

@export var runner: MatchRunner
@export var controller: PlayerController  ## The Commands' sink, the haptic and the settings.
@export var camera: RtsCamera
@export var ghost_layer: GhostLayer  ## Tells how high the picture rises, for the grab area.
@export var strike_aim: StrikeAim  ## Aiming a strike and placing a building exclude each other.

var active: bool = false
var type_index: int = -1  ## The World type being placed.
var foot: Vector2i = Vector2i.ONE  ## Its footprint, tiles.
var tile: Vector2i = Vector2i.ZERO  ## The tile that holds the footprint's centre.
var reason: int = Placement.Reason.OK  ## `Placement.Reason` of the footprint at `tile`.
var pending: bool = false  ## A PLACE was sent and the snapshot has not answered yet.
var blocked: bool = false  ## The sim refused the last PLACE; the ghost is red until it moves.
## A finger holds the ghost (the recognizer is in its GRAB state): `TouchInput` keeps it. The check
## mark and the X hide meanwhile, so the ghost's edge pan and its lifted point have the screen.
var dragging: bool = false

var _serial: int = -1  ## match_serial the mode began in.
var _command: Command = null  ## The PLACE in flight; the runner stamps its `tick`.
var _dp_px: float = 1.0  ## `UiScale.base_px_per_dp()`, read when the window changes.
var _safe: Rect2 = Rect2()  ## `UiScale.safe_rect_base()`, likewise.


func _ready() -> void:
	get_viewport().size_changed.connect(read_metrics)
	read_metrics()
	if runner != null:
		runner.ticked.connect(refresh.unbind(1))
		runner.match_ended.connect(cancel.unbind(1))
	if strike_aim != null:
		strike_aim.changed.connect(_on_aim_changed)


## Reads the base px per dp and the safe area again: a resize does it, and a test that puts in
## another `UiScale` override must call it. Every frame of an edge pan asks for them, and the
## engine's metrics are not cheap (a new `UiMetrics`, the platform's dpi and safe area).
func read_metrics() -> void:
	_dp_px = UiScale.base_px_per_dp()
	_safe = UiScale.safe_rect_base()


## Starts the mode for the structure of `type`: the ghost at the tile under the view's centre.
## False, with nothing changed, without a snapshot, for a type that has no footprint and while a
## PLACE is in flight (the card is still READY then, and a tap on it must not send a second one).
func begin(type: int) -> bool:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null or type < 0 or type >= snap.type_foot_w.size() or snap.type_foot_w[type] < 1:
		return false
	if active and pending:
		return false
	if strike_aim != null:
		strike_aim.cancel()
	active = true
	_forget_place()
	type_index = type
	foot = Vector2i(snap.type_foot_w[type], snap.type_foot_h[type])
	_serial = snap.match_serial
	tile = _tile_at(camera.position)
	reason = _judge(snap)
	changed.emit()
	return true


## The top-left tile of the footprint, the tile PLACE names.
func origin() -> Vector2i:
	return tile - foot / 2


## The ground point, milli-tiles, of the footprint's centre.
func centre_ground() -> Vector2i:
	return (origin() * 2 + foot) * World.TILE_CENTRE


## Whether the ghost fits as far as anyone knows: the snapshot's verdict is OK and the sim has not
## refused a PLACE here since the ghost last moved.
func fits() -> bool:
	return reason == Placement.Reason.OK and not blocked


## Whether the check mark would send a PLACE: the ghost fits and none is in flight.
func can_confirm() -> bool:
	return active and not pending and fits()


## The check mark: one PLACE for the origin tile. The mode stays, the ghost pending until the
## snapshot answers (`refresh`). False, with no Command, while `can_confirm` is false.
func confirm() -> bool:
	if not can_confirm() or controller == null:
		return false
	var at: Vector2i = origin() * World.MILLI_PER_TILE + Vector2i.ONE * World.TILE_CENTRE
	_command = Command.place(runner.scenario.local_player, at.x, at.y)
	pending = true
	controller.command_sink.call(_command)
	if controller.settings.haptics_enabled:
		controller.vibrate.call(controller.settings.haptic_ms)
	changed.emit()
	return true


## The X: the mode ends and the structure stays ready. Nothing is sent. A PLACE already in flight
## is not recalled.
func cancel() -> void:
	if active:
		active = false
		_forget_place()
		changed.emit()


## Judges the ghost again on the latest snapshot; a new match ends the mode, and so does a
## structure that is no longer ready at the head of the queue (a hold on its card cancelled it, or
## an earlier PLACE used it up). While a PLACE is pending it reads the sim's answer instead, once
## the snapshot is past the Command's tick. It runs
## from `runner.ticked` only (a test may call it with the runner idle): it reads `Command.tick`,
## which the worker stamps, and that is safe there alone, after the hand-off and before the next
## job is posted.
func refresh() -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if not active or snap == null:
		return
	if snap.match_serial != _serial:
		cancel()
		return
	if pending:
		_answer(snap)
		return
	if not _ready_head(snap):
		cancel()
		return
	var next: int = _judge(snap)
	if next != reason:
		reason = next
		changed.emit()


## The recognizer's test for a press at `at` (base px): within `ghost_grab_dp` of the silhouette.
## A pending ghost is held: nothing grabs it.
func grabs(at: Vector2) -> bool:
	return active and not pending and _near(at, controller.settings.ghost_grab_dp * _dp_px)


## The gestures of the mode (PlayerController calls it while `active`): GHOST_DRAG moves the ghost
## under the finger's lifted point, a tap moves it to the tapped tile unless it is on the ghost.
func handle_gesture(e: GestureEvent) -> void:
	match e.kind:
		GestureEvent.Kind.GHOST_DRAG:
			_track(e.position)
		GestureEvent.Kind.TAP, GestureEvent.Kind.DOUBLE_TAP:
			if not _near(e.position, 0.0):
				_move_to(_tile_at(camera.screen_to_world(e.position)))


## Which way the map scrolls for a ghost drag whose finger is at `finger` (base px): a unit vector
## toward the edge band the finger is in, the diagonal in a corner, zero outside the bands. The
## bands lie `edge_band_dp` inside the edges of the map view: the safe area (a finger in a cutout
## is in them too), whose bottom edge is the build menu's real top (`HudLayout.menu_top_px`: in
## portrait the band covers the map there, and with a top cutout it stands higher than the safe
## area's bottom less its height). The ghost rides `ghost_lift_dp` above the finger, so the top
## band is measured on the ghost's point: the map starts to scroll while the ghost is still in
## view, not after it left it. The other three are measured on the finger, because the ghost is
## never near the bottom edge.
func edge_heading(finger: Vector2) -> Vector2:
	var settings: InputSettings = controller.settings
	var band: float = settings.edge_band_dp * _dp_px
	var ghost_y: float = finger.y - settings.ghost_lift_dp * _dp_px
	var bottom: float = HudLayout.map_bottom_px(_safe)
	var heading: Vector2 = Vector2.ZERO
	if finger.x < _safe.position.x + band:
		heading.x = -1.0
	elif finger.x > _safe.end.x - band:
		heading.x = 1.0
	if ghost_y < _safe.position.y + band:
		heading.y = -1.0
	elif finger.y > bottom - band:
		heading.y = 1.0
	return heading.normalized()


## Called every frame while a ghost drag's finger is at `finger`, `delta` seconds after the last
## call: in an edge band the map scrolls toward the edge at `edge_pan_dp_per_s` of screen (the
## same at any zoom and frame rate, within the camera's clamp) and the ghost stays on the tile under
## the finger's lifted point, though the finger has not moved. A frame that took longer than
## `edge_pan_max_step_ms` scrolls that long and no more, so a stall is not a jump. Nothing is sent.
## A pending ghost is held.
func edge_pan(finger: Vector2, delta: float) -> void:
	if not active or pending:
		return
	var heading: Vector2 = edge_heading(finger)
	if heading == Vector2.ZERO:
		return
	var settings: InputSettings = controller.settings
	var step: float = minf(delta, settings.edge_pan_max_step_ms / 1000.0)
	camera.pan_by_screen(-heading * settings.edge_pan_dp_per_s * _dp_px * step)
	_track(finger)


## The box round the ghost's silhouette on the screen, base px (the `_near` shape with no margin):
## the footprint's width, from the picture's top down to the diamond's lowest corner. Empty while
## the mode is off. `GhostControls` stands its buttons beside it.
func silhouette_rect() -> Rect2:
	if not active:
		return Rect2()
	var half: Vector2 = _half_extent()
	var rise: float = _rise(half)
	return Rect2(_ghost_centre() - Vector2(half.x, rise), Vector2(half.x * 2.0, rise + half.y))


## The screen point of the footprint's centre on the ground.
func _ghost_centre() -> Vector2:
	var ground: Vector2i = centre_ground()
	return camera.world_to_screen(IsoProjection.ground_to_px(ground.x, ground.y))


## Half the footprint's diamond on the screen, base px.
func _half_extent() -> Vector2:
	var side: float = camera.zoom.x * (foot.x + foot.y) * 0.5
	return Vector2(IsoProjection.HALF_W, IsoProjection.HALF_H) * side


## How far the picture rises above the footprint's centre, base px: not less than the diamond's.
func _rise(half: Vector2) -> float:
	return half.y if ghost_layer == null else maxf(ghost_layer.rise_px() * camera.zoom.x, half.y)


## Whether the ghost's silhouette (the footprint's diamond and the rectangle from its side corners
## up to the picture's top, ADR 0023 section 3), grown by `margin` base px all round, holds `at`.
func _near(at: Vector2, margin: float) -> bool:
	if not active:
		return false
	var from: Vector2 = at - _ghost_centre()
	var half: Vector2 = _half_extent()
	var rise: float = _rise(half)
	if absf(from.x) > half.x + margin or from.y < -rise - margin or from.y > half.y + margin:
		return false
	if from.y <= margin:
		return true
	# The diamond's lower edges lie where |x| / a + y / b = 1; a line `margin` away from one is at
	# 1 + margin * sqrt(1 / a^2 + 1 / b^2), so the margin is the same across the edge as everywhere.
	var grown: float = 1.0 + margin * sqrt(1.0 / (half.x * half.x) + 1.0 / (half.y * half.y))
	return absf(from.x) / half.x + from.y / half.y <= grown


## The tile that holds the ground point under the world px `world`.
func _tile_at(world: Vector2) -> Vector2i:
	var ground: Vector2i = IsoProjection.px_to_ground(world)
	return Vector2i(
		floori(float(ground.x) / World.MILLI_PER_TILE),
		floori(float(ground.y) / World.MILLI_PER_TILE)
	)


## The ghost on the tile under the point `ghost_lift_dp` above the finger at `finger`.
func _track(finger: Vector2) -> void:
	var lift: float = controller.settings.ghost_lift_dp * _dp_px
	_move_to(_tile_at(camera.screen_to_world(finger - Vector2(0.0, lift))))


## Moves the ghost to tile `next` and judges it: it clears "Blocked". A pending ghost is held.
func _move_to(next: Vector2i) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if next == tile or snap == null or pending:
		return
	tile = next
	blocked = false
	reason = _judge(snap)
	changed.emit()


## The sim's answer to the PLACE in flight, once a snapshot is past the Command's tick (`tick` is -1
## until the runner takes the Command, and the snapshot of the tick it is applied at has the next
## tick): a building at the ghost's centre ends the mode, and so does a queue with no ready
## structure of the type (an earlier PLACE used it up: the X and a second tap on the card, within
## two ticks); the structure still ready and no building there means the sim refused: "Blocked".
func _answer(snap: MatchSnapshot) -> void:
	if _command.tick < 0 or snap.tick <= _command.tick:
		return
	_forget_place()
	if _built(snap) or not _ready_head(snap):
		active = false
	else:
		blocked = true
		reason = _judge(snap)
	changed.emit()


## Whether the snapshot has a building of the type being placed, the local player's, at the ghost.
func _built(snap: MatchSnapshot) -> bool:
	var at: Vector2i = centre_ground()
	var player: int = runner.scenario.local_player
	for row: int in snap.unit_count():
		if (
			snap.owner[row] == player
			and snap.type_index[row] == type_index
			and snap.pos_x[row] == at.x
			and snap.pos_y[row] == at.y
		):
			return true
	return false


## Whether the head of the local player's STRUCTURES queue is a finished structure of the type being
## placed (the sidebar's READY state, `Production.apply_place`'s first test).
@warning_ignore("integer_division")
func _ready_head(snap: MatchSnapshot) -> bool:
	var queue: int = runner.scenario.local_player * World.TABS + World.Tab.STRUCTURES
	if queue >= snap.queue_count.size() or snap.queue_count[queue] == 0:
		return false
	var slots: int = snap.queue_type.size() / (snap.credits.size() * World.TABS)
	if snap.queue_type[queue * slots] != type_index:
		return false
	return (
		snap.queue_progress[queue]
		>= snap.type_build_ticks[type_index] * Production.PROGRESS_PER_TICK
	)


func _forget_place() -> void:
	pending = false
	blocked = false
	_command = null


func _judge(snap: MatchSnapshot) -> int:
	var at: Vector2i = origin()
	return Placement.reason(
		snap.placement_input(), runner.scenario.local_player, type_index, at.x, at.y
	)


## Aiming a strike ends placement (and `begin` ends the aim), so one mode owns the map's taps.
func _on_aim_changed() -> void:
	if strike_aim.active:
		cancel()
