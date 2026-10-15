class_name SelectionModel
extends RefCounted
## The player's selected unit ids and control groups 1-3 (ADR 0004 section 5). It reads no World
## and sends no Command. `selected` is sorted and unique, so a Command can carry it as it is.
## `changed` fires once per real change of `selected`. Group changes and a set to the ids already
## selected do not fire it.

signal changed

const GROUP_COUNT: int = 3

var selected: PackedInt32Array = PackedInt32Array()
var _groups: Dictionary[int, PackedInt32Array] = {}  ## Slot -> ids. Only slots 1-3 get a key.


## Selects `ids` (any order, duplicates allowed). The caller's array is not changed.
func set_ids(ids: PackedInt32Array) -> void:
	var sorted: PackedInt32Array = ids.duplicate()
	sorted.sort()
	var unique: PackedInt32Array = PackedInt32Array()
	for id: int in sorted:
		if unique.is_empty() or unique[-1] != id:
			unique.append(id)
	if unique == selected:
		return
	selected = unique
	changed.emit()


func clear() -> void:
	set_ids(PackedInt32Array())


## Takes the units `ids` (any order, ids that are not here are ignored) out of the selection and
## out of groups 1-3, as when they die. `changed` fires once, after the groups are updated too, and
## only when the selection lost a unit.
func remove_ids(ids: PackedInt32Array) -> void:
	if ids.is_empty():
		return
	var gone: PackedInt32Array = ids.duplicate()
	gone.sort()
	for slot: int in _groups.keys():
		_groups[slot] = _without(_groups[slot], gone)
	var kept: PackedInt32Array = _without(selected, gone)
	if kept.size() != selected.size():
		selected = kept
		changed.emit()


func is_selected(id: int) -> bool:
	var at: int = selected.bsearch(id)
	return at < selected.size() and selected[at] == id


## A copy of the ids in group `slot` (1-3), empty for any other slot.
func group(slot: int) -> PackedInt32Array:
	var ids: PackedInt32Array = _groups.get(slot, PackedInt32Array())
	return ids.duplicate()


## Stores the current selection in group `slot`, even when it is empty (that empties the group).
func assign_group(slot: int) -> void:
	if slot >= 1 and slot <= GROUP_COUNT:
		_groups[slot] = selected.duplicate()


## Selects group `slot`. False, with the selection unchanged, when the group is empty.
func recall_group(slot: int) -> bool:
	var ids: PackedInt32Array = group(slot)
	if ids.is_empty():
		return false
	set_ids(ids)
	return true


## `list` without the ids in `gone` (sorted), in the same order.
static func _without(list: PackedInt32Array, gone: PackedInt32Array) -> PackedInt32Array:
	var kept: PackedInt32Array = PackedInt32Array()
	for id: int in list:
		var at: int = gone.bsearch(id)
		if at == gone.size() or gone[at] != id:
			kept.append(id)
	return kept
