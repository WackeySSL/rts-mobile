extends GdUnitTestSuite
## P117d: the flash, muzzle and puff rows of `EffectsLayer` and the rocket of `ProjectileLayer` for
## the Phase 3 faction weapons. A shot of `breaker_rocket`, `redoubt_gun` and `arcline_gun` draws
## its own flash, muzzle reach and puff, the Breakers' as a rocket, and the old weapons keep theirs
## (test_effects_layer.gd and test_projectile_layer.gd pin the three of Phase 2 by behaviour).
## The scans read data/units, not a list typed here, as test_sprite_lift.gd does for the muzzle
## lifts (P117c): a roster that adds a weapon without rows would draw it with the defaults.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const Rig: GDScript = preload("res://tests/view/support/effects_rig.gd")
const UNITS_DIR: String = "res://data/units/"
## STYLE.md "Combat effects": the atlas regions of the flash, the puff, the shell and the rocket.
const FLASH: Rect2 = Rect2(144, 0, 32, 32)
const PUFF: Rect2 = Rect2(84, 0, 56, 56)
const SHELL: Rect2 = Rect2(84.0, 60.0, 16.0, 8.0)
const ROCKET: Rect2 = Rect2(84.0, 72.0, 36.0, 12.0)
const TOL: Vector2 = Vector2(0.001, 0.001)
## Per weapon id: x the flash's side, y the muzzle's reach, z the puff's side (0: no puff row, the
## rifle is hitscan and lands no IMPACT), all in world px, typed again so a wrong table fails. The
## first three are the weapons of Phase 2 that had rows before P117d; the Redoubt's and the
## artillery's rows are the defaults the turret and the artillery always drew with.
const ROWS: Dictionary[StringName, Vector3] = {
	&"tank_cannon": Vector3(32.0, 31.0, 40.0),
	&"rocket": Vector3(24.0, 13.0, 56.0),
	&"rifle": Vector3(16.0, 13.0, 0.0),
	&"heavy_cannon": Vector3(24.0, 13.0, 40.0),
	&"turret_gun": Vector3(24.0, 13.0, 40.0),
	&"artillery_gun": Vector3(24.0, 13.0, 40.0),
	&"breaker_rocket": Vector3(24.0, 13.0, 56.0),
	&"redoubt_gun": Vector3(24.0, 13.0, 40.0),
	&"arcline_gun": Vector3(24.0, 13.0, 40.0),
}
const FACTION_WEAPONS: Array[StringName] = [&"breaker_rocket", &"redoubt_gun", &"arcline_gun"]

var _now_ms: int = 0
var _runner: MatchRunner
var _effects: EffectsLayer
var _projectiles: ProjectileLayer


func before_test() -> void:
	# A duel whose roster holds every armed unit of the data, so the snapshot's weapon table has
	# every weapon a shipped unit fires.
	var scenario: ScenarioDef = Rig.duel()
	for fired: UnitDef in _fired().values():
		if not scenario.roster.has(fired):
			scenario.roster.append(fired)
	_now_ms = 0
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = scenario
	_runner.start()
	_effects = auto_free(EffectsLayer.new())
	_effects.runner = _runner
	_effects.reveal_enemies = true  # The effects are the subject, not the fog.
	_effects.clock = func() -> int: return _now_ms
	add_child(_effects)
	_effects.set_process(false)
	_projectiles = auto_free(ProjectileLayer.new())
	_projectiles.runner = _runner
	_projectiles.reveal_enemies = true
	add_child(_projectiles)
	_projectiles.set_process(false)


func after_test() -> void:
	CommandQueue.clear()


