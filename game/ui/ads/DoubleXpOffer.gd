class_name DoubleXpOffer
extends RewardedOffer
## The Double XP offer of the result screen (ADR 0039 section 7, plan P432): the generic rewarded
## offer for the award of the match that just ended. It shows only while an ad is loaded AND the
## screen holds an award that can still take the bonus (a real id, bonus not applied yet), so a
## lesson, an unscored match, a re-show or a second award never offers it twice. The tap shows the
## ad; `Progression.apply_bonus(award_id, reward_xp_multiplier)` runs only inside the SDK's reward
## callback (RewardRelay), bound to the Progression autoload, never to the screen. Remove ads
## does not hide it: rewarded stays. The text and the multiplier come from `data/ads_settings.tres`.
## No layout shift under the finger (the ad policy forbids it): while the screen holds such an
## award the offer keeps its full height (the button, invisible and untappable until an ad is ready,
## and the gap of
## `banner_gap_dp` below it), so an ad that loads late, or the recheck timer, moves nothing. Only
## the grant (the player's own action) collapses it. A shown button ignores taps for
## `reward_arm_ms`, so a tap carried over from the match starts no ad.
## The same holds while the screen's score is still pending (`set_award(null, source, true)`): the
## space is reserved, so a late award that can take the bonus turns it into the offer with nothing
## moving, and one that cannot (no id, 0 XP, applied) collapses it, where no button ever appears.

const PLACEMENT: StringName = &"double_xp"
const ProgressionScript: GDScript = preload("res://game/meta/progression_service.gd")

## Milliseconds clock for the arm delay; tests replace it with a fake one.
var now_ms: Callable = Time.get_ticks_msec

var _award: XpAward = null
var _source: ProgressionScript = null
var _bound_source: ProgressionScript = null
var _pending: bool = false
var _bound_id: StringName = &""
var _live: bool = false
var _armed_at_ms: int = 1 << 60


func _init() -> void:
	super()
	name = &"DoubleXpOffer"
	configure(null, PLACEMENT, settings.reward_xp_text % settings.reward_xp_multiplier, Callable())
	var gap: Control = Control.new()
	gap.name = &"Gap"
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var floor_dp: DpMinSize = DpMinSize.new()
	floor_dp.min_dp = Vector2(0, settings.banner_gap_dp)
	gap.add_child(floor_dp)
	add_child(gap)
	_show(false)


## Hands the offer the award of the shown match (null: none yet, a late score calls it again).
## `pending` is true while the score may still land: the space stays reserved. The same award again
## changes nothing; a running ad keeps its callback, and the callback follows the current award
## (or source) once the ad is over.
func set_award(award: XpAward, source: ProgressionScript, pending: bool = false) -> void:
	_award = award
	_source = source
	_pending = pending
	_rebind()
	refresh()


## Uses another AdService than the autoload (tests); keeps the award's callback.
func use_service(service_node: AdServiceScript) -> void:
	configure(service_node, PLACEMENT, reward_text, on_reward, _scope)


## True while the screen's award can still take the bonus.
func _takes_bonus() -> bool:
	return _award != null and _award.id != &"" and _award.base_xp > 0 and not _award.bonus_applied


func _may_offer() -> bool:
	return _takes_bonus() and super()


## True while the button shows (an ad is ready), not while the offer only holds its space.
func is_offered() -> bool:
	return _live and is_visible_in_tree()


## The offer stays laid out while it could still show; only the button's look and touch follow the
## ad.
func _show(on: bool) -> void:
	var was: bool = _live
	_live = on
	var keeps: bool = (
		(_takes_bonus() or (_pending and _award == null)) and not _done and _claimed_scope != null
	)
	visible = on or keeps
	_button.modulate.a = float(on)  # Not a colour: 1 while shown, 0 while it only holds space.
	_button.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	_button.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	if on and not was:
		_armed_at_ms = int(now_ms.call()) + settings.reward_arm_ms


func _on_pressed() -> void:
	if not _live or int(now_ms.call()) < _armed_at_ms:
		return
	super()


func _on_show_finished() -> void:
	super()
	_rebind()


func _rebind() -> void:
	if _busy or _award == null or _source == null:
		return
	if _award.id == _bound_id and _source == _bound_source:
		return
	_bound_id = _award.id
	_bound_source = _source
	on_reward = _source.apply_bonus.bind(_award.id, settings.reward_xp_multiplier)


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
