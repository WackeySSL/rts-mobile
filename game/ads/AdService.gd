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
## Tests may set it; the fake backend follows at the next call.
var fake_auto_close: bool = _default_auto_close(DisplayServer.get_name())

## Consent's answer (P404 sets it): whether ads may be requested at all.
var _can_request_ads: bool = false
var _settings: AdsSettingsDef = AdsSettingsDef.load_default()
var _ledger: AdLedger = AdLedger.new()
var _backend: AdBackend = _make_backend()
## Milliseconds clock for the timeouts and retries; tests replace it with a fake one.
var _now_ms: Callable = Time.get_ticks_msec
var _busy: bool = false
## A run that timed out but whose ad may still open; see FullscreenRun.
var _late: FullscreenRun = null
var _banner_requests: int = 0
var _banner_height: int = 0
var _rewarded_retry_ms: int = 0


## Fake everywhere until P405 adds the AdMob backend and wires `AdBackend.is_admob_mode` here
## (ADR 0039 section 2); `play` builds keep the fake until then.
static func _make_backend() -> AdBackend:
	return FakeAdBackend.new()


static func _default_auto_close(display_name: String) -> bool:
	return display_name == "headless"


func _init() -> void:
	_sync_fake()


func _ready() -> void:
	if _backend is FakeAdBackend:
		(_backend as FakeAdBackend).host = self


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


## Synchronous. The cached entitlement (P406 fills it).
func has_remove_ads() -> bool:
	return _ledger.remove_ads


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
## say no, and when the ad has not opened within `fullscreen_timeout_ms` (one deadline for the
## load and the open); once it opened the call waits for the close.
func maybe_show_interstitial(placement: StringName) -> bool:
	if _busy:
		return false
	_sync_fake()
	if not AdCaps.may_show_interstitial(_settings, _ledger, placement, _can_request_ads):
		return false
	var shown: bool = await _run_fullscreen(AdBackend.KIND_INTERSTITIAL, placement, Callable())
	if shown:
		_preload_interstitial()
	return shown


## Called once per finished match (win, loss, surrender) with its play time in whole seconds.
func note_match_completed(play_seconds: int) -> void:
	_ledger.note_match_completed(play_seconds)
	_preload_interstitial()


## Synchronous. The pending start-credits bonus once, then 0.
func take_start_credits_bonus() -> int:
	return _ledger.take_start_credits_bonus(_settings.start_credits_bonus_max)


## Internal (Phase 6 widgets). True when a rewarded ad is loaded and may be requested; an offer
## shows only then, never a spinner. Asks the backend to preload one when none is loading; after
## a failed load it asks again at most once per `banner_reload_min_ms` (that field is reused as
## the retry interval for every ad load).
@warning_ignore("unused_parameter")
# gdlint: ignore=unused-argument
func rewarded_ready(placement: StringName) -> bool:
	_sync_fake()
	if not _can_request_ads:
		return false
	var state: AdBackend.LoadState = _backend.load_state(AdBackend.KIND_REWARDED)
	var now: int = int(_now_ms.call())
	var failed_and_due: bool = state == AdBackend.LoadState.FAILED and now >= _rewarded_retry_ms
	if state == AdBackend.LoadState.IDLE or failed_and_due:
		_request_rewarded_load()
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
		_request_rewarded_load()
	return rewarded


## Internal, called by the banner band on `enter_tree`. Requests are counted: the banner shows
## while at least one is open.
func show_banner() -> void:
	_banner_requests += 1
	_refresh_banner()


## Internal, called by the banner band on `exit_tree`. The last release takes effect at idle, so a
## band that is reparented (out and in again within the frame) never destroys and reloads it.
func hide_banner() -> void:
	_banner_requests = maxi(_banner_requests - 1, 0)
	if _banner_requests == 0:
		_refresh_banner.call_deferred()
	else:
		_refresh_banner()


## Shows or hides the backend's banner for the current consent, entitlement and requests, and
## emits `banner_changed` when the height changed. Consent and billing call it when theirs change.
func _refresh_banner() -> void:
	_sync_fake()
	var may_show: bool = _banner_requests > 0 and _can_request_ads and not _ledger.remove_ads
	var height: int = 0
	if may_show:
		_backend.show_banner()
		height = _backend.banner_height_dp()
	else:
		_backend.hide_banner()
	if height != _banner_height:
		_banner_height = height
		banner_changed.emit(height)


func _request_rewarded_load() -> void:
	_backend.request_load(AdBackend.KIND_REWARDED)
	_rewarded_retry_ms = int(_now_ms.call()) + _settings.banner_reload_min_ms


## Loads the next interstitial ahead of need once ads may be requested at all.
func _preload_interstitial() -> void:
	if not _can_request_ads or _ledger.remove_ads:
		return
	var state: AdBackend.LoadState = _backend.load_state(AdBackend.KIND_INTERSTITIAL)
	if state == AdBackend.LoadState.IDLE or state == AdBackend.LoadState.FAILED:
		_backend.request_load(AdBackend.KIND_INTERSTITIAL)


func _run_fullscreen(kind: StringName, placement: StringName, on_reward: Callable) -> bool:
	if _late != null:
		_late.abandon()
		_late = null
	_busy = true
	var run: FullscreenRun = FullscreenRun.new(
		_backend, _now_ms, _settings.fullscreen_timeout_ms, _ledger, kind, placement, on_reward
	)
	run.opened.connect(_on_run_opened)
	run.closed.connect(_on_run_closed)
	var result: bool = await run.execute()
	_busy = false
	if run.is_late_pending():
		_late = run
	return result


func _on_run_opened(placement: StringName) -> void:
	if _late != null:
		_busy = true
	ad_opened.emit(placement)


func _on_run_closed(placement: StringName) -> void:
	if _late != null:
		_busy = false
		_late = null
	ad_closed.emit(placement)


func _sync_fake() -> void:
	if _backend is FakeAdBackend:
		var fake: FakeAdBackend = _backend as FakeAdBackend
		fake.auto_close = fake_auto_close
		fake.draw_placeholders = not fake_auto_close
