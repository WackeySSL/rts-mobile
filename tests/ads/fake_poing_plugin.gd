class_name FakePoingPlugin
extends RefCounted
## A test double for the Poing plugin's native singletons (v5.1.0): the same method and signal names
## the vendored GDScript wrappers use, a call log, and no behaviour. One object stands in for every
## singleton (AdMobBackend and UmpPluginBackend look each one up by name and get this).

signal on_initialization_complete(status: Dictionary)
signal on_interstitial_ad_loaded(uid: int)
signal on_interstitial_ad_failed_to_load(uid: int, error: Dictionary)
signal on_interstitial_ad_showed_full_screen_content(uid: int)
signal on_interstitial_ad_dismissed_full_screen_content(uid: int)
signal on_interstitial_ad_failed_to_show_full_screen_content(uid: int, error: Dictionary)
signal on_rewarded_ad_loaded(uid: int)
signal on_rewarded_ad_failed_to_load(uid: int, error: Dictionary)
signal on_rewarded_ad_showed_full_screen_content(uid: int)
signal on_rewarded_ad_dismissed_full_screen_content(uid: int)
signal on_rewarded_ad_failed_to_show_full_screen_content(uid: int, error: Dictionary)
signal on_rewarded_ad_user_earned_reward(uid: int, item: Dictionary)
signal on_ad_failed_to_load(uid: int, error: Dictionary)
signal on_consent_info_updated_success
signal on_consent_info_updated_failure(error: Dictionary)
signal on_consent_form_load_success_listener(uid: int)
signal on_consent_form_load_failure_listener(error: Dictionary)
signal on_consent_form_dismissed(uid: int, error: Dictionary)
signal on_privacy_options_form_dismissed_listener(error: Dictionary)

## Every call as "name" plus its arguments, in order.
var calls: Array[Array] = []
var consent_status: int = 0
var privacy_options_status: int = 0
var banner_size: Dictionary = {"width": 360, "height": 56}
var _next_uid: int = 100


func names() -> Array[String]:
	var out: Array[String] = []
	for entry: Array in calls:
		out.append(String(entry[0]))
	return out


func args_of(call_name: String) -> Array:
	for entry: Array in calls:
		if entry[0] == call_name:
			return entry.slice(1)
	return []


func count(call_name: String) -> int:
	return names().count(call_name)


func lookup(_singleton: String) -> Object:
	return self


func initialize() -> void:
	calls.append(["initialize"])


func set_request_configuration(config: Dictionary, test_devices: Array) -> void:
	calls.append(["set_request_configuration", config, test_devices])


func create(view: Variant = null) -> int:
	_next_uid += 1
	calls.append(["create", view, _next_uid])
	return _next_uid


func load(unit: String, request: Dictionary, keywords: Array, uid: int) -> void:
	calls.append(["load", unit, request, keywords, uid])


func load_ad(uid: int, request: Dictionary, keywords: Array) -> void:
	calls.append(["load_ad", uid, request, keywords])


func show(uid: int) -> void:
	calls.append(["show", uid])


func hide(uid: int) -> void:
	calls.append(["hide", uid])


func destroy(uid: int) -> void:
	calls.append(["destroy", uid])


# gdlint: ignore=function-name
func getCurrentOrientationAnchoredAdaptiveBannerAdSize(width: int) -> Dictionary:
	calls.append(["adaptive_size", width])
	return banner_size


func update(params: Dictionary) -> void:
	calls.append(["update", params])


func get_consent_status() -> int:
	return consent_status


func get_privacy_options_requirement_status() -> int:
	return privacy_options_status


func load_consent_form() -> void:
	calls.append(["load_consent_form"])


func show_privacy_options_form() -> void:
	calls.append(["show_privacy_options_form"])
