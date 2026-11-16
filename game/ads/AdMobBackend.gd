class_name AdMobBackend
extends AdBackend
## The real ad backend (ADR 0039 section 2), with `UmpPluginBackend` the only file that names the
## Poing Studios godot-admob plugin (v5.1.0, vendored at addons/admob). It talks to the plugin's
## native singletons directly (the same calls the plugin's GDScript wrappers make), reached through
## `lookup`, so nothing here needs the plugin's classes to be registered: the editor, the tests and
## every build without the plugin import this file unchanged. Tests pass a fake plugin object.
##
## Confirmed against the vendored v5.1.0 sources (the native Android part is not vendored):
## - Singletons: `PoingGodotAdMob` (initialize, set_request_configuration), `...InterstitialAd` and
##   `...RewardedAd` (create() -> uid, load(unit, request, keywords, uid), show(uid), destroy(uid)),
##   `...AdView` (create(dict) -> uid, load_ad, show, hide, destroy), `...AdSize`.
## - Every callback carries the ad's uid first; this class keeps a uid to kind map and ignores any
##   other uid. The wrappers defer every callback to the main thread (the native side may call from
##   another), so each connection here uses CONNECT_DEFERRED and the signals fire on the main
##   thread.
## - The reward signal `on_rewarded_ad_user_earned_reward(uid, item)` is the only source of
##   `reward_earned`. Signals are relayed in arrival order, so a reward that arrives after the close
##   comes after `closed`, and AdService then does not grant it.
## - A shown ad cannot be recalled: `cancel_show` does nothing.
## Not confirmable without a device (to confirm in P410b's APK): whether a created banner view is
## visible before its first `show`, and the banner's size unit (dp assumed, as the adaptive size
## call takes a width).

const S_CORE: String = "PoingGodotAdMob"
const S_INTERSTITIAL: String = "PoingGodotAdMobInterstitialAd"
const S_REWARDED: String = "PoingGodotAdMobRewardedAd"
const S_VIEW: String = "PoingGodotAdMobAdView"
const S_SIZE: String = "PoingGodotAdMobAdSize"
const SINGLETONS: Array[String] = [S_CORE, S_INTERSTITIAL, S_REWARDED, S_VIEW, S_SIZE]

## The plugin's AdPosition.BOTTOM, and its "no custom position" marker.
const POSITION_BOTTOM: int = 1
const NO_POSITION: int = -1
## Request configuration: not child-directed, max content rating T (ADR 0039 section 3).
const TAG_CHILD_FALSE: int = 0
const TAG_UNDER_AGE_UNSPECIFIED: int = -1
const MAX_RATING: String = "T"
const REQUEST_AGENT: String = "Godot-PoingStudios-5.1.0"

## Tests set the banner's reload gap (ms); the default is the data value.
var banner_reload_min_ms: int = AdsSettingsDef.load_default().banner_reload_min_ms

var _lookup: Callable
var _ids: AdIds
var _width_dp: Callable
var _now_ms: Callable
var _later: Callable
var _initialised: bool = false
var _sdk_ready: bool = false
var _connected: bool = false
var _states: Dictionary = {}
var _uids: Dictionary = {}
var _kind_of: Dictionary = {}
var _queued: Array[StringName] = []
var _banner_uid: int = -1
var _banner_shown: bool = false
var _banner_height: int = 0
var _banner_failed_ms: int = -1


func _init(
	ids: AdIds = null,
	lookup: Callable = AdMobBackend.engine_lookup,
	width_dp: Callable = AdMobBackend.screen_width_dp,
	now_ms: Callable = Time.get_ticks_msec,
	later: Callable = AdMobBackend.after_ms
) -> void:
	_ids = ids if ids != null else AdIds.load_units(OS.is_debug_build())
	_lookup = lookup
	_width_dp = width_dp
	_now_ms = now_ms
	_later = later


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
				"tag_for_under_age_of_consent": TAG_UNDER_AGE_UNSPECIFIED,
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
	plugin.show(int(_uids[kind]))


## AdMob cannot recall a show it has started; AdService hears a late open (see FullscreenRun).
func cancel_show(_kind: StringName) -> void:
	pass


## Idempotent. The first call creates the anchored adaptive banner at the bottom and loads it.
func show_banner() -> void:
	var view: Object = _plugin(S_VIEW)
	if view == null:
		return
	_connect_signals()
	if _banner_uid < 0:
		_create_banner(view)
	elif not _banner_shown:
		view.show(_banner_uid)
		_reload_banner_if_due(view)
	_banner_shown = true


