class_name FullscreenRun
extends RefCounted
## One full-screen ad, load to close (ADR 0039 section 2). One deadline covers the load wait and
## the wait for the ad to open, and nothing after: once it opened the run waits for the close with
## no timeout. It relays the backend's signals as its own `opened` and `closed`, so they pair.
## A show that fails before it opens ends the run with false at once. After a timeout the run
## stays connected as a late listener: if the backend opens the ad anyway (AdMob cannot recall
## a show), the pair is still emitted, an interstitial is still noted in the ledger and a reward
## is granted only if it comes before the close. `abandon` ends that listening.

signal opened(placement: StringName)
signal closed(placement: StringName)

var placement: StringName
var _backend: AdBackend
var _now_ms: Callable
var _timeout_ms: int
var _ledger: AdLedger
var _kind: StringName
var _on_reward: Callable
var _connected: bool = false
var _timed_out: bool = false
var _is_opened: bool = false
var _is_closed: bool = false
var _failed: bool = false
var _rewarded: bool = false


func _init(
	backend: AdBackend,
	now_ms: Callable,
	timeout_ms: int,
	ledger: AdLedger,
	kind: StringName,
	for_placement: StringName,
	on_reward: Callable
) -> void:
	_backend = backend
	_now_ms = now_ms
	_timeout_ms = timeout_ms
	_ledger = ledger
	_kind = kind
	placement = for_placement
	_on_reward = on_reward


## True: an interstitial showed and closed, or a rewarded ad's reward came before its close.
func execute() -> bool:
	var deadline: int = int(_now_ms.call()) + _timeout_ms
	if not await _await_loaded(deadline):
		return false
	_connect()
	_backend.show_ad(_kind)
	while not _is_opened and not _failed:
		if int(_now_ms.call()) >= deadline:
			_timed_out = true
			_backend.cancel_show(_kind)
			return false
		await _next_frame()
	if _failed:
		_disconnect()
		return false
	while not _is_closed:
		await _next_frame()
	_disconnect()
	return _rewarded if _kind == AdBackend.KIND_REWARDED else true


## True while the run timed out and its ad may still open or is open and not yet closed.
func is_late_pending() -> bool:
	return _timed_out and _connected and not _is_closed


## Stops listening; used when a new call replaces a late listener.
func abandon() -> void:
	_disconnect()


func _await_loaded(deadline: int) -> bool:
	var state: AdBackend.LoadState = _backend.load_state(_kind)
	if state != AdBackend.LoadState.READY and state != AdBackend.LoadState.LOADING:
		_backend.request_load(_kind)
	while _backend.load_state(_kind) == AdBackend.LoadState.LOADING:
		if int(_now_ms.call()) >= deadline:
			return false
		await _next_frame()
	return _backend.load_state(_kind) == AdBackend.LoadState.READY


func _next_frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _connect() -> void:
	_connected = true
	_backend.opened.connect(_on_opened)
	_backend.reward_earned.connect(_on_reward_earned)
	_backend.closed.connect(_on_closed)
	_backend.show_failed.connect(_on_show_failed)


func _disconnect() -> void:
	if not _connected:
		return
	_connected = false
	_backend.opened.disconnect(_on_opened)
	_backend.reward_earned.disconnect(_on_reward_earned)
	_backend.closed.disconnect(_on_closed)
	_backend.show_failed.disconnect(_on_show_failed)


func _on_opened(kind: StringName) -> void:
	if kind != _kind or _is_opened or _failed:
		return
	_is_opened = true
	if kind == AdBackend.KIND_INTERSTITIAL:
		_ledger.note_interstitial_shown()
	opened.emit(placement)


func _on_reward_earned(kind: StringName) -> void:
	if kind != _kind or not _is_opened or _is_closed or _rewarded:
		return
	_rewarded = true
	if _on_reward.is_valid():
		_on_reward.call()


func _on_closed(kind: StringName) -> void:
	if kind != _kind or not _is_opened or _is_closed:
		return
	_is_closed = true
	closed.emit(placement)
	if _timed_out:
		_disconnect()


func _on_show_failed(kind: StringName) -> void:
	if kind == _kind and not _is_opened:
		_failed = true
