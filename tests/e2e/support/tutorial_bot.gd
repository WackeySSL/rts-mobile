extends RefCounted
## The TutorialBot of plan row P545 (ADR 0044 section 5). Not a test suite.
##
## It plays a tutorial lesson through its real match: the main scene (the real HUD, controller,
## placement, strike aim and camera) seated on the lesson's scenario and seed, the lesson's scripted
## opponent in player 2's seat, a `TutorialDirector` and a `CoachMark` bound to it. For each beat
## the director shows it does what the beat's condition waits for, the way a player would, and
## presses Next on a Next card. The run ends when the director says `lesson_done`, or fails with the
## beat that could not be finished.
##
## What is real: the controls it taps are found by the name the lesson's beats and the authoring
## notes use (`BuildButton`, `TabInfantry`, `Tile_<type>`, `PlaceConfirm`, `StrikeButton`, the
## card's `Next` ...) and must exist, show and be enabled when it taps them, so a renamed or hidden
## HUD control fails the run. Every order a player gives on the map is a TAP gesture through
## `PlayerController.handle_gesture` at the screen point of the ground or the enemy (the placement
## ghost, the move, the harvest, the attack and the strike aim), so the controller decides what the
## tap means: a tap outside a field's reach is a MOVE, and the harvest beat then fails. Every
## Command goes through the controller's sink (the bot keeps a copy to see what a tap sent), and the
## match ticks through `MatchRunner.run_ticks`, with the scripted enemy thinking as in a game.
## What is not a finger, and why it is equivalent:
## - A unit selection sets the selection model's ids, `select_all_army` is the group column's
##   "all army" button's call (a box or a double-tap ends in `selection.set_ids` too).
## - A card tap is `ItemTile.chose` (what its press-and-release emits), a button tap is the
##   button's `pressed` (or `toggled`) signal, a radar tap is the scope's own touch handler fed one
##   press and one release.
## - The camera is moved by `pan_by_screen`, `step_zoom` (what a drag and a pinch end in) and
##   `centre_on` (a player pans the target into view before a tap).
##
## Time is counted in ticks, never measured. `think_ticks` is how long the bot waits after a card
## shows before it acts (a slow player); the card's own pause holds the match, so a paused beat
## does not wait.

const PLAYER: int = 1
## One frame is run every `FRAME_EVERY` ticks, so the HUD, the tweens and the coach mark follow.
const FRAME_EVERY: int = 2
## A beat that is still open after this many ticks of match time has failed. Far above every
## beat's budget: a training or a build waits for the sim, and a fighting beat for the enemy.
const BEAT_CAP_TICKS: int = 3600
## Steps (one per loop, a frame each while the match is held) a beat may take, and steps in a row
## that the match may stay paused: a held beat or an open menu that nothing ends fails by this.
const BEAT_CAP_STEPS: int = 7200
const PAUSED_CAP_STEPS: int = 300
## The whole lesson's cap, a safeguard against a loop that keeps shifting beats.
const LESSON_CAP_TICKS: int = 12000
## How long a card waits for its ring before the bot acts (3 s of match time).
const RING_GRACE_TICKS: int = 45
## Looks a control lead-in step waits for the ring to stand on its control.
const LEAD_LOOKS: int = 30
## The distance in tiles that counts as an enemy at the base.
const CONTACT_TILES: int = 8
## An order that has not done its work is sent again after this many ticks.
const REORDER_TICKS: int = 150
const UNIT_PANS: int = 2  ## Centrings tried before a unit that stays out of the field is told.
const UNIT_WATCH_TICKS: int = 15  ## A unit tap must have passed its step after this long.
## Ticks after the first MOVE of a `move` beat that a bot with `stop_mid_move` taps STOP at.
const STOP_AFTER_TICKS: int = 8
const SELF_PAN: Array[Vector2] = [
	Vector2(-400, 0), Vector2(400, 0), Vector2(0, -400), Vector2(0, 400)
]

## How many ticks the bot waits after a card shows before it acts.
var think_ticks: int = 0
## Set by a test: in a `move` beat the bot taps STOP a few ticks after its first MOVE (the squads
## halt short of the mark, as on Michael's phone) and then sends them again.
var stop_mid_move: bool = false
## Set by a test: the `groups` beat is played with one squad selected, as a player may.
var single_squad_group: bool = false
## Set by a test: a beat that has a selection lead-in starts with nothing selected, as when a player
## has dropped the selection, so the bot follows that step with a real tap on its tile or control.
var drop_selection: bool = false
## How many selection lead-in steps the bot followed (a tap on a tile, or the AllArmy control).
var selection_steps: int = 0
## How many taps the bot made on a unit the ring stood on (a `UNIT` step: lead-in or beat).
var unit_taps: int = 0
## How many STOP commands the bot sent, by tapping the Stop button.
var stops_sent: int = 0

