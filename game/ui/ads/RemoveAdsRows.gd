class_name RemoveAdsRows
extends VBoxContainer
## The Remove ads and Restore purchases rows (ADR 0039 section 8, plan P434), the widget of
## Settings' `PurchaseSlot`. It only calls the AdService facade: `has_remove_ads`,
## `remove_ads_price_text`, `purchase_remove_ads`, `restore_purchases` and `entitlement_changed`.
## - Space (P445, the rule of the rewarded offers): while the store has not answered the rows keep
##   their full height, invisible and untouchable, so nothing below them moves when the answer
##   comes. They collapse to 0 only when the store is already known unavailable at the moment they
##   would take their place; that is decided once per visit (a screen re-entering the tree starts
##   a new visit). A late answer never resizes: a price fills the reserved space, an unavailable
##   store leaves it empty for the rest of the visit.
## - "Remove ads" with the store's price text shows only while the entitlement is not held and the
##   store has a price (`store_state` AVAILABLE), never a spinner. While the store answers the rows
##   poll for it.
## - "Restore purchases" shows with the same rule (no store, nothing to restore from), and stays
##   while the entitlement is held.
## - Rows that appear ignore touches for `reward_arm_ms`, so a tap meant for the button that stood
##   there a moment ago hits nothing.
## - While a call runs both rows are disabled and the tapped one reads WORKING… (RESTORING… for
##   Restore); a second tap is ignored. The rows come back after, also when the screen left the
##   tree meanwhile (Back is refused while a call runs, so it is never freed under it).
## - A title too long for the row shortens before the price does; only a price wider than the
##   whole row (down to one title character) can still be clipped.
## - Outside a node named `PurchaseSlot` the widget never shows (a battle's Settings has no slot).
## Rows are at least 48 dp; their height does not change with the text.

const SLOT_NAME: StringName = &"PurchaseSlot"
const ROW_DP: Vector2 = Vector2(0.0, 48.0)
## Seconds between price checks while the store has not answered.
const POLL_S: float = 1.0

## Settings and tests set it before the widget enters the tree; null means the autoload.
var service: Node = null
## Milliseconds clock for the arm delay; tests replace it with a fake one.
var now_ms: Callable = Time.get_ticks_msec

var remove_button: Button
var restore_button: Button
var _busy: bool = false
var _timer: Timer
var _price: String = ""
## Decided at the visit's first refresh: the rows take no space for this visit.
var _collapsed: bool = false
var _decided: bool = false
var _live: bool = false
var _armed_at_ms: int = 0
var _arm_ms: int = AdsSettingsDef.load_default().reward_arm_ms


func _ready() -> void:
	RemoveAdsText.register()
	name = &"RemoveAdsRows"
	service = service if service != null else get_tree().root.get_node_or_null("AdService")
	remove_button = _row(_on_remove)
	restore_button = _row(_on_restore)
	restore_button.text = tr(RemoveAdsText.RESTORE)
	remove_button.resized.connect(_fit)
	_timer = Timer.new()
	_timer.wait_time = POLL_S
	_timer.timeout.connect(refresh)
	add_child(_timer)
	if service != null and service.has_signal(&"entitlement_changed"):
		service.connect(&"entitlement_changed", _on_entitlement)
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and _timer != null:
		# Back from a screen: a new visit, and an entitlement may have changed meanwhile. Deferred,
		# because the parent is notified before the child Timer is in the tree.
		_decided = false
		refresh.call_deferred()


## True while a purchase or restore call is open: Settings keeps itself open then.
func is_busy() -> bool:
	return _busy


