// The FOG kernel's rules, a mirror of FogUpdate.run and _covered in game/sim/FogUpdate.gd and of FogGrid.stamp in
// game/sim/FogGrid.gd: see fog.h. MIT.
#include "fog.h"

namespace fog {

namespace {

constexpr int64_t MILLI_PER_TILE = 1000; // World.MILLI_PER_TILE (FogGrid.MILLI_PER_TILE)

// GDScript's clampi: the lower bound is tested first, as in Godot's CLAMP.
int64_t clamp(int64_t value, int64_t low, int64_t high) {
	return value < low ? low : (value > high ? high : value);
}

int64_t larger(int64_t a, int64_t b) {
	return a > b ? a : b;
}

int64_t smaller(int64_t a, int64_t b) {
	return a < b ? a : b;
}

// Whether the grid has cells to stamp: sides that make its cells (FogGrid.configure always does). The twin takes the same test
// (FogUpdate.run), so the two agree on a grid that is not one, and no index below (row * cols, block * cells) can overflow int64
// for it. A grid with no players is one: no row has a player in 1..0, so nothing is stamped.
bool usable(const Grid &grid) {
	if (grid.cols < 1 || grid.rows < 1) {
		return false;
	}
	// cols * rows == cells, tested by division so that it cannot overflow.
	return grid.cells % grid.cols == 0 && grid.cells / grid.cols == grid.rows;
}

// FogUpdate._covered: the cells of a mask centred on `cell` that lie in the map, which is what stamp walks. `radius` is the
// mask's and `first` its `mask_start` plus the radius.
int64_t covered(const Grid &grid, int64_t cell, int64_t radius, int64_t first) {
	const int64_t width = grid.cols;
	const int64_t centre_x = cell % width;
	const int64_t centre_y = cell / width;
	const int64_t spans = first - centre_y;
	const int64_t last_y = smaller(centre_y + radius, grid.rows - 1);
	int64_t total = 0;
	for (int64_t y = larger(centre_y - radius, 0); y <= last_y; y++) {
		const int64_t reach = grid.mask_half.get(spans + y);
		total += smaller(centre_x + reach, width - 1) - larger(centre_x - reach, 0) + 1;
	}
	return total;
}

} // namespace

void stamp(Grid &grid, int64_t player, int64_t cell, int64_t mask, int64_t delta) {
	if (grid.cols < 1) {
		return;
	}
	const int64_t block = player - 1;
	const int64_t base = block * grid.cells;
	const int64_t width = grid.cols;
	const int64_t centre_x = cell % width;
	const int64_t centre_y = cell / width;
	const int64_t radius = grid.mask_radius.get(mask);
	const int64_t spans = grid.mask_start.get(mask) + radius - centre_y;
	const int64_t list_at = block * grid.dirty_capacity;
	const int64_t capacity = grid.dirty_capacity;
	const int64_t last_y = smaller(centre_y + radius, grid.rows - 1);
	int64_t used = grid.dirty_count.get(block);
	bool flipped = false;
	bool overflowed = false;
	for (int64_t y = larger(centre_y - radius, 0); y <= last_y; y++) {
		const int64_t reach = grid.mask_half.get(spans + y);
		const int64_t row_at = y * width;
		const int64_t last_x = smaller(centre_x + reach, width - 1);
		for (int64_t x = larger(centre_x - reach, 0); x <= last_x; x++) {
			const int64_t at = row_at + x;
			const int64_t before = grid.visible.get(base + at);
			const int64_t after = before + delta;
			grid.visible.set(base + at, after);
			if (after > 0) {
				grid.explored.set(base + at, 1);
			}
			if ((before > 0) == (after > 0)) {
				continue;
			}
			flipped = true;
			if (grid.listed.get(base + at) != 0) {
				continue;
			}
			if (used < capacity) {
				grid.dirty.set(list_at + used, at);
				used += 1;
				grid.listed.set(base + at, 1);
			} else {
				overflowed = true;
			}
		}
	}
	grid.dirty_count.set(block, used);
	if (overflowed) {
		grid.dirty_full.set(block, 1);
	}
	if (flipped) {
		grid.version.set(block, grid.version.get(block) + 1);
	}
}

int64_t run(Grid &grid, Rows &rows, const Rules &rules) {
	if (!usable(grid)) {
		return 0;
	}
	const int64_t period = larger(rules.fog_period_ticks, 1);
	int64_t total = 0;
	for (int64_t row = 0; row < rows.count; row++) {
		const int64_t player = rows.owner.get(row);
		// The left side is negative for a player past the tick, and % truncates toward zero as in GDScript.
		if (player < 1 || player > grid.player_count || (rules.tick - player + 1) % period != 0) {
			continue;
		}
		const int64_t cell = clamp(rows.pos_y.get(row) / MILLI_PER_TILE, 0, grid.rows - 1) * grid.cols + clamp(rows.pos_x.get(row) / MILLI_PER_TILE, 0, grid.cols - 1);
		const int64_t old = rows.fog_cell.get(row);
		if (cell == old) {
			continue;
		}
		const int64_t mask = smaller(rows.type_index.get(row), rules.pad_mask);
		const int64_t radius = grid.mask_radius.get(mask);
		const int64_t first = grid.mask_start.get(mask) + radius;
		stamp(grid, player, cell, mask, 1);
		total += covered(grid, cell, radius, first);
		if (old >= 0) {
			stamp(grid, player, old, mask, -1);
			total += covered(grid, old, radius, first);
		}
		rows.fog_cell.set(row, cell);
	}
	return total;
}

} // namespace fog