## The tick the STOP goes out at, -1 when none is due.
var _stop_at: int = -1

var _suite: Node
var _main: Node
var _runner: MatchRunner
var _controller: PlayerController
var _camera: RtsCamera
var _placement: PlacementController
var _strike_aim: StrikeAim
var _hud: Node
var _feed: HudStateFeed
var _sidebar: BuildSidebar
var _director: TutorialDirector
var _mark: CoachMark
var _lesson: TutorialLessonDef
var _beat: TutorialBeatDef = null
var _beat_tick: int = 0
var _acted_tick: int = -REORDER_TICKS
var _pan_try: int = 0
var _ticks_run: int = 0
var _failure: String = ""
var _finished: bool = false
var _skipped: bool = false
var _shown: Dictionary[StringName, int] = {}
var _done_at: Dictionary[StringName, int] = {}
var _missing: Array[String] = []
var _ringless: Array[String] = []
var _contact: int = -1
var _ring_noted: bool = false
## The tile step of a selection the bot tapped, to be seen passed on the next look.
var _pending_tile: TutorialLeadInDef = null
var _unit_tapped: Object = null  ## The beat or lead-in step whose unit was tapped (once).
var _unit_tick: int = 0
var _unit_pans: int = 0
var _unit_noted: bool = false
## The lead-in steps of the beat on show that the bot has tapped (each once).
var _led: Array[TutorialLeadInDef] = []
var _lead_looks: int = 0
var _sent: Array[Command] = []
var _beat_steps: int = 0
var _stuck_steps: int = 0
var _last_id: StringName = &""


## `suite` is the node that owns the frames (the test suite); `main` is the main scene, already in
## the tree, its runner given the lesson's scenario, seed and opponent and started.
func _init(suite: Node, main: Node) -> void:
	_suite = suite
	_main = main
	_runner = main.get_node("MatchRunner")
	_controller = main.get_node("PlayerController")
	_camera = main.get_node("Camera")
	_placement = main.get_node("PlacementController")
	_strike_aim = main.get_node("StrikeAim")
	_hud = main.get_node("Hud")
	_feed = _hud.get_node("HudStateFeed")
	_sidebar = _hud.find_child("BuildSidebar", true, false) as BuildSidebar
	_runner.set_process(false)  # The bot ticks the match; real frame time would tick it too.
	_controller.command_sink = _on_command


## The first node of the main scene whose script class is `type_name`.
func _layer_of(type_name: String) -> Node:
	for node: Node in _main.find_children("*", type_name, true, false):
		return node
	return null


## The controller's sink: the bot keeps a copy of what a tap sent, and the queue takes it.
func _on_command(command: Command) -> void:
	_sent.append(command)
	CommandQueue.submit(command)


## Plays `lesson` to its end. The result: `done` (the lesson ended), `skipped`, `failure` (what
## stopped the run, empty when none), `ticks` (match ticks played), `shown` and `done_at` (the tick
## each beat's card showed and ended, by beat id), `missing` (anchor controls that are no node of
## the HUD at all) and `ringless` (control anchors that were not shown when their card showed).
func play(lesson: TutorialLessonDef) -> Dictionary:
	_lesson = lesson
	_director = TutorialDirector.new()
	_director.runner = _runner
	_director.selection = _controller.selection
	_director.hud = _feed.state
	_director.camera = _camera
	_director.sidebar = _sidebar
	_director.placement = _placement
	_director.strike_aim = _strike_aim
	_director.lesson_done.connect(func(_id: StringName) -> void: _finished = true)
	_director.lesson_skipped.connect(func(_id: StringName) -> void: _skipped = true)
	_director.beat_shown.connect(_on_shown)
	_director.beat_done.connect(func(beat: TutorialBeatDef) -> void: _done_at[beat.id] = _tick())
	_mark = CoachMark.new()
	_mark.director = _director
	_mark.hud_root = _hud
	_mark.camera = _camera
	_mark.runner = _runner
	_mark.ground_layer = _layer_of("UnitLayer") as UnitLayer
	_mark.air_layer = _layer_of("AirLayer") as AirLayer
	_hud.add_child(_mark)
	await _suite.get_tree().process_frame
	_director.start(lesson)
	while _failure.is_empty() and not _finished and not _skipped:
		await _step()
	var result: Dictionary = {
		"done": _finished,
		"skipped": _skipped,
		"failure": _failure,
		"ticks": _ticks_run,
		"shown": _shown,
		"done_at": _done_at,
		"missing": _missing,
		"ringless": _ringless,
		"contact": _contact,
		"stops": stops_sent,
		"selection_steps": selection_steps,
		"unit_taps": unit_taps,
		"reduced": _mark.reduced,
	}
	_director.skip()
	_mark.queue_free()
	_director.free()
	return result


func _tick() -> int:
	return _runner.snapshot.tick if _runner.snapshot != null else 0


