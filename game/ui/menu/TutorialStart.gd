class_name TutorialStart
extends RefCounted
## What the tutorial screen, the main menu's first launch and the match host share (plan row P544,
## ADR 0044 sections 1 and 2): the lessons in teaching order, a lesson's `MatchSetup` built from its
## lesson file alone, and the "Basics offered" flag in section `tutorial` of the save (next to the
## director's `done`). A lesson is a match of its own (never written to the resume file, ADR 0042
## section 6), so leaving one and coming back starts it again from the top.

## The order the screen lists them and the first launch starts the first.
const ORDER: Array[StringName] = [&"basics", &"strikes", &"air", &"support"]
const LESSON_PATH: String = "res://data/tutorial/%s.tres"
const KEY_OFFERED: String = "offered"
## The route a lesson's end, and Leave tutorial, return to (`MenuFlow.take_pending_screen`).
const RETURN_SCREEN: StringName = MenuRoutes.TUTORIAL


## The lesson `id` from its file, or null when there is none.
static func lesson(id: StringName) -> TutorialLessonDef:
	var path: String = LESSON_PATH % id
	return load(path) as TutorialLessonDef if ResourceLoader.exists(path) else null


## The setup of `def`: its scenario, seed and scripted enemy at seat 2, no level and no map id.
## Null when the lesson names no scenario or no enemy.
static func setup_for(def: TutorialLessonDef) -> MatchSetup:
	if def == null or def.scenario == null or def.enemy == null:
		return null
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = def.scenario.resource_path
	setup.match_seed = def.match_seed
	setup.opponents.append(def.enemy)
	setup.lesson_id = def.id
	return setup


## Starts lesson `id` through `flow` (MenuFlow). Always `await` it.
static func start(flow: Node, id: StringName) -> Error:
	var setup: MatchSetup = setup_for(lesson(id))
	if setup == null:
		push_warning("TutorialStart: lesson %s has no scenario or enemy" % id)
		return ERR_FILE_NOT_FOUND
	return await flow.call(&"start_match", setup) as Error


## The first lesson that is not done, or &"" when all are.
static func next_lesson() -> StringName:
	for id: StringName in ORDER:
		if not TutorialDirector.is_done(id):
			return id
	return &""


## True on a first launch: Basics was never offered and nothing was finished.
static func first_launch_due() -> bool:
	var offered: Variant = SaveService.get_section(TutorialDirector.SECTION).get(KEY_OFFERED, false)
	return offered != true and TutorialDirector.lessons_done().is_empty()


## Records that Basics was offered (once; the section's other keys stay). False when the save
## refused it.
static func mark_offered() -> bool:
	var values: Dictionary = SaveService.get_section(TutorialDirector.SECTION)
	values[KEY_OFFERED] = true
	return SaveService.set_section(TutorialDirector.SECTION, values)
