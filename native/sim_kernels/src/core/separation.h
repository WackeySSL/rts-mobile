// The rules of the SEPARATION kernel (ADR 0013 sections 1 and 2, plan P39n): Separation.run over views of the arrays the
// kernel borrowed. Every unit scans the 3x3 cells of the separation grid around its own, row by row, each cell's list in
// ascending id order; it looks at most at `scan` other units and uses the first `neighbours` that overlap it; each pair
// gives a push (the sqrt-free formula, or the fixed push for a near-coincident pair), a share of it goes to the unit, and
// the unit's sum is clamped. The grid is the one the GDScript rebuild wrote this tick (SpatialGrid, `head` per cell and
// `next` per row): the pass never rebuilds it. Plain C++17, no Godot header, no float. Rule values come in through
// `Rules`, read from the World by the bind layer.
// Twin: game/sim/Separation.gd (run), in the twin's row order, so that the full state matches after every call. Tests:
// tests/sim/test_separation*.gd under both implementations, tests/sim/native/test_separation_kernel.gd (crafted cases and
// the names), and the lockstep of P39n2: test_separation_lockstep.gd, _cases.gd and _random.gd (same folder). MIT.
//
// Range (the decision of P39n, which records it and clamps nothing). The pass is exact in int64 while
//   - the positions stay within 10^9 milli-tiles of the origin in both axes (a million tiles; a map is a few hundred), so
//     that d2 = dx*dx + dy*dy of any two units stays below 2^63;
//   - the two radii of a pair sum to a `reach` of at most 2,097,151 (so that reach^3, the bound of dx * weight in the
//     formula push, stays below 2^63), and reach * coincident_divisor is at most 3,037,000,499 (the integer square root
//     of INT64_MAX), so that d2 * divisor * divisor < (reach * divisor)^2 cannot overflow. Every radius in data/units is at
//     most 500 milli-tiles, a reach of at most 1000, so the divisor may be up to 3,037,000 (the rule is 4); one reach of
//     2,000,000 would allow a divisor of 1518.
// Past that range the production build wraps like the twin (-fwrapv), so the two still agree, on a meaningless push; the
// sanitizer build, which has no -fwrapv, aborts. RulesDef and UnitDef have no @export_range for any of it.
// A row's sums are int64 up to the clamp, with no bound on the table: max_rows is a rule int with no range, and 1,025 hits of the
// widest reach already pass 2^31 (test_separation_lockstep_cases.gd holds a table of 1,100 rows for it).
#pragma once

#include <cstdint>

#include "array_view.h"

namespace separation {

// The per-row columns of the World that the pass reads or writes (World.ROW_ARRAYS and the scratch arrays). `count` is the
// number of rows (unit_id.size()); the intent and push arrays are max_rows long, and the pass fills all of push_x and push_y.
struct Rows {
	int64_t count = 0;
	ArrayView<const int32_t> type_index, pos_x, pos_y, intent_x, intent_y;
	ArrayView<int32_t> push_x, push_y;
};

// The per-type radius table (World.type_radius).
struct Types {
	ArrayView<const int32_t> radius;
};

// World.sep_grid as the pass reads it: cells per row and rows of cells, the side of a cell in milli-tiles, `head` per cell
// (the lowest row in it, -1 for none) and `next` per row (the next higher row in the same cell, -1 at the end).
struct Grid {
	int64_t cols = 0, rows = 0, cell_milli = 0;
	ArrayView<const int32_t> head, next;
};

// The ints of the World that the pass reads: the rule values (data/rules.tres), used as the twin uses them, with the same
// guards (a divisor below 1 is 1, a push cap below 0 is 0, the idle share is clamped to 0..100).
struct Rules {
	int64_t neighbours = 0, scan = 0, idle_share = 0, push_max = 0, coincident_divisor = 0;
};

// Separation.run: writes push_x and push_y of every row (0 for a unit with no neighbour in reach, and for all rows on a grid
// with no cells or a cell side below 1), and returns the units looked at, which the caller adds to stats[SEP_PAIRS].
int64_t run(const Rows &rows, const Types &types, const Grid &grid, const Rules &rules);

} // namespace separation
