extends GdUnitTestSuite
## The fixture of the command bar's building-order suites (plan P272): the main scene at a size with
## the Commands, the haptic and the bar's clock caught. Not a test suite.
## The command bar's building orders (plan P272, ADR 0037 sections 3, 4 and 9) in the main scene at
## the six sizes of ScreenSizes.ALL: Mend and Sell show for one own complete building only (never
## for an enemy building, a unit or a site; the Headquarters has no Sell); Mend is a toggle that
## sends one MEND; Sell is a two-tap order that arms on the first tap ("+N" from
## `Production.sale_refund`, amber), sends one SELL on a second tap between `sell_arm_min_ms` and
## `sell_confirm_ms`, and is disarmed by any other touch, the window running out or a turn of the
## phone; a resting thumb never sells; the last producer asks on the question card. The tests set
## their own rules on the snapshot (`sell_refund_percent`), not the shipped ones.
## Player 1 has a Deep Bore (id 1), a light tank (2), a barracks (4), a second barracks (5, when
## `SECOND`) and a Headquarters (6, when `HQ`); player 2 has the Headquarters 3.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const TouchEvents: GDScript = preload("res://tests/support/touch_events.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const BORE: int = 1
const TANK: int = 2
const ENEMY_HQ: int = 3
const BARRACKS: int = 4
const SPARE: int = 5
const OWN_HQ: int = 6
const BASE: Array[Array] = [
	[1, "fossil_strike", 6, 6],
	[1, "light_tank", 14, 14],
	[2, "renew_hq", 20, 20],
	[1, "barracks", 10, 10],
]
const SECOND: Array = [1, "barracks", 10, 16]
const HQ: Array = [1, "headquarters", 24, 6]
const PERCENT: int = 50
const TOLERANCE_PX: float = 0.5

var _window_size_before: Vector2i
var _main: Node2D
var _controller: PlayerController
var _runner: MatchRunner
var _bar: CommandBar
var _sent: Array[Command] = []
var _now: int = 10000
var _buzzes: Array[int] = []


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	MenuRig.begin()


func after_test() -> void:
	MenuRig.end()
	UiScale.clear_override()
	CommandQueue.clear()


## A finger down on `control` `down_ms` after now and up at `up_ms` after now (the test's clock).
func _rest(control: Control, down_ms: int, up_ms: int) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	var start: int = _now
	_now = start + down_ms
	TouchEvents.press(get_viewport(), 0, at)
	_now = start + up_ms
	TouchEvents.release(get_viewport(), 0, at)


func _row(id: int) -> int:
	return _runner.snapshot.index_of(id)


func _x(id: StringName) -> float:
	return _bar.order_button(id).get_global_rect().position.x


func _word(id: StringName) -> Label:
	return _bar.order_button(id).get_node("Face/Word") as Label


func _card() -> ConfirmDialog:
	return _main.get_node("Hud").find_child("SellCard", true, false) as ConfirmDialog


func _select(ids: Array) -> void:
	_controller.selection.set_ids(PackedInt32Array(ids))
	await await_idle_frame()
	await await_idle_frame()


## A tick's worth of publishing: the bar fills from the snapshot the test has written.
func _tick() -> void:
	_runner.ticked.emit(_runner.snapshot.tick)
	await await_idle_frame()


## A tap on the middle of a control, with the touch events a finger sends.
func _tap(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	TouchEvents.press(get_viewport(), 0, at)
	TouchEvents.release(get_viewport(), 0, at)


## A new scene at `size`, its match paused, the Commands caught, the clock the test's.
func _open(size: Vector2i, extra: Array) -> void:
	if _main != null and is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free((load("res://scenes/main.tscn") as PackedScene).instantiate())
	var spawns: Array[SpawnDef] = []
	for entry: Array in BASE + extra:
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	var scenario: ScenarioDef = Rig.scenario(spawns)
	_runner = _main.get_node("MatchRunner") as MatchRunner
	_runner.scenario = scenario
	_runner.paused = true
	add_child(_main)
	await await_idle_frame()
	_controller = _main.get_node("PlayerController")
	_bar = _main.get_node("Hud").find_child("CommandBar", true, false) as CommandBar
	_sent.clear()
	_buzzes.clear()
	_now = 10000
	_controller.command_sink = func(command: Command) -> void: _sent.append(command)
	_controller.vibrate = func(ms: int) -> void: _buzzes.append(ms)
	_bar.clock = func() -> int: return _now
	_runner.snapshot.sell_refund_percent = PERCENT  # The test's own rules, not the shipped ones.
	await await_idle_frame()
