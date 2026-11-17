class_name RewardedOffer
extends VBoxContainer
## The generic rewarded-ad offer (ADR 0039 section 7; plan P431). P432 (Double XP) and P433
## (+500 starting credits) build it with `RewardedOffer.new()`, call `configure` with a placement,
## the exact reward text and an `on_reward` Callable, and put it as the only child of their
## screen's slot (plan Interfaces items 4, 5 and 13). The slot is a plain Container, so it takes
## this node's minimum size: the button's, and 0 while the offer is hidden.
## Rules (skill admob-policy, "Rewarded flow"): it shows only while the service says a rewarded ad
## is ready, never a spinner; a tap awaits `show_rewarded`, and the host's `on_reward` runs only
## inside the SDK's reward callback (so the host saves before the close), never on close or
## cancel; after a grant the offer goes away, also when the ad opened after the service's deadline.
## After a cancel it stays, or hides when no ad is ready and returns when one is. One offer per
## screen: at most `rewarded_offers_per_screen` (data) live offers share a screen scope; the rest
## stay hidden and take a slot when one frees up. The scope is `configure`'s, else the slot's
## screen (`parent.owner`, else the parent); an offer under a hidden screen holds no slot.
## `on_reward` must be bound to an autoload or a service, never to the screen: the reward arrives
## even when the screen was freed while the ad was open.
## The button is a CapsButton (upper-case text), so the host's tree must inherit the HUD theme
## (`game/ui/theme.tres`). Nothing here animates: no spinner, no polling per frame (a Timer).

## Fires after the reward callback ran (in the callback, before the ad closes).
signal granted

## Seconds between two re-checks of `rewarded_ready` while the offer is in the tree.
const RECHECK_INTERVAL_S: float = 1.0
const BUTTON_DP: Vector2 = Vector2(48, 48)
const AdServiceScript: GDScript = preload("res://game/ads/AdService.gd")
const AUTOLOAD_PATH: NodePath = ^"/root/AdService"
const _CLAIM_META: StringName = &"rewarded_offer_claims"

var placement: StringName = &""
var reward_text: String = ""
var on_reward: Callable = Callable()
## The ads data; tests replace it. Its `rewarded_offers_per_screen` is the screen's limit.
var settings: AdsSettingsDef = AdsSettingsDef.load_default()

var _service: AdServiceScript = null
var _bound: AdServiceScript = null
var _scope: Node = null
var _claimed_scope: Node = null
var _busy: bool = false
var _done: bool = false
var _button: Button = Button.new()
var _timer: Timer = Timer.new()


func _init() -> void:
	visible = false
	_button.name = &"OfferButton"
	_button.theme_type_variation = &"CapsButton"
	_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var floor_dp: DpMinSize = DpMinSize.new()
	floor_dp.min_dp = BUTTON_DP
	_button.add_child(floor_dp)
	_button.pressed.connect(_on_pressed)
	add_child(_button)
	_timer.name = &"RecheckTimer"
	_timer.wait_time = RECHECK_INTERVAL_S
	_timer.timeout.connect(refresh)
	add_child(_timer)


func _ready() -> void:
	_bind_parent()
	_bind_service()
	refresh()
	_start_timer()


func _enter_tree() -> void:
	if not is_node_ready():
		return
	_bind_parent()
	_bind_service()
	refresh()
	_start_timer.call_deferred()


func _exit_tree() -> void:
	_release()
	_unbind_parent()
	_unbind_service()


## Sets what the host owns. `service_node` is the AdService (default: the autoload); `scope_node`
## stands for the screen. Call it before or after the offer enters the tree; a call while the ad is
## running is ignored (the running offer keeps its values).
func configure(
	service_node: AdServiceScript,
	placement_id: StringName,
	text: String,
	reward_callable: Callable,
	scope_node: Node = null
) -> void:
	if _busy:
		return
	_unbind_service()
	_service = service_node
	placement = placement_id
	reward_text = text
	on_reward = reward_callable
	_scope = scope_node
	_button.text = reward_text.to_upper()
	if is_inside_tree():
		_release()
		_bind_service()
		refresh()