func hide_banner() -> void:
	var view: Object = _plugin(S_VIEW)
	if view != null and _banner_uid >= 0 and _banner_shown:
		view.hide(_banner_uid)
	_banner_shown = false


func banner_height_dp() -> int:
	return _banner_height if _banner_shown else 0


func _create_banner(view: Object) -> void:
	var size: Dictionary = {"width": 0, "height": 0}
	var sizes: Object = _plugin(S_SIZE)
	if sizes != null:
		size = sizes.getCurrentOrientationAnchoredAdaptiveBannerAdSize(int(_width_dp.call()))
	_banner_height = int(size["height"])
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


func _reload_banner_if_due(view: Object) -> void:
	if _banner_failed_ms < 0:
		return
	if int(_now_ms.call()) - _banner_failed_ms >= banner_reload_min_ms:
		_banner_failed_ms = -1
		view.load_ad(_banner_uid, _request(), [])


func _retry_banner() -> void:
	var view: Object = _plugin(S_VIEW)
	if view != null and _banner_shown:
		_reload_banner_if_due(view)


func _load(kind: StringName) -> void:
	var plugin: Object = _fullscreen_plugin(kind)
	if plugin == null:
		_states[kind] = LoadState.FAILED
		return
	var uid: int = int(plugin.create())
	_uids[kind] = uid
	_kind_of[uid] = kind
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
	var inter: String = "on_interstitial_ad_"
	_on(S_INTERSTITIAL, inter + "loaded", _on_loaded.bind(KIND_INTERSTITIAL))
	_on(S_INTERSTITIAL, inter + "failed_to_load", _on_load_failed.bind(KIND_INTERSTITIAL))
	_on(S_INTERSTITIAL, inter + "showed_full_screen_content", _on_opened)
	_on(S_INTERSTITIAL, inter + "dismissed_full_screen_content", _on_closed)
	_on(S_INTERSTITIAL, inter + "failed_to_show_full_screen_content", _on_show_failed)
	var rewarded: String = "on_rewarded_ad_"
	_on(S_REWARDED, rewarded + "loaded", _on_loaded.bind(KIND_REWARDED))
	_on(S_REWARDED, rewarded + "failed_to_load", _on_load_failed.bind(KIND_REWARDED))
	_on(S_REWARDED, rewarded + "showed_full_screen_content", _on_opened)
	_on(S_REWARDED, rewarded + "dismissed_full_screen_content", _on_closed)
	_on(S_REWARDED, rewarded + "failed_to_show_full_screen_content", _on_show_failed)
	_on(S_REWARDED, rewarded + "user_earned_reward", _on_reward)
	_on(S_VIEW, "on_ad_failed_to_load", _on_banner_failed)


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
	if _kind_of.get(uid) == kind:
		_states[kind] = LoadState.READY


func _on_load_failed(uid: int, _error: Dictionary, kind: StringName) -> void:
	if _kind_of.get(uid) == kind:
		_states[kind] = LoadState.FAILED
		_kind_of.erase(uid)


func _on_opened(uid: int) -> void:
	if _kind_of.has(uid):
		opened.emit(_kind_of[uid])


func _on_closed(uid: int) -> void:
	if _kind_of.has(uid):
		var kind: StringName = _kind_of[uid]
		_release(uid, kind)
		closed.emit(kind)


func _on_show_failed(uid: int, _error: Dictionary = {}) -> void:
	if _kind_of.has(uid):
		var kind: StringName = _kind_of[uid]
		_release(uid, kind)
		show_failed.emit(kind)


func _on_reward(uid: int, _item: Dictionary = {}) -> void:
	if _kind_of.has(uid):
		reward_earned.emit(_kind_of[uid])


func _on_banner_failed(uid: int, _error: Dictionary = {}) -> void:
	if uid == _banner_uid:
		_banner_failed_ms = int(_now_ms.call())
		_later.call(banner_reload_min_ms, _retry_banner)


## A shown ad is spent: free its native object and forget it, so the next load makes a new one.
func _release(uid: int, kind: StringName) -> void:
	var plugin: Object = _fullscreen_plugin(kind)
	if plugin != null:
		plugin.destroy(uid)
	_kind_of.erase(uid)
	if _uids.get(kind) == uid:
		_uids.erase(kind)
