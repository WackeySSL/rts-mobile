class_name CountingPurchaseService
extends Node
## A stand-in AdService for the Remove ads suites: counts the calls and keeps each one open until
## `release`.

signal entitlement_changed(has_remove_ads: bool)
signal release
var price: String = "kr 19,00"
var owned: bool = false
var purchases: int = 0
var restores: int = 0


func has_remove_ads() -> bool:
	return owned


func is_privacy_options_required() -> bool:
	return false


func remove_ads_price_text() -> String:
	return price


func purchase_remove_ads() -> bool:
	purchases += 1
	await release
	return owned


func restore_purchases() -> bool:
	restores += 1
	await release
	return owned
