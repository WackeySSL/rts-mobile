class_name TutorialBeatDef
extends Resource
## One beat of a tutorial lesson (ADR 0044 section 2, plan row P541): a prompt, where it points,
## what the player must do before the next beat, and which `docs/HOW_TO_PLAY.md` rows it teaches.
## Data only (`data/tutorial/`, CLAUDE.md rule 5): every timing and count is a field here.

## What `anchor` points the coach mark at: nothing (a card alone), a HUD control by node name, or a
## world tile.
enum Anchor { NONE, CONTROL, TILE }

## Unique in its lesson; progress and tests name the beat by it.
@export var id: StringName = &""
## The translation key of the prompt text (English through translation keys, ADR 0044 section 3).
@export var prompt_key: StringName = &""
@export var anchor: Anchor = Anchor.NONE
## The node name of the HUD control (`Anchor.CONTROL`), looked up by `CoachMark`.
@export var anchor_control: StringName = &""
## The tile (`Anchor.TILE`).
@export var anchor_tile: Vector2i = Vector2i.ZERO
## The condition that ends the beat, and its parameters (see `TutorialConditions.Kind` for which
## each kind reads): a type id (any type when empty), a count, a tile rectangle, and one int (a zoom
## level, a drawer tab, a `HudState.Unfold`, a group slot).
@export var kind: TutorialConditions.Kind = TutorialConditions.Kind.NEXT
@export var type_id: StringName = &""
@export var count: int = 1
@export var area: Rect2i = Rect2i()
@export var value: int = 0
## HOW_TO_PLAY row ids this beat teaches (`<section>-<slug>`, ADR 0044 section 4).
@export var covers: Array[StringName] = []
## The match is paused from the beat's prompt until it is done (the pause menu's path,
## `MatchRunner.paused`). Only for a beat whose condition needs no tick (`needs_ticks`).
@export var pause: bool = false
## Ticks to wait after the beat before it (or after the lesson's start) before the prompt shows.
@export var delay_ticks: int = 0
## The prompt shows only once this step of the scripted opponent has fired (empty: no wait).
@export var after_ai_step: StringName = &""
## Seconds the beat is budgeted: a beat whose condition is still open after it is `stalled`, so the
## card may offer Next or a hint; and the lesson's budgets sum to its target (ADR 0044 section 5).
@export var budget_s: int = 10
