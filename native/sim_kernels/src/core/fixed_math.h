// FixedMath.isqrt for the INTEGRATE kernel and FixedMath.line_clear for the TARGETING kernel (ADR 0013 section 2, plans
// P37n and P41n): the integer square root, which the stall rule takes of the distance to the goal, and the supercover
// line test, which the engagement pass runs for the chase and for the re-test of an ATTACK unit's line. Plain C++17, no
// Godot header, no float. step_toward, the other function that the ADR names for the INTEGRATE kernel, is not here:
// Movement.integrate does not call it (the step is Movement.run's, the INTENTS phase), and a core/ function lands with
// the kernel that calls it. The INTENTS caller of line_clear (Movement._check_line, P37n2, if that port fires) would take
// this function as it is.
// Twin: game/sim/FixedMath.gd (isqrt, line_clear). Tests: tests/sim/native/test_integrate_kernel.gd (the stall cases) and the
// INTEGRATE lockstep in test_integrate_lockstep_cases.gd (same folder: the corners of the 64 x 64 map, the top of the int32
// range); for line_clear tests/sim/native/test_targeting_kernel_lines.gd, which compares it with the twin on every segment
// of small maps and on crafted ones, and the engagement suites under both implementations (tests/sim/test_engagement*.gd). MIT.
#pragma once

#include <cstdint>

#include "array_view.h"

namespace fixed_math {

// The floor of the square root of n, or 0 when n <= 0, exact over the whole int64 range.
int64_t isqrt(int64_t n);

// FixedMath.line_clear: whether every tile that the segment (x0, y0)-(x1, y1) touches is passable for `move_class`,
// over the World's `move_cost` (one list of `cols` x `rows` cells per move class) and map size. True while no map is
// loaded (cols == 0), false for a class that does not exist. Exact in int64 while the map in milli-tiles has
// max_x * max_y below 2^63, about 3 million tiles a side (a map is a few hundred). A cell outside `move_cost` reads 0
// (blocked), which no World whose `move_cost` holds three lists of cols * rows cells can reach.
bool line_clear(const ArrayView<const uint8_t> &move_cost, int64_t cols, int64_t rows, int64_t x0, int64_t y0, int64_t x1, int64_t y1, int64_t move_class);

} // namespace fixed_math
