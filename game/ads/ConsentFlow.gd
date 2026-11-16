class_name ConsentFlow
extends RefCounted
## AdService's consent side (ADR 0039 section 3): the backend, the one busy flag, the debug
## geography decision and the gate runs. The consent flow and the privacy options flow exclude each
## other: a call made while one runs awaits it and starts nothing. `settled` fires once per
## finished flow, before any waiter resumes (AdService connects first and owns the gate).

## A flow finished, with whether ads may be requested.
signal settled(can_request_ads: bool)

var backend: ConsentBackend
var _is_debug_build: Callable
var _busy: bool = false


func _init(consent_backend: ConsentBackend, is_debug_build: Callable) -> void:
	backend = consent_backend
	_is_debug_build = is_debug_build


## Awaitable; always finishes. `debug_eea` is honoured only in a debug build.
func run_consent(now_ms: Callable, timeout_ms: int, debug_eea: bool) -> bool:
	if _busy:
		return await settled
	_busy = true
	var gate: ConsentGate = ConsentGate.new(
		backend, now_ms, timeout_ms, debug_eea and bool(_is_debug_build.call())
	)
	var allowed: bool = await gate.execute()
	return _finish(allowed)


## Awaitable until the privacy options form closes; nothing when none is required.
func run_privacy_options(now_ms: Callable, timeout_ms: int) -> void:
	if _busy:
		await settled
		return
	if not backend.is_privacy_options_required():
		return
	_busy = true
	await ConsentGate.new(backend, now_ms, timeout_ms, false).run_privacy_options()
	_finish(backend.can_request_ads())


## Fake backend wiring: the placeholder follows `fake_auto_close` and draws on `host`.
func configure_fake(auto_close: bool, host: Node) -> void:
	if backend is FakeUmp:
		var ump: FakeUmp = backend as FakeUmp
		ump.auto_close = auto_close
		ump.draw_placeholders = not auto_close
		ump.host = host


func _finish(allowed: bool) -> bool:
	_busy = false
	settled.emit(allowed)
	return allowed
