class_name FakeAdBackend
extends AdBackend
## The fake ad backend: editor, tests, web preview and every build without the real plugin
## (ADR 0039 section 2). Scriptable: fill or no fill, a load that never answers, a show that never
## opens, a show that never closes, reward granted or not. With `auto_close` a show opens and
## closes in the same call; without it a "Test ad" placeholder is drawn on `host` and the show
## ends when its Close is pressed (or `finish_show` is called). Reaches no network and no plugin.

## Standard anchored banner height; the real backend reports the SDK's own.
const DEFAULT_BANNER_HEIGHT_DP: int = 50

## Scripts for tests. A fill of false answers a load with FAILED at once.
var fill: bool = true
var load_never_answers: bool = false
var show_never_opens: bool = false
var show_never_closes: bool = false
## Whether the rewarded ad earns its reward before it closes.
var grant_reward: bool = true
var banner_height: int = DEFAULT_BANNER_HEIGHT_DP
## Where the placeholders are drawn; none is drawn without one in the tree.
var host: Node = null

var load_requests: Array[StringName] = []
var shows: Array[StringName] = []
var banner_visible: bool = false

var _states: Dictionary = {}
var _showing: StringName = &""
var _opened: bool = false
var _fullscreen_node: CanvasLayer = null
var _banner_node: CanvasLayer = null


func load_state(kind: StringName) -> LoadState:
	return _states.get(kind, LoadState.IDLE)


func request_load(kind: StringName) -> void:
	load_requests.append(kind)
	if load_never_answers:
		_states[kind] = LoadState.LOADING
	else:
		_states[kind] = LoadState.READY if fill else LoadState.FAILED


func show_ad(kind: StringName, auto_close: bool) -> void:
	if load_state(kind) != LoadState.READY:
		return
	_states[kind] = LoadState.IDLE
	shows.append(kind)
	if show_never_opens:
		return
	_showing = kind
	_opened = true
	opened.emit(kind)
	if show_never_closes:
		return
	if auto_close:
		finish_show()
	else:
		_draw_fullscreen()


func cancel_show(kind: StringName) -> void:
	if _showing == kind and not _opened:
		_showing = &""


## The Close press: the reward first when the script grants one, then `closed`.
func finish_show() -> void:
	if _showing == &"" or not _opened:
		return
	var kind: StringName = _showing
	_showing = &""
	_opened = false
	_clear_fullscreen()
	if kind == KIND_REWARDED and grant_reward:
		reward_earned.emit(kind)
	closed.emit(kind)


func show_banner(draw_placeholder: bool) -> void:
	banner_visible = true
	if draw_placeholder and _banner_node == null and _host_ready():
		_banner_node = FakeAdPlaceholders.build_banner(banner_height)
		host.add_child(_banner_node)


func hide_banner() -> void:
	banner_visible = false
	if _banner_node != null:
		_banner_node.queue_free()
		_banner_node = null


func banner_height_dp() -> int:
	return banner_height


func _draw_fullscreen() -> void:
	if _fullscreen_node == null and _host_ready():
		_fullscreen_node = FakeAdPlaceholders.build_fullscreen(finish_show)
		host.add_child(_fullscreen_node)


func _clear_fullscreen() -> void:
	if _fullscreen_node != null:
		_fullscreen_node.queue_free()
		_fullscreen_node = null


func _host_ready() -> bool:
	return host != null and is_instance_valid(host) and host.is_inside_tree()
