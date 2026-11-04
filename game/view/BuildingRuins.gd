class_name BuildingRuins
extends RefCounted
## What becomes of a building that was shown when it died (ADR 0029 section 8, plan P159's hook;
## P165 fills it in with the collapse and the ruin). For now `adopt` does what `BuildingLayer` did
## before: it lays the crater where the building stood and frees its node. The layer hands over the
## tick of the DIED, whether the entry was a site at its last tick and whether the DIED carries the
## cancel flag (`Production.DIED_CANCEL_FLAG_AT`), which are what the collapse will need.

var _sort: WorldSort
var _decals: DecalLayer


func setup(sort: WorldSort, decals: DecalLayer) -> void:
	_sort = sort
	_decals = decals


## Takes over `entry`, a shown building that left the rows in tick `died_tick`. The layer has
## already dropped it from its tables, its shadow and the selection.
func adopt(entry: BuildingLayer.Entry, _died_tick: int, _was_site: bool, _cancelled: bool) -> void:
	_decals.add_crater(entry.node.position, entry.foot * BuildingLayer.CRATER_MILLI_PER_TILE)
	_sort.remove_child(entry.node)
	entry.node.queue_free()


## Whether `snap`'s events hold the DIED of building `id` with the cancel flag set.
static func cancelled(snap: MatchSnapshot, id: int) -> bool:
	var events: PackedInt32Array = snap.events
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] == World.Event.DIED and events[at + 1] == id:
			return events[at + Production.DIED_CANCEL_FLAG_AT] != 0
	return false
