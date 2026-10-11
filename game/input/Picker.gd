class_name Picker
extends RefCounted
## Turns a touch point or a box into unit choices, from a PickSnapshot (ADR 0004 sections 4-5).
## Pure and static. A unit is hit when the point is within its `radius_px` of its centre. Any owner
## but `local_player` is an enemy. Box queries use unit centres and return ascending ids.

const ANY_TYPE: int = -1


## The snapshot index of the unit hit at `pos`, or -1. Without a selection only own units count.
## With one, a hit enemy wins over a hit own unit. Among equals the closest centre wins, and a
## tie goes to the lower id.
static func pick(snap: PickSnapshot, pos: Vector2, local_player: int, has_selection: bool) -> int:
	var best: int = -1
	var best_enemy: bool = false
	var best_d2: float = INF
	for i: int in snap.size():
		var enemy: bool = snap.owners[i] != local_player
		var d2: float = snap.screen_pos[i].distance_squared_to(pos)
		if (enemy and not has_selection) or d2 > snap.radius_px[i] * snap.radius_px[i]:
			continue
		var wins: bool = best < 0 or (enemy and not best_enemy)
		if not wins and enemy == best_enemy:
			wins = d2 < best_d2 or (d2 == best_d2 and snap.ids[i] < snap.ids[best])
		if wins:
			best = i
			best_enemy = enemy
			best_d2 = d2
	return best


## Replaces `out` with the ids of `local_player`'s units whose centres lie in `rect`.
static func own_in_rect(
	snap: PickSnapshot, rect: Rect2, local_player: int, out: PackedInt32Array
) -> void:
	_collect(snap, ANY_TYPE, rect, local_player, out)


## Like own_in_rect, but only units of type `type_index` (a World type index, 0 or more).
static func own_of_type_in_rect(
	snap: PickSnapshot, type_index: int, rect: Rect2, local_player: int, out: PackedInt32Array
) -> void:
	_collect(snap, type_index, rect, local_player, out)


static func _collect(
	snap: PickSnapshot, type_index: int, rect: Rect2, local_player: int, out: PackedInt32Array
) -> void:
	out.clear()
	for i: int in snap.size():
		var wanted: bool = type_index == ANY_TYPE or snap.type_index[i] == type_index
		if snap.owners[i] == local_player and wanted and rect.has_point(snap.screen_pos[i]):
			out.append(snap.ids[i])
	out.sort()
