class_name TutorialStepDef
extends Resource
## One step of a tutorial script (ADR 0044 section 2, plan row P540): a trigger over what the
## scripted opponent's `PlayerView` shows, and one action sent as Commands when it holds. A step
## fires once; `TutorialAi` copies these fields into ints when it is made and never keeps the
## Resource. Types are named by type id, so one script reads against any roster that has them.

## What a step waits for. `threshold` is the number each kind compares with.
## - TICK: the match tick is at least `threshold`.
## - ENEMY_NEAR: at least `threshold` rows of another, non-neutral owner that the player SEES (a
##   ghost or a fogged row is not seen) of `trigger_type` (any type when empty) are within
##   `trigger_radius_tiles` of the centre of one of the player's buildings.
## - ENEMY_SEEN: at least `threshold` such seen rows anywhere.
## - OWN_AT_LEAST / OWN_AT_MOST: the player owns at least / at most `threshold` rows of
##   `trigger_type` (any type when empty).
## - CREDITS: the player has at least `threshold` credits.
## - BEAT: the lesson's beat `trigger_beat` was done `threshold` ticks ago or more. The director
##   tells the script of a beat it finished through `TutorialAi.note_beat` (see there): a step
##   that waits for the player's progress, not for the clock. A beat that was never noted never
##   fires it.
## Append only: the values are stored in `data/tutorial/*.tres`.
enum Trigger { TICK, ENEMY_NEAR, ENEMY_SEEN, OWN_AT_LEAST, OWN_AT_MOST, CREDITS, BEAT }

## What a step does.
## - QUEUE: queue `count` items of `action_type` (one at a time as its queue has room, the credits
##   last and its requirement is owned); the step is done when all are queued.
## - ATTACK_MOVE / MOVE: send the player's combat units of `action_type` (all combat units when
##   empty), the `count` lowest ids (all when 0), to the target.
## - STOP: halt those units where they stand.
enum Action { QUEUE, ATTACK_MOVE, MOVE, STOP }

## Where an order goes. TILE: `target_tile`. HOME: the centre of the Headquarters (the first
## building without one) moved by `target_tile` tiles. TRIGGER: the first row (lowest) that made an
## ENEMY_NEAR or ENEMY_SEEN trigger hold, else HOME.
enum Target { TILE, HOME, TRIGGER }

## The step's name, unique in its script: other steps and the director name it.
@export var id: StringName = &""
## A step that is not yet fired and names `after_step` waits until that step has fired, then
## `delay_ticks` more ticks. With no `after_step` the delay counts from tick 0.
@export var after_step: StringName = &""
@export var delay_ticks: int = 0
@export var trigger: Trigger = Trigger.TICK
@export var trigger_type: StringName = &""
@export var threshold: int = 0
@export var trigger_radius_tiles: int = 0
## `Trigger.BEAT`: the id of the beat (of the lesson that plays this script) the step waits for.
@export var trigger_beat: StringName = &""
@export var action: Action = Action.ATTACK_MOVE
@export var action_type: StringName = &""
@export var count: int = 0
@export var target: Target = Target.HOME
@export var target_tile: Vector2i = Vector2i.ZERO
