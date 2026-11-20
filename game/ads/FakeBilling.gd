class_name FakeBilling
extends BillingBackend
## The fake store: editor, tests, web preview and every build without the Play plugin (ADR 0039
## section 8). Scriptable: an unavailable store, a connection or query that never answers, a query
## that answers only later, an offline query, an unknown product, a sheet that never shows (until
## `show_late_sheet`) or never closes, any outcome, a failing acknowledge, a refund. Answers
## synchronously otherwise. The sheet's default outcome is CANCELED, so nothing is bought by
## accident in the editor. Enums are written in full (`BillingBackend.X`): the bare inherited name
## does not match the same type in other scripts.

## The placeholder price: the real text comes from the store, never from the game.
const DEFAULT_PRICE: String = "Test price"

## The store cannot be reached: connecting ends UNAVAILABLE and queries fail.
var store_available: bool = true
## The connection stays CONNECTING.
var connect_never_answers: bool = false
## A connect or a product query answers one step late: it stays CONNECTING or LOADING until
## `answer_late`, as a real store does (never synchronously).
var late_answers: bool = false
## A connect resets the product query (the price is gone until it is asked again), as a store
## client may on a reconnect.
var reset_product_on_connect: bool = false
## false: the store does not know the product.
var product_found: bool = true
## The product query stays LOADING.
var product_never_answers: bool = false
## The purchases query ends FAILED (offline).
var query_fails: bool = false
## The purchases query stays LOADING for good.
var query_never_answers: bool = false
## The purchases query answers only at `answer_queries`, from the purchases at the time it asked.
var defer_queries: bool = false
## A launch ends FAILED before any sheet shows.
var launch_fails: bool = false
## The sheet opens only at `show_late_sheet`.
var sheet_never_shows: bool = false
## The sheet stays open until `finish_sheet`.
var sheet_never_closes: bool = false
## The outcome a sheet ends with.
var next_outcome: BillingBackend.Outcome = BillingBackend.Outcome.CANCELED
## An acknowledge is answered with failure.
var ack_fails: bool = false
## The price text the store reports.
var price: String = DEFAULT_PRICE
## Fake-only: a sheet ends at once per `next_outcome`. Set by AdService from `fake_auto_close`.
var auto_close: bool = true
## Fake-only: draw the "Test purchase" sheet on `host` (when `auto_close` is false).
var draw_placeholders: bool = false
## Where the sheet is drawn; none is drawn without one in the tree.
var host: Node = null
## The store's purchases, as the next query reports them.
var purchases: Array[Dictionary] = []

var launches: Array[String] = []
var acknowledges: Array[String] = []

var _connection: BillingBackend.ConnState = BillingBackend.ConnState.IDLE
var _product: BillingBackend.QueryState = BillingBackend.QueryState.IDLE
var _query: BillingBackend.QueryState = BillingBackend.QueryState.IDLE
var _request_id: int = 0
var _snapshot: Array[Dictionary] = []
var _answer: Array[Dictionary] = []
var _pending: bool = false
var _sheet_open: bool = false
var _token_count: int = 0
var _sheet_node: FakeBillingSheet = null
var _late: Array[StringName] = []


func connection_state() -> BillingBackend.ConnState:
	return _connection


func connect_store() -> void:
	if reset_product_on_connect:
		_product = BillingBackend.QueryState.IDLE
	if connect_never_answers:
		_connection = BillingBackend.ConnState.CONNECTING
	elif late_answers:
		_connection = BillingBackend.ConnState.CONNECTING
		_late.append(&"connect")
	else:
		_settle_connection()


func product_state(_product_id: String) -> BillingBackend.QueryState:
	return _product


func query_product(_product_id: String) -> void:
	if product_never_answers:
		_product = BillingBackend.QueryState.LOADING
	elif late_answers:
		_product = BillingBackend.QueryState.LOADING
		_late.append(&"product")
	else:
		_settle_product()


## Answers the connects and queries that `late_answers` held back.
func answer_late() -> void:
	var held: Array[StringName] = _late.duplicate()
	_late.clear()
	for step: StringName in held:
		if step == &"connect":
			_settle_connection()
		else:
			_settle_product()


func _settle_connection() -> void:
	_connection = (
		BillingBackend.ConnState.READY if store_available else BillingBackend.ConnState.UNAVAILABLE
	)


func _settle_product() -> void:
	_product = (
		BillingBackend.QueryState.DONE if product_found else BillingBackend.QueryState.FAILED
	)


