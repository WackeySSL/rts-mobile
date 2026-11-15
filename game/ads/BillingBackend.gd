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

## The purchase sheet is on screen. Never emitted when the launch failed before it showed.
signal sheet_shown
## A purchase attempt ended, or a pending one completed later. `token` is empty unless the outcome
## is PURCHASED or PENDING.
signal purchase_finished(outcome: Outcome, token: String)
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


func connection_state() -> ConnState:
	return ConnState.UNAVAILABLE


func connect_store() -> void:
	pass


## DONE only when the store knows the product.
func product_state(_product_id: String) -> QueryState:
	return QueryState.FAILED


func query_product(_product_id: String) -> void:
	pass


## The store's localised price text, or empty while unknown.
func price_text(_product_id: String) -> String:
	return ""


## Opens the purchase sheet: `sheet_shown` then, later, `purchase_finished`; or only
## `purchase_finished` with FAILED.
func launch_purchase(_product_id: String) -> void:
	pass


func purchases_state() -> QueryState:
	return QueryState.FAILED


## Asks the store for the player's current purchases. FAILED means no answer (offline).
func query_purchases() -> void:
	pass


## The last answer's purchases, each a dictionary with the KEY_ fields.
func owned_purchases() -> Array[Dictionary]:
	return []


func acknowledge(_token: String) -> void:
	pass
