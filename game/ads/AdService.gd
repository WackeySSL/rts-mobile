extends Node
## The one facade for ads, consent and the Remove ads purchase (ADR 0039 section 1).
## Phase 5 calls only what is declared here; the signals, methods and their types are the
## agreed contract (docs/plans/2026-11-15-phase-6.md, "Interfaces with Phase 5", item 1).
##
## P403 fills in the ads behind these signatures: the caps (AdCaps), the counters (AdLedger, in
## memory until P407 saves it), the timeouts from data, the banner and the rewarded ad, all through
## an AdBackend: the AdMobBackend in AdMob mode (P405), else the FakeAdBackend. Consent (P404) goes
## through a ConsentBackend (UmpPluginBackend in AdMob mode, else FakeUmp): the SDK is initialised
## and any ad loaded only once `_can_request_ads` is true. Purchases (P406) go through Purchases
## over a BillingBackend (always the FakeBilling until P406b adds the Play one) and do not depend
## on consent: the ledger's Remove ads flag follows them, and a silent restore runs on start and on
## resume. No plugin code and no ad IDs live here.
##
## Persistence (P407): the ledger is the `ads` section of SaveService. Autoloads are all created
## before any is in the tree, so the load happens in `_ready`, not `_init`: SaveService is listed
## before AdService in project.godot and has loaded by then. The load comes before the silent
## restore, so a buyer's cached Remove ads is in the ledger before the first banner request. Every
## ledger change saves; the entitlement, a shown interstitial and a start-credits grant also flush
## at once (the app may be killed under an ad), the entitlement before `entitlement_changed` is
## emitted. Consent is not saved (UMP keeps its own storage).
## Never touched by game/sim. No class_name: this is an autoload (tests/project/test_autoloads.gd).

## Fires when consent is settled, with whether ads may be requested. `ensure_consent` emits it
## before it returns; a privacy options choice that changes the answer emits it again.
signal consent_finished(can_request_ads: bool)
## Fires when the Remove ads entitlement changes, with the new state.
signal entitlement_changed(has_remove_ads: bool)
## Fires when the banner's height changes, with the new height in dp (0 = none).
signal banner_changed(height_dp: int)
## Fires when a full-screen ad opens, with its placement.
signal ad_opened(placement: StringName)
## Fires when a full-screen ad closes, with its placement.
signal ad_closed(placement: StringName)

const SaveServiceScript: GDScript = preload("res://game/meta/save_service.gd")

## True: fake full-screen ads and fake flows close at once (gdUnit4, headless). False: the fake
## placeholders wait for their Close button and the fake flows for their buttons (P403 on).
## Tests may set it; the fake backend follows at the next call.
var fake_auto_close: bool = _default_auto_close(DisplayServer.get_name())

## Tests inject a SaveService here; null means the SaveService autoload.
var save_service: SaveServiceScript = null

## Debug builds only: ask UMP for the EEA debug geography, so the form shows for a test device
## (ADR 0039 section 3). ConsentFlow ignores it unless `OS.is_debug_build()`.
var debug_geography_eea: bool = false

## Consent's answer: whether ads may be requested at all. Only `_set_can_request` writes it.
var _can_request_ads: bool = false
var _consent: ConsentFlow = ConsentFlow.new(_make_consent(not fake_auto_close), OS.is_debug_build)
var _initialised: bool = false
var _settings: AdsSettingsDef = AdsSettingsDef.load_default()
var _ledger: AdLedger = AdLedger.new()
var _ledger_loaded: bool = false
var _backend: AdBackend = _make_backend()
var _billing: BillingBackend = _make_billing()
var _purchases: Purchases = null
## Milliseconds clock for the timeouts and retries; tests replace it with a fake one.
var _now_ms: Callable = Time.get_ticks_msec
## The full-screen runs: the one awaited and the late ones; see FullscreenRuns.
var _runs: FullscreenRuns = FullscreenRuns.new()
var _banner_shown: bool = false
## The backend holds a banner view (shown or hidden) that Remove ads or lost consent must destroy.
var _banner_alive: bool = false
var _banner_requests: int = 0
var _banner_height: int = 0
var _rewarded_retry_ms: int = 0


## AdMob mode (ADR 0039 section 2): Android, not the editor, the plugin's singletons present and
## the `play` feature tag. Everything else, desktop, headless, web and the dev APKs, is fake mode.
static func _is_admob_mode() -> bool:
	return AdBackend.is_admob_mode(
		OS.get_name(),
		OS.has_feature("editor"),
		AdMobBackend.plugin_present() and UmpPluginBackend.plugin_present(),
		OS.has_feature("play")
	)


## The real backend in AdMob mode, else the fake. Debug builds get Google's test units (AdIds).
static func _make_backend() -> AdBackend:
	if _is_admob_mode():
		return AdMobBackend.new(AdIds.load_units(OS.is_debug_build()))
	return FakeAdBackend.new()


