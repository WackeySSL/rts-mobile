extends GdUnitTestSuite
## P404: AdService's privacy options, the debug geography, the preview default and the form
## placeholder on FakeUmp. The flow and the gate are test_ad_service_consent.gd.

const SCRIPT_PATH: String = AdServiceHarness.SCRIPT_PATH

var _h: AdServiceHarness
var _seen: Array[bool] = []


func before_test() -> void:
	_h = AdServiceHarness.new()
	_seen = []


func after_test() -> void:
	_h.dispose()
	UiScale.clear_override()


func _make() -> Node:
	var service: Node = auto_free(_h.make(false))
	service.consent_finished.connect(func(allowed: bool) -> void: _seen.append(allowed))
	return service


## A service whose consent is required and whose declines block, with a banner asked for.
func _blocking(service: Node) -> FakeUmp:
	var ump: FakeUmp = AdServiceHarness.ump(service)
	ump.consent_required = true
	ump.decline_limits_ads = false
	service.show_banner()
	return ump


func test_privacy_options_are_not_required_without_consent_rules_and_show_nothing() -> void:
	var service: Node = _make()
	assert_bool(service.is_privacy_options_required()).is_false()
	await service.ensure_consent()
	assert_bool(service.is_privacy_options_required()).is_false()
	var frame: int = Engine.get_process_frames()
	await service.show_privacy_options()
	assert_int(Engine.get_process_frames()).is_equal(frame)
	assert_int(AdServiceHarness.ump(service).forms_shown).is_equal(0)


func test_privacy_options_are_required_once_the_form_was_required() -> void:
	var service: Node = _make()
	AdServiceHarness.ump(service).consent_required = true
	assert_bool(service.is_privacy_options_required()).is_false()
	await service.ensure_consent()
	assert_bool(service.is_privacy_options_required()).is_true()


func test_withdrawing_in_the_privacy_form_closes_the_gate_and_hides_the_banner() -> void:
	var service: Node = _make()
	var ump: FakeUmp = _blocking(service)
	await service.ensure_consent()
	assert_int(service.banner_height_dp()).override_failure_message("banner before").is_greater(0)
	ump.obtained = false
	await service.show_privacy_options()
	assert_int(service.banner_height_dp()).override_failure_message("banner after").is_equal(0)
	assert_bool(service.rewarded_ready(&"x")).is_false()
	assert_array(_seen).contains_exactly([true, false])


func test_no_load_happens_after_a_withdrawal() -> void:
	var service: Node = _make()
	var ump: FakeUmp = _blocking(service)
	await service.ensure_consent()
	ump.obtained = false
	await service.show_privacy_options()
	var fake: FakeAdBackend = AdServiceHarness.fake(service)
	var before: int = fake.calls.size()
	service.note_match_completed(500)
	service.note_match_completed(500)
	service.note_match_completed(500)
	assert_bool(service.rewarded_ready(&"x")).is_false()
	assert_bool(await service.maybe_show_interstitial(&"post_match")).is_false()
	assert_array(fake.calls.slice(before)).override_failure_message("calls after").is_empty()


func test_privacy_options_can_turn_consent_on() -> void:
	var service: Node = _make()
	var ump: FakeUmp = _blocking(service)
	ump.obtained = false
	assert_bool(await service.ensure_consent()).is_false()
	assert_int(service.banner_height_dp()).is_equal(0)
	assert_int(AdServiceHarness.fake(service).initializations).is_equal(0)
	ump.obtained = true
	await service.show_privacy_options()
	assert_int(AdServiceHarness.fake(service).initializations).is_equal(1)
	assert_int(service.banner_height_dp()).is_equal(FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP)
	assert_array(_seen).contains_exactly([false, true])


func test_a_privacy_form_closed_unchanged_keeps_ads_and_announces_the_finish() -> void:
	var service: Node = _make()
	AdServiceHarness.ump(service).consent_required = true
	service.show_banner()
	await service.ensure_consent()
	await service.show_privacy_options()
	assert_int(service.banner_height_dp()).is_equal(FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP)
	assert_array(_seen).contains_exactly([true, true])


func test_the_privacy_form_waits_for_its_close_and_a_second_call_joins_it() -> void:
	var service: Node = _make()
	var ump: FakeUmp = AdServiceHarness.ump(service)
	ump.consent_required = true
	await service.ensure_consent()
	ump.form_never_closes = true
	var shown_before: int = ump.forms_shown
	var first: Array = AdServiceHarness.start(service.show_privacy_options)
	var second: Array = AdServiceHarness.start(service.show_privacy_options)
	_h.clock_ms = AdServiceHarness.consent_timeout_ms(service) * 10
	await AdServiceHarness.frames(3)
	assert_array(first).is_empty()
	assert_array(second).is_empty()
	assert_int(ump.forms_shown - shown_before).override_failure_message("privacy forms").is_equal(1)
	ump.dismiss(true)
	await AdServiceHarness.frames(2)
	assert_array(first).has_size(1)
	assert_array(second).has_size(1)
	assert_array(_seen).override_failure_message("one finish per flow").contains_exactly(
		[true, true]
	)


