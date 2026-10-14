// The rules of the FLOW kernel (ADR 0013 section 2, plan P30n): FlowField.begin and advance, FlowCache.recount and
// the pick of the next request, over views of the arrays the kernel borrowed. Plain C++17, no Godot header.
// Twin: game/sim/FlowField.gd and FlowCache.gd, in the twin's order, so that the full state matches after every call.
// Test: tests/sim/native/test_flow_lockstep.gd. MIT.
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

} // namespace flow