## The real UMP backend in AdMob mode, else the fake. Where the fake placeholders wait for buttons
## (the editor, the phone preview) consent is required by default, so the form can be walked;
## headless stays "not required".
static func _make_consent(required: bool) -> ConsentBackend:
	if _is_admob_mode():
		return UmpPluginBackend.new()
	var ump: FakeUmp = FakeUmp.new()
	ump.consent_required = required
	return ump


## Fake everywhere until P406b adds the Play Billing backend (ADR 0039 section 8).
static func _make_billing() -> BillingBackend:
	return FakeBilling.new()


static func _default_auto_close(display_name: String) -> bool:
	return display_name == "headless"


func _init() -> void:
	_consent.settled.connect(_set_can_request)
	_backend.can_request_ads = func() -> bool: return _can_request_ads
	_backend.banner_height_changed.connect(_refresh_banner)
	_runs.opened.connect(ad_opened.emit)
	_runs.closed.connect(ad_closed.emit)
	_sync_fake()
	_purchases = Purchases.new(_billing, _settings.remove_ads_product_id, has_remove_ads)
	_purchases.entitlement_changed.connect(_on_entitlement_changed)


func _ready() -> void:
	_load_ledger()
	if not _ledger_loaded:
		push_warning("AdService: no SaveService; the ads ledger is not persisted")
	# Silent, no UI: retries failed acknowledges and grants pendings paid while the app was closed.
	_restore_silently()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_restore_silently()


## Awaitable; always finishes. True means ads may be requested. Runs the consent info update and
## the form load within `consent_timeout_ms`, waits for the form once it shows, then sets the
## gate and emits `consent_finished`. Offline, an error or the timeout give false. A call while
## a consent or privacy options flow runs waits for it.
func ensure_consent() -> bool:
	_sync_fake()
	return await _consent.run_consent(_now_ms, _settings.consent_timeout_ms, debug_geography_eea)


## Synchronous. UMP's answer from the last consent update.
func is_privacy_options_required() -> bool:
	return _consent.backend.is_privacy_options_required()


## Awaitable until UMP's privacy options form closes (no timeout once it shows). A choice that
## changes whether ads may be requested takes effect when it closes. While a consent or privacy
## options flow runs it waits for that flow and shows nothing more.
func show_privacy_options() -> void:
	_sync_fake()
	await _consent.run_privacy_options(_now_ms, _settings.consent_timeout_ms)


## Synchronous. The cached entitlement: Play's answer when it answers, else the last known one.
func has_remove_ads() -> bool:
	return _ledger.remove_ads


## Awaitable. True once the entitlement is held (also when it already was). False on cancel, on
## PENDING (never granted), on failure and when the store sheet has not shown within
## `billing_timeout_ms`; once it showed the call waits for it.
func purchase_remove_ads() -> bool:
	_sync_fake()
	return await _purchases.purchase(_now_ms, _settings.billing_timeout_ms)


## Awaitable. True when the entitlement stands after the store's answer. That answer is the truth:
## a missing purchase clears the entitlement (a refund); no answer (offline, timeout) keeps the
## cached one and returns false. Returns false at once while a purchase or another restore waits.
func restore_purchases() -> bool:
	_sync_fake()
	return await _purchases.restore(_now_ms, _settings.billing_timeout_ms)


## Internal (Phase 6 widgets). The store's localised price text for Remove ads, empty until known
## or when billing is unavailable: the row is hidden then. Never a literal in the game.
func remove_ads_price_text() -> String:
	return _purchases.price_text()


## Synchronous. The banner's height while one may show (consent, no Remove ads, a band asked for
## it through `show_banner`), else 0.
func banner_height_dp() -> int:
	return _banner_height


## Awaitable. True means one interstitial showed and closed. Returns false at once when the caps
## say no, and when the ad has not opened within `fullscreen_timeout_ms` (one deadline for the
## load and the open); once it opened the call waits for the close.
func maybe_show_interstitial(placement: StringName) -> bool:
	if _runs.is_busy():
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
	_save_ledger()
	_preload_interstitial()


## Synchronous. The pending start-credits bonus once, then 0.
func take_start_credits_bonus() -> int:
	var had_pending: bool = _ledger.pending_start_credits > 0
	var taken: int = _ledger.take_start_credits_bonus(_settings.start_credits_bonus_max)
	if had_pending:
		_save_ledger()
	return taken


## Internal (Phase 6 widgets; P433's grant after the rewarded callback). Records the pending
## start-credits bonus, at most `start_credits_bonus_max`, and saves it at once (ADR 0039 section
## 7). False, and nothing changes, while a bonus is already pending.
func grant_start_credits_bonus(amount: int) -> bool:
	var granted: bool = _ledger.grant_start_credits_bonus(amount, _settings.start_credits_bonus_max)
	if granted:
		_save_ledger(true)
	return granted


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
	if _runs.is_busy() or not rewarded_ready(placement):
		return false
	var rewarded: bool = await _run_fullscreen(AdBackend.KIND_REWARDED, placement, on_reward)
	_request_rewarded_load()
	return rewarded


