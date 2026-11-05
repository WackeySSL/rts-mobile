extends GdUnitTestSuite
## The HUD is view only (plan P125, ADR 0025 sections 1 and 17, the method of P62): a scripted
## main-scene run of the Derrick League's Skirmish against its dummy, with the same Commands at the
## same ticks, ends with the same state hash, checked every 15 ticks, and the same command log as
## the run in which the HUD is worked between the ticks: the drawer opened and closed, a selection
## and Deselect, a pause and Resume, the full map opened and pinned and folded, and the economy
## card opened from the pill with the drawer open and closed by the next touch. Nothing the HUD does
## queues a Command, and pause sends none.
## Time is the test's: the match is paused except for the instant between a pause menu's open or
## Resume and the line that pauses it again, with no frame between, and only `run_ticks` plays, so
## the frames that the HUD actions wait for play no tick.

const HudWalk: GDScript = preload("res://tests/ui/support/hud_walk.gd")
const MatchRig: GDScript = preload("res://tests/ui/support/match_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const PERIOD: int = 15  ## Ticks between two checks.
const CHUNKS: int = 12
## Where the scripted Commands send the player's units, in milli-tiles.
const TARGET: Vector2i = Vector2i(14000, 14000)

var _window_size_before: Vector2i
var _main: Node


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


func test_a_run_with_hud_actions_ends_in_the_hash_of_the_run_without_them() -> void:
	for size: Vector2i in [ScreenSizes.LANDSCAPE[0], ScreenSizes.PORTRAIT[0]]:
		var plain: Dictionary = await _play(size, false)
		var worked: Dictionary = await _play(size, true)
		assert_int(plain["hashes"].size()).is_equal(CHUNKS)
		assert_array(plain["log"]).is_not_empty()  # The scripted Commands were logged.
		assert_array(worked["hashes"]).override_failure_message(str(size)).is_equal(plain["hashes"])
		assert_int(worked["final"]).override_failure_message(str(size)).is_equal(plain["final"])
		assert_array(worked["log"]).override_failure_message(str(size)).is_equal(plain["log"])
		assert_int(worked["sunk"]).override_failure_message("Commands from the HUD").is_equal(0)
		assert_int(plain["tick"]).is_equal(CHUNKS * PERIOD)
		assert_int(worked["tick"]).is_equal(CHUNKS * PERIOD)
		# The hashes move: the run is a real match, not a frozen one.
		assert_bool(plain["hashes"][0] != plain["hashes"][CHUNKS - 1]).is_true()


## The control: the run is not blind to a Command. One more Command that the HUD would not send
## changes the hash, so that equal hashes above mean something.
func test_a_run_with_one_more_command_ends_in_another_hash() -> void:
	var plain: Dictionary = await _play(ScreenSizes.LANDSCAPE[0], false)
	var extra: Dictionary = await _play(ScreenSizes.LANDSCAPE[0], false, true)
	assert_bool(extra["final"] != plain["final"]).is_true()
	assert_bool(extra["log"] != plain["log"]).is_true()


## One run: `CHUNKS` times `PERIOD` ticks. Between the chunks the scripted Commands go in and, when
## `hud`, an action of the HUD runs. Returns the hash after each chunk, the final hash, the command
## log, the tick, and how many Commands the controller's sink saw (none may come from the HUD).
func _play(size: Vector2i, hud: bool, extra: bool = false) -> Dictionary:
	UiScale.clear_override()
	get_window().size = size
	await await_idle_frame()
	_main = auto_free(await MatchRig.open(self))
	var runner: MatchRunner = _main.get_node("MatchRunner")
	runner.paused = true
	runner.start()  # The same seed and the same first tick, whatever the frames above played.
	await await_idle_frame()
	var sunk: Array[int] = [0]
	var controller: PlayerController = _main.get_node("PlayerController")
	controller.command_sink = func(_command: Command) -> void: sunk[0] += 1
	var units: PackedInt32Array = MatchRig.units_of(_main, 1)
	var hashes: Array[int] = []
	for chunk: int in CHUNKS:
		if chunk == 1:
			CommandQueue.submit(Command.move(1, units, TARGET.x, TARGET.y))
		elif chunk == 5:
			CommandQueue.submit(Command.stop(1, units))
		elif chunk == 8 and extra:
			CommandQueue.submit(Command.move(1, units, 5000, 20000))
		runner.run_ticks(PERIOD)
		hashes.append(runner.world.state_hash())
		if hud:
			await _act(chunk, units)
			(
				assert_int(CommandQueue.pending())
				. override_failure_message("chunk %d" % chunk)
				. is_zero()
			)
	var out: Dictionary = {
		"hashes": hashes,
		"final": runner.world.state_hash(),
		"log": Array(runner.replay.commands),
		"tick": runner.snapshot.tick,
		"sunk": sunk[0],
	}
	_main.free()
	await await_idle_frame()
	return out


## The HUD action after chunk `chunk`; the match is paused in every frame it waits.
func _act(chunk: int, units: PackedInt32Array) -> void:
	var controller: PlayerController = _main.get_node("PlayerController")
	var runner: MatchRunner = _main.get_node("MatchRunner")
	var state: HudState = HudWalk.state(_main)
	match chunk:
		0:
			await HudWalk.tap(self, HudWalk.hud(_main, "BuildButton"))  # Opens the drawer.
			assert_bool(state.is_open(HudState.Unfold.DRAWER)).is_true()
		1:
			controller.selection.set_ids(units)
			await HudWalk.frames(self)
		2:
			await HudWalk.tap(
				self, HudWalk.hud(_main, "BuildSidebar").find_child("Close", true, false) as Control
			)  # Closes the drawer.
			assert_bool(state.is_open(HudState.Unfold.NONE)).is_true()
		3:
			await HudWalk.tap(self, HudWalk.hud(_main, "Deselect"))
			assert_array(controller.selection.selected).is_empty()
		4:
			runner.paused = false  # With no frame between, so that the menu's pause can be seen.
			HudWalk.tap_now(self, HudWalk.hud(_main, "Menu"))  # The pause menu opens.
			assert_bool(runner.paused).is_true()
			assert_bool(state.is_open(HudState.Unfold.PAUSE)).is_true()
			(HudWalk.hud(_main, "ResumeButton") as Button).pressed.emit()
			assert_bool(runner.paused).is_false()
			runner.paused = true  # Before any frame plays a tick.
			await HudWalk.frames(self)
			assert_bool(state.is_open(HudState.Unfold.PAUSE)).is_false()
		5:
			await HudWalk.tap(self, HudWalk.hud(_main, "RadarScope"))  # The full map.
			await HudWalk.tap(self, HudWalk.hud(_main, "MapPin"))
			assert_bool(state.pinned).is_true()
		6:
			controller.select_all_army()
			await HudWalk.frames(self)
		7:
			await HudWalk.tap(self, HudWalk.hud(_main, "MapCollapse"))
			assert_bool(state.is_open(HudState.Unfold.RADAR)).is_false()
		8:
			controller.assign_group(1)
			controller.deselect()
			controller.tap_group(1)
			await HudWalk.frames(self)
		9:
			await HudWalk.tap(self, HudWalk.hud(_main, "BuildButton"))  # The drawer is open ...
			assert_bool(state.is_open(HudState.Unfold.DRAWER)).is_true()
		10:
			await HudWalk.tap(self, HudWalk.hud(_main, "CreditsTap"))  # ... and the pill opens the card.
			assert_bool(state.is_open(HudState.Unfold.ECONOMY)).is_true()
		11:
			await HudWalk.tap(self, HudWalk.hud(_main, "CreditsTap"))  # The next touch closes it.
			assert_bool(state.is_open(HudState.Unfold.ECONOMY)).is_false()
		_:
			await HudWalk.frames(self)
