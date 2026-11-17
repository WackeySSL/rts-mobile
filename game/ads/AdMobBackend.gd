class_name AdMobBackend
extends AdBackend
## The real ad backend (ADR 0039 section 2), with `UmpPluginBackend` the only file that names the
## Poing Studios godot-admob plugin (v5.1.0, vendored at addons/admob). It talks to the plugin's
## native singletons directly (the same calls the plugin's GDScript wrappers make), reached through
## `lookup`, so nothing here needs the plugin's classes to be registered: the editor, the tests and
## every build without the plugin import this file unchanged. Tests pass fake plugin objects.
##
## Confirmed against the vendored v5.1.0 sources (the native Android part is not vendored):
## - Singletons: `PoingGodotAdMob` (initialize, set_request_configuration), `...InterstitialAd` and
##   `...RewardedAd` (create() -> uid, load(unit, request, keywords, uid), show(uid), destroy(uid)),
##   `...AdView` (create(dict) -> uid, load_ad, show, hide, destroy), `...AdSize`.
## - Every callback carries the ad's uid first. Uids are per singleton (the vendored mocks each
##   count from 1), so this class keeps its uids per kind, binds the kind into every connection and
##   ignores a uid that is not the kind's current one. The wrappers defer every callback to the main
##   thread (the native side may call from another), so each connection here uses CONNECT_DEFERRED
##   and the signals fire on the main thread.
## - The reward signal `on_rewarded_ad_user_earned_reward(uid, item)` is the only source of
##   `reward_earned`. Signals are relayed in arrival order, so a reward that arrives after the close
##   comes after `closed`, and AdService then does not grant it.
## - A shown ad cannot be recalled: `cancel_show` does nothing. A callback from an ad that a newer
##   show of the same kind has replaced is ignored (its native object is still destroyed on close).
## - A failed load destroys its native ad, so no-fill retries do not leak.
## Not confirmable without a device (to confirm in P410b's APK): whether a created banner view is
## visible before its first `show`, the banner's size unit (dp assumed, as the adaptive size call
## takes a width), and uid reuse: if the native side hands out a destroyed ad's uid again, a late
## callback from the old ad could match the new one, and nothing here can tell them apart.

const S_CORE: String = "PoingGodotAdMob"
const S_INTERSTITIAL: String = "PoingGodotAdMobInterstitialAd"
const S_REWARDED: String = "PoingGodotAdMobRewardedAd"
const S_VIEW: String = "PoingGodotAdMobAdView"
const S_SIZE: String = "PoingGodotAdMobAdSize"
const SINGLETONS: Array[String] = [S_CORE, S_INTERSTITIAL, S_REWARDED, S_VIEW, S_SIZE]

## The plugin's AdPosition.BOTTOM, and its "no custom position" marker.
const POSITION_BOTTOM: int = 1
const NO_POSITION: int = -1
## Request configuration: not child-directed, not under the age of consent (our audience is 13 and
## over, ADR 0039 section 3), max content rating T. UMP gets the same under-age answer (false).
const TAG_CHILD_FALSE: int = 0
const TAG_UNDER_AGE_FALSE: int = 0
const MAX_RATING: String = "T"
const REQUEST_AGENT: String = "Godot-PoingStudios-5.1.0"

## Tests set the banner's reload gap (ms); the default is the data value.
var banner_reload_min_ms: int = AdsSettingsDef.load_default().banner_reload_min_ms

var _lookup: Callable
var _ids: AdIds
var _width_dp: Callable
var _now_ms: Callable
var _later: Callable
var _size_changed: Signal
var _initialised: bool = false
var _sdk_ready: bool = false
var _connected: bool = false
var _states: Dictionary = {}
## Per kind: the uid of the latest ad created, and of the latest one shown and not yet closed.
var _uids: Dictionary = {}
var _shown: Dictionary = {}
var _queued: Array[StringName] = []
var _banner_uid: int = -1
var _banner_shown: bool = false
var _banner_loaded: bool = false
var _banner_width: int = 0
var _banner_height: int = 0
var _banner_failed_ms: int = -1
var _retry_pending: bool = false
## The last turn's re-create (ms, -1 = none yet), and whether one is waiting for the gap to pass.
var _turn_ms: int = -1
var _turn_pending: bool = false


