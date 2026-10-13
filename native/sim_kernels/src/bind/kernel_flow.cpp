// FLOW, the native twin of FlowCache.run (ADR 0013 sections 2 and 3, plan P30n): the recount of the references from
// the World's `field` column, then FlowCache.advance with FlowField.begin and advance, in place over the arrays of
// the World, the cache and its slots. The rules are core/flow.h's, a mirror of FlowField.gd and FlowCache.gd.
// Twin: game/sim/FlowCache.gd (run). Lockstep test: tests/sim/native/test_flow_lockstep.gd. MIT.
#include "sim_kernels.h"

#include <godot_cpp/variant/utility_functions.hpp>

#include "core/flow.h"

using namespace godot;
using namespace world_access;

namespace {

constexpr int64_t STAT_FLOW_CELLS = 0; // World.Stat.FLOW_CELLS

// What one slot's turn borrows: the Variants keep the arrays alive until the turn ends.
struct SlotTurn {
	Object *object = nullptr;
	Borrowed<int32_t> cost, next, bucket_head, link_next, link_prev;
	Borrowed<uint8_t> pad_cost;
	flow::Slot slot;
};

// Slot `index` of the typed Array flow.fields; the Array keeps it alive.
Object *slot_at(const Array &fields, int64_t index) {
	const Variant item = fields[index];
	return WorldAccess::object_in(item);
}

SlotTurn load_turn(const WorldAccess &access, Object *object) {
	SlotTurn turn;
	turn.object = object;
	turn.cost = access.write_i32(object, ID_SLOT_cost);
	turn.next = access.write_i32(object, ID_SLOT_next);
	turn.bucket_head = access.write_i32(object, ID_SLOT_bucket_head);
	turn.link_next = access.write_i32(object, ID_SLOT_link_next);
	turn.link_prev = access.write_i32(object, ID_SLOT_link_prev);
	turn.pad_cost = access.write_bytes(object, ID_SLOT_pad_cost);
	flow::Slot &slot = turn.slot;
	slot.cost = turn.cost.view;
	slot.next = turn.next.view;
	slot.bucket_head = turn.bucket_head.view;
	slot.link_next = turn.link_next.view;
	slot.link_prev = turn.link_prev.view;
	slot.pad_cost = turn.pad_cost.view;
	slot.goal_cell = access.int_in(object, ID_SLOT_goal_cell);
	slot.move_class = access.int_in(object, ID_SLOT_move_class);
	slot.grid_cols = access.int_in(object, ID_SLOT_grid_cols);
	slot.cell_count = access.int_in(object, ID_SLOT_cell_count);
	slot.stride = access.int_in(object, ID_SLOT_stride);
	slot.level = access.int_in(object, ID_SLOT_level);
	slot.pending = access.int_in(object, ID_SLOT_pending);
	slot.complete = access.bool_in(object, ID_SLOT_complete);
	return turn;
}

// The exit of a turn: the scalars, and the one swap of the Variants that the completion of a field makes (the
// two sets of ADR 0013 section 2). No pointer of the turn is used afterwards.
void store_turn(const WorldAccess &access, const SlotTurn &turn) {
	Object *object = turn.object;
	const flow::Slot &slot = turn.slot;
	access.set(object, ID_SLOT_goal_cell, slot.goal_cell);
	access.set(object, ID_SLOT_move_class, slot.move_class);
	access.set(object, ID_SLOT_grid_cols, slot.grid_cols);
	access.set(object, ID_SLOT_cell_count, slot.cell_count);
	access.set(object, ID_SLOT_stride, slot.stride);
	access.set(object, ID_SLOT_level, slot.level);
	access.set(object, ID_SLOT_pending, slot.pending);
	access.set(object, ID_SLOT_complete, slot.complete);
	if (slot.swapped) {
		access.set(object, ID_SLOT_cost, turn.next.value);
		access.set(object, ID_SLOT_next, turn.cost.value);
	}
}

} // namespace

void SimKernels::flow(Object *world, int64_t budget) const {
	const int64_t status = access_.check(world, PHASE_FLOW);
	if (status != 0) {
		UtilityFunctions::push_error("SimKernels.flow: ", TABLE[status / FAULT_COUNT].name, " fails the checked table (status ", status, "); nothing was written.");
		return;
	}
	const WorldAccess &access = access_;
	const Variant cache_variant = access.helper(world, OWN_FLOW);
	Object *cache = WorldAccess::object_in(cache_variant);
	const Variant fields_variant = access.get(cache, ID_FLOW_fields);
	const Array fields = fields_variant;
	const Borrowed<const int32_t> unit_id = access.read_i32(world, ID_WORLD_unit_id);
	const Borrowed<const int32_t> field = access.read_i32(world, ID_WORLD_field);
	const Borrowed<const uint8_t> costs = access.read_bytes(world, ID_WORLD_move_cost);
	const Borrowed<const int32_t> key_goal = access.read_i32(cache, ID_FLOW_key_goal);
	const Borrowed<const int32_t> key_class = access.read_i32(cache, ID_FLOW_key_class);
	const Borrowed<const int32_t> requested = access.read_i32(cache, ID_FLOW_requested);
	const Borrowed<int32_t> refs = access.write_i32(cache, ID_FLOW_ref_count);
	Borrowed<int32_t> state = access.write_i32(cache, ID_FLOW_status);
	Borrowed<int32_t> stats = access.write_i32(world, ID_WORLD_stats);
	const int64_t cols = access.int_in(cache, ID_FLOW_cols);
	const int64_t rows = access.int_in(cache, ID_FLOW_rows);

	flow::recount(refs.view, field.view, unit_id.view.size);
	const auto pending_of = [&](int64_t slot) { return access.int_in(slot_at(fields, slot), ID_SLOT_pending); };
	int64_t settled = 0;
	while (settled < budget) {
		const int64_t pick = flow::oldest_request(state.view, requested.view, pending_of);
		if (pick == -1) {
			break;
		}
		Object *object = slot_at(fields, pick);
		SlotTurn turn = load_turn(access, object);
		if (state.view.get(pick) == flow::WAITING) {
			flow::begin(turn.slot, key_goal.view.get(pick), key_class.view.get(pick), costs.view, cols, rows);
			state.view.set(pick, flow::ACTIVE);
		}
		settled += flow::advance(turn.slot, budget - settled);
		store_turn(access, turn);
	}
	stats.view.set(STAT_FLOW_CELLS, stats.view.get(STAT_FLOW_CELLS) + settled);
}
