class_name CarryAim
extends Node
## The Board, Unload and Mine aims of the command bar (ADR 0036 sections 8 and 12, `touch-ui-rules`
## "Orders and their aims"). Board: with squads selected, a tap on an own carrier with a free seat
## rings it (`carrier_id`); the check mark sends one LOAD. Unload: with a loaded carrier selected, a
## tap on the ground sets the point (a chevron marks it, another tap moves it); the check mark sends
## one UNLOAD for the selected loaded carriers. Any other tap while boarding is refused (`refused`,
## the view shakes) and sends nothing. It writes nothing to the sim: the Command leaves through
## `controller.command_sink`, exactly one per aim, and the mode ends first.
## Mine (P294, the "MineAim"): with minelayers selected, a ground tap sets the point (a mark and the
## blast ring show, another tap moves them); the check mark sends one LAY_MINE for the selected
## layers. Like Unload it refuses a tap on an own unit or building (a shake, no point).
## The aim ends with nothing sent on `cancel` (the X, a second tap on the button), a turn of the
## phone, a new match, a selection or world that no longer holds what the order serves, and when
## placement or the strike aim begins, and (Mine) the player reaches `mine_cap`; beginning it ends
## both of those (one mode owns the taps).

signal changed  ## The mode, the ringed carrier or the point changed.
signal refused  ## A tap the aim refuses: no seat free (Board), an own thing (Unload, Mine).

enum Mode { NONE, BOARD, UNLOAD, MINE }

@export var runner: MatchRunner
@export var controller: PlayerController  ## The Commands' sink, the haptic and the selection.
@export var placement: PlacementController
@export var strike_aim: StrikeAim

var mode: Mode = Mode.NONE
var carrier_id: int = 0  ## Board: the ringed carrier, 0 for none yet.
var has_point: bool = false  ## Unload and Mine: a ground point is set.
var point: Vector2i = Vector2i.ZERO  ## Milli-tiles, inside the map.

var _blast: int = 0  ## Mine: the ring's radius, worked out when the aim starts and each tick.

var _serial: int = -1
var _portrait: bool = false


func _ready() -> void:
	_portrait = UiScale.is_portrait_size(get_tree().root.size)
	get_viewport().size_changed.connect(_on_size_changed)
	if runner != null:
		runner.ticked.connect(refresh.unbind(1))
	if controller != null:
		controller.selection_changed.connect(refresh.unbind(1))
	if placement != null:
		placement.changed.connect(_on_other_mode)
	if strike_aim != null:
		strike_aim.changed.connect(_on_other_mode)


## Whether an aim is open.
func is_active() -> bool:
	return mode != Mode.NONE


## Whether `want` can start now: Board needs squads selected and a carrier with a free seat on the
## map, Unload a loaded carrier selected, Mine minelayers selected while under the mine cap.
func can_begin(want: Mode) -> bool:
	var snap: MatchSnapshot = null if runner == null or controller == null else runner.snapshot
	if snap == null or runner.scenario == null:
		return false
	var player: int = runner.scenario.local_player
	var ids: PackedInt32Array = controller.selection.selected
	if want == Mode.BOARD:
		return (
			not CarryRules.squads_in(snap, ids, player).is_empty()
			and CarryRules.has_carrier(snap, player)
		)
	if want == Mode.MINE:
		return (
			not CarryRules.layers_in(snap, ids, player).is_empty()
			and CarryRules.mines_laid(snap, player) < snap.mine_cap
		)
	return want == Mode.UNLOAD and not CarryRules.loaded_in(snap, ids, player).is_empty()


## A tap on the order's button: starts the aim, ends it when it is this one's already, and moves to
## this one from the other. False when the order cannot start or the tap ended the aim.
func toggle(want: Mode) -> bool:
	if mode == want:
		cancel()
		return false
	if not can_begin(want):
		return false
	mode = want  # First: the command bar keeps its slot through the swap of modes.
	_blast = 0
	if want == Mode.MINE:
		var ids: PackedInt32Array = controller.selection.selected
		_blast = CarryRules.blast_of(runner.snapshot, ids, runner.scenario.local_player)
	carrier_id = 0
	has_point = false
	_serial = runner.snapshot.match_serial
	if placement != null:
		placement.cancel()
	if strike_aim != null:
		strike_aim.cancel()
	changed.emit()
	return true


