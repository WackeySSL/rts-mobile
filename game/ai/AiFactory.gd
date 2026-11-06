class_name AiFactory
extends RefCounted
## Builds the controller for a def (ADR 0030 section 6, plan row P175): an `OpponentDef` gives an
## `OpponentAi` at the given level, a plain `AiDef` gives the dummy (the level is ignored and may be
## null). Whoever seats a computer player (MatchRunner, the harnesses) calls this and nothing else.


## The controller of `player_id` on `def`, its stream `rng` (the match's, for this player).
static func create(
	def: AiDef, level: AiDifficultyDef, player_id: int, rng: DetRandom
) -> AiController:
	var opponent: OpponentDef = def as OpponentDef
	if opponent != null:
		return OpponentAi.create(opponent, level, player_id, rng)
	return DummyAi.create(def, player_id, rng)
