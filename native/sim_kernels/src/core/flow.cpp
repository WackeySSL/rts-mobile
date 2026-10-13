// The FLOW kernel's rules, a mirror of FlowField.gd and FlowCache.gd: see flow.h. MIT.
#include "flow.h"

namespace flow {

// FlowField._swap: the served buffer and the one just integrated trade places.
static void swap_buffers(Slot &slot) {
	const ArrayView<int32_t> served = slot.cost;
	slot.cost = slot.next;
	slot.next = served;
	slot.complete = true;
	slot.swapped = true;
}

void begin(Slot &slot, int64_t goal_cell, int64_t move_class, const ArrayView<const uint8_t> &costs, int64_t cols, int64_t rows) {
	slot.complete = slot.complete && goal_cell == slot.goal_cell && move_class == slot.move_class;
	slot.goal_cell = goal_cell;
	slot.move_class = move_class;
	slot.grid_cols = cols > 0 ? cols : 0;
	slot.cell_count = slot.grid_cols * (rows > 0 ? rows : 0);
	slot.stride = slot.grid_cols + PAD;
	if (!slot.complete) {
		slot.cost.fill(UNREACHED);
	}
	slot.next.fill(UNREACHED);
	slot.bucket_head.fill(-1);
	slot.level = 0;
	slot.pending = 0;
	const int64_t base = move_class * slot.cell_count;
	const bool usable = goal_cell >= 0 && goal_cell < slot.cell_count && move_class >= 0;
	if (!usable || base + slot.cell_count > costs.size()) {
		swap_buffers(slot);
		return;
	}
	slot.pad_cost.fill(0);
	for (int64_t y = 0; y < rows; y++) {
		const int64_t src = base + y * cols;
		const int64_t dst = (y + 1) * slot.stride + 1;
		for (int64_t x = 0; x < cols; x++) {
			slot.pad_cost.set(dst + x, costs.get(src + x));
		}
	}
	// A usable key has a goal inside the map, so cols is above 0 here.
	const int64_t goal = (goal_cell / cols + 1) * slot.stride + goal_cell % cols + 1;
	slot.next.set(goal, 0);
	slot.link_next.set(goal, -1);
	slot.bucket_head.set(0, goal);
	slot.pending = 1;
}

int64_t advance(Slot &slot, int64_t budget) {
	if (slot.pending == 0 || budget <= 0) {
		return 0;
	}
	int64_t queued = slot.pending;
	int64_t dist = slot.level;
	int64_t settled = 0;
	while (settled < budget && queued > 0) {
		const int64_t cell = slot.bucket_head.get(dist & BUCKET_MASK);
		if (cell == -1) {
			dist += 1;
			continue;
		}
		// A pop moves only the head: the new head keeps a stale link_prev, never read because a cell of the
		// bucket being drained is never relaxed (old <= dist). It stays as it is: the lockstep compares it.
		slot.bucket_head.set(dist & BUCKET_MASK, slot.link_next.get(cell));
		queued -= 1;
		settled += 1;
		for (int64_t k = 0; k < NEIGHBOURS; k++) {
			const int64_t other = cell + DY[k] * slot.stride + DX[k];
			const int64_t old = slot.next.get(other);
			const int64_t terrain = slot.pad_cost.get(other);
			if (old <= dist || terrain == 0) {
				continue;
			}
			const int64_t through = dist + terrain * STEP_PERCENT[k] / STEP_BASE;
			if (through >= old) {
				continue;
			}
			// A diagonal step needs both orthogonal cells open (no corner cutting).
			if (STEP_PERCENT[k] != STEP_BASE) {
				if (slot.pad_cost.get(cell + DX[k]) == 0 || slot.pad_cost.get(cell + DY[k] * slot.stride) == 0) {
					continue;
				}
			}
			if (old == UNREACHED) {
				queued += 1;
			} else {
				const int64_t older = slot.link_prev.get(other);
				const int64_t newer = slot.link_next.get(other);
				if (older == -1) {
					slot.bucket_head.set(old & BUCKET_MASK, newer);
				} else {
					slot.link_next.set(older, newer);
				}
				if (newer != -1) {
					slot.link_prev.set(newer, older);
				}
			}
			const int64_t first = slot.bucket_head.get(through & BUCKET_MASK);
			slot.link_next.set(other, first);
			slot.link_prev.set(other, -1);
			if (first != -1) {
				slot.link_prev.set(first, other);
			}
			slot.bucket_head.set(through & BUCKET_MASK, other);
			slot.next.set(other, through);
		}
	}
	slot.pending = queued;
	slot.level = dist;
	if (queued == 0) {
		swap_buffers(slot);
	}
	return settled;
}

void recount(ArrayView<int32_t> ref_count, const ArrayView<const int32_t> &field, int64_t count) {
	ref_count.fill(0);
	const int64_t rows = count < field.size() ? count : field.size();
	for (int64_t row = 0; row < rows; row++) {
		const int64_t slot = field.get(row);
		if (slot >= 0 && slot < ref_count.size()) {
			ref_count.set(slot, ref_count.get(slot) + 1);
		}
	}
}

} // namespace flow
