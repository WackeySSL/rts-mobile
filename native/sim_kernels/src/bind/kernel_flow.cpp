// FLOW, the native twin of FlowCache.run (ADR 0013 sections 2 and 3, plan P30n): the recount of the references from
// the World's `field` column, then FlowCache.advance with FlowField.begin and advance, in place over the arrays of
// the World, the cache and its slots. The rules and the loop of the call are core/flow.h's (flow::run, which the
// sanitizer harness calls too), a mirror of FlowField.gd and FlowCache.gd; this file borrows the arrays and hands
// run() the slots one turn at a time.
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

// The slots of flow.fields for flow::run: one turn at a time, loaded from the slot object and stored back.
class FlowTurns final : public flow::Turns {
public:
	FlowTurns(const WorldAccess &access, const Array &fields) :
			access_(access), fields_(fields) {}

	int64_t pending_of(int64_t slot) override { return access_.int_in(WorldAccess::slot_in(fields_, slot), ID_SLOT_pending); }
	bool load(int64_t slot) override {
		Object *object = WorldAccess::slot_in(fields_, slot);
		if (object == nullptr) {
			return false;
		}
		turn_ = load_turn(access_, object);
		return true;
	}
	flow::Slot &slot() override { return turn_.slot; }
	void store() override { store_turn(access_, turn_); }

private:
	const WorldAccess &access_;
	const Array &fields_;
	SlotTurn turn_;
};

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
	const Borrowed<int32_t> state = access.write_i32(cache, ID_FLOW_status);
	Borrowed<int32_t> stats = access.write_i32(world, ID_WORLD_stats);

	flow::Call call;
	call.ref_count = refs.view;
	call.status = state.view;
	call.field = field.view;
	call.requested = requested.view;
	call.key_goal = key_goal.view;
	call.key_class = key_class.view;
	call.costs = costs.view;
	call.units = unit_id.view.size();
	call.cols = access.int_in(cache, ID_FLOW_cols);
	call.rows = access.int_in(cache, ID_FLOW_rows);
	FlowTurns turns(access, fields);
	const flow::Run run = flow::run(call, budget, turns);
	stats.view.set(STAT_FLOW_CELLS, stats.view.get(STAT_FLOW_CELLS) + run.settled);
}
