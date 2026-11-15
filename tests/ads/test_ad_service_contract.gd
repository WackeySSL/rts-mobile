extends GdUnitTestSuite
## The AdService facade contract (plan "Interfaces with Phase 5", item 1; ADR 0039 section 1).
## Every signal, method and the fake_auto_close property is pinned, so a later row cannot drift.

const SCRIPT_PATH: String = "res://game/ads/AdService.gd"

## Signals: name -> [arg name, arg type] pairs.
const SIGNALS: Dictionary = {
	"consent_finished": [["can_request_ads", TYPE_BOOL]],
	"entitlement_changed": [["has_remove_ads", TYPE_BOOL]],
	"banner_changed": [["height_dp", TYPE_INT]],
	"ad_opened": [["placement", TYPE_STRING_NAME]],
	"ad_closed": [["placement", TYPE_STRING_NAME]],
}
## Methods: name -> [arg types, return type]. A void return is TYPE_NIL.
const METHODS: Dictionary = {
	"ensure_consent": [[], TYPE_BOOL],
	"is_privacy_options_required": [[], TYPE_BOOL],
	"show_privacy_options": [[], TYPE_NIL],
	"has_remove_ads": [[], TYPE_BOOL],
	"purchase_remove_ads": [[], TYPE_BOOL],
	"restore_purchases": [[], TYPE_BOOL],
	"banner_height_dp": [[], TYPE_INT],
	"maybe_show_interstitial": [[TYPE_STRING_NAME], TYPE_BOOL],
	"note_match_completed": [[TYPE_INT], TYPE_NIL],
	"take_start_credits_bonus": [[], TYPE_INT],
}

var _script: GDScript = load(SCRIPT_PATH)


func test_script_has_no_class_name() -> void:
	assert_str(String(_script.get_global_name())).is_empty()


func test_the_signals_are_exactly_the_contract() -> void:
	var found: Dictionary = {}
	for entry: Dictionary in _script.get_script_signal_list():
		found[entry["name"]] = entry["args"]
	assert_array(found.keys()).contains_exactly_in_any_order(SIGNALS.keys())
	for signal_name: String in SIGNALS:
		var expected: Array = SIGNALS[signal_name]
		var args: Array = found[signal_name]
		assert_int(args.size()).override_failure_message(signal_name).is_equal(expected.size())
		for index: int in mini(args.size(), expected.size()):
			var arg: Dictionary = args[index]
			assert_str(arg["name"]).is_equal(expected[index][0])
			assert_int(arg["type"]).override_failure_message(signal_name).is_equal(
				expected[index][1]
			)


func test_the_public_methods_are_exactly_the_contract() -> void:
	var found: Dictionary = {}
	for entry: Dictionary in _script.get_script_method_list():
		var method_name: String = entry["name"]
		if not method_name.begins_with("_"):
			found[method_name] = entry
	assert_array(found.keys()).contains_exactly_in_any_order(METHODS.keys())
	for method_name: String in METHODS:
		var entry: Dictionary = found[method_name]
		var arg_types: Array = METHODS[method_name][0]
		var args: Array = entry["args"]
		assert_int(args.size()).override_failure_message(method_name).is_equal(arg_types.size())
		for index: int in mini(args.size(), arg_types.size()):
			var arg: Dictionary = args[index]
			assert_int(arg["type"]).override_failure_message(method_name).is_equal(arg_types[index])
		var returns: Dictionary = entry["return"]
		assert_int(returns["type"]).override_failure_message(method_name).is_equal(
			METHODS[method_name][1]
		)


func test_fake_auto_close_is_a_bool_property_defaulting_by_display_server() -> void:
	var found: bool = false
	for entry: Dictionary in _script.get_script_property_list():
		if entry["name"] == "fake_auto_close":
			found = true
			assert_int(entry["type"]).is_equal(TYPE_BOOL)
	assert_bool(found).is_true()
	var service: Node = auto_free(_script.new())
	assert_bool(service.fake_auto_close).is_equal(DisplayServer.get_name() == "headless")


func test_the_autoload_is_the_contract_script() -> void:
	var node: Node = get_tree().root.get_node_or_null("AdService")
	assert_object(node).is_not_null()
	assert_str(node.get_script().resource_path).is_equal(SCRIPT_PATH)
