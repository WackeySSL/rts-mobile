extends GdUnitTestSuite
## The DetRng autoload (ADR 0007 section 6): a stateless factory whose streams are exactly
## DetRandom's for the same (match seed, stream id).


func test_create_gives_the_det_random_stream_of_the_same_seed_and_stream() -> void:
	assert_array(DetRng.create(7, 1).state()).is_equal(DetRandom.create(7, 1).state())
	# The seed and the stream each reach the generator, in that order, and the draws follow.
	var pairs: Array[Vector2i] = [
		Vector2i(42, DetRandom.STREAM_SIM),
		Vector2i(42, DetRandom.STREAM_AI_BASE + 2),
		Vector2i(1, 7),
		Vector2i(0, 0),
		Vector2i(0x7FFFFFFF, 0xFFFF),
	]
	for pair: Vector2i in pairs:
		var made: DetRandom = DetRng.create(pair.x, pair.y)
		var reference: DetRandom = DetRandom.create(pair.x, pair.y)
		assert_array(made.state()).override_failure_message(str(pair)).is_equal(reference.state())
		assert_array([made.next_u32(), made.next_u32()]).is_equal(
			[reference.next_u32(), reference.next_u32()]
		)
	assert_array(DetRng.create(42, 1).state()).is_not_equal(DetRng.create(42, 2).state())


## Stateless: every call makes a new generator, so draws from one stream never move another.
func test_every_call_returns_a_new_generator() -> void:
	var first: DetRandom = DetRng.create(7, 1)
	var second: DetRandom = DetRng.create(7, 1)
	assert_bool(is_same(first, second)).is_false()
	first.next_u32()
	assert_array(second.state()).is_equal(DetRandom.create(7, 1).state())
	assert_array(DetRng.create(7, 1).state()).is_equal(DetRandom.create(7, 1).state())
