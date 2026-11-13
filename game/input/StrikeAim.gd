class_name StrikeAim
extends Node
## The local player's strike and its aiming (plan P112, ADR 0023 section 10). Each tick it reads the
## snapshot: `owned` (a strike building of the player's), `building_id` (the first that can fire
## now, else 0: charged, not offline, no rupture of the player's in the air, as
## `Strike.apply_superweapon` checks), `share` of the charge and `wait` in ticks. Aiming: `begin`,
## `place` (PlayerController hands it the map taps), `confirm` (exactly one SUPERWEAPON through
## `controller.command_sink`, then the mode ends) and `cancel` (no Command); a turn of the phone, a
## new match and a strike that cannot fire any more cancel too. It writes nothing to the sim.
##
## One button serves every strike building, so it binds the one that suits the player (P235):
## - A space centre (kind REVEAL, the sweep) whose owner's sweep stands (`reveal_site` set) never
##   competes: the sim drops its SUPERWEAPON, and a fired centre keeps its `ready_tick`, so it would
##   always read "Ready". When it is the only strike building the button shows the sweep, `sweep`
##   1 (on) or 2 (paused), and `building_id` stays 0.
## - The sweep ignores a rupture in the air (`Strike.apply_superweapon` tests it after the kind),
##   and a REVEAL building is refused on low power: `low_power`, with `building_id` 0.
## - A construction site (`build_left` not 0) is no strike building: the sim drops its SUPERWEAPON.
## - While an aim is open, a tie stays with the building it began on, and any other binding ends
##   the aim (never carries the point or the lit check mark to another building).
## - Of the rest the least wait wins, as before; a ready one wins any tie, one refused for low
##   power ranks just after a ready one and before any that still charges.
## - A REVEAL building has no aim: `begin` sets the point at once (`reveal`), so the check mark is
##   lit, map taps are ignored, and `confirm` sends the SUPERWEAPON with the point 0, 0 (the sim
##   ignores it).

signal changed  ## The status or the aim changed.

@export var runner: MatchRunner
@export var controller: PlayerController  ## The Commands' sink, the haptic and the settings.

var owned: bool = false
var building_id: int = 0
var type_index: int = -1  ## Its type, or the best building's while none can fire.
var share: float = 0.0
var wait: int = 0
var radius: int = 0  ## Of `type_index`, milli-tiles.
var reveal: bool = false  ## The bound building is a REVEAL one: no aim, no map tap.
var low_power: bool = false  ## The bound REVEAL building is refused for low power.
var sweep: int = 0  ## The local player's sweep: 0 none, 1 on, 2 paused (`Reveal.State`).
var sweep_bound: bool = false  ## The button is bound to the standing sweep's space centre.
var active: bool = false  ## Aiming.
var has_point: bool = false
var point: Vector2i = Vector2i.ZERO  ## Milli-tiles, inside the map.

var _shown: Vector4i = Vector4i(-1, -1, -1, -1)  ## Owned, building, wait and type last told.
var _shown_flags: int = -1  ## `reveal`, `low_power`, `sweep` and `sweep_bound` last told.
var _serial: int = -1
var _aim_id: int = 0  ## The building the open aim began on (ties stay with it, a change ends it).
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
	var site: int = 0
	var sweep_state: int = 0
	if player >= 0 and player < snap.reveal_site.size() and player < snap.reveal.size():
		site = snap.reveal_site[player]
		sweep_state = snap.reveal[player] if site != 0 else 0
	var short: bool = (
		player >= 0
		and player < mini(snap.power_made.size(), snap.power_used.size())
		and snap.power_used[player] > snap.power_made[player]
	)
	var best: int = -1  # The best key so far: the wait, doubled, plus 1 for a refusal.
	var best_id: int = 0
	var best_type: int = -1
	var best_share: float = 0.0
	var best_refused: bool = false
	var sweep_type: int = -1  # The standing sweep's centre, shown when nothing else is owned.
	var ids: PackedInt32Array = snap.unit_id  # Aliased once: no snapshot property read per row.
	var owners: PackedInt32Array = snap.owner
	var types: PackedInt32Array = snap.type_index
	var ready_ticks: PackedInt32Array = snap.ready_tick
	var offline_ticks: PackedInt32Array = snap.offline_until
	var kinds: PackedInt32Array = snap.type_strike_kind
	var charges: PackedInt32Array = snap.type_charge_ticks
	var building: PackedInt32Array = snap.build_left
	for row: int in ids.size():
		var type: int = types[row]
		if owners[row] != player or type >= kinds.size():
			continue
		var kind: int = kinds[type]
		if kind == Strike.Kind.NONE or building[row] != 0:  # A site is no strike building yet.
			continue
		var is_reveal: bool = kind == Strike.Kind.REVEAL
		if is_reveal and site != 0:  # The sim drops it: a spare waits for the sweep to end.
			if ids[row] == site:
				sweep_type = type
			continue
		var charge: int = maxi(ready_ticks[row] - stamp, 0)
		var hold: int = 0 if is_reveal else pending  # A sweep never waits for a rupture.
		var left: int = maxi(charge, maxi(offline_ticks[row] - stamp, hold))
		var refused: bool = is_reveal and short and left == 0
		var key: int = left * 2 + (1 if refused else 0)
		if best < 0 or key < best or (key == best and active and ids[row] == _aim_id):
			best = key
			best_id = ids[row]
			best_type = type
			best_refused = refused
			best_share = 1.0 - minf(float(charge) / maxi(charges[type], 1), 1.0)
	sweep = sweep_state
	sweep_bound = best < 0 and sweep_type >= 0
	owned = best >= 0 or sweep_bound
	if sweep_bound:
		best_type = sweep_type
		best_share = 1.0
		best_id = 0
		best = 0
	var can_fire: bool = best == 0 and not sweep_bound
	building_id = best_id if can_fire else 0
	type_index = best_type
	reveal = owned and not sweep_bound and kinds[best_type] == Strike.Kind.REVEAL
	low_power = reveal and best_refused
	share = best_share
	wait = (best >> 1) if owned and not sweep_bound else 0
	radius = snap.type_strike_radius[best_type] if owned else 0
	var dropped: bool = active and (building_id != _aim_id or snap.match_serial != _serial)
	_serial = snap.match_serial
	if dropped:
		active = false
		has_point = false
	var key: Vector4i = Vector4i(1 if owned else 0, building_id, wait, type_index)
	var flags: int = (
		(1 if reveal else 0) | (2 if low_power else 0) | (4 if sweep_bound else 0) | (sweep << 3)
	)
	if dropped or key != _shown or flags != _shown_flags:
		_shown = key
		_shown_flags = flags
		changed.emit()


## Starts aiming; false, and nothing changes, while the strike cannot fire or the mode is on.
func begin() -> bool:
	if active or building_id == 0:
		return false
	active = true
	_aim_id = building_id
	has_point = reveal  # The sweep has no aim: the check mark is lit at once.
	point = Vector2i.ZERO
	changed.emit()
	return true


## Sets the point to the ground point `ground` (milli-tiles), held inside the map.
func place(ground: Vector2i) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if not active or snap == null or reveal:  # A sweep takes no point.
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
		if HudPrefs.vibrates(controller.settings):
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
