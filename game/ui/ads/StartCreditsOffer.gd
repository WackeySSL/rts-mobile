class_name StartCreditsOffer
extends RewardedOffer
## The starting-credits offer of the map select (ADR 0039 section 7, plan P433): the generic
## rewarded offer, "+500 credits next match". A tap shows the ad; the service's
## `grant_start_credits_bonus(reward_start_credits)` runs only inside the SDK's reward callback
## (RewardRelay), bound to the service, never to the screen. The grant lands in the ledger's
## `ads` section; this widget writes no `MatchSetup` (MenuFlow takes the bonus at match start,
## once). Once the bonus is pending the button shows the pending text, disabled, and no second ad
## is offered; it clears by itself after the match start took the bonus (the recheck timer and the
## screen's visibility ask the service again). Remove ads does not hide it: rewarded stays. Text
## and amount come from `data/ads_settings.tres`.
## No layout shift (the ad policy forbids it): while it holds a slot the offer keeps its full height
## (the button, invisible and untappable until an ad is ready, plus `banner_gap_dp` below), so an ad
## that loads late moves nothing, START included. A shown button ignores taps for `reward_arm_ms`.
## One exception, decided once per visit when the screen opens: with consent already answered "no
## ads" and no bonus pending, the offer takes no space at all. It never grows or shrinks while the
## screen is visible; a late consent waits for the next visit, and unknown consent keeps the space.
## `granted` (the base's signal) may emit more than once per offer: a grant does not end the offer.

const PLACEMENT: StringName = &"start_credits"

## Milliseconds clock for the arm delay; tests replace it with a fake one.
var now_ms: Callable = Time.get_ticks_msec

var _live: bool = false
var _pending: bool = false
var _armed_at_ms: int = 1 << 60
var _decided: bool = false
var _collapsed: bool = false


func _init() -> void:
	super()
	name = &"StartCreditsOffer"
	var text: String = settings.reward_credits_text % settings.reward_start_credits
	configure(null, PLACEMENT, text, Callable())
	var gap: Control = Control.new()
	gap.name = &"Gap"
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var floor_dp: DpMinSize = DpMinSize.new()
	floor_dp.min_dp = Vector2(0, settings.banner_gap_dp)
	gap.add_child(floor_dp)
	add_child(gap)
	_show(false)


## Uses another AdService than the autoload (tests).
func use_service(service_node: AdServiceScript) -> void:
	configure(service_node, PLACEMENT, reward_text, on_reward, _scope)


## True while the button shows an ad that can be tapped.
func is_offered() -> bool:
	return _live and is_visible_in_tree()


## True while the offer's ad is loading, open or closing (START waits for it).
func is_running() -> bool:
	return _busy


## True while the granted bonus waits for the next match.
func is_pending() -> bool:
	return _pending and is_visible_in_tree()


## The grant is not "done": after it the offer shows the pending state, and a bonus that was taken
## may be earned again. The relay's own once-per-tap guard stops a second callback.
func note_granted() -> bool:
	return true


func _may_offer() -> bool:
	return not _pending_now() and super()


func _pending_now() -> bool:
	var svc: AdServiceScript = _resolve_service()
	return svc != null and svc.pending_start_credits() > 0


func _show(on: bool) -> void:
	var was: bool = _live
	_pending = _claimed_scope != null and _pending_now()
	_decide_visit()
	_live = on and not _pending and not _collapsed
	visible = _claimed_scope != null and not _collapsed
	_button.modulate.a = float(_live or _pending)  # 0 while it only holds its space.
	_button.mouse_filter = Control.MOUSE_FILTER_STOP if _live else Control.MOUSE_FILTER_IGNORE
	_button.focus_mode = Control.FOCUS_ALL if _live else Control.FOCUS_NONE
	if _pending:
		var waiting: int = _resolve_service().pending_start_credits()
		_button.text = (settings.reward_credits_pending_text % waiting).to_upper()
	else:
		_button.text = reward_text.to_upper()
	if _live and not was:
		_armed_at_ms = int(now_ms.call()) + settings.reward_arm_ms


## Giving up the slot (the screen hides, another service) ends the visit.
func _release() -> void:
	super()
	_decided = false


## Once per visit, when the offer takes its slot: collapse for consent that said no.
func _decide_visit() -> void:
	if _claimed_scope == null:
		_decided = false
		_collapsed = false
	elif not _decided:
		_decided = true
		var svc: AdServiceScript = _resolve_service()
		_collapsed = (
			svc != null and svc.consent_known() and not svc.can_request_ads() and not _pending
		)


func _on_pressed() -> void:
	if not _live or int(now_ms.call()) < _armed_at_ms:
		return
	var svc: AdServiceScript = _resolve_service()
	if svc == null:
		return
	on_reward = svc.grant_start_credits_bonus.bind(settings.reward_start_credits)
	super()


## The slot hides itself while this offer is hidden, so the base's parent test would never let the
## offer show: the offer follows the screen (the slot's owner) instead.
func _screen_shown() -> bool:
	var screen: CanvasItem = _find_scope() as CanvasItem
	return is_inside_tree() and (screen == null or screen.is_visible_in_tree())


func _bind_parent() -> void:
	var screen: CanvasItem = _find_scope() as CanvasItem
	if screen != null and not screen.visibility_changed.is_connected(refresh):
		screen.visibility_changed.connect(refresh)


func _unbind_parent() -> void:
	var screen: CanvasItem = _find_scope() as CanvasItem
	if screen != null and screen.visibility_changed.is_connected(refresh):
		screen.visibility_changed.disconnect(refresh)
