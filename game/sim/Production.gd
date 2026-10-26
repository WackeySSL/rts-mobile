class_name Production
extends RefCounted
## The PRODUCTION phase and its Commands (ADR 0017 section 5, ADR 0018 section 5): the queues
## advance, finished units spawn at their exit and leave for the rally point, finished structures
## turn ready. QUEUE pays and joins the queue of the item's tab, CANCEL refunds, `run` advances each
## queue's head and ProductionSpawn puts a finished unit on the map. A finished structure (the
## STRUCTURES tab, plan row P73b) is not spawned: its head stops at 100 % and waits, with no state
## of its own ("ready" is progress at the goal), until PLACE puts it on the map or CANCEL takes it
## out; PLACE builds it complete through `World.add_building` and ProductionSpawn gives a refinery
## its free harvester.
##
## A queue is identified by `queue = player * TABS + tab`. Its items are the `queue_count[queue]`
## type indexes in `queue_type` from `queue * queue_slots` on, the head first; a slot past the count
## holds -1. `queue_progress[queue]` is the head's progress in hundredths of a tick: the head is
## done at `type_build_ticks * PROGRESS_PER_TICK`. The queues of a defeated player (`defeated_tick`
## above 0, plan row P76) stop where they are: no progress and no spawn, whatever producers the
## player still owns (a surrender leaves them), and nothing is refunded.

## Hundredths of a tick: the resolution of `queue_progress` (a structural unit, like a tile's
## 1,000 milli). A head gains this much per tick (ADR 0018 section 5), or `low_power_percent` of it
## while its player is on low power (`Power.scaled`, ADR 0018 section 4).
const PROGRESS_PER_TICK: int = 100

## One PRODUCTION step: the head of every queue that has a producer gains PROGRESS_PER_TICK, or
## `low_power_percent` of it on low power (every tab, STRUCTURES included), never past its goal. A
## done unit spawns (ProductionSpawn.spawn) and leaves the queue; one that cannot spawn yet waits at
## 100 %, and so does a done structure, until PLACE or CANCEL. Players ascending, then tabs. A queue
## without a producer waits, and so does every queue of a defeated player. The loop runs over the
## arrays as sized, so a hand-built World whose player_count was raised after prepare() has no queue
## for the late players.
@warning_ignore("integer_division")
static func run(world: World) -> void:
	var defeated: PackedInt32Array = world.defeated_tick
	var counts: PackedInt32Array = world.queue_count
	var progress: PackedInt32Array = world.queue_progress
	var items: PackedInt32Array = world.queue_type
	var build_ticks: PackedInt32Array = world.type_build_ticks
	var slots: int = world.queue_slots
	for queue: int in range(World.TABS, counts.size()):
		var tab: int = queue % World.TABS
		if counts[queue] == 0:
			continue
		var player: int = queue / World.TABS
		if defeated[player] != 0:
			continue
		var producer: int = producer_row(world, player, tab)
		if producer < 0:
			continue
		var head: int = items[queue * slots]
		var done: int = build_ticks[head] * PROGRESS_PER_TICK
		var step: int = Power.scaled(world, player, PROGRESS_PER_TICK)  # Less on low power.
		progress[queue] = mini(progress[queue] + step, done)
		if (
			tab != World.Tab.STRUCTURES
			and progress[queue] >= done
			and ProductionSpawn.spawn(world, player, head, producer)
		):
			remove_item(world, queue, 0)
			world.stat_built[player] += 1


## QUEUE `[type_index]`: true when the item joined the player's queue and its cost was paid. The
## type needs a tab (a structure's too), the player a producer of that tab (producer_row) whose
## faction may queue it (`_faction_allows`) and a row of the type's requirement (if it has one), the
## queue room and at least the type's cost in credits.
static func apply_queue(world: World, command: Command) -> bool:
	if command.payload.size() != 1:
		return false
	var type: int = command.payload[0]
	if type < 0 or type >= world.type_tab.size():
		return false
	var tab: int = world.type_tab[type]
	var player: int = command.player_id
	if tab < 0 or tab >= World.TABS:
		return false
	var producer: int = producer_row(world, player, tab)
	if producer < 0 or not _faction_allows(world, type, producer):
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


## PLACE: true when the player's ready STRUCTURES head was built at the point (ADR 0018 section 5).
## The payload is empty and the head is ready (its progress at the goal; a producer is not asked
## for, so a structure finished before its Headquarters died can still be placed). The footprint's
## origin is the tile that holds the point, and `Placement.reason` must say OK: a failing reason
## drops the command and leaves the head ready. Then the building comes complete
## (`World.add_building`, which a full row table refuses), the head leaves the queue, `stat_built`
## counts it and a refinery gets its free harvester (ProductionSpawn.spawn_free). The cost was paid
## when the item was queued, so the credits do not move. Event cadence: one `PlacementInput` per
## call.
@warning_ignore("integer_division")
static func apply_place(world: World, command: Command) -> bool:
	if not command.payload.is_empty():
		return false
	var player: int = command.player_id
	var queue: int = player * World.TABS + World.Tab.STRUCTURES
	if world.queue_count[queue] == 0:
		return false
	var head: int = world.queue_type[queue * world.queue_slots]
	if world.queue_progress[queue] < world.type_build_ticks[head] * PROGRESS_PER_TICK:
		return false
	# A negative point is outside the map; `/` would truncate it to tile 0.
	var col: int = command.target_x / World.MILLI_PER_TILE if command.target_x >= 0 else -1
	var line: int = command.target_y / World.MILLI_PER_TILE if command.target_y >= 0 else -1
	var input: PlacementInput = PlacementInput.of_world(world)
	if Placement.reason(input, player, head, col, line) != Placement.Reason.OK:
		return false
	var id: int = world.add_building(player, head, col, line)
	if id == 0:
		return false
	remove_item(world, queue, 0)
	world.stat_built[player] += 1
	ProductionSpawn.spawn_free(world, world.index_of(id))
	return true


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


## The producer-faction rule (ADR 0023 section 6): a type with no faction (-1) is queued at any
## producer; one with a faction only at a producer of that faction, so a producer with no faction
## queues only the types with none. A player's faction is the faction of what it owns: no state.
static func _faction_allows(world: World, type: int, producer: int) -> bool:
	var faction: int = world.type_faction[type]
	return faction < 0 or faction == world.type_faction[world.type_index[producer]]


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