func _init(
	ids: AdIds = null,
	lookup: Callable = AdMobBackend.engine_lookup,
	width_dp: Callable = AdMobBackend.screen_width_dp,
	now_ms: Callable = Time.get_ticks_msec,
	later: Callable = AdMobBackend.after_ms,
	size_changed: Signal = AdMobBackend.root_size_changed()
) -> void:
	_ids = ids if ids != null else AdIds.load_units(OS.is_debug_build())
	_lookup = lookup
	_width_dp = width_dp
	_now_ms = now_ms
	_later = later
	_size_changed = size_changed


## True when every singleton this backend uses is registered (an Android build with the plugin).
static func plugin_present() -> bool:
	for singleton: String in SINGLETONS:
		if not Engine.has_singleton(singleton):
			return false
	return true


static func engine_lookup(singleton: String) -> Object:
	return Engine.get_singleton(singleton) if Engine.has_singleton(singleton) else null


static func screen_width_dp() -> int:
	var dpi: int = maxi(DisplayServer.screen_get_dpi(), 1)
	return DisplayServer.window_get_size().x * 160 / dpi


## The main window's size_changed (a turn of the phone), or a null Signal without a tree.
static func root_size_changed() -> Signal:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.size_changed if tree != null else Signal()


## Calls `callback` after `ms` milliseconds, on the main loop's clock.
static func after_ms(ms: int, callback: Callable) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.create_timer(float(ms) / 1000.0).timeout.connect(callback)


func initialize() -> void:
	if _initialised:
		return
	_initialised = true
	_connect_signals()
	var core: Object = _plugin(S_CORE)
	if core == null:
		return
	(
		core
		. set_request_configuration(
			{
				"max_ad_content_rating": MAX_RATING,
				"tag_for_child_directed_treatment": TAG_CHILD_FALSE,
				"tag_for_under_age_of_consent": TAG_UNDER_AGE_FALSE,
			},
			[]
		)
	)
	core.initialize()


func load_state(kind: StringName) -> LoadState:
	return _states.get(kind, LoadState.IDLE) as LoadState


func request_load(kind: StringName) -> void:
	var state: LoadState = load_state(kind)
	if state == LoadState.LOADING or state == LoadState.READY or not _initialised:
		return
	if not bool(can_request_ads.call()):
		return
	_states[kind] = LoadState.LOADING
	if _sdk_ready:
		_load(kind)
	elif kind not in _queued:
		_queued.append(kind)


func show_ad(kind: StringName) -> void:
	var plugin: Object = _fullscreen_plugin(kind)
	if load_state(kind) != LoadState.READY or plugin == null:
		show_failed.emit(kind)
		return
	_states[kind] = LoadState.IDLE
	_shown[kind] = _uids[kind]
	plugin.show(int(_uids[kind]))


## AdMob cannot recall a show it has started; AdService hears a late open (see FullscreenRun).
func cancel_show(_kind: StringName) -> void:
	pass


## Idempotent. The first call creates the anchored adaptive banner at the bottom and loads it; a
## banner made for another width (the phone turned while it was hidden) is made again.
func show_banner() -> void:
	var view: Object = _plugin(S_VIEW)
	if view == null:
		return
	_connect_signals()
	if _banner_uid >= 0 and int(_width_dp.call()) != _banner_width:
		_drop_banner(view)
	if _banner_uid < 0:
		_create_banner(view)
	else:
		if not _banner_shown:
			view.show(_banner_uid)
		_reload_banner_if_due(view)
	_banner_shown = true


func hide_banner() -> void:
	var view: Object = _plugin(S_VIEW)
	if view != null and _banner_uid >= 0 and _banner_shown:
		view.hide(_banner_uid)
	_banner_shown = false


func destroy_banner() -> void:
	var view: Object = _plugin(S_VIEW)
	if view != null:
		_drop_banner(view)
	_banner_shown = false


## 0 until the banner has loaded, and again after a failed load or while it is made again.
func banner_height_dp() -> int:
	return _banner_height if _banner_shown and _banner_loaded else 0


