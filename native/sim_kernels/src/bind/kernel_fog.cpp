// FOG, the native twin of FogUpdate.run (ADR 0013 sections 1 to 3, plan P46n): the players whose turn it is move the sight disc
// of each of their rows to the cell of its position, in place over the arrays of the World and of its FogGrid (the visible
// counts, the explored bytes, the version, the dirty-list blocks, their counts and flags, and the `listed` marks), and the
// cells the stamps cover are added to stats[FOG_CELLS]. FogUpdate.begin (the dirty lists emptied before the removal),
// World.remove_dead's unstamp and World.prepare's initial stamp stay GDScript. The rules are core/fog.h's, a mirror of
// FogUpdate.gd and FogGrid.gd; this file borrows the arrays once on entry and adds the count on exit.
// Twin: game/sim/FogUpdate.gd (run). Tests: tests/sim/test_fog.gd, test_fog_edges.gd and test_fog_grid.gd under both
// implementations and tests/sim/native/test_fog_kernel.gd; lockstep (P46n2): later. MIT.
#include "sim_kernels.h"

#include <godot_cpp/variant/utility_functions.hpp>

#include "core/fog.h"

using namespace godot;
using namespace world_access;

namespace {

constexpr int64_t STAT_FOG_CELLS = 4; // World.Stat.FOG_CELLS

} // namespace

void SimKernels::fog(Object *world) const {
	const int64_t status = access_.check(world, PHASE_FOG);
	if (status != 0) {
		UtilityFunctions::push_error("SimKernels.fog: ", TABLE[status / FAULT_COUNT].name, " fails the checked table (status ", status, "); nothing was written.");
		return;
	}
	const WorldAccess &access = access_;
	const Variant grid_variant = access.helper(world, OWN_FOG);
	Object *fog_grid = WorldAccess::object_in(grid_variant);

	// The columns and tables the pass only reads, then the ones it writes.
	const Borrowed<const int32_t> unit_id = access.read_i32(world, ID_WORLD_unit_id);
	const Borrowed<const int32_t> owner = access.read_i32(world, ID_WORLD_owner);
	const Borrowed<const int32_t> type_index = access.read_i32(world, ID_WORLD_type_index);
	const Borrowed<const int32_t> pos_x = access.read_i32(world, ID_WORLD_pos_x);
	const Borrowed<const int32_t> pos_y = access.read_i32(world, ID_WORLD_pos_y);
	const Borrowed<const int32_t> type_sight = access.read_i32(world, ID_WORLD_type_sight);
	const Borrowed<const int32_t> mask_start = access.read_i32(fog_grid, ID_FOG_mask_start);
	const Borrowed<const int32_t> mask_radius = access.read_i32(fog_grid, ID_FOG_mask_radius);
	const Borrowed<const int32_t> mask_half = access.read_i32(fog_grid, ID_FOG_mask_half);
	const Borrowed<int32_t> fog_cell = access.write_i32(world, ID_WORLD_fog_cell);
	Borrowed<int32_t> stats = access.write_i32(world, ID_WORLD_stats);
	const Borrowed<int32_t> visible = access.write_i32(fog_grid, ID_FOG_visible);
	const Borrowed<uint8_t> explored = access.write_bytes(fog_grid, ID_FOG_explored);
	const Borrowed<uint8_t> listed = access.write_bytes(fog_grid, ID_FOG_listed);
	const Borrowed<int32_t> version = access.write_i32(fog_grid, ID_FOG_version);
	const Borrowed<int32_t> dirty = access.write_i32(fog_grid, ID_FOG_dirty);
	const Borrowed<int32_t> dirty_count = access.write_i32(fog_grid, ID_FOG_dirty_count);
	const Borrowed<int32_t> dirty_full = access.write_i32(fog_grid, ID_FOG_dirty_full);

	fog::Grid grid;
	grid.cols = access.int_in(fog_grid, ID_FOG_cols);
	grid.rows = access.int_in(fog_grid, ID_FOG_rows);
	grid.cells = access.int_in(fog_grid, ID_FOG_cells);
	grid.player_count = access.int_in(fog_grid, ID_FOG_player_count);
	grid.dirty_capacity = access.int_in(fog_grid, ID_FOG_dirty_capacity);
	grid.visible = visible.view;
	grid.dirty = dirty.view;
	grid.dirty_count = dirty_count.view;
	grid.dirty_full = dirty_full.view;
	grid.version = version.view;
	grid.explored = explored.view;
	grid.listed = listed.view;
	grid.mask_start = mask_start.view;
	grid.mask_radius = mask_radius.view;
	grid.mask_half = mask_half.view;
	fog::Rows rows;
	rows.count = unit_id.view.size();
	rows.owner = owner.view;
	rows.type_index = type_index.view;
	rows.pos_x = pos_x.view;
	rows.pos_y = pos_y.view;
	rows.fog_cell = fog_cell.view;
	fog::Rules rules;
	rules.tick = access.int_in(world, ID_WORLD_tick);
	rules.fog_period_ticks = access.int_in(world, ID_WORLD_fog_period_ticks);
	rules.pad_mask = type_sight.view.size();

	const int64_t covered = fog::run(grid, rows, rules);
	stats.view.set(STAT_FOG_CELLS, stats.view.get(STAT_FOG_CELLS) + covered);
}