## One tick of the match (none while the director holds the pause), the director's look, the bot's
## move, and a frame now and then.
func _step() -> void:
	if not is_instance_valid(_runner):
		_failure = "the main scene was freed under the run"
		return
	_beat_steps += 1
	if not _runner.paused:
		_runner.run_ticks(1)
		_ticks_run += 1
		_stuck_steps = 0
	else:
		_stuck_steps += 1
	_director.advance()
	_watch_contact()
	await _move()
	if _ticks_run % FRAME_EVERY == 0 or _runner.paused:
		await _suite.get_tree().process_frame
	if is_instance_valid(_runner):
		_check_ends()


## The first tick an enemy unit stands within `CONTACT_TILES` of one of the player's buildings:
## when a wave reaches the base, for the report on how late a slow player's card comes.
func _watch_contact() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	if _contact >= 0 or snap == null or snap.tick % 15 != 0:
		return
	for row: int in snap.unit_count():
		if (
			snap.owner[row] == PLAYER
			or snap.owner[row] == 0
			or snap.type_foot_w[snap.type_index[row]] > 0
		):
			continue
		for other: int in snap.unit_count():
			if snap.owner[other] != PLAYER or snap.type_foot_w[snap.type_index[other]] == 0:
				continue
			var d: int = maxi(
				absi(snap.pos_x[row] - snap.pos_x[other]), absi(snap.pos_y[row] - snap.pos_y[other])
			)
			if d <= CONTACT_TILES * Sim.MILLI_PER_TILE:
				_contact = snap.tick
				return


func _check_ends() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	if snap != null and snap.match_end_tick > 0 and not _finished:
		_failure = "the match ended (winner %d) before the lesson did" % snap.winner
	elif _ticks_run > LESSON_CAP_TICKS:
		_failure = "the lesson is over %d ticks long" % LESSON_CAP_TICKS
	elif _stuck_steps > PAUSED_CAP_STEPS:
		_failure = (
			"the match stayed paused for %d steps at beat '%s' (a held card or an open menu)"
			% [PAUSED_CAP_STEPS, _where()]
		)
	elif _beat_steps > BEAT_CAP_STEPS:
		_failure = "beat '%s' took more than %d steps" % [_where(), BEAT_CAP_STEPS]
	elif _beat != null and _ticks_run - _beat_tick > BEAT_CAP_TICKS and not _runner.paused:
		_failure = (
			"beat '%s' (kind %d) is not done after %d ticks"
			% [_where(), _beat.kind, BEAT_CAP_TICKS]
		)


## The bot's turn: notices a new card and does what it asks.
func _move() -> void:
	var beat: TutorialBeatDef = _director.current
	if beat == null:
		_beat = null
		# The pause menu of a "pause" beat stands open and holds the match: the next card waits for
		# the match to run, so a player closes the menu, and the bot taps Resume.
		if _feed.state.is_open(HudState.Unfold.PAUSE):
			_press(&"ResumeButton")
		return
	if beat != _beat:
		_beat = beat
		_last_id = beat.id
		_beat_steps = 0
		_beat_tick = _ticks_run
		_shown[beat.id] = _tick()
		_acted_tick = -REORDER_TICKS
		_ring_noted = false
		_led.clear()
		_lead_looks = 0
		_pending_tile = null
		_unit_tapped = null
		_unit_pans = 0
		_unit_noted = false
		_note_missing(beat)
		if drop_selection and _selection_lead(beat) != null:
			_controller.selection.clear()
			return  # The director looks at the empty selection before the bot acts.
	var waited: int = _ticks_run - _beat_tick
	_watch_unit(beat)
	var thinking: bool = waited < think_ticks and not _runner.paused
	if thinking or _lead_unit(beat) or _tap_lead_in(beat) or not _ring_settled(beat, waited):
		return
	if (
		_stop_at >= 0
		and _ticks_run >= _stop_at
		and beat.kind == TutorialConditions.Kind.UNITS_IN_AREA
	):
		_tap_stop(beat)
		return
	if beat.kind == TutorialConditions.Kind.NEXT:
		_press_button(_mark.find_child("Next", true, false) as BaseButton, "the card's Next")
		return
	if beat.anchor == TutorialBeatDef.Anchor.UNIT:
		_tap_unit(beat)
		return
	await _act(beat)