func test_the_debug_geography_asks_for_the_eea_form_only_when_set() -> void:
	var plain: Node = _make()
	await plain.ensure_consent()
	assert_bool(AdServiceHarness.ump(plain).last_debug_eea).is_false()
	assert_int(AdServiceHarness.ump(plain).forms_shown).is_equal(0)
	var eea: Node = _make()
	eea.debug_geography_eea = true
	await eea.ensure_consent()
	# Tests run in a debug build, where the flag is honoured.
	assert_bool(AdServiceHarness.ump(eea).last_debug_eea).is_equal(OS.is_debug_build())
	assert_bool(eea.is_privacy_options_required()).is_equal(OS.is_debug_build())


func test_consent_is_required_by_default_only_where_the_placeholders_wait_for_buttons() -> void:
	var script: GDScript = load(SCRIPT_PATH) as GDScript
	assert_bool(script.call("_default_auto_close", "headless")).is_true()
	var required: FakeUmp = script.call("_make_consent", true) as FakeUmp
	var not_required: FakeUmp = script.call("_make_consent", false) as FakeUmp
	assert_bool(required.consent_required).is_true()
	assert_bool(not_required.consent_required).is_false()


func test_without_auto_close_the_form_placeholder_waits_for_its_buttons() -> void:
	UiScale.set_override(
		UiMetrics.create("Android", 480, 1.0, 1.0, Vector2i(1280, 720), Rect2i(60, 30, 1160, 660))
	)
	var service: Node = _make()
	service.fake_auto_close = false
	add_child(service)
	AdServiceHarness.ump(service).consent_required = true
	AdServiceHarness.ump(service).decline_limits_ads = false
	var out: Array = AdServiceHarness.start(service.ensure_consent)
	await AdServiceHarness.frames(2)
	assert_array(out).is_empty()
	var form: Node = service.get_node("FakeConsentForm")
	assert_object(form.find_child("Close", true, false)).is_null()
	(form.find_child("Decline", true, false) as Button).pressed.emit()
	await AdServiceHarness.frames(2)
	assert_array(out).contains_exactly([false])
	assert_bool(service.has_node("FakeConsentForm")).is_false()


func test_the_privacy_placeholder_has_a_close_that_changes_nothing() -> void:
	var service: Node = _make()
	add_child(service)
	AdServiceHarness.ump(service).consent_required = true
	service.show_banner()
	await service.ensure_consent()
	service.fake_auto_close = false
	var out: Array = AdServiceHarness.start(service.show_privacy_options)
	await AdServiceHarness.frames(2)
	var form: Node = service.get_node("FakeConsentForm")
	(form.find_child("Close", true, false) as Button).pressed.emit()
	await AdServiceHarness.frames(2)
	assert_array(out).has_size(1)
	assert_int(service.banner_height_dp()).is_equal(FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP)
	assert_array(_seen).contains_exactly([true, true])


func test_a_cut_privacy_run_keeps_the_gate_and_the_next_resume_re_reads_consent() -> void:
	var service: Node = _make()
	var ump: FakeUmp = AdServiceHarness.ump(service)
	ump.consent_required = true
	await service.ensure_consent()
	assert_array(_seen).is_equal([true])
	ump.show_never_shows = true
	var call: Array = AdServiceHarness.start(
		func() -> bool:
			await service.show_privacy_options()
			return true
	)
	await AdServiceHarness.frames(4)
	assert_array(call).is_empty()
	_h.clock_ms = AdServiceHarness.consent_timeout_ms(service)
	await AdServiceHarness.frames(4)
	assert_array(call).is_equal([true])
	assert_array(_seen).is_equal([true])  # Nothing announced by the cut; the gate is as it was.
	var updates: int = ump.info_updates
	service.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await AdServiceHarness.frames(4)
	assert_int(ump.info_updates).is_equal(updates + 1)  # Re-read on resume.
	service.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await AdServiceHarness.frames(4)
	assert_int(ump.info_updates).is_equal(updates + 1)  # Once: the mark was cleared.


func test_focus_out_and_pause_reach_the_consent_backend() -> void:
	var service: Node = _make()
	var ump: FakeUmp = AdServiceHarness.ump(service)
	service.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	service.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_int(ump.app_pauses).is_equal(2)
