class_name UiSounds
extends Node
## The interface sounds of ADR 0041 section 4, on the Ui bus through AudioService: a click on every
## `BaseButton` (hooked through `SceneTree.node_added`, so no HUD or menu file is edited; a button
## with the meta `no_click` is silent; the meta `ui_cue` names another cue: `back`, `confirm`; a
## tap on a disabled button plays `refuse`; the phone's Back button plays `back` through a
## `back_requested` signal on any node, which `MenuStack` has), a chirp when the local player
## gives an order (`CommandQueue.submitted`) and the alert chirp when `AttackCues` raises a cue.
## It reads and plays; it never writes the sim or a Command. The sounds are `UiSoundsDef`'s.
##
## All connections live while the node is in the tree (`_enter_tree` to `_exit_tree`); outside it
## nothing plays.
##
## One sound per action: a click is deferred to the end of the frame and dropped when the local
## player's order arrives in that frame, so a button that issues a Command plays the order chirp
## only (the order chirp wins).

const DEF_PATH: String = "res://data/audio_ui_sounds.tres"
const META_NO_CLICK: StringName = &"no_click"
const CUE_CLICK: StringName = &"ui_click"
const META_CUE: StringName = &"ui_cue"
const SIGNAL_BACK: StringName = &"back_requested"
const CUE_BACK: StringName = &"ui_back"
const CUE_CONFIRM: StringName = &"ui_confirm"
const CUE_REFUSE: StringName = &"ui_refuse"
const CUE_ORDER: StringName = &"ui_order"
const CUE_ALERT: StringName = &"ui_alert"

## False in the menu, where nobody gives orders: the node then ignores the command queue.
@export var chirp_orders: bool = true

## Only this player's orders chirp. The match setup must set it from the scenario's local player;
## while it is -1 no order chirps (one warning at the first order).
var local_player: int = -1
var def: UiSoundsDef
## The sound service and the command queue; null means the autoload of that name. Untyped Node
## because the autoloads declare no class_name. Tests set them before the node enters the tree.
var audio: Node
var queue: Node

var _cues: AttackCues
var _pending: StringName = &""  ## The cue that waits for the end of the frame.
var _warned_unset: bool = false


func _enter_tree() -> void:
	if def == null:
		def = load(DEF_PATH) as UiSoundsDef
		if def == null:
			push_error("UiSounds: cannot load %s; the interface stays silent" % DEF_PATH)
	if audio == null:
		audio = get_node_or_null(^"/root/AudioService")
	if queue == null:
		queue = get_node_or_null(^"/root/CommandQueue")
	if chirp_orders and queue != null and not queue.is_connected(&"submitted", _on_submitted):
		queue.connect(&"submitted", _on_submitted)
	_link_cues(true)
	var tree: SceneTree = get_tree()
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	# Buttons that were in the tree before this node.
	for node: Node in tree.root.find_children("*", "", true, false):
		_on_node_added(node)


func _exit_tree() -> void:
	_pending = &""
	var tree: SceneTree = get_tree()
	if tree != null and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)
	if queue != null and queue.is_connected(&"submitted", _on_submitted):
		queue.disconnect(&"submitted", _on_submitted)
	_link_cues(false)


## Plays the alert chirp whenever `cues` raises a cue (read-only). One cue source at a time.
func connect_attack_cues(cues: AttackCues) -> void:
	_link_cues(false)
	_cues = cues
	_link_cues(is_inside_tree())


func _link_cues(on: bool) -> void:
	if _cues == null:
		return
	var linked: bool = _cues.cue_changed.is_connected(_on_cue_changed)
	if on and not linked:
		_cues.cue_changed.connect(_on_cue_changed)
	elif not on and linked:
		_cues.cue_changed.disconnect(_on_cue_changed)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_hook(node as BaseButton)
	elif node.has_signal(SIGNAL_BACK) and not node.is_connected(SIGNAL_BACK, _on_back):
		node.connect(SIGNAL_BACK, _on_back)


func _hook(button: BaseButton) -> void:
	var callback: Callable = _on_pressed.bind(button)
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)
	var gui: Callable = _on_gui_input.bind(button)
	if not button.gui_input.is_connected(gui):
		button.gui_input.connect(gui)


## The meta is read at the press, so a button may set it after it entered the tree. The cue
## waits for the end of the frame (see the class comment).
func _on_pressed(button: BaseButton) -> void:
	if button.get_meta(META_NO_CLICK, false):
		return
	_queue_cue(StringName(button.get_meta(META_CUE, CUE_CLICK)))


## A press on a disabled button is a refused action. A touch also arrives as an emulated mouse
## press; the one pending slot keeps it to one cue.
func _on_gui_input(event: InputEvent, button: BaseButton) -> void:
	if not button.disabled or button.get_meta(META_NO_CLICK, false):
		return
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if (
		(mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT)
		or (touch != null and touch.pressed)
	):
		_queue_cue(CUE_REFUSE)


func _on_back() -> void:
	_queue_cue(CUE_BACK)


func _queue_cue(cue: StringName) -> void:
	if is_inside_tree() and _pending == &"":
		_pending = cue
		_flush.call_deferred()


func _flush() -> void:
	if _pending == &"" or def == null:
		return
	var cue: StringName = _pending
	_pending = &""
	match cue:
		CUE_BACK:
			_play(def.back_stream, cue, def.back_priority, def.back_db)
		CUE_CONFIRM:
			_play(def.confirm_stream, cue, def.confirm_priority, def.confirm_db)
		CUE_REFUSE:
			_play(def.refuse_stream, cue, def.refuse_priority, def.refuse_db)
		_:
			_play(def.click_stream, CUE_CLICK, def.click_priority, def.click_db)


func _on_submitted(command: Command) -> void:
	if def == null:
		return
	if local_player < 0:
		if not _warned_unset:
			_warned_unset = true
			push_warning("UiSounds: local_player is not set; orders do not chirp")
		return
	if command.player_id == local_player:
		_pending = &""
		_play(def.order_stream, CUE_ORDER, def.order_priority, def.order_db)


## One chirp per `cue_changed` while a cue shows: a new attacked area or a replaced cue chirps
## (AttackCues already throttles per area); a dismissal or an expiry fires the same signal and is
## silent.
func _on_cue_changed() -> void:
	if def != null and _cues != null and _cues.active:
		_play(def.alert_stream, CUE_ALERT, def.alert_priority, def.alert_db)


func _play(stream: AudioStream, cue: StringName, priority: int, volume_db: float) -> void:
	if def != null and audio != null and stream != null:
		audio.call(&"play_ui", stream, cue, priority, def.max_voices, volume_db)