## Follows the ring through the beat's lead-ins (ADR 0048 section 5, P593): while the active step
## is not yet tapped, a control step is tapped on `mark.target_control()` (what the ring stands on,
## as a finger would) and a tile step with a SELECTED condition by a TAP gesture on the tile through
## the controller, as a player picks the unit there. Returns true when it tapped. A ring on another
## control than the step names, and a tile tap that did not pass the step, are told in `ringless`.
func _tap_lead_in(beat: TutorialBeatDef) -> bool:
	var step: TutorialLeadInDef = _director.active_target()
	if _pending_tile != null:
		if step == _pending_tile:
			_ringless.append("%s: a tap on tile %s did not select" % [beat.id, step.anchor_tile])
		_pending_tile = null
	if step == null or not beat.lead_in.has(step) or _led.has(step):
		return false
	if step.anchor == TutorialBeatDef.Anchor.CONTROL and _lead_looks < LEAD_LOOKS:
		var seen: Control = _mark.target_control()
		if seen == null or seen.name != step.anchor_control:
			_lead_looks += 1  # The mark looks again every few frames: give it time.
			return true
	_led.append(step)
	_lead_looks = 0
	if step.anchor == TutorialBeatDef.Anchor.TILE:
		if step.kind != TutorialConditions.Kind.SELECTED:
			return false
		_pending_tile = step
		selection_steps += 1
		_tap_ground(Vector2i(step.anchor_tile.x * 1000 + 500, step.anchor_tile.y * 1000 + 500))
		return true
	var target: Control = _mark.target_control()
	if target == null or target.name != step.anchor_control:
		_ringless.append("%s: lead-in %s (ring on %s)" % [beat.id, step.anchor_control, target])
		return false
	if step.kind == TutorialConditions.Kind.SELECTED:
		selection_steps += 1
	_press_button(target as BaseButton, String(step.anchor_control))
	return true


## A lead-in on a unit (ADR 0048 section 13.7): panned to and tapped through `_tap_unit`. True while
## the active step is one that is not tapped yet.
func _lead_unit(beat: TutorialBeatDef) -> bool:
	var step: TutorialLeadInDef = _director.active_target()
	if step == null or step.anchor != TutorialBeatDef.Anchor.UNIT or _led.has(step):
		return false
	if not beat.lead_in.has(step):
		return false
	if _tap_unit(step):
		_led.append(step)
		selection_steps += int(step.kind == TutorialConditions.Kind.SELECTED)
	return true


## The beat's lead-in of kind SELECTED, null when it has none.
func _selection_lead(beat: TutorialBeatDef) -> TutorialLeadInDef:
	for step: TutorialLeadInDef in beat.lead_in:
		if step.kind == TutorialConditions.Kind.SELECTED:
			return step
	return null


## A control anchor must be a node of the HUD at all (`missing`).
func _note_missing(beat: TutorialBeatDef) -> void:
	if beat.anchor == TutorialBeatDef.Anchor.CONTROL and _control(beat.anchor_control) == null:
		_missing.append("%s: %s" % [beat.id, beat.anchor_control])


## Whether the bot may act: a card whose ring is not on its control yet waits for it, up to
## `RING_GRACE_TICKS` (the mark looks again every `CoachMark.FIND_EVERY` frames, and the command
## bar takes a frame to show what a selection made); a ring that never comes is told in `ringless`.
func _ring_settled(beat: TutorialBeatDef, waited: int) -> bool:
	if beat.anchor != TutorialBeatDef.Anchor.CONTROL or _ring_noted:
		return true
	if _control(beat.anchor_control) == null or _mark.target_control() != null:
		_ring_noted = true
		return true
	if waited < RING_GRACE_TICKS and not _runner.paused:
		return false
	_ring_noted = true
	var control: Control = _control(beat.anchor_control)
	(
		_ringless
		. append(
			(
				"%s: %s (visible %s, shown in tree %s, drawer %s)"
				% [
					beat.id,
					beat.anchor_control,
					control.visible,
					control.is_visible_in_tree(),
					_feed.state.is_open(HudState.Unfold.DRAWER),
				]
			)
		)
	)
	return true


# ------------------------------------------------------------------ what each kind asks


func _act(beat: TutorialBeatDef) -> void:
	match beat.kind:
		TutorialConditions.Kind.SELECTED:
			_select(beat.type_id)
		TutorialConditions.Kind.UNITS_IN_AREA:
			_go_to_area(beat)
		TutorialConditions.Kind.BUILDING_PLACED, TutorialConditions.Kind.BUILDING_DONE:
			await _build(beat.type_id, false)
		TutorialConditions.Kind.PLACING:
			await _build(beat.type_id, true)
		TutorialConditions.Kind.OWN_AT_LEAST:
			await _train(beat.type_id, beat.count)
		TutorialConditions.Kind.HARVESTED:
			_harvest()
		TutorialConditions.Kind.ENEMY_LOSSES, TutorialConditions.Kind.MATCH_WON:
			_attack()
		TutorialConditions.Kind.ZOOM_LEVEL:
			await _zoom(beat.value)
		TutorialConditions.Kind.CAMERA_PANNED:
			_pan()
		TutorialConditions.Kind.UNFOLD_OPEN:
			await _unfold(beat.value)
		TutorialConditions.Kind.UNFOLD_CLOSED:
			_press(&"ResumeButton")  # The card asks for Resume.
		TutorialConditions.Kind.DRAWER_TAB:
			await _drawer_tab(beat.value)
		TutorialConditions.Kind.GROUP_SAVED:
			await _save_group(beat.value)
		TutorialConditions.Kind.STRIKE_AIMED:
			await _aim()
		TutorialConditions.Kind.STRIKE_PENDING:
			await _fire()
		_:
			_failure = "beat '%s': the bot has no action for kind %d" % [beat.id, beat.kind]


