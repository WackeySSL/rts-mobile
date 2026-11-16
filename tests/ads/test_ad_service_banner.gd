extends GdUnitTestSuite
## P405: AdService and the banner's lifecycle on the backend: the height re-read when the backend
## says it changed, the view destroyed (not just hidden) for Remove ads and lost consent, and the
## consent gate the backend asks before every load (ADR 0039 sections 2, 3, 8).


## A fake that counts destroy_banner (which the fake otherwise folds into hide_banner).
class SpyBackend:
	extends FakeAdBackend
	var destroyed: int = 0

	func destroy_banner() -> void:
		destroyed += 1
		super()


var _harness: AdServiceHarness


func before_test() -> void:
	_harness = AdServiceHarness.new()


func after_test() -> void:
	_harness.dispose()


func _service() -> Node:
	var service: Node = auto_free(_harness.make())
	var spy: SpyBackend = SpyBackend.new()
	service._backend = spy
	spy.initialize()
	service._initialised = true
	return service


func _spy(service: Node) -> SpyBackend:
	return service._backend as SpyBackend


func test_the_height_is_read_again_when_the_backend_says_it_changed() -> void:
	var service: Node = _service()
	var spy: SpyBackend = _spy(service)
	spy.banner_height_changed.connect(service._refresh_banner)
	spy.fill = false
	var heights: Array[int] = []
	service.banner_changed.connect(func(height: int) -> void: heights.append(height))
	service.show_banner()
	assert_int(service.banner_height_dp()).is_equal(0)
	spy.fill = true
	spy.notify_banner()
	assert_int(service.banner_height_dp()).is_equal(FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP)
	assert_array(heights).contains_exactly([FakeAdBackend.DEFAULT_BANNER_HEIGHT_DP])
	spy.fill = false
	spy.notify_banner()
	assert_int(service.banner_height_dp()).is_equal(0)


func test_the_service_listens_to_the_backends_height_signal() -> void:
	var service: Node = auto_free(_harness.make())
	(
		assert_bool(service._backend.banner_height_changed.is_connected(service._refresh_banner))
		. is_true()
	)


func test_remove_ads_destroys_the_banner_view() -> void:
	var service: Node = _service()
	service.show_banner()
	AdServiceHarness.billing(service).next_outcome = BillingBackend.Outcome.PURCHASED
	await service.purchase_remove_ads()
	assert_int(_spy(service).destroyed).is_equal(1)
	assert_int(_spy(service).calls.count("hide_banner")).is_equal(1)


func test_remove_ads_destroys_a_banner_that_was_only_hidden() -> void:
	var service: Node = _service()
	service.show_banner()
	service.hide_banner()
	await get_tree().process_frame
	assert_int(_spy(service).destroyed).is_equal(0)
	AdServiceHarness.billing(service).next_outcome = BillingBackend.Outcome.PURCHASED
	await service.purchase_remove_ads()
	assert_int(_spy(service).destroyed).is_equal(1)


func test_losing_consent_destroys_the_banner_view() -> void:
	var service: Node = _service()
	service.show_banner()
	service._set_can_request(false)
	assert_int(_spy(service).destroyed).is_equal(1)
	assert_int(service.banner_height_dp()).is_equal(0)


func test_a_banner_released_by_its_menu_is_only_hidden() -> void:
	var service: Node = _service()
	service.show_banner()
	service.hide_banner()
	await get_tree().process_frame
	assert_int(_spy(service).destroyed).is_equal(0)
	assert_int(_spy(service).calls.count("hide_banner")).is_equal(1)


func test_the_backends_gate_follows_the_consent_answer() -> void:
	var service: Node = auto_free(_harness.make(false))
	var backend: AdBackend = service._backend
	assert_bool(bool(backend.can_request_ads.call())).is_false()
	service._set_can_request(true)
	assert_bool(bool(backend.can_request_ads.call())).is_true()
