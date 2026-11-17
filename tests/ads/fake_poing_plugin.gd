class_name FakePoingPlugin
extends RefCounted
## A test double for one of the Poing plugin's native singletons (v5.1.0): the same method and
## signal names the vendored GDScript wrappers use and no behaviour. Like the real ones, each
## singleton counts its own uids from 1. All of a `FakePoingSet`'s fakes append to one shared log.

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
signal on_ad_loaded(uid: int)
signal on_ad_failed_to_load(uid: int, error: Dictionary)
signal on_consent_info_updated_success
signal on_consent_info_updated_failure(error: Dictionary)
signal on_consent_form_load_success_listener(uid: int)
signal on_consent_form_load_failure_listener(error: Dictionary)
signal on_consent_form_dismissed(uid: int, error: Dictionary)
signal on_privacy_options_form_dismissed_listener(error: Dictionary)

## Every call as "name", its arguments, then the singleton's name; shared with the set.
var calls: Array[Array] = []
var singleton: String = ""
var consent_status: int = 0
var privacy_options_status: int = 0
var banner_size: Dictionary = {"width": 360, "height": 56}
var _next_uid: int = 0


func _init(singleton_name: String = "", shared_calls: Array[Array] = []) -> void:
	singleton = singleton_name
	calls = shared_calls


func initialize() -> void:
	_log(["initialize"])


func set_request_configuration(config: Dictionary, test_devices: Array) -> void:
	_log(["set_request_configuration", config, test_devices])


func create(view: Variant = null) -> int:
	_next_uid += 1
	_log(["create", view, _next_uid])
	return _next_uid


func load(unit: String, request: Dictionary, keywords: Array, uid: int) -> void:
	_log(["load", unit, request, keywords, uid])


func load_ad(uid: int, request: Dictionary, keywords: Array) -> void:
	_log(["load_ad", uid, request, keywords])


func show(uid: int) -> void:
	_log(["show", uid])


func hide(uid: int) -> void:
	_log(["hide", uid])


func destroy(uid: int) -> void:
	_log(["destroy", uid])


# gdlint: ignore=function-name
func getCurrentOrientationAnchoredAdaptiveBannerAdSize(width: int) -> Dictionary:
	_log(["adaptive_size", width])
	return banner_size


func update(params: Dictionary) -> void:
	_log(["update", params])


func get_consent_status() -> int:
	return consent_status


func get_privacy_options_requirement_status() -> int:
	return privacy_options_status


func load_consent_form() -> void:
	_log(["load_consent_form"])


func show_privacy_options_form() -> void:
	_log(["show_privacy_options_form"])


func _log(entry: Array) -> void:
	entry.append(singleton)
	calls.append(entry)
