class_name DoubleXpOffer
extends RewardedOffer
## The Double XP offer of the result screen (ADR 0039 section 7, plan P432): the generic rewarded
## offer for the award of the match that just ended. It shows only while an ad is loaded AND the
## screen holds an award that can still take the bonus (a real id, bonus not applied yet), so a
## lesson, an unscored match, a re-show or a second award never offers it twice. The tap shows the
## ad; `Progression.apply_bonus(award_id, reward_xp_multiplier)` runs only inside the SDK's reward
## callback (RewardRelay), bound to the Progression autoload, never to the screen. Remove ads
## does not hide it: rewarded stays. The text and the multiplier come from `data/ads_settings.tres`.

const PLACEMENT: StringName = &"double_xp"
const ProgressionScript: GDScript = preload("res://game/meta/progression_service.gd")

var _award: XpAward = null


func _init() -> void:
	super()
	name = &"DoubleXpOffer"
	configure(null, PLACEMENT, settings.reward_xp_text % settings.reward_xp_multiplier, Callable())


## Hands the offer the award of the shown match (null: none yet, a late score calls it again).
## The same award again changes nothing; a running ad keeps its callback.
func set_award(award: XpAward, source: ProgressionScript) -> void:
	if award != null and (_award == null or _award.id != award.id) and not _busy:
		on_reward = source.apply_bonus.bind(award.id, settings.reward_xp_multiplier)
	_award = award
	refresh()


## Uses another AdService than the autoload (tests); keeps the award's callback.
func use_service(service_node: AdServiceScript) -> void:
	configure(service_node, PLACEMENT, reward_text, on_reward, _scope)


func _may_offer() -> bool:
	return _award != null and _award.id != &"" and not _award.bonus_applied and super()


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
