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
## The intel manager (P177).
var intel: AiIntel = null
var last_slot: int = -1
## Thinks per slot, for the suites.
var slot_thinks: PackedInt32Array = PackedInt32Array([0, 0, 0])
## Commands cut because a think sent more than the level allows.
var commands_cut: int = 0
## The economy manager (P176), slot ECONOMY.
var economy: AiEconomy = null

## The level and def, copied into ints. A manager copies the values it reads itself when it is made
## (plan row of ADR 0030 section 6), so only what the controller uses is here.
var def_id: StringName = &""
var level_id: StringName = &""
var tier: int = 0
var commands_per_think_max: int = 0

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
	ai.intel = AiIntel.create(def, chosen, player_id)
	ai.def_id = def.id
	ai.level_id = chosen.id
	ai.tier = clampi(chosen.build_order_tier, 0, OpponentDef.TIERS - 1)
	ai.commands_per_think_max = maxi(chosen.commands_per_think_max, 0)
	ai.economy = AiEconomy.create(def, chosen, player_id)
	return ai


## The slot of a think at `tick`.
@warning_ignore("integer_division")
func slot_of(tick: int) -> int:
	return ((tick + think_offset) / think_period) % SLOTS


func think(view: PlayerView, out: Array[Command]) -> void:
	var before: int = out.size()
	work = 1
	memory.commands_left = commands_per_think_max
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
	# A guard, not the budget: managers check `memory.can_send` before they append, so the cut
	# stays 0 (the manager suites assert `commands_cut == 0`).
	var sent: int = out.size() - before
	if sent > commands_per_think_max:
		out.resize(before + commands_per_think_max)
		commands_cut += sent - commands_per_think_max
		sent = commands_per_think_max
	commands += sent
	work_max = maxi(work_max, work)


## Slot 0: P176 adds `AiEconomy`, P178 `AiProduction`.
func _run_economy_slot(view: PlayerView, out: Array[Command]) -> void:
	economy.run(view, memory, rng, out)
	work += economy.passes


## Slot 1: P177 adds the intel refresh, P179 `AiArmy`.
func _run_army_slot(view: PlayerView, _out: Array[Command]) -> void:
	intel.refresh(view, memory)
	work += intel.passes


## Slot 2: P177 adds `AiIntel`, P181 `AiStrikes`.
func _run_intel_slot(view: PlayerView, out: Array[Command]) -> void:
	intel.run(view, memory, rng, out)
	work += intel.passes
	scouts = intel.scouts
