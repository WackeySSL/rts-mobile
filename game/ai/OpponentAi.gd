class_name OpponentAi
extends AiController
## The opponent AI's controller (ADR 0030, plan row P175): one `AiMemory` and, in the rows after
## this one, five managers (economy, production, intel, army, strikes) that read the `PlayerView` of
## the think and write Commands to the think's list. This row is the skeleton: the slot of every
## think, the difficulty and def copied into ints, the memory, the counters, and the cap on the
## Commands of a think. A manager row adds its call to its slot's function below and nothing else.
##
## A think happens every `think_period` (3) ticks and runs one of five slots, chosen from the tick
## alone: `(tick / think_period + slot_shift) % SLOTS`. Slot ECONOMY runs the economy, PRODUCTION
## the production, REFRESH the intel refresh (the sector map and id lists), ARMY the army (which
## reads what REFRESH wrote one think, 3 ticks, earlier) and INTEL the intel run and then the
## strikes, so every manager runs once a second (15 ticks, P198b) and a think carries one fifth of
## the AI. Two lanes of residues are free of the checkpoint (`tick % 3 != 2`, as a checkpoint
## hashes in the step that starts at `tick % 15 == 14`): player `p` thinks on the residue of lane
## `(p - 1) % 2`, so players 1 and 2 never share a tick, and players 3 and 4 share one with 1 and 2
## but run slots two places on (`slot_shift`), so no two players ever run the same slot on one tick.
## Like every controller it reads the match only through the view, uses no clock, and draws only
## from `rng`.

enum Slot { ECONOMY, PRODUCTION, REFRESH, ARMY, INTEL }
const SLOTS: int = 5
## How many slots a later lane of players runs ahead of the first lane.
const LANE_SHIFT: int = 2

## The memory between thinks and the slot of the last think (-1 before the first).
var memory: AiMemory = null
## The intel manager (P177).
var intel: AiIntel = null
var last_slot: int = -1
## The slots this player runs ahead of the first lane (`LANE_SHIFT` a lane), from its player id.
var slot_shift: int = 0
## Thinks per slot, for the suites.
var slot_thinks: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
## Commands cut because a think sent more than the level allows.
var commands_cut: int = 0
## The economy manager (P176), slot ECONOMY.
var economy: AiEconomy = null
## The production manager (P178), slot PRODUCTION.
var production: AiProduction = null
## The army manager (P179), slot ARMY, one think after the intel refresh.
var army: AiArmy = null
## The superweapon manager (P181), slot INTEL after the intel run (`strikes` is the counter).
var striker: AiStrikes = null

## The level and def, copied into ints. A manager copies the values it reads itself when it is made
## (plan row of ADR 0030 section 6), so only what the controller uses is here.
var def_id: StringName = &""
var level_id: StringName = &""
var tier: int = 0
var commands_per_think_max: int = 0

## A controller for `player_id` on `def` at `level`, which it copies and does not keep. A null level
## plays as the script defaults, which are Normal's.
@warning_ignore("shadowed_variable", "integer_division")
static func create(
	def: OpponentDef, level: AiDifficultyDef, player_id: int, rng: DetRandom
) -> OpponentAi:
	var chosen: AiDifficultyDef = level if level != null else AiDifficultyDef.new()
	var ai: OpponentAi = OpponentAi.new()
	ai.player_id = player_id
	ai.rng = rng
	ai.think_period = maxi(def.think_period, 1)
	# Preconditions, pinned by a data test: the period divides 15 and `think_tick % think_period` is
	# 0 (so residue `think_period - 1`, the checkpoint's, is the one left out). A checkpoint tick
	# leaves `think_period - 1` residues free; a player takes the residue of its lane, and a player
	# past the first lane runs its slots `LANE_SHIFT` places on (P198b).
	var lanes: int = maxi(ai.think_period - 1, 1)
	ai.think_offset = posmod(-(def.think_tick + posmod(player_id - 1, lanes)), ai.think_period)
	ai.slot_shift = maxi(player_id - 1, 0) / lanes * LANE_SHIFT
	ai.memory = AiMemory.create(def)
	ai.intel = AiIntel.create(def, chosen, player_id)
	ai.def_id = def.id
	ai.level_id = chosen.id
	ai.tier = clampi(chosen.build_order_tier, 0, OpponentDef.TIERS - 1)
	ai.commands_per_think_max = maxi(chosen.commands_per_think_max, 0)
	ai.economy = AiEconomy.create(def, chosen, player_id)
	ai.production = AiProduction.create(def, chosen, player_id)
	ai.army = AiArmy.create(def, chosen, player_id)
	ai.striker = AiStrikes.create(def, chosen, player_id)
	return ai


## The slot of a think at `tick`.
@warning_ignore("integer_division")
func slot_of(tick: int) -> int:
	return (tick / maxi(think_period, 1) + slot_shift) % SLOTS


func think(view: PlayerView, out: Array[Command]) -> void:
	var before: int = out.size()
	work = 1
	last_slot = slot_of(view.tick)
	# One budget a round for the economy and the production, as before the five slots (Easy's "slow
	# hands", ADR 0030 section 6): ECONOMY resets it and PRODUCTION spends what is left. ARMY and
	# INTEL (with the strikes) have their own; REFRESH sends nothing.
	if last_slot != Slot.PRODUCTION:
		memory.commands_left = commands_per_think_max
	memory.unit_cap = view.unit_cap
	slot_thinks[last_slot] += 1
	match last_slot:
		Slot.ECONOMY:
			_run_economy_slot(view, out)
		Slot.PRODUCTION:
			_run_production_slot(view, out)
		Slot.REFRESH:
			_run_refresh_slot(view)
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


## Slot ECONOMY: `AiEconomy`.
func _run_economy_slot(view: PlayerView, out: Array[Command]) -> void:
	economy.run(view, memory, rng, out)
	work += economy.passes


## Slot PRODUCTION: `AiProduction`.
func _run_production_slot(view: PlayerView, out: Array[Command]) -> void:
	production.run(view, memory, rng, out)
	work += production.passes


## Slot REFRESH: the intel refresh, which fills the sector map and the id lists that `AiArmy` reads
## one think (3 ticks) later.
func _run_refresh_slot(view: PlayerView) -> void:
	intel.refresh(view, memory)
	work += intel.passes


## Slot ARMY: `AiArmy` on the lists of the last REFRESH.
func _run_army_slot(view: PlayerView, out: Array[Command]) -> void:
	army.run(view, memory, rng, out)
	waves = army.waves
	retreats = army.retreats


## Slot INTEL: `AiIntel` (memory, scouting), then `AiStrikes`.
func _run_intel_slot(view: PlayerView, out: Array[Command]) -> void:
	intel.run(view, memory, rng, out)
	work += intel.passes
	scouts = intel.scouts
	striker.run(view, memory, rng, out)
	work += striker.passes
	strikes = striker.strikes
