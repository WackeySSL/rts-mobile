class_name TutorialDirector
extends Node
## Plays a tutorial lesson's beats (ADR 0044 section 2, plan row P541). Node-side presentation: it
## reads the published snapshot, the selection, `HudState`, the camera and the drawer, and never
## writes the sim and sends no Command (the player's actions go through the controller as always).
## Between prompts it may pause the match the way the pause menu does, `MatchRunner.paused`.
##
## One beat at a time, in the lesson's order: a GAP (`delay_ticks` of match time, and the scripted
## opponent's `after_ai_step` when the beat names one), then SHOWING (the prompt is up and the
## beat's condition, `TutorialConditions`, is checked every frame), then the next beat. The lesson
## ends with `lesson_done` (its id goes into section `tutorial` of `SaveService`) or
## `lesson_skipped`.
##
## What `CoachMark` (P542) and the tutorial screen (P544) use: the signals `beat_shown`,
## `beat_done`, `lesson_done`, `lesson_skipped`; `current` (the beat on show, null in a gap),
## `can_next()`, `next()`, `skip()`, `stalled()`, `progress()` and `running()`; the static
## `lessons_done()`, `is_done()` and `mark_done()`.
##
## Pause: a beat with `pause` holds `runner.paused` from its prompt to its end. The pause menu
## unpauses when it closes, so the director pauses again on the next frame (a held beat stays held);
## it never unpauses while the pause menu is open, and it unpauses only what it paused.
##
## The scripted opponent (`ai`) is read only in `_on_ticked`, after `runner.wait_idle()` (ADR 0038
## section 2): the main thread never reads a controller while a batch runs.

## The prompt of a beat is up (`current` is that beat).
signal beat_shown(beat: TutorialBeatDef)
## A beat's condition held, or the player tapped Next.
signal beat_done(beat: TutorialBeatDef)
## The last beat was done; the lesson is marked done in the save.
signal lesson_done(lesson_id: StringName)
## The lesson was skipped, or a new match began under it. Nothing is saved.
signal lesson_skipped(lesson_id: StringName)

enum Phase { IDLE, GAP, SHOWING }

const SECTION: StringName = &"tutorial"
const KEY_DONE: String = "done"

var runner: MatchRunner
var selection: SelectionModel
var hud: HudState
var camera: RtsCamera
var sidebar: BuildSidebar
var placement: PlacementController
var strike_aim: StrikeAim
## The scripted opponent of the lesson's match, for `after_ai_step` (null: no beat waits for it).
var ai: TutorialAi
## The beat on show; null in a gap and when no lesson runs.
var current: TutorialBeatDef = null
var lesson: TutorialLessonDef = null

var _phase: Phase = Phase.IDLE
var _index: int = 0
var _serial: int = -1
var _gap_from: int = 0
var _shown_at: int = 0
var _gate_open: bool = true
var _holding: bool = false
var _start: TutorialContext = null


## The ids of the lessons the player finished.
static func lessons_done() -> PackedStringArray:
	var saved: Variant = SaveService.get_section(SECTION).get(KEY_DONE, PackedStringArray())
	return saved if saved is PackedStringArray else PackedStringArray()


static func is_done(lesson_id: StringName) -> bool:
	return lessons_done().has(String(lesson_id))


## Records the lesson as done (once). False when the save refused it.
static func mark_done(lesson_id: StringName) -> bool:
	var done: PackedStringArray = lessons_done()
	if done.has(String(lesson_id)):
		return true
	done.append(String(lesson_id))
	return SaveService.set_section(SECTION, {KEY_DONE: done})


## Starts `def` on the running match. A lesson that is running is dropped without a signal.
func start(def: TutorialLessonDef) -> void:
	_stop_quietly()
	lesson = def
	_index = 0
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	_serial = snap.match_serial if snap != null else -1
	_gap_from = snap.tick if snap != null else 0
	if runner != null and not runner.ticked.is_connected(_on_ticked):
		runner.ticked.connect(_on_ticked)
	if def == null or def.beats.is_empty():
		lesson = null
		return
	_enter_gap()


func running() -> bool:
	return _phase != Phase.IDLE


## (beats done, beats in the lesson), for a progress line.
func progress() -> Vector2i:
	return Vector2i(_index, lesson.beats.size() if lesson != null else 0)


