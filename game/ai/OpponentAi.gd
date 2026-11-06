class_name OpponentAi
extends AiController
## The opponent AI's controller (ADR 0030, plan row P175): one `AiMemory` and, in the rows after
## this one, five managers (economy, production, intel, army, strikes) that read the `PlayerView` of
## the think and write Commands to the think's list. This row is the skeleton: the slot of every
## think, the difficulty and def copied into ints, the memory, the counters, and the cap on the
## Commands of a think. A manager row adds its call to its slot's function below and nothing else.
##
## A think happens every `think_period` (5) ticks and runs one of three slots, chosen from the tick
## alone: `((tick + think_offset) / think_period) % SLOTS`. Slot ECONOMY runs economy then
## production, slot ARMY the intel refresh then the army, slot INTEL intel then strikes, so every
## manager runs once a second and a think carries a third of the AI. The offset puts player `p` on
## `tick % 5 == (p + 4) % 5`, never on 4: a checkpoint hashes in the step that starts at
## `tick % 15 == 14` and no think falls there (players 1 to 4). Like every controller it reads the
## match only through the view, uses no clock, and draws only from `rng`.

enum Slot { ECONOMY, ARMY, INTEL }
const SLOTS: int = 3

## The memory between thinks and the slot of the last think (-1 before the first).
var memory: AiMemory = null
var last_slot: int = -1
## Thinks per slot, for the suites.
var slot_thinks: PackedInt32Array = PackedInt32Array([0, 0, 0])
## Commands cut because a think sent more than the level allows.
var commands_cut: int = 0

## The level and def, copied into ints.
var def_id: StringName = &""
var level_id: StringName = &""
var tier: int = 0
var reaction_ticks: int = 0
var commands_per_think_max: int = 0
var uses_strike: int = 0
var defend_radius_tiles: int = 0
var staging_offset_tiles: int = 0
var place_tries_per_think: int = 0
var target_tests_max: int = 0

## A controller for `player_id` on `def` at `level`, which it copies and does not keep. A null level
## plays as the script defaults, which are Normal's.
@warning_ignore("shadowed_variable")
static func create(
	def: OpponentDef, level: AiDifficultyDef, player_id: int, rng: DetRandom
) -> OpponentAi:
	var chosen: AiDifficultyDef = level if level != null else AiDifficultyDef.new()
	var ai: OpponentAi = OpponentAi.new()
	ai.player_id = player_id
	ai.rng = rng
	ai.think_period = maxi(def.think_period, 1)
	ai.think_offset = posmod(-(def.think_tick + player_id - 2), ai.think_period)
	ai.memory = AiMemory.create(def)
	ai.def_id = def.id
	ai.level_id = chosen.id
	ai.tier = clampi(chosen.build_order_tier, 0, OpponentDef.TIERS - 1)
	ai.reaction_ticks = chosen.reaction_ticks
	ai.commands_per_think_max = chosen.commands_per_think_max
	ai.uses_strike = chosen.uses_strike
	ai.defend_radius_tiles = def.defend_radius_tiles
	ai.staging_offset_tiles = def.staging_offset_tiles
	ai.place_tries_per_think = def.place_tries_per_think
	ai.target_tests_max = def.target_tests_max
	return ai


## The slot of a think at `tick`.
@warning_ignore("integer_division")
func slot_of(tick: int) -> int:
	return ((tick + think_offset) / think_period) % SLOTS


func think(view: PlayerView, out: Array[Command]) -> void:
	var before: int = out.size()
	work = 1
	memory.unit_cap = view.unit_cap
	last_slot = slot_of(view.tick)
	slot_thinks[last_slot] += 1
	match last_slot:
		Slot.ECONOMY:
			_run_economy_slot(view, out)
		Slot.ARMY:
			_run_army_slot(view, out)
		_:
			_run_intel_slot(view, out)
	var sent: int = out.size() - before
	if sent > commands_per_think_max:
		out.resize(before + commands_per_think_max)
		commands_cut += sent - commands_per_think_max
		sent = commands_per_think_max
	commands += sent
	work_max = maxi(work_max, work)


## Slot 0: P176 adds `AiEconomy`, P178 `AiProduction`.
func _run_economy_slot(_view: PlayerView, _out: Array[Command]) -> void:
	pass


## Slot 1: P177 adds the intel refresh, P180 `AiArmy`.
func _run_army_slot(_view: PlayerView, _out: Array[Command]) -> void:
	pass


## Slot 2: P177 adds `AiIntel`, P181 `AiStrikes`.
func _run_intel_slot(_view: PlayerView, _out: Array[Command]) -> void:
	pass
