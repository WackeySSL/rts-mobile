// The rules of the INTEGRATE kernel (ADR 0013 sections 1 and 2, plan P37n): Movement.integrate and the helpers it
// calls, over views of the arrays the kernel borrowed. Every unit moves by its intent plus its push, clamped to the
// map and slid along rock; a unit arrives, or stalls, and its order ends; a FIELD unit looks up its next tile with
// flow::best_neighbour at event cadence, an ATTACK unit re-keys its field, and a unit that waits for no free slot
// takes the field of its own goal (flow::acquire). Plain C++17, no Godot header, no float. Rule values come in
// through `Rules`, read from the World by the bind layer.
// Twin: game/sim/Movement.gd (integrate, _refresh_next, _rekey, _take_own_field, _end_order) and game/sim/World.gd
// (cell_of, is_passable, which integrate.cpp copies), in the twin's row order, so that the full state matches after every
// call. Tests: tests/sim/test_movement*.gd under both implementations, tests/sim/native/test_integrate_kernel.gd. MIT.
#pragma once

#include <cstdint>
#include <limits>

#include "array_view.h"
#include "flow.h"

namespace integrate {

// The slots whose `complete` the pass asks the slot objects for once per call (and again only after a recycle): the value
// bits of an int64_t, so that a slot's bit is a shift by 0 to 62. A slot past them is asked on each use.
inline constexpr int64_t MEMO_SLOTS = std::numeric_limits<int64_t>::digits;

// The per-row columns of the World that the pass reads or writes (World.ROW_ARRAYS and the scratch arrays). A row
// is an index in ascending id order; the scratch arrays (intent, push) may be longer than the rows.
struct Rows {
	ArrayView<const int32_t> unit_id, type_index, push_x, push_y;
	ArrayView<int32_t> pos_x, pos_y, goal_x, goal_y, group_cell, order, nav_mode, nav_cell, field, nav_next, best_dist, stall, intent_x, intent_y;
};

// The per-type tables (World.type_*).
struct Types {
	ArrayView<const int32_t> speed, spacing, move_class;
};

// The ints of the World that the pass reads: the map, the tick and the rule values (data/rules.tres).
struct Rules {
	int64_t map_cols = 0, map_rows = 0, map_w = 0, map_h = 0, map_version = 0, tick = 0;
	int64_t line_check_period_ticks = 0, stall_ticks = 0, stall_range_spacings = 0, attack_rekey_milli = 0;
};

// The slot objects of FlowCache.fields as the pass reaches them: the bind layer over the Godot objects, the sanitizer
// harness over plain buffers. A Served that a call returns is valid until the next call of this object.
class Slots {
public:
	virtual ~Slots() = default;
	// The number of slots (fields.size()).
	virtual int64_t count() = 0;
	// slots[slot].complete; false for no such slot. The pass asks once per slot below MEMO_SLOTS and call, and again only
	// after recycle() of that slot (a bind layer pays an Object::get for each ask, which ADR 0013 section 2 forbids per row).
	virtual bool complete(int64_t slot) = 0;
	// The served field of slots[slot]: the cost array and what indexes it; an empty field for no such slot.
	virtual flow::Served served(int64_t slot) = 0;
	// What FlowCache.acquire does to a slot that takes a new key: complete false, cost all UNREACHED.
	virtual void recycle(int64_t slot) = 0;
};

// Movement.integrate. `keys` holds the cache's columns and counters, which acquire() changes in place; `requests` is
// stored back by the caller.
void run(const Rows &rows, const Types &types, const ArrayView<const uint8_t> &move_cost, const Rules &rules, flow::Keys &keys, Slots &slots);

} // namespace integrate