## Selects every own unit of `type_id`, or the first of its buildings (a tap picks one).
func _select(type_id: StringName) -> void:
	var ids: PackedInt32Array = _own_ids(type_id)
	if ids.is_empty():
		_failure = "beat '%s': no own %s to select" % [_where(), type_id]
		return
	var snap: MatchSnapshot = _runner.snapshot
	if snap.type_foot_w[snap.type_ids.find(type_id)] > 0:
		ids = PackedInt32Array([ids[0]])  # A tap picks one building.
	_controller.selection.set_ids(ids)


## Selects the units of the beat's type and sends them to the middle of its area, again when they
## have not got there after a while.
func _go_to_area(beat: TutorialBeatDef) -> void:
	if not _due():
		return
	var ids: PackedInt32Array = _own_unit_ids(beat.type_id)
	if ids.size() < beat.count:
		_failure = (
			"beat '%s': %d own %s, the beat asks for %d"
			% [beat.id, ids.size(), beat.type_id, beat.count]
		)
		return
	# A tap on bare ground of the area: the middle first, then the tiles round it. A tap that
	# lands on one of the own units selects it instead (nothing is sent), so the squads are
	# selected again for the next tile.
	var middle: Vector2i = beat.area.position * 2 + beat.area.size  # twice the centre, tiles
	var tiles: Array[Vector2i] = [middle * (Sim.MILLI_PER_TILE / 2)]
	for dy: int in beat.area.size.y:
		for dx: int in beat.area.size.x:
			var tile: Vector2i = beat.area.position + Vector2i(dx, dy)
			tiles.append(tile * Sim.MILLI_PER_TILE + Vector2i.ONE * (Sim.MILLI_PER_TILE / 2))
	for at: Vector2i in tiles:
		_controller.selection.set_ids(ids)
		var before: int = _sent.size()
		_tap_ground(at)
		if _sent.size() > before and _sent[-1].type == Command.Type.MOVE:
			if stop_mid_move and stops_sent == 0 and _stop_at < 0:
				_stop_at = _ticks_run + STOP_AFTER_TICKS
			return
	_failure = "beat '%s': no tap on its area sends a MOVE" % beat.id


## Taps the Stop button with the squads selected, and lets the next step send them again.
func _tap_stop(beat: TutorialBeatDef) -> void:
	_stop_at = -1
	_controller.selection.set_ids(_own_unit_ids(beat.type_id))
	var before: int = _sent.size()
	_press(&"Stop")
	if _sent.size() > before and _sent[-1].type == Command.Type.STOP:
		stops_sent += 1
	_acted_tick = -REORDER_TICKS  # The MOVE goes out again at the next step.


## Selects the own tankers and taps the ground at the beat's tile, as a player does: the controller
## decides whether that is a HARVEST (ore within `harvest_pick_milli`) or a MOVE.
func _harvest() -> void:
	if not _due():
		return
	_tap_field(_beat)


## Taps the beat's tile with the tankers selected; the tap must send a HARVEST, and the run fails
## with the beat's id when it sends a MOVE (the tile is out of the ore's reach: a player cannot
## finish the beat either).
func _tap_field(beat: TutorialBeatDef) -> void:
	var ids: PackedInt32Array = PackedInt32Array()
	var snap: MatchSnapshot = _runner.snapshot
	for row: int in snap.unit_count():
		var type: int = snap.type_index[row]
		if (
			snap.owner[row] == PLAYER
			and snap.type_harvest[type] > 0
			and snap.type_foot_w[type] == 0
		):
			ids.append(snap.unit_id[row])
	if ids.is_empty():
		_failure = "beat '%s': no own harvester" % beat.id
		return
	_controller.selection.set_ids(ids)
	var before: int = _sent.size()
	_tap_ground(beat.anchor_tile * Sim.MILLI_PER_TILE + Vector2i.ONE * (Sim.MILLI_PER_TILE / 2))
	if _sent.size() == before or _sent[-1].type != Command.Type.HARVEST:
		_failure = (
			"beat '%s': a tap at its tile %s does not send a HARVEST (sent %s)"
			% [beat.id, beat.anchor_tile, "nothing" if _sent.size() == before else _sent[-1].type]
		)


## A card showed: the harvest beat is tried at once, so that a beat the sim satisfies by itself
## (the tanker already works) still has its tap checked.
func _on_shown(beat: TutorialBeatDef) -> void:
	if beat.kind == TutorialConditions.Kind.HARVESTED:
		_tap_field(beat)


