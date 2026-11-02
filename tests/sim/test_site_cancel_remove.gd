extends GdUnitTestSuite
## What leaves with a cancelled row (plan row P128b, ADR 0026 section 6), and what REMOVE does with
## it: the DIED record's cancel mark and the losses of a removal that mixes cancelled, destroyed and
## living rows (a cancelled row hit in its last tick has fewer than 0 hit points, so only the mark
## tells it from a kill); the enemy's last-seen record; the site slot, the tiles and the reach,
## which the row holds until REMOVE (a PLACE of the cancel's tick starts nothing, so a site cannot
## hop across the map); the refund rule the Cancel button's label shares; and the derived state,
## which a forced rebuild from the rows restores. `cancel_rig.gd` has the world; every price and
## number is read from it.

const SiteRig: GDScript = preload("res://tests/sim/support/site_rig.gd")
const Rig: GDScript = preload("res://tests/sim/support/cancel_rig.gd")
const Worlds: GDScript = preload("res://tests/sim/support/building_worlds.gd")
const OWN_SITE: int = Rig.OWN_SITE
const ENEMY_SITE: int = Rig.ENEMY_SITE
const OPEN: Array[int] = Rig.OPEN
const SPOT_CELL: int = Rig.SPOT_CELL


## `remove_dead` and `count_losses` on rows built by hand: the mark and the loss follow each row
## through the compaction, whatever the order of cancelled, destroyed and living rows. The cancelled
## row has fewer than 0 hit points (a shot of the same tick), so only its mark tells it from a kill.
func test_the_mark_and_the_loss_follow_each_row_in_a_mixed_removal() -> void:
	var made: World = Rig.world()
	var site: int = made.index_of(OWN_SITE)
	var rival: int = made.index_of(ENEMY_SITE)
	var unit: int = made.unit_count() - 1
	var plant: int = made.index_of(SiteRig.PLANT)
	var unit_id: int = made.unit_id[unit]
	made.events.clear()
	made.hp[plant] = -5  # Destroyed, complete (a shot takes it below 0).
	made.hp[site] = -40  # Cancelled by hand, and hit on top in the same tick.
	made.build_left[site] = -1
	made.hp[rival] = -1  # Destroyed site (work left).
	made.hp[unit] = -3  # Destroyed unit.
	made.remove_dead()
	assert_array(Worlds.costs_at(made, SPOT_CELL)).is_equal(OPEN)  # The cancelled site's tiles.
	var flags: Array[Array] = []
	for record: Array in Rig.died(made):
		flags.append([record[1], record[6]])
	assert_array(flags).is_equal([[SiteRig.PLANT, 0], [OWN_SITE, 1], [ENEMY_SITE, 0], [unit_id, 0]])
	for id: int in [SiteRig.PLANT, OWN_SITE, ENEMY_SITE, unit_id]:
		assert_int(made.index_of(id)).override_failure_message("row %d stays" % id).is_equal(-1)
	assert_array([made.stat_lost_buildings[1], made.stat_lost_units[1]]).is_equal([1, 1])
	assert_array([made.stat_lost_buildings[2], made.stat_lost_units[2]]).is_equal([1, 0])


## The enemy's last-seen record of a site that was cancelled (it may have seen the site, type only)
## goes with the row when the footprint is in its sight, also when a shot of the same tick took the
## cancelled row below 0 hit points (`LastSeen.forget_dead`).
func test_the_enemys_record_of_a_cancelled_site_goes_with_the_row() -> void:
	var made: World = Rig.world()
	var row: int = made.index_of(OWN_SITE)
	var entry: int = 2 * made.ghost_cap
	made.ghost_count[2] = 1
	made.ghost_id[entry] = OWN_SITE
	made.ghost_type[entry] = made.type_index[row]
	made.ghost_owner[entry] = 1
	made.ghost_cell[entry] = SPOT_CELL
	var command: Command = Command.cancel_build(1, OWN_SITE)
	command.tick = made.tick
	assert_bool(Production.apply_cancel_build(made, command)).is_true()
	made.hp[row] = -40  # Hit on top, in FIRE of the same tick.
	made.remove_dead()
	assert_array([made.ghost_count[2], made.ghost_id[entry], made.index_of(OWN_SITE)]).is_equal(
		[0, 0, -1]
	)


## The slot, the ground and the reach all leave with the row, in REMOVE: a PLACE of the tick of the
## cancel (after it in sequence) is dropped and pays nothing, whether it asks for another spot or
## for the tiles of the site, and the same PLACE of the next tick starts. The refund pays for it.
@warning_ignore("integer_division")
func test_a_cancel_frees_the_slot_and_the_tiles_only_after_remove() -> void:
	var made: World = Rig.world()
	var barracks: Command = SiteRig.place(made, "barracks", SiteRig.WIDE)
	barracks.sequence = 1
	var refund: int = SiteRig.cost(made, "power_plant") * 75 / 100
	var credits: int = made.credits[1]
	Rig.step(made, [Command.cancel_build(1, OWN_SITE), barracks])
	assert_array([made.dropped_commands, made.credits[1]]).is_equal([1, credits + refund])
	assert_int(SiteRig.rows_of(made, 1, "barracks").size()).is_equal(1)  # Only the shipped one.
	assert_int(SiteRig.sites(made).size()).is_equal(1)  # The rival's.
	Rig.step(made, [SiteRig.place(made, "barracks", SiteRig.WIDE)])
	assert_int(made.dropped_commands).is_equal(1)
	assert_int(made.credits[1]).is_equal(credits + refund - SiteRig.cost(made, "barracks"))
	assert_int(SiteRig.rows_of(made, 1, "barracks").size()).is_equal(2)
	var again: World = Rig.world()
	var same_tiles: Command = SiteRig.place(again, "power_plant", SiteRig.SPOT)
	same_tiles.sequence = 1
	Rig.step(again, [Command.cancel_build(1, OWN_SITE), same_tiles])
	assert_int(again.dropped_commands).is_equal(1)
	assert_int(SiteRig.rows_of(again, 1, "power_plant").size()).is_equal(1)  # The shipped one.
	Rig.step(again, [SiteRig.place(again, "power_plant", SiteRig.SPOT)])
	assert_int(again.dropped_commands).is_equal(1)
	assert_int(SiteRig.rows_of(again, 1, "power_plant").size()).is_equal(2)  # Shipped + the new site.


