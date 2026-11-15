class_name RewardRelay
extends RefCounted
## The Callable's owner for one RewardedOffer (plan P431): the service holds `fire` as the reward
## callback, so the host's grant still runs when the offer was freed while the ad was open. The
## offer is only a weak reference, told once so it can hide and stop asking.

const AdServiceScript: GDScript = preload("res://game/ads/AdService.gd")

var _on_reward: Callable
var _offer: WeakRef
var _fired: bool = false


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


## Shows the ad and calls `finished` afterwards (not when the offer was freed meanwhile). The
## callback handed to the service is a lambda that captures the relay, so the relay lives exactly
## as long as the service's run may still call it (after a timeout the ad may still pay out) and no
## longer: nothing holds it for itself, so nothing outlives the service.
func run(service: AdServiceScript, ad_placement: StringName, finished: Callable) -> void:
	await service.show_rewarded(ad_placement, _callback())
	if finished.is_valid():
		finished.call()


## Built outside the coroutine: a lambda made in a function that awaits would hold its state.
func _callback() -> Callable:
	var relay: RewardRelay = self
	return func() -> void: relay.fire()
