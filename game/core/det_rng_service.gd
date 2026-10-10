# DetRng autoload (ADR 0002 section 1). Node-side stateless factory: the match setup will use it
# to create one DetRandom generator per stream from (match seed, stream id). It holds no
# generator state and is never referenced from game/sim. API defined in Phase 2.
extends Node
