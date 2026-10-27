class_name StrikeAim
extends Node
## The local player's strike and its aiming (plan P112, ADR 0023 section 10). Each tick it reads the
## snapshot: `owned` (a strike building of the player's), `building_id` (the first that can fire
## now, else 0: charged, not offline, no rupture of the player's in the air, as
## `Strike.apply_superweapon` checks), `share` of the charge and `wait` in ticks. Aiming: `begin`,
## `place` (PlayerController hands it the map taps), `confirm` (exactly one SUPERWEAPON through
## `controller.command_sink`, then the mode ends) and `cancel` (no Command); a turn of the phone, a
## new match and a strike that cannot fire any more cancel too. It writes nothing to the sim.

signal changed  ## The status or the aim changed.

@export var runner: MatchRunner
@export var controller: PlayerController  ## The Commands' sink, the haptic and the settings.

var owned: bool = false
var building_id: int = 0
var type_index: int = -1  ## Its type, or the best building's while none can fire.
var share: float = 0.0
var wait: int = 0
var radius: int = 0  ## Of `type_index`, milli-tiles.
var active: bool = false  ## Aiming.
var has_point: bool = false
var point: Vector2i = Vector2i.ZERO  ## Milli-tiles, inside the map.

var _shown: Vector4i = Vector4i(-1, -1, -1, -1)  ## Owned, building, wait and type last told.
var _serial: int = -1
var _portrait: bool = false  ## The window's orientation at the last resize.


func _ready() -> void:
	_portrait = UiScale.is_portrait_size(get_tree().root.size)
	get_viewport().size_changed.connect(_on_size_changed)
	if runner != null:
		runner.ticked.connect(refresh.unbind(1))
		refresh()


## Reads the snapshot and tells `changed` when anything moved.
func refresh() -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null or runner.scenario == null:
		return
	var player: int = runner.scenario.local_player
	var stamp: int = snap.tick + 1
	var pending: int = 0  # A rupture in the air holds every strike building until it lands.
	if player >= 0 and player < snap.strike_tick.size() and snap.strike_tick[player] != 0:
		pending = maxi(snap.strike_tick[player] - snap.tick, 1)
	var best: int = -1  # Ticks to wait of the best building so far.
	var best_id: int = 0
	var best_type: int = -1
	var best_share: float = 0.0
	for row: int in snap.unit_id.size():
		var type: int = snap.type_index[row]
		if snap.owner[row] != player or type >= snap.type_strike_kind.size():
			continue
		if snap.type_strike_kind[type] == Strike.Kind.NONE:
			continue
		var charge: int = maxi(snap.ready_tick[row] - stamp, 0)
		var left: int = maxi(charge, maxi(snap.offline_until[row] - stamp, pending))
		if best < 0 or left < best:
			best = left
			best_id = snap.unit_id[row]
			best_type = type
			best_share = 1.0 - minf(float(charge) / maxi(snap.type_charge_ticks[type], 1), 1.0)
	owned = best >= 0
	building_id = best_id if best == 0 else 0
	type_index = best_type
	share = best_share
	wait = maxi(best, 0)
	radius = snap.type_strike_radius[best_type] if owned else 0
	var dropped: bool = active and (building_id == 0 or snap.match_serial != _serial)
	_serial = snap.match_serial
	if dropped:
		active = false
		has_point = false
	var key: Vector4i = Vector4i(1 if owned else 0, building_id, wait, type_index)
	if dropped or key != _shown:
		_shown = key
		changed.emit()


## Starts aiming; false, and nothing changes, while the strike cannot fire or the mode is on.
func begin() -> bool:
	if active or building_id == 0:
		return false
	active = true
	has_point = false
	changed.emit()
	return true


## Sets the point to the ground point `ground` (milli-tiles), held inside the map.
func place(ground: Vector2i) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if not active or snap == null:
		return
	var far: Vector2i = Vector2i(snap.map_cols, snap.map_rows) * ViewScale.MILLI_PER_TILE
	point = Vector2i(
		clampi(ground.x, 0, maxi(far.x - 1, 0)), clampi(ground.y, 0, maxi(far.y - 1, 0))
	)
	has_point = true
	changed.emit()


## The check mark: one SUPERWEAPON for the building that can fire, at the point; false, with no
## Command, when there is none to send. The mode ends first, so a second press is a no-op.
func confirm() -> bool:
	var fire: bool = active and has_point and building_id != 0 and controller != null
	if fire:
		var player: int = runner.scenario.local_player
		controller.command_sink.call(Command.superweapon(player, building_id, point.x, point.y))
		if controller.settings.haptics_enabled:
			controller.vibrate.call(controller.settings.haptic_ms)
	cancel()
	return fire


## Ends the mode and sends nothing.
func cancel() -> void:
	if not active:
		return
	active = false
	has_point = false
	changed.emit()


## A turn of the phone cancels the aim (ADR 0015 section 3): the point is of the old layout.
func _on_size_changed() -> void:
	var portrait: bool = UiScale.is_portrait_size(get_tree().root.size)
	if portrait != _portrait:
		_portrait = portrait
		cancel()