func price_text(_product_id: String) -> String:
	return price if _product == BillingBackend.QueryState.DONE else ""


func launch_purchase(product_id: String) -> void:
	launches.append(product_id)
	if launch_fails:
		purchase_finished.emit(product_id, BillingBackend.Outcome.FAILED, "")
		return
	_pending = true
	if not sheet_never_shows:
		show_late_sheet()


## Shows the pending sheet unless it already shows; then ends it per the script.
func show_late_sheet() -> void:
	if not _pending or _sheet_open:
		return
	_sheet_open = true
	sheet_shown.emit()
	if not auto_close and draw_placeholders and _host_ready():
		_draw_sheet()
	elif not sheet_never_closes:
		finish_sheet(next_outcome)


## The end of the open sheet: records the purchase for PURCHASED and PENDING, then reports it.
func finish_sheet(outcome: BillingBackend.Outcome) -> void:
	if not _pending:
		return
	_pending = false
	_sheet_open = false
	_clear_sheet()
	var token: String = ""
	var product_id: String = launches.back()
	if outcome == BillingBackend.Outcome.PURCHASED or outcome == BillingBackend.Outcome.PENDING:
		_token_count += 1
		token = "fake-token-%d" % _token_count
		add_owned(product_id, token, outcome == BillingBackend.Outcome.PURCHASED, false)
	purchase_finished.emit(product_id, outcome, token)


## Puts a purchase in the store, as a query reports it.
func add_owned(
	product_id: String, token: String, purchased: bool = true, acknowledged: bool = true
) -> void:
	var entry: Dictionary = {
		BillingBackend.KEY_PRODUCT: product_id,
		BillingBackend.KEY_TOKEN: token,
		BillingBackend.KEY_PURCHASED: purchased,
		BillingBackend.KEY_ACKNOWLEDGED: acknowledged,
	}
	purchases.append(entry)


## A pending purchase is paid: the store reports it as PURCHASED. Unknown tokens report nothing.
func complete_pending(token: String) -> void:
	for entry: Dictionary in purchases:
		if entry[BillingBackend.KEY_TOKEN] == token:
			entry[BillingBackend.KEY_PURCHASED] = true
			purchase_finished.emit(
				entry[BillingBackend.KEY_PRODUCT], BillingBackend.Outcome.PURCHASED, token
			)
			return


## A refund or revoke: the store no longer lists the purchases.
func refund() -> void:
	purchases.clear()


func purchases_state(request_id: int) -> BillingBackend.QueryState:
	return _query if request_id == _request_id else BillingBackend.QueryState.FAILED


func query_purchases() -> int:
	_request_id += 1
	_snapshot = purchases.duplicate(true)
	_answer = []
	if query_never_answers or defer_queries:
		_query = BillingBackend.QueryState.LOADING
	else:
		_resolve_query()
	return _request_id


## Answers a deferred query, with the purchases as they were when it asked.
func answer_queries() -> void:
	if _query == BillingBackend.QueryState.LOADING and not query_never_answers:
		_resolve_query()


func owned_purchases() -> Array[Dictionary]:
	return _answer.duplicate(true)


func acknowledge(token: String) -> void:
	acknowledges.append(token)
	if ack_fails:
		acknowledge_finished.emit(token, false)
		return
	for entry: Dictionary in purchases:
		if entry[BillingBackend.KEY_TOKEN] == token:
			entry[BillingBackend.KEY_ACKNOWLEDGED] = true
	acknowledge_finished.emit(token, true)


func _resolve_query() -> void:
	if query_fails or not store_available:
		_query = BillingBackend.QueryState.FAILED
	else:
		_query = BillingBackend.QueryState.DONE
		_answer = _snapshot


func _draw_sheet() -> void:
	if _sheet_node != null:
		return
	var buy: Callable = finish_sheet.bind(BillingBackend.Outcome.PURCHASED)
	var wait: Callable = finish_sheet.bind(BillingBackend.Outcome.PENDING)
	var cancel: Callable = finish_sheet.bind(BillingBackend.Outcome.CANCELED)
	_sheet_node = FakeBillingSheet.build(price, buy, wait, cancel)
	host.add_child(_sheet_node)


func _clear_sheet() -> void:
	if is_instance_valid(_sheet_node):
		_sheet_node.queue_free()
	_sheet_node = null


func _host_ready() -> bool:
	return host != null and is_instance_valid(host) and host.is_inside_tree()