## The height the banner will have for the current width, known before it loads: the adaptive
## size's own answer (what `_create_banner` asks for), so the pause foot's first fit check is real.
## The loaded height once there is one. 0 without the plugin or before `initialize`.
func banner_height_preview_dp() -> int:
	if not _initialised:
		return 0
	if _banner_shown and _banner_loaded:
		return _banner_height
	var sizes: Object = _plugin(S_SIZE)
	if sizes == null:
		return 0
	var size: Dictionary = sizes.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
		int(_width_dp.call())
	)
	return int(size["height"])


func _create_banner(view: Object) -> void:
	var size: Dictionary = {"width": 0, "height": 0}
	var sizes: Object = _plugin(S_SIZE)
	_banner_width = int(_width_dp.call())
	if sizes != null:
		size = sizes.getCurrentOrientationAnchoredAdaptiveBannerAdSize(_banner_width)
	_banner_height = int(size["height"])
	_banner_loaded = false
	_banner_uid = int(
		(
			view
			. create(
				{
					"ad_unit_id": _ids.unit(AdIds.KIND_BANNER),
					"ad_position": POSITION_BOTTOM,
					"custom_position": {"x": NO_POSITION, "y": NO_POSITION},
					"ad_size": size,
				}
			)
		)
	)
	view.load_ad(_banner_uid, _request(), [])


func _drop_banner(view: Object) -> void:
	if _banner_uid >= 0:
		view.destroy(_banner_uid)
	_banner_uid = -1
	_banner_loaded = false
	_banner_failed_ms = -1


## Reloads a failed banner once the gap has passed; before that it asks `_later` to come back for
## the rest of the gap (a timer may fire a little early).
func _reload_banner_if_due(view: Object) -> void:
	if _banner_failed_ms < 0:
		return
	var remaining: int = banner_reload_min_ms - (int(_now_ms.call()) - _banner_failed_ms)
	if remaining <= 0:
		_banner_failed_ms = -1
		view.load_ad(_banner_uid, _request(), [])
	elif not _retry_pending:
		_retry_pending = true
		_later.call(remaining, _retry_banner)


func _retry_banner() -> void:
	_retry_pending = false
	var view: Object = _plugin(S_VIEW)
	if view != null and _banner_shown and _banner_uid >= 0:
		_reload_banner_if_due(view)


func _load(kind: StringName) -> void:
	var plugin: Object = _fullscreen_plugin(kind)
	if plugin == null:
		_states[kind] = LoadState.FAILED
		return
	if not bool(can_request_ads.call()):
		_states[kind] = LoadState.IDLE
		return
	var uid: int = int(plugin.create())
	_uids[kind] = uid
	plugin.load(_ids.unit(kind), _request(), [], uid)


func _request() -> Dictionary:
	return {"mediation_extras": {}, "extras": {}, "google_request_agent": REQUEST_AGENT}


func _fullscreen_plugin(kind: StringName) -> Object:
	return _plugin(S_INTERSTITIAL if kind == KIND_INTERSTITIAL else S_REWARDED)


func _plugin(singleton: String) -> Object:
	var found: Variant = _lookup.call(singleton)
	return found as Object


func _connect_signals() -> void:
	if _connected:
		return
	_connected = true
	_on(S_CORE, "on_initialization_complete", _on_initialised)
	_on_fullscreen(S_INTERSTITIAL, "on_interstitial_ad_", KIND_INTERSTITIAL)
	_on_fullscreen(S_REWARDED, "on_rewarded_ad_", KIND_REWARDED)
	_on(S_REWARDED, "on_rewarded_ad_user_earned_reward", _on_reward.bind(KIND_REWARDED))
	_on(S_VIEW, "on_ad_loaded", _on_banner_loaded)
	_on(S_VIEW, "on_ad_failed_to_load", _on_banner_failed)
	if not _size_changed.is_null():
		_size_changed.connect(_on_resized)


