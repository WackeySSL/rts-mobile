class_name WorldShape
extends RefCounted
## The shape lists of a World (ADR 0007 section 8, ADR 0013 section 3), split out of World.gd
## (P287a) so that file keeps room under gdlint's line limit. Pure data: the names of every array
## and scalar a World declares, grouped by what the state hash, the defs hash and the coverage
## walks do with them. World.gd re-exports each one under the same name (`World.ROW_ARRAYS` is
## `WorldShape.ROW_ARRAYS`, the same constant), so no caller changes. The lists, their order and
## their contents are exactly World's own, moved.

## The per-unit columns, in this order.
const ROW_ARRAYS: Array[StringName] = [
	&"unit_id",
	&"owner",
	&"type_index",
	&"pos_x",
	&"pos_y",
	&"goal_x",
	&"goal_y",
	&"group_cell",
	&"order",
	&"hp",
	&"order_target",
	&"target",
	&"cooldown",
	&"nav_mode",
	&"field",
	&"nav_cell",
	&"nav_next",
	&"best_dist",
	&"stall",
	&"fog_cell",
	&"harvest_mode",
	&"cargo",
	&"harvest_slot",
	&"home",
	&"ready_tick",
	&"offline_until",
	&"build_left",
	&"ammo",
	&"carry_mode",
	&"stance",
]
## The per-type tables, one entry per type_ids entry once prepare() has run.
const TYPE_ARRAYS: Array[StringName] = [
	&"type_speed",
	&"type_radius",
	&"type_selection_radius",
	&"type_spacing",
	&"type_max_hp",
	&"type_armour",
	&"type_move_class",
	&"type_sight",
	&"type_acquire",
	&"type_weapon",
	&"type_names",
	&"type_foot_w",
	&"type_foot_h",
	&"type_cost",
	&"type_build_ticks",
	&"type_tab",
	&"type_requires",
	&"type_produces",
	&"type_power",
	&"type_harvest",
	&"type_free_unit",
	&"type_dock_x",
	&"type_dock_y",
	&"type_exit_x",
	&"type_exit_y",
	&"type_faction",
	&"type_strike_kind",
	&"type_charge_ticks",
	&"type_strike_radius",
	&"type_strike_delay",
	&"type_strike_ticks",
	&"type_strike_weapon",
	&"type_layer_bit",
	&"type_ammo",
	&"type_rearm_ticks",
	&"type_pads",
	&"type_pad_first",
	&"type_upgrade",
	&"type_repair_classes",
	&"type_repair_hp",
	&"type_repair_period",
	&"type_repair_cost_percent",
	&"type_repair_reach",
	&"type_repair_slots",
	&"type_repair_seek",
	&"type_carry_slots",
	&"type_carry_classes",
	&"type_carry_eject_percent",
	&"type_mine_weapon",
	&"type_mine_cost",
	&"type_mine_aware",
	&"type_detect_milli",
]
## The landing pad offsets (ADR 0036 section 3, a pad_offsets table beside `type_pads`): entries
## `type_pad_first[type]` to `+ type_pads[type]` of both lists are the tile offsets, from the
## footprint origin, of a type's pads. In `defs_hash` after the type and weapon tables.
const PAD_ARRAYS: Array[StringName] = [&"pad_offset_x", &"pad_offset_y"]
## The upgrade tables (ADR 0036 sections 2 and 3), one entry per `upgrade_ids` entry except the flat
## `upgrade_types`, whose entries `upgrade_type_first[u]` to `+ upgrade_type_count[u]` are the type
## indexes upgrade `u` changes. In `defs_hash` after the pad offsets.
const UPGRADE_ARRAYS: Array[StringName] = [
	&"upgrade_stat",
	&"upgrade_value",
	&"upgrade_type_first",
	&"upgrade_type_count",
	&"upgrade_types",
]
## The weapon tables, one entry per weapon (weapon_vs_armour has four).
const WEAPON_ARRAYS: Array[StringName] = [
	&"weapon_range",
	&"weapon_min_range",
	&"weapon_damage",
	&"weapon_cooldown",
	&"weapon_projectile_speed",
	&"weapon_vs_armour",
	&"weapon_targets",
	&"weapon_blast_milli",
]
## The projectile slots, max_projectiles entries each. proj_free is the stack of free slots.
const PROJECTILE_ARRAYS: Array[StringName] = [
	&"proj_id",
	&"proj_owner",
	&"proj_weapon",
	&"proj_target",
	&"proj_x",
	&"proj_y",
	&"proj_aim_x",
	&"proj_aim_y",
	&"proj_ticks",
	&"proj_free",
]
## The per-player state (ADR 0017 section 3), sized by prepare(): the first seven have an entry per
## player (index 0 is neutral and unused), the next four one per player and tab (`player * TABS +
## tab`), `queue_type` one per queue slot (`(player * TABS + tab) * queue_slots + slot`) and the
## next three (the pending strike, P109) and the last three (`reveal_site`, `reveal` and `upgrades`,
## ADR 0036 section 3) one per player again. Hashed, one block per array, in the
## section `players`.
const PLAYER_ARRAYS: Array[StringName] = [
	&"credits",
	&"defeated_tick",
	&"had_producer",
	&"stat_built",
	&"stat_lost_units",
	&"stat_lost_buildings",
	&"stat_harvested",
	&"queue_count",
	&"queue_progress",
	&"rally_x",
	&"rally_y",
	&"queue_type",
	&"strike_x",
	&"strike_y",
	&"strike_tick",
	&"reveal_site",
	&"reveal",
	&"upgrades",
]
## The boarded squads (ADR 0036 section 8): record `i` is entry `i` of the five arrays, live below
## `pass_count`, `passenger_cap` entries each. Hashed, live records only, in `passengers`.
const PASSENGER_ARRAYS: Array[StringName] = [
	&"pass_carrier", &"pass_id", &"pass_type", &"pass_hp", &"pass_owner"
]
## Laid mines (ADR 0037 section 8): record `i` is entry `i`, live below `mine_count`; the mines a
## player found: entry `p * mine_known_cap + i`, live below `mine_seen_count[p]`. Hashed, `mines`.
const MINE_ARRAYS: Array[StringName] = [
	&"mine_id", &"mine_owner", &"mine_cell", &"mine_weapon", &"mine_armed_tick"
]
const MINE_SEEN_ARRAYS: Array[StringName] = [
	&"mine_seen_id", &"mine_seen_owner", &"mine_seen_cell", &"mine_seen_count"
]
## The ore left in each ore cell, one entry per `ore_cell` entry. Hashed, in the section `ore`.
const ORE_ARRAYS: Array[StringName] = [&"ore_amount"]
## The last-seen building records (ADR 0017 section 3): record `i` of player `p` is entry
## `p * ghost_cap + i` of the four record arrays, live below `ghost_count[p]`. Hashed, live records
## only, in the section `ghosts`.
const GHOST_ARRAYS: Array[StringName] = [
	&"ghost_id", &"ghost_type", &"ghost_owner", &"ghost_cell", &"ghost_count"
]
## State that follows from the hashed state (ADR 0016), rebuilt when `rows_version` moves and in
## no hash section: the power totals per player and the ascending rows of buildings, harvesters and
## aircraft.
const DERIVED_ARRAYS: Array[StringName] = [
	&"power_made",
	&"power_used",
	&"building_rows",
	&"harvester_rows",
	&"air_rows",
	&"repair_rows",
	&"mod_dealt",
	&"mod_taken",
	&"mod_ammo",
	&"mine_at",
]
## The tile grid: the terrain index per cell, the move cost per class and cell, the cost per
## terrain and class that set_terrain copies into it, the buildable flag per terrain and the
## ascending cells of the ore terrain (fixed at load).
const MAP_ARRAYS: Array[StringName] = [
	&"terrain", &"move_cost", &"terrain_cost", &"terrain_buildable", &"ore_cell"
]
## Per-row working space, max_rows entries each, rewritten every tick. Not state.
const SCRATCH_ARRAYS: Array[StringName] = [&"intent_x", &"intent_y", &"push_x", &"push_y"]
## Match setup per player (P173): not in the state hash, in `defs_hash`; WorldLoad.set_income.
const SETUP_ARRAYS: Array[StringName] = [&"income_percent"]
## Rewritten every tick, neither hashed nor compacted.
const RUNTIME_ARRAYS: Array[StringName] = [&"events", &"stats"]

