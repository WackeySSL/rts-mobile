class_name ConsentGate
extends RefCounted
## One consent run (ADR 0039 sections 3 and 11). One deadline covers the info update and the form
## load, and nothing after: once the form shows the run waits for its dismissal with no timeout,
## so nothing proceeds under it. Offline, an error or the timeout end with false and ads stay
## unrequested; the run never hangs boot. When nothing is pending it finishes in the same frame.

var _backend: ConsentBackend
var _now_ms: Callable
var _timeout_ms: int
var _debug_eea: bool
var _dismissed: bool = false


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


## Awaitable until the privacy options form closes; no timeout.
func run_privacy_options() -> void:
	await _show(_backend.show_privacy_options)


func _show(show: Callable) -> void:
	_backend.form_dismissed.connect(_on_dismissed, CONNECT_ONE_SHOT)
	show.call()
	while not _dismissed:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _on_dismissed() -> void:
	_dismissed = true


## True once `state` is DONE; false on FAILED or when the deadline passes first.
func _until_done(deadline: int, state: Callable) -> bool:
	while state.call() == ConsentBackend.Step.PENDING:
		if int(_now_ms.call()) >= deadline:
			return false
		await (Engine.get_main_loop() as SceneTree).process_frame
	return state.call() == ConsentBackend.Step.DONE
