class_name Purchases
extends RefCounted
## The Remove ads purchase (ADR 0039 section 8), over a BillingBackend. It owns the rules and keeps
## no entitlement of its own: it reads the cached one through `owned` (AdService's ledger) and
## reports a change with `entitlement_changed`, which AdService writes back.
## - Only PURCHASED grants; PENDING never does (a later PURCHASED, as the store reports it, does).
## - A purchase is acknowledged once per token; a failed acknowledge is retried by the next
##   restore, because the store lists it as unacknowledged.
## - A query that answers is the truth: a purchase missing from it clears the cache (a refund),
##   unless a grant came in while that query was in flight (its answer is older than the grant).
##   One that does not answer (offline, timeout) leaves the cache as it is.
## - The wait has a deadline only until the store sheet shows (or the query answers). Once the
##   sheet is up the call waits for its end. A result that comes after the deadline is still
##   applied, because the backend's signals are always connected.
## - `restore` and `purchase` do not overlap: the second returns false while the first waits.
## Pure RefCounted: the clock is passed in, so tests use a fake one. Never touched by game/sim.

## Fires when the entitlement changes from what `owned` reports, with the new state.
signal entitlement_changed(has_remove_ads: bool)

## After this many timeouts without a sheet an unanswered purchase stops blocking new ones.
const RESULT_GRACE_FACTOR: int = 4
## No deadline: wait for the condition however long it takes.
const NO_DEADLINE: int = -1

var _backend: BillingBackend
var _product_id: String
var _owned: Callable
var _busy: bool = false
var _sheet_open: bool = false
var _finished: bool = false
var _awaiting_result: bool = false
var _awaiting_since_ms: int = 0
var _query_id: int = 0
var _granted_during_query: bool = false
var _acked: Dictionary[String, bool] = {}
## Tokens the store reported as PENDING: their later completion is not the current call's answer.
var _pending_tokens: Dictionary[String, bool] = {}


## `owned` is a Callable returning the cached entitlement.
func _init(backend: BillingBackend, product_id: String, owned: Callable) -> void:
	_backend = backend
	_product_id = product_id
	_owned = owned
	_backend.sheet_shown.connect(_on_sheet_shown)
	_backend.purchase_finished.connect(_on_purchase_finished)
	_backend.acknowledge_finished.connect(_on_acknowledge_finished)


## The store's price text for the product, empty until known or when the store has no such
## product. Starts the connection and the product query when idle; never blocks.
func price_text() -> String:
	if _backend.connection_state() == BillingBackend.ConnState.IDLE:
		_backend.connect_store()
	if _backend.connection_state() == BillingBackend.ConnState.READY:
		if _backend.product_state(_product_id) == BillingBackend.QueryState.IDLE:
			_backend.query_product(_product_id)
	return _backend.price_text(_product_id)


## True once the entitlement is held. False at the deadline before the sheet shows, on cancel,
## failure, PENDING and while a restore or an earlier purchase is still waiting.
func purchase(now_ms: Callable, timeout_ms: int) -> bool:
	if _is_owned():
		return true
	if _busy:
		return false
	_expire_stale_result(int(now_ms.call()), timeout_ms)
	if _awaiting_result:
		return false
	_busy = true
	var deadline: int = int(now_ms.call()) + timeout_ms
	# The entitlement may have arrived while the product was loading: never launch then.
	if await _await_product(now_ms, deadline) and not _is_owned():
		_sheet_open = false
		_finished = false
		_awaiting_result = true
		_awaiting_since_ms = int(now_ms.call())
		_backend.launch_purchase(_product_id)
		var started: Callable = func() -> bool: return _sheet_open or _finished or _is_owned()
		if await _until(started, now_ms, deadline):
			await _until(func() -> bool: return _finished or _is_owned(), now_ms)
	_busy = false
	return _is_owned()


