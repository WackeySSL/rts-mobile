class_name ConsentFlow
extends RefCounted
## AdService's consent side (ADR 0039 section 3): the backend, the one busy flag, the debug
## geography decision and the gate runs. The consent flow and the privacy options flow exclude each
## other: a call made while one runs awaits it and starts nothing. `settled` fires once per
## finished flow, before any waiter resumes (AdService connects first and owns the gate).

## A flow finished, with whether ads may be requested.
signal settled(can_request_ads: bool)
## A flow ended, finished or cut; waiters resume on this, after `settled`.
signal ended

## A privacy options run was cut at its deadline: consent is unknown (a choice in the abandoned form
## may have changed it). Nothing was announced; the next consent run, which starts with a fresh
## info update, clears it, and AdService starts one on the next resume.
var needs_recheck: bool = false

var backend: ConsentBackend
var _is_debug_build: Callable
var _busy: bool = false
var _last_allowed: bool = false


func _init(consent_backend: ConsentBackend, is_debug_build: Callable) -> void:
	backend = consent_backend
	_is_debug_build = is_debug_build


## Awaitable; always finishes. `debug_eea` is honoured only in a debug build.
func run_consent(now_ms: Callable, timeout_ms: int, debug_eea: bool) -> bool:
	var waited: bool = false
	while _busy:
		waited = true
		await ended
	if waited and not needs_recheck:
		return _last_allowed
	needs_recheck = false
	_busy = true
	var gate: ConsentGate = ConsentGate.new(
		backend, now_ms, timeout_ms, debug_eea and bool(_is_debug_build.call())
	)
	var allowed: bool = await gate.execute()
	return _finish(allowed)


## Awaitable until the privacy options form closes; nothing when none is required. Gives up at
## `timeout_ms` if the form has not shown (the flow is then free again); once shown it waits for
## the close with no timeout.
func run_privacy_options(now_ms: Callable, timeout_ms: int) -> void:
	if _busy:
		while _busy:
			await ended
		return
	if not backend.is_privacy_options_required():
		return
	_busy = true
	if await ConsentGate.new(backend, now_ms, timeout_ms, false).run_privacy_options():
		_finish(backend.can_request_ads())
		return
	# Cut: fail closed. No `settled`, so the cached answer neither rises nor falls.
	needs_recheck = true
	_busy = false
	ended.emit()


## Fake backend wiring: the placeholder follows `fake_auto_close` and draws on `host`.
func configure_fake(auto_close: bool, host: Node) -> void:
	if backend is FakeUmp:
		var ump: FakeUmp = backend as FakeUmp
		ump.auto_close = auto_close
		ump.draw_placeholders = not auto_close
		ump.host = host


func _finish(allowed: bool) -> bool:
	_busy = false
	_last_allowed = allowed
	settled.emit(allowed)
	ended.emit()
	return allowed
