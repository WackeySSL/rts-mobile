extends RefCounted
## Fixture of the tutorial director suites (plan row P541). Not a test suite. A world on
## `ai_rig.gd`'s
## mirrored start (player 1's Headquarters at (6, 6), two rifle squads at (4, 10); player 2 far to
## the south-east) and small lessons of fixture beats, with fixture HOW_TO_PLAY ids.

const Rig: GDScript = preload("res://tests/ai/support/ai_rig.gd")


## A beat of `kind` with the fields a test names (the rest are `TutorialBeatDef`'s defaults).
static func beat(
	id: String, kind: TutorialConditions.Kind, fields: Dictionary = {}
) -> TutorialBeatDef:
	var made: TutorialBeatDef = TutorialBeatDef.new()
	made.id = StringName(id)
	made.prompt_key = StringName("tutorial.test." + id)
	made.kind = kind
	for key: String in fields:
		if fields[key] is Array:
			(made.get(key) as Array).assign(fields[key])  # A typed array takes no plain one.
		else:
			made.set(key, fields[key])
	return made


## A lesson of `beats` (a plain Array: a literal of a preloaded script is not typed).
static func lesson(id: String, beats: Array, target_s: int = 180) -> TutorialLessonDef:
	var made: TutorialLessonDef = TutorialLessonDef.new()
	made.id = StringName(id)
	made.target_s = target_s
	for one: TutorialBeatDef in beats:
		made.beats.append(one)
	return made


## The snapshot of `world` as it stands.
static func snapshot(world: World, serial: int = 1) -> MatchSnapshot:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.match_serial = serial
	snap.capture(world, null)
	return snap


## A context over the snapshot of `world` with a fresh selection and unfold state.
static func context(world: World) -> TutorialContext:
	var ctx: TutorialContext = TutorialContext.new()
	ctx.snapshot = snapshot(world)
	ctx.selection = SelectionModel.new()
	ctx.hud = HudState.new()
	return ctx


## The id of the first row of player `player` with the type `id`.
static func row_id(world: World, player: int, id: String) -> int:
	var type: int = Rig.type_of(world, id)
	for row: int in world.unit_count():
		if world.owner[row] == player and world.type_index[row] == type:
			return world.unit_id[row]
	return -1
