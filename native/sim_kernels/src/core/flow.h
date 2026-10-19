// The rules of the FLOW kernel (ADR 0013 section 2, plan P30n): FlowField.begin and advance, FlowCache.recount and
// the pick of the next request, and run, the loop of one FLOW call, over views of the arrays the kernel borrowed. The
// INTEGRATE kernel (plan P37n) adds the part of the cache that units use: best_neighbour and acquire. Plain C++17, no
// Godot header.
// Twin: game/sim/FlowField.gd and FlowCache.gd, in the twin's order, so that the full state matches after every call.
// Tests: tests/sim/native/test_flow_lockstep.gd (the FLOW rules), tests/sim/native/test_integrate_kernel.gd and, for
// best_neighbour and acquire, the INTEGRATE lockstep in test_integrate_lockstep.gd and test_integrate_lockstep_cases.gd (same
// folder: the slot tables after every tick, the scan-order ties). MIT.
#pragma once

#include <cstdint>

#include "array_view.h"

namespace flow {

constexpr int64_t UNREACHED = 0x3FFFFFFF; // FlowField.UNREACHED
constexpr int64_t BUCKETS = 512; // FlowField.BUCKETS
constexpr int64_t BUCKET_MASK = BUCKETS - 1; // FlowField.BUCKET_MASK
constexpr int64_t PAD = 2; // FlowField.PAD
constexpr int64_t NEIGHBOURS = 8; // len(FlowField.DX)
inline constexpr int64_t DX[NEIGHBOURS] = { -1, 0, 1, -1, 1, -1, 0, 1 }; // FlowField.DX
inline constexpr int64_t DY[NEIGHBOURS] = { -1, -1, -1, 0, 0, 1, 1, 1 }; // FlowField.DY
inline constexpr int64_t STEP_PERCENT[NEIGHBOURS] = { 14, 10, 14, 10, 10, 14, 10, 14 }; // FlowField.STEP_PERCENT
constexpr int64_t STEP_BASE = 10; // FlowField.STEP_BASE
constexpr int64_t FREE = 0; // FlowCache.Status.FREE
constexpr int64_t WAITING = 1; // FlowCache.Status.WAITING
constexpr int64_t ACTIVE = 2; // FlowCache.Status.ACTIVE

// One FlowField: its arrays as views and its int and bool members. The kernel loads it from the slot object and
// stores it back; `swapped` tells it that cost and next traded places, so that the members trade the same way.
struct Slot {
	ArrayView<int32_t> cost, next, bucket_head, link_next, link_prev;
	ArrayView<uint8_t> pad_cost;
	int64_t goal_cell = -1, move_class = 0, grid_cols = 0, cell_count = 0, stride = 0, level = 0, pending = 0;
	bool complete = false;
	bool swapped = false;
};

// FlowField.begin: the check on entry found every array at the padded size, so reserve() has nothing to resize.
void begin(Slot &slot, int64_t goal_cell, int64_t move_class, const ArrayView<const uint8_t> &costs, int64_t cols, int64_t rows);
// FlowField.advance: settles at most `budget` cells; the call that settles the last queued cell swaps the buffers.
int64_t advance(Slot &slot, int64_t budget);
// FlowCache.recount: every slot's references from the first `count` entries of the World's `field` column.
void recount(ArrayView<int32_t> ref_count, const ArrayView<const int32_t> &field, int64_t count);

// FlowCache._oldest_request: the slot with an integration to start or finish and the lowest request number, or -1.
// `pending_of(slot)` reads the `pending` of an ACTIVE slot's field.
template <typename PendingOf>
int64_t oldest_request(const ArrayView<int32_t> &status, const ArrayView<const int32_t> &requested, PendingOf pending_of) {
	int64_t best = -1;
	for (int64_t slot = 0; slot < status.size(); slot++) {
		bool work = status.get(slot) == WAITING;
		if (status.get(slot) == ACTIVE) {
			work = pending_of(slot) > 0;
		}
		if (work && (best == -1 || requested.get(slot) < requested.get(best))) {
			best = slot;
		}
	}
	return best;
}

// What one FLOW call works over: the World's `field` column and `move_cost`, and FlowCache's columns and map size.
// `status` and `ref_count` are written, the rest is read.
struct Call {
	ArrayView<int32_t> ref_count, status;
	ArrayView<const int32_t> field, requested, key_goal, key_class;
	ArrayView<const uint8_t> costs;
	int64_t units = 0, cols = 0, rows = 0;
};

// The slots as run() reaches them, one turn at a time: bind/kernel_flow.cpp over the slot objects, the sanitizer
// harness over plain buffers. run() calls them in this order only: pending_of for each slot of a pick, then load,
// slot, store.
class Turns {
public:
	virtual ~Turns() = default;
	// The `pending` of the field of an ACTIVE slot.
	virtual int64_t pending_of(int64_t slot) = 0;
	// Loads the slot of the pick into the turn; false when there is no such slot, which ends the call.
	virtual bool load(int64_t slot) = 0;
	// The loaded slot, which run() changes in place.
	virtual Slot &slot() = 0;
	// The exit of the turn: the scalars and the swap, if run() made one.
	virtual void store() = 0;
};

struct Run {
	int64_t settled = 0; // the cells settled, which the kernel adds to stats[FLOW_CELLS]
	bool stuck = false; // a pick that neither began nor settled: the loop would repeat for ever (unreachable)
};

// FlowCache.run without its stats line (the kernel adds `settled`): the recount of the references, then FlowCache.advance
// with `budget` cells: the oldest request, begin() on a WAITING slot, advance() until the budget is spent. Every pick
// begins a field or settles a cell, so the loop ends; `stuck` stops it if one did neither, and the harness reports it.
Run run(const Call &call, int64_t budget, Turns &turns);

// The part of a FlowField that units read: its served `cost` and what indexes it. `complete` is the flag of the slot.
struct Served {
	ArrayView<const int32_t> cost;
	int64_t grid_cols = 0, cell_count = 0, stride = 0;
	bool complete = false;
};

// FlowField.best_neighbour: the neighbour with the lowest served cost strictly below this cell's, the first of
// NW, N, NE, W, E, SW, S, SE on a tie, a diagonal only past two reached orthogonal cells; -1 at the goal and at an
// unreached or outside cell. Cells are plain cells, as in the twin.
int64_t best_neighbour(const Served &field, int64_t cell);

// FlowCache's slot columns and counters as acquire() reads and writes them (the `requests` counter is stored back by
// the kernel after the call).
struct Keys {
	ArrayView<int32_t> key_goal, key_class, key_version, last_used, ref_count, requested, status;
	int64_t cols = 0, rows = 0, classes = 0, requests = 0;
};

struct Acquired {
	int64_t slot = -1; // -1: the goal is no cell, the class is none, or every slot is referenced
	bool recycled = false; // the slot took a new key: its field serves nothing (complete false, cost all UNREACHED)
};

// FlowCache.acquire: the slot that holds the key (its last use becomes `tick`), else a free one, else the least recently
// used one with no references, ties to the lower slot. The slot it hands out counts as referenced until the next
// recount() (a provisional reference). A recycled slot is the caller's to clear, which is the one part of acquire that
// reaches a slot object.
Acquired acquire(Keys &keys, int64_t goal_cell, int64_t move_class, int64_t map_version, int64_t tick);

} // namespace flow
