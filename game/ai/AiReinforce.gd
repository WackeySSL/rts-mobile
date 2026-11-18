class_name AiReinforce
extends RefCounted
## All-in reinforcements as groups (plan row P250e). From the all-in tick every new home unit used
## to join the wave at once and walk across the map alone, to die one by one at the enemy base.
## With `all_in_group_value` set the home squad keeps gathering at the staging point (and defends
## there)
## until its value reaches that, or `all_in_group_ticks` have passed since its first unit waited,
## and then goes to the wave's goal as one group and joins the wave (`AiArmy._fight`). A unit that
## held artillery joins holds from the moment it is in the wave squad (`AiHold`), as before. Off
## (Easy, the frozen files) when both fields are 0.

## Groups sent over the match, for the suites.
var groups: int = 0

var _value: int = 0
var _cap: int = 0
## The tick the home squad first had a unit waiting for the group (-1: none waiting).
var _since: int = -1


static func create(level: AiDifficultyDef) -> AiReinforce:
	var reinforce: AiReinforce = AiReinforce.new()
	reinforce._value = maxi(level.all_in_group_value, 0)
	reinforce._cap = maxi(level.all_in_group_ticks, 0)
	return reinforce


## Whether the home squad (`waiting` units of value `value`) leaves now. Without a threshold every
## unit leaves at once, as before the row.
func ready(tick: int, value: int, waiting: int) -> bool:
	if _value == 0 and _cap == 0:
		return true
	if waiting == 0:
		_since = -1
		return false
	if _since < 0:
		_since = tick
	return (_value > 0 and value >= _value) or (_cap > 0 and tick - _since >= _cap)


## The group was ordered: the next one starts to gather.
func sent() -> void:
	_since = -1
	groups += 1
