// The rules of the TARGETING kernel (ADR 0013 sections 1 and 2, plan P41n): Targeting.run and Targeting._engage over views
// of the arrays the kernel borrowed, two passes over the rows in ascending id order. Acquisition: an ATTACK row locks its
// target (or falls back to ATTACK_MOVE when that unit is gone), a MOVE row drops its target, and a due ATTACK_MOVE or IDLE
// row keeps its target or scans the cells of the targeting grid around it for the best enemy (the highest damage percent,
// then the smaller squared distance, then the lower row). Engagement: a unit with a target in weapon range holds, an
// attack-moving unit chases a target inside its acquire range while the line to it is clear, an ATTACK unit re-tests its
// line on its line-check turn, and a unit whose target is gone resumes the path of its order. Every mode change goes through
// reset_row (Movement.reset_row): it writes the six navigation columns and nothing else. Plain C++17, no Godot header, no
// float. Rule values come in through `Rules`, `Types`, `Weapons` and the grid, read from the World by the bind layer.
// The grid is the one the GDScript rebuild wrote this tick (SpatialGrid, `head` per cell and `next` per row): the pass never
// rebuilds it.
// Twin: game/sim/Targeting.gd (run, _engage) and game/sim/Movement.gd (reset_row), in the twin's row order, so that the full
// state matches after every call. Tests: tests/sim/test_targeting*.gd and test_engagement*.gd under both implementations,
// tests/sim/native/test_targeting_kernel.gd (the names, the in-place writes, the guards and the range), the crafted cases
// in test_targeting_kernel_cases.gd (exact-distance ties, every state of the engagement pass, unarmed types, seeded random
// states) and test_targeting_kernel_lines.gd (line_clear); the 900-tick lockstep is P41n2, later. MIT.
//
// Range. The pass is exact in int64 while the positions stay within 10^9 milli-tiles of the origin in both axes (a million
// tiles; a map is a few hundred), so that d2 = dx*dx + dy*dy of any two units stays below 2^63 (at most 8 * 10^18), and while
// a reach, an acquire range or a minimum range is below 2^31 (an int32 element, whose square is below 2^62), and while
// `tick + id` stays below 2^63 (the tick is a match counter, a few million at the most). Past it the
// production build wraps like the twin (-fwrapv), so the two still agree, on a meaningless answer; the sanitizer build, which
// has no -fwrapv, aborts. `weapon * 4 + armour` indexes the percents, four armour classes a weapon; an index outside the
// table reads 0 (no damage), where the twin would stop with a script error.
#pragma once

#include <cstdint>

#include "array_view.h"

namespace targeting {

// The per-row columns of the World that the pass reads or writes (World.ROW_ARRAYS). A row is an index in ascending id
// order, and every column has one entry per row.
struct Rows {
	ArrayView<const int32_t> unit_id, owner, type_index, pos_x, pos_y;
	ArrayView<int32_t> goal_x, goal_y, order, order_target, target, nav_mode, nav_cell, field, nav_next, best_dist, stall;
};

// The per-type tables (World.type_*): the armour class, the acquire range, the weapon index (negative for none) and the
// movement class.
struct Types {
	ArrayView<const int32_t> armour, acquire, weapon, move_class;
};

// The weapon tables (World.weapon_*): the range and minimum range per weapon, and four percents per weapon, one for each
// armour class.
struct Weapons {
	ArrayView<const int32_t> range, min_range, vs_armour;
};

// World.target_grid as the pass reads it: cells per row and rows of cells, the side of a cell in milli-tiles, `head` per cell
// (the lowest row in it, -1 for none) and `next` per row (the next higher row in the same cell, -1 at the end). A grid with
// no cells, or a cell side below 1, is an empty map: the pass finds nobody.
struct Grid {
	int64_t cols = 0, rows = 0, cell_milli = 0;
	ArrayView<const int32_t> head, next;
};

// The map FixedMath.line_clear reads: the World's size in tiles and its `move_cost`.
struct Map {
	int64_t cols = 0, rows = 0;
	ArrayView<const uint8_t> move_cost;
};

// The ints of the World that the pass reads: the tick and the two cadences (data/rules.tres), used as the twin uses them
// (a period below 1 is 1).
struct Rules {
	int64_t tick = 0, retarget_period_ticks = 0, line_check_period_ticks = 0;
};

// What the caller adds to `stats`.
struct Counts {
	int64_t candidates = 0; // stats[TARGET_CANDIDATES]: the rows the scans looked at
	int64_t line_checks = 0; // stats[LINE_CHECKS]: the line_clear calls of the engagement pass
};

// Targeting.run: acquisition, then engagement.
Counts run(const Rows &rows, const Types &types, const Weapons &weapons, const Grid &grid, const Map &map, const Rules &rules);

} // namespace targeting
