extends GdUnitTestSuite
## P404: AdService's privacy options, the debug geography and the form placeholder on FakeUmp.
## The flow and the gate are test_ad_service_consent.gd.

const WINDOW: Vector2i = Vector2i(1280, 720)
const SAFE: Rect2i = Rect2i(60, 30, 1160, 660)

var _h: AdServiceHarness = AdServiceHarness.new()
var _seen: Array[bool] = []


func before_test() -> void:
	_h = AdServiceHarness.new()
	_seen = []


func after_test() -> void:
	UiScale.clear_override()


func _make() -> Node:
	var service: Node = auto_free(_h.make(false))
	service.consent_finished.connect(func(allowed: bool) -> void: _seen.append(allowed))
	return service


static func _ump(service: Node) -> FakeUmp:
	return service._consent as FakeUmp


func _timeout(service: Node) -> int:
	return service._settings.consent_timeout_ms


# --- privacy options ------------------------------------------------------------------------


func test_privacy_options_are_not_required_without_consent_rules_and_show_nothing() -> void:
	var service: Node = _make()
	assert_bool(service.is_privacy_options_required()).is_false()
	await service.ensure_consent()
	assert_bool(service.is_privacy_options_required()).is_false()
	var frame: int = Engine.get_process_frames()
	await service.show_privacy_options()
	assert_int(Engine.get_process_frames()).is_equal(frame)
	assert_int(_ump(service).forms_shown).is_equal(0)


func test_privacy_options_are_required_once_the_form_was_required() -> void:
	var service: Node = _make()
	_ump(service).consent_required = true
	assert_bool(service.is_privacy_options_required()).is_false()
	await service.ensure_consent()
	assert_bool(service.is_privacy_options_required()).is_true()


func test_withdrawing_in_the_privacy_form_closes_the_gate_and_hides_the_banner() -> void:
	var service: Node = _make()
	_ump(service).consent_required = true
	service.show_banner()
	await service.ensure_consent()
	assert_int(service.banner_height_dp()).is_greater(0)
	_ump(service).obtained = false
	await service.show_privacy_options()
	assert_bool(service._can_request_ads).is_false()
	assert_int(service.banner_height_dp()).is_equal(0)
	assert_array(_seen).contains_exactly([true, false])


func test_the_privacy_form_waits_for_its_close() -> void:
	var service: Node = _make()
	_ump(service).consent_required = true
	await service.ensure_consent()
	_ump(service).form_never_closes = true
	var out: Array = AdServiceHarness.start(service.show_privacy_options)
	_h.clock_ms = _timeout(service) * 10
	await AdServiceHarness.frames(3)
	assert_array(out).is_empty()
	_ump(service).dismiss(true)
	await AdServiceHarness.frames(2)
	assert_array(out).has_size(1)
	assert_array(_seen).contains_exactly([true])


# --- debug geography ------------------------------------------------------------------------


func test_the_debug_geography_asks_for_the_eea_form_only_when_set() -> void:
	var plain: Node = _make()
	await plain.ensure_consent()
	assert_bool(_ump(plain).last_debug_eea).is_false()
	assert_int(_ump(plain).forms_shown).is_equal(0)
	var eea: Node = _make()
	eea.debug_geography_eea = true
	await eea.ensure_consent()
	assert_bool(_ump(eea).last_debug_eea).is_true()
	assert_int(_ump(eea).forms_shown).is_equal(1)
	assert_bool(eea.is_privacy_options_required()).is_true()


func test_the_debug_geography_is_allowed_only_in_a_debug_or_fake_build() -> void:
	var script: GDScript = load(AdServiceHarness.SCRIPT_PATH) as GDScript
	assert_bool(script.call("_debug_geography_allowed", true, false)).is_true()
	assert_bool(script.call("_debug_geography_allowed", false, true)).is_true()
	assert_bool(script.call("_debug_geography_allowed", false, false)).is_false()


# --- the placeholder ------------------------------------------------------------------------


func test_without_auto_close_the_form_placeholder_waits_for_its_buttons() -> void:
	UiScale.set_override(UiMetrics.create("Android", 480, 1.0, 1.0, WINDOW, SAFE))
	var service: Node = _make()
	service.fake_auto_close = false
	add_child(service)
	_ump(service).consent_required = true
	var out: Array = AdServiceHarness.start(service.ensure_consent)
	await AdServiceHarness.frames(2)
	assert_array(out).is_empty()
	var form: Node = service.get_node("FakeConsentForm")
	for caption: String in ["Accept", "Decline"]:
		var button: Button = form.find_child(caption, true, false) as Button
		assert_float(button.custom_minimum_size.x).is_greater_equal(UiScale.dp(48))
		assert_float(button.custom_minimum_size.y).is_greater_equal(UiScale.dp(48))
	assert_object(form.find_child("Close", true, false)).is_null()
	(form.find_child("Decline", true, false) as Button).pressed.emit()
	await AdServiceHarness.frames(2)
	assert_array(out).contains_exactly([false])
	assert_bool(service.has_node("FakeConsentForm")).is_false()


func test_the_privacy_placeholder_has_a_close_that_changes_nothing() -> void:
	var service: Node = _make()
	add_child(service)
	_ump(service).consent_required = true
	await service.ensure_consent()
	service.fake_auto_close = false
	var out: Array = AdServiceHarness.start(service.show_privacy_options)
	await AdServiceHarness.frames(2)
	var close: Button = (
		service.get_node("FakeConsentForm").find_child("Close", true, false) as Button
	)
	assert_float(close.custom_minimum_size.y).is_greater_equal(UiScale.dp(48))
	close.pressed.emit()
	await AdServiceHarness.frames(2)
	assert_array(out).has_size(1)
	assert_bool(service._can_request_ads).is_true()
	assert_array(_seen).contains_exactly([true])
