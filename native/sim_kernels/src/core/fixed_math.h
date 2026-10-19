// FixedMath.isqrt for the INTEGRATE kernel (ADR 0013 section 2, plan P37n): the integer square root, which the stall
// rule takes of the distance to the goal. Plain C++17, no Godot header, no float. step_toward, the other function
// that the ADR names for this kernel, is not here: Movement.integrate does not call it (the step is Movement.run's,
// the INTENTS phase), and a core/ function lands with the kernel that calls it.
// Twin: game/sim/FixedMath.gd (isqrt). Tests: tests/sim/native/test_integrate_kernel.gd (the stall cases) and the INTEGRATE
// lockstep in test_integrate_lockstep_cases.gd (same folder: the corners of the 64 x 64 map, the top of the int32 range). MIT.
#pragma once

#include <cstdint>

namespace fixed_math {

// The floor of the square root of n, or 0 when n <= 0, exact over the whole int64 range.
int64_t isqrt(int64_t n);

} // namespace fixed_math
