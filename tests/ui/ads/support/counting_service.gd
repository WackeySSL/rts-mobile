extends "res://game/ads/AdService.gd"
## AdService that counts `rewarded_ready` calls (P431 polling test); otherwise the real thing.

var ready_calls: int = 0


func rewarded_ready(placement: StringName) -> bool:
	ready_calls += 1
	return super(placement)
