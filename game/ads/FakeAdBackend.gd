class_name FakeAdBackend
extends AdBackend
## The fake ad backend: editor, tests, web preview and every build without the real plugin
## (ADR 0039 section 2). Scriptable: fill or no fill, a load that never answers, a show that fails,
## never opens (until `open_late`) or never closes, reward granted or not. With `auto_close` a
## show opens and closes in the same call; without it a "Test ad" placeholder is drawn on `host`
## and the show ends when its Close is pressed (or `finish_show` is called). Reaches no network
## and no plugin.

## Standard anchored banner height; the real backend reports the SDK's own.
const DEFAULT_BANNER_HEIGHT_DP: int = 50

## Scripts for tests. A fill of false answers a load with FAILED at once.
var fill: bool = true
var load_never_answers: bool = false
var show_fails: bool = false
var show_never_opens: bool = false
var show_never_closes: bool = false
## A backend that cannot recall a show (AdMob): `cancel_show` does nothing.
var ignore_cancel: bool = false
## Whether the rewarded ad earns its reward, and whether it comes after the close.
var grant_reward: bool = true
var reward_after_close: bool = false
var banner_height: int = DEFAULT_BANNER_HEIGHT_DP
## Fake-only: a show closes at once. Set by AdService from `fake_auto_close`.
var auto_close: bool = true
## Fake-only: draw the "Test ad" placeholders on `host`.
var draw_placeholders: bool = false
## Where the placeholders are drawn; none is drawn without one in the tree.
var host: Node = null

## Fake-only: `push_error` when a load, banner or show runs before `initialize`. AdService sets it.
var strict_order: bool = false
var initializations: int = 0
## Every call in order: "initialize", "load:<kind>", "show:<kind>", "banner", "hide_banner".
var calls: Array[String] = []
var load_requests: Array[StringName] = []
var shows: Array[StringName] = []
var cancels: Array[StringName] = []
var banner_visible: bool = false

var _states: Dictionary[StringName, LoadState] = {}
## The shows asked for and not yet closed, per kind (AdMob holds one per ad object): kind to
## whether it opened.
var _shows: Dictionary[StringName, bool] = {}
var _fullscreen_node: FakeAdPlaceholders = null
var _banner_node: FakeAdPlaceholders = null


func initialize() -> void:
	initializations += 1
	calls.append("initialize")


func load_state(kind: StringName) -> LoadState:
	return _states.get(kind, LoadState.IDLE)


func request_load(kind: StringName) -> void:
	_note("load:" + kind)
	load_requests.append(kind)
	if load_never_answers:
		_states[kind] = LoadState.LOADING
	else:
		_states[kind] = LoadState.READY if fill else LoadState.FAILED


func show_ad(kind: StringName) -> void:
	_note("show:" + kind)
	if load_state(kind) != LoadState.READY:
		return
	_states[kind] = LoadState.IDLE
	shows.append(kind)
	if show_fails:
		show_failed.emit(kind)
		return
	_shows[kind] = false
	if not show_never_opens:
		open_late(kind)


## Opens the pending shows (those of `kind`, or all for an empty one) unless they were cancelled;
## then closes them per the script.
func open_late(kind: StringName = &"") -> void:
	for pending: StringName in _shows.keys():
		if (kind.is_empty() or pending == kind) and not _shows[pending]:
			_open(pending)


func cancel_show(kind: StringName) -> void:
	cancels.append(kind)
	if ignore_cancel:
		return
	if _shows.has(kind) and not _shows[kind]:
		_shows.erase(kind)


## The Close press: the reward first when the script grants one, then `closed`. Closes the open
## ad of `kind`, or every open ad for an empty one.
func finish_show(kind: StringName = &"") -> void:
	for open_kind: StringName in _shows.keys():
		if (kind.is_empty() or open_kind == kind) and _shows[open_kind]:
			_close(open_kind)


func show_banner() -> void:
	_note("banner")
	banner_visible = true
	if fill and draw_placeholders and _banner_node == null and _host_ready():
		_banner_node = FakeAdPlaceholders.build_banner(banner_height)
		host.add_child(_banner_node)


func hide_banner() -> void:
	_note("hide_banner")
	banner_visible = false
	if is_instance_valid(_banner_node):
		_banner_node.queue_free()
	_banner_node = null


func banner_height_dp() -> int:
	return banner_height if fill else 0


func _open(kind: StringName) -> void:
	_shows[kind] = true
	opened.emit(kind)
	if show_never_closes:
		return
	if auto_close:
		_close(kind)
	elif draw_placeholders and _host_ready():
		_draw_fullscreen(kind)
	else:
		# Nothing to draw on (no host in the tree): close as scripted, so a run never waits forever.
		_close(kind)


func _close(kind: StringName) -> void:
	_shows.erase(kind)
	if _shows.values().all(func(opened_now: bool) -> bool: return not opened_now):
		_clear_fullscreen()
	var earns: bool = kind == KIND_REWARDED and grant_reward
	if earns and not reward_after_close:
		reward_earned.emit(kind)
	closed.emit(kind)
	if earns and reward_after_close:
		reward_earned.emit(kind)


func _draw_fullscreen(kind: StringName) -> void:
	if _fullscreen_node == null:
		_fullscreen_node = FakeAdPlaceholders.build_fullscreen(finish_show.bind(kind))
		host.add_child(_fullscreen_node)


func _clear_fullscreen() -> void:
	if is_instance_valid(_fullscreen_node):
		_fullscreen_node.queue_free()
	_fullscreen_node = null


func _host_ready() -> bool:
	return host != null and is_instance_valid(host) and host.is_inside_tree()


func _note(call: String) -> void:
	calls.append(call)
	if strict_order and initializations == 0:
		push_error("FakeAdBackend: %s before initialize (consent gate)" % call)
