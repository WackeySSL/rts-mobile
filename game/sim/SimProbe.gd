class_name SimProbe
extends RefCounted
## Where a tick's time goes (ADR 0007 section 4). Sim.step calls begin() first and mark(phase)
## after each phase it ran; this base class does nothing, and a subclass outside game/sim reads
## the clock. A probe never sees the World. The ids are fixed and never renumbered; a phase that
## does not exist yet is not marked and keeps its id; marks come in ascending id order, each phase
## at most once per tick. COMMANDS covers prepare, the clear and the commands; FLOW to FOG are the
## next ten steps in order; ECONOMY, PRODUCTION and MEMORY (ADR 0017 section 5) follow FOG; the tick
## counter is not timed.

enum Phase {
	COMMANDS = 0,
	FLOW = 1,
	GRIDS = 2,
	TARGETING = 3,
	INTENTS = 4,
	SEPARATION = 5,
	INTEGRATE = 6,
	PROJECTILES = 7,
	FIRE = 8,
	REMOVE = 9,
	FOG = 10,
	ECONOMY = 11,
	PRODUCTION = 12,
	MEMORY = 13,
	COUNT = 14
}

## One name per phase, in id order.
const PHASE_NAMES: Array[String] = [
	"commands",
	"flow",
	"grids",
	"targeting",
	"intents",
	"separation",
	"integrate",
	"projectiles",
	"fire",
	"remove",
	"fog",
	"economy",
	"production",
	"memory"
]


## The start of a tick.
func begin() -> void:
	pass


## The end of `phase`, a Phase id.
func mark(_phase: int) -> void:
	pass
