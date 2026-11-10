extends RefCounted
## P196 experiment only, never merged: a tick-sampled read of both sides, printed compactly. It only
## reads the World and the controllers (no Command, no draw), so a match plays the same with it.
## One line per sample: `run-sim-smoke: P196 s<seed> t<tick> | <side> | <side>`, a side being
##   u<combat units> i<idle> a<attack-move> m<move> k<attack> w<in the wave> st<wave state H/W/R>
##   c<centre x,y> sp<mean tile distance to centre> far<units over 12 tiles from the centre>
##   nw<joined the wave since last sample> nwd<their mean distance to the wave centre>
##   tg<target tile and what stands there> d<army centre to target, tiles> P<own producers alive>
##   EP<enemy producers alive> kp<sum of the AI's seen_count over producer types> wc<waves launched>
##   L<units lost since last sample> T<of them killed by a turret>.

const SmokeCount: GDScript = preload("res://tests/smoke/smoke_count.gd")
const SAMPLE: int = 300
const FROM: int = 6000
const FAR: int = 12

static var seed_now: int = 0
static var _prev_wave: Array = [{}, {}, {}]
static var _prev_lost: Array[int] = [0, 0, 0]
static var _prev_turret: Array[int] = [0, 0, 0]
## Deaths of a player's combat units since the last sample by zone: enemy turret zone, enemy base,
## field, own base.
static var _deaths: Array = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]


static func reset(match_seed: int) -> void:
	seed_now = match_seed
	_prev_wave = [{}, {}, {}]
	_prev_lost = [0, 0, 0]
	_prev_turret = [0, 0, 0]
	_deaths = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]


static func after(world: World) -> void:
	var events: PackedInt32Array = world.events
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] != World.Event.DIED:
			continue
		var type: int = events[at + 4]
		var owner: int = events[at + 5]
		if owner < 1 or owner > 2 or world.type_foot_w[type] > 0 or world.type_weapon[type] < 0:
			continue
		var x: int = events[at + 2] / 1000
		var y: int = events[at + 3] / 1000
		var zone: int = 2
		var near_enemy: bool = false
		var near_own: bool = false
		for row: int in world.unit_count():
			var other: int = world.type_index[row]
			if world.type_foot_w[other] <= 0 or world.owner[row] <= 0:
				continue
			var gap: int = maxi(absi(world.pos_x[row] / 1000 - x), absi(world.pos_y[row] / 1000 - y))
			if world.owner[row] != owner:
				if gap <= 8 and world.type_weapon[other] >= 0 and world.build_left[row] == 0:
					zone = 0
					break
				if gap <= 10:
					near_enemy = true
			elif gap <= 10:
				near_own = true
		if zone != 0:
			zone = 1 if near_enemy else (3 if near_own else 2)
		_deaths[owner][zone] += 1


static func sample(world: World, controllers: Array[AiController], counter: SmokeCount) -> void:
	if world.tick < FROM or world.tick % SAMPLE != 0:
		return
	var text: String = "run-sim-smoke: P196 s%d t%d" % [seed_now, world.tick]
	for index: int in controllers.size():
		var ai: OpponentAi = controllers[index] as OpponentAi
		if ai == null:
			continue
		text += " | %d %s" % [ai.player_id, _side(world, ai, counter)]
	print(text)


static func _is_producer(world: World, type: int) -> bool:
	return world.type_foot_w[type] > 0 and world.type_produces[type] >= 0 and world.type_produces[type] < 3


