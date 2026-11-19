extends GdUnitTestSuite
## The AdService facade contract (plan "Interfaces with Phase 5", item 1; ADR 0039 section 1).
## Every signal, method and the fake_auto_close property is pinned, so a later row cannot drift.
## That the autoload exists, uses this script and has no class_name is test_autoloads.gd's job.

const SCRIPT_PATH: String = "res://game/ads/AdService.gd"

## Signals: name -> [arg name, arg type] pairs.
const SIGNALS: Dictionary = {
	"consent_finished": [["can_request_ads", TYPE_BOOL]],
	"entitlement_changed": [["has_remove_ads", TYPE_BOOL]],
	"banner_changed": [["height_dp", TYPE_INT]],
	"ad_opened": [["placement", TYPE_STRING_NAME]],
	"ad_closed": [["placement", TYPE_STRING_NAME]],
}
## Phase 5's methods, exactly the contract: name -> [arg [name, type] pairs, return type].
## A void return is TYPE_NIL. Never edit this for an internal method; use WIDGET_METHODS.
const METHODS: Dictionary = {
	"ensure_consent": [[], TYPE_BOOL],
	"is_privacy_options_required": [[], TYPE_BOOL],
	"show_privacy_options": [[], TYPE_NIL],
	"has_remove_ads": [[], TYPE_BOOL],
	"purchase_remove_ads": [[], TYPE_BOOL],
	"restore_purchases": [[], TYPE_BOOL],
	"banner_height_dp": [[], TYPE_INT],
	"maybe_show_interstitial": [[["placement", TYPE_STRING_NAME]], TYPE_BOOL],
	"note_match_completed": [[["play_seconds", TYPE_INT]], TYPE_NIL],
	"take_start_credits_bonus": [[], TYPE_INT],
}
## Internal methods Phase 6's widgets may call, pinned like METHODS: P403's rewarded API and
## banner show and hide, P406's Remove ads price text, and P409's MenuFlow wait.
## Phase 5 never calls these.
const WIDGET_METHODS: Dictionary = {
	"rewarded_ready": [[["placement", TYPE_STRING_NAME]], TYPE_BOOL],
	"show_rewarded": [[["placement", TYPE_STRING_NAME], ["on_reward", TYPE_CALLABLE]], TYPE_BOOL],
	"show_banner": [[], TYPE_NIL],
	"hide_banner": [[], TYPE_NIL],
	"banner_height_preview_dp": [[], TYPE_INT],
	"remove_ads_price_text": [[], TYPE_STRING],
	"grant_start_credits_bonus": [[["amount", TYPE_INT]], TYPE_BOOL],
	"pending_start_credits": [[], TYPE_INT],
	"consent_state": [[], TYPE_INT],
	"settle_fullscreen": [[], TYPE_NIL],
}

var _script: GDScript = load(SCRIPT_PATH) as GDScript


func test_the_signals_are_exactly_the_contract() -> void:
	var found: Dictionary = {}
	for entry: Dictionary in _script.get_script_signal_list():
		found[entry["name"]] = entry["args"]
	assert_array(found.keys()).contains_exactly_in_any_order(SIGNALS.keys())
	for signal_name: String in SIGNALS:
		var expected: Array = SIGNALS[signal_name]
		var args: Array = found.get(signal_name, [])
		assert_int(args.size()).override_failure_message(signal_name).is_equal(expected.size())
		for index: int in mini(args.size(), expected.size()):
			var arg: Dictionary = args[index]
			var label: String = "%s arg %d" % [signal_name, index]
			assert_str(arg["name"]).override_failure_message(label).is_equal(expected[index][0])
			assert_int(arg["type"]).override_failure_message(label).is_equal(expected[index][1])


func test_the_public_methods_are_exactly_the_contract_and_the_widget_allowlist() -> void:
	var found: Dictionary = {}
	for entry: Dictionary in _script.get_script_method_list():
		var method_name: String = entry["name"]
		if not method_name.begins_with("_"):
			found[method_name] = entry
	var every: Dictionary = METHODS.merged(WIDGET_METHODS)
	var allowed: Array = every.keys()
	assert_array(found.keys()).contains_exactly_in_any_order(allowed)
	for method_name: String in every:
		var entry: Dictionary = found.get(method_name, {})
		if entry.is_empty():
			continue
		var expected_args: Array = every[method_name][0]
		var args: Array = entry["args"]
		assert_int(args.size()).override_failure_message(method_name).is_equal(expected_args.size())
		for index: int in mini(args.size(), expected_args.size()):
			var arg: Dictionary = args[index]
			var label: String = "%s arg %d" % [method_name, index]
			assert_str(arg["name"]).override_failure_message(label).is_equal(
				expected_args[index][0]
			)
			assert_int(arg["type"]).override_failure_message(label).is_equal(
				expected_args[index][1]
			)
		var returns: Dictionary = entry["return"]
		var expected_return: int = every[method_name][1]
		assert_int(returns["type"]).override_failure_message(method_name).is_equal(expected_return)
		if expected_return == TYPE_NIL:
			# A typed void, not an untyped Variant return.
			var variant_flag: int = int(returns["usage"]) & PROPERTY_USAGE_NIL_IS_VARIANT
			assert_int(variant_flag).override_failure_message(method_name).is_equal(0)


func test_fake_auto_close_is_a_bool_property() -> void:
	var found: bool = false
	for entry: Dictionary in _script.get_script_property_list():
		if entry["name"] == "fake_auto_close":
			found = true
			assert_int(entry["type"]).is_equal(TYPE_BOOL)
	assert_bool(found).is_true()


func test_fake_auto_close_defaults_to_true_only_for_the_headless_display_server() -> void:
	assert_bool(_script.call("_default_auto_close", "headless")).is_true()
	assert_bool(_script.call("_default_auto_close", "Wayland")).is_false()
	assert_bool(_script.call("_default_auto_close", "")).is_false()
	var service: Node = auto_free(_script.new())
	assert_bool(service.fake_auto_close).is_equal(
		bool(_script.call("_default_auto_close", DisplayServer.get_name()))
	)
