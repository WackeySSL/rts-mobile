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


## True on a first launch: a save with no play history (no XP or award, no completed match, no
## resume file) where Basics was neither finished nor explicitly left (`note_left`). A player who
## updated the app keeps their Continue file and rank: they are never a first launch. A Basics
## that was refused, or cut short by a kill, is offered again (ADR 0044 section 1: a lesson
## restarts).
static func first_launch_due() -> bool:
	var offered: Variant = SaveService.get_section(TutorialDirector.SECTION).get(KEY_OFFERED, false)
	if offered == true or TutorialDirector.is_done(ORDER[0]):
		return false
	return not has_play_history()


## Whether the save shows the player has played: rank XP or an award, a completed match, a resume
## file.
static func has_play_history() -> bool:
	var progress: Dictionary = SaveService.get_section(&"progress")
	var awards: Variant = progress.get("awards", [])
	var ads: Dictionary = SaveService.get_section(&"ads")
	return (
		int(progress.get("xp", 0)) > 0
		or (awards is Array and not (awards as Array).is_empty())
		or int(ads.get("completed_matches", 0)) > 0
		or ResumeStore.has_file()
	)


## Records that Basics was dealt with (finished is saved by the director; this is the explicit
## skip). False when the save refused it.
static func mark_offered() -> bool:
	var values: Dictionary = SaveService.get_section(TutorialDirector.SECTION)
	values[KEY_OFFERED] = true
	return SaveService.set_section(TutorialDirector.SECTION, values)


## The player left lesson `id` on purpose (Skip lesson, Leave tutorial): leaving Basics ends the
## first-launch offer. A kill or a refused start never calls this.
static func note_left(id: StringName) -> void:
	if id == ORDER[0]:
		mark_offered()
