extends "res://tests/ai/support/strike_suite.gd"
## The base of the Dusk Array suites (plan rows P181, P576, P576b): the Lumen Accord is player 1,
## the Derrick League player 2, and the constants and hand-built Worlds the cases share. Not a
## suite.

## The factory's centre, the cluster's point: no other producer is within the radius of 4,000.
const CLUSTER_POINT: Vector2i = Vector2i(31500, 31500)
## The far barracks the wave's goal may point at.
## The second factory of the equal pair.
const TWIN_POINT: Vector2i = Vector2i(11500, 32500)
## The tile of the radar beside the twin.
const RADAR_TILE: Vector2i = Vector2i(11, 29)
const FAR_POINT: Vector2i = Vector2i(7000, 29000)
## The wave numbers of the integration case: the first tick and strength (a Lumen Accord tank and
## the two starting rifle squads: 1000 + 100 + 100); the first ARMY slot is tick 5, 15 ticks apart.
const WAVE_TICK: int = 100
const WAVE_STRENGTH: int = 1200
const LAUNCH: int = 110
## The army's own numbers for that case: staging offset and defence radius (tiles), and the keys.
const OFFSET: int = 6
const DEFENCE: int = 12
const KEYS: int = 4


func _side() -> String:
	return "renew"


## A lone enemy factory (1,800) and, far off, two barracks with a refinery beside them.
func _producers() -> void:
	_enemy_building("vehicle_factory", 30, 30)
	_enemy_building("barracks", 6, 28)
	_enemy_building("barracks", 8, 28)
	_enemy_building("refinery", 6, 31)
	_see_all()


## The wave table by hand: `count` waves launched, the wave squad in `state`.
func _wave(count: int, state: int) -> void:
	_memory.wave_count = count
	_memory.squad_state[AiArmy.WAVE] = state
	_memory.squad_role[AiArmy.WAVE] = AiArmy.ROLE_WAVE
	_memory.member_id = PackedInt32Array([AiRig.ids_of(_world, 1, "renew_rifle")[0]])
	_memory.member_squad = PackedInt32Array([AiArmy.WAVE])


## Two lone factories of equal value, the wave in the field, the factories sighted and fired on
## once (the shot stays in `_out` only, so a later run may fire again).
func _twins() -> void:
	_flag_radars()
	_enemy_building("vehicle_factory", 30, 30)
	_enemy_building("vehicle_factory", 10, 31)
	_see_all()
	_wave(1, AiMemory.SquadState.WAVE)
	_fire(READY)
	_fire(KNOWN)
	assert_int(_shots().size()).is_equal(1)
	_memory.strike_wave = 0


## Runs until a thing first seen at `KNOWN + 15` is old enough; that run's shot stays in `_out`.
func _after_sighting() -> void:
	_fire(KNOWN + 15)
	_memory.strike_wave = 0
	_fire(KNOWN + 15 + REACTION)


## The frozen arena's radar copies carry no `radar` flag (test_radar_dark.gd), so the cases that
## need a radar set it on the World's type table the way the shipped data has it.
func _flag_radars() -> void:
	for id: String in ["fossil_radar", "renew_radar"]:
		_world.type_radar[_world.type_ids.find(StringName(id))] = 1


## Ring A (factory and barracks, 2,200) at CLUSTER_POINT and ring B (the twin factory, 1,800) with
## the radar beside it, the wave in the field, the shot sent once all is old enough.
func _rich_and_radar() -> void:
	_flag_radars()
	_cluster()
	_enemy_building("vehicle_factory", 10, 31)
	_enemy_building("fossil_radar", RADAR_TILE.x, RADAR_TILE.y)
	_see_all()
	_wave(1, AiMemory.SquadState.WAVE)
	_fire(READY)
	_after_sighting()
