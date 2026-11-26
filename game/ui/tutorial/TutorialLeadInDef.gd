class_name TutorialLeadInDef
extends Resource
## One step of a beat's chain of targets (ADR 0048 section 5, plan row P586): a control or tile to
## tap before the beat's own anchor, and the condition that shows the player has passed it (the
## drawer is open, the tab is on). Data only (`data/tutorial/`, CLAUDE.md rule 5).
##
## The kinds a lead-in may use are the UI-state ones, `TutorialConditions.LEAD_IN_KINDS`: none
## needs a tick, so a chain works on a paused beat too. The fields read as on `TutorialBeatDef`.

@export var anchor: TutorialBeatDef.Anchor = TutorialBeatDef.Anchor.CONTROL
@export var anchor_control: StringName = &""
@export var anchor_tile: Vector2i = Vector2i.ZERO
## The unit selector (`Anchor.UNIT` only).
@export var unit: TutorialUnitPickDef = null
@export var kind: TutorialConditions.Kind = TutorialConditions.Kind.UNFOLD_OPEN
@export var value: int = 0
@export var type_id: StringName = &""
## The gesture the hint plays on this step (a tap by default).
@export var gesture: TutorialBeatDef.Gesture = TutorialBeatDef.Gesture.TAP
