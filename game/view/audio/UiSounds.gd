class_name UiSounds
extends Node
## The interface sounds of ADR 0041 section 4, on the Ui bus through AudioService: a click on every
## `BaseButton` (hooked through `SceneTree.node_added`, so no HUD or menu file is edited; a button
## with the meta `no_click` is silent), a chirp when the local player gives an order
## (`CommandQueue.submitted`) and the alert chirp when `AttackCues` raises a cue. It reads and
## plays; it never writes the sim or a Command. The sounds are `UiSoundsDef`'s.
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
const CUE_ORDER: StringName = &"ui_order"
const CUE_ALERT: StringName = &"ui_alert"

## Only this player's orders chirp. The match setup must set it from the scenario's local player;
## while it is -1 no order chirps (one warning at the first order).
var local_player: int = -1
var def: UiSoundsDef
## The sound service and the command queue; null means the autoload of that name. Untyped Node
## because the autoloads declare no class_name. Tests set them before the node enters the tree.
var audio: Node
var queue: Node

var _cues: AttackCues
var _click_pending: bool = false
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
	if queue != null and not queue.is_connected(&"submitted", _on_submitted):
		queue.connect(&"submitted", _on_submitted)
	_link_cues(true)
	var tree: SceneTree = get_tree()
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	# Buttons that were in the tree before this node.
	for node: Node in tree.root.find_children("*", "BaseButton", true, false):
		_hook(node as BaseButton)


func _exit_tree() -> void:
	_click_pending = false
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


func _hook(button: BaseButton) -> void:
	var callback: Callable = _on_pressed.bind(button)
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


## The meta is read at the press, so a button may set it after it entered the tree. The click
## waits for the end of the frame (see the class comment).
func _on_pressed(button: BaseButton) -> void:
	if not is_inside_tree() or button.get_meta(META_NO_CLICK, false):
		return
	if not _click_pending:
		_click_pending = true
		_flush_click.call_deferred()


func _flush_click() -> void:
	if _click_pending and def != null:
		_click_pending = false
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
		_click_pending = false
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
