class_name RewardRelay
extends RefCounted
## The Callable's owner for one RewardedOffer (plan P431): the service holds `fire` as the reward
## callback, so the host's grant still runs when the offer was freed while the ad was open. The
## offer is only a weak reference, told once so it can hide and stop asking.

const AdServiceScript: GDScript = preload("res://game/ads/AdService.gd")

var _on_reward: Callable
var _offer: WeakRef
var _fired: bool = false
## The relay owns itself while an ad may still pay out (a Callable does not keep it alive).
var _keep: RewardRelay = null


func _init(offer: RewardedOffer, on_reward: Callable) -> void:
	_offer = weakref(offer)
	_on_reward = on_reward


## Runs inside the service's reward callback: the offer first (hide, no second watch), then the
## host.
func fire() -> void:
	if _fired:
		return
	_fired = true
	var offer: RewardedOffer = _offer.get_ref() as RewardedOffer
	if offer != null and not offer.note_granted():
		return
	if _on_reward.is_valid():
		_on_reward.call()
	if offer != null and is_instance_valid(offer):
		offer.granted.emit()


## Shows the ad and calls `finished` afterwards (not when the offer was freed meanwhile). After a
## timeout the ad may still open and pay out, so the relay stays until the service's next close.
func run(service: AdServiceScript, ad_placement: StringName, finished: Callable) -> void:
	_keep = self
	await service.show_rewarded(ad_placement, fire)
	if _fired or not is_instance_valid(service):
		_keep = null
	else:
		service.ad_closed.connect(_release, CONNECT_ONE_SHOT)
	if finished.is_valid():
		finished.call()


func _release(_placement: StringName) -> void:
	_keep = null