## The load, show and close signals of one full-screen singleton, each bound to its kind.
func _on_fullscreen(singleton: String, prefix: String, kind: StringName) -> void:
	_on(singleton, prefix + "loaded", _on_loaded.bind(kind))
	_on(singleton, prefix + "failed_to_load", _on_load_failed.bind(kind))
	_on(singleton, prefix + "showed_full_screen_content", _on_opened.bind(kind))
	_on(singleton, prefix + "dismissed_full_screen_content", _on_closed.bind(kind))
	_on(singleton, prefix + "failed_to_show_full_screen_content", _on_show_failed.bind(kind))


func _on(singleton: String, signal_name: String, callable: Callable) -> void:
	var plugin: Object = _plugin(singleton)
	if plugin != null:
		plugin.connect(signal_name, callable, CONNECT_DEFERRED)


func _on_initialised(_status: Dictionary = {}) -> void:
	_sdk_ready = true
	var queued: Array[StringName] = _queued.duplicate()
	_queued.clear()
	for kind: StringName in queued:
		_load(kind)


func _on_loaded(uid: int, kind: StringName) -> void:
	if _uids.get(kind) == uid and load_state(kind) == LoadState.LOADING:
		_states[kind] = LoadState.READY


func _on_load_failed(uid: int, _error: Dictionary, kind: StringName) -> void:
	if _uids.get(kind) == uid and load_state(kind) == LoadState.LOADING:
		_states[kind] = LoadState.FAILED
		_uids.erase(kind)
		_destroy(uid, kind)


func _on_opened(uid: int, kind: StringName) -> void:
	if _shown.get(kind) == uid:
		opened.emit(kind)


func _on_closed(uid: int, kind: StringName) -> void:
	var current: bool = _shown.get(kind) == uid
	_release(uid, kind)
	if current:
		closed.emit(kind)


func _on_show_failed(uid: int, _error: Dictionary, kind: StringName) -> void:
	var current: bool = _shown.get(kind) == uid
	_release(uid, kind)
	if current:
		show_failed.emit(kind)


func _on_reward(uid: int, _item: Dictionary, kind: StringName) -> void:
	if _shown.get(kind) == uid:
		reward_earned.emit(kind)


func _on_banner_loaded(uid: int) -> void:
	if uid == _banner_uid:
		_banner_loaded = true
		banner_height_changed.emit()


func _on_banner_failed(uid: int, _error: Dictionary = {}) -> void:
	if uid != _banner_uid:
		return
	_banner_loaded = false
	_banner_failed_ms = int(_now_ms.call())
	banner_height_changed.emit()
	var view: Object = _plugin(S_VIEW)
	if view != null and _banner_shown:
		_reload_banner_if_due(view)


## The phone turned while the banner shows: the adaptive size depends on the width, so the banner
## is destroyed and made again at the new width (its height is 0 until it loads), at most once per
## `banner_reload_min_ms`. Turns inside the gap coalesce into one re-create at the gap's end.
func _on_resized() -> void:
	_remake_for_turn()


func _remake_for_turn() -> void:
	var view: Object = _plugin(S_VIEW)
	if view == null or _banner_uid < 0 or not _banner_shown:
		return
	if int(_width_dp.call()) == _banner_width:
		return
	var remaining: int = banner_reload_min_ms - (int(_now_ms.call()) - _turn_ms)
	if _turn_ms >= 0 and remaining > 0:
		if not _turn_pending:
			_turn_pending = true
			_later.call(remaining, _turn_due)
		return
	_turn_ms = int(_now_ms.call())
	_drop_banner(view)
	_create_banner(view)
	banner_height_changed.emit()


func _turn_due() -> void:
	_turn_pending = false
	_remake_for_turn()


## A shown ad is spent (or superseded): free its native object and forget it, so the next load
## makes a new one. Only the kind's current shown ad is forgotten.
func _release(uid: int, kind: StringName) -> void:
	_destroy(uid, kind)
	if _shown.get(kind) == uid:
		_shown.erase(kind)
	if _uids.get(kind) == uid:
		_uids.erase(kind)


func _destroy(uid: int, kind: StringName) -> void:
	var plugin: Object = _fullscreen_plugin(kind)
	if plugin != null:
		plugin.destroy(uid)