## True while the offer is on screen.
func is_offered() -> bool:
	return is_visible_in_tree()


## Re-asks the service and shows or hides the offer; the timer and the service's signals call it.
func refresh() -> void:
	if _busy:
		return
	if not _screen_shown():
		_release()
		_show(false)
		return
	_claim()
	_show(_may_offer())


## Marks the offer as granted: hides it for good. False when it already was (a second reward of
## the same offer is ignored). Called by the relay inside the reward callback.
func note_granted() -> bool:
	if _done:
		return false
	_done = true
	visible = false
	_timer.stop()
	return true


## Applies the answer of `refresh`; a host may keep the node laid out while the ad is not ready.
func _show(on: bool) -> void:
	visible = on


func _may_offer() -> bool:
	if _done or _claimed_scope == null or placement == &"":
		return false
	var svc: AdServiceScript = _resolve_service()
	return svc != null and svc.rewarded_ready(placement)


func _on_pressed() -> void:
	if _busy or _done:
		return
	var svc: AdServiceScript = _resolve_service()
	if svc == null:
		return
	_busy = true
	_button.disabled = true
	# The relay awaits the ad, so a freed offer leaves no half-resumed coroutine behind.
	RewardRelay.new(self, on_reward).run(svc, placement, _on_show_finished)


func _on_show_finished() -> void:
	_busy = false
	_button.disabled = false
	if is_inside_tree():
		refresh()


func _resolve_service() -> AdServiceScript:
	if is_instance_valid(_service):
		return _service
	var loop: SceneTree = get_tree()
	if loop == null:
		return null
	return loop.root.get_node_or_null(AUTOLOAD_PATH) as AdServiceScript


func _bind_service() -> void:
	var svc: AdServiceScript = _resolve_service()
	if svc == null or svc == _bound:
		return
	_unbind_service()
	_bound = svc
	svc.consent_finished.connect(_on_service_event)
	svc.ad_closed.connect(_on_service_event)


func _unbind_service() -> void:
	if is_instance_valid(_bound):
		_bound.consent_finished.disconnect(_on_service_event)
		_bound.ad_closed.disconnect(_on_service_event)
	_bound = null


func _on_service_event(_arg: Variant) -> void:
	refresh()


func _bind_parent() -> void:
	var parent: CanvasItem = get_parent() as CanvasItem
	if parent != null and not parent.visibility_changed.is_connected(refresh):
		parent.visibility_changed.connect(refresh)


func _unbind_parent() -> void:
	var parent: CanvasItem = get_parent() as CanvasItem
	if parent != null and parent.visibility_changed.is_connected(refresh):
		parent.visibility_changed.disconnect(refresh)


func _start_timer() -> void:
	if not _done and is_inside_tree():
		_timer.start()


## False while an ancestor screen is hidden (the offer's own `visible` is its own business).
func _screen_shown() -> bool:
	var parent: CanvasItem = get_parent() as CanvasItem
	return is_inside_tree() and (parent == null or parent.is_visible_in_tree())


func _find_scope() -> Node:
	if is_instance_valid(_scope):
		return _scope
	var parent: Node = get_parent()
	return parent.owner if parent != null and parent.owner != null else parent


## Takes one of the screen's offer slots; stays unclaimed (hidden) when they are all taken.
func _claim() -> void:
	if _claimed_scope != null or not is_inside_tree():
		return
	var scope: Node = _find_scope()
	if scope == null:
		return
	var count: int = int(scope.get_meta(_CLAIM_META, 0))
	if count >= settings.rewarded_offers_per_screen:
		return
	scope.set_meta(_CLAIM_META, count + 1)
	_claimed_scope = scope


func _release() -> void:
	if is_instance_valid(_claimed_scope):
		var count: int = int(_claimed_scope.get_meta(_CLAIM_META, 1))
		_claimed_scope.set_meta(_CLAIM_META, maxi(count - 1, 0))
	_claimed_scope = null
