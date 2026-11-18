class_name Restorer
extends Node
## Plays a saved match again off the tree (ADR 0042 section 6, plan P515). `begin(data, main)` gives
## the runner of the main scene `main` the setup, sets `restored`, starts it and holds the mute
## reason `restoring` (and `ResumeWatcher.restoring`, so a pause never writes a half-played match
## over the file). Each frame `_process` replays ticks until `restore_slice_ms` is spent (at least
## one): the local player's logged Commands of tick t go in through `CommandQueue.submit_logged`
## (no `submitted`, so no order chirp), then `run_ticks(1)`. The AI is not fed from the log; it
## thinks on the same views and makes its own Commands again. At every checkpoint tick the runner's
## hash must equal the log's and the World's hash at the stored tick the file's end hash (the
## checkpoints stop up to 14 ticks short of it); a mismatch, a stall or another `defs_hash` ends the
## restore with an error. At the stored tick `finished(OK)` comes and the runner is paused: the
## caller puts `main` in the tree and calls `hand_over(main)`, which drops the mute reason when it
## has entered the tree, then the Restorer frees itself. The watcher flag ends with the finish. A
## caller that does not use the match calls `abandon()`.
## Integers only; time is read here (game/core), never in `game/sim`.

## Ticks played so far of `total`, after each frame's slice.
signal progressed(done: int, total: int)
## Once: OK at the stored tick, ERR_SKIP after `cancel()`, else why it failed.
signal finished(result: Error)

const SETTINGS: RestoreSettings = preload("res://data/restore_settings.tres")
const USEC_PER_MSEC: int = 1000

## What a frame's time is read from, in microseconds; tests replace it with a counted clock.
var clock: Callable = Time.get_ticks_usec
## The frame's budget in microseconds (restore_slice_ms of the data).
var slice_usec: int = SETTINGS.restore_slice_ms * USEC_PER_MSEC
## The mute target; null means the AudioService autoload.
var audio: Node = null
## Set by `begin`: the runner and the setup the match is played with.
var runner: MatchRunner = null
var setup: MatchSetup = null
## The ticks the last frame played (tests count these instead of timing).
var last_frame_ticks: int = 0

var _data: ResumeData = null
var _local: Array[Command] = []  ## The local player's logged Commands, in log order.
var _at: int = 0
var _checkpoint: int = 0
var _active: bool = false
var _held: bool = false  ## The mute reason and the watcher flag are on.


## Starts the restore of `data` in `scene`, a main scene not in the tree. OK means it runs and
## `finished` comes from a later frame; an error means nothing runs and nothing is held.
func begin(data: ResumeData, scene: Node) -> Error:
	runner = scene.get_node_or_null("MatchRunner") as MatchRunner if scene != null else null
	if data == null or runner == null or data.setup == null or data.replay == null:
		return ERR_UNCONFIGURED
	setup = data.setup
	var applied: Error = setup.apply(runner)
	if applied != OK:
		return applied
	_data = data
	if not _decode_local():
		return ERR_INVALID_DATA
	_hold()
	runner.restored = true
	runner.start()
	if runner.world == null or runner.world.defs_hash() != data.defs_hash:
		_release()
		return ERR_FILE_CORRUPT  # Another build's data: the log would not play the same.
	_active = true
	return OK


func _process(_delta: float) -> void:
	if not _active:
		return
	var started: int = int(clock.call())
	last_frame_ticks = 0
	while _active:
		_play_tick()
		last_frame_ticks += 1
		if int(clock.call()) - started >= slice_usec:
			break
	if _active:
		progressed.emit(_done(), _data.tick)


## The player's Cancel: the restore stops and the file stays. `finished(ERR_SKIP)`.
func cancel() -> void:
	if _active:
		_finish(ERR_SKIP)


## The restored match goes to the player: the runner stays paused (the caller opens the pause menu)
## and the mute reason ends when `scene` has entered the tree.
func hand_over(scene: Node) -> void:
	if scene.is_inside_tree():
		_release()
	else:
		scene.tree_entered.connect(_release, CONNECT_ONE_SHOT)


## Gives the restore up (a failed switch): the caller frees the scene; the holds end.
func abandon() -> void:
	_active = false
	_release()
	if is_inside_tree():
		queue_free()


func _exit_tree() -> void:
	_active = false
	_release()


func _decode_local() -> bool:
	_local.clear()
	var data: PackedInt32Array = _data.replay.commands
	# The scenario's own orders are recorded first in their tick and the runner's loop gives them
	# again, so the first of that tick's local records are not the player's.
	var scenario_orders: Dictionary[int, int] = {}
	for order: OrderDef in setup.scenario().orders:
		if order != null and order.player == _data.local_player:
			scenario_orders[order.tick] = scenario_orders.get(order.tick, 0) + 1
	var at: int = 0
	while at < data.size():
		var command: Command = Command.new()
		var end: int = Command.decode(data, at, command)
		if end < 0:
			return false
		at = end
		if command.tick >= _data.tick or command.player_id != _data.local_player:
			continue
		if scenario_orders.get(command.tick, 0) > 0:
			scenario_orders[command.tick] -= 1
			continue
		_local.append(command)
	return true


func _play_tick() -> void:
	var tick: int = runner.snapshot.tick
	while _at < _local.size() and _local[_at].tick <= tick:
		CommandQueue.submit_logged(_local[_at])
		_at += 1
	runner.run_ticks(1)
	var now: int = runner.snapshot.tick
	if now != tick + 1:
		_finish(ERR_BUG)  # The match ended or the runner did not move: it cannot reach the tick.
	elif not _check(now):
		_finish(ERR_FILE_CORRUPT)
	elif now >= _data.tick:
		# The checkpoints stop up to 14 ticks short of the stored tick: the end hash closes the gap.
		var same: bool = runner.wait_idle() and runner.world.state_hash() == _data.end_hash
		_finish(OK if same else ERR_FILE_CORRUPT)


## Compares the checkpoints up to `tick` with the runner's hash; false on the first difference.
func _check(tick: int) -> bool:
	var replay: Replay = _data.replay
	while (
		_checkpoint < replay.checkpoint_ticks.size()
		and replay.checkpoint_ticks[_checkpoint] <= tick
	):
		var same: bool = (
			replay.checkpoint_ticks[_checkpoint] == tick
			and runner.last_hash == replay.checkpoint_hashes[_checkpoint]
		)
		if not same:
			return false
		_checkpoint += 1
	return true


func _done() -> int:
	return runner.snapshot.tick if runner != null and runner.snapshot != null else 0


func _finish(result: Error) -> void:
	_active = false
	CommandQueue.clear()  # A cancelled or failed restore leaves no order in the shared queue.
	if result == OK:
		runner.paused = true
		ResumeWatcher.restoring = false  # Only the mute waits for the scene to enter the tree.
	else:
		_release()
	progressed.emit(_done(), _data.tick)
	finished.emit(result)


func _hold() -> void:
	_held = true
	ResumeWatcher.restoring = true
	_audio().add_mute_reason(AudioService.REASON_RESTORING)


func _release() -> void:
	if not _held:
		return
	_held = false
	ResumeWatcher.restoring = false
	_audio().clear_mute_reason(AudioService.REASON_RESTORING)
	if is_inside_tree():
		queue_free()


func _audio() -> Node:
	return audio if audio != null else AudioService
