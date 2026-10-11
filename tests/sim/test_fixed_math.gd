extends GdUnitTestSuite
## FixedMath.isqrt (ADR 0003 section 2): the exact floor square root, 0 for n <= 0.


func test_isqrt_known_values() -> void:
	var expected: Dictionary[int, int] = {
		0: 0,
		1: 1,
		2: 1,
		3: 1,
		4: 2,
		9: 3,
		15: 3,
		16: 4,
		14400: 120,
		99999999: 9999,
		2304000000: 48000,
		4611686018427387904: 2147483648,
		9223372036854775807: 3037000499,
	}
	for n: int in expected:
		assert_int(FixedMath.isqrt(n)).is_equal(expected[n])


func test_isqrt_negative_numbers_give_zero() -> void:
	for n: int in [-1, -2, -4, -100, -9223372036854775807 - 1]:
		assert_int(FixedMath.isqrt(n)).is_equal(0)


## r is the floor root exactly when r*r <= n < (r+1)*(r+1).
func test_isqrt_is_the_exact_floor_for_0_to_100000() -> void:
	var wrong: Array[int] = []
	for n: int in range(0, 100001):
		var r: int = FixedMath.isqrt(n)
		if r * r > n or (r + 1) * (r + 1) <= n:
			wrong.append(n)
	assert_array(wrong).is_empty()


## Around every perfect square up to 10^12: k*k-1 gives k-1, k*k and k*k+1 give k.
func test_isqrt_around_perfect_squares_up_to_a_million() -> void:
	var wrong: Array[int] = []
	for k: int in range(1, 1000001):
		if (
			FixedMath.isqrt(k * k - 1) != k - 1
			or FixedMath.isqrt(k * k) != k
			or FixedMath.isqrt(k * k + 1) != k
		):
			wrong.append(k)
	assert_array(wrong).is_empty()
