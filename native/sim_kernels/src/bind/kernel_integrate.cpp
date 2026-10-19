// INTEGRATE, the native twin of Movement.integrate (ADR 0013 sections 1 to 3, plan P37n): every unit moves by its
// intent plus its push, slides along rock, arrives or stalls, and a FIELD unit looks up its next tile and an ATTACK
// unit re-keys its field, in place over the arrays of the World and of the flow cache. The rules are core/integrate.h's,
// a mirror of Movement.gd, with core/flow.h's best_neighbour and acquire and core/fixed_math.h's isqrt; this file
// borrows the arrays once on entry and hands the pass the slot objects one call at a time.
// Slots: ADR 0013 section 2 has a kernel fetch each slot it touches once per call, bounded by flow_cache_size. Holding the
// cost array of every slot for the whole call needs room for as many as there are, and flow_cache_size has no upper
// bound to size it by, so a slot is fetched where the pass asks for it, at event cadence (a FIELD unit's look-up, a recycle
// of acquire), never per row or per cell. That is the second recorded exception to the rule, beside FLOW's re-read of
// `pending` (plan, P37n).
// Twin: game/sim/Movement.gd (integrate). Tests: tests/sim/native/test_integrate_kernel.gd and the movement suites under both
// implementations (tests/sim/test_movement*.gd); the lockstep over 900 ticks is P37n3. MIT.
#include "sim_kernels.h"

#include <godot_cpp/variant/utility_functions.hpp>

#include "core/integrate.h"

using namespace godot;
using namespace world_access;

namespace {

// The slot objects of flow.fields for the pass. Nothing is kept between calls of the pass: a Served borrows the cost
// array of the slot it was asked for until the next call.
class BoundSlots final : public integrate::Slots {
public:
	BoundSlots(const WorldAccess &access, const Array &fields) :
			access_(access), fields_(fields) {}

	int64_t count() override { return fields_.size(); }
	bool complete(int64_t slot) override { return access_.bool_in(WorldAccess::slot_in(fields_, slot), ID_SLOT_complete); }
	flow::Served served(int64_t slot) override {
		flow::Served found;
		Object *object = WorldAccess::slot_in(fields_, slot);
		if (object == nullptr) {
			return found;
		}
		cost_ = access_.read_i32(object, ID_SLOT_cost);
		found.cost = cost_.view;
		found.grid_cols = access_.int_in(object, ID_SLOT_grid_cols);
		found.cell_count = access_.int_in(object, ID_SLOT_cell_count);
		found.stride = access_.int_in(object, ID_SLOT_stride);
		found.complete = access_.bool_in(object, ID_SLOT_complete);
		return found;
	}
	void recycle(int64_t slot) override {
		Object *object = WorldAccess::slot_in(fields_, slot);
		if (object == nullptr) {
			return;
		}
		cost_ = Borrowed<const int32_t>();
		Borrowed<int32_t> cost = access_.write_i32(object, ID_SLOT_cost);
		cost.view.fill(flow::UNREACHED);
		access_.set(object, ID_SLOT_complete, false);
	}

private:
	const WorldAccess &access_;
	const Array &fields_;
	Borrowed<const int32_t> cost_;
};

} // namespace

