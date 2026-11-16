extends GdUnitTestSuite
## P405: UmpPluginBackend against a fake Poing plugin object: the call order, the status mapping
## and the callbacks (ADR 0039 section 3). No real plugin is involved.

var _plugin: FakePoingPlugin
var _hash: String = ""
var _backend: UmpPluginBackend
var _dismissed: int = 0


func before_test() -> void:
	_plugin = FakePoingPlugin.new()
	_hash = ""
	_dismissed = 0
	_backend = UmpPluginBackend.new(_plugin.lookup, func() -> String: return _hash)
	_backend.form_dismissed.connect(func() -> void: _dismissed += 1)


func test_the_info_update_is_pending_until_the_plugin_answers() -> void:
	_backend.update_info(false)
	assert_int(_backend.info_state()).is_equal(ConsentBackend.Step.PENDING)
	var params: Dictionary = _plugin.args_of("update")[0]
	assert_bool(params["tag_for_under_age_of_consent"]).is_false()
	assert_object(params["consent_debug_settings"]).is_null()
	_plugin.on_consent_info_updated_success.emit()
	await get_tree().process_frame
	assert_int(_backend.info_state()).is_equal(ConsentBackend.Step.DONE)


func test_a_failed_update_is_failed_and_a_new_update_is_pending_again() -> void:
	_backend.update_info(false)
	_plugin.on_consent_info_updated_failure.emit({})
	await get_tree().process_frame
	assert_int(_backend.info_state()).is_equal(ConsentBackend.Step.FAILED)
	_backend.update_info(false)
	assert_int(_backend.info_state()).is_equal(ConsentBackend.Step.PENDING)
	assert_int(_plugin.count("update")).is_equal(2)


func test_the_debug_geography_needs_a_test_device_hash() -> void:
	_backend.update_info(true)
	assert_object(_plugin.args_of("update")[0]["consent_debug_settings"]).is_null()
	_hash = "abc"
	_backend.update_info(false)
	assert_object(_plugin.calls[1][1]["consent_debug_settings"]).is_null()
	_backend.update_info(true)
	var debug: Dictionary = _plugin.calls[2][1]["consent_debug_settings"]
	assert_int(debug["debug_geography"]).is_equal(UmpPluginBackend.GEOGRAPHY_EEA)
	assert_array(debug["test_device_hashed_ids"].values()).is_equal(["abc"])


func test_the_plugins_status_numbers_map_to_ours() -> void:
	var expected: Dictionary = {
		0: ConsentBackend.Status.UNKNOWN,
		1: ConsentBackend.Status.NOT_REQUIRED,
		2: ConsentBackend.Status.REQUIRED,
		3: ConsentBackend.Status.OBTAINED,
	}
	for plugin_value: int in expected:
		_plugin.consent_status = plugin_value
		assert_int(_backend.consent_status()).is_equal(expected[plugin_value])


func test_ads_may_be_requested_only_when_not_required_or_obtained() -> void:
	var allowed: Dictionary = {0: false, 1: true, 2: false, 3: true}
	for plugin_value: int in allowed:
		_plugin.consent_status = plugin_value
		assert_bool(_backend.can_request_ads()).is_equal(allowed[plugin_value])
	_plugin.consent_status = 2
	assert_bool(_backend.is_form_required()).is_true()


func test_a_form_is_loaded_then_shown_by_its_uid_and_dismissal_is_relayed() -> void:
	_backend.load_form()
	assert_int(_backend.form_state()).is_equal(ConsentBackend.Step.PENDING)
	_plugin.on_consent_form_load_success_listener.emit(7)
	await get_tree().process_frame
	assert_int(_backend.form_state()).is_equal(ConsentBackend.Step.DONE)
	_backend.show_form()
	assert_array(_plugin.names()).is_equal(["load_consent_form", "show"])
	assert_array(_plugin.args_of("show")).is_equal([7])
	assert_int(_dismissed).is_equal(0)
	_plugin.on_consent_form_dismissed.emit(7, {})
	await get_tree().process_frame
	assert_int(_dismissed).is_equal(1)


func test_a_failed_load_fails_and_showing_without_a_form_still_dismisses() -> void:
	_backend.load_form()
	_plugin.on_consent_form_load_failure_listener.emit({})
	await get_tree().process_frame
	assert_int(_backend.form_state()).is_equal(ConsentBackend.Step.FAILED)
	_backend.show_form()
	assert_int(_plugin.count("show")).is_equal(0)
	assert_int(_dismissed).is_equal(1)


func test_privacy_options_follow_the_requirement_status() -> void:
	assert_bool(_backend.is_privacy_options_required()).is_false()
	_plugin.privacy_options_status = 1
	assert_bool(_backend.is_privacy_options_required()).is_false()
	_plugin.privacy_options_status = 2
	assert_bool(_backend.is_privacy_options_required()).is_true()


func test_the_privacy_options_form_dismisses_when_the_plugin_says_so() -> void:
	_backend.show_privacy_options()
	assert_int(_plugin.count("show_privacy_options_form")).is_equal(1)
	assert_int(_dismissed).is_equal(0)
	_plugin.on_privacy_options_form_dismissed_listener.emit({})
	await get_tree().process_frame
	assert_int(_dismissed).is_equal(1)


func test_without_the_plugin_ads_stay_unrequested_and_forms_dismiss_at_once() -> void:
	var bare: UmpPluginBackend = UmpPluginBackend.new(
		func(_name: String) -> Object: return null, func() -> String: return ""
	)
	bare.form_dismissed.connect(func() -> void: _dismissed += 1)
	bare.update_info(false)
	bare.load_form()
	assert_int(bare.info_state()).is_equal(ConsentBackend.Step.FAILED)
	assert_int(bare.form_state()).is_equal(ConsentBackend.Step.FAILED)
	assert_bool(bare.can_request_ads()).is_false()
	assert_bool(bare.is_privacy_options_required()).is_false()
	bare.show_form()
	bare.show_privacy_options()
	assert_int(_dismissed).is_equal(2)
