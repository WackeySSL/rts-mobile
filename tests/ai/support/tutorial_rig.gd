extends RefCounted
## Fixture of the `TutorialAi` suites (plan row P540). Not a test suite. A tiny script of three
## steps on `ai_rig.gd`'s mirrored start, played by player 2 (its base at (26, 26), 28 tiles from
## player 1's): `train` queues two rifle squads once it can, `wave` sends every combat unit to the
## first seen enemy row within 8 tiles of a building, `fall_back` moves them home 30 ticks later.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")
const PLAYER: int = 2
const FOE: int = 1


## One step with the fields a test names; the rest are the defaults of `TutorialStepDef`.
static func step(
	id: String, trigger: TutorialStepDef.Trigger, action: TutorialStepDef.Action, fields: Dictionary
) -> TutorialStepDef:
	var made: TutorialStepDef = TutorialStepDef.new()
	made.id = StringName(id)
	made.trigger = trigger
	made.action = action
	for key: String in fields:
		made.set(key, fields[key])
	return made


## The three-step script of the header.
static func script_def() -> TutorialScriptDef:
	var def: TutorialScriptDef = TutorialScriptDef.new()
	def.id = &"tutorial_test"
	def.steps.append(
		step(
			"train",
			TutorialStepDef.Trigger.TICK,
			TutorialStepDef.Action.QUEUE,
			{"threshold": 0, "action_type": &"rifle_squad", "count": 2}
		)
	)
	def.steps.append(
		step(
			"wave",
			TutorialStepDef.Trigger.ENEMY_NEAR,
			TutorialStepDef.Action.ATTACK_MOVE,
			{"threshold": 1, "trigger_radius_tiles": 8, "target": TutorialStepDef.Target.TRIGGER}
		)
	)
	def.steps.append(
		step(
			"fall_back",
			TutorialStepDef.Trigger.TICK,
			TutorialStepDef.Action.MOVE,
			{"after_step": &"wave", "delay_ticks": 30, "target": TutorialStepDef.Target.HOME}
		)
	)
	return def


## The scripted player of `def` with its own stream of `seed`.
static func ai_of(def: TutorialScriptDef, seed: int = 1) -> TutorialAi:
	return TutorialAi.create(def, PLAYER, DetRandom.create(seed, DetRandom.STREAM_AI_BASE + PLAYER))


## A start with the script's barracks given to the scripted player and the fog settled.
static func start() -> World:
	var world: World = Rig.start()
	Rig.give(world, PLAYER, "barracks", 31, 26)
	return world


## One think of `ai` on a fresh view of its player; returns the Commands it sent.
static func think(world: World, ai: TutorialAi) -> Array[Command]:
	var sent: Array[Command] = []
	ai.think(PlayerView.of(world, PLAYER), sent)
	return sent
