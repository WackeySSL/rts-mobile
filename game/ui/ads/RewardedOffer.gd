class_name RewardedOffer
extends VBoxContainer
## The generic rewarded-ad offer (ADR 0039 section 7; plan P431). P432 (Double XP) and P433
## (+500 starting credits) configure it with a placement, the exact reward text and an
## `on_reward` Callable, and put it as the only child of their screen's slot (plan Interfaces
## items 4, 5 and 13).
## Rules (skill admob-policy, "Rewarded flow"): it shows only while the service says a rewarded ad
## is ready, never a spinner; a tap awaits `show_rewarded`, and the host's `on_reward` runs only
## inside the SDK's reward callback (so the host saves before the close), never on close or
## cancel; after a grant the offer goes away; after a cancel it stays (or hides when no ad is
## ready any more and returns when one is). One offer per screen: at most
## `rewarded_offers_per_screen` (data) live offers share a screen scope, the rest stay hidden.
## The service is injected (`configure`); without one it is the AdService autoload.

## Fires after the reward callback ran and the ad closed.
signal granted

## Seconds between two re-checks of `rewarded_ready` while the offer is in the tree.
const RECHECK_INTERVAL_S: float = 1.0
const _CLAIM_META: StringName = &"rewarded_offer_claims"

var placement: StringName = &""
var reward_text: String = ""
var on_reward: Callable = Callable()
## The ads data; tests replace it. Its `rewarded_offers_per_screen` is the screen's limit.
var settings: AdsSettingsDef = AdsSettingsDef.load_default()

var _service: Node = null
var _scope: Node = null
var _claimed_scope: Node = null
var _busy: bool = false
var _done: bool = false
var _since_check_s: float = 0.0

@onready var _button: Button = $OfferButton


func _ready() -> void:
	_button.text = reward_text
	_button.pressed.connect(_on_pressed)
	visible = false
	_claim()
	refresh()


func _exit_tree() -> void:
	_release()


func _process(delta: float) -> void:
	_since_check_s += delta
	if _since_check_s >= RECHECK_INTERVAL_S:
		refresh()


## Sets what the host owns. `service_node` is an AdService (or a fake with the same two methods);
## `scope_node` stands for the screen (default: the top node under the root). Call it before the
## offer enters the tree, or after: it re-checks at once.
func configure(
	service_node: Node,
	placement_id: StringName,
	text: String,
	reward_callable: Callable,
	scope_node: Node = null
) -> void:
	_service = service_node
	placement = placement_id
	reward_text = text
	on_reward = reward_callable
	_scope = scope_node
	if is_node_ready():
		_button.text = reward_text
		_release()
		_claim()
		refresh()


## True while the offer is on screen.
func is_offered() -> bool:
	return visible


## Re-asks the service and shows or hides the offer; the periodic check calls it too.
func refresh() -> void:
	_since_check_s = 0.0
	if _busy:
		return
	visible = _may_offer()


func _may_offer() -> bool:
	if _done or _claimed_scope == null or placement == &"":
		return false
	var svc: Node = _resolve_service()
	return svc != null and bool(svc.call(&"rewarded_ready", placement))


func _on_pressed() -> void:
	if _busy or _done:
		return
	var svc: Node = _resolve_service()
	if svc == null:
		return
	_busy = true
	_button.disabled = true
	var earned: bool = bool(await svc.call(&"show_rewarded", placement, _on_reward_callback))
	_busy = false
	if not is_inside_tree():
		return
	_button.disabled = false
	if earned:
		_done = true
		visible = false
		granted.emit()
	else:
		refresh()


## Runs inside the service's reward callback: the host grants and saves here.
func _on_reward_callback() -> void:
	if on_reward.is_valid():
		on_reward.call()


func _resolve_service() -> Node:
	if _service != null:
		return _service
	var loop: SceneTree = get_tree()
	return loop.root.get_node_or_null("AdService") if loop != null else null


func _find_scope() -> Node:
	if _scope != null:
		return _scope
	var node: Node = self
	while node.get_parent() != null and node.get_parent() != get_tree().root:
		node = node.get_parent()
	return node


## Takes one of the screen's offer slots; stays unclaimed (hidden) when they are all taken.
func _claim() -> void:
	if _claimed_scope != null or not is_inside_tree():
		return
	var scope: Node = _find_scope()
	var count: int = int(scope.get_meta(_CLAIM_META, 0))
	if count >= settings.rewarded_offers_per_screen:
		return
	scope.set_meta(_CLAIM_META, count + 1)
	_claimed_scope = scope


func _release() -> void:
	if _claimed_scope != null and is_instance_valid(_claimed_scope):
		var count: int = int(_claimed_scope.get_meta(_CLAIM_META, 1))
		_claimed_scope.set_meta(_CLAIM_META, maxi(count - 1, 0))
	_claimed_scope = null
