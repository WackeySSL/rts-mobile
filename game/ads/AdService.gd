extends Node
## The one facade for ads, consent and the Remove ads purchase (ADR 0039 section 1).
## Phase 5 calls only what is declared here; the signals, methods and their types are the
## agreed contract (docs/plans/2026-11-15-phase-6.md, "Interfaces with Phase 5", item 1).
##
## P403 fills in the ads behind these signatures: the caps (AdCaps), the counters (AdLedger, in
## memory until P407 saves it), the timeouts from data, the banner and the rewarded ad, all through
## an AdBackend. The backend is always the FakeAdBackend for now: the real one is P405, so builds
## with the `play` feature tag keep the fake until it lands. Consent (P404) and purchases (P406)
## are still stubs: `_can_request_ads` is false and Remove ads is the ledger's flag, so no
## interstitial or banner shows until they set them. No plugin code and no ad IDs live here.
## Never touched by game/sim. No class_name: this is an autoload (tests/project/test_autoloads.gd).

## Fires when consent is settled, with whether ads may be requested. `ensure_consent` emits it
## (with false in the stub) before it returns.
signal consent_finished(can_request_ads: bool)
## Fires when the Remove ads entitlement changes, with the new state.
signal entitlement_changed(has_remove_ads: bool)
## Fires when the banner's height changes, with the new height in dp (0 = none).
signal banner_changed(height_dp: int)
## Fires when a full-screen ad opens, with its placement.
signal ad_opened(placement: StringName)
## Fires when a full-screen ad closes, with its placement.
signal ad_closed(placement: StringName)

## True: fake full-screen ads and fake flows close at once (gdUnit4, headless). False: the fake
## placeholders wait for their Close button and the fake flows for their buttons (P403 on).
## Tests may set it.
var fake_auto_close: bool = _default_auto_close(DisplayServer.get_name())

## Consent's answer (P404 sets it): whether ads may be requested at all.
var _can_request_ads: bool = false
var _settings: AdsSettingsDef = AdsSettingsDef.load_default()
var _ledger: AdLedger = AdLedger.new()
var _backend: AdBackend = _make_backend()
## Milliseconds clock for the pre-show timeouts; tests replace it with a fake one.
var _now_ms: Callable = Time.get_ticks_msec
var _busy: bool = false
var _banner_wanted: bool = false
var _banner_height: int = 0


## Fake everywhere until P405 adds the AdMob backend (ADR 0039 section 2).
static func _make_backend() -> AdBackend:
	return FakeAdBackend.new()


func _ready() -> void:
	if _backend is FakeAdBackend:
		(_backend as FakeAdBackend).host = self


static func _default_auto_close(display_name: String) -> bool:
	return display_name == "headless"


## Awaitable; always finishes. True means ads may be requested. The stub emits
## `consent_finished(false)` and returns false: no ad is ever requested in fake mode.
func ensure_consent() -> bool:
	# A real coroutine that returns in the same frame, so callers must `await` from day one.
	@warning_ignore("redundant_await")
	await null
	consent_finished.emit(false)
	return false


## Synchronous.
func is_privacy_options_required() -> bool:
	return false


## Awaitable until UMP's privacy options form closes. The stub has no form.
func show_privacy_options() -> void:
	@warning_ignore("redundant_await")
	await null


## Synchronous.
func has_remove_ads() -> bool:
	return false


## Awaitable. True once the entitlement is granted. The stub cannot purchase.
func purchase_remove_ads() -> bool:
	@warning_ignore("redundant_await")
	await null
	return false


## Awaitable. True when a purchase was restored. The stub has none.
func restore_purchases() -> bool:
	@warning_ignore("redundant_await")
	await null
	return false


## Synchronous. The banner's height while one may show (consent, no Remove ads, a band asked for
## it through `show_banner`), else 0.
func banner_height_dp() -> int:
	return _banner_height


## Awaitable. True means one interstitial showed and closed. Returns false at once when the caps
## say no, and when the ad has not opened within `fullscreen_timeout_ms`; once it opened the call
## waits for the close.
func maybe_show_interstitial(placement: StringName) -> bool:
	if _busy:
		return false
	if not AdCaps.may_show_interstitial(_settings, _ledger, placement, _can_request_ads):
		return false
	var shown: bool = await _run_fullscreen(AdBackend.KIND_INTERSTITIAL, placement, Callable())
	return shown


## Called once per finished match (win, loss, surrender) with its play time in whole seconds.
func note_match_completed(play_seconds: int) -> void:
	_ledger.note_match_completed(play_seconds)


## Synchronous. The pending start-credits bonus once, then 0.
func take_start_credits_bonus() -> int:
	return _ledger.take_start_credits_bonus(_settings.start_credits_bonus_max)