## Selects the whole army, then taps the nearest enemy (the view first panned onto it): the
## controller sends the ATTACK of the units that can hit it.
func _attack() -> void:
	if not _due():
		return
	var snap: MatchSnapshot = _runner.snapshot
	_controller.select_all_army()
	var army: PackedInt32Array = _controller.selection.selected
	if army.is_empty():
		_failure = "beat '%s': no army left to attack with" % _where()
		return
	var goal: Vector2i = _enemy_point(snap, army[0])
	if goal.x < 0:
		_failure = "beat '%s': no enemy to attack" % _where()
		return
	_tap_ground(goal)


## ADR 0048 section 13.7: a unit the ring stands on is panned into the field when it is not in it,
## then tapped once (`owner` is the beat or lead-in step, never tapped twice, so a selected unit is
## not tapped inside the double-tap window) at `unit_anchor().point` as a finger would. True when it
## tapped; false with no unit (the card alone) or while it pans. A unit still out of the field after
## `UNIT_PANS` centrings, and an `attack` tap that sent no ATTACK on that unit, are told in
## `ringless`.
func _tap_unit(owner: Object) -> bool:
	var unit: GuideUnitAnchor = _mark.unit_anchor()
	if _unit_tapped == owner or unit.unit_id < 0:
		return false
	if not unit.in_field:
		_unit_pans += 1
		if _unit_pans > UNIT_PANS:
			_note_unit("unit %d is not in the field after centring" % unit.unit_id)
			return false
		_camera.centre_on(_camera.screen_to_world(unit.point))
		_camera.force_update_scroll()
		return false
	var before: int = _sent.size()
	var tap: GestureEvent = GestureEvent.new()
	tap.kind = GestureEvent.Kind.TAP
	tap.position = unit.point
	_controller.handle_gesture(tap)
	_unit_tapped = owner
	_unit_tick = _ticks_run
	unit_taps += 1
	if _director.current.kind == TutorialConditions.Kind.ENEMY_LOSSES:
		var sent: Command = _sent[-1] if _sent.size() > before else null
		if sent == null or sent.type != Command.Type.ATTACK or sent.target_id != unit.unit_id:
			_note_unit("the tap sent no ATTACK on unit %d" % unit.unit_id)
	return true


## Tells `text` of the current beat once in `ringless`.
func _note_unit(text: String) -> void:
	if not _unit_noted:
		_unit_noted = true
		_ringless.append("%s: %s" % [_where(), text])


## A unit tap that has not passed its step after `UNIT_WATCH_TICKS` is told in `ringless`; an
## attack beat is exempt, since it ends on kills.
func _watch_unit(beat: TutorialBeatDef) -> void:
	if _unit_tapped == null or _unit_noted or _ticks_run - _unit_tick < UNIT_WATCH_TICKS:
		return
	if beat.kind == TutorialConditions.Kind.ENEMY_LOSSES:
		return  # An attack ends on kills, which take time: the ATTACK it sent is the proof.
	var pending: bool = _unit_tapped == beat or _director.active_target() == _unit_tapped
	if pending:
		_note_unit("the tap on unit %d did not pass" % _mark.unit_anchor().unit_id)


## One TAP gesture on the ground point `ground` (milli-tiles): the view is panned onto it first.
func _tap_ground(ground: Vector2i) -> void:
	var at: Vector2 = IsoProjection.ground_to_px(ground.x, ground.y)
	_camera.centre_on(at)
	_camera.force_update_scroll()  # The pick reads the canvas transform the camera sets.
	var tap: GestureEvent = GestureEvent.new()
	tap.kind = GestureEvent.Kind.TAP
	tap.position = _camera.world_to_screen(at)
	_controller.handle_gesture(tap)


## One step of the zoom toward `level`, sent again only after `REORDER_TICKS` (the snap is a
## tween of real time that the frames of the loop play; the director sees the new level).
func _zoom(level: int) -> void:
	if _camera.zoom_level_index() == level or not _due():
		return
	var up: int = 1 if _camera.zoom_level_index() < level else -1
	_camera.step_zoom(up, _camera.get_viewport_rect().size * 0.5)


## One pan of the view by a finger's 400 px; the next try goes the other way when the map's edge
## held the camera back.
func _pan() -> void:
	if not _due():
		return
	_camera.pan_by_screen(SELF_PAN[_pan_try % SELF_PAN.size()])
	_pan_try += 1


## Taps the radar to open the full map, or the menu button to open the pause menu.
func _unfold(which: int) -> void:
	if _feed.state.current == which:
		return
	match which:
		HudState.Unfold.RADAR:
			var scope: Control = _need(&"RadarScope")
			if scope != null:
				_tap_scope(scope)
		HudState.Unfold.PAUSE:
			_press(&"Menu")
		HudState.Unfold.DRAWER:
			await _open_drawer()
		_:
			_failure = "beat '%s': the bot cannot open unfold %d" % [_where(), which]
	await _suite.get_tree().process_frame


