// The rules of the FOG kernel (ADR 0013 sections 1 and 2, plan P46n): FogUpdate.run, which moves the sight disc of every
// row whose player has its turn, and FogGrid.stamp, the disc stamp it is made of, over views of the arrays the kernel
// borrowed. Row by row in ascending order: a row whose cell differs from `fog_cell` stamps the disc of its new cell first
// and unstamps the old one after it (ADR 0010 section 1's status note of 2026-10-13), so only the cells that really flip
// are listed. A stamp adds its delta to the visible count of every cell of the mask's disc inside the map, marks the cells
// it leaves visible as explored, lists a cell that flips once per update (a fixed block of the flat `dirty` array, with a
// byte `listed` per player and cell; a cell that finds its block full sets the "full" flag and is not marked) and grows the
// player's version by one if any cell flipped. Plain C++17, no Godot header, no float. Rule values come in through `Rules`
// and the grid's own columns, read from the World by the bind layer.
// Twin: game/sim/FogUpdate.gd (run, _covered) and game/sim/FogGrid.gd (stamp), in the twin's row order, so that the full
// state matches after every call. FogUpdate.begin, World.remove_dead's unstamp and World.prepare's initial stamp stay
// GDScript (REMOVE and PREPARE are not ported phases): they call FogGrid.stamp, which therefore stays the reference.
// Tests: tests/sim/test_fog.gd, test_fog_edges.gd and test_fog_grid.gd under both implementations (the last through
// tests/sim/support/fog_stamper.gd, as there is no test-only bound entry) and tests/sim/native/test_fog_kernel.gd (the names,
// the in-place writes, the guards and the range); the 900-tick lockstep and the crafted cases are P46n2, later. MIT.
//
// Range. The pass is exact in int64 while `tick - player + 1` stays inside int64 (a match counter, a few million at the
// most), and while the sides of the grid make its cells (configure() does): the sizes of the arrays are checked against
// `player_count * cells`, not against `cols * rows`, so a grid that says otherwise is no fog at all (see usable()) and no
// index can overflow. The mask tables are as add_mask() builds them: a radius and half-widths below 2^31 (an int32 element).
// A position outside the map gives the nearest edge cell, as World.cell_of does. Past the range the production build wraps
// like the twin (-fwrapv), so the two still agree; the sanitizer build, which has no -fwrapv, aborts.
#pragma once

#include <cstdint>

#include "array_view.h"

namespace fog {

// World.fog as the stamp and the update write it (FogGrid): the sizes, the per-player blocks and the mask tables. `visible`,
// `explored` and `listed` hold `player_count` blocks of `cells` entries, at (player - 1) * cells + cell; `version`,
// `dirty_count` and `dirty_full` hold one entry per player; `dirty` holds `player_count` blocks of `dirty_capacity` cells.
// A mask is `mask_start[mask]` (where its rows start in `mask_half`), `mask_radius[mask]` (rows above and below its centre)
// and one half-width in tiles per row, from dy = -radius down.
struct Grid {
	int64_t cols = 0, rows = 0, cells = 0, player_count = 0, dirty_capacity = 0;
	ArrayView<int32_t> visible, dirty, dirty_count, dirty_full, version;
	ArrayView<uint8_t> explored, listed;
	ArrayView<const int32_t> mask_start, mask_radius, mask_half;
};

// The per-row columns of the World that the update reads or writes (World.ROW_ARRAYS): the owner (0 = none), the type index,
// the position in milli-tiles and `fog_cell`, the cell last stamped (-1 = none). `count` is the number of rows.
struct Rows {
	int64_t count = 0;
	ArrayView<const int32_t> owner, type_index, pos_x, pos_y;
	ArrayView<int32_t> fog_cell;
};

// The ints of the World that the update reads: the tick, the cadence (data/rules.tres, used as the twin uses it: a period
// below 1 is 1) and the id of the pad mask, `type_sight.size()`. A type index past the pad takes the pad mask (sight 0).
struct Rules {
	int64_t tick = 0, fog_period_ticks = 0, pad_mask = 0;
};

// FogGrid.stamp: `delta` (+1 stamps, -1 unstamps) to the visible count of every cell of the mask's disc centred on `cell`,
// clipped to the map, in `player`'s block. `cell` must be in the map, `player` in 1..player_count and `mask` a mask of the
// grid; an index outside an array reads 0 and writes nothing (ArrayView), so a call that breaks this corrupts nothing.
void stamp(Grid &grid, int64_t player, int64_t cell, int64_t mask, int64_t delta);

// FogUpdate.run: the rows of the players whose turn it is move their disc from `fog_cell` to the cell of their position
// (a row not stamped yet, -1, only stamps). Returns the cells those stamps cover, clipped to the map, which the caller adds
// to stats[FOG_CELLS]. A grid with no cells, or sides that do not make its cells, does nothing and returns 0.
int64_t run(Grid &grid, Rows &rows, const Rules &rules);

} // namespace fog
