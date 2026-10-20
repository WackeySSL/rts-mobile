// SEPARATION, the native twin of Separation.run (ADR 0013 sections 2 and 3, plan P39n): every unit is pushed away from the
// units it overlaps, in place over the arrays of the World and over the separation grid that the GDScript rebuild wrote this
// tick (World.sep_grid: the GRIDS phase rebuilds it, this kernel never does). The rules are core/separation.h's, a mirror of
// Separation.gd; this file borrows the arrays once on entry and adds the units looked at to stats[SEP_PAIRS] on exit.
// Twin: game/sim/Separation.gd (run). Tests: tests/sim/test_separation*.gd under both implementations and
// tests/sim/native/test_separation_kernel.gd; lockstep (P39n2): test_separation_lockstep.gd (the arena), _cases.gd (crafted crowds)
// and _random.gd (seeded random states) in tests/sim/native/. MIT.
#include "sim_kernels.h"

#include <godot_cpp/variant/utility_functions.hpp>

#include "core/separation.h"

using namespace godot;
using namespace world_access;

namespace {

constexpr int64_t STAT_SEP_PAIRS = 2; // World.Stat.SEP_PAIRS

} // namespace

void SimKernels::separation(Object *world) const {
	const int64_t status = access_.check(world, PHASE_SEPARATION);
	if (status != 0) {
		UtilityFunctions::push_error("SimKernels.separation: ", TABLE[status / FAULT_COUNT].name, " fails the checked table (status ", status, "); nothing was written.");
		return;
	}
	const WorldAccess &access = access_;
	const Variant grid_variant = access.helper(world, OWN_SEP);
	Object *grid = WorldAccess::object_in(grid_variant);

	const Borrowed<const int32_t> unit_id = access.read_i32(world, ID_WORLD_unit_id);
	const Borrowed<const int32_t> type_index = access.read_i32(world, ID_WORLD_type_index);
	const Borrowed<const int32_t> type_radius = access.read_i32(world, ID_WORLD_type_radius);
	const Borrowed<const int32_t> pos_x = access.read_i32(world, ID_WORLD_pos_x);
	const Borrowed<const int32_t> pos_y = access.read_i32(world, ID_WORLD_pos_y);
	const Borrowed<const int32_t> intent_x = access.read_i32(world, ID_WORLD_intent_x);
	const Borrowed<const int32_t> intent_y = access.read_i32(world, ID_WORLD_intent_y);
	const Borrowed<const int32_t> head = access.read_i32(grid, ID_SEP_head);
	const Borrowed<const int32_t> next = access.read_i32(grid, ID_SEP_next);
	const Borrowed<int32_t> push_x = access.write_i32(world, ID_WORLD_push_x);
	const Borrowed<int32_t> push_y = access.write_i32(world, ID_WORLD_push_y);
	Borrowed<int32_t> stats = access.write_i32(world, ID_WORLD_stats);

	separation::Rows rows;
	rows.count = unit_id.view.size();
	rows.type_index = type_index.view;
	rows.pos_x = pos_x.view;
	rows.pos_y = pos_y.view;
	rows.intent_x = intent_x.view;
	rows.intent_y = intent_y.view;
	rows.push_x = push_x.view;
	rows.push_y = push_y.view;
	separation::Types types;
	types.radius = type_radius.view;
	separation::Grid cells;
	cells.cols = access.int_in(grid, ID_SEP_cols);
	cells.rows = access.int_in(grid, ID_SEP_rows);
	cells.cell_milli = access.int_in(grid, ID_SEP_cell_milli);
	cells.head = head.view;
	cells.next = next.view;
	separation::Rules rules;
	rules.neighbours = access.int_in(world, ID_WORLD_separation_neighbours);
	rules.scan = access.int_in(world, ID_WORLD_separation_scan);
	rules.idle_share = access.int_in(world, ID_WORLD_separation_idle_share);
	rules.push_max = access.int_in(world, ID_WORLD_separation_push_max);
	rules.coincident_divisor = access.int_in(world, ID_WORLD_separation_coincident_divisor);

	const int64_t pairs = separation::run(rows, types, cells, rules);
	stats.view.set(STAT_SEP_PAIRS, stats.view.get(STAT_SEP_PAIRS) + pairs);
}
