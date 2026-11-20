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


# --- the privacy options deadline -------------------------------------------------------------


func _privacy_ump() -> FakeUmp:
	var ump: FakeUmp = FakeUmp.new()
	ump.consent_required = true
	ump.update_info(false)
	return ump


func _tick() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func test_privacy_options_that_never_show_return_at_the_timeout_and_free_the_flow() -> void:
	var ump: FakeUmp = _privacy_ump()
	ump.show_never_shows = true
	var clock: Array[int] = [0]
	var now: Callable = func() -> int: return clock[0]
	var flow: ConsentFlow = _flow(ump, false)
	var settled: Array[bool] = []
	flow.settled.connect(func(can: bool) -> void: settled.append(can))
	var done: Array[bool] = []
	var run: Callable = func() -> void:
		await flow.run_privacy_options(now, 1000)
		done.append(true)
	run.call()
	clock[0] = 999
	await _tick()
	await _tick()
	assert_array(done).is_empty()  # One ms short: still waiting.
	assert_array(settled).is_empty()
	clock[0] = 1000
	await _tick()
	await _tick()
	assert_array(done).is_equal([true])
	assert_array(settled).is_empty()  # A cut announces nothing: fail closed.
	assert_bool(flow.needs_recheck).is_true()  # Cut: fail closed, the next consent run re-reads.
	# A later consent run does not await the dead flow.
	ump.show_never_shows = false
	ump.show_held_form()  # The late show of the dead flow comes and closes by itself.
	assert_bool(await flow.run_consent(now, 1000, false)).is_true()


func test_a_privacy_options_form_that_showed_is_waited_for_past_the_timeout() -> void:
	var ump: FakeUmp = _privacy_ump()
	ump.form_never_closes = true
	var clock: Array[int] = [0]
	var now: Callable = func() -> int: return clock[0]
	var flow: ConsentFlow = _flow(ump, false)
	var done: Array[bool] = []
	var run: Callable = func() -> void:
		await flow.run_privacy_options(now, 1000)
		done.append(true)
	run.call()
	clock[0] = 100000  # Far past the timeout.
	await _tick()
	await _tick()
	assert_int(ump.forms_shown).is_equal(1)
	assert_array(done).is_empty()  # Shown: no timeout.
	ump.dismiss(true)
	assert_array(done).is_equal([true])


func test_a_privacy_options_show_that_comes_late_is_ignored_without_a_second_finish() -> void:
	var ump: FakeUmp = _privacy_ump()
	ump.show_never_shows = true
	ump.form_never_closes = true
	var clock: Array[int] = [0]
	var now: Callable = func() -> int: return clock[0]
	var flow: ConsentFlow = _flow(ump, false)
	var settled: Array[bool] = []
	flow.settled.connect(func(can: bool) -> void: settled.append(can))
	var run: Callable = func() -> void: await flow.run_privacy_options(now, 1000)
	run.call()
	clock[0] = 1000
	await _tick()
	await _tick()
	assert_array(settled).is_empty()  # A cut announces nothing.
	ump.show_held_form()  # The late show: nobody waits for it.
	assert_int(ump.forms_shown).is_equal(1)
	ump.dismiss(true)  # The late close.
	assert_array(settled).is_empty()  # The late close finishes nothing.
	# The flow works again: a new run shows and finishes normally.
	ump.show_never_shows = false
	ump.form_never_closes = false
	await flow.run_privacy_options(now, 1000)
	assert_int(ump.forms_shown).is_equal(2)
	assert_array(settled).has_size(1)


func test_a_gate_that_is_cut_tells_the_backend_and_lets_go_of_it() -> void:
	var ump: FakeUmp = _privacy_ump()
	ump.show_never_shows = true
	var clock: Array[int] = [0]
	var gate: ConsentGate = ConsentGate.new(ump, func() -> int: return clock[0], 1000, false)
	var results: Array[bool] = []
	var run: Callable = func() -> void: results.append(await gate.run_privacy_options())
	run.call()
	clock[0] = 1000
	await _tick()
	await _tick()
	assert_array(results).is_equal([false])  # Cut.
	assert_int(ump.form_dismissed.get_connections().size()).is_equal(0)
	assert_int(ump.form_shown.get_connections().size()).is_equal(0)
	ump.show_held_form()  # The show was recalled by the gate but the SDK opens it late anyway.
	assert_int(ump.forms_shown).is_equal(1)


func test_a_failed_privacy_options_show_is_not_a_cut_and_lets_go() -> void:
	var ump: FakeUmp = _privacy_ump()
	ump.show_fails = true
	var gate: ConsentGate = ConsentGate.new(ump, _now, 1000, false)
	assert_bool(await gate.run_privacy_options()).is_true()
	assert_int(ump.form_dismissed.get_connections().size()).is_equal(0)
	assert_int(ump.form_shown.get_connections().size()).is_equal(0)


func test_a_late_open_form_stays_open_and_a_new_run_neither_takes_its_close_nor_hangs() -> void:
	var ump: FakeUmp = _privacy_ump()
	ump.show_never_shows = true
	ump.form_never_closes = true
	var clock: Array[int] = [0]
	var now: Callable = func() -> int: return clock[0]
	var flow: ConsentFlow = _flow(ump, false)
	var run: Callable = func() -> void: await flow.run_privacy_options(now, 1000)
	run.call()
	clock[0] = 1000
	await _tick()
	await _tick()
	ump.show_held_form()  # Opens late and stays open.
	assert_int(ump.forms_shown).is_equal(1)
	ump.show_never_shows = false
	var second: Array[bool] = []
	var again: Callable = func() -> void:
		await flow.run_privacy_options(now, 1000)
		second.append(true)
	again.call()  # The show is refused (one form at a time): the run ends, it does not hang.
	assert_array(second).is_equal([true])
	assert_int(ump.forms_shown).is_equal(1)
	assert_bool(flow.needs_recheck).is_true()  # Only a consent run clears the mark.
	ump.dismiss(true)  # The old form's close reaches nobody.
	assert_array(second).has_size(1)


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


func test_a_fake_form_without_a_host_to_draw_on_answers_as_scripted() -> void:
	var ump: FakeUmp = FakeUmp.new()
	ump.consent_required = true
	ump.auto_close = false
	ump.draw_placeholders = true
	ump.obtained = true
	var dismissed: Array[bool] = []
	ump.form_dismissed.connect(func() -> void: dismissed.append(true))
	ump.update_info(false)
	ump.show_form()
	assert_array(dismissed).contains_exactly([true])
	assert_bool(ump.can_request_ads()).is_true()
