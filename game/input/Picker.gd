class_name Picker
extends RefCounted
## Turns a touch point or a box into unit choices, from a PickSnapshot (ADR 0004 sections 4-5).
## Pure and static. A unit is hit when the point is within its `radius_px` of its centre. Any owner
## but `local_player` is an enemy. Box queries use unit centres and return ascending ids. A row
## whose `pickable` entry is 0 (an enemy the fog hides, P47p) is skipped by every query, even at
## distance 0 or inside a box; the index `pick` returns is still the row of the snapshot.
## A building is picked apart, by `pick_building`, on its silhouette (P115b, ADR 0023 section 3).

const _ANY_TYPE: int = -1


## The snapshot index of the unit hit at `pos`, or -1. Without a selection only own units count.
## With one, a hit enemy wins over a hit own unit. Among equals the closest centre wins, and a
## tie goes to the lower id.
static func pick(snap: PickSnapshot, pos: Vector2, local_player: int, has_selection: bool) -> int:
	var best: int = -1
	var best_enemy: bool = false
	var best_d2: float = INF
	var pickable: PackedByteArray = snap.pickable
	var marked: int = pickable.size()  # A row from here on has no entry and is pickable.
	for i: int in snap.size():
		if i < marked and pickable[i] == 0:
			continue
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


## The index in the snapshot's building arrays of the building hit at `pos`, or -1. The caller asks
## after `pick` found no unit, because a unit is hit before a building. The shape is the footprint's
## diamond plus the rectangle between its side corners, from the sprite's top down to the corners'
## y. One under 2 x `min_half` px wide or high (48 dp across, a unit's hit radius twice) becomes
## the box of that size about the middle of its own. Of the buildings hit the one drawn in front
## wins (the larger sort key, then the higher id); with `has_units` (own units selected) a hit
## enemy building wins over an own one, to be attacked. Any owner but `local_player` is an enemy.
static func pick_building(
	snap: PickSnapshot, pos: Vector2, local_player: int, has_units: bool, min_half: float
) -> int:
	var best: int = -1
	var best_enemy: bool = false
	for i: int in snap.building_count():
		if not _in_silhouette(snap, i, pos, min_half):
			continue
		var enemy: bool = snap.building_owners[i] != local_player
		var wins: bool = best < 0
		if not wins:
			wins = enemy if has_units and enemy != best_enemy else _in_front(snap, i, best)
		if wins:
			best = i
			best_enemy = enemy
	return best


## Replaces `out` with the ids of `local_player`'s units whose centres lie in `rect`.
static func own_in_rect(
	snap: PickSnapshot, rect: Rect2, local_player: int, out: PackedInt32Array
) -> void:
	_collect(snap, _ANY_TYPE, rect, local_player, out)


## Like own_in_rect, but only units of type `type_index` (a World type index, 0 or more).
static func own_of_type_in_rect(
	snap: PickSnapshot, type_index: int, rect: Rect2, local_player: int, out: PackedInt32Array
) -> void:
	_collect(snap, type_index, rect, local_player, out)


static func _collect(
	snap: PickSnapshot, type_index: int, rect: Rect2, local_player: int, out: PackedInt32Array
) -> void:
	out.clear()
	var pickable: PackedByteArray = snap.pickable
	var marked: int = pickable.size()
	for i: int in snap.size():
		if i < marked and pickable[i] == 0:
			continue
		var wanted: bool = type_index == _ANY_TYPE or snap.type_index[i] == type_index
		if snap.owners[i] == local_player and wanted and rect.has_point(snap.screen_pos[i]):
			out.append(snap.ids[i])
	out.sort()


static func _in_silhouette(snap: PickSnapshot, i: int, pos: Vector2, min_half: float) -> bool:
	var half: Vector2 = snap.building_half[i]
	var rise: float = maxf(snap.building_rise[i], half.y)
	var at: Vector2 = pos - snap.building_centres[i]
	var width: float = 2.0 * half.x
	var height: float = rise + half.y
	if width < 2.0 * min_half or height < 2.0 * min_half:
		# Too small to hit by hand: the box of at least 48 dp a side round the shape's middle.
		var middle_y: float = 0.5 * (half.y - rise)
		return (
			absf(at.x) <= maxf(half.x, min_half)
			and absf(at.y - middle_y) <= maxf(height * 0.5, min_half)
		)
	if absf(at.x) > half.x:
		return false
	if at.y <= 0.0:
		return at.y >= -rise  # The rectangle, which holds the diamond's upper half.
	return at.y <= half.y * (1.0 - absf(at.x) / half.x)


## Whether building `i` is drawn in front of building `j`.
static func _in_front(snap: PickSnapshot, i: int, j: int) -> bool:
	var keys: PackedFloat32Array = snap.building_keys
	return keys[i] > keys[j] or (keys[i] == keys[j] and snap.building_ids[i] > snap.building_ids[j])
