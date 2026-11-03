class_name PowerConsumers
extends RefCounted
## Which buildings of a published snapshot use power, counted the way `Power.run` counts them (ADR
## 0018 section 4): a building whose type has a negative `type_power`, that is not a construction
## site (`build_left` 0) and that no blackout holds offline (`offline_until` not above the tick).
## The economy card sums these rows and the bar layer marks them on low power (plan P89), so the
## two never disagree on which buildings count. Reads the snapshot only.


## Whether row `row` of `snap` is a building that uses power now. A unit has no power entry.
static func is_consumer(snap: MatchSnapshot, row: int) -> bool:
	var type: int = snap.type_index[row]
	return (
		type < snap.type_power.size()
		and snap.type_power[type] < 0
		and snap.build_left[row] == 0
		and snap.offline_until[row] <= snap.tick
	)
