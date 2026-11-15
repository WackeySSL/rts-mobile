class_name FullscreenRun
extends RefCounted
## One full-screen ad, load to close (ADR 0039 section 2). One deadline covers the load wait and
## the wait for the ad to open, and nothing after: once it opened the run waits for the close with
## no timeout. It relays the backend's signals as its own `opened` and `closed`, so they pair.
## A show that fails before it opens ends the run with false at once. After a timeout (or a
## `cancel`) the run stays connected as a late listener: if the backend opens the ad anyway (AdMob
## cannot recall a show), the pair is still emitted, an interstitial is still noted in the ledger
## (the caps describe what the player saw) and a reward is granted only if it comes before the
## close. `abandon` ends that listening for good; it is used only by the run that `replaces` it,
## once that run listens itself, so one open is never announced twice and never missed.
## The signals carry the run, never a bound Callable: a bound run would be a reference cycle.

signal opened(placement: StringName, run: FullscreenRun)
signal closed(placement: StringName, run: FullscreenRun)
## A late run's show failed after its timeout: it stopped listening and can be forgotten.
signal gave_up(run: FullscreenRun)
## This run listens now and ended the unopened late run it replaces.
signal took_over(old: FullscreenRun)

## An unopened late run of the same kind that this run takes over at connect, if it connects.
var replaces: FullscreenRun = null
var placement: StringName
var _backend: AdBackend
var _now_ms: Callable
var _timeout_ms: int
var _ledger: AdLedger
var _kind: StringName
var _on_reward: Callable
var _connected: bool = false
var _shown: bool = false
var _cancelled: bool = false
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
	_shown = true
	_backend.show_ad(_kind)
	while not _is_opened and not _failed:
		if _cancelled or int(_now_ms.call()) >= deadline:
			_timed_out = true
			if not _cancelled:
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


## The run's ad kind.
func ad_kind() -> StringName:
	return _kind


## True once the ad opened (it may still be open).
func is_opened() -> bool:
	return _is_opened


## Withdraws a show that has not opened (consent withdrawn, Remove ads bought). The backend may
## not be able to recall it; the run keeps listening then and pairs a late open. A run that
## already timed out was withdrawn then.
func cancel() -> void:
	if _is_opened or _cancelled or _timed_out:
		return
	_cancelled = true
	if _shown:
		_backend.cancel_show(_kind)


## Stops listening; used by the run that replaces this late one, once that one listens.
func abandon() -> void:
	_disconnect()


func _await_loaded(deadline: int) -> bool:
	var state: AdBackend.LoadState = _backend.load_state(_kind)
	if state != AdBackend.LoadState.READY and state != AdBackend.LoadState.LOADING:
		_backend.request_load(_kind)
	while _backend.load_state(_kind) == AdBackend.LoadState.LOADING:
		if _cancelled or int(_now_ms.call()) >= deadline:
			return false
		await _next_frame()
	return not _cancelled and _backend.load_state(_kind) == AdBackend.LoadState.READY


func _next_frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _connect() -> void:
	# Hand over from the late run before this one's show, and only if that one is still unopened.
	if replaces != null and not replaces.is_opened():
		replaces.abandon()
		took_over.emit(replaces)
	replaces = null
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
	opened.emit(placement, self)


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
	closed.emit(placement, self)
	if _timed_out:
		_disconnect()


func _on_show_failed(kind: StringName) -> void:
	if kind != _kind or _is_opened:
		return
	_failed = true
	if _timed_out:
		_disconnect()
		gave_up.emit(self)
