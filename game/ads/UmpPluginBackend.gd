class_name UmpPluginBackend
extends ConsentBackend
## The real consent backend (ADR 0039 section 3): Google's UMP through the Poing godot-admob plugin
## (v5.1.0). With `AdMobBackend` the only file that names the plugin; it uses the plugin's native
## singletons through `lookup`, so it imports without the plugin and a test passes a fake object.
##
## Confirmed against the vendored v5.1.0 sources:
## - Singletons: `PoingGodotAdMobConsentInformation` (update, get_consent_status,
##   get_privacy_options_requirement_status) and `PoingGodotAdMobUserMessagingPlatform`
##   (load_consent_form, show(form uid), show_privacy_options_form).
## - The plugin's consent status enum is UNKNOWN 0, NOT_REQUIRED 1, REQUIRED 2, OBTAINED 3: not the
##   order of `ConsentBackend.Status`, so `consent_status` maps it. Privacy options: REQUIRED is 2.
## - The plugin has no "can request ads" call. UMP's rule is derived: true for NOT_REQUIRED and
##   OBTAINED. A stored consent offline is not used (the base class notes the same).
## - The info update answers with `on_consent_info_updated_success()` or `..._failure(error)`, the
##   form load with `on_consent_form_load_success_listener(uid)` or `..._failure_listener(error)`, a
##   shown form with `on_consent_form_dismissed(uid, error)` and the privacy options form with
##   `on_privacy_options_form_dismissed_listener(error)`. All connect with CONNECT_DEFERRED (main
##   thread) and, unlike the plugin's wrappers, before the call, so a fast answer is not missed.
## - `update` takes {tag_for_under_age_of_consent, consent_debug_settings: {debug_geography,
##   test_device_hashed_ids}}; the debug geography is 0 disabled, 1 EEA, 2 not EEA.

const S_INFO: String = "PoingGodotAdMobConsentInformation"
const S_UMP: String = "PoingGodotAdMobUserMessagingPlatform"
const SINGLETONS: Array[String] = [S_INFO, S_UMP]

const PLUGIN_NOT_REQUIRED: int = 1
const PLUGIN_REQUIRED: int = 2
const PLUGIN_OBTAINED: int = 3
const GEOGRAPHY_DISABLED: int = 0
const GEOGRAPHY_EEA: int = 1

var _lookup: Callable
var _test_device_hash: Callable
var _connected: bool = false
var _info: Step = Step.PENDING
var _form: Step = Step.PENDING
var _form_uid: int = -1


func _init(
	lookup: Callable = UmpPluginBackend.engine_lookup,
	test_device_hash: Callable = AdIds.test_device_hash
) -> void:
	_lookup = lookup
	_test_device_hash = test_device_hash


static func plugin_present() -> bool:
	for singleton: String in SINGLETONS:
		if not Engine.has_singleton(singleton):
			return false
	return true


static func engine_lookup(singleton: String) -> Object:
	return Engine.get_singleton(singleton) if Engine.has_singleton(singleton) else null


## `debug_eea` is passed by ConsentFlow only in a debug build (never in release).
func update_info(debug_eea: bool) -> void:
	_info = Step.PENDING
	var info: Object = _plugin(S_INFO)
	if info == null:
		_info = Step.FAILED
		return
	_connect_signals()
	var debug: Variant = null
	var hash_id: String = String(_test_device_hash.call())
	if debug_eea and not hash_id.is_empty():
		debug = {"debug_geography": GEOGRAPHY_EEA, "test_device_hashed_ids": {0: hash_id}}
	info.update({"tag_for_under_age_of_consent": false, "consent_debug_settings": debug})


func info_state() -> Step:
	return _info


func consent_status() -> Status:
	var info: Object = _plugin(S_INFO)
	if info == null:
		return Status.UNKNOWN
	match int(info.get_consent_status()):
		PLUGIN_NOT_REQUIRED:
			return Status.NOT_REQUIRED
		PLUGIN_REQUIRED:
			return Status.REQUIRED
		PLUGIN_OBTAINED:
			return Status.OBTAINED
	return Status.UNKNOWN


func load_form() -> void:
	_form = Step.PENDING
	_form_uid = -1
	var ump: Object = _plugin(S_UMP)
	if ump == null:
		_form = Step.FAILED
		return
	_connect_signals()
	ump.load_consent_form()


func form_state() -> Step:
	return _form


func show_form() -> void:
	var ump: Object = _plugin(S_UMP)
	if ump == null or _form != Step.DONE or _form_uid < 0:
		form_dismissed.emit()
		return
	var uid: int = _form_uid
	_form = Step.PENDING
	_form_uid = -1
	ump.show(uid)


func can_request_ads() -> bool:
	var status: Status = consent_status()
	return status == Status.NOT_REQUIRED or status == Status.OBTAINED


func is_privacy_options_required() -> bool:
	var info: Object = _plugin(S_INFO)
	return info != null and int(info.get_privacy_options_requirement_status()) == PLUGIN_REQUIRED


func show_privacy_options() -> void:
	var ump: Object = _plugin(S_UMP)
	if ump == null:
		form_dismissed.emit()
		return
	_connect_signals()
	ump.show_privacy_options_form()


func _plugin(singleton: String) -> Object:
	var found: Variant = _lookup.call(singleton)
	return found as Object


func _connect_signals() -> void:
	if _connected:
		return
	_connected = true
	_on(S_INFO, "on_consent_info_updated_success", _on_info_done)
	_on(S_INFO, "on_consent_info_updated_failure", _on_info_failed)
	_on(S_UMP, "on_consent_form_load_success_listener", _on_form_loaded)
	_on(S_UMP, "on_consent_form_load_failure_listener", _on_form_load_failed)
	_on(S_UMP, "on_consent_form_dismissed", _on_form_dismissed)
	_on(S_UMP, "on_privacy_options_form_dismissed_listener", _on_options_dismissed)


func _on(singleton: String, signal_name: String, callable: Callable) -> void:
	var plugin: Object = _plugin(singleton)
	if plugin != null:
		plugin.connect(signal_name, callable, CONNECT_DEFERRED)


func _on_info_done() -> void:
	_info = Step.DONE


func _on_info_failed(_error: Dictionary = {}) -> void:
	_info = Step.FAILED


func _on_form_loaded(uid: int) -> void:
	_form_uid = uid
	_form = Step.DONE


func _on_form_load_failed(_error: Dictionary = {}) -> void:
	_form = Step.FAILED


func _on_form_dismissed(_uid: int, _error: Dictionary = {}) -> void:
	form_dismissed.emit()


func _on_options_dismissed(_error: Dictionary = {}) -> void:
	form_dismissed.emit()
