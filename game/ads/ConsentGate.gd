class_name ConsentGate
extends RefCounted
## One consent run (ADR 0039 sections 3 and 11). One deadline covers the info update and the form
## load (for the privacy options form: the show), and nothing after: once the form shows the run
## waits for its dismissal with no timeout, so nothing proceeds under it.
## Offline, an error or the timeout end with false and ads stay unrequested; the run never
## hangs boot.
## When nothing is pending it finishes in the same frame.
## Single use: make a new gate per run.

var _backend: ConsentBackend
var _now_ms: Callable
var _timeout_ms: int
var _debug_eea: bool
var _dismissed: bool = false
var _shown: bool = false


func _init(backend: ConsentBackend, now_ms: Callable, timeout_ms: int, debug_eea: bool) -> void:
	_backend = backend
	_now_ms = now_ms
	_timeout_ms = timeout_ms
	_debug_eea = debug_eea


## True: ads may be requested.
func execute() -> bool:
	var deadline: int = int(_now_ms.call()) + _timeout_ms
	_backend.update_info(_debug_eea)
	if not await _until_done(deadline, _backend.info_state):
		return false
	if _backend.is_form_required():
		_backend.load_form()
		if not await _until_done(deadline, _backend.form_state):
			return false
		await _show(_backend.show_form)
	return _backend.can_request_ads()


## Awaitable. Like `execute`: one deadline before the form shows (`form_shown`, or a dismissal
## without one), then the wait for the close has no timeout. On the deadline the run returns and
## lets go of the backend; a late show or close then reaches nobody.
func run_privacy_options() -> void:
	var deadline: int = int(_now_ms.call()) + _timeout_ms
	_dismissed = false
	_backend.form_shown.connect(_on_shown, CONNECT_ONE_SHOT)
	_backend.form_dismissed.connect(_on_dismissed, CONNECT_ONE_SHOT)
	_backend.show_privacy_options()
	if not await _until_done(deadline, _shown_state):
		_release(_backend.form_shown, _on_shown)
		_release(_backend.form_dismissed, _on_dismissed)
		return
	if not _dismissed:
		await _backend.form_dismissed


## Waits for `form_dismissed`, which the backend fires on every outcome (ConsentBackend).
func _show(show: Callable) -> void:
	_dismissed = false
	_backend.form_dismissed.connect(_on_dismissed, CONNECT_ONE_SHOT)
	show.call()
	if not _dismissed:
		await _backend.form_dismissed


func _on_dismissed() -> void:
	_dismissed = true


func _on_shown() -> void:
	_shown = true


func _shown_state() -> ConsentBackend.Step:
	if _shown or _dismissed:
		return ConsentBackend.Step.DONE
	return ConsentBackend.Step.PENDING


func _release(form_signal: Signal, handler: Callable) -> void:
	if form_signal.is_connected(handler):
		form_signal.disconnect(handler)


## True once `state` is DONE; false on FAILED or when the deadline passes first. Frame polling
## lives only here, because a pending answer has no signal.
func _until_done(deadline: int, state: Callable) -> bool:
	while state.call() == ConsentBackend.Step.PENDING:
		if int(_now_ms.call()) >= deadline:
			return false
		await (Engine.get_main_loop() as SceneTree).process_frame
	return state.call() == ConsentBackend.Step.DONE