func test_every_weapon_a_shipped_unit_fires_has_a_flash_a_muzzle_and_a_puff_row() -> void:
	var fired: Dictionary[StringName, UnitDef] = _fired()
	# The scan reaches the units of both factions, so it cannot pass by finding nothing.
	for weapon_id: StringName in ROWS:
		assert_bool(fired.has(weapon_id)).override_failure_message(String(weapon_id)).is_true()
	for weapon_id: StringName in fired:
		var note: String = "%s (fired by %s)" % [weapon_id, fired[weapon_id].type_id]
		assert_bool(_effects.flash_px.has(weapon_id)).override_failure_message(note).is_true()
		assert_bool(_effects.muzzle_px.has(weapon_id)).override_failure_message(note).is_true()
		# A hitscan weapon lands no IMPACT, so a puff row is for a weapon that flies.
		if fired[weapon_id].weapon.projectile_speed > 0:
			assert_bool(_effects.puff_px.has(weapon_id)).override_failure_message(note).is_true()


func test_the_rows_are_the_pinned_sizes_and_the_three_old_weapons_keep_theirs() -> void:
	for weapon_id: StringName in ROWS:
		var row: Vector3 = ROWS[weapon_id]
		var note: String = String(weapon_id)
		(
			assert_float(_effects.flash_px.get(weapon_id, -1.0))
			. override_failure_message(note)
			. is_equal(row.x)
		)
		(
			assert_float(_effects.muzzle_px.get(weapon_id, -1.0))
			. override_failure_message(note)
			. is_equal(row.y)
		)
		assert_float(_effects.puff_px.get(weapon_id, 0.0)).override_failure_message(note).is_equal(
			row.z
		)


func test_a_faction_weapon_takes_the_row_of_the_old_weapon_of_its_kind_of_shooter() -> void:
	# The same rule as the muzzle lifts of P117c: the same kind of shooter, the same sizes.
	var pairs: Array[PackedStringArray] = [
		PackedStringArray(["defence_turret", "renew_defence"]),
		PackedStringArray(["rocket_squad", "renew_rocket"]),
		PackedStringArray(["artillery", "renew_artillery"]),
	]
	for pair: PackedStringArray in pairs:
		var old_id: StringName = (load(UNITS_DIR + pair[0] + ".tres") as UnitDef).weapon.id
		var new_id: StringName = (load(UNITS_DIR + pair[1] + ".tres") as UnitDef).weapon.id
		for table: Dictionary in [_effects.flash_px, _effects.muzzle_px, _effects.puff_px]:
			(
				assert_float(table[new_id])
				. override_failure_message("%s, %s" % [pair[0], pair[1]])
				. is_equal(table[old_id])
			)


func test_a_shot_of_each_faction_weapon_draws_its_flash_out_at_its_muzzle() -> void:
	var shooter: Vector2i = Vector2i(10000, 20000)
	var target: Vector2i = Vector2i(10000, 24000)  # 4 tiles south, past every reach.
	for weapon_id: StringName in FACTION_WEAPONS:
		var lift: Vector2 = Vector2(0.0, -SpriteLift.MUZZLE_PX[weapon_id])
		var from_px: Vector2 = IsoProjection.ground_to_px(shooter.x, shooter.y) + lift
		var to_px: Vector2 = IsoProjection.ground_to_px(target.x, target.y) + lift
		_now_ms += 1000  # The effects before are gone.
		_tick_with(Rig.shot(shooter, target, _weapon(weapon_id)))
		var note: String = String(weapon_id)
		assert_int(_effects.line_count()).override_failure_message(note).is_equal(0)  # Projectile.
		assert_int(_effects.quad_count()).override_failure_message(note).is_equal(1)
		assert_that(_effects.quad_region(0)).is_equal(FLASH)
		assert_float(_effects.quad_rect(0).size.x).is_equal_approx(ROWS[weapon_id].x, 0.001)
		var along: Vector2 = (to_px - from_px).normalized()
		(
			assert_vector(_effects.quad_rect(0).get_center())
			. override_failure_message(note)
			. is_equal_approx(from_px + along * ROWS[weapon_id].y, TOL)
		)


