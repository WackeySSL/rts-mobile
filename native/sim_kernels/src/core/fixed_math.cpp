// FixedMath.isqrt and FixedMath.line_clear, a mirror of game/sim/FixedMath.gd: see fixed_math.h. MIT.
#include "fixed_math.h"

namespace fixed_math {

namespace {

constexpr int64_t MILLI_PER_TILE = 1000; // World.MILLI_PER_TILE
constexpr int64_t MOVE_CLASSES = 3; // World.MoveClass.size()

// GDScript's clampi, mini and maxi: the lower bound of a clamp is tested first, as in Godot's CLAMP.
int64_t clamp(int64_t value, int64_t low, int64_t high) {
	return value < low ? low : (value > high ? high : value);
}
int64_t smaller(int64_t a, int64_t b) {
	return a < b ? a : b;
}
int64_t larger(int64_t a, int64_t b) {
	return a > b ? a : b;
}

} // namespace

// The five steps of FixedMath.isqrt, which writes them as literals: shift `rest` right by 32, 16, 8, 4 and 2 bits
// when it is at or over 1 shifted left by as much, and add half the shift to `half`.
inline constexpr int64_t SHIFTS[] = { 32, 16, 8, 4, 2 };

int64_t isqrt(int64_t n) {
	if (n <= 0) {
		return 0;
	}
	// The shifts add up to 2 * half and leave 1 to 3 in `rest`, so n < 2 ^ (2 * half + 2).
	int64_t rest = n;
	int64_t half = 0;
	for (const int64_t shift : SHIFTS) {
		if (rest >= (int64_t(1) << shift)) {
			rest >>= shift;
			half += shift >> 1;
		}
	}
	// A power of two at or over the root; Newton's method from above ends on the floor.
	int64_t root = int64_t(1) << (half + 1);
	int64_t next = (root + n / root) >> 1;
	while (next < root) {
		root = next;
		next = (root + n / root) >> 1;
	}
	return root;
}

bool line_clear(const ArrayView<const uint8_t> &move_cost, int64_t cols, int64_t rows, int64_t x0, int64_t y0, int64_t x1, int64_t y1, int64_t move_class) {
	if (cols == 0) {
		return true;
	}
	if (move_class < 0 || move_class >= MOVE_CLASSES) {
		return false;
	}
	const int64_t base = move_class * cols * rows;
	const int64_t max_x = cols * MILLI_PER_TILE;
	const int64_t max_y = rows * MILLI_PER_TILE;
	// Left to right, inside the grid, so every numerator and quotient below is not negative.
	const bool flip = x0 > x1;
	const int64_t ax = clamp(flip ? x1 : x0, 0, max_x);
	const int64_t ay = clamp(flip ? y1 : y0, 0, max_y);
	const int64_t bx = clamp(flip ? x0 : x1, 0, max_x);
	const int64_t by = clamp(flip ? y0 : y1, 0, max_y);
	const int64_t dx = bx - ax;
	const int64_t dy = by - ay;
	const int64_t scale = dx > 0 ? dx * MILLI_PER_TILE : MILLI_PER_TILE;
	const int64_t last_column = smaller(bx / MILLI_PER_TILE, cols - 1);
	for (int64_t column = smaller(ax / MILLI_PER_TILE, cols - 1); column <= last_column; column++) {
		int64_t first_row = smaller(ay, by) / MILLI_PER_TILE;
		int64_t last_row = larger(ay, by) / MILLI_PER_TILE;
		if (dx > 0) {
			const int64_t left_x = larger(column * MILLI_PER_TILE, ax);
			const int64_t right_x = smaller((column + 1) * MILLI_PER_TILE, bx);
			const int64_t left = ay * dx + dy * (left_x - ax);
			const int64_t right = ay * dx + dy * (right_x - ax);
			const int64_t open_end = dy > 0 && column < last_column ? 1 : 0;
			first_row = smaller(left, right) / scale;
			last_row = (larger(left, right) - open_end) / scale;
			if (dy != 0 && left_x > ax && left_x < bx && left % scale == 0) {
				first_row = smaller(first_row, left / scale - 1);
				last_row = larger(last_row, left / scale);
			}
			if (dy != 0 && right_x < bx && right % scale == 0) {
				first_row = smaller(first_row, right / scale - 1);
				last_row = larger(last_row, right / scale);
			}
		}
		const int64_t stop = smaller(last_row, rows - 1) + 1;
		for (int64_t row = smaller(first_row, rows - 1); row < stop; row++) {
			if (move_cost.get(base + row * cols + column) == 0) {
				return false;
			}
		}
	}
	return true;
}

} // namespace fixed_math