## True when the entitlement stands after the query (the store lists the purchase, or a grant came
## in meanwhile). The deadline covers the connection and the answer; offline or unanswered it
## returns false and keeps the cache. Needs no UI: AdService also calls it silently at start-up
## and on resume, which retries failed acknowledges and grants pendings paid while the app was
## closed.
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
	var pending: bool = false
	for entry: Dictionary in _backend.owned_purchases():
		if entry[BillingBackend.KEY_PRODUCT] != _product_id:
			continue
		if not entry[BillingBackend.KEY_PURCHASED]:
			pending = true
			continue
		found = true
		if not entry[BillingBackend.KEY_ACKNOWLEDGED]:
			_acknowledge_once(entry[BillingBackend.KEY_TOKEN])
	if found:
		_set_owned(true)
	elif not _granted_during_query:
		_set_owned(false)
	# An answer with no pending purchase and no sheet means nothing is still on its way.
	if not pending and not _sheet_open:
		_awaiting_result = false
	return _is_owned()


func _is_owned() -> bool:
	return bool(_owned.call())


func _expire_stale_result(now: int, timeout_ms: int) -> void:
	var limit: int = _awaiting_since_ms + timeout_ms * RESULT_GRACE_FACTOR
	if _awaiting_result and not _sheet_open and now >= limit:
		_awaiting_result = false


func _await_connected(now_ms: Callable, deadline: int) -> bool:
	var state: BillingBackend.ConnState = _backend.connection_state()
	if state != BillingBackend.ConnState.READY and state != BillingBackend.ConnState.CONNECTING:
		_backend.connect_store()
	var settled: Callable = func() -> bool:
		return _backend.connection_state() != BillingBackend.ConnState.CONNECTING
	if not await _until(settled, now_ms, deadline):
		return false
	return _backend.connection_state() == BillingBackend.ConnState.READY


func _await_product(now_ms: Callable, deadline: int) -> bool:
	if not await _await_connected(now_ms, deadline):
		return false
	var state: BillingBackend.QueryState = _backend.product_state(_product_id)
	if state != BillingBackend.QueryState.DONE and state != BillingBackend.QueryState.LOADING:
		_backend.query_product(_product_id)
	var settled: Callable = func() -> bool:
		return _backend.product_state(_product_id) != BillingBackend.QueryState.LOADING
	if not await _until(settled, now_ms, deadline):
		return false
	return _backend.product_state(_product_id) == BillingBackend.QueryState.DONE


func _await_query(now_ms: Callable, deadline: int) -> bool:
	if not await _await_connected(now_ms, deadline):
		return false
	# A request still loading (an earlier restore timed out) is adopted, never doubled.
	if _query_id == 0 or _backend.purchases_state(_query_id) != BillingBackend.QueryState.LOADING:
		_granted_during_query = false
		_query_id = _backend.query_purchases()
	var request: int = _query_id
	var settled: Callable = func() -> bool:
		return _backend.purchases_state(request) != BillingBackend.QueryState.LOADING
	if not await _until(settled, now_ms, deadline):
		return false
	return _backend.purchases_state(request) == BillingBackend.QueryState.DONE


## True when `done` returned true; false when `now_ms` reached `deadline_ms` first. Returns at
## once, with no frame passing, when the condition already holds. (A shared helper with
## FullscreenRun's loops is a follow-up after P404 and P406 merge.)
func _until(done: Callable, now_ms: Callable, deadline_ms: int = NO_DEADLINE) -> bool:
	while not bool(done.call()):
		if deadline_ms != NO_DEADLINE and int(now_ms.call()) >= deadline_ms:
			return false
		await (Engine.get_main_loop() as SceneTree).process_frame
	return true


func _on_sheet_shown() -> void:
	_sheet_open = true


func _on_purchase_finished(
	product_id: String, outcome: BillingBackend.Outcome, token: String
) -> void:
	if product_id != _product_id:
		return
	var is_old_pending: bool = not token.is_empty() and _pending_tokens.has(token)
	if outcome == BillingBackend.Outcome.PENDING and not token.is_empty():
		_pending_tokens[token] = true
	if _awaiting_result and not is_old_pending:
		_finished = true
		_awaiting_result = false
		_sheet_open = false
	if outcome == BillingBackend.Outcome.PURCHASED:
		_pending_tokens.erase(token)
		_granted_during_query = true
		_acknowledge_once(token)
		_set_owned(true)


func _on_acknowledge_finished(token: String, ok: bool) -> void:
	if not ok:
		_acked.erase(token)


func _acknowledge_once(token: String) -> void:
	if token.is_empty() or _acked.has(token):
		return
	_acked[token] = true
	_backend.acknowledge(token)


func _set_owned(value: bool) -> void:
	if value != _is_owned():
		entitlement_changed.emit(value)
