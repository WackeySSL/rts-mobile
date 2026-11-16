class_name UiSounds
extends Node
## The interface sounds of ADR 0041 section 4, on the Ui bus through AudioService: a click on every
## `BaseButton` (hooked through `SceneTree.node_added`, so no HUD or menu file is edited; a button
## with the meta `no_click` is silent), a chirp when the local player gives an order
## (`CommandQueue.submitted`) and the alert chirp when `AttackCues` raises a cue. It reads and
## plays; it never writes the sim or a Command. The sounds are `UiSoundsDef`'s.

const DEF_PATH: String = "res://data/audio_ui_sounds.tres"
const META_NO_CLICK: StringName = &"no_click"
const CUE_CLICK: StringName = &"ui_click"
const CUE_ORDER: StringName = &"ui_order"
const CUE_ALERT: StringName = &"ui_alert"

## Only this player's orders chirp. The match setup sets it from the scenario's local player.
var local_player: int = 1
var def: UiSoundsDef
## The sound service and the command queue; null means the autoload of that name. Tests set them
## before the node enters the tree.
var audio: Node
var queue: Node

var _cues: AttackCues


func _ready() -> void:
	if def == null:
		def = load(DEF_PATH) as UiSoundsDef
	if audio == null:
		audio = get_node_or_null(^"/root/AudioService")
	if queue == null:
		queue = get_node_or_null(^"/root/CommandQueue")
	if queue != null and not queue.is_connected(&"submitted", _on_submitted):
		queue.connect(&"submitted", _on_submitted)
	var tree: SceneTree = get_tree()
	tree.node_added.connect(_on_node_added)
	# Buttons that were in the tree before this node.
	for node: Node in tree.root.find_children("*", "BaseButton", true, false):
		_hook(node as BaseButton)


## Plays the alert chirp whenever `cues` raises a cue (read-only). One cue source at a time.
func connect_attack_cues(cues: AttackCues) -> void:
	if _cues != null and _cues.cue_changed.is_connected(_on_cue_changed):
		_cues.cue_changed.disconnect(_on_cue_changed)
	_cues = cues
	if _cues != null:
		_cues.cue_changed.connect(_on_cue_changed)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_hook(node as BaseButton)


func _hook(button: BaseButton) -> void:
	var callback: Callable = _on_pressed.bind(button)
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


## The meta is read at the press, so a button may set it after it entered the tree.
func _on_pressed(button: BaseButton) -> void:
	if not button.get_meta(META_NO_CLICK, false):
		_play(def.click_stream, CUE_CLICK, def.click_priority, def.click_db)


func _on_submitted(command: Command) -> void:
	if command.player_id == local_player:
		_play(def.order_stream, CUE_ORDER, def.order_priority, def.order_db)


## `cue_changed` also fires when a cue is dismissed or runs out; only a shown cue chirps.
func _on_cue_changed() -> void:
	if _cues != null and _cues.active:
		_play(def.alert_stream, CUE_ALERT, def.alert_priority, def.alert_db)


func _play(stream: AudioStream, cue: StringName, priority: int, volume_db: float) -> void:
	if audio != null and stream != null:
		audio.call(&"play_ui", stream, cue, priority, def.max_voices, volume_db)
