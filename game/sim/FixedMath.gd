class_name FixedMath
extends RefCounted
## Integer math for the simulation (ADR 0003 section 2). Phase 2 adds the sine table and dir_to.


## The floor of the square root of n, or 0 when n <= 0. Digit by digit, so it is exact over
## the whole 64-bit range and needs no float, no division and no overflow-prone sum.
static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var rest: int = n
	var root: int = 0
	var bit: int = 1 << 62
	while bit > rest:
		bit >>= 2
	while bit != 0:
		if rest >= root + bit:
			rest -= root + bit
			root = (root >> 1) + bit
		else:
			root >>= 1
		bit >>= 2
	return root
