extends GdUnitTestSuite
## P404: the consent classes without AdService: FakeUmp's model of UMP's status, ConsentGate's
## wait for the dismissal (every outcome ends it) and ConsentFlow's debug geography rule.

var _now: Callable = func() -> int: return 0


func _gate(ump: FakeUmp, debug_eea: bool = false) -> ConsentGate:
	return ConsentGate.new(ump, _now, 1000, debug_eea)


func _flow(ump: FakeUmp, is_debug: bool) -> ConsentFlow:
	return ConsentFlow.new(ump, func() -> bool: return is_debug)


# --- the status model -----------------------------------------------------------------------


func test_the_status_moves_unknown_to_not_required_without_a_form() -> void:
	var ump: FakeUmp = FakeUmp.new()
	assert_int(ump.consent_status()).is_equal(ConsentBackend.Status.UNKNOWN)
	assert_bool(await _gate(ump).execute()).is_true()
	assert_int(ump.consent_status()).is_equal(ConsentBackend.Status.NOT_REQUIRED)
	assert_int(ump.forms_shown).is_equal(0)
	assert_bool(ump.is_privacy_options_required()).is_false()


func test_a_required_status_shows_the_form_and_ends_obtained() -> void:
	var ump: FakeUmp = FakeUmp.new()
	ump.consent_required = true
	assert_bool(await _gate(ump).execute()).is_true()
	assert_int(ump.consent_status()).is_equal(ConsentBackend.Status.OBTAINED)
	assert_int(ump.forms_shown).is_equal(1)


func test_a_returning_eea_user_sees_no_form_but_keeps_the_privacy_options() -> void:
	var ump: FakeUmp = FakeUmp.new()
	ump.consent_required = true
	await _gate(ump).execute()
	assert_bool(await _gate(ump).execute()).is_true()
	assert_int(ump.forms_shown).override_failure_message("second launch").is_equal(1)
	assert_int(ump.consent_status()).is_equal(ConsentBackend.Status.OBTAINED)
	assert_bool(ump.is_privacy_options_required()).is_true()


func test_a_decline_ends_obtained_unless_the_script_blocks() -> void:
	var limits: FakeUmp = FakeUmp.new()
	limits.consent_required = true
	limits.obtained = false
	assert_bool(await _gate(limits).execute()).is_true()
	assert_int(limits.consent_status()).is_equal(ConsentBackend.Status.OBTAINED)
	var blocks: FakeUmp = FakeUmp.new()
	blocks.consent_required = true
	blocks.obtained = false
	blocks.decline_limits_ads = false
	assert_bool(await _gate(blocks).execute()).is_false()
	assert_int(blocks.consent_status()).is_equal(ConsentBackend.Status.REQUIRED)


func test_a_form_is_not_shown_twice_at_once() -> void:
	var ump: FakeUmp = FakeUmp.new()
	ump.form_never_closes = true
	ump.show_form()
	ump.show_form()
	ump.show_privacy_options()
	assert_int(ump.forms_shown).is_equal(1)


# --- every outcome ends the wait ------------------------------------------------------------


func test_a_show_that_fails_still_ends_the_wait() -> void:
	var ump: FakeUmp = FakeUmp.new()
	ump.consent_required = true
	ump.show_fails = true
	var frame: int = Engine.get_process_frames()
	assert_bool(await _gate(ump).execute()).override_failure_message("consent form").is_false()
	await _gate(ump).run_privacy_options()
	assert_int(Engine.get_process_frames()).override_failure_message("no hang").is_equal(frame)


func test_the_inert_base_backend_ends_every_wait_and_requests_no_ads() -> void:
	var base: ConsentBackend = ConsentBackend.new()
	assert_bool(await ConsentGate.new(base, _now, 1000, false).execute()).is_false()
	await ConsentGate.new(base, _now, 1000, false).run_privacy_options()
	assert_bool(base.can_request_ads()).is_false()


# --- the debug geography --------------------------------------------------------------------


func test_the_debug_geography_is_never_passed_in_a_non_debug_build() -> void:
	var ump: FakeUmp = FakeUmp.new()
	await _flow(ump, false).run_consent(_now, 1000, true)
	assert_bool(ump.last_debug_eea).is_false()
	assert_int(ump.forms_shown).is_equal(0)


func test_the_debug_geography_is_passed_in_a_debug_build_and_the_fake_honours_it() -> void:
	var ump: FakeUmp = FakeUmp.new()
	await _flow(ump, true).run_consent(_now, 1000, true)
	assert_bool(ump.last_debug_eea).is_true()
	assert_int(ump.forms_shown).is_equal(1)
	var off: FakeUmp = FakeUmp.new()
	await _flow(off, true).run_consent(_now, 1000, false)
	assert_bool(off.last_debug_eea).is_false()


func test_the_flow_wires_the_fake_placeholder() -> void:
	var ump: FakeUmp = FakeUmp.new()
	var host: Node = auto_free(Node.new())
	_flow(ump, true).configure_fake(false, host)
	assert_bool(ump.auto_close).is_false()
	assert_bool(ump.draw_placeholders).is_true()
	assert_object(ump.host).is_same(host)
