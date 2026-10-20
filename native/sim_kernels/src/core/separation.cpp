// The SEPARATION kernel's rules, a mirror of Separation.run in game/sim/Separation.gd: see separation.h. MIT.
#include "separation.h"

namespace separation {

namespace {

constexpr int64_t BLOCK_CELLS = 9; // Separation.BLOCK_CELLS
constexpr int64_t BLOCK_SIDE = 3; // Separation.BLOCK_SIDE
constexpr int64_t PERCENT = 100; // Separation.PERCENT
constexpr int64_t EQUAL_SHARE = 50; // Separation.EQUAL_SHARE
constexpr int64_t PAIR_DENOMINATOR = 2; // Separation.PAIR_DENOMINATOR

// GDScript's clampi: the lower bound is tested first, as in Godot's CLAMP.
int64_t clamp(int64_t value, int64_t low, int64_t high) {
	return value < low ? low : (value > high ? high : value);
}

// GDScript's signi.
int64_t sign(int64_t value) {
	return value > 0 ? 1 : (value < 0 ? -1 : 0);
}

} // namespace

int64_t run(const Rows &rows, const Types &types, const Grid &grid, const Rules &rules) {
	const ArrayView<const int32_t> type_index = rows.type_index;
	const ArrayView<const int32_t> pos_x = rows.pos_x;
	const ArrayView<const int32_t> pos_y = rows.pos_y;
	const ArrayView<const int32_t> intent_x = rows.intent_x;
	const ArrayView<const int32_t> intent_y = rows.intent_y;
	ArrayView<int32_t> push_x = rows.push_x;
	ArrayView<int32_t> push_y = rows.push_y;
	const ArrayView<const int32_t> radii = types.radius;
	const ArrayView<const int32_t> heads = grid.head;
	const ArrayView<const int32_t> links = grid.next;
	const int64_t cols = grid.cols;
	const int64_t lines = grid.rows;
	const int64_t side = grid.cell_milli;
	const int64_t count = rows.count;
	const int64_t scan_cap = rules.scan;
	const int64_t hit_cap = rules.neighbours;
	const int64_t idle_share = clamp(rules.idle_share, 0, PERCENT);
	const int64_t divisor = rules.coincident_divisor > 1 ? rules.coincident_divisor : 1;
	const int64_t push_max = rules.push_max > 0 ? rules.push_max : 0;
	int64_t pairs = 0;
	push_x.fill(0);
	push_y.fill(0);
	// No cells (an empty map) or a cell side below 1 (SpatialGrid.configure keeps it at 1 or more): the pushes stay 0.
	if (cols == 0 || side < 1) {
		return 0;
	}
	for (int64_t row = 0; row < count; row++) {
		const int64_t x = pos_x.get(row);
		const int64_t y = pos_y.get(row);
		const int64_t radius = radii.get(type_index.get(row));
		const bool moving = intent_x.get(row) != 0 || intent_y.get(row) != 0;
		const int64_t column = clamp(x / side, 0, cols - 1);
		const int64_t line = clamp(y / side, 0, lines - 1);
		int64_t sum_x = 0;
		int64_t sum_y = 0;
		int64_t looked = 0;
		int64_t hits = 0;
		int64_t block = 0;
		// The inner loop enforces the caps; testing them here as well only skips the cells left.
		while (block < BLOCK_CELLS && looked < scan_cap && hits < hit_cap) {
			const int64_t scan_column = column + block % BLOCK_SIDE - 1;
			const int64_t scan_line = line + block / BLOCK_SIDE - 1;
			block += 1;
			if (scan_column < 0 || scan_column >= cols || scan_line < 0 || scan_line >= lines) {
				continue;
			}
			int64_t next = heads.get(scan_line * cols + scan_column);
			while (next != -1 && looked < scan_cap && hits < hit_cap) {
				const int64_t other = next;
				next = links.get(other);
				if (other == row) {
					continue;
				}
				looked += 1;
				const int64_t dx = x - pos_x.get(other);
				const int64_t dy = y - pos_y.get(other);
				const int64_t d2 = dx * dx + dy * dy;
				const int64_t reach = radius + radii.get(type_index.get(other));
				const int64_t reach2 = reach * reach;
				if (d2 >= reach2) {
					continue;
				}
				hits += 1;
				int64_t pair_x = 0;
				int64_t pair_y = 0;
				if (d2 * divisor * divisor < reach2) {
					const int64_t quotient = reach / divisor;
					const int64_t fixed_push = quotient < push_max ? quotient : push_max;
					if (d2 == 0) {
						pair_x = row < other ? -fixed_push : fixed_push;
					} else {
						pair_x = fixed_push * sign(dx);
						pair_y = fixed_push * sign(dy);
					}
				} else {
					const int64_t weight = reach2 - d2;
					pair_x = dx * weight / (PAIR_DENOMINATOR * reach2);
					pair_y = dy * weight / (PAIR_DENOMINATOR * reach2);
				}
				int64_t share = EQUAL_SHARE;
				const bool other_moving = intent_x.get(other) != 0 || intent_y.get(other) != 0;
				if (moving != other_moving) {
					share = moving ? PERCENT - idle_share : idle_share;
				}
				sum_x += pair_x * share / PERCENT;
				sum_y += pair_y * share / PERCENT;
			}
		}
		pairs += looked;
		push_x.set(row, clamp(sum_x, -push_max, push_max));
		push_y.set(row, clamp(sum_y, -push_max, push_max));
	}
	return pairs;
}

} // namespace separation
