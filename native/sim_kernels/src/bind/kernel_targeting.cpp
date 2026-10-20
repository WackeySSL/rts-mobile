// TARGETING, the native twin of Targeting.run (ADR 0013 sections 1 to 3, plan P41n): acquisition and engagement in one call,
// in place over the arrays of the World and over the targeting grid that the GDScript rebuild wrote this tick
// (World.target_grid: the GRIDS phase rebuilds it, this kernel never does). Every unit locks, keeps or scans for its target
// and then holds, chases or resumes its path; the units the scans looked at are added to stats[TARGET_CANDIDATES] and the
// line tests of the engagement pass to stats[LINE_CHECKS]. The rules are core/targeting.h's, a mirror of Targeting.gd, with
// core/fixed_math.h's line_clear; this file borrows the arrays once on entry and adds the two counts on exit.
// Twin: game/sim/Targeting.gd (run, _engage). Tests: tests/sim/test_targeting*.gd and tests/sim/test_engagement*.gd under both
// implementations and tests/sim/native/test_targeting_kernel.gd, test_targeting_kernel_cases.gd,
// test_targeting_kernel_indexes.gd and test_targeting_kernel_lines.gd; lockstep (P41n2): later. MIT.
#include "sim_kernels.h"

#include <godot_cpp/variant/utility_functions.hpp>

#include "core/targeting.h"

using namespace godot;
using namespace world_access;

namespace {

constexpr int64_t STAT_LINE_CHECKS = 1; // World.Stat.LINE_CHECKS
constexpr int64_t STAT_TARGET_CANDIDATES = 3; // World.Stat.TARGET_CANDIDATES

} // namespace

void SimKernels::targeting(Object *world) const {
	const int64_t status = access_.check(world, PHASE_TARGETING);
	if (status != 0) {
		UtilityFunctions::push_error("SimKernels.targeting: ", TABLE[status / FAULT_COUNT].name, " fails the checked table (status ", status, "); nothing was written.");
		return;
	}
	const WorldAccess &access = access_;
	const Variant grid_variant = access.helper(world, OWN_TARGET);
	Object *grid = WorldAccess::object_in(grid_variant);

	// The columns and tables the pass only reads, then the ones it writes.
	const Borrowed<const int32_t> unit_id = access.read_i32(world, ID_WORLD_unit_id);
	const Borrowed<const int32_t> owner = access.read_i32(world, ID_WORLD_owner);
	const Borrowed<const int32_t> type_index = access.read_i32(world, ID_WORLD_type_index);
	const Borrowed<const int32_t> pos_x = access.read_i32(world, ID_WORLD_pos_x);
	const Borrowed<const int32_t> pos_y = access.read_i32(world, ID_WORLD_pos_y);
	const Borrowed<const int32_t> type_armour = access.read_i32(world, ID_WORLD_type_armour);
	const Borrowed<const int32_t> type_acquire = access.read_i32(world, ID_WORLD_type_acquire);
	const Borrowed<const int32_t> type_weapon = access.read_i32(world, ID_WORLD_type_weapon);
	const Borrowed<const int32_t> type_move_class = access.read_i32(world, ID_WORLD_type_move_class);
	const Borrowed<const int32_t> weapon_range = access.read_i32(world, ID_WORLD_weapon_range);
	const Borrowed<const int32_t> weapon_min_range = access.read_i32(world, ID_WORLD_weapon_min_range);
	const Borrowed<const int32_t> weapon_vs_armour = access.read_i32(world, ID_WORLD_weapon_vs_armour);
	const Borrowed<const uint8_t> move_cost = access.read_bytes(world, ID_WORLD_move_cost);
	const Borrowed<const int32_t> head = access.read_i32(grid, ID_TARGET_head);
	const Borrowed<const int32_t> next = access.read_i32(grid, ID_TARGET_next);
	const Borrowed<int32_t> goal_x = access.write_i32(world, ID_WORLD_goal_x);
	const Borrowed<int32_t> goal_y = access.write_i32(world, ID_WORLD_goal_y);
	const Borrowed<int32_t> order = access.write_i32(world, ID_WORLD_order);
	const Borrowed<int32_t> order_target = access.write_i32(world, ID_WORLD_order_target);
	const Borrowed<int32_t> target = access.write_i32(world, ID_WORLD_target);
	const Borrowed<int32_t> nav_mode = access.write_i32(world, ID_WORLD_nav_mode);
	const Borrowed<int32_t> nav_cell = access.write_i32(world, ID_WORLD_nav_cell);
	const Borrowed<int32_t> field = access.write_i32(world, ID_WORLD_field);
	const Borrowed<int32_t> nav_next = access.write_i32(world, ID_WORLD_nav_next);
	const Borrowed<int32_t> best_dist = access.write_i32(world, ID_WORLD_best_dist);
	const Borrowed<int32_t> stall = access.write_i32(world, ID_WORLD_stall);
	Borrowed<int32_t> stats = access.write_i32(world, ID_WORLD_stats);

	targeting::Rows rows;
	rows.unit_id = unit_id.view;
	rows.owner = owner.view;
	rows.type_index = type_index.view;
	rows.pos_x = pos_x.view;
	rows.pos_y = pos_y.view;
	rows.goal_x = goal_x.view;
	rows.goal_y = goal_y.view;
	rows.order = order.view;
	rows.order_target = order_target.view;
	rows.target = target.view;
	rows.nav_mode = nav_mode.view;
	rows.nav_cell = nav_cell.view;
	rows.field = field.view;
	rows.nav_next = nav_next.view;
	rows.best_dist = best_dist.view;
	rows.stall = stall.view;
	targeting::Types types;
	types.armour = type_armour.view;
	types.acquire = type_acquire.view;
	types.weapon = type_weapon.view;
	types.move_class = type_move_class.view;
	targeting::Weapons weapons;
	weapons.range = weapon_range.view;
	weapons.min_range = weapon_min_range.view;
	weapons.vs_armour = weapon_vs_armour.view;
	targeting::Grid cells;
	cells.cols = access.int_in(grid, ID_TARGET_cols);
	cells.rows = access.int_in(grid, ID_TARGET_rows);
	cells.cell_milli = access.int_in(grid, ID_TARGET_cell_milli);
	cells.head = head.view;
	cells.next = next.view;
	targeting::Map map;
	map.cols = access.int_in(world, ID_WORLD_map_cols);
	map.rows = access.int_in(world, ID_WORLD_map_rows);
	map.move_cost = move_cost.view;
	targeting::Rules rules;
	rules.tick = access.int_in(world, ID_WORLD_tick);
	rules.retarget_period_ticks = access.int_in(world, ID_WORLD_retarget_period_ticks);
	rules.line_check_period_ticks = access.int_in(world, ID_WORLD_line_check_period_ticks);

	const targeting::Counts counts = targeting::run(rows, types, weapons, cells, map, rules);
	stats.view.set(STAT_LINE_CHECKS, stats.view.get(STAT_LINE_CHECKS) + counts.line_checks);
	stats.view.set(STAT_TARGET_CANDIDATES, stats.view.get(STAT_TARGET_CANDIDATES) + counts.candidates);
}