## Board: a tap on row `id`. An own carrier with a free seat is ringed (another moves the ring);
## anything else is refused with no Command. False for a refusal or when the aim is not Board.
func pick_carrier(id: int) -> bool:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if mode != Mode.BOARD or snap == null:
		return false
	var row: int = snap.index_of(id)
	if row < 0 or not CarryRules.can_take_squads(snap, row, runner.scenario.local_player):
		refused.emit()
		return false
	carrier_id = id
	changed.emit()
	return true


## A tap the aim does not take (an own unit or building during Unload or Mine): the view shakes
## the button.
func refuse() -> void:
	if mode != Mode.NONE:
		refused.emit()


## Unload and Mine: sets the point to ground point `ground` (milli-tiles), held inside the map.
func place(ground: Vector2i) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if (mode != Mode.UNLOAD and mode != Mode.MINE) or snap == null:
		return
	var far: Vector2i = Vector2i(snap.map_cols, snap.map_rows) * ViewScale.MILLI_PER_TILE
	point = Vector2i(
		clampi(ground.x, 0, maxi(far.x - 1, 0)), clampi(ground.y, 0, maxi(far.y - 1, 0))
	)
	has_point = true
	changed.emit()


## Mine: the blast radius of the selected layers' mines, milli-tiles (the ring's size).
func blast_milli() -> int:
	return _blast


## Whether the check mark can send now: a carrier is ringed, or (Unload, Mine) a point is set.
func can_confirm() -> bool:
	return (
		(mode == Mode.BOARD and carrier_id != 0)
		or (has_point and (mode == Mode.UNLOAD or mode == Mode.MINE))
	)


## The check mark: exactly one LOAD, UNLOAD or LAY_MINE, then the aim ends; false, with nothing
## sent, when
## it cannot send (the aim ends either way, so a second press is a no-op).
func confirm() -> bool:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	var sent: bool = false
	if can_confirm() and snap != null and controller != null:
		var player: int = runner.scenario.local_player
		var ids: PackedInt32Array = controller.selection.selected
		if mode == Mode.BOARD:
			var squads: PackedInt32Array = CarryRules.squads_in(snap, ids, player)
			sent = not squads.is_empty()
			if sent:
				controller.command_sink.call(Command.board(player, squads, carrier_id))
		elif mode == Mode.MINE:
			var layers: PackedInt32Array = CarryRules.layers_in(snap, ids, player)
			sent = not layers.is_empty()
			if sent:
				controller.command_sink.call(Command.lay_mine(player, layers, point.x, point.y))
		else:
			var carriers: PackedInt32Array = CarryRules.loaded_in(snap, ids, player)
			sent = not carriers.is_empty()
			if sent:
				controller.command_sink.call(Command.unload(player, carriers, point.x, point.y))
		if sent and HudPrefs.vibrates(controller.settings):
			controller.vibrate.call(controller.settings.haptic_ms)
	cancel()
	return sent


## Ends the aim and sends nothing.
func cancel() -> void:
	if mode == Mode.NONE:
		return
	mode = Mode.NONE
	carrier_id = 0
	has_point = false
	changed.emit()


## Brings the aim up to date with the selection and the snapshot: it ends when what it serves is
## gone (no squads, no loaded carrier, no minelayer or the mine cap reached, a new match), and a
## ringed carrier that cannot take squads any more loses its ring.
func refresh() -> void:
	if mode == Mode.NONE:
		return
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null or snap.match_serial != _serial:
		cancel()
		return
	var ids: PackedInt32Array = controller.selection.selected
	var player: int = runner.scenario.local_player
	if mode == Mode.MINE:
		if (
			CarryRules.layers_in(snap, ids, player).is_empty()
			or CarryRules.mines_laid(snap, player) >= snap.mine_cap
		):
			cancel()
		else:
			_blast = CarryRules.blast_of(snap, ids, player)
	elif mode == Mode.UNLOAD:
		if CarryRules.loaded_in(snap, ids, player).is_empty():
			cancel()
	elif CarryRules.squads_in(snap, ids, player).is_empty():
		cancel()
	elif carrier_id != 0:
		var row: int = snap.index_of(carrier_id)
		if row < 0 or not CarryRules.can_take_squads(snap, row, player):
			carrier_id = 0
			changed.emit()


func _on_other_mode() -> void:
	if (placement != null and placement.active) or (strike_aim != null and strike_aim.active):
		cancel()


## A turn of the phone ends the aim (ADR 0015 section 3): its point and ring are of the old layout.
func _on_size_changed() -> void:
	var portrait: bool = UiScale.is_portrait_size(get_tree().root.size)
	if portrait != _portrait:
		_portrait = portrait
		cancel()
