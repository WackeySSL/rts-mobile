// FixedMath.isqrt, a mirror of game/sim/FixedMath.gd: see fixed_math.h. MIT.
#include "fixed_math.h"

namespace fixed_math {

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

} // namespace fixed_math
