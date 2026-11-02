extends GdUnitTestSuite
## PLACE with a type (plan row P128, ADR 0026 section 2): `PLACE [type_index]` takes the whole price
## at once and puts the building on the map as a site (`build_left` = the type's build time in
## hundredths of a tick, hit points at `construct_start_hp_percent`, its tiles blocked), and every
## failed rule drops the command, counts it and pays nothing. The old path (an empty payload: place
## the ready head of the STRUCTURES queue) works beside it, unchanged, until P131. `site_rig.gd` has
## the world; every cost, tick count and hit point is read from the World's tables.

const SiteRig: GDScript = preload("res://tests/sim/support/site_rig.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const STRUCTURES: int = World.Tab.STRUCTURES


## One tick with `command`: it is dropped and counted, and neither the credits, the rows nor the
## sites (which a case may have made by hand) change.
func _assert_dropped(label: String, made: World, command: Command) -> void:
	var player: int = command.player_id
	var credits: int = made.credits[player]
	var rows: int = made.unit_count()
	var dropped: int = made.dropped_commands
	var before: Array[int] = SiteRig.sites(made)
	SiteRig.step(made, [command])
	assert_int(made.dropped_commands).override_failure_message(label).is_equal(dropped + 1)
	assert_int(made.credits[player]).override_failure_message(label + ": credits").is_equal(credits)
	assert_int(made.unit_count()).override_failure_message(label + ": rows").is_equal(rows)
	assert_array(SiteRig.sites(made)).override_failure_message(label + ": sites").is_equal(before)


## One tick with `command`: it is applied (not counted as dropped) and the price left the credits.
func _assert_started(label: String, made: World, command: Command, price: int) -> void:
	var player: int = command.player_id
	var credits: int = made.credits[player]
	var rows: int = made.unit_count()
	var dropped: int = made.dropped_commands
	SiteRig.step(made, [command])
	assert_int(made.dropped_commands).override_failure_message(label).is_equal(dropped)
	assert_int(made.credits[player]).override_failure_message(label + ": credits").is_equal(
		credits - price
	)
	assert_int(made.unit_count()).override_failure_message(label + ": rows").is_equal(rows + 1)
	assert_int(SiteRig.sites(made).size()).override_failure_message(label + ": sites").is_equal(1)


func test_the_factory_takes_the_type_last_and_builds_the_old_payload_without_it() -> void:
	var old: Command = Command.place(1, 6700, 5300)
	assert_array([old.type, old.player_id, old.target_x, old.target_y]).is_equal(
		[Command.Type.PLACE, 1, 6700, 5300]
	)
	assert_array(old.payload).is_empty()
	assert_array(Command.place(1, 6700, 5300, -1).payload).is_empty()
	var typed: Command = Command.place(2, 100, 200, 7)
	assert_array([typed.type, typed.player_id, typed.target_x, typed.target_y]).is_equal(
		[Command.Type.PLACE, 2, 100, 200]
	)
	assert_array(typed.payload).is_equal([7])
	assert_array(Command.place(1, 0, 0, 0).payload).is_equal([0])
	# The payload is already encoded (ADR 0017 section 4): the replay log carries the type.
	var log: PackedInt32Array = PackedInt32Array()
	typed.tick = 12
	typed.encode(log)
	var back: Command = Command.new()
	assert_int(Command.decode(log, 0, back)).is_equal(log.size())
	assert_array([back.type, back.tick, back.target_x, back.target_y]).is_equal(
		[Command.Type.PLACE, 12, 100, 200]
	)
	assert_array(back.payload).is_equal([7])


## The state PLACE leaves, before the same tick's PRODUCTION: the whole price is gone, the row is
## there with its work and its starting hit points, and its tiles block every class.
@warning_ignore("integer_division")
func test_a_place_with_a_type_pays_the_whole_price_and_puts_a_site_on_the_map() -> void:
	var made: World = SiteRig.world()
	var plant: int = SiteRig.type_of(made, "power_plant")
	var credits: int = made.credits[1]
	var rows: int = made.unit_count()
	var open: Array[int] = Worlds.costs_at(made, 5 * SiteRig.COLS + 6)
	assert_array(open).is_equal([10, 10, 10])
	assert_bool(SiteRig.apply(made, SiteRig.place(made, "power_plant", SiteRig.SPOT))).is_true()
	assert_int(made.credits[1]).is_equal(credits - SiteRig.cost(made, "power_plant"))
	assert_int(made.unit_count()).is_equal(rows + 1)
	var row: int = SiteRig.last(made)
	assert_array([made.owner[row], made.type_index[row]]).is_equal([1, plant])
	assert_int(made.build_left[row]).is_equal(SiteRig.done(made, "power_plant"))
	var start: int = SiteRig.hit_points(made, "power_plant") * made.construct_start_hp_percent / 100
	assert_int(made.hp[row]).is_equal(start)
	assert_bool(start > 0 and start < SiteRig.hit_points(made, "power_plant")).is_true()
	assert_vector(made.footprint_origin(row)).is_equal(SiteRig.SPOT)
	for cell: int in [5 * SiteRig.COLS + 6, 5 * SiteRig.COLS + 7, 6 * SiteRig.COLS + 6]:
		assert_array(Worlds.costs_at(made, cell)).is_equal([0, 0, 0])
	assert_array(SiteRig.sites(made)).is_equal([row])
	# Nothing else moved: no queue, no count, no refusal, no strike charge.
	assert_array([made.stat_built[1], made.dropped_commands, made.ready_tick[row]]).is_equal(
		[0, 0, 0]
	)
	assert_int(made.queue_count[1 * World.TABS + STRUCTURES]).is_equal(0)


## At least one hit point whatever the percent says: a type with 5 hit points at 10 % starts on 1.
@warning_ignore("integer_division")
func test_the_starting_hit_points_are_the_percent_of_the_maximum_and_at_least_one() -> void:
	var made: World = SiteRig.world()
	var plant: int = SiteRig.type_of(made, "power_plant")
	made.type_max_hp[plant] = 5
	assert_bool(SiteRig.apply(made, SiteRig.place(made, "power_plant", SiteRig.SPOT))).is_true()
	assert_int(made.hp[SiteRig.last(made)]).is_equal(1)
	var other: World = SiteRig.world()
	other.construct_start_hp_percent = 35
	assert_bool(SiteRig.apply(other, SiteRig.place(other, "power_plant", SiteRig.SPOT))).is_true()
	assert_int(other.hp[SiteRig.last(other)]).is_equal(
		SiteRig.hit_points(other, "power_plant") * 35 / 100
	)


## Through the tick: COMMANDS takes the price and PRODUCTION already gives the site its first step.
func test_in_a_tick_the_price_leaves_in_commands_and_the_site_gains_its_first_step() -> void:
	var made: World = SiteRig.world()
	var credits: int = made.credits[1]
	SiteRig.step(made, [SiteRig.place(made, "power_plant", SiteRig.SPOT)])
	var row: int = SiteRig.last(made)
	assert_int(made.credits[1]).is_equal(credits - SiteRig.cost(made, "power_plant"))
	assert_int(made.build_left[row]).is_equal(
		SiteRig.done(made, "power_plant") - Production.PROGRESS_PER_TICK
	)
	assert_int(made.stat_built[1]).is_equal(0)
	assert_bool(made.building_rows.has(row)).is_true()
	assert_int(made.dropped_commands).is_equal(0)


func test_a_type_that_is_not_a_structure_or_not_a_type_is_dropped() -> void:
	var made: World = SiteRig.world()
	# A unit (infantry tab), a harvester (vehicles tab), a building with no tab, and types that do
	# not exist.
	for id: String in ["rifle_squad", "harvester", "headquarters", "renew_hq"]:
		_assert_dropped(id, made, SiteRig.place(made, id, SiteRig.SPOT))
	var past: int = made.type_tab.size()
	for type: int in [-2, past, past + 40]:
		_assert_dropped("type %d" % type, made, Command.place(1, 6700, 5300, type))
	var two: Command = Command.place(1, 6700, 5300, SiteRig.type_of(made, "power_plant"))
	two.payload.append(0)
	_assert_dropped("two payload ints", made, two)


## The tab rule alone: each type below passes every other rule (a build time, the faction, no
## requirement, a price the credits cover, the ground and the reach), so only its tab drops it. The
## controls put it on the Structures tab and it starts.
func test_only_the_tab_drops_a_type_that_passes_every_other_rule() -> void:
	var made: World = SiteRig.world()
	SiteRig.fast(made, "headquarters", 5)
	var hq: int = SiteRig.type_of(made, "headquarters")  # Tab -1, price 0, fossil, no requirement.
	assert_int(made.type_tab[hq]).is_equal(-1)
	_assert_dropped("no tab", made, SiteRig.place(made, "headquarters", SiteRig.WIDE))
	made.type_tab[hq] = World.Tab.STRUCTURES
	_assert_started(
		"control: the Structures tab", made, SiteRig.place(made, "headquarters", SiteRig.WIDE), 0
	)
	var other: World = SiteRig.world()
	var plant: int = SiteRig.type_of(other, "power_plant")
	for tab: int in [World.Tab.INFANTRY, World.Tab.VEHICLES]:
		other.type_tab[plant] = tab
		_assert_dropped("tab %d" % tab, other, SiteRig.place(other, "power_plant", SiteRig.SPOT))
	other.type_tab[plant] = World.Tab.STRUCTURES
	_assert_started(
		"control: the plant on the Structures tab",
		other,
		SiteRig.place(other, "power_plant", SiteRig.SPOT),
		SiteRig.cost(other, "power_plant")
	)


func test_a_structures_type_with_no_build_time_is_dropped() -> void:
	var made: World = SiteRig.world()
	SiteRig.fast(made, "power_plant", 0)
	_assert_dropped("build time 0", made, SiteRig.place(made, "power_plant", SiteRig.SPOT))
	SiteRig.fast(made, "power_plant", -3)
	_assert_dropped("build time -3", made, SiteRig.place(made, "power_plant", SiteRig.SPOT))
	# One tick is the least: the site is complete in the same step (COMMANDS places it, PRODUCTION
	# gives it its one step), so it is a finished building and not a site afterwards.
	SiteRig.fast(made, "power_plant", 1)
	var credits: int = made.credits[1]
	SiteRig.step(made, [SiteRig.place(made, "power_plant", SiteRig.SPOT)])
	var row: int = SiteRig.last(made)
	assert_int(made.credits[1]).is_equal(credits - SiteRig.cost(made, "power_plant"))
	assert_array([made.build_left[row], made.stat_built[1], made.dropped_commands]).is_equal(
		[0, 1, 2]
	)


## The producer: complete, not blacked out, and of a faction that allows the type. A blacked-out
## Headquarters starts no site until the stamp that reaches `offline_until`.
func test_the_producer_must_be_complete_online_and_of_the_types_faction() -> void:
	var unfinished: World = SiteRig.world()
	SiteRig.unfinish(unfinished, unfinished.index_of(SiteRig.HQ))
	_assert_dropped(
		"headquarters is a site", unfinished, SiteRig.place(unfinished, "power_plant", SiteRig.SPOT)
	)
	var out: World = SiteRig.world()
	var hq: int = out.index_of(SiteRig.HQ)
	out.offline_until[hq] = out.tick + 2  # Above the stamp (tick + 1): still blacked out.
	_assert_dropped("blacked out", out, SiteRig.place(out, "power_plant", SiteRig.SPOT))
	out.offline_until[hq] = out.tick + 1  # Equal to the stamp: back.
	_assert_started(
		"back at the stamp",
		out,
		SiteRig.place(out, "power_plant", SiteRig.SPOT),
		SiteRig.cost(out, "power_plant")
	)
	# Player 1 owns a renew headquarters as well (so the requirement of a Wind Park is met), but
	# its STRUCTURES producer is the lowest id: the fossil headquarters, whose faction differs.
	var faction: World = SiteRig.world()
	faction.add_building(1, SiteRig.type_of(faction, "renew_hq"), 8, 12)
	_assert_dropped(
		"a renew type at a fossil headquarters",
		faction,
		SiteRig.place(faction, "renew_power", SiteRig.SPOT, 1)
	)
	faction.type_faction[SiteRig.type_of(faction, "renew_power")] = -1  # No faction: any producer.
	_assert_started(
		"a type with no faction",
		faction,
		SiteRig.place(faction, "renew_power", SiteRig.SPOT, 1),
		SiteRig.cost(faction, "renew_power")
	)
	var renew: World = SiteRig.world()
	_assert_started(
		"a renew type at a renew headquarters",
		renew,
		SiteRig.place(renew, "renew_power", SiteRig.SPOT_2, 2),
		SiteRig.cost(renew, "renew_power")
	)


func test_a_player_with_no_structures_producer_starts_no_site() -> void:
	var made: World = SiteRig.world()
	made.hp[made.index_of(SiteRig.HQ)] = 0
	SiteRig.step(made)
	assert_int(made.index_of(SiteRig.HQ)).is_equal(-1)
	_assert_dropped("headquarters gone", made, SiteRig.place(made, "power_plant", SiteRig.SPOT))


## The requirement must be a complete row: none at all, and one that is itself a site, drop it.
func test_the_requirement_must_be_owned_complete() -> void:
	var made: World = SiteRig.world()
	_assert_dropped("no radar", made, SiteRig.place(made, "fossil_strike", SiteRig.FAR))
	var turret: World = SiteRig.world()
	_assert_started(
		"the barracks stands",
		turret,
		SiteRig.place(turret, "defence_turret", SiteRig.SPOT),
		SiteRig.cost(turret, "defence_turret")
	)
	var site: World = SiteRig.world()
	SiteRig.unfinish(site, site.index_of(SiteRig.BARRACKS))
	_assert_dropped(
		"the barracks is a site", site, SiteRig.place(site, "defence_turret", SiteRig.SPOT)
	)
	# A requirement of another player does not count (the turret has no faction here, so that is
	# the rule that drops it), and a barracks of its own is what lets player 2 place it.
	var other: World = SiteRig.world()
	other.type_faction[SiteRig.type_of(other, "defence_turret")] = -1
	_assert_dropped(
		"the rival's barracks", other, SiteRig.place(other, "defence_turret", SiteRig.SPOT_2, 2)
	)
	other.add_building(2, SiteRig.type_of(other, "barracks"), 14, 14)
	_assert_started(
		"its own barracks",
		other,
		SiteRig.place(other, "defence_turret", SiteRig.SPOT_2, 2),
		SiteRig.cost(other, "defence_turret")
	)


func test_the_credits_must_cover_the_price_and_the_boundary_is_the_price() -> void:
	var made: World = SiteRig.world()
	var price: int = SiteRig.cost(made, "power_plant")
	made.credits[1] = price - 1
	_assert_dropped("one short", made, SiteRig.place(made, "power_plant", SiteRig.SPOT))
	made.credits[1] = price
	_assert_started("exactly", made, SiteRig.place(made, "power_plant", SiteRig.SPOT), price)
	assert_int(made.credits[1]).is_equal(0)
	assert_int(made.credits[2]).is_equal(made.start_credits)  # Only the placer pays.


## `construction_sites_max` (a rule int) is the limit: the shipped 1 drops the second site, 2 lets
## it start, 0 lets none start.
func test_a_player_builds_at_most_construction_sites_max_sites_at_once() -> void:
	var made: World = SiteRig.world()
	assert_int(made.construction_sites_max).is_equal(1)
	SiteRig.step(made, [SiteRig.place(made, "power_plant", SiteRig.SPOT)])
	assert_int(SiteRig.sites(made).size()).is_equal(1)
	var credits: int = made.credits[1]
	var dropped: int = made.dropped_commands
	SiteRig.step(made, [SiteRig.place(made, "barracks", SiteRig.WIDE)])
	assert_array([made.dropped_commands, made.credits[1], SiteRig.sites(made).size()]).is_equal(
		[dropped + 1, credits, 1]
	)
	# The other player's count is its own: its first site starts.
	SiteRig.step(made, [SiteRig.place(made, "renew_power", SiteRig.SPOT_2, 2)])
	assert_int(SiteRig.sites(made).size()).is_equal(2)
	var more: World = SiteRig.world()
	more.construction_sites_max = 2
	SiteRig.step(more, [SiteRig.place(more, "power_plant", SiteRig.SPOT)])
	SiteRig.step(more, [SiteRig.place(more, "barracks", SiteRig.WIDE)])
	assert_int(SiteRig.sites(more).size()).is_equal(2)
	SiteRig.step(more, [SiteRig.place(more, "refinery", SiteRig.FAR)])
	assert_array([SiteRig.sites(more).size(), more.dropped_commands]).is_equal([2, 1])
	var none: World = SiteRig.world()
	none.construction_sites_max = 0
	_assert_dropped("no site allowed", none, SiteRig.place(none, "power_plant", SiteRig.SPOT))


## A cancelled row (`build_left` -1, written by CANCEL_BUILD and gone in the same tick's REMOVE)
## still holds its site slot until REMOVE, as it holds its tiles and its reach (P128b, ADR 0026
## section 6): it counts against the limit, and the slot is free once the row has left.
func test_a_cancelled_row_holds_its_slot_until_it_leaves() -> void:
	var made: World = SiteRig.world()
	SiteRig.step(made, [SiteRig.place(made, "power_plant", SiteRig.SPOT)])
	assert_int(Production._sites_of(made, 1)).is_equal(1)
	var row: int = SiteRig.last(made)
	var id: int = made.unit_id[row]
	made.build_left[row] = -1
	assert_int(Production._sites_of(made, 1)).is_equal(1)
	assert_int(Production._sites_of(made, 2)).is_equal(0)  # Only its owner's slot.
	_assert_dropped("the second site", made, SiteRig.place(made, "barracks", SiteRig.WIDE))
	made.hp[row] = 0  # REMOVE takes it out in the next step.
	SiteRig.step(made)
	assert_int(made.index_of(id)).is_equal(-1)
	assert_int(Production._sites_of(made, 1)).is_equal(0)
	_assert_started(
		"the second site, once the row has left",
		made,
		SiteRig.place(made, "barracks", SiteRig.WIDE),
		SiteRig.cost(made, "barracks")
	)


## A finished building is not a site: the limit counts the rows under construction only.
func test_a_completed_site_frees_the_limit() -> void:
	var made: World = SiteRig.world()
	SiteRig.fast(made, "power_plant", 3)
	SiteRig.step(made, [SiteRig.place(made, "power_plant", SiteRig.SPOT)])
	SiteRig.run(made, 2)
	assert_array(SiteRig.sites(made)).is_empty()
	SiteRig.step(made, [SiteRig.place(made, "barracks", SiteRig.WIDE)])
	assert_array([SiteRig.sites(made).size(), made.dropped_commands]).is_equal([1, 0])


## The ground is `Placement.reason`'s: rock, off the map, a unit in the way, no own building within
## reach, the building cap, and the tiles of another site, which block at once.
func test_a_failing_placement_drops_the_command_and_pays_nothing() -> void:
	var rock: World = SiteRig.world([SiteRig.SPOT])
	_assert_dropped("rock", rock, SiteRig.place(rock, "power_plant", SiteRig.SPOT))
	var made: World = SiteRig.world()
	_assert_dropped(
		"off the map", made, Command.place(1, -400, 5300, made.type_ids.find(&"power_plant"))
	)
	_assert_dropped("past the map", made, SiteRig.place(made, "power_plant", Vector2i(23, 15)))
	_assert_dropped(
		"too far from any own building", made, SiteRig.place(made, "power_plant", Vector2i(20, 2))
	)
	var crowded: World = SiteRig.world()
	crowded.add_unit(1, SiteRig.type_of(crowded, "rifle_squad"), 6500, 5500)
	_assert_dropped(
		"a unit in the way", crowded, SiteRig.place(crowded, "power_plant", SiteRig.SPOT)
	)
	var capped: World = SiteRig.world()
	capped.building_cap = 4  # Player 1 owns four buildings.
	_assert_dropped("the building cap", capped, SiteRig.place(capped, "power_plant", SiteRig.SPOT))
	var sites: World = SiteRig.world()
	sites.construction_sites_max = 2
	SiteRig.step(sites, [SiteRig.place(sites, "power_plant", SiteRig.SPOT)])
	var dropped: int = sites.dropped_commands
	SiteRig.step(sites, [SiteRig.place(sites, "barracks", SiteRig.SPOT)])
	assert_array([sites.dropped_commands, SiteRig.sites(sites).size()]).is_equal([dropped + 1, 1])


## A site counts for the building cap and for the reach of a later placement (ADR 0026 section 4:
## unchanged), so the second site may stand beside the first and nowhere else far from a building.
func test_a_site_counts_for_the_cap_and_for_the_reach() -> void:
	var made: World = SiteRig.world()
	made.construction_sites_max = 2
	made.building_cap = 5
	SiteRig.step(made, [SiteRig.place(made, "power_plant", Vector2i(20, 2))])
	assert_int(SiteRig.sites(made).size()).is_equal(0)  # Too far from every building.
	SiteRig.step(made, [SiteRig.place(made, "power_plant", SiteRig.SPOT)])
	assert_int(SiteRig.sites(made).size()).is_equal(1)
	# 4 + 1 = 5 buildings: at the cap now, so the next one is refused although the site is near.
	var dropped: int = made.dropped_commands
	SiteRig.step(made, [SiteRig.place(made, "barracks", SiteRig.WIDE)])
	assert_array([made.dropped_commands, SiteRig.sites(made).size()]).is_equal([dropped + 1, 1])


func test_a_defeated_player_and_an_ended_match_place_nothing() -> void:
	var made: World = SiteRig.world()
	made.defeated_tick[1] = 1
	_assert_dropped("defeated", made, SiteRig.place(made, "power_plant", SiteRig.SPOT))
	var over: World = SiteRig.world()
	over.match_end_tick = 1
	_assert_dropped("ended", over, SiteRig.place(over, "power_plant", SiteRig.SPOT))


func test_a_full_row_table_refuses_the_site_and_the_price_stays() -> void:
	var made: World = SiteRig.world()
	made.max_rows = made.unit_count()
	var refused: int = made.spawn_refused
	_assert_dropped("no room", made, SiteRig.place(made, "power_plant", SiteRig.SPOT))
	assert_int(made.spawn_refused).is_equal(refused + 1)
	assert_array(Worlds.costs_at(made, 5 * SiteRig.COLS + 6)).is_equal([10, 10, 10])


## The old path, beside the new: QUEUE a structure, wait until it is ready, PLACE with an empty
## payload. It builds complete (no `build_left`), the cost was paid when it was queued, and a site
## under construction changes none of it.
func test_the_old_path_works_unchanged_beside_the_new_one() -> void:
	var made: World = SiteRig.world()
	SiteRig.fast(made, "power_plant", 4)
	var plant: int = SiteRig.type_of(made, "power_plant")
	var price: int = SiteRig.cost(made, "power_plant")
	var credits: int = made.credits[1]
	SiteRig.step(made, [Command.queue(1, plant)])
	assert_int(made.credits[1]).is_equal(credits - price)
	SiteRig.run(made, 3)
	var queue: int = 1 * World.TABS + STRUCTURES
	assert_int(made.queue_progress[queue]).is_equal(SiteRig.done(made, "power_plant"))
	# A site of the new path is under construction now; the old PLACE is not affected by it.
	SiteRig.step(made, [SiteRig.place(made, "barracks", SiteRig.WIDE)])
	var site: int = SiteRig.last(made)
	assert_int(made.build_left[site]).is_greater(0)
	var credits_before: int = made.credits[1]
	var rows: int = made.unit_count()
	var old: Command = Command.place(1, 6700, 5300)  # No type: the ready head.
	SiteRig.step(made, [old])
	assert_int(made.unit_count()).is_equal(rows + 1)
	var placed: int = SiteRig.last(made)
	assert_array([made.type_index[placed], made.build_left[placed]]).is_equal([plant, 0])
	assert_int(made.hp[placed]).is_equal(SiteRig.hit_points(made, "power_plant"))
	assert_int(made.credits[1]).is_equal(credits_before)  # Paid at QUEUE, not at PLACE.
	assert_int(made.queue_count[queue]).is_equal(0)
	assert_int(made.stat_built[1]).is_equal(1)
	assert_array(SiteRig.sites(made)).is_equal([site])
	assert_int(made.dropped_commands).is_equal(0)
