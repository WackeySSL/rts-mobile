class_name Purchases
extends RefCounted
## The Remove ads purchase (ADR 0039 section 8), over a BillingBackend. It owns the rules and
## `owned`, the cached entitlement AdService keeps in its ledger and syncs in before each call.
## - Only PURCHASED grants; PENDING never does (a later PURCHASED, as the store reports it, does).
## - A purchase is acknowledged once per token; a failed acknowledge is retried by the next
##   restore, because the store lists it as unacknowledged.
## - A query that answers is the truth: a purchase missing from it clears the cache (a refund).
##   One that does not answer (offline) leaves the cache as it is.
## - The wait has a deadline only until the store sheet shows (or the query answers). Once the
##   sheet is up the call waits for its end. A result that comes after the deadline is still
##   applied, because the backend's signal is always connected.
## Pure RefCounted: the clock is passed in, so tests use a fake one. Never touched by game/sim.

## Fires when `owned` changes, with the new state.
signal entitlement_changed(has_remove_ads: bool)

var owned: bool = false

var _backend: BillingBackend
var _product_id: String
var _busy: bool = false
var _sheet_open: bool = false
var _finished: bool = false
var _awaiting_result: bool = false
var _acked: Dictionary[String, bool] = {}


func _init(backend: BillingBackend, product_id: String) -> void:
	_backend = backend
	_product_id = product_id
	_backend.sheet_shown.connect(_on_sheet_shown)
	_backend.purchase_finished.connect(_on_purchase_finished)
	_backend.acknowledge_finished.connect(_on_acknowledge_finished)


## The store's price text for the product, empty until known or when the store has no such
## product. Starts the connection and the product query when idle; never blocks.
func price_text() -> String:
	var connection: BillingBackend.ConnState = _backend.connection_state()
	if connection == BillingBackend.ConnState.IDLE:
		_backend.connect_store()
	if _backend.connection_state() == BillingBackend.ConnState.READY:
		if _backend.product_state(_product_id) == BillingBackend.QueryState.IDLE:
			_backend.query_product(_product_id)
	if _backend.product_state(_product_id) != BillingBackend.QueryState.DONE:
		return ""
	return _backend.price_text(_product_id)


## True once the entitlement is held. False at the deadline before the sheet shows, on cancel,
## failure and PENDING.
func purchase(now_ms: Callable, timeout_ms: int) -> bool:
	if owned:
		return true
	if _busy or _awaiting_result:
		return false
	_busy = true
	var deadline: int = int(now_ms.call()) + timeout_ms
	if await _await_product(now_ms, deadline):
		_sheet_open = false
		_finished = false
		_awaiting_result = true
		_backend.launch_purchase(_product_id)
		while not _sheet_open and not _finished:
			if int(now_ms.call()) >= deadline:
				_busy = false
				return false
			await _next_frame()
		while not _finished:
			await _next_frame()
	_busy = false
	return owned


## True when the store lists the purchase (granted now, or already held). The query's deadline
## covers the connection and the answer; offline or unanswered it returns false and keeps the
## cache.
func restore(now_ms: Callable, timeout_ms: int) -> bool:
	if _busy:
		return false
	_busy = true
	var deadline: int = int(now_ms.call()) + timeout_ms
	var answered: bool = await _await_query(now_ms, deadline)
	_busy = false
	if not answered:
		return false
	var found: bool = false
	for entry: Dictionary in _backend.owned_purchases():
		if entry[BillingBackend.KEY_PRODUCT] != _product_id:
			continue
		if not entry[BillingBackend.KEY_PURCHASED]:
			continue
		found = true
		if not entry[BillingBackend.KEY_ACKNOWLEDGED]:
			_acknowledge_once(entry[BillingBackend.KEY_TOKEN])
	_set_owned(found)
	return found


func _await_connected(now_ms: Callable, deadline: int) -> bool:
	var state: BillingBackend.ConnState = _backend.connection_state()
	if state != BillingBackend.ConnState.READY and state != BillingBackend.ConnState.CONNECTING:
		_backend.connect_store()
	while _backend.connection_state() == BillingBackend.ConnState.CONNECTING:
		if int(now_ms.call()) >= deadline:
			return false
		await _next_frame()
	return _backend.connection_state() == BillingBackend.ConnState.READY


func _await_product(now_ms: Callable, deadline: int) -> bool:
	if not await _await_connected(now_ms, deadline):
		return false
	var state: BillingBackend.QueryState = _backend.product_state(_product_id)
	if state != BillingBackend.QueryState.DONE and state != BillingBackend.QueryState.LOADING:
		_backend.query_product(_product_id)
	while _backend.product_state(_product_id) == BillingBackend.QueryState.LOADING:
		if int(now_ms.call()) >= deadline:
			return false
		await _next_frame()
	return _backend.product_state(_product_id) == BillingBackend.QueryState.DONE


func _await_query(now_ms: Callable, deadline: int) -> bool:
	if not await _await_connected(now_ms, deadline):
		return false
	_backend.query_purchases()
	while _backend.purchases_state() == BillingBackend.QueryState.LOADING:
		if int(now_ms.call()) >= deadline:
			return false
		await _next_frame()
	return _backend.purchases_state() == BillingBackend.QueryState.DONE


func _next_frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _on_sheet_shown() -> void:
	_sheet_open = true


func _on_purchase_finished(outcome: BillingBackend.Outcome, token: String) -> void:
	_finished = true
	_awaiting_result = false
	if outcome == BillingBackend.Outcome.PURCHASED:
		_acknowledge_once(token)
		_set_owned(true)


func _on_acknowledge_finished(token: String, ok: bool) -> void:
	if not ok:
		_acked.erase(token)


func _acknowledge_once(token: String) -> void:
	if _acked.has(token):
		return
	_acked[token] = true
	_backend.acknowledge(token)


func _set_owned(value: bool) -> void:
	if value == owned:
		return
	owned = value
	entitlement_changed.emit(value)