## Lays the rows out again from the service's answers.
func refresh() -> void:
	_price = _store_price()
	var state: int = _store_state()
	var in_slot: bool = _in_slot()
	if in_slot and not _decided:
		_decided = true
		_collapsed = state == Purchases.StoreState.UNAVAILABLE
	var reserved: bool = in_slot and not _collapsed
	var live: bool = reserved and state == Purchases.StoreState.AVAILABLE and not _price.is_empty()
	if live and not _live:
		_armed_at_ms = int(now_ms.call()) + _arm_ms
	_live = live
	remove_button.visible = reserved and not _owned()
	restore_button.visible = reserved
	visible = reserved
	for button: Button in [remove_button, restore_button]:
		button.flat = not live  # Reserved but empty: no plate and (below) no text, the space only.
		button.mouse_filter = Control.MOUSE_FILTER_STOP if live else Control.MOUSE_FILTER_IGNORE
		button.focus_mode = Control.FOCUS_ALL if live else Control.FOCUS_NONE
		button.disabled = _busy or not live
	if not _busy:
		restore_button.text = tr(RemoveAdsText.RESTORE) if live else ""
	_fit()
	if _timer == null or not _timer.is_inside_tree():
		return  # A timer starts only in the tree; the enter-tree refresh covers the rest.
	if reserved and state == Purchases.StoreState.UNKNOWN:
		_timer.start()  # The store has not answered yet: ask again.
	else:
		_timer.stop()


func _in_slot() -> bool:
	return get_parent() != null and get_parent().name == SLOT_NAME


func _store_price() -> String:
	if service == null or not service.has_method(&"remove_ads_price_text"):
		return ""
	return String(service.call(&"remove_ads_price_text"))


## `Purchases.StoreState` from the service; a service that cannot say counts as unavailable.
func _store_state() -> int:
	if service == null or not service.has_method(&"store_state"):
		return Purchases.StoreState.UNAVAILABLE
	return int(service.call(&"store_state"))


func _owned() -> bool:
	return (
		service != null
		and service.has_method(&"has_remove_ads")
		and bool(service.call(&"has_remove_ads"))
	)


## The Remove ads text: title and price, the title shortened until the whole text fits.
func _fit() -> void:
	if _busy or remove_button == null:
		return
	if not _live:
		remove_button.text = ""
		return
	var title: String = tr(RemoveAdsText.REMOVE)
	var text: String = tr(RemoveAdsText.PRICED) % [title, _price]
	var font: Font = remove_button.get_theme_font("font")
	var font_size: int = remove_button.get_theme_font_size("font_size")
	var room: float = (
		remove_button.size.x - remove_button.get_theme_stylebox("normal").get_minimum_size().x
	)
	if room > 0.0:
		for keep: int in range(title.length() - 1, 0, -1):
			if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= room:
				break
			text = (
				tr(RemoveAdsText.PRICED) % [title.left(keep) + tr(RemoveAdsText.ELLIPSIS), _price]
			)
	remove_button.text = text


func _on_entitlement(_owned_now: bool) -> void:
	refresh()


func _on_remove() -> void:
	await _run(remove_button, &"purchase_remove_ads", RemoveAdsText.BUSY)


func _on_restore() -> void:
	await _run(restore_button, &"restore_purchases", RemoveAdsText.RESTORING)


func _run(button: Button, method: StringName, busy_text: StringName) -> void:
	if _busy or not _live or service == null or not service.has_method(method):
		return  # One call at a time: a second tap does nothing (nor on reserved, empty rows).
	if int(now_ms.call()) < _armed_at_ms:
		return  # The rows have only just appeared.
	_busy = true
	_set_disabled(true)
	button.text = tr(busy_text)
	await service.call(method)
	_busy = false  # Always, also when Settings left the tree meanwhile.
	_set_disabled(false)
	restore_button.text = tr(RemoveAdsText.RESTORE)
	_fit()
	if is_inside_tree():
		refresh()


func _set_disabled(on: bool) -> void:
	remove_button.disabled = on or not _live
	restore_button.disabled = on or not _live


func _row(action: Callable) -> Button:
	var button: Button = Button.new()
	button.theme_type_variation = &"CapsButton"
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	button.visible = false  # `refresh` shows it, and arms the touch delay.
	var floor_dp: DpMinSize = DpMinSize.new()
	floor_dp.min_dp = ROW_DP
	button.add_child(floor_dp)
	button.pressed.connect(action)
	add_child(button)
	return button