## One press and one release of a finger on the scope, through its own touch handler.
func _tap_scope(scope: Control) -> void:
	for pressed: bool in [true, false]:
		var touch: InputEventScreenTouch = InputEventScreenTouch.new()
		touch.index = 0
		touch.pressed = pressed
		touch.position = scope.size * 0.5
		scope._gui_input(touch)


func _drawer_tab(tab: int) -> void:
	await _open_drawer()
	await _open_tab(tab)


## Selects squads and taps the plus of the group column.
func _save_group(slot: int) -> void:
	if not _due():
		return
	_controller.select_all_army()
	if single_squad_group:
		var ids: PackedInt32Array = _own_unit_ids(&"rifle_squad")
		if not ids.is_empty():
			_controller.selection.set_ids(PackedInt32Array([ids[0]]))
	if not _controller.units_selected():
		_failure = "beat '%s': no squads to save as group %d" % [_where(), slot]
		return
	await _suite.get_tree().process_frame
	_press(&"AddGroup")


## Taps the strike button, then puts the aim on the enemy.
func _aim() -> void:
	if not _strike_aim.active:
		if not _due():
			return
		_press(&"StrikeButton")
		await _suite.get_tree().process_frame
	if _strike_aim.active and not _strike_aim.has_point:
		var snap: MatchSnapshot = _runner.snapshot
		var goal: Vector2i = _enemy_point(snap, -1)
		if goal.x < 0:
			_failure = "beat '%s': no enemy to aim at" % _where()
			return
		_tap_ground(goal)  # The controller hands the tap to the aim.


## Taps the check mark of the aim.
func _fire() -> void:
	if _strike_aim.active and _strike_aim.has_point:
		_press(&"StrikeConfirm")
		await _suite.get_tree().process_frame


# ------------------------------------------------------------------ building and training


## Builds one structure of `type_id`: BUILD, the tab, the card (queue it, then place it when it is
## Ready), the ghost on a free tile and the check mark. With `stop_at_ghost` it ends when the ghost
## stands. Nothing to do once a building of the type stands (or its site).
func _build(type_id: StringName, stop_at_ghost: bool) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var type: int = snap.type_ids.find(type_id)
	if type < 0:
		_failure = "beat '%s': %s is no type of the match" % [_where(), type_id]
		return
	if _placement.active and _placement.type_index == type:
		if stop_at_ghost:
			return
		await _place_ghost()
		return
	if _own_ids(type_id).size() > 0 and not _placement.active:
		return  # The site stands, or the building: the sim builds it.
	await _open_drawer()
	await _open_tab(snap.type_tab[type])
	var tile: ItemTile = _tile(type_id)
	if tile == null:
		return
	match tile.state:
		ItemTile.State.AVAILABLE:
			if tile.queued == 0 and _due():
				tile.chose.emit()
		ItemTile.State.READY:
			tile.chose.emit()  # Begins the placement and folds the drawer.
			await _suite.get_tree().process_frame
			if not stop_at_ghost:
				await _place_ghost()


## Finds a tile the footprint fits on, near the first own building, and taps the check mark.
func _place_ghost() -> void:
	if not _placement.active:
		return
	if not _placement.pending and not _placement.fits():
		_move_ghost_to_free_tile()
	if _placement.can_confirm():
		_press(&"PlaceConfirm")
		await _suite.get_tree().process_frame
	elif not _placement.pending and not _placement.fits():
		_failure = (
			"beat '%s': no tile near the base where %s fits"
			% [_where(), _lesson_type_name(_placement.type_index)]
		)


func _move_ghost_to_free_tile() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var base: Vector2i = Vector2i(-1, -1)
	for row: int in snap.unit_count():
		if snap.owner[row] == PLAYER and snap.type_foot_w[snap.type_index[row]] > 0:
			base = Vector2i(
				snap.pos_x[row] / Sim.MILLI_PER_TILE, snap.pos_y[row] / Sim.MILLI_PER_TILE
			)
			break
	if base.x < 0:
		return
	for ring: int in range(2, 12):
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var tap: GestureEvent = GestureEvent.new()
				tap.kind = GestureEvent.Kind.TAP
				tap.position = _camera.world_to_screen(
					IsoProjection.cell_centre_px(base.x + dx, base.y + dy)
				)
				_controller.handle_gesture(tap)
				if _placement.fits():
					return


## Queues units of `type_id` until `count` of them stand or are queued.
func _train(type_id: StringName, count: int) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var type: int = snap.type_ids.find(type_id)
	if type < 0:
		_failure = "beat '%s': %s is no type of the match" % [_where(), type_id]
		return
	await _open_drawer()
	await _open_tab(snap.type_tab[type])
	var tile: ItemTile = _tile(type_id)
	if tile == null:
		return
	if _own_ids(type_id).size() + tile.queued >= count:
		return
	if tile.state == ItemTile.State.AVAILABLE:
		tile.chose.emit()


