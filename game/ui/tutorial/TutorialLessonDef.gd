class_name TutorialLessonDef
extends Resource
## A tutorial lesson (ADR 0044 section 1): its beats in order and its time target. One file per
## lesson in `data/tutorial/`.

## Row ids: a section prefix, then kebab-case words (`camera-pinch`).
const ID_PATTERN: String = "^[a-z0-9]+(-[a-z0-9]+)+$"

@export var id: StringName = &""
@export var title_key: StringName = &""
## The one-line goal the pause menu shows in place of the skirmish's objective (a key of
## `data/tutorial/text_en.tres`).
@export var objective_key: StringName = &""
@export var beats: Array[TutorialBeatDef] = []
## The match of the lesson (ADR 0044 section 1): its scenario on a `data/maps/tutorial_*.tres`, the
## scripted opponent that plays player 2 (`TutorialAi` through `AiFactory`), and the seed of the
## match. A lesson is a match of its own, replayable from the seed.
@export var scenario: ScenarioDef
@export var enemy: TutorialScriptDef
@export var match_seed: int = 1
## The seconds the lesson aims for; the beats' budgets must fit in it (Basics 180).
@export var target_s: int = 180


## The sum of the beats' budgets, seconds.
func budget_s() -> int:
	var total: int = 0
	for beat: TutorialBeatDef in beats:
		total += maxi(beat.budget_s, 0)
	return total


## Every HOW_TO_PLAY id any beat covers, in beat order, without repeats.
func covered_ids() -> Array[StringName]:
	var found: Array[StringName] = []
	for beat: TutorialBeatDef in beats:
		for row: StringName in beat.covers:
			if not found.has(row):
				found.append(row)
	return found


## What is wrong with the lesson, one line each (empty when nothing): no beats, a repeated or empty
## beat id, a malformed `covers` id, a pause on a beat that is not a Next beat, an empty prompt key,
## a control anchor without a name, budgets over the target.
func problems() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var pattern: RegEx = RegEx.create_from_string(ID_PATTERN)
	var seen: Array[StringName] = []
	if beats.is_empty():
		found.append("%s: no beats" % id)
	for beat: TutorialBeatDef in beats:
		if beat.id == &"" or seen.has(beat.id):
			found.append("%s: beat id '%s' is empty or repeated" % [id, beat.id])
		seen.append(beat.id)
		if beat.prompt_key == &"":
			found.append("%s: no prompt key" % beat.id)
		if beat.anchor == TutorialBeatDef.Anchor.CONTROL and beat.anchor_control == &"":
			found.append("%s: a control anchor names no control" % beat.id)
		if beat.pause and beat.kind != TutorialConditions.Kind.NEXT:
			found.append("%s: pauses on a condition that is not Next" % beat.id)
		for row: StringName in beat.covers:
			if pattern.search(String(row)) == null:
				found.append("%s: covers id '%s' is not <section>-<slug>" % [beat.id, row])
	if budget_s() > target_s:
		found.append("%s: budgets %d s exceed the target %d s" % [id, budget_s(), target_s])
	return found