func test_an_impact_of_each_faction_weapon_draws_its_puff_at_the_height_it_flew() -> void:
	var landing: Vector2i = Vector2i(12500, 9500)
	for weapon_id: StringName in FACTION_WEAPONS:
		var landing_px: Vector2 = IsoProjection.ground_to_px(landing.x, landing.y)
		landing_px.y -= SpriteLift.MUZZLE_PX[weapon_id]
		_now_ms += 1000
		_tick_with(Rig.impact(landing, _weapon(weapon_id), 3, 7))
		var note: String = String(weapon_id)
		assert_int(_effects.quad_count()).override_failure_message(note).is_equal(1)
		assert_that(_effects.quad_region(0)).is_equal(PUFF)
		(
			assert_vector(_effects.quad_rect(0).get_center())
			. override_failure_message(note)
			. is_equal_approx(landing_px, TOL)
		)
		_now_ms += 200  # Grown by now.
		_effects._process(0.0)
		assert_float(_effects.quad_rect(0).size.x).override_failure_message(note).is_equal_approx(
			ROWS[weapon_id].z, 0.001
		)


func test_every_rocket_kind_weapon_draws_as_a_rocket_and_every_other_as_a_shell() -> void:
	# The kind is read from the data: a weapon that flies (projectile_speed above 0) and is fired
	# by infantry is a launcher's. The cannons, the guns and the hitscan rifle are not.
	var fired: Dictionary[StringName, UnitDef] = _fired()
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(snap.proj_id.size()).is_greater_equal(fired.size())
	var slot: int = 0
	for weapon_id: StringName in fired:
		(
			assert_int(snap.weapon_ids.find(weapon_id))
			. override_failure_message(String(weapon_id))
			. is_greater_equal(0)
		)
		_set_slot(
			slot, 100 + slot, Vector2i(1000, 1000 + 1000 * slot), snap.weapon_ids.find(weapon_id)
		)
		slot += 1
	_projectiles._process(0.0)
	assert_int(_projectiles.active_count()).is_equal(fired.size())
	var rockets: Array[StringName] = []
	for index: int in _projectiles.active_count():
		var weapon_id: StringName = snap.weapon_ids[snap.proj_weapon[_projectiles.quad_slot(index)]]
		var unit: UnitDef = fired[weapon_id]
		var is_rocket: bool = (
			unit.armour == World.Armour.INFANTRY and unit.weapon.projectile_speed > 0
		)
		if is_rocket:
			rockets.append(weapon_id)
		(
			assert_that(_projectiles.quad_region(index))
			. override_failure_message(String(weapon_id))
			. is_equal(ROCKET if is_rocket else SHELL)
		)
	# Both launchers are found, so the loop cannot pass by finding none.
	assert_array(rockets).contains_exactly_in_any_order([&"rocket", &"breaker_rocket"])


## Every weapon that a shipped unit fires, by weapon id, with a unit that fires it.
func _fired() -> Dictionary[StringName, UnitDef]:
	var fired: Dictionary[StringName, UnitDef] = {}
	for path: String in FileScan.list_files(UNITS_DIR, ".tres"):
		var unit: UnitDef = load(path) as UnitDef
		assert_object(unit).override_failure_message(path).is_not_null()
		if unit.weapon != null:
			fired[unit.weapon.id] = unit
	return fired


func _weapon(weapon_id: StringName) -> int:
	var index: int = _runner.snapshot.weapon_ids.find(weapon_id)
	assert_int(index).override_failure_message(String(weapon_id)).is_greater_equal(0)
	return index


## Delivers `events` as the events of a tick, the way the runner does, then plans a frame.
func _tick_with(events: PackedInt32Array) -> void:
	_runner.snapshot.events = events
	_runner.ticked.emit(_runner.snapshot.tick)
	_effects._process(0.0)


## Writes projectile slot `slot` of the published snapshot: live with id `id` of weapon `weapon`,
## going 1000 milli east from `from`, in this tick and in the one before.
func _set_slot(slot: int, id: int, from: Vector2i, weapon: int) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.proj_id[slot] = id
	snap.prev_proj_id[slot] = id
	snap.proj_owner[slot] = 1
	snap.proj_weapon[slot] = weapon
	snap.prev_proj_x[slot] = from.x
	snap.prev_proj_y[slot] = from.y
	snap.proj_x[slot] = from.x + 1000
	snap.proj_y[slot] = from.y
