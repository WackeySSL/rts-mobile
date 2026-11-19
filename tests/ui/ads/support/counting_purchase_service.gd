class_name CountingPurchaseService
extends Node
## A stand-in AdService for the Remove ads suites: counts the calls and keeps each one open until
## `release`.

signal entitlement_changed(has_remove_ads: bool)
signal release
var price: String = "kr 19,00"
## `Purchases.StoreState` the store reports; tests move it with `answer`.
var state: int = Purchases.StoreState.AVAILABLE
var owned: bool = false
var purchases: int = 0
var restores: int = 0


func has_remove_ads() -> bool:
	return owned


func is_privacy_options_required() -> bool:
	return false


func remove_ads_price_text() -> String:
	return price


func store_state() -> int:
	return state


## The store answers: a price (AVAILABLE) or none (UNAVAILABLE).
func answer(new_price: String) -> void:
	price = new_price
	state = (
		Purchases.StoreState.AVAILABLE
		if not new_price.is_empty()
		else Purchases.StoreState.UNAVAILABLE
	)


func purchase_remove_ads() -> bool:
	purchases += 1
	await release
	return owned


func restore_purchases() -> bool:
	restores += 1
	await release
	return owned