## A cancelled row still gives reach until REMOVE (`Placement` counts every own building), so the
## slot it holds is what stops a site from hopping: a PLACE that only the cancelled site reaches,
## in the tick of the cancel, is dropped and pays nothing. A tick later the reach is gone and the
## same spot is too far from every building left.
func test_a_place_in_reach_of_only_the_cancelled_site_is_dropped() -> void:
	var made: World = SiteRig.world()
	var first: Vector2i = Vector2i(19, 1)  # Within reach of the refinery (12, 1).
	var second: Vector2i = Vector2i(22, 6)  # Within reach of the site at (19, 1) alone.
	var plant: int = SiteRig.type_of(made, "power_plant")
	assert_int(made.build_reach_tiles).is_equal(4)
	assert_int(Placement.reason(PlacementInput.of_world(made), 1, plant, 22, 6)).is_equal(
		Placement.Reason.TOO_FAR
	)
	Rig.step(made, [SiteRig.place(made, "power_plant", first)])
	var site: int = made.unit_id[SiteRig.last(made)]
	assert_array(SiteRig.sites(made)).is_equal([SiteRig.last(made)])
	assert_int(Placement.reason(PlacementInput.of_world(made), 1, plant, 22, 6)).is_equal(
		Placement.Reason.OK
	)
	var hop: Command = SiteRig.place(made, "power_plant", second)
	hop.sequence = 1
	var credits: int = made.credits[1]
	Rig.step(made, [Command.cancel_build(1, site), hop])
	assert_array([made.dropped_commands, made.index_of(site)]).is_equal([1, -1])
	assert_int(made.credits[1]).is_equal(credits + Production.refund(made.type_cost[plant], 75))
	assert_array(SiteRig.sites(made)).is_empty()
	assert_array(Worlds.costs_at(made, 6 * SiteRig.COLS + 22)).is_equal(OPEN)
	# The row is gone and so is its reach: the same PLACE of the next tick is dropped for the ground.
	credits = made.credits[1]
	assert_int(Placement.reason(PlacementInput.of_world(made), 1, plant, 22, 6)).is_equal(
		Placement.Reason.TOO_FAR
	)
	Rig.step(made, [SiteRig.place(made, "power_plant", second)])
	assert_array([made.dropped_commands, made.credits[1]]).is_equal([2, credits])
	assert_array(SiteRig.sites(made)).is_empty()


## The pure rule the cancel uses and the Cancel button's label shares: `cost * percent / 100`,
## truncated, from the arguments alone.
func test_refund_is_the_truncated_share_of_the_cost() -> void:
	var rows: Array = [[600, 75, 450], [333, 75, 249], [333, 1, 3], [1, 99, 0], [600, 0, 0]]
	rows.append_array([[600, 100, 600], [0, 75, 0]])
	for row: Array in rows:
		assert_int(Production.refund(row[0], row[1])).override_failure_message(str(row)).is_equal(
			row[2]
		)


## Derived state after a cancel (ADR 0016): the hash moves with the credits and the rows; a cancel
## leaves the power totals as they were (a site made and used nothing), and a rebuild from the
## rows, forced by hand after the derived state was spoiled, gives back the totals of an
## independent scan and a building list without the cancelled row. The hash does not see the spoil.
func test_the_derived_state_after_a_cancel_equals_a_rebuild_from_the_rows() -> void:
	var made: World = Rig.world()
	var listed: int = made.building_rows.size()
	var before: int = made.state_hash()
	var totals: Array[Array] = [Rig.scan(made, 1), Rig.scan(made, 2)]
	Rig.step(made, [Command.cancel_build(1, OWN_SITE)])
	assert_int(made.state_hash()).is_not_equal(before)
	assert_array(Rig.scan(made, 1)).is_equal(totals[0])
	assert_array(Rig.scan(made, 2)).is_equal(totals[1])
	var hashed: int = made.state_hash()
	made.building_rows.clear()
	made.power_made.fill(-7)
	made.power_used.fill(-7)
	assert_int(made.state_hash()).is_equal(hashed)
	made._lists_version = -1
	Power.run(made)
	assert_array([made.power_made[1], made.power_used[1]]).is_equal(totals[0])
	assert_array([made.power_made[2], made.power_used[2]]).is_equal(totals[1])
	var buildings: Array[int] = []
	for at: int in made.unit_count():
		if made.type_foot_w[made.type_index[at]] > 0:
			buildings.append(at)
	assert_array(Array(made.building_rows)).is_equal(buildings)
	assert_int(buildings.size()).is_equal(listed - 1)
	assert_bool(buildings.has(made.index_of(OWN_SITE))).is_false()
