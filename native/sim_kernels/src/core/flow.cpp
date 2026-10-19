// The FLOW kernel's rules and the lookups of the INTEGRATE kernel, a mirror of FlowField.gd and FlowCache.gd: see
// flow.h. MIT.
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

Run run(const Call &call, int64_t budget, Turns &turns) {
	recount(call.ref_count, call.field, call.units);
	ArrayView<int32_t> status = call.status;
	const auto pending_of = [&turns](int64_t slot) { return turns.pending_of(slot); };
	Run result;
	while (result.settled < budget) {
		const int64_t pick = oldest_request(status, call.requested, pending_of);
		if (pick == -1 || !turns.load(pick)) {
			break;
		}
		Slot &slot = turns.slot();
		const bool starts = status.get(pick) == WAITING;
		if (starts) {
			begin(slot, call.key_goal.get(pick), call.key_class.get(pick), call.costs, call.cols, call.rows);
			status.set(pick, ACTIVE);
		}
		const int64_t advanced = advance(slot, budget - result.settled);
		result.settled += advanced;
		turns.store();
		if (!starts && advanced == 0) {
			result.stuck = true;
			break;
		}
	}
	return result;
}

int64_t best_neighbour(const Served &field, int64_t cell) {
	// The twin divides by grid_cols and stride, which a begun field has above 0; a slot never begun has no cells.
	if (cell < 0 || cell >= field.cell_count || field.grid_cols <= 0 || field.stride <= 0) {
		return -1;
	}
	const int64_t here = (cell / field.grid_cols + 1) * field.stride + cell % field.grid_cols + 1;
	int64_t best = field.cost.get(here);
	if (best == UNREACHED) {
		return -1;
	}
	int64_t pick = -1;
	for (int64_t k = 0; k < NEIGHBOURS; k++) {
		const int64_t other = here + DY[k] * field.stride + DX[k];
		if (field.cost.get(other) >= best) {
			continue;
		}
		if (STEP_PERCENT[k] != STEP_BASE) {
			if (field.cost.get(here + DX[k]) == UNREACHED || field.cost.get(here + DY[k] * field.stride) == UNREACHED) {
				continue;
			}
		}
		best = field.cost.get(other);
		pick = other;
	}
	if (pick == -1) {
		return -1;
	}
	return (pick / field.stride - 1) * field.grid_cols + pick % field.stride - 1;
}

Acquired acquire(Keys &keys, int64_t goal_cell, int64_t move_class, int64_t map_version, int64_t tick) {
	Acquired none;
	if (goal_cell < 0 || goal_cell >= keys.cols * keys.rows || move_class < 0 || move_class >= keys.classes) {
		return none;
	}
	int64_t free_slot = -1;
	int64_t oldest = -1;
	for (int64_t slot = 0; slot < keys.status.size(); slot++) {
		if (keys.status.get(slot) == FREE) {
			if (free_slot == -1) {
				free_slot = slot;
			}
		} else if (keys.key_goal.get(slot) == goal_cell && keys.key_class.get(slot) == move_class && keys.key_version.get(slot) == map_version) {
			keys.last_used.set(slot, tick);
			keys.ref_count.set(slot, keys.ref_count.get(slot) + 1);
			Acquired held;
			held.slot = slot;
			return held;
		} else if (keys.ref_count.get(slot) == 0 && (oldest == -1 || keys.last_used.get(slot) < keys.last_used.get(oldest))) {
			oldest = slot;
		}
	}
	const int64_t pick = free_slot != -1 ? free_slot : oldest;
	if (pick == -1) {
		return none;
	}
	keys.key_goal.set(pick, goal_cell);
	keys.key_class.set(pick, move_class);
	keys.key_version.set(pick, map_version);
	keys.last_used.set(pick, tick);
	keys.ref_count.set(pick, keys.ref_count.get(pick) + 1);
	// FlowCache._request: the next request number, and the slot waits for its integration.
	keys.requests += 1;
	keys.requested.set(pick, keys.requests);
	keys.status.set(pick, WAITING);
	Acquired fresh;
	fresh.slot = pick;
	fresh.recycled = true;
	return fresh;
}

} // namespace flow
