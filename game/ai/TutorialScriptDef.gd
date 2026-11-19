class_name TutorialScriptDef
extends AiDef
## The data of the scripted tutorial opponent (ADR 0044 section 2, plan row P540): an `AiDef` (so
## `AiFactory` and every seat take it as any def; the dummy's build order and defence fields are
## unused, `hq_type`, `think_period` and `think_tick` are read) with the ordered `steps` that
## `TutorialAi` plays. Every timing, count and trigger of a lesson's enemy is a field here
## (`data/tutorial/`, CLAUDE.md rule 5).

## The steps, tried in this order on every think; each fires once.
@export var steps: Array[TutorialStepDef] = []