void SimKernels::integrate(Object *world) const {
	const int64_t status = access_.check(world, PHASE_INTEGRATE);
	if (status != 0) {
		UtilityFunctions::push_error("SimKernels.integrate: ", TABLE[status / FAULT_COUNT].name, " fails the checked table (status ", status, "); nothing was written.");
		return;
	}
	const WorldAccess &access = access_;
	const Variant cache_variant = access.helper(world, OWN_FLOW);
	Object *cache = WorldAccess::object_in(cache_variant);
	const Variant fields_variant = access.get(cache, ID_FLOW_fields);
	const Array fields = fields_variant;

	// The columns of the World: the ones the pass only reads, then the ones it writes.
	const Borrowed<const int32_t> unit_id = access.read_i32(world, ID_WORLD_unit_id);
	const Borrowed<const int32_t> type_index = access.read_i32(world, ID_WORLD_type_index);
	const Borrowed<const int32_t> push_x = access.read_i32(world, ID_WORLD_push_x);
	const Borrowed<const int32_t> push_y = access.read_i32(world, ID_WORLD_push_y);
	const Borrowed<const int32_t> type_speed = access.read_i32(world, ID_WORLD_type_speed);
	const Borrowed<const int32_t> type_spacing = access.read_i32(world, ID_WORLD_type_spacing);
	const Borrowed<const int32_t> type_move_class = access.read_i32(world, ID_WORLD_type_move_class);
	const Borrowed<const uint8_t> move_cost = access.read_bytes(world, ID_WORLD_move_cost);
	const Borrowed<int32_t> pos_x = access.write_i32(world, ID_WORLD_pos_x);
	const Borrowed<int32_t> pos_y = access.write_i32(world, ID_WORLD_pos_y);
	const Borrowed<int32_t> goal_x = access.write_i32(world, ID_WORLD_goal_x);
	const Borrowed<int32_t> goal_y = access.write_i32(world, ID_WORLD_goal_y);
	const Borrowed<int32_t> group_cell = access.write_i32(world, ID_WORLD_group_cell);
	const Borrowed<int32_t> order = access.write_i32(world, ID_WORLD_order);
	const Borrowed<int32_t> nav_mode = access.write_i32(world, ID_WORLD_nav_mode);
	const Borrowed<int32_t> nav_cell = access.write_i32(world, ID_WORLD_nav_cell);
	const Borrowed<int32_t> field = access.write_i32(world, ID_WORLD_field);
	const Borrowed<int32_t> nav_next = access.write_i32(world, ID_WORLD_nav_next);
	const Borrowed<int32_t> best_dist = access.write_i32(world, ID_WORLD_best_dist);
	const Borrowed<int32_t> stall = access.write_i32(world, ID_WORLD_stall);
	const Borrowed<int32_t> intent_x = access.write_i32(world, ID_WORLD_intent_x);
	const Borrowed<int32_t> intent_y = access.write_i32(world, ID_WORLD_intent_y);
	// The columns of the flow cache, which acquire() writes.
	const Borrowed<int32_t> key_goal = access.write_i32(cache, ID_FLOW_key_goal);
	const Borrowed<int32_t> key_class = access.write_i32(cache, ID_FLOW_key_class);
	const Borrowed<int32_t> key_version = access.write_i32(cache, ID_FLOW_key_version);
	const Borrowed<int32_t> last_used = access.write_i32(cache, ID_FLOW_last_used);
	const Borrowed<int32_t> ref_count = access.write_i32(cache, ID_FLOW_ref_count);
	const Borrowed<int32_t> requested = access.write_i32(cache, ID_FLOW_requested);
	const Borrowed<int32_t> state = access.write_i32(cache, ID_FLOW_status);

	integrate::Rows rows;
	rows.unit_id = unit_id.view;
	rows.type_index = type_index.view;
	rows.push_x = push_x.view;
	rows.push_y = push_y.view;
	rows.pos_x = pos_x.view;
	rows.pos_y = pos_y.view;
	rows.goal_x = goal_x.view;
	rows.goal_y = goal_y.view;
	rows.group_cell = group_cell.view;
	rows.order = order.view;
	rows.nav_mode = nav_mode.view;
	rows.nav_cell = nav_cell.view;
	rows.field = field.view;
	rows.nav_next = nav_next.view;
	rows.best_dist = best_dist.view;
	rows.stall = stall.view;
	rows.intent_x = intent_x.view;
	rows.intent_y = intent_y.view;
	integrate::Types types;
	types.speed = type_speed.view;
	types.spacing = type_spacing.view;
	types.move_class = type_move_class.view;
	integrate::Rules rules;
	rules.map_cols = access.int_in(world, ID_WORLD_map_cols);
	rules.map_rows = access.int_in(world, ID_WORLD_map_rows);
	rules.map_w = access.int_in(world, ID_WORLD_map_w);
	rules.map_h = access.int_in(world, ID_WORLD_map_h);
	rules.map_version = access.int_in(world, ID_WORLD_map_version);
	rules.tick = access.int_in(world, ID_WORLD_tick);
	rules.line_check_period_ticks = access.int_in(world, ID_WORLD_line_check_period_ticks);
	rules.stall_ticks = access.int_in(world, ID_WORLD_stall_ticks);
	rules.stall_range_spacings = access.int_in(world, ID_WORLD_stall_range_spacings);
	rules.attack_rekey_milli = access.int_in(world, ID_WORLD_attack_rekey_milli);
	flow::Keys keys;
	keys.key_goal = key_goal.view;
	keys.key_class = key_class.view;
	keys.key_version = key_version.view;
	keys.last_used = last_used.view;
	keys.ref_count = ref_count.view;
	keys.requested = requested.view;
	keys.status = state.view;
	keys.cols = access.int_in(cache, ID_FLOW_cols);
	keys.rows = access.int_in(cache, ID_FLOW_rows);
	keys.classes = access.int_in(cache, ID_FLOW_classes);
	keys.requests = access.int_in(cache, ID_FLOW_requests);
	const int64_t requests_before = keys.requests;

	BoundSlots slots(access, fields);
	integrate::run(rows, types, move_cost.view, rules, keys, slots);
	// The one scalar acquire() changes; the arrays and the slots' own members were written in place.
	if (keys.requests != requests_before) {
		access.set(cache, ID_FLOW_requests, keys.requests);
	}
}
