class_name MenuStack
extends Control
## The stack of menu screens (ADR 0043 sections 3 and 4). `push`, `pop` and `replace` slide a screen
## for `slide_ms`; with `reduced` (the player's Reduced effects switch) or `slide_ms` 0 they cut.
## A new call while a slide runs finishes that slide first. Screens stay in the tree, so a turn of
## the phone keeps the stack, each screen's scroll and (restored on pop) its focus.
## Back (`NOTIFICATION_WM_GO_BACK_REQUEST`, or `back()`): an open question closes, a screen above
## the root pops, the root asks "Quit Treadline?". `SceneTree.quit_on_go_back` is off while the
## stack is in the tree, or Android's back button would quit before the stack hears it.
## It holds no game rule and sends no Command.

signal screen_changed(screen: MenuScreen)

@export var slide_ms: int = 200
## Handed to every screen as its opaque backdrop (set in menu.tscn).
@export var backdrop_color: Color
## Reduced effects: every change of screen is a cut. The owner sets it (the settings screen, P526).
var reduced: bool = false
## What a yes to the quit question does; tests replace it.
var quit_handler: Callable = _quit_app

var _screens: Array[MenuScreen] = []
var _focus: Dictionary[MenuScreen, Control] = {}
var _quit: ConfirmDialog
var _tween: Tween = null
var _finish: Callable = Callable()
var _quit_on_go_back_before: bool = true


func _enter_tree() -> void:
	_quit_on_go_back_before = get_tree().quit_on_go_back
	get_tree().quit_on_go_back = false


func _exit_tree() -> void:
	get_tree().quit_on_go_back = _quit_on_go_back_before


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_quit = ConfirmDialog.new()
	_quit.name = &"QuitQuestion"
	_quit.question = "QUIT TREADLINE?"
	_quit.detail = "Your progress is saved."
	_quit.yes_text = "QUIT"
	_quit.no_text = "STAY"
	_quit.confirmed.connect(func() -> void: quit_handler.call())
	add_child(_quit)
	_quit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back.call_deferred()  # Never change scenes inside a notification dispatch.


func depth() -> int:
	return _screens.size()


func current() -> MenuScreen:
	return null if _screens.is_empty() else _screens.back()


func is_asking_to_quit() -> bool:
	return _quit.visible


## Puts `screen` on top; the one under it stays, hidden once the slide ends.
func push(screen: MenuScreen) -> void:
	_settle()
	var below: MenuScreen = current()
	_remember_focus(below)
	_add(screen)
	_screens.append(screen)
	_run(screen, below, true, false)


## Removes the top screen (never the root) and shows the one under it. False at the root.
func pop() -> bool:
	_settle()
	if _screens.size() < 2:
		return false
	var gone: MenuScreen = _screens.pop_back()
	var below: MenuScreen = current()
	below.visible = true
	_run(below, gone, false, true)
	return true


## Swaps the top screen for `screen` (the old one is freed); the stack gets no deeper.
func replace(screen: MenuScreen) -> void:
	_settle()
	var old: MenuScreen = current()
	_add(screen)
	if old != null:
		_screens.pop_back()
	_screens.append(screen)
	_run(screen, old, true, true)


## The back request. Always handled: it closes a question, pops, or asks to quit at the root.
func back() -> void:
	if _quit.visible:
		_quit.close()
		return
	_settle()
	var top: MenuScreen = current()
	if top != null and top.on_back():
		return
	if not pop():
		_quit.open()


func _add(screen: MenuScreen) -> void:
	screen.backdrop_color = backdrop_color
	add_child(screen)
	move_child(screen, _quit.get_index())  # The question stays on top of every screen.


func _run(incoming: MenuScreen, outgoing: MenuScreen, forward: bool, free_out: bool) -> void:
	_finish = _end.bind(incoming, outgoing, free_out)
	var moving: MenuScreen = incoming if forward else outgoing
	if reduced or slide_ms <= 0 or outgoing == null or not is_inside_tree():
		_settle()
		return
	var width: float = size.x
	moving.position.x = width if forward else 0.0
	_tween = create_tween()
	_tween.tween_property(moving, "position:x", 0.0 if forward else width, slide_ms / 1000.0)
	_tween.finished.connect(_settle)


func _settle() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	if _finish.is_valid():
		var done: Callable = _finish
		_finish = Callable()
		done.call()


func _end(incoming: MenuScreen, outgoing: MenuScreen, free_out: bool) -> void:
	incoming.position.x = 0.0
	incoming.visible = true
	if outgoing != null and is_instance_valid(outgoing):
		if free_out:
			_focus.erase(outgoing)
			outgoing.queue_free()
		else:
			outgoing.visible = false
			outgoing.position.x = 0.0
	var target: Control = _focus.get(incoming)
	if target != null and is_instance_valid(target) and target.is_visible_in_tree():
		target.grab_focus(true)
	screen_changed.emit(incoming)


func _remember_focus(screen: MenuScreen) -> void:
	if screen == null:
		return
	var owner_control: Control = get_viewport().gui_get_focus_owner()
	if owner_control != null and screen.is_ancestor_of(owner_control):
		_focus[screen] = owner_control


func _quit_app() -> void:
	get_tree().quit()
