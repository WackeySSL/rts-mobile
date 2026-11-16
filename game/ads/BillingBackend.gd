class_name BillingBackend
extends RefCounted
## The seam between Purchases and a store (ADR 0039 section 8). Purchases owns every rule (never
## grant on PENDING, acknowledge once, refund, offline); a backend only connects, queries, launches
## and reports. Methods never block: connection, product and purchase queries answer through their
## state getters, the purchase sheet through the signals. This base is an inert backend whose store
## is unavailable. `FakeBilling` is the scriptable fake; `PlayBillingBackend` (P406b, after P411b)
## is the only class that may name the Play Billing plugin.
##
## To confirm in P406b:
## - Every signal below is emitted on the main thread (deferred when the plugin calls from another).
## - A purchase that completes after Purchases stopped waiting still arrives as `purchase_finished`.
## - ITEM_ALREADY_OWNED on a launch means the store already holds the purchase: report FAILED and
##   let Purchases' silent restore pick it up.
## - A purchase lists several `products`: report one `purchase_finished` per product id, and one
##   entry per product in `owned_purchases`.
## - UNSPECIFIED_STATE is neither PURCHASED nor PENDING: it is not purchased.
## - An acknowledge that never answers must not stay in Purchases' acknowledged set: answer
##   `acknowledge_finished(token, false)` at a timeout, so the next restore retries. Play refunds a
##   purchase that stays unacknowledged for 3 days, so the silent restore at start-up and on resume
##   matters.

## The purchase sheet is on screen. Never emitted when the launch failed before it showed.
signal sheet_shown
## A purchase attempt ended, or a pending one completed later. `token` is empty unless the outcome
## is PURCHASED or PENDING.
signal purchase_finished(product_id: String, outcome: Outcome, token: String)
## The answer to `acknowledge`.
signal acknowledge_finished(token: String, ok: bool)

enum ConnState { IDLE, CONNECTING, READY, UNAVAILABLE }
enum QueryState { IDLE, LOADING, DONE, FAILED }
enum Outcome { PURCHASED, PENDING, CANCELED, FAILED }

## Keys of the dictionaries in `owned_purchases`.
const KEY_PRODUCT: String = "product_id"
const KEY_TOKEN: String = "token"
## false while the purchase is PENDING.
const KEY_PURCHASED: String = "purchased"
const KEY_ACKNOWLEDGED: String = "acknowledged"


## IDLE until `connect_store`, CONNECTING while the store answers, then READY or UNAVAILABLE.
func connection_state() -> ConnState:
	return ConnState.UNAVAILABLE


## Starts a connection to the store; the answer shows in `connection_state`.
func connect_store() -> void:
	pass


## DONE only when the store knows the product.
func product_state(_product_id: String) -> QueryState:
	return QueryState.FAILED


## Asks the store for the product's details; the answer shows in `product_state`.
func query_product(_product_id: String) -> void:
	pass


## The store's localised price text; empty unless `product_state` is DONE.
func price_text(_product_id: String) -> String:
	return ""


## Opens the purchase sheet: `sheet_shown` then, later, `purchase_finished`; or only
## `purchase_finished` with FAILED.
func launch_purchase(_product_id: String) -> void:
	pass


## The state of the request `query_purchases` returned. FAILED for any other id (a superseded
## request) and when the store did not answer (offline). DONE means a valid answer, nothing else.
func purchases_state(_request_id: int) -> QueryState:
	return QueryState.FAILED


## Asks the store for the player's current purchases and returns the request's id. Before it
## returns the state is LOADING and `owned_purchases` is empty: an older answer never stands in
## for the new one.
func query_purchases() -> int:
	return 0


## The latest answer's purchases, each a dictionary with the KEY_ fields; empty until DONE.
func owned_purchases() -> Array[Dictionary]:
	return []


## Asks the store to acknowledge the purchase; the answer is `acknowledge_finished`.
func acknowledge(_token: String) -> void:
	pass