## The int properties in the state hash, in hash order: the header ints, then map_version (the map
## grid goes in as a cached digest), then the match end and the passenger count. rng.state()
## follows them.
const HASHED_SCALARS: Array[StringName] = [
	&"tick",
	&"next_id",
	&"next_projectile_id",
	&"dropped_commands",
	&"projectile_overflow",
	&"spawn_refused",
	&"player_count",
	&"proj_free_top",
	&"map_version",
	&"match_end_tick",
	&"winner",
	&"pass_count",
	&"next_mine_id",
	&"mine_count",
]
## The rule ints, copied from RulesDef under the same names. defs_hash() covers them.
const RULE_SCALARS: Array[StringName] = [
	&"retarget_period_ticks",
	&"fog_period_ticks",
	&"line_check_period_ticks",
	&"flow_cells_per_tick",
	&"flow_cache_size",
	&"separation_neighbours",
	&"separation_scan",
	&"separation_idle_share",
	&"separation_push_max",
	&"separation_coincident_divisor",
	&"stall_ticks",
	&"stall_range_spacings",
	&"attack_rekey_milli",
	&"max_projectiles",
	&"max_rows",
	&"start_credits",
	&"ore_start",
	&"ore_cell_max",
	&"ore_regrow_ticks",
	&"credits_per_ore",
	&"harvest_ticks_per_ore",
	&"unload_ticks_per_ore",
	&"harvest_reach_milli",
	&"dock_reach_milli",
	&"harvest_retry_ticks",
	&"harvest_resume_ticks",
	&"harvest_pick_milli",
	&"low_power_percent",
	&"queue_slots",
	&"build_reach_tiles",
	&"unit_cap",
	&"building_cap",
	&"ghost_cap",
	&"construct_start_hp_percent",
	&"construct_refund_percent",
	&"construction_sites_max",
	&"sell_refund_percent",
	&"mend_hp",
	&"mend_period_ticks",
	&"mend_cost_percent",
	&"passenger_cap",
	&"load_reach_milli",
	&"unload_reach_tiles",
	&"mine_cap",
	&"mine_lay_ticks",
	&"mine_arm_ticks",
	&"sweep_ticks",
	&"mine_known_cap",
]
## The other int properties, none in the state hash: the map size, the view's rows_version,
## native_phases (which implementation runs a phase is never state, ADR 0013 section 3), the map
## digest cache (it follows from map_version and the grid) and the rule ints, which repeat
## RULE_SCALARS (a literal, because `+` on typed constants gives an untyped Array; a test pins it).
const UNHASHED_SCALARS: Array[StringName] = [
	&"map_w",
	&"map_h",
	&"map_cols",
	&"map_rows",
	&"rows_version",
	&"native_phases",
	&"_map_digest",
	&"_map_digest_version",
	&"_lists_version",
	&"retarget_period_ticks",
	&"fog_period_ticks",
	&"line_check_period_ticks",
	&"flow_cells_per_tick",
	&"flow_cache_size",
	&"separation_neighbours",
	&"separation_scan",
	&"separation_idle_share",
	&"separation_push_max",
	&"separation_coincident_divisor",
	&"stall_ticks",
	&"stall_range_spacings",
	&"attack_rekey_milli",
	&"max_projectiles",
	&"max_rows",
	&"start_credits",
	&"ore_start",
	&"ore_cell_max",
	&"ore_regrow_ticks",
	&"credits_per_ore",
	&"harvest_ticks_per_ore",
	&"unload_ticks_per_ore",
	&"harvest_reach_milli",
	&"dock_reach_milli",
	&"harvest_retry_ticks",
	&"harvest_resume_ticks",
	&"harvest_pick_milli",
	&"low_power_percent",
	&"queue_slots",
	&"build_reach_tiles",
	&"unit_cap",
	&"building_cap",
	&"ghost_cap",
	&"construct_start_hp_percent",
	&"construct_refund_percent",
	&"construction_sites_max",
	&"sell_refund_percent",
	&"mend_hp",
	&"mend_period_ticks",
	&"mend_cost_percent",
	&"passenger_cap",
	&"load_reach_milli",
	&"unload_reach_tiles",
	&"mine_cap",
	&"mine_lay_ticks",
	&"mine_arm_ticks",
	&"sweep_ticks",
	&"mine_known_cap"
]
## The members that are not state (ADR 0013 section 3): the coverage test, the state hash and the
## reachability walk skip exactly these. `kernels` is the native kernels object, or null.
const NON_STATE_MEMBERS: Array[StringName] = [&"kernels"]
