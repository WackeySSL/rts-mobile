class_name RemoveAdsRows
extends VBoxContainer
## The Remove ads and Restore purchases rows (ADR 0039 section 8, plan P434), the widget of
## Settings' `PurchaseSlot`. It only calls the AdService facade: `has_remove_ads`,
## `remove_ads_price_text`, `purchase_remove_ads`, `restore_purchases` and `entitlement_changed`.
## - "Remove ads" with the store's price text shows only while the entitlement is not held and the
##   store has a price. An empty price means billing is unavailable (or not answered yet, and the
##   rows poll until it does), so the row stays hidden, never a spinner.
## - "Restore purchases" shows with the same rule (no store, nothing to restore from), and stays
##   while the entitlement is held.
## - While a call runs both rows are disabled and the tapped one reads WORKING…; a second tap is
##   ignored. The rows come back after, and `entitlement_changed` hides Remove ads on success.
## - Outside a node named `PurchaseSlot` the widget never shows (a battle's Settings has no slot).
## Rows are at least 48 dp; their size does not change with the text (clipped, one line).

const SLOT_NAME: StringName = &"PurchaseSlot"
const ROW_DP: Vector2 = Vector2(0.0, 48.0)
## Seconds between price checks while the store has not answered.
const POLL_S: float = 1.0

## Settings and tests set it before the widget enters the tree; null means the autoload.
var service: Node = null

var remove_button: Button
var restore_button: Button
var _busy: bool = false
var _timer: Timer


func _ready() -> void:
	RemoveAdsText.register()
	name = &"RemoveAdsRows"
	service = service if service != null else get_tree().root.get_node_or_null("AdService")
	remove_button = _row(_on_remove)
	restore_button = _row(_on_restore)
	restore_button.text = tr(RemoveAdsText.RESTORE)
	_timer = Timer.new()
	_timer.wait_time = POLL_S
	_timer.timeout.connect(refresh)
	add_child(_timer)
	if service != null and service.has_signal(&"entitlement_changed"):
		service.connect(&"entitlement_changed", _on_entitlement)
	refresh()


## Lays the rows out again from the service's answers.
func refresh() -> void:
	var price: String = _price()
	var billing: bool = _in_slot() and not price.is_empty()
	remove_button.visible = billing and not _owned()
	restore_button.visible = billing
	visible = billing
	if not _busy:
		remove_button.text = tr(RemoveAdsText.REMOVE) % price
	if _in_slot() and price.is_empty():
		_timer.start()  # The store has not answered yet: ask again.
	else:
		_timer.stop()


func _in_slot() -> bool:
	return get_parent() != null and get_parent().name == SLOT_NAME


func _price() -> String:
	if service == null or not service.has_method(&"remove_ads_price_text"):
		return ""
	return String(service.call(&"remove_ads_price_text"))


func _owned() -> bool:
	return (
		service != null
		and service.has_method(&"has_remove_ads")
		and bool(service.call(&"has_remove_ads"))
	)


func _on_entitlement(_owned_now: bool) -> void:
	refresh()


func _on_remove() -> void:
	await _run(remove_button, &"purchase_remove_ads")


func _on_restore() -> void:
	await _run(restore_button, &"restore_purchases")


func _run(button: Button, method: StringName) -> void:
	if _busy or service == null or not service.has_method(method):
		return  # One call at a time: a second tap does nothing.
	_busy = true
	_set_disabled(true)
	button.text = tr(RemoveAdsText.BUSY)
	await service.call(method)
	if not is_inside_tree():
		return
	_busy = false
	_set_disabled(false)
	restore_button.text = tr(RemoveAdsText.RESTORE)
	refresh()


func _set_disabled(on: bool) -> void:
	remove_button.disabled = on
	restore_button.disabled = on


func _row(action: Callable) -> Button:
	var button: Button = Button.new()
	button.theme_type_variation = &"CapsButton"
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	var floor_dp: DpMinSize = DpMinSize.new()
	floor_dp.min_dp = ROW_DP
	button.add_child(floor_dp)
	button.pressed.connect(action)
	add_child(button)
	return button
