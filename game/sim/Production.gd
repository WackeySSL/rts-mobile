class_name Production
extends RefCounted
## The PRODUCTION phase and its Commands (ADR 0017 section 5, ADR 0018 section 5): the queues
## advance, finished units spawn at their exit and leave for the rally point, finished structures
## turn ready. Since plan row P73 the two unit tabs, INFANTRY and VEHICLES, work: QUEUE pays and
## joins the queue, CANCEL refunds, `run` advances each queue's head and ProductionSpawn puts the
## finished unit on the map. The STRUCTURES tab (a ready structure, PLACE, the free harvester) is
## plan row P73b's: QUEUE refuses a structure, `run` leaves that queue alone and `apply_place`
## still refuses, so a PLACE is dropped and counted.
##
## A queue is identified by `queue = player * TABS + tab`. Its items are the `queue_count[queue]`
## type indexes in `queue_type` from `queue * queue_slots` on, the head first; a slot past the count
## holds -1. `queue_progress[queue]` is the head's progress in hundredths of a tick: the head is
## done at `type_build_ticks * PROGRESS_PER_TICK`. Players are never skipped for being defeated:
## the defeat rules (plan row P76) decide whether a defeated player's queues go on.

## Hundredths of a tick: the resolution of `queue_progress` (a structural unit, like a tile's
## 1,000 milli). A head gains this much per tick (ADR 0018 section 5; plan row P74 scales it on
## low power).
const PROGRESS_PER_TICK: int = 100

## One PRODUCTION step: the head of every unit queue that has a producer gains PROGRESS_PER_TICK
## (never past its goal) and, once done, spawns (ProductionSpawn.spawn) and leaves the queue; one
## that cannot spawn yet waits at 100 %. Players ascending, then tabs. A queue without a producer
## waits. The loop runs over the arrays as sized, so a hand-built World whose player_count was
## raised after prepare() has no queue for the late players.
@warning_ignore("integer_division")
static func run(world: World) -> void:
	var counts: PackedInt32Array = world.queue_count
	var progress: PackedInt32Array = world.queue_progress
	var items: PackedInt32Array = world.queue_type
	var build_ticks: PackedInt32Array = world.type_build_ticks
	var slots: int = world.queue_slots
	for queue: int in range(World.TABS, counts.size()):
		var tab: int = queue % World.TABS
		if counts[queue] == 0 or not _unit_tab(tab):
			continue
		var player: int = queue / World.TABS
		var producer: int = producer_row(world, player, tab)
		if producer < 0:
			continue
		var head: int = items[queue * slots]
		var done: int = build_ticks[head] * PROGRESS_PER_TICK
		progress[queue] = mini(progress[queue] + PROGRESS_PER_TICK, done)
		if progress[queue] >= done and ProductionSpawn.spawn(world, player, head, producer):
			remove_item(world, queue, 0)
			world.stat_built[player] += 1


## QUEUE `[type_index]`: true when the item joined the player's queue and its cost was paid. The
## type needs a unit tab, the player a producer of that tab (producer_row) and a row of the type's
## requirement (if it has one), the queue room and at least the type's cost in credits.
static func apply_queue(world: World, command: Command) -> bool:
	if command.payload.size() != 1:
		return false
	var type: int = command.payload[0]
	if type < 0 or type >= world.type_tab.size():
		return false
	var tab: int = world.type_tab[type]
	var player: int = command.player_id
	if not _unit_tab(tab) or producer_row(world, player, tab) < 0:
		return false
	var queue: int = player * World.TABS + tab
	var count: int = world.queue_count[queue]
	var cost: int = world.type_cost[type]
	if (
		count >= world.queue_slots
		or world.credits[player] < cost
		or not _owns(world, player, world.type_requires[type])
	):
		return false
	world.credits[player] -= cost
	world.queue_type[queue * world.queue_slots + count] = type
	world.queue_count[queue] = count + 1
	return true


## CANCEL `[tab, slot]`: true when the item in that slot of the player's queue left it and its
## whole cost came back. The later items move up; cancelling the head starts the next one at 0.
static func apply_cancel(world: World, command: Command) -> bool:
	if command.payload.size() != 2:
		return false
	var tab: int = command.payload[0]
	var slot: int = command.payload[1]
	if tab < 0 or tab >= World.TABS:
		return false
	var player: int = command.player_id
	var queue: int = player * World.TABS + tab
	if slot < 0 or slot >= world.queue_count[queue]:
		return false
	var type: int = world.queue_type[queue * world.queue_slots + slot]
	world.credits[player] += world.type_cost[type]
	remove_item(world, queue, slot)
	return true


## PLACE: true when the ready head of the STRUCTURES queue stands on the ground of the point. Plan
## row P73b; until then it refuses.
static func apply_place(_world: World, _command: Command) -> bool:
	return false


## Takes the item in `slot` out of `queue` and moves the later ones up, leaving -1 in the freed last
## slot. Removing the head (slot 0) resets the progress, so the next item starts at 0. The credits
## and the stats are the caller's.
static func remove_item(world: World, queue: int, slot: int) -> void:
	var items: PackedInt32Array = world.queue_type
	var base: int = queue * world.queue_slots
	var last: int = world.queue_count[queue] - 1
	for at: int in range(base + slot, base + last):
		items[at] = items[at + 1]
	items[base + last] = -1
	world.queue_count[queue] = last
	if slot == 0:
		world.queue_progress[queue] = 0


## The row of the player's primary producer of `tab` (ADR 0018 section 5): the lowest-id building
## of that player whose type produces the tab; -1 when there is none. The derived building list is
## brought up to date first (a no-op when `rows_version` has not moved since ECONOMY rebuilt it).
static func producer_row(world: World, player: int, tab: int) -> int:
	Buildings.rebuild_lists(world)
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	var produces: PackedInt32Array = world.type_produces
	var buildings: PackedInt32Array = world.building_rows
	for row: int in buildings:
		if owners[row] == player and produces[types[row]] == tab:
			return row
	return -1


## Whether `tab` is one of the two unit tabs; the STRUCTURES tab is plan row P73b's.
static func _unit_tab(tab: int) -> bool:
	return tab == World.Tab.INFANTRY or tab == World.Tab.VEHICLES


## Whether the player owns a row of `type` (-1 = no requirement).
static func _owns(world: World, player: int, type: int) -> bool:
	if type < 0:
		return true
	var owners: PackedInt32Array = world.owner
	var types: PackedInt32Array = world.type_index
	for row: int in owners.size():
		if owners[row] == player and types[row] == type:
			return true
	return false
