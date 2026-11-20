extends GdUnitTestSuite
## P445: `Purchases.store_state` over the FakeBilling knobs: UNKNOWN until the connection and the
## product query answer, UNAVAILABLE without a store, a product or a price, else AVAILABLE.

const PRODUCT: String = "remove_ads"

var _fake: FakeBilling
var _purchases: Purchases


func before_test() -> void:
	_fake = FakeBilling.new()
	_purchases = _make(_fake)


func _make(backend: BillingBackend) -> Purchases:
	return Purchases.new(backend, PRODUCT, func() -> bool: return false)


func test_store_state_follows_the_connection_and_the_product_query() -> void:
	assert_int(_purchases.store_state()).is_equal(Purchases.StoreState.UNKNOWN)  # Never asked.
	_purchases.price_text()  # Starts the connection and the query; the fake answers at once.
	assert_int(_purchases.store_state()).is_equal(Purchases.StoreState.AVAILABLE)
	var slow: FakeBilling = FakeBilling.new()
	slow.connect_never_answers = true
	var connecting: Purchases = _make(slow)
	connecting.price_text()
	assert_int(connecting.store_state()).is_equal(Purchases.StoreState.UNKNOWN)
	var loading: FakeBilling = FakeBilling.new()
	loading.product_never_answers = true
	var product: Purchases = _make(loading)
	product.price_text()
	assert_int(product.store_state()).is_equal(Purchases.StoreState.UNKNOWN)


func test_store_state_is_unavailable_without_a_store_or_a_product() -> void:
	_fake.store_available = false
	_purchases.price_text()
	assert_int(_purchases.store_state()).is_equal(Purchases.StoreState.UNAVAILABLE)
	var missing: FakeBilling = FakeBilling.new()
	missing.product_found = false
	var lacking: Purchases = _make(missing)
	lacking.price_text()
	assert_int(lacking.store_state()).is_equal(Purchases.StoreState.UNAVAILABLE)
	assert_int(_make(BillingBackend.new()).store_state()).is_equal(Purchases.StoreState.UNAVAILABLE)


func test_a_known_price_stays_available_when_the_connection_drops_later() -> void:
	_purchases.price_text()
	_fake.connect_never_answers = true
	_fake.connect_store()  # Connecting again, and it never ends.
	assert_int(_purchases.store_state()).is_equal(Purchases.StoreState.AVAILABLE)
