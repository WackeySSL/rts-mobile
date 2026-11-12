class_name BuildingOrders
extends RefCounted
## What the command bar's building orders, Mend and Sell, ask of a published snapshot (ADR 0037
## sections 3, 4 and 9, plan P272). Pure statics, no Node. A row's order shows for ONE own complete
## building only: an enemy building is selected for its information alone and never shows a switch.
## The sale's "+N" is `Production.sale_refund`, the sim's own math, so the label never drifts from
## what the sim pays.


## The row of the one own complete building that `ids` holds, -1 for any other selection (nothing,
## two or more, a unit, a site, an enemy building, a row that is dying).
static func target(snap: MatchSnapshot, ids: PackedInt32Array, player: int) -> int:
	if snap == null or ids.size() != 1:
		return -1
	var row: int = snap.index_of(ids[0])
	if row < 0 or snap.owner[row] != player or snap.hp[row] <= 0 or snap.build_left[row] != 0:
		return -1
	return row if _is_building(snap, snap.type_index[row]) else -1


## Whether the building in `row` can be sold: it has a price (the Headquarters, price 0, cannot).
static func can_sell(snap: MatchSnapshot, row: int) -> bool:
	return snap.type_cost[snap.type_index[row]] > 0


## Whether the building's repair switch is on (`cargo` of a row with a footprint).
static func mending(snap: MatchSnapshot, row: int) -> bool:
	return snap.cargo[row] == 1


## Whether switching the repair on can do anything: the building is below full health.
static func can_mend(snap: MatchSnapshot, row: int) -> bool:
	return snap.hp[row] < snap.type_max_hp[snap.type_index[row]]


## What a sale of the building in `row` pays now.
static func refund(snap: MatchSnapshot, row: int) -> int:
	var type: int = snap.type_index[row]
	return Production.sale_refund(
		snap.type_cost[type], snap.sell_refund_percent, snap.hp[row], snap.type_max_hp[type]
	)


## The most any sale can pay (a building of the highest price at full health): the Sell button is
## made as wide as this "+N" needs, so the refund never shifts it.
static func widest_refund(snap: MatchSnapshot) -> int:
	var widest: int = 0
	for type: int in snap.type_cost.size():
		if _is_building(snap, type):
			widest = maxi(
				widest, Production.sale_refund(snap.type_cost[type], snap.sell_refund_percent, 1, 1)
			)
	return widest


## Whether the building in `row` is the player's last production building: the only complete own
## building whose type produces a tab. Selling it loses the match (`Outcome`), so the command bar
## asks first.
static func is_last_producer(snap: MatchSnapshot, row: int, player: int) -> bool:
	if snap.type_produces[snap.type_index[row]] < 0:
		return false
	for other: int in snap.unit_id.size():
		if other == row or snap.owner[other] != player or snap.build_left[other] != 0:
			continue
		if snap.hp[other] > 0 and snap.type_produces[snap.type_index[other]] >= 0:
			return false
	return true


static func _is_building(snap: MatchSnapshot, type: int) -> bool:
	return type >= 0 and type < snap.type_foot_w.size() and snap.type_foot_w[type] > 0