## Whether the prompt on show ends by the player's Next (a read-only beat).
func can_next() -> bool:
	return _phase == Phase.SHOWING and current.kind == TutorialConditions.Kind.NEXT


## The player's Next: ends a read-only beat. False when the beat on show asks for an action.
func next() -> bool:
	if not can_next():
		return false
	_complete()
	return true


## Whether the beat on show has run past its budget in match time, so the card may offer more help.
func stalled() -> bool:
	if _phase != Phase.SHOWING or current.budget_s <= 0:
		return false
	return _tick() - _shown_at >= current.budget_s * Sim.TICK_RATE


## Ends the lesson at once: the pause is released and `lesson_skipped` fires.
func skip() -> void:
	if running():
		var id: StringName = lesson.id
		_stop_quietly()
		lesson_skipped.emit(id)


func _process(_delta: float) -> void:
	advance()


## One look at the beat: shows the next prompt when it is due, ends the one on show when its
## condition holds. `_process` calls it each frame; a test calls it directly.
func advance() -> void:
	if not running():
		return
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap != null and snap.match_serial != _serial:
		skip()  # A new match began under the lesson.
		return
	_keep_pause()
	if _phase == Phase.GAP:
		if _gate_open and _tick() - _gap_from >= current_beat().delay_ticks:
			_show()
	elif TutorialConditions.check(current, _gather(), _start):
		_complete()


func current_beat() -> TutorialBeatDef:
	return lesson.beats[_index]


func _tick() -> int:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	return snap.tick if snap != null else 0


## A tick was published: the one moment the scripted opponent may be read (nothing is in flight).
func _on_ticked(_tick_number: int) -> void:
	if _phase != Phase.GAP or _gate_open or ai == null:
		return
	if runner.wait_idle():
		_gate_open = ai.has_fired(current_beat().after_ai_step)


func _enter_gap() -> void:
	_phase = Phase.GAP
	current = null
	_gate_open = current_beat().after_ai_step == &""
	if not _gate_open and ai == null:
		push_warning(
			"TutorialDirector: beat %s waits for the opponent, none is set" % current_beat().id
		)
		_gate_open = true


func _show() -> void:
	_phase = Phase.SHOWING
	current = current_beat()
	_shown_at = _tick()
	_start = _gather()
	if current.pause and runner != null:
		runner.paused = true
		_holding = true
	beat_shown.emit(current)


func _complete() -> void:
	var done: TutorialBeatDef = current
	_release_pause()
	_index += 1
	_gap_from = _tick()
	if _index >= lesson.beats.size():
		var id: StringName = lesson.id
		_stop_quietly()
		mark_done(id)
		beat_done.emit(done)
		lesson_done.emit(id)
		return
	_enter_gap()
	beat_done.emit(done)


func _stop_quietly() -> void:
	_release_pause()
	_phase = Phase.IDLE
	current = null
	lesson = null
	_start = null
	if runner != null and runner.ticked.is_connected(_on_ticked):
		runner.ticked.disconnect(_on_ticked)


## Pauses again after the pause menu's Resume took the match's pause away from a held beat.
func _keep_pause() -> void:
	if _holding and runner != null and not runner.paused and not _pause_menu_open():
		runner.paused = true


func _release_pause() -> void:
	if _holding and runner != null and not _pause_menu_open():
		runner.paused = false
	_holding = false


func _pause_menu_open() -> bool:
	return hud != null and hud.is_open(HudState.Unfold.PAUSE)


## The values the conditions read, from the nodes that were set (a missing one leaves its default).
func _gather() -> TutorialContext:
	var ctx: TutorialContext = TutorialContext.new()
	if runner != null:
		ctx.snapshot = runner.snapshot
		if runner.scenario != null:
			ctx.local_player = runner.scenario.local_player
	ctx.selection = selection
	ctx.hud = hud
	if camera != null:
		ctx.zoom_level = camera.zoom_level_index()
		ctx.camera_centre = camera.position
	if sidebar != null:
		ctx.drawer_tab = sidebar.tab
	if placement != null and placement.active:
		ctx.placement_type = placement.type_index
	if strike_aim != null:
		ctx.strike_aiming = strike_aim.active
		ctx.strike_has_point = strike_aim.has_point
	return ctx
