class_name FakeBilling
extends BillingBackend
## The fake store: editor, tests, web preview and every build without the Play plugin (ADR 0039
## section 8). Scriptable: an unavailable store, a connection or query that never answers, an
## offline query, an unknown product, a sheet that never shows (until `show_late_sheet`) or never
## closes, any outcome, a failing acknowledge, a refund. Answers synchronously otherwise. The
## sheet's default outcome is CANCELED, so nothing is bought by accident in the editor.

## The placeholder price: the real text comes from the store, never from the game.
const DEFAULT_PRICE: String = "Test price"

var store_available: bool = true
var connect_never_answers: bool = false
var product_found: bool = true
var product_never_answers: bool = false
var query_fails: bool = false
var query_never_answers: bool = false
var launch_fails: bool = false
var sheet_never_shows: bool = false
var sheet_never_closes: bool = false
var next_outcome: BillingBackend.Outcome = BillingBackend.Outcome.CANCELED
var ack_fails: bool = false
var price: String = DEFAULT_PRICE
## The store's purchases, as `owned_purchases` reports them.
var purchases: Array[Dictionary] = []

var launches: Array[String] = []
var acknowledges: Array[String] = []

var _connection: ConnState = ConnState.IDLE
var _product: QueryState = QueryState.IDLE
var _query: QueryState = QueryState.IDLE
var _pending: bool = false
var _sheet_open: bool = false
var _token_count: int = 0


func connection_state() -> ConnState:
	return _connection


func connect_store() -> void:
	if connect_never_answers:
		_connection = ConnState.CONNECTING
	else:
		_connection = ConnState.READY if store_available else ConnState.UNAVAILABLE


func product_state(_product_id: String) -> QueryState:
	return _product


func query_product(_product_id: String) -> void:
	if product_never_answers:
		_product = QueryState.LOADING
	else:
		_product = QueryState.DONE if product_found else QueryState.FAILED


func price_text(_product_id: String) -> String:
	return price if _product == QueryState.DONE else ""


func launch_purchase(product_id: String) -> void:
	launches.append(product_id)
	if launch_fails:
		purchase_finished.emit(BillingBackend.Outcome.FAILED, "")
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
	if not sheet_never_closes:
		finish_sheet(next_outcome)


## The end of the open sheet: records the purchase for PURCHASED and PENDING, then reports it.
func finish_sheet(outcome: BillingBackend.Outcome) -> void:
	if not _pending:
		return
	_pending = false
	_sheet_open = false
	var token: String = ""
	if outcome == BillingBackend.Outcome.PURCHASED or outcome == BillingBackend.Outcome.PENDING:
		_token_count += 1
		token = "fake-token-%d" % _token_count
		var entry: Dictionary = {
			KEY_PRODUCT: launches.back(),
			KEY_TOKEN: token,
			KEY_PURCHASED: outcome == BillingBackend.Outcome.PURCHASED,
			KEY_ACKNOWLEDGED: false,
		}
		purchases.append(entry)
	purchase_finished.emit(outcome, token)


## A pending purchase is paid: the store reports it as PURCHASED.
func complete_pending(token: String) -> void:
	for entry: Dictionary in purchases:
		if entry[KEY_TOKEN] == token:
			entry[KEY_PURCHASED] = true
	purchase_finished.emit(BillingBackend.Outcome.PURCHASED, token)


## A refund or revoke: the store no longer lists the purchases.
func refund() -> void:
	purchases.clear()


func purchases_state() -> QueryState:
	return _query


func query_purchases() -> void:
	if query_never_answers:
		_query = QueryState.LOADING
	else:
		_query = QueryState.FAILED if query_fails or not store_available else QueryState.DONE


func owned_purchases() -> Array[Dictionary]:
	return purchases.duplicate(true)


func acknowledge(token: String) -> void:
	acknowledges.append(token)
	if ack_fails:
		acknowledge_finished.emit(token, false)
		return
	for entry: Dictionary in purchases:
		if entry[KEY_TOKEN] == token:
			entry[KEY_ACKNOWLEDGED] = true
	acknowledge_finished.emit(token, true)