static func _side(world: World, ai: OpponentAi, counter: SmokeCount) -> String:
	var player: int = ai.player_id
	var memory: AiMemory = ai.memory
	var ids: Dictionary = {}
	var wave_ids: Dictionary = {}
	var xs: Array[int] = []
	var ys: Array[int] = []
	var wx: int = 0
	var wy: int = 0
	var idle: int = 0
	var amove: int = 0
	var move: int = 0
	var attack: int = 0
	var own_prod: int = 0
	var enemy_prod: int = 0
	var in_wave: int = 0
	for at: int in memory.member_id.size():
		ids[memory.member_id[at]] = memory.member_squad[at]
	for row: int in world.unit_count():
		var type: int = world.type_index[row]
		if world.type_foot_w[type] > 0:
			if _is_producer(world, type):
				if world.owner[row] == player:
					own_prod += 1
				elif world.owner[row] > 0:
					enemy_prod += 1
			continue
		if world.owner[row] != player or world.type_weapon[type] < 0:
			continue
		var id: int = world.unit_id[row]
		xs.append(world.pos_x[row] / 1000)
		ys.append(world.pos_y[row] / 1000)
		match world.order[row]:
			World.Order.IDLE:
				idle += 1
			World.Order.ATTACK_MOVE:
				amove += 1
			World.Order.MOVE:
				move += 1
			_:
				attack += 1
		if ids.get(id, -1) == AiArmy.WAVE and memory.squad_role[AiArmy.WAVE] != AiMemory.NONE:
			wave_ids[id] = Vector2i(world.pos_x[row] / 1000, world.pos_y[row] / 1000)
			in_wave += 1
			wx += world.pos_x[row] / 1000
			wy += world.pos_y[row] / 1000
	var units: int = xs.size()
	var cx: int = 0
	var cy: int = 0
	for index: int in units:
		cx += xs[index]
		cy += ys[index]
	if units > 0:
		cx /= units
		cy /= units
	var spread: int = 0
	var far: int = 0
	for index: int in units:
		var dist: int = absi(xs[index] - cx) + absi(ys[index] - cy)
		spread += dist
		if dist > FAR:
			far += 1
	if units > 0:
		spread /= units
	# The wave centre, and the ones that joined since the last sample.
	var wcx: int = cx
	var wcy: int = cy
	if in_wave > 0:
		wcx = wx / in_wave
		wcy = wy / in_wave
	var joined: int = 0
	var joined_dist: int = 0
	for id: int in wave_ids:
		if not _prev_wave[player].has(id):
			joined += 1
			var tile: Vector2i = wave_ids[id]
			joined_dist += absi(tile.x - wcx) + absi(tile.y - wcy)
	if joined > 0:
		joined_dist /= joined
	_prev_wave[player] = wave_ids
	# The target and what stands there.
	var target: String = "none"
	var dist_to: int = -1
	var front: String = "-"
	if memory.base_x != AiMemory.NONE:
		var kind: String = "empty"
		for row: int in world.unit_count():
			var type: int = world.type_index[row]
			if world.owner[row] == player or world.owner[row] <= 0 or world.type_foot_w[type] <= 0:
				continue
			if absi(world.pos_x[row] / 1000 - memory.base_x) <= 2 and absi(world.pos_y[row] / 1000 - memory.base_y) <= 2:
				kind = String(world.type_ids[type])
				break
		target = "%d,%d:%s" % [memory.base_x, memory.base_y, kind]
		dist_to = absi(wcx - memory.base_x) + absi(wcy - memory.base_y)
		var ds: Array[int] = []
		var mine_near: int = 0
		var foes_near: int = 0
		var guns_near: int = 0
		for row: int in world.unit_count():
			var other: int = world.type_index[row]
			var gap: int = maxi(absi(world.pos_x[row] / 1000 - memory.base_x), absi(world.pos_y[row] / 1000 - memory.base_y))
			if world.owner[row] <= 0 or world.type_weapon[other] < 0:
				continue
			if world.type_foot_w[other] > 0:
				if world.owner[row] != player and gap <= 12 and world.build_left[row] == 0:
					guns_near += 1
				continue
			if world.owner[row] == player:
				if gap <= 12:
					mine_near += 1
				if wave_ids.has(world.unit_id[row]):
					ds.append(gap)
			elif gap <= 12:
				foes_near += 1
		ds.sort()
		if not ds.is_empty():
			front = "%d/%d/%d" % [ds[0], ds[ds.size() / 2], ds[ds.size() - 1]]
		front += " n%d e%d g%d" % [mine_near, foes_near, guns_near]
	var known: int = 0
	for type: int in memory.seen_count.size():
		if type < world.type_ids.size() and _is_producer(world, type):
			known += memory.seen_count[type]
	var state: String = "H"
	if memory.squad_role[AiArmy.WAVE] != AiMemory.NONE:
		state = "R" if memory.squad_state[AiArmy.WAVE] == AiMemory.SquadState.RETREAT else "W"
	var lost: int = world.stat_lost_units[player]
	var turret: int = 0
	var other: int = 3 - player
	for key: String in counter.kills[other]:
		if key.contains("defence"):
			turret += int(counter.kills[other][key])
	var army: AiArmy = ai.army
	var extra: String = (
		" G%d,%d/%d,%d fo%d sg%d rc%d pr%s"
		% [memory.squad_goal_x[1], memory.squad_goal_y[1], memory.staging_x, memory.staging_y, army.retreats, army.focuses, army.recalls, str(army._pressed)]
	)
	var out: String = (
		"u%d i%d a%d m%d k%d w%d %s c%d,%d sp%d far%d nw%d/%d tg%s d%d fq%s P%d EP%d kp%d wc%d L%d T%d D%d/%d/%d/%d"
		% [
			units, idle, amove, move, attack, in_wave, state, cx, cy, spread, far, joined, joined_dist,
			target, dist_to, front, own_prod, enemy_prod, known, ai.waves,
			lost - _prev_lost[player], turret - _prev_turret[player],
			_deaths[player][0], _deaths[player][1], _deaths[player][2], _deaths[player][3],
		]
	)
	out += extra
	_prev_lost[player] = lost
	_prev_turret[player] = turret
	_deaths[player] = [0, 0, 0, 0]
	return out