## Internal (P435). The height a band would get if it asked now, with no request made: lets a host
## see whether the banner fits before it shows one. 0 where none may show.
func banner_height_preview_dp() -> int:
	if _initialised and _can_request_ads and not _ledger.remove_ads:
		return _backend.banner_height_preview_dp()
	return 0


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
	var may_show: bool = (
		_initialised and _banner_requests > 0 and _can_request_ads and not _ledger.remove_ads
	)
	var height: int = 0
	if may_show:
		if not _banner_shown:
			_banner_shown = true
			_banner_alive = true
			_backend.show_banner()
		height = _backend.banner_height_dp()
	elif (_ledger.remove_ads or not _can_request_ads or _banner_requests == 0) and _banner_alive:
		# Remove ads, no consent, or the last band released (at idle, so a reparent keeps it): the
		# view goes, not just out of sight (ADR 0039 sections 6 and 8).
		_banner_alive = false
		_banner_shown = false
		_backend.destroy_banner()
	elif _banner_shown:
		_banner_shown = false
		_backend.hide_banner()
	if height != _banner_height:
		_banner_height = height
		banner_changed.emit(height)


## The one writer of the gate: initialises the SDK when ads may first be requested, tells the
## banner, and announces the answer.
func _set_can_request(allowed: bool) -> void:
	_can_request_ads = allowed
	if not allowed:
		_runs.cancel_unopened()
	if allowed and not _initialised:
		_initialised = true
		_backend.initialize()
	_refresh_banner()
	consent_finished.emit(allowed)


## The entitlement changed (a purchase, a restore, a refund): the ledger follows, then the banner.
func _on_entitlement_changed(has_remove_ads_now: bool) -> void:
	if has_remove_ads_now == _ledger.remove_ads:
		return
	_ledger.remove_ads = has_remove_ads_now
	_save_ledger(true)  # Save, then emit (ADR 0039 section 8).
	# An interstitial that has not opened yet is withdrawn; AdMob cannot recall a show it started,
	# so it may still appear once, paired and counted. A rewarded ad stays: rewards remain.
	if has_remove_ads_now:
		_runs.cancel_unopened(AdBackend.KIND_INTERSTITIAL)
	# The banner first, so a handler reads the fresh `banner_height_dp()`.
	_refresh_banner()
	entitlement_changed.emit(has_remove_ads_now)


func _request_rewarded_load() -> void:
	if not _can_request_ads:
		return
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
	var run: FullscreenRun = FullscreenRun.new(
		_backend, _now_ms, _settings.fullscreen_timeout_ms, _ledger, kind, placement, on_reward
	)
	if kind == AdBackend.KIND_INTERSTITIAL:
		run.opened.connect(_save_after_open)
	return await _runs.start(run)


## An interstitial that opened was noted in the ledger by the run: save it.
func _save_after_open(_placement: StringName, _run: FullscreenRun) -> void:
	_save_ledger(true)


## The injected SaveService, else the autoload; null when neither is there.
func _save_service() -> SaveServiceScript:
	if is_instance_valid(save_service):
		return save_service
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	return root.get_node_or_null("SaveService") as SaveServiceScript


## Reads the `ads` section once; a missing or corrupt one gives the defaults. The ledger object
## stays (Purchases and the runs hold it), so its fields are replaced in place.
func _load_ledger() -> void:
	var service: SaveServiceScript = _save_service()
	if _ledger_loaded or service == null:
		return
	_ledger_loaded = true
	_ledger.apply_dict(service.get_section(&"ads"))


## Queues the ledger into SaveService (atomic file, one write at the frame's end), or writes it at
## once with `now`. Does nothing before the section was read, so a fresh ledger never overwrites
## the saved one.
func _save_ledger(now: bool = false) -> void:
	var service: SaveServiceScript = _save_service()
	if service == null or not _ledger_loaded:
		return
	service.set_section(&"ads", _ledger.to_dict())
	if now:
		service.flush()


func _restore_silently() -> void:
	await restore_purchases()


func _sync_fake() -> void:
	if _backend is FakeAdBackend:
		var fake: FakeAdBackend = _backend as FakeAdBackend
		fake.auto_close = fake_auto_close
		fake.draw_placeholders = not fake_auto_close
		fake.strict_order = true
		fake.host = self
	if _billing is FakeBilling:
		var store: FakeBilling = _billing as FakeBilling
		store.host = self
		store.auto_close = fake_auto_close
		store.draw_placeholders = not fake_auto_close
	_consent.configure_fake(fake_auto_close, self)
