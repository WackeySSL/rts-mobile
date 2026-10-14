# DetRng autoload (ADR 0002 section 1, API in ADR 0007 section 6). Node-side stateless factory: the
# match runner creates the sim stream with it, and AI controllers will create theirs (one per
# player). It holds no generator state and is never referenced from game/sim.
extends Node


## A new generator for (match seed, stream id), the same as DetRandom.create(match_seed, stream_id).
## Each call returns its own object, so draws from one never move another.
func create(match_seed: int, stream_id: int) -> DetRandom:
	return DetRandom.create(match_seed, stream_id)
