class_name PlacementController
extends Node
## Placement mode (plan P86, ADR 0019 section 2, ADR 0023 section 3): the local state of putting a
## finished structure on the map. A tap on a READY card calls `begin`; the ghost then stands on a
## tile, judged by `Placement.reason` over the latest snapshot, and no Command is sent until the
## check mark (`confirm`: one PLACE through `controller.command_sink`, then the mode ends; whether
## the sim took it is row P86b's "pending" and "Blocked"). It reads the snapshot afresh and writes
## nothing to the sim. `tile` is the tile that holds the footprint's centre, as the sim names a
## remembered building (`ghost_cell`); `origin()`, that less half the footprint, is the PLACE tile.
## Gestures (`PlayerController` hands them over while the mode is on): a drag that starts within
## `ghost_grab_dp` of the ghost's silhouette moves it, the ghost `ghost_lift_dp` above the finger
## and snapping to tiles (`grabs` is the recognizer's test, GHOST_DRAG its events); a drag elsewhere
## pans; a tap anywhere but on the ghost itself moves it to the tile under the finger; a release
## alone never places and a hold draws no box. A turn keeps the tile (the recognizer cancels the
## drag with no event). A new match, a strike aim and the X end the mode with no Command.

signal changed  ## The mode began or ended, or the ghost's tile or verdict changed.

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

var _serial: int = -1  ## match_serial the mode began in.


func _ready() -> void:
	if runner != null:
		runner.ticked.connect(refresh.unbind(1))
	if strike_aim != null:
		strike_aim.changed.connect(_on_aim_changed)


## Starts the mode for the structure of `type`: the ghost at the tile under the view's centre.
## False, with nothing changed, without a snapshot or for a type that has no footprint.
func begin(type: int) -> bool:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null or type < 0 or type >= snap.type_foot_w.size() or snap.type_foot_w[type] < 1:
		return false
	if strike_aim != null:
		strike_aim.cancel()
	active = true
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


## The check mark: one PLACE for the origin tile, then the mode ends. False, with no Command and
## the mode kept, while the ghost does not fit.
func confirm() -> bool:
	var place: bool = active and reason == Placement.Reason.OK and controller != null
	if place:
		var at: Vector2i = origin() * World.MILLI_PER_TILE + Vector2i.ONE * World.TILE_CENTRE
		var player: int = runner.scenario.local_player
		controller.command_sink.call(Command.place(player, at.x, at.y))
		if controller.settings.haptics_enabled:
			controller.vibrate.call(controller.settings.haptic_ms)
		cancel()
	return place


## The X: the mode ends and the structure stays ready. Nothing is sent.
func cancel() -> void:
	if active:
		active = false
		changed.emit()


## Judges the ghost again on the latest snapshot; a new match ends the mode.
func refresh() -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if not active or snap == null:
		return
	if snap.match_serial != _serial:
		cancel()
		return
	var next: int = _judge(snap)
	if next != reason:
		reason = next
		changed.emit()


## The recognizer's test for a press at `at` (base px): within `ghost_grab_dp` of the silhouette.
func grabs(at: Vector2) -> bool:
	return active and _near(at, UiScale.dp(controller.settings.ghost_grab_dp))


## The gestures of the mode (PlayerController calls it while `active`): GHOST_DRAG moves the ghost
## under the finger's lifted point, a tap moves it to the tapped tile unless it is on the ghost.
func handle_gesture(e: GestureEvent) -> void:
	match e.kind:
		GestureEvent.Kind.GHOST_DRAG:
			var lift: float = UiScale.dp(controller.settings.ghost_lift_dp)
			_move_to(_tile_at(camera.screen_to_world(e.position - Vector2(0.0, lift))))
		GestureEvent.Kind.TAP, GestureEvent.Kind.DOUBLE_TAP:
			if not _near(e.position, 0.0):
				_move_to(_tile_at(camera.screen_to_world(e.position)))


## Whether the ghost's silhouette (the footprint's diamond and the rectangle from its side corners
## up to the picture's top, ADR 0023 section 3), grown by `margin` base px all round, holds `at`.
func _near(at: Vector2, margin: float) -> bool:
	if not active:
		return false
	var zoom: float = camera.zoom.x
	var ground: Vector2i = centre_ground()
	var from: Vector2 = at - camera.world_to_screen(IsoProjection.ground_to_px(ground.x, ground.y))
	var half: Vector2 = (
		Vector2(IsoProjection.HALF_W, IsoProjection.HALF_H) * (zoom * (foot.x + foot.y) * 0.5)
	)
	var rise: float = half.y if ghost_layer == null else maxf(ghost_layer.rise_px() * zoom, half.y)
	if absf(from.x) > half.x + margin or from.y < -rise - margin or from.y > half.y + margin:
		return false
	if from.y <= margin:
		return true
	return absf(from.x) / half.x + from.y / half.y <= 1.0 + margin / half.x + margin / half.y


## The tile that holds the ground point under the world px `world`.
func _tile_at(world: Vector2) -> Vector2i:
	var ground: Vector2i = IsoProjection.px_to_ground(world)
	return Vector2i(
		floori(float(ground.x) / World.MILLI_PER_TILE),
		floori(float(ground.y) / World.MILLI_PER_TILE)
	)


func _move_to(next: Vector2i) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if next == tile or snap == null:
		return
	tile = next
	reason = _judge(snap)
	changed.emit()


func _judge(snap: MatchSnapshot) -> int:
	var at: Vector2i = origin()
	return Placement.reason(
		snap.placement_input(), runner.scenario.local_player, type_index, at.x, at.y
	)


## Aiming a strike ends placement (and `begin` ends the aim), so one mode owns the map's taps.
func _on_aim_changed() -> void:
	if strike_aim.active:
		cancel()
