class_name TutorialChain
extends RefCounted
## Which step of a beat's chain of targets the player is on (ADR 0048 section 5, plan row P586).
## The steps are the beat's lead-ins in order, then the beat's own anchor as the final step. Pure
## and stateless: it is re-evaluated every frame and never latched, so the highlight follows the
## player both ways (placement closes the drawer yet the step before the check mark still holds;
## closing the drawer by hand sends the ring back to BUILD).


## The index of the active step: `lead_in.size()` is the beat's own anchor. The furthest lead-in
## whose condition holds now wins, and the step after it is active; with none holding, step 0.
static func active(beat: TutorialBeatDef, ctx: TutorialContext) -> int:
	for index: int in range(beat.lead_in.size() - 1, -1, -1):
		var step: TutorialLeadInDef = beat.lead_in[index]
		if TutorialConditions.check_kind(
			step.kind, step.type_id, 1, Rect2i(), step.value, ctx, ctx
		):
			return index + 1
	return 0


## The beat's own anchor as a step, built once when the beat shows (nothing is allocated per frame).
static func final_step(beat: TutorialBeatDef) -> TutorialLeadInDef:
	var step: TutorialLeadInDef = TutorialLeadInDef.new()
	step.anchor = beat.anchor
	step.anchor_control = beat.anchor_control
	step.anchor_tile = beat.anchor_tile
	step.unit = beat.unit
	step.kind = beat.kind
	step.value = beat.value
	step.type_id = beat.type_id
	step.gesture = beat.gesture
	return step