func _open_drawer() -> void:
	if _feed.state.is_open(HudState.Unfold.DRAWER):
		return
	_press(&"BuildButton")
	await _suite.get_tree().process_frame


func _open_tab(tab: int) -> void:
	if _sidebar.tab == tab and _feed.state.is_open(HudState.Unfold.DRAWER):
		return
	if tab < 0 or tab >= BuildSidebar.TAB_NAMES.size():
		_failure = "beat '%s': tab %d is none" % [_where(), tab]
		return
	_press(StringName("Tab" + BuildSidebar.TAB_NAMES[tab]))
	await _suite.get_tree().process_frame


# ------------------------------------------------------------------ the HUD and the snapshot


## The HUD control called `node_name`, null when there is none (the run fails: a renamed control).
func _control(node_name: StringName) -> Control:
	return _hud.find_child(String(node_name), true, false) as Control


## The control, which must be shown; a miss is the run's failure.
func _need(node_name: StringName) -> Control:
	var found: Control = _control(node_name)
	if found == null:
		_failure = "beat '%s': the HUD has no control named %s" % [_where(), node_name]
		return null
	if not found.is_visible_in_tree():
		_failure = "beat '%s': the control %s is not shown" % [_where(), node_name]
		return null
	return found


## Taps a button: its toggle when something listens to that, its `pressed` otherwise.
func _press(node_name: StringName) -> void:
	var button: BaseButton = _need(node_name) as BaseButton
	if button == null and _failure.is_empty():
		_failure = "beat '%s': %s is no button" % [_where(), node_name]
	_press_button(button, String(node_name))


func _press_button(button: BaseButton, label: String) -> void:
	if button == null or not _failure.is_empty():
		if _failure.is_empty():
			_failure = "beat '%s': %s is not there" % [_where(), label]
		return
	if not button.is_visible_in_tree():
		_failure = "beat '%s': %s is not shown" % [_where(), label]
		return
	if button.disabled:
		_failure = "beat '%s': %s is disabled" % [_where(), label]
		return
	if button.toggle_mode and not button.toggled.get_connections().is_empty():
		button.button_pressed = not button.button_pressed
	else:
		button.pressed.emit()


## The card `Tile_<type>` of the drawer; the run fails when there is none.
func _tile(type_id: StringName) -> ItemTile:
	var found: ItemTile = _sidebar.find_child("Tile_%s" % type_id, true, false) as ItemTile
	if found == null:
		_failure = "beat '%s': the drawer has no card Tile_%s" % [_where(), type_id]
		return null
	if not found.is_visible_in_tree():
		_failure = "beat '%s': the card Tile_%s is not shown on its tab" % [_where(), type_id]
		return null
	return found


## Whether an order that repeats may go out now (every `REORDER_TICKS`).
func _due() -> bool:
	if _ticks_run - _acted_tick < REORDER_TICKS:
		return false
	_acted_tick = _ticks_run
	return true


## The ids of the player's rows of `type_id`, units and buildings.
func _own_ids(type_id: StringName) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	var snap: MatchSnapshot = _runner.snapshot
	var type: int = snap.type_ids.find(type_id)
	for row: int in snap.unit_count():
		if snap.owner[row] == PLAYER and snap.type_index[row] == type:
			ids.append(snap.unit_id[row])
	return ids


func _own_unit_ids(type_id: StringName) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	var snap: MatchSnapshot = _runner.snapshot
	var type: int = snap.type_ids.find(type_id)
	if type >= 0 and snap.type_foot_w[type] == 0:
		ids = _own_ids(type_id)
	return ids


## The ground point (milli-tiles) of the enemy row nearest the row `near` (the first enemy when -1),
## (-1, -1) when none stands.
func _enemy_point(snap: MatchSnapshot, near: int) -> Vector2i:
	var from: int = snap.index_of(near) if near >= 0 else -1
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = -1
	for row: int in snap.unit_count():
		if snap.owner[row] == PLAYER or snap.owner[row] == 0 or snap.hp[row] <= 0:
			continue
		var d: int = 0
		if from >= 0:
			d = absi(snap.pos_x[row] - snap.pos_x[from]) + absi(snap.pos_y[row] - snap.pos_y[from])
		if best_d < 0 or d < best_d:
			best_d = d
			best = Vector2i(snap.pos_x[row], snap.pos_y[row])
	return best


func _lesson_type_name(type: int) -> String:
	var snap: MatchSnapshot = _runner.snapshot
	return String(snap.type_ids[type]) if type >= 0 and type < snap.type_ids.size() else "?"


## Where the run is, for a failure line.
func _where() -> String:
	if _beat != null:
		return String(_beat.id)
	return "after %s" % _last_id if _last_id != &"" else "(before the first beat)"