## Internal (Phase 6 widgets). True when a rewarded ad is loaded and may be requested; an offer
## shows only then, never a spinner. Asks the backend to preload one the first time.
func rewarded_ready(_placement: StringName) -> bool:
	if not _can_request_ads:
		return false
	var state: AdBackend.LoadState = _backend.load_state(AdBackend.KIND_REWARDED)
	if state == AdBackend.LoadState.IDLE:
		_backend.request_load(AdBackend.KIND_REWARDED)
		state = _backend.load_state(AdBackend.KIND_REWARDED)
	return state == AdBackend.LoadState.READY


## Internal. Awaitable. True only when the SDK's reward callback fired before the close. False at
## once when no ad is ready, and when it has not opened within `fullscreen_timeout_ms`; once it
## opened the call waits for the close. `on_reward` runs inside the callback, before `ad_closed`,
## so a grant can be saved before the close is handled (ADR 0039 section 7).
func show_rewarded(placement: StringName, on_reward: Callable = Callable()) -> bool:
	if _busy or not rewarded_ready(placement):
		return false
	var rewarded: bool = await _run_fullscreen(AdBackend.KIND_REWARDED, placement, on_reward)
	if _can_request_ads:
		_backend.request_load(AdBackend.KIND_REWARDED)
	return rewarded


## Internal, called by the banner band on `enter_tree`.
func show_banner() -> void:
	_banner_wanted = true
	_refresh_banner()


## Internal, called by the banner band on `exit_tree`.
func hide_banner() -> void:
	_banner_wanted = false
	_refresh_banner()


## Shows or hides the backend's banner for the current consent, entitlement and request, and
## emits `banner_changed` when the height changed. Consent and billing call it when theirs change.
func _refresh_banner() -> void:
	var may_show: bool = _banner_wanted and _can_request_ads and not _ledger.remove_ads
	var height: int = 0
	if may_show:
		_backend.show_banner(not fake_auto_close)
		height = _backend.banner_height_dp()
	else:
		_backend.hide_banner()
	if height != _banner_height:
		_banner_height = height
		banner_changed.emit(height)


## One full-screen ad: loads if needed, shows, waits for it to open (timeout) and then for the
## close (no timeout). `ad_opened` and `ad_closed` come from the backend's signals, so they pair.
func _run_fullscreen(kind: StringName, placement: StringName, on_reward: Callable) -> bool:
	_busy = true
	var run: _FullscreenRun = _FullscreenRun.new(self, kind, placement, on_reward)
	var result: bool = await run.execute()
	_busy = false
	return result


func _wait_frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


## Tracks one full-screen show; connects to the backend's signals for its duration.
class _FullscreenRun:
	extends RefCounted

	var _service: Node
	var _backend: AdBackend
	var _kind: StringName
	var _placement: StringName
	var _on_reward: Callable
	var _active: bool = false
	var _opened: bool = false
	var _closed: bool = false
	var _rewarded: bool = false

	func _init(service: Node, kind: StringName, placement: StringName, on_reward: Callable) -> void:
		_service = service
		_backend = service._backend
		_kind = kind
		_placement = placement
		_on_reward = on_reward

	func execute() -> bool:
		var deadline: int = _service._now_ms.call() + _service._settings.fullscreen_timeout_ms
		if not await _await_loaded(deadline):
			return false
		_connect()
		_backend.show_ad(_kind, _service.fake_auto_close)
		while not _opened:
			if _service._now_ms.call() >= deadline:
				_backend.cancel_show(_kind)
				_disconnect()
				return false
			await _service._wait_frame()
		while not _closed:
			await _service._wait_frame()
		_disconnect()
		return _rewarded if _kind == AdBackend.KIND_REWARDED else true

	func _await_loaded(deadline: int) -> bool:
		var state: AdBackend.LoadState = _backend.load_state(_kind)
		if state != AdBackend.LoadState.READY and state != AdBackend.LoadState.LOADING:
			_backend.request_load(_kind)
		while _backend.load_state(_kind) == AdBackend.LoadState.LOADING:
			if _service._now_ms.call() >= deadline:
				return false
			await _service._wait_frame()
		return _backend.load_state(_kind) == AdBackend.LoadState.READY

	func _connect() -> void:
		_active = true
		_backend.opened.connect(_on_opened)
		_backend.reward_earned.connect(_on_reward_earned)
		_backend.closed.connect(_on_closed)

	func _disconnect() -> void:
		_active = false
		_backend.opened.disconnect(_on_opened)
		_backend.reward_earned.disconnect(_on_reward_earned)
		_backend.closed.disconnect(_on_closed)

	func _on_opened(kind: StringName) -> void:
		if not _active or kind != _kind or _opened:
			return
		_opened = true
		if kind == AdBackend.KIND_INTERSTITIAL:
			_service._ledger.note_interstitial_shown()
		_service.ad_opened.emit(_placement)

	func _on_reward_earned(kind: StringName) -> void:
		if not _active or kind != _kind or not _opened or _closed:
			return
		_rewarded = true
		if _on_reward.is_valid():
			_on_reward.call()

	func _on_closed(kind: StringName) -> void:
		if not _active or kind != _kind or not _opened or _closed:
			return
		_closed = true
		_service.ad_closed.emit(_placement)
